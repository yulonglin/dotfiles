// Regression check for the review queue's checklist: node artifacts/pr-review-queue/checklist-test.js
//
// The published page cannot be opened from a session, so the three things that
// broke are pinned here instead. It runs the page's own script text against a
// stub DOM and a stub db capability -- no browser, no network.
//
//   1. a tick made before the db handle resolves survives the first delivery
//      and reaches the store (the handle arrives asynchronously, so a toggle
//      can land while it is still null)
//   2. a stored document repaints the ticks (the load path must read
//      snapshot.data(), not the snapshot object's own fields)
//   3. the ticks leave with the copy, as plain text
//
// Exit code is the result; every failure prints what it expected.

const fs = require("fs");
const path = require("path");

const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
if (blocks.length !== 2) bail("expected 2 script blocks in index.html, found " + blocks.length);

let failures = 0;
function bail(m) { console.error("FAIL: " + m); process.exit(1); }
function check(ok, m) { if (ok) { console.log("  ok   " + m); } else { failures++; console.error("  FAIL " + m); } }

// ---- stub DOM ------------------------------------------------------------
function El(tag) {
  this.tag = tag; this.children = []; this.className = ""; this.textContent = "";
  this.attrs = {}; this.checked = false; this.listeners = {};
  // real datasets stringify on assignment, and the paint path looks rows up by
  // that value, so the stub must stringify too
  this.dataset = new Proxy({}, { set: (t, k, v) => { t[k] = String(v); return true; } });
}
El.prototype.append = function () { for (const c of arguments) this.children.push(c); };
El.prototype.setAttribute = function (k, v) { this.attrs[k] = v; };
El.prototype.addEventListener = function (k, f) { (this.listeners[k] = this.listeners[k] || []).push(f); };
El.prototype.walk = function (out) { out = out || []; for (const c of this.children) { out.push(c); c.walk(out); } return out; };
El.prototype.querySelector = function (sel) { return this.walk().find((e) => e.tag === sel); };
Object.defineProperty(El.prototype, "classList", { get() {
  const self = this;
  return { toggle(c, on) {
    const set = new Set(self.className.split(" ").filter(Boolean));
    on ? set.add(c) : set.delete(c);
    self.className = [...set].join(" ");
  } };
} });

const root = new El("root"), byId = {};
for (const id of ["group-quick", "group-code", "group-call", "group-other", "group-stale", "c-done", "sync"]) {
  byId[id] = new El("ul"); root.append(byId[id]);
}

let snapshotCb = null, writes = [];
// The real capability resolves over the network, so the handle is handed over
// on demand here: until handOverDb() runs, the page's store is null and any
// tick in that window is the race this file exists to pin.
let handOverDb = null;
const dbHandle = {
  doc: (p) => ({ path: p,
    onSnapshot: (next) => { snapshotCb = next; return () => {}; },
    set: async (d) => { writes.push(d); } })
};
const sandbox = {
  console,
  setTimeout,
  document: {
    title: "Dotfiles Review Queue",
    getElementById: (id) => byId[id],
    createElement: (t) => new El(t),
    querySelectorAll: (sel) => {
      if (sel !== "li.row") bail("unexpected selector " + sel);
      return root.walk().filter((e) => e.tag === "li" && e.className.split(" ").includes("row"));
    }
  },
  window: { claude: { use: (n) => n !== "db"
    ? Promise.resolve(null)
    : new Promise((resolve) => { handOverDb = () => resolve(dbHandle); }) } }
};
sandbox.window.document = sandbox.document;

// ---- run the page script -------------------------------------------------
require("vm").createContext(sandbox);
require("vm").runInContext(blocks[0], sandbox, { filename: "index.html#script1" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rowsNow = () => sandbox.document.querySelectorAll("li.row");
const rowFor = (n) => rowsNow().find((r) => r.dataset.pr === String(n));
function tick(n, on) {
  const box = rowFor(n).querySelector("input");
  box.checked = on;
  for (const f of box.listeners.change) f();
}
const tickedPrs = () => rowsNow().filter((r) => r.className.includes("is-done"))
  .map((r) => r.dataset.pr).sort().join(",");

(async () => {
  const win = sandbox.window;
  await sleep(20);

  console.log("the handle resolves late");
  check(rowsNow().length > 0, "the rows are built without waiting for the store");
  check(snapshotCb === null, "no subscription yet, so a tick now is genuinely unsaved");

  tick(119, true);
  check(byId["c-done"].textContent === "1", "a tick made before the handle resolves paints at once");
  check(writes.length === 0, "with no store there is nothing to write to");

  handOverDb();
  await sleep(20);
  check(snapshotCb !== null, "the page subscribes once the handle resolves");
  check(writes.length === 0,
    "nothing is written before the first delivery, or the flush would replace the stored ticks unread");

  snapshotCb({ id: "checklist", exists: true, data: () => ({ checked: { "124": true, "122": true }, updatedAt: 1 }) });
  check(byId["c-done"].textContent === "3",
    "the first delivery merges, so the tick made while the handle was null survives, got " + byId["c-done"].textContent);
  check(tickedPrs() === "119,122,124", "the merge keeps both sides, got " + tickedPrs());
  check(writes.length === 1 && writes[0].checked["119"] && writes[0].checked["124"],
    "the merged state is flushed, so the early tick reaches the other reviewers too");

  snapshotCb({ id: "checklist", exists: true, data: () => ({ checked: { "124": true, "122": true }, updatedAt: 2 }) });
  check(tickedPrs() === "122,124",
    "a later delivery replaces rather than merges, so an untick elsewhere still lands, got " + tickedPrs());

  console.log("persistence");
  const rows = rowsNow();
  check(byId["c-done"].textContent === "2", "a stored document repaints the ticks (counter reads 2)");
  check(tickedPrs() === "122,124", "the rows painted are the rows stored, keyed by pull request number, got " + tickedPrs());
  const box = rowFor(124);
  check(!!box && box.querySelector("input").checked, "the checkbox itself is re-checked, not just the row style");

  snapshotCb({ id: "checklist", exists: false, data: () => undefined });
  check(byId["c-done"].textContent === "2", "a document that is not there is not an untick");

  console.log("copy output");
  // A page with no hook at all is a failure to report, not a crash to read.
  const hook = typeof win.anPageSection === "function" ? win.anPageSection : () => null;
  check(typeof win.anPageSection === "function", "the page hands the annotation layer a section to copy");
  const md = hook() || "";
  check(/^## Reviewed so far$/m.test(md), "the copy gains a plain-text section of its own");
  check(/- \[x\] #124 /.test(md) && /- \[ \] #119 /.test(md), "ticked and unticked rows are both legible as text");
  check(md.split("\n").filter((l) => l.startsWith("- [")).length === rows.length,
    "every tickable row is listed, not only the ticked ones");

  snapshotCb({ id: "checklist", exists: true, data: () => ({ checked: {}, updatedAt: 3 }) });
  check(byId["c-done"].textContent === "0", "unticking elsewhere propagates back");
  check(hook() === "", "nothing ticked contributes nothing, so an empty copy still says so");

  console.log(failures ? failures + " check(s) failed" : "all checks pass");
  process.exit(failures ? 1 : 0);
})();
