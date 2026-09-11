// Regression check for the review queue's checklist: node artifacts/pr-review-queue/checklist-test.js
//
// The published page cannot be opened from a session, so the two things that
// broke are pinned here instead. It runs the page's own script text against a
// stub DOM and a stub db capability -- no browser, no network.
//
//   1. a stored document repaints the ticks (the load path must read
//      snapshot.data(), not the snapshot object's own fields)
//   2. the ticks leave with the copy, as plain text
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
  window: { claude: { use: async (n) => n !== "db" ? null : {
    doc: (p) => ({ path: p,
      onSnapshot: (next) => { snapshotCb = next; return () => {}; },
      set: async (d) => { writes.push(d); } })
  } } }
};
sandbox.window.document = sandbox.document;

// ---- run the page script -------------------------------------------------
require("vm").createContext(sandbox);
require("vm").runInContext(blocks[0], sandbox, { filename: "index.html#script1" });

setTimeout(() => {
  const win = sandbox.window;
  const rows = sandbox.document.querySelectorAll("li.row");
  if (!snapshotCb) bail("the load path never subscribed — nothing can ever restore a tick");

  console.log("persistence");
  snapshotCb({ id: "checklist", exists: true, data: () => ({ checked: { "124": true, "122": true }, updatedAt: 1 }) });
  check(byId["c-done"].textContent === "2", "a stored document repaints the ticks (counter reads 2)");
  const on = rows.filter((r) => r.className.includes("is-done")).map((r) => r.dataset.pr).sort().join(",");
  check(on === "122,124", "the rows painted are the rows stored, keyed by pull request number, got " + on);
  const box = rows.find((r) => r.dataset.pr === "124");
  check(!!box && box.querySelector("input").checked, "the checkbox itself is re-checked, not just the row style");

  snapshotCb({ id: "checklist", exists: false, data: () => undefined });
  check(byId["c-done"].textContent === "2", "an empty store does not wipe a tick made before the first delivery");

  console.log("copy output");
  // A page with no hook at all is a failure to report, not a crash to read.
  const hook = typeof win.anPageSection === "function" ? win.anPageSection : () => null;
  check(typeof win.anPageSection === "function", "the page hands the annotation layer a section to copy");
  const md = hook() || "";
  check(/^## Reviewed so far$/m.test(md), "the copy gains a plain-text section of its own");
  check(/- \[x\] #124 /.test(md) && /- \[ \] #119 /.test(md), "ticked and unticked rows are both legible as text");
  check(md.split("\n").filter((l) => l.startsWith("- [")).length === rows.length,
    "every tickable row is listed, not only the ticked ones");

  snapshotCb({ id: "checklist", exists: true, data: () => ({ checked: {}, updatedAt: 2 }) });
  check(byId["c-done"].textContent === "0", "unticking elsewhere propagates back");
  check(hook() === "", "nothing ticked contributes nothing, so an empty copy still says so");

  console.log(failures ? failures + " check(s) failed" : "all checks pass");
  process.exit(failures ? 1 : 0);
}, 50);
