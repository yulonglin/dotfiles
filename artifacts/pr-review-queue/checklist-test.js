// Regression check for the review queue's checklist: node artifacts/pr-review-queue/checklist-test.js
//
// The published page cannot be opened from a session, so what broke is pinned
// here instead. Each scenario runs the page's own script text against a fresh
// stub DOM and a fresh stub db capability -- no browser, no network.
//
// One sentence covers most of it. A write replaces the WHOLE stored document,
// which is the only way an untick can be expressed, so the page may only write
// a document it computed from state it has already reconciled with the store.
// Reconciliation happens exactly once, on the first snapshot, and the handle
// resolving is not it. Everything below is a schedule that broke that rule:
//
//   1. a toggle made before the handle resolves survives the first delivery
//   2. a toggle made after the handle resolves but before the first delivery
//      survives it too, and neither one replaces the stored ticks unread
//   3. a write that failed, and a toggle made while a write was on the wire,
//      stay queued -- a write only clears what it actually carried
//   4. a stored document repaints the ticks (the load path must read
//      snapshot.data(), not the snapshot object's own fields)
//   5. the ticks leave with the copy, as plain text
//
// Exit code is the result; every failure prints what it expected.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
if (blocks.length !== 2) bail("expected 2 script blocks in index.html, found " + blocks.length);

let failures = 0;
function bail(m) { console.error("FAIL: " + m); process.exit(1); }
function check(ok, m) { if (ok) { console.log("  ok   " + m); } else { failures++; console.error("  FAIL " + m); } }
function scenario(name) { console.log("\n" + name); }

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

// ---- one page instance ---------------------------------------------------
// The real capability resolves over the network and the real set() lands over
// it, so both are driven by hand here: until handOverDb() runs the page's
// store is null, until deliver() runs it has never seen the stored document,
// and h.mode picks whether a write resolves, rejects, or hangs on the wire.
function newPage() {
  const root = new El("root"), byId = {};
  for (const id of ["group-quick", "group-code", "group-call", "group-other", "group-stale", "c-done", "sync"]) {
    byId[id] = new El("ul"); root.append(byId[id]);
  }

  const h = { writes: [], snapshotCb: null, errCb: null, handOverDb: null, mode: "ok", held: [], byId };
  const dbHandle = {
    doc: (p) => ({ path: p,
      onSnapshot: (next, onErr) => { h.snapshotCb = next; h.errCb = onErr; return () => {}; },
      set: (d) => {
        h.writes.push(d);
        if (h.mode === "fail") return Promise.reject(new Error("write refused"));
        if (h.mode === "throw") throw new Error("write threw");
        if (h.mode === "hold") return new Promise((resolve, reject) => h.held.push({ resolve, reject }));
        return Promise.resolve();
      } })
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
      : new Promise((resolve) => { h.handOverDb = () => resolve(dbHandle); }) } }
  };
  sandbox.window.document = sandbox.document;
  vm.createContext(sandbox);
  vm.runInContext(blocks[0], sandbox, { filename: "index.html#script1" });

  h.window = sandbox.window;
  h.rows = () => sandbox.document.querySelectorAll("li.row");
  h.rowFor = (n) => h.rows().find((r) => r.dataset.pr === String(n));
  h.tick = (n, on) => {
    const box = h.rowFor(n).querySelector("input");
    box.checked = on;
    for (const f of box.listeners.change) f();
  };
  h.tickedPrs = () => h.rows().filter((r) => r.className.includes("is-done"))
    .map((r) => r.dataset.pr).sort().join(",");
  h.done = () => byId["c-done"].textContent;
  h.sync = () => byId["sync"].textContent;
  // checked === null stands for a document that is not there at all
  h.deliver = (checked, updatedAt) => h.snapshotCb({
    id: "checklist", exists: checked !== null,
    data: () => (checked === null ? undefined : { checked, updatedAt })
  });
  h.lastWrite = () => h.writes[h.writes.length - 1];
  h.wroteKeys = () => Object.keys((h.lastWrite() || { checked: {} }).checked).sort().join(",");
  return h;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// a write settles as a microtask, so one macrotask hop is enough to see its
// effect on the queue
const settle = () => sleep(0);

