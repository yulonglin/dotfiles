// Regression check for the review queue's checklist: node artifacts/pr-review-queue/checklist-test.js
//
// The published page cannot be opened from a session, so what broke is pinned
// here instead. Each scenario runs the page's own script text against a fresh
// stub DOM and a fresh stub db capability -- no browser, no network.
//
// One sentence covers most of it. Each row's tick is its OWN document, keyed
// by the pull request number, so a write carries one row's value and nothing
// else. Two viewers ticking different rows write different documents and
// cannot collide; two viewers ticking the same row resolve last-writer-wins,
// which is correct rather than a defect. Everything below is a schedule that
// used to break the shared map this page wrote before:
//
//   1. a toggle made before the handle resolves reaches the store
//   2. a toggle made after the handle resolves needs no read first
//   3. toggles either side of the handle both reach the store
//   4. a refused write stays pending, and marks only its own row
//   5. a second row does not wait behind the first; a re-toggle of the same
//      row does, and is sent when that row's write settles
//   6. a delivery arriving mid-write is display only
//   7. an untick is a stored false, not a deleted key
//   8. a write that throws rather than rejecting does not wedge its row
//   9. a stored collection repaints the ticks, and they leave with the copy
//  10. THE DEFECT AT 656dec0: a remote tick arriving while this device's write
//      is on the wire is no longer erased by it
//  11. a row with no document of its own reads its value out of the old
//      shared document, lazily, with nothing copied and nothing marked done
//
// Exit code is the result; every failure prints what it expected.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
if (blocks.length !== 2) bail("expected 2 script blocks in index.html, found " + blocks.length);