(async () => {
  // ---------------------------------------------------------------- 1 ----
  scenario("a toggle made before the handle resolves");
  {
    const h = newPage();
    await sleep(20);
    check(h.rows().length > 0, "the rows are built without waiting for the store");
    check(h.snapshotCb === null, "no subscription yet, so a tick now is genuinely unsaved");

    h.tick(119, true);
    check(h.done() === "1", "a tick made before the handle resolves paints at once");
    check(h.writes.length === 0, "with no store there is nothing to write to");

    h.handOverDb();
    await sleep(20);
    check(h.snapshotCb !== null, "the page subscribes once the handle resolves");
    check(h.writes.length === 0,
      "nothing is written before the first delivery, or the flush would replace the stored ticks unread");

    h.deliver({ "124": true, "122": true }, 1);
    check(h.done() === "3",
      "the first delivery reconciles, so the tick made while the handle was null survives, got " + h.done());
    check(h.tickedPrs() === "119,122,124", "the reconciled state keeps both sides, got " + h.tickedPrs());
    check(h.writes.length === 1 && h.wroteKeys() === "119,122,124",
      "the reconciled document is flushed once, so the early tick reaches the other reviewers too, got " + h.wroteKeys());

    await settle();
    h.deliver({ "124": true, "122": true }, 2);
    check(h.tickedPrs() === "122,124",
      "a later delivery replaces rather than merges, so an untick elsewhere still lands, got " + h.tickedPrs());
  }

  // ---------------------------------------------------------------- 2 ----
  // The reported defect, schedule one: the handle is not reconciliation.
  scenario("a toggle after the handle resolves but before the first delivery");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    check(h.snapshotCb !== null, "subscribed, but nothing has been delivered yet");

    h.tick(119, true);
    check(h.done() === "1", "the tick paints at once");
    check(h.writes.length === 0,
      "a resolved handle is not a read stored document, so the tick is queued, not written, got " + h.writes.length + " write(s)");

    h.deliver({ "124": true, "122": true, "118": true }, 1);
    check(h.tickedPrs() === "118,119,122,124", "the first delivery reconciles all four, got " + h.tickedPrs());
    check(h.writes.length === 1 && h.wroteKeys() === "118,119,122,124",
      "exactly one write, carrying the stored ticks as well as the local one, got " + h.wroteKeys());

    await settle();
    h.deliver({ "118": true, "119": true, "122": true, "124": true }, 2);
    check(h.tickedPrs() === "118,119,122,124",
      "the write's own echo paints the same four back, it does not clear them, got " + h.tickedPrs());
  }

  // ---------------------------------------------------------------- 3 ----
  // The reported defect, schedule two: one toggle either side of the handle.
  scenario("a toggle either side of the handle, both before the first delivery");
  {
    const h = newPage();
    await sleep(20);
    h.tick(119, true);
    h.handOverDb();
    await sleep(20);
    h.tick(118, true);
    check(h.done() === "2", "both ticks paint");
    check(h.writes.length === 0,
      "neither is written before the stored document has been read, got " + h.writes.length + " write(s)");

    h.deliver({ "124": true, "122": true }, 1);
    check(h.tickedPrs() === "118,119,122,124", "the first delivery reconciles all four, got " + h.tickedPrs());
    check(h.writes.length === 1 && h.wroteKeys() === "118,119,122,124",
      "one write carries both local ticks and both stored ones, got " + h.wroteKeys());

    await settle();
    h.deliver({ "118": true, "119": true, "122": true, "124": true }, 2);
    check(h.tickedPrs() === "118,119,122,124", "the echo keeps all four, got " + h.tickedPrs());
  }

  // ---------------------------------------------------------------- 4 ----
  scenario("a write that failed stays queued");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({}, 1);
    await settle();
    check(h.writes.length === 0, "an empty stored document with nothing queued writes nothing");

    h.mode = "fail";
    h.tick(119, true);
    await settle();
    check(h.writes.length === 1, "the tick is attempted once");
    check(/save failed/.test(h.sync()), "a failed write says so, got " + JSON.stringify(h.sync()));

    h.mode = "ok";
    h.tick(118, true);
    await settle();
    check(h.writes.length === 2 && h.wroteKeys() === "118,119",
      "the retry carries the tick the failed write never landed, got " + h.wroteKeys());
    check(/synced/.test(h.sync()), "and the page says it is synced again, got " + JSON.stringify(h.sync()));
  }

  // ---------------------------------------------------------------- 5 ----
  scenario("a toggle made while a write is on the wire");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({}, 1);
    await settle();

    h.mode = "hold";
    h.tick(119, true);
    check(h.writes.length === 1 && h.wroteKeys() === "119", "the first tick goes out, got " + h.wroteKeys());
    h.tick(118, true);
    check(h.writes.length === 1, "one write at a time: the second tick waits, got " + h.writes.length + " write(s)");

    h.mode = "ok";
    h.held[0].resolve();
    await settle();
    check(h.writes.length === 2 && h.wroteKeys() === "118,119",
      "the settle flushes what queued behind it, so the second tick is not cleared by the first write, got " + h.wroteKeys());
    await settle();
    check(h.writes.length === 2, "and then it stops: a settled queue writes nothing");
  }

  // ---------------------------------------------------------------- 6 ----
  scenario("a delivery arriving before a write has settled");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({}, 1);
    await settle();

    h.mode = "hold";
    h.tick(119, true);
    check(h.writes.length === 1, "the tick goes out and hangs on the wire");

    h.deliver({ "122": true }, 2);
    check(h.tickedPrs() === "119,122",
      "a toggle no successful write has carried yet is re-applied over an incoming document, got " + h.tickedPrs());
    check(h.writes.length === 1, "and it is not written twice while the first write is still on the wire");

    h.held[0].resolve();
    await settle();
    check(h.tickedPrs() === "119,122", "the settle changes nothing on screen, got " + h.tickedPrs());
    check(h.writes.length === 1, "nothing is left queued, so no second write, got " + h.writes.length + " write(s)");
  }

  // ---------------------------------------------------------------- 7 ----
  scenario("an untick made before the first delivery");
  {
    const h = newPage();
    await sleep(20);
    h.tick(119, true);
    h.tick(119, false);
    h.handOverDb();
    await sleep(20);
    h.deliver({ "119": true, "122": true }, 1);
    check(h.tickedPrs() === "122",
      "an untick is a queued change too, so it wins over the stored tick it undid, got " + h.tickedPrs());
    check(h.writes.length === 1 && h.wroteKeys() === "122",
      "and the flush drops the key, which is the only way to say untick, got " + h.wroteKeys());
  }

  // ---------------------------------------------------------------- 8 ----
  scenario("a write that throws rather than rejecting");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({}, 1);
    await settle();

    h.mode = "throw";
    h.tick(119, true);
    await settle();
    check(/save failed/.test(h.sync()), "a set() that throws reads as a failed write, got " + JSON.stringify(h.sync()));

    h.mode = "ok";
    h.tick(118, true);
    await settle();
    check(h.writes.length === 2 && h.wroteKeys() === "118,119",
      "and the in-flight flag was released, so the queue is not wedged behind it, got " + h.wroteKeys());
  }

  // ---------------------------------------------------------------- 9 ----
  scenario("persistence");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({ "124": true, "122": true }, 1);
    await settle();
    check(h.done() === "2", "a stored document repaints the ticks (counter reads 2)");
    check(h.tickedPrs() === "122,124", "the rows painted are the rows stored, keyed by pull request number, got " + h.tickedPrs());
    const box = h.rowFor(124);
    check(!!box && box.querySelector("input").checked, "the checkbox itself is re-checked, not just the row style");
    check(h.writes.length === 0, "a load with nothing queued writes nothing back");

    h.deliver(null);
    check(h.done() === "2", "a document that is not there is not an untick");

    scenario("copy output");
    // A page with no hook at all is a failure to report, not a crash to read.
    const hook = typeof h.window.anPageSection === "function" ? h.window.anPageSection : () => null;
    check(typeof h.window.anPageSection === "function", "the page hands the annotation layer a section to copy");
    const md = hook() || "";
    check(/^## Reviewed so far$/m.test(md), "the copy gains a plain-text section of its own");
    check(/- \[x\] #124 /.test(md) && /- \[ \] #119 /.test(md), "ticked and unticked rows are both legible as text");
    check(md.split("\n").filter((l) => l.startsWith("- [")).length === h.rows().length,
      "every tickable row is listed, not only the ticked ones");

    h.deliver({}, 3);
    check(h.done() === "0", "unticking elsewhere propagates back");
    check(hook() === "", "nothing ticked contributes nothing, so an empty copy still says so");
  }

  console.log("\n" + (failures ? failures + " check(s) failed" : "all checks pass"));
  process.exit(failures ? 1 : 0);
})();