const TICKS = "review/checklist/ticks";
const LEGACY = "review/checklist";

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
// store is null, until deliver() runs it has never seen the collection, and
// h.mode picks whether a write resolves, rejects, hangs on the wire, or throws.
//
// h.stored is the WHOLE store, one entry per row, which is what the page now
// writes into. A write lands in it only when that write succeeds, so a refused
// or still-held write is visibly absent. h.remote() is another viewer writing.
function newPage() {
  const root = new El("root"), byId = {};
  for (const id of ["group-quick", "group-code", "group-call", "group-other", "group-stale", "c-done", "sync"]) {
    byId[id] = new El("ul"); root.append(byId[id]);
  }

  const h = { writes: [], snapshotCb: null, errCb: null, handOverDb: null, mode: "ok", held: [],
              byId, stored: new Map(), subPath: null, legacy: null, legacyWrites: 0, legacyGets: 0,
              legacyMode: "ok" };

  const docRef = (p) => ({
    path: p,
    get: () => {
      if (p !== LEGACY) bail("unexpected get() on " + p);
      h.legacyGets++;
      if (h.legacyMode === "fail") return Promise.reject(new Error("read refused"));
      if (h.legacyMode === "throw") throw new Error("read threw");
      const body = h.legacy;
      return Promise.resolve({ id: "checklist", exists: !!body, data: () => body || undefined });
    },
    set: (d) => {
      if (p === LEGACY) { h.legacyWrites++; return Promise.resolve(); }
      if (!p.startsWith(TICKS + "/")) bail("write to an unexpected path: " + p);
      const pr = p.slice(TICKS.length + 1);
      if (pr.includes("/")) bail("a row document must be one segment below the collection: " + p);
      h.writes.push({ path: p, pr, data: d });
      const land = () => h.stored.set(pr, !!(d && d.on));
      if (h.mode === "fail") return Promise.reject(new Error("write refused"));
      if (h.mode === "throw") throw new Error("write threw");
      if (h.mode === "hold") return new Promise((resolve, reject) => h.held.push({ pr, resolve: () => { land(); resolve(); }, reject }));
      land();
      return Promise.resolve();
    },
    onSnapshot: () => bail("the page should subscribe to the collection, not to " + p)
  });
  const dbHandle = {
    doc: docRef,
    collection: (p) => ({
      path: p,
      doc: (id) => docRef(p + "/" + id),
      onSnapshot: (next, onErr) => { h.subPath = p; h.snapshotCb = next; h.errCb = onErr; return () => {}; }
    })
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

  // another viewer's writes, applied to the store without any delivery
  h.remote = (map) => { for (const pr of Object.keys(map || {})) h.stored.set(pr, !!map[pr]); };
  h.snapshot = (fromCache) => ({
    docs: [...h.stored.entries()].map(([pr, on]) => ({
      id: pr, exists: true, data: () => ({ on, updatedAt: 1 }), metadata: { fromCache: !!fromCache, hasPendingWrites: false }
    })),
    get size() { return this.docs.length; },
    get empty() { return this.docs.length === 0; },
    docChanges: () => [],
    metadata: { fromCache: !!fromCache, hasPendingWrites: false }
  });
  // apply another viewer's writes, then deliver the whole collection
  h.deliver = (map) => { h.remote(map); h.snapshotCb(h.snapshot(false)); };
  h.deliverCache = (map) => { h.remote(map); h.snapshotCb(h.snapshot(true)); };
  h.deliverStored = () => h.snapshotCb(h.snapshot(false));
  h.releaseAll = () => { for (const x of h.held.splice(0)) x.resolve(); };

  h.writeCount = () => h.writes.length;
  h.lastWrite = () => h.writes[h.writes.length - 1];
  h.wroteRows = () => h.writes.map((w) => w.pr).join(",");
  h.storedKeys = () => [...h.stored.entries()].filter(([, on]) => on).map(([pr]) => pr).sort().join(",");
  return h;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// a write settles as a microtask, so one macrotask hop is enough to see its
// effect on the pending set
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
    check(h.writeCount() === 0, "with no store there is nothing to write to");

    h.handOverDb();
    await sleep(20);
    check(h.snapshotCb !== null, "the page subscribes once the handle resolves");
    check(h.subPath === TICKS, "and it subscribes to the collection, so one row's change touches one row, got " + h.subPath);
    // The old suite asserted the opposite here -- that nothing may be written
    // before the first delivery -- because a whole-document write had to be
    // computed from state already reconciled with the store. One document per
    // row has nothing to reconcile, so that gate is gone with the design.
    check(h.writeCount() === 1 && h.storedKeys() === "119",
      "the tick is stored as soon as the handle resolves, with no read first, got " + h.storedKeys());
    check(h.lastWrite().path === TICKS + "/119" && h.lastWrite().data.on === true,
      "one document, named by the pull request number, holding that row's value, got " + h.lastWrite().path);

    h.deliver({ "124": true, "122": true });
    check(h.done() === "3",
      "the first delivery brings the other reviewers' rows in beside it, got " + h.done());
    check(h.tickedPrs() === "119,122,124", "all three are on screen, got " + h.tickedPrs());
    check(h.writeCount() === 1, "and a delivery writes nothing back: no write is derived from a read");

    h.deliver({ "119": false });
    check(h.tickedPrs() === "122,124",
      "an untick made elsewhere is a stored false, and it lands, got " + h.tickedPrs());
  }

  // ---------------------------------------------------------------- 2 ----
  scenario("a toggle after the handle resolves but before the first delivery");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    check(h.snapshotCb !== null, "subscribed, but nothing has been delivered yet");

    h.tick(119, true);
    check(h.done() === "1", "the tick paints at once");
    await settle();
    check(h.writeCount() === 1 && h.storedKeys() === "119",
      "a resolved handle is enough to store one row: there is no shared state to read first, got " + h.storedKeys());

    h.deliver({ "124": true, "122": true, "118": true });
    check(h.tickedPrs() === "118,119,122,124", "the first delivery paints all four, got " + h.tickedPrs());
    check(h.writeCount() === 1,
      "still exactly one write: the three rows this device never touched are never written by it, got " + h.writeCount());

    await settle();
    h.deliverStored();
    check(h.tickedPrs() === "118,119,122,124",
      "the echo paints the same four back, it does not clear them, got " + h.tickedPrs());
  }

  // ---------------------------------------------------------------- 3 ----
  scenario("a toggle either side of the handle, both before the first delivery");
  {
    const h = newPage();
    await sleep(20);
    h.tick(119, true);
    h.handOverDb();
    await sleep(20);
    h.tick(118, true);
    check(h.done() === "2", "both ticks paint");
    await settle();
    check(h.writeCount() === 2 && h.storedKeys() === "118,119",
      "one write each, so both reach the store, got " + h.storedKeys());

    h.deliver({ "124": true, "122": true });
    check(h.tickedPrs() === "118,119,122,124", "the first delivery paints all four, got " + h.tickedPrs());
    check(h.writeCount() === 2, "and adds no write of its own, got " + h.writeCount());

    await settle();
    h.deliverStored();
    check(h.tickedPrs() === "118,119,122,124", "the echo keeps all four, got " + h.tickedPrs());
  }

  // ---------------------------------------------------------------- 4 ----
  scenario("a write that failed stays pending, and marks only its own row");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await settle();
    check(h.writeCount() === 0, "an empty collection with nothing pending writes nothing");

    h.mode = "fail";
    h.tick(119, true);
    await settle();
    check(h.writeCount() === 1, "the tick is attempted once");
    check(h.storedKeys() === "", "and nothing is stored, because the write was refused, got " + h.storedKeys());
    check(/save failed/.test(h.sync()), "a failed write says so, got " + JSON.stringify(h.sync()));

    h.mode = "ok";
    h.tick(118, true);
    await settle();
    check(h.storedKeys() === "118,119",
      "the retry carries the row the failed write never landed, got " + h.storedKeys());
    check(/synced/.test(h.sync()), "and the page says it is synced again, got " + JSON.stringify(h.sync()));
  }

  // ---------------------------------------------------------------- 4b ---
  scenario("a refusal for one row leaves every other row alone");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({ "124": true });
    await settle();

    h.mode = "fail";
    h.tick(119, true);
    await settle();
    check(/save failed/.test(h.sync()), "the refusal is reported, got " + JSON.stringify(h.sync()));
    check(h.storedKeys() === "124",
      "the row another viewer stored is untouched by this device's refused write, got " + h.storedKeys());
    check(h.tickedPrs() === "119,124", "and both stay on screen, got " + h.tickedPrs());

    // Only a write that carried 119 may clear 119's flag. A successful write
    // for a different row must not.
    h.mode = "ok";
    h.tick(118, true);
    await settle();
    check(h.storedKeys() === "118,119,124", "the pending row is retried alongside the new one, got " + h.storedKeys());
    check(/synced/.test(h.sync()), "and only then is the failure cleared, got " + JSON.stringify(h.sync()));
  }

  // ---------------------------------------------------------------- 5 ----
  scenario("a toggle made while a write is on the wire");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await settle();

    h.mode = "hold";
    h.tick(119, true);
    check(h.writeCount() === 1 && h.lastWrite().pr === "119", "the first tick goes out, got " + h.wroteRows());
    // The old suite asserted "one write at a time" here, which was a property
    // of writing one shared document. Different rows are different documents,
    // so the second tick has nothing to wait for.
    h.tick(118, true);
    check(h.writeCount() === 2 && h.lastWrite().pr === "118",
      "a second row does not wait behind the first, got " + h.wroteRows());

    // The same row does still wait for its own write, or the later value could
    // be overtaken by the earlier one.
    h.tick(119, false);
    check(h.writeCount() === 2, "but a re-toggle of a row already on the wire waits, got " + h.wroteRows());

    h.mode = "ok";
    h.releaseAll();
    await settle();
    check(h.writeCount() === 3 && h.lastWrite().pr === "119",
      "and is sent as soon as that row's write settles, got " + h.wroteRows());
    check(h.storedKeys() === "118",
      "so the re-toggle is not cleared by the write it queued behind, got " + h.storedKeys());
    await settle();
    check(h.writeCount() === 3, "and then it stops: nothing pending writes nothing");
  }

  // ---------------------------------------------------------------- 6 ----
  scenario("a delivery arriving before a write has settled");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await settle();

    h.mode = "hold";
    h.tick(119, true);
    check(h.writeCount() === 1, "the tick goes out and hangs on the wire");

    h.deliver({ "122": true });
    check(h.tickedPrs() === "119,122",
      "a toggle no successful write has carried yet is kept on top of an incoming snapshot, got " + h.tickedPrs());
    check(h.writeCount() === 1, "and the delivery adds no write of its own, got " + h.writeCount());

    h.mode = "ok";
    h.releaseAll();
    await settle();
    check(h.tickedPrs() === "119,122", "the settle changes nothing on screen, got " + h.tickedPrs());
    check(h.writeCount() === 1, "nothing is left pending, so no second write, got " + h.writeCount());
  }

  // ---------------------------------------------------------------- 7 ----
  scenario("an untick made before the first delivery");
  {
    const h = newPage();
    await sleep(20);
    h.remote({ "119": true, "122": true });   // stored by other reviewers before this page loaded
    h.tick(119, true);
    h.tick(119, false);
    h.mode = "hold";
    h.handOverDb();
    await sleep(20);
    check(h.writeCount() === 1 && h.lastWrite().path === TICKS + "/119" && h.lastWrite().data.on === false,
      "the untick is stored as an explicit false rather than said by deleting a key, got " +
      JSON.stringify(h.lastWrite() && h.lastWrite().data.on));

    h.deliverStored();                        // a snapshot that predates the untick landing
    check(h.tickedPrs() === "122",
      "an untick is a pending change too, so it wins over the stored tick it undid, got " + h.tickedPrs());

    h.mode = "ok";
    h.releaseAll();
    await settle();
    check(h.storedKeys() === "122", "so the row reads as unticked for everyone, got " + h.storedKeys());
  }

  // ---------------------------------------------------------------- 8 ----
  scenario("a write that throws rather than rejecting");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await settle();

    h.mode = "throw";
    h.tick(119, true);
    await settle();
    check(/save failed/.test(h.sync()), "a set() that throws reads as a failed write, got " + JSON.stringify(h.sync()));

    h.mode = "ok";
    h.tick(118, true);
    await settle();
    check(h.storedKeys() === "118,119",
      "and that row was not left stuck on the wire, so the retry lands, got " + h.storedKeys());
  }

  // ---------------------------------------------------------------- 9 ----
  scenario("persistence");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({ "124": true, "122": true });
    await settle();
    check(h.done() === "2", "a stored collection repaints the ticks (counter reads 2)");
    check(h.tickedPrs() === "122,124", "the rows painted are the rows stored, keyed by pull request number, got " + h.tickedPrs());
    const box = h.rowFor(124);
    check(!!box && box.querySelector("input").checked, "the checkbox itself is re-checked, not just the row style");
    check(h.writeCount() === 0, "a load with nothing pending writes nothing back");

    // The old suite asserted here that a document that is not there is not an
    // untick. That was forced by the shared map, where an absent key could not
    // say whether a row had been unticked or had never been stored. Per row
    // there is no ambiguity to protect against: a row stored false is
    // unticked, and it says nothing about any other row.
    h.deliver({ "119": false });
    check(h.tickedPrs() === "122,124",
      "a row stored as false is a row not ticked, and it disturbs no other row, got " + h.tickedPrs());

    scenario("copy output");
    // A page with no hook at all is a failure to report, not a crash to read.
    const hook = typeof h.window.anPageSection === "function" ? h.window.anPageSection : () => null;
    check(typeof h.window.anPageSection === "function", "the page hands the annotation layer a section to copy");
    const md = hook() || "";
    check(/^## Reviewed so far$/m.test(md), "the copy gains a plain-text section of its own");
    check(/- \[x\] #124 /.test(md) && /- \[ \] #119 /.test(md), "ticked and unticked rows are both legible as text");
    check(md.split("\n").filter((l) => l.startsWith("- [")).length === h.rows().length,
      "every tickable row is listed, not only the ticked ones");

    h.deliver({ "124": false, "122": false });
    check(h.done() === "0", "unticking elsewhere propagates back");
    check(hook() === "", "nothing ticked contributes nothing, so an empty copy still says so");
  }

  // --------------------------------------------------------------- 10 ----
  // The defect at 656dec0, which six rounds of reconciliation could not close.
  // A whole-document write was computed before it went on the wire, so a tick
  // another viewer made while it was in flight was not in it -- and the write
  // replaced the document anyway. The display was reconciled, the store was
  // not, and the write's success emptied the queue so no correction followed.
  // One document per row removes the collision rather than reconciling it.
  scenario("a remote tick arriving while a write is on the wire");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await settle();

    h.mode = "hold";
    h.tick(119, true);
    check(h.writeCount() === 1, "the local tick goes out and hangs on the wire");

    h.deliver({ "122": true });            // another viewer ticks a different row
    check(h.tickedPrs() === "119,122", "both ticks are on screen, got " + h.tickedPrs());

    h.mode = "ok";
    h.releaseAll();
    await settle();
    check(h.storedKeys() === "119,122",
      "the other viewer's tick survives this device's write, stored is " + h.storedKeys());
    check(h.writes.every((w) => w.pr === "119"),
      "because this device only ever wrote the row it ticked, got " + h.wroteRows());
    check(/synced/.test(h.sync()), "and the page says synced, got " + JSON.stringify(h.sync()));

    h.deliverStored();                     // the echo of whatever is really stored
    check(h.tickedPrs() === "119,122",
      "so the echo paints both back rather than dropping one, got " + h.tickedPrs());
  }

  // --------------------------------------------------------------- 10b ---
  scenario("two viewers ticking the same row resolve last-writer-wins");
  {
    const h = newPage();
    await sleep(20);
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await settle();

    h.tick(119, true);
    await settle();
    check(h.storedKeys() === "119", "this device stores its value, got " + h.storedKeys());
    h.deliver({ "119": false });           // the other viewer unticks the same row, later
    check(h.tickedPrs() === "",
      "the last writer decides the one value they disagree about, got " + JSON.stringify(h.tickedPrs()));
    check(h.writeCount() === 1, "and this device does not write back to argue, got " + h.writeCount());
  }

  // --------------------------------------------------------------- 11 ----
  // THE LAZY FALLBACK, which replaced a one-time migration pass. A row with no
  // document of its own reads its value out of the old shared document, every
  // time it is read. Nothing is copied, so there is no completion marker to
  // record wrongly, no partial-failure window, and no "did it finish?" to get
  // wrong: a row that never gained a document of its own is simply read from
  // the old document again next time.
  scenario("a row with no document of its own reads the old shared document");
  {
    const h = newPage();
    await sleep(20);
    h.legacy = { checked: { "124": true, "122": true, "118": false }, updatedAt: 1 };
    h.handOverDb();
    await sleep(20);
    h.deliver({});                         // the new collection is empty
    await sleep(20);
    check(h.tickedPrs() === "122,124", "the old document's ticks are painted, got " + h.tickedPrs());
    check(h.writeCount() === 0,
      "and nothing is copied: there is no migration pass, got " + h.writeCount() + " write(s)");
    check(h.storedKeys() === "", "so the collection is left as it was, got " + h.storedKeys());
    check(h.legacyWrites === 0,
      "the old document is never written, so a rolled-back page still finds its ticks");

    h.deliverStored();
    await sleep(20);
    check(h.legacyGets === 1, "the old document is read once per page, not once per delivery, got " + h.legacyGets);
    check(h.tickedPrs() === "122,124", "and the fallback still stands on the next delivery, got " + h.tickedPrs());

    // A cached empty snapshot was the case the old gate had to exclude, because
    // migrating off one would have re-ticked rows since unticked. Reading is
    // not writing, so it is now just another delivery.
    h.deliverCache({});
    await sleep(20);
    check(h.tickedPrs() === "122,124" && h.writeCount() === 0,
      "a snapshot the server has not confirmed needs no special case, got " + h.tickedPrs() +
      " and " + h.writeCount() + " write(s)");
  }

  // -------------------------------------------------------------- 11a ----
  scenario("a row's own document wins over the old shared one");
  {
    const h = newPage();
    await sleep(20);
    h.legacy = { checked: { "124": true, "122": true }, updatedAt: 1 };
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await sleep(20);
    check(h.tickedPrs() === "122,124", "both rows fall back to the old document, got " + h.tickedPrs());

    h.tick(124, false);                    // untick a row only the old document holds
    await settle();
    check(h.lastWrite() && h.lastWrite().path === TICKS + "/124" && h.lastWrite().data.on === false,
      "the untick is stored as that row's own false, got " + (h.lastWrite() && h.lastWrite().path));
    check(h.tickedPrs() === "122", "and the row reads unticked, got " + h.tickedPrs());

    h.deliverStored();
    check(h.tickedPrs() === "122",
      "a row's own document shadows the old one for good, got " + h.tickedPrs());
    check(h.legacyWrites === 0, "and the old document is still not written");
  }

  // -------------------------------------------------------------- 11b ----
  // The reviewer's first reproduction: the old gate read a non-empty
  // collection as proof that migration had finished, and a viewer ticking one
  // row before the first delivery makes the collection non-empty.
  scenario("a tick made before the first delivery does not hide the old document");
  {
    const h = newPage();
    await sleep(20);
    h.legacy = { checked: { "124": true, "122": true }, updatedAt: 1 };
    h.handOverDb();
    await sleep(20);
    h.tick(119, true);
    await settle();
    check(h.storedKeys() === "119",
      "the tick creates a document, so the collection is no longer empty, got " + h.storedKeys());

    h.deliverStored();
    await sleep(20);
    check(h.tickedPrs() === "119,122,124",
      "a non-empty collection is not proof the old document is spent: its rows still read through, got " +
      h.tickedPrs());
  }

  // -------------------------------------------------------------- 11c ----
  // The reviewer's second reproduction, built against real quota exhaustion: a
  // read that FAILED is not a read that returned nothing.
  scenario("a refused read of the old document is not an empty one");
  {
    const h = newPage();
    await sleep(20);
    h.legacy = { checked: { "124": true, "122": true }, updatedAt: 1 };
    h.legacyMode = "throw";                // a get() that throws rather than rejecting
    h.handOverDb();
    await sleep(20);
    h.deliver({ "119": true });
    await sleep(20);
    check(h.legacyGets === 1, "the old document is read, got " + h.legacyGets);
    check(h.tickedPrs() === "119",
      "a read that threw adds nothing, and clears nothing already there, got " + h.tickedPrs());

    h.legacyMode = "fail";
    h.deliverStored();
    await sleep(20);
    check(h.legacyGets === 2, "the next delivery tries again rather than recording an empty answer, got " + h.legacyGets);
    check(h.tickedPrs() === "119", "and a refused read changes nothing either, got " + h.tickedPrs());

    h.legacyMode = "ok";
    h.deliverStored();
    await sleep(20);
    check(h.legacyGets === 3, "and again, got " + h.legacyGets);
    check(h.tickedPrs() === "119,122,124", "until a read lands, and then the rows appear, got " + h.tickedPrs());
  }

  // -------------------------------------------------------------- 11d ----
  // The partial-migration case: a store that accepts some writes and refuses
  // others used to mark itself migrated and abandon the rest. Nothing is
  // copied now, so a store refusing every write cannot lose a tick.
  scenario("a store refusing every write still shows the old document's ticks");
  {
    const h = newPage();
    await sleep(20);
    h.legacy = { checked: { "124": true, "122": true, "118": true }, updatedAt: 1 };
    h.mode = "fail";
    h.handOverDb();
    await sleep(20);
    h.deliver({});
    await sleep(20);
    check(h.tickedPrs() === "118,122,124",
      "every old tick reads through a store that will accept nothing, got " + h.tickedPrs());
    check(h.writeCount() === 0, "because none of them is written, got " + h.writeCount() + " write(s)");
    check(/synced/.test(h.sync()),
      "and no failure is reported for work the page never took on, got " + JSON.stringify(h.sync()));

    h.deliverStored();
    await sleep(20);
    check(h.tickedPrs() === "118,122,124", "they are still there on the next delivery, got " + h.tickedPrs());
  }

  // --------------------------------------------------------------- 12 ----
  scenario("the store is never reached at all");
  {
    const h = newPage();
    h.window.claude.use = () => Promise.resolve(null);
    await sleep(20);
    h.tick(119, true);
    check(h.done() === "1", "the page still ticks with no store behind it");
    check(h.writeCount() === 0, "and writes nothing anywhere");
  }

  console.log("\n" + (failures ? failures + " check(s) failed" : "all checks pass"));
  process.exit(failures ? 1 : 0);
})();
