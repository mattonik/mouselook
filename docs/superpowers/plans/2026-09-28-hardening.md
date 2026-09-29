# Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use WebKit's own pointer lock when it works (polyfill as fallback), and add per-service health checks that tell the user once when a service stopped behaving, with a local diagnostics log and a Copy diagnostics button.

**Architecture:** The polyfill keeps WebKit's pointer lock functions if they exist and tries them first, falling back to its own lock within 250 ms; it tells the app which path locked. A new page script, `health-checks.js`, runs after the polyfill and reports check results through the existing message handler. On the native side, `HealthMonitor` (one per browser) turns results into at most one toast per check per session, `DiagnosticsLog` keeps the last 200 events on disk, and Settings ▸ Advanced shows the checks and copies a `DiagnosticsReport`.

**Tech Stack:** Swift 5 / UIKit / SwiftUI / WKWebView (iPadOS 17+, built with Xcode 26), XCTest; JavaScript page scripts tested with Playwright in headless Chromium.

**Spec:** `docs/superpowers/specs/2026-09-28-hardening-design.md`

## Global Constraints

- Run tests locally with `tools/test.sh` (`swift`, `js`, or both). CI only runs on merges to `main`; never add push/PR triggers.
- All work stays on branch `claude/hardening`; one PR to `main` at the end.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Checks only observe: no DOM changes, no `preventDefault`, no `stopPropagation` in `health-checks.js`.
- Privacy: reports and log entries carry only check id, result, short code, service id and page **host**. No page text, URL paths, file names or keystrokes.
- On iPadOS 26 (no native API) behaviour for the user is unchanged.
- Native fallback budget: 250 ms. `lock-on-click` wait: 2 s, problem after 2 misses in a row. `scrub-lock`: drag > 3 px, wait 500 ms. `desktop-client`: ok after 10 s. Log capacity: 200 entries.
- Toast text, exactly:
  - `desktop-client`: "GeForce NOW didn't load its desktop version, so the mouse may not lock. Updating Mouselook usually fixes this."
  - `lock-on-click`: "The game didn't ask for the mouse. Click into the game again, or check Settings ▸ Advanced."
  - `scrub-lock`: "Figma didn't lock the pointer while you dragged, so values stop at the screen edge."
- The spec's `lockMode` message is carried as a `mode` field (`"native"` / `"polyfill"`) on the existing `lock`/`unlock` messages, so lock and mode can never arrive out of order.

## Review Focus

1. A page calls `requestPointerLock` twice while the first native attempt is still pending: expect one lock and one `pointerlockchange`, not two attempts racing. (Task 1: `testSecondRequestWhileNativePending`.)
2. The requested element is removed from the page during the 250 ms native attempt: expect no lock and no stale "locked" state. (Task 1: `testElementRemovedWhileNativePending`.)
3. A problem arrives while locked, then the user switches service before unlocking: the queued toast must not appear in the new service. (Task 6: `testSwitchingServiceDropsQueuedToast`.)
4. A page posts health messages with unknown check ids or junk fields (pages can call the message handler too): expect them ignored, no crash, nothing logged. (Task 6: `testUnknownAndMalformedReportsAreIgnored`.)
5. A very long detail string reaches the log (for example a hostile host name): expect it truncated to 200 characters so the log file stays small. (Task 5: `testLongDetailsAreTruncated`.)

---

## File Structure

| File | Responsibility |
|---|---|
| `Apps/PointerLocker/Resources/pointerlock-polyfill.js` (modify) | Native-first lock with fallback; `mode` on lock messages |
| `Apps/PointerLocker/Resources/health-checks.js` (create) | The three checks, observing only |
| `Apps/PointerLocker/Health/LockMessage.swift` (create) | Parses `lock`/`unlock` messages into locked + native |
| `Apps/PointerLocker/Health/HealthCheck.swift` (create) | `HealthCheckID`, titles, toast texts; profile check lists; page config script |
| `Apps/PointerLocker/Health/DiagnosticsLog.swift` (create) | Ring buffer of 200 entries saved as JSON |
| `Apps/PointerLocker/Health/HealthMonitor.swift` (create) | Results per check, toast once per session, queue while locked |
| `Apps/PointerLocker/Health/DiagnosticsReport.swift` (create) | Plain-text report for Copy diagnostics |
| `Apps/PointerLocker/Services/*Profile.swift`, `ServiceProfile.swift` (modify) | `healthChecks` per profile |
| `Apps/PointerLocker/WebViewFactory.swift` (modify) | Inject health config + script after the polyfill |
| `Apps/PointerLocker/BrowserViewController.swift`, `RootViewController.swift`, `SettingsView.swift` (modify) | Wiring, logging points, Settings rows and button |
| `tests/polyfill.test.mjs` (modify), `tests/health-checks.test.mjs` (create), `package.json` (modify) | JS tests |
| `tests/PointerLockerTests/LockMessageTests.swift`, `HealthCheckTests.swift`, `DiagnosticsLogTests.swift`, `HealthMonitorTests.swift`, `DiagnosticsReportTests.swift` (create) | Swift tests |

---

### Task 1: Native pointer lock first, polyfill as fallback

**Files:**
- Modify: `Apps/PointerLocker/Resources/pointerlock-polyfill.js` (top of the IIFE after `post`; `setLocked`; `requestPointerLock`/`exitPointerLock`; `pointerLockElementGetter`; hold-Esc unlock near line 316; `api.forceUnlock` and `api.isLocked` near line 500)
- Modify: `tests/polyfill.test.mjs`

**Interfaces:**
- Produces: messages `{type: "lock", mode: "native" | "polyfill"}` and `{type: "unlock", mode: "native" | "polyfill"}` (consumed by Task 2). `window.__pointerLocker.isLocked` is true for either path.

- [ ] **Step 1: Make the existing test pages match iPadOS 26 (no native API).** In `tests/polyfill.test.mjs`, after the `stub` constant add:

```js
// iPadOS 26 WebKit has no pointer lock API; Chromium does. Remove it so the
// main suite runs the polyfill path the app runs today.
const noNativeLock = `
  for (const [proto, names] of [
    [Element.prototype, ["requestPointerLock", "webkitRequestPointerLock"]],
    [Document.prototype, ["exitPointerLock", "webkitExitPointerLock", "pointerLockElement",
                          "webkitPointerLockElement", "onpointerlockchange", "onpointerlockerror"]],
  ]) for (const n of names) delete proto[n];
`;
```

and change every `addInitScript({ content: stub ... })` for `page`, `plain`, `workerPage`, `hudPage` and `modPage` to prepend it, e.g. `await page.addInitScript({ content: noNativeLock + stub + identity });`. Also change the stub to keep full messages alongside types:

```js
const stub = `
  window.__native = [];
  window.__messages = [];
  window.webkit = { messageHandlers: { pointerLocker: {
    postMessage: (m) => { window.__native.push(m.type); window.__messages.push(m); } } } };
`;
```

- [ ] **Step 2: Write the failing tests** (append before `await browser.close();`):

```js
// Native pointer lock: fakes stand in for a future WebKit so each case is exact.
const fakeNative = (behaviour) => `
  let locked = null;
  Object.defineProperty(Document.prototype, "pointerLockElement", { configurable: true, get() { return locked; } });
  Document.prototype.exitPointerLock = function () {
    locked = null; window.__nativeExits = (window.__nativeExits || 0) + 1;
    setTimeout(() => document.dispatchEvent(new Event("pointerlockchange", { bubbles: true })), 0);
  };
  Element.prototype.requestPointerLock = function () {
    window.__nativeRequests = (window.__nativeRequests || 0) + 1;
    const el = this;
    if (${JSON.stringify(behaviour)} === "works") {
      setTimeout(() => { locked = el; document.dispatchEvent(new Event("pointerlockchange", { bubbles: true })); }, 5);
      return new Promise((r) => setTimeout(r, 6));
    }
    if (${JSON.stringify(behaviour)} === "refuses") {
      setTimeout(() => document.dispatchEvent(new Event("pointerlockerror", { bubbles: true })), 5);
      return Promise.reject(new DOMException("not allowed", "NotAllowedError"));
    }
    return undefined; // "silent": never locks, never errors
  };
`;
const nativePage = async (behaviour) => {
  const p = await browser.newPage();
  await p.addInitScript({ content: fakeNative(behaviour) + stub });
  await p.addInitScript({ content: polyfill });
  await p.goto(`data:text/html,<canvas id="c" width="100" height="100"></canvas>`);
  await p.evaluate(() => {
    window.__events = [];
    for (const t of ["pointerlockchange", "pointerlockerror"])
      document.addEventListener(t, () => window.__events.push(t));
  });
  return p;
};
const lockCanvas = (p) => p.evaluate(async () => {
  const t0 = performance.now();
  await document.getElementById("c").requestPointerLock();
  await new Promise((r) => setTimeout(r, 30));
  return { ms: performance.now() - t0, el: document.pointerLockElement?.id ?? null,
           events: window.__events, messages: window.__messages, locked: window.__pointerLocker.isLocked };
});

await test("without a native API the polyfill locks and says so", async () => {
  await page.evaluate(() => window.__pointerLocker.forceUnlock());
  await page.evaluate(() => { window.__messages = []; });
  await page.evaluate(() => document.getElementById("c").requestPointerLock());
  const m = await page.evaluate(() => window.__messages);
  assert.deepEqual(m[0], { type: "lock", mode: "polyfill" });
  await page.evaluate(() => window.__pointerLocker.forceUnlock());
});

await test("working native lock is used and the app is told", async () => {
  const p = await nativePage("works");
  const r = await lockCanvas(p);
  assert.equal(r.el, "c");
  assert.deepEqual(r.events, ["pointerlockchange"]);
  assert.deepEqual(r.messages, [{ type: "lock", mode: "native" }]);
  assert.equal(r.locked, true);
  await p.evaluate(() => document.exitPointerLock());
  await p.evaluate(() => new Promise((r) => setTimeout(r, 20)));
  assert.equal(await p.evaluate(() => window.__nativeExits), 1);
  assert.deepEqual((await p.evaluate(() => window.__messages)).at(-1), { type: "unlock", mode: "native" });
  await p.close();
});

await test("refused native lock falls back to the polyfill without an error reaching the page", async () => {
  const p = await nativePage("refuses");
  const r = await lockCanvas(p);
  assert.equal(r.el, "c");
  assert.deepEqual(r.events, ["pointerlockchange"]);
  assert.deepEqual(r.messages, [{ type: "lock", mode: "polyfill" }]);
  assert.ok(r.ms < 250 + 60, `took ${r.ms} ms`);
  await p.close();
});

await test("silent native lock falls back after 250 ms and isn't tried again", async () => {
  const p = await nativePage("silent");
  const r = await lockCanvas(p);
  assert.equal(r.el, "c");
  assert.ok(r.ms >= 240 && r.ms < 400, `took ${r.ms} ms`);
  assert.deepEqual(r.messages, [{ type: "lock", mode: "polyfill" }]);
  await p.evaluate(() => document.exitPointerLock());
  await lockCanvas(p);
  assert.equal(await p.evaluate(() => window.__nativeRequests), 1, "native tried once per page");
  await p.close();
});

await test("testSecondRequestWhileNativePending: one lock, one change", async () => {
  const p = await nativePage("works");
  const r = await p.evaluate(async () => {
    const c = document.getElementById("c");
    await Promise.all([c.requestPointerLock(), c.requestPointerLock()]);
    await new Promise((r) => setTimeout(r, 30));
    return { events: window.__events, requests: window.__nativeRequests, messages: window.__messages };
  });
  assert.deepEqual(r.events, ["pointerlockchange"]);
  assert.equal(r.requests, 1);
  assert.deepEqual(r.messages, [{ type: "lock", mode: "native" }]);
  await p.close();
});

await test("testElementRemovedWhileNativePending: no lock, no stale state", async () => {
  const p = await nativePage("silent");
  const r = await p.evaluate(async () => {
    const c = document.getElementById("c");
    const pending = c.requestPointerLock().catch((e) => e.name);
    c.remove();
    const outcome = await pending;
    await new Promise((r) => setTimeout(r, 30));
    return { outcome, el: document.pointerLockElement, locked: window.__pointerLocker.isLocked, messages: window.__messages };
  });
  assert.equal(r.el, null);
  assert.equal(r.locked, false);
  assert.deepEqual(r.messages, []);
  assert.equal(r.outcome, "WrongDocumentError");
  await p.close();
});
```

- [ ] **Step 3: Run to see them fail.** Run: `tools/test.sh js`. Expected: FAIL on "without a native API the polyfill locks and says so" (message has no `mode`) and on the native tests (native is never called; the polyfill overrides it). The older tests still pass.

- [ ] **Step 4: Implement.** In `pointerlock-polyfill.js`, right after the `post` constant, add:

```js
  // WebKit on iPadOS 26 has no pointer lock API. If a future WebKit has one,
  // try it first and fall back to ours when it refuses or never locks.
  const NATIVE_FALLBACK_MS = 250;
  const native = {
    request: Element.prototype.requestPointerLock,
    exit: Document.prototype.exitPointerLock,
    element: Object.getOwnPropertyDescriptor(Document.prototype, "pointerLockElement")?.get,
  };
  let nativeUsable = typeof native.request === "function";
  let nativeLocked = false;
  let nativePending = null; // { el, promise } while an attempt runs
  const nativeElement = () => {
    try { return native.element ? native.element.call(document) : null; } catch (_) { return null; }
  };
```

Change `setLocked`'s post line to `post({ type: el ? "lock" : "unlock", mode: "polyfill" });`.

Replace `requestPointerLock` and `exitPointerLock` with:

```js
  function requestPointerLock(options) {
    const el = this;
    if (!(el instanceof Element) || !el.isConnected) {
      setTimeout(() => dispatchDocEvent("pointerlockerror"), 0);
      return Promise.reject(new DOMException("Element is not in a document", "WrongDocumentError"));
    }
    if (nativePending && nativePending.el === el) return nativePending.promise;
    if (nativeUsable) return requestNative(el, options);
    setLocked(el);
    return Promise.resolve();
  }

  function requestNative(el, options) {
    const promise = new Promise((resolve, reject) => {
      let done = false;
      const finish = (ok) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        window.removeEventListener("pointerlockchange", onChange, true);
        window.removeEventListener("pointerlockerror", onError, true);
        nativePending = null;
        if (!el.isConnected) {
          reject(new DOMException("Element is not in a document", "WrongDocumentError"));
          return;
        }
        if (ok) {
          nativeLocked = true;
          post({ type: "lock", mode: "native" });
        } else {
          nativeUsable = false; // this page uses the polyfill from now on
          setLocked(el);
        }
        resolve();
      };
      const onChange = () => { if (nativeElement() === el) finish(true); };
      const onError = (e) => { e.stopImmediatePropagation(); finish(false); };
      window.addEventListener("pointerlockchange", onChange, true);
      window.addEventListener("pointerlockerror", onError, true);
      const timer = setTimeout(() => finish(nativeElement() === el), NATIVE_FALLBACK_MS);
      try {
        const p = native.request.call(el, options);
        if (p && typeof p.then === "function") p.then(() => { if (nativeElement() === el) finish(true); }, () => finish(false));
      } catch (_) {
        finish(false);
      }
    });
    nativePending = { el, promise };
    return promise;
  }

  // The page learns about native lock changes from WebKit's own events; the
  // app hears it here.
  document.addEventListener("pointerlockchange", () => {
    if (nativeLocked && !nativeElement()) {
      nativeLocked = false;
      post({ type: "unlock", mode: "native" });
    }
  }, true);

  const unlockAll = () => {
    if (nativeLocked && native.exit) native.exit.call(document);
    setLocked(null);
  };

  function exitPointerLock() {
    unlockAll();
  }
```

In `pointerLockElementGetter.get`, first line: `if (nativeLocked) { const n = nativeElement(); if (n) return n.ownerDocument === this ? n : null; }`.

Replace `setLocked(null)` in the hold-Esc handler (near line 316) and in `api.forceUnlock` with `unlockAll()`. Change `api.isLocked` to `return !!lockedElement || nativeLocked;`.

- [ ] **Step 5: Run the tests.** Run: `tools/test.sh js`. Expected: all pass, including the six new ones.

- [ ] **Step 6: Commit.**

```bash
git add Apps/PointerLocker/Resources/pointerlock-polyfill.js tests/polyfill.test.mjs
git commit -m "Polyfill: try WebKit's own pointer lock first, fall back in 250 ms

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The app follows the lock path

**Files:**
- Create: `Apps/PointerLocker/Health/LockMessage.swift`
- Modify: `Apps/PointerLocker/BrowserViewController.swift` (`userContentController(_:didReceive:)`, `setPageLock`)
- Test: `tests/PointerLockerTests/LockMessageTests.swift`

**Interfaces:**
- Consumes: Task 1's `{type, mode}` messages.
- Produces: `struct LockMessage { let locked: Bool; let native: Bool; init?(_ body: [String: Any]) }`; `BrowserViewController.lastLockMode: String?` ("native"/"polyfill", nil before the first lock), used by Task 7.

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
@testable import PointerLocker

final class LockMessageTests: XCTestCase {
    func testPolyfillLockDrivesTheMouseBridge() {
        XCTAssertEqual(LockMessage(["type": "lock", "mode": "polyfill"]), LockMessage(locked: true, native: false))
    }

    func testNativeLockLeavesTheMouseToWebKit() {
        XCTAssertEqual(LockMessage(["type": "lock", "mode": "native"]), LockMessage(locked: true, native: true))
        XCTAssertEqual(LockMessage(["type": "unlock", "mode": "native"]), LockMessage(locked: false, native: true))
    }

    func testOlderMessagesWithoutModeMeanPolyfill() {
        XCTAssertEqual(LockMessage(["type": "lock"]), LockMessage(locked: true, native: false))
    }

    func testOtherMessagesAreNotLockMessages() {
        XCTAssertNil(LockMessage(["type": "health"]))
        XCTAssertNil(LockMessage([:]))
    }
}
```

- [ ] **Step 2: Run to see it fail.** Run: `tools/test.sh swift -only-testing:PointerLockerTests/LockMessageTests`. Expected: build error, `LockMessage` not found.

- [ ] **Step 3: Implement.**

```swift
/// A lock change from the polyfill: which way, and whether WebKit's own
/// pointer lock holds it (then WebKit delivers mouse movement, not MouseBridge).
struct LockMessage: Equatable {
    let locked: Bool
    let native: Bool

    init(locked: Bool, native: Bool) {
        self.locked = locked
        self.native = native
    }

    init?(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "lock": locked = true
        case "unlock": locked = false
        default: return nil
        }
        native = body["mode"] as? String == "native"
    }
}
```

In `BrowserViewController`: add `private(set) var lastLockMode: String?`. Replace the `switch type` in `userContentController(_:didReceive:)` with:

```swift
        if let lock = LockMessage(body) {
            setPageLock(lock.locked, native: lock.native)
            return
        }
        switch type {
        default: break
        }
```

Change `setPageLock` to `private func setPageLock(_ locked: Bool, native: Bool = false)`, and inside it replace `bridge.isActive = locked` with:

```swift
        bridge.isActive = locked && !native
        if locked { lastLockMode = native ? "native" : "polyfill" }
```

- [ ] **Step 4: Run the tests.** Run: `tools/test.sh`. Expected: all Swift and JS tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Apps/PointerLocker/Health/LockMessage.swift Apps/PointerLocker/BrowserViewController.swift tests/PointerLockerTests/LockMessageTests.swift
git commit -m "MouseBridge stays idle while WebKit's own lock holds the pointer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Health checks in the page

**Files:**
- Create: `Apps/PointerLocker/Resources/health-checks.js`
- Create: `tests/health-checks.test.mjs`
- Modify: `package.json` (`"test"` runs both test files)

**Interfaces:**
- Consumes: `window.__mouselookHealth = { checks: string[], phase: () => number, desktopClientOkAfterMs?, lockWaitMs?, scrubWaitMs? }` set before the script (Task 4 generates it).
- Produces: messages `{type: "health", check: "desktop-client" | "lock-on-click" | "scrub-lock", result: "ok" | "problem", code: string}`.

- [ ] **Step 1: Write the failing tests** in `tests/health-checks.test.mjs`:

```js
// Health checks observe a page and report once per check per page load.
//   npm test
import { chromium } from "playwright";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const read = (f) => readFileSync(new URL(`../Apps/PointerLocker/Resources/${f}`, import.meta.url), "utf8");
const polyfill = read("pointerlock-polyfill.js");
const checks = read("health-checks.js");
const stub = `
  window.__messages = [];
  window.webkit = { messageHandlers: { pointerLocker: { postMessage: (m) => window.__messages.push(m) } } };
`;
// Like iPadOS 26: no native pointer lock, so the polyfill path is deterministic.
const noNativeLock = `
  for (const [proto, names] of [
    [Element.prototype, ["requestPointerLock", "webkitRequestPointerLock"]],
    [Document.prototype, ["exitPointerLock", "webkitExitPointerLock", "pointerLockElement",
                          "webkitPointerLockElement", "onpointerlockchange", "onpointerlockerror"]],
  ]) for (const n of names) delete proto[n];
`;
const browser = await chromium.launch();
let failures = 0;
async function test(name, fn) {
  try { await fn(); console.log(`ok   ${name}`); }
  catch (e) { failures++; console.log(`FAIL ${name}\n     ${e.message}`); }
}
const health = (p) => p.evaluate(() => window.__messages.filter((m) => m.type === "health"));
const open = async (html, config) => {
  const p = await browser.newPage();
  await p.addInitScript({ content: noNativeLock + stub });
  await p.addInitScript({ content: polyfill });
  await p.addInitScript({ content: `window.__mouselookHealth = ${config};` + checks });
  await p.goto("data:text/html," + encodeURIComponent(html));
  return p;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

await test("desktop-client: the iPad flow is a problem", async () => {
  const p = await open(`<p>Tap Share, then Add to Home Screen</p>`,
    `{ checks: ["desktop-client"], phase: () => 0, desktopClientOkAfterMs: 300 }`);
  await wait(400);
  assert.deepEqual(await health(p), [{ type: "health", check: "desktop-client", result: "problem", code: "ipad-flow" }]);
  await p.close();
});

await test("desktop-client: iPad flow appearing later is caught", async () => {
  const p = await open(`<main></main>`, `{ checks: ["desktop-client"], phase: () => 0, desktopClientOkAfterMs: 1500 }`);
  await p.evaluate(() => setTimeout(() => { document.querySelector("main").textContent = "Add to Home Screen"; }, 100));
  await wait(900);
  assert.equal((await health(p))[0]?.result, "problem");
  await p.close();
});

await test("desktop-client: no iPad flow means ok after the wait", async () => {
  const p = await open(`<main>Library</main>`, `{ checks: ["desktop-client"], phase: () => 0, desktopClientOkAfterMs: 300 }`);
  await wait(400);
  assert.deepEqual(await health(p), [{ type: "health", check: "desktop-client", result: "ok", code: "desktop" }]);
  await p.close();
});

const stream = `<video style="width:300px;height:200px;display:block"></video>`;
await test("lock-on-click: two clicks on the stream without a lock request is a problem", async () => {
  const p = await open(stream, `{ checks: ["lock-on-click"], phase: () => 2, lockWaitMs: 100 }`);
  await p.mouse.click(50, 50); await wait(150);
  assert.deepEqual(await health(p), [], "one miss is not enough");
  await p.mouse.click(60, 60); await wait(150);
  assert.deepEqual(await health(p), [{ type: "health", check: "lock-on-click", result: "problem", code: "no-request" }]);
  await p.close();
});

await test("lock-on-click: a lock request while streaming is ok, and ok wins", async () => {
  const p = await open(stream, `{ checks: ["lock-on-click"], phase: () => 2, lockWaitMs: 100 }`);
  await p.evaluate(() => document.querySelector("video").addEventListener("click", (e) => e.target.requestPointerLock()));
  await p.mouse.click(50, 50); await wait(150);
  await p.evaluate(() => { document.querySelector("video").replaceWith(document.querySelector("video").cloneNode()); window.__pointerLocker.forceUnlock(); });
  await p.mouse.click(50, 50); await wait(150);
  await p.mouse.click(60, 60); await wait(150);
  assert.deepEqual(await health(p), [{ type: "health", check: "lock-on-click", result: "ok", code: "locked" }]);
  await p.close();
});

await test("lock-on-click: clicks outside a stream don't count", async () => {
  const p = await open(stream, `{ checks: ["lock-on-click"], phase: () => 0, lockWaitMs: 100 }`);
  await p.mouse.click(50, 50); await wait(150);
  await p.mouse.click(60, 60); await wait(150);
  assert.deepEqual(await health(p), []);
  await p.close();
});

const scrub = `<div class="scrubbable_control--x"><span id="label" style="display:inline-block;width:40px;height:20px">W</span></div>`;
await test("scrub-lock: a scrub without a lock request is a problem", async () => {
  const p = await open(scrub, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(30, 10, { steps: 5 });
  await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), [{ type: "health", check: "scrub-lock", result: "problem", code: "no-request" }]);
  await p.close();
});

await test("scrub-lock: a scrub that locks is ok", async () => {
  const p = await open(scrub, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.evaluate(() => document.getElementById("label").addEventListener("pointerdown", (e) => e.target.requestPointerLock()));
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(30, 10, { steps: 5 });
  await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), [{ type: "health", check: "scrub-lock", result: "ok", code: "locked" }]);
  await p.close();
});

await test("scrub-lock: a tiny wiggle or a press elsewhere doesn't count", async () => {
  const p = await open(scrub + `<p style="height:100px">text</p>`, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(12, 11); await wait(150); await p.mouse.up();
  await p.mouse.move(10, 80); await p.mouse.down(); await p.mouse.move(60, 80, { steps: 5 }); await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), []);
  await p.close();
});

await test("a check that throws doesn't break the page or other checks", async () => {
  const p = await open(`<main>Library</main>`,
    `{ checks: ["desktop-client"], get phase() { throw new Error("boom"); }, desktopClientOkAfterMs: 200 }`);
  await wait(300);
  assert.equal((await health(p))[0]?.result, "ok");
  assert.equal(await p.evaluate(() => typeof window.__pointerLocker.batch), "function");
  await p.close();
});

await test("checks don't change the page", async () => {
  const p = await open(`<main>Library</main>`, `{ checks: ["desktop-client"], phase: () => 0, desktopClientOkAfterMs: 100 }`);
  const before = await p.evaluate(() => document.documentElement.outerHTML);
  await wait(200);
  assert.equal(await p.evaluate(() => document.documentElement.outerHTML), before);
  await p.close();
});

await browser.close();
if (failures) { console.log(`\n${failures} test(s) failed`); process.exit(1); }
console.log("\nall health check tests passed");
```

In `package.json`, set `"test": "node tests/polyfill.test.mjs && node tests/health-checks.test.mjs"`.

- [ ] **Step 2: Run to see them fail.** Run: `tools/test.sh js`. Expected: FAIL, `health-checks.js` not found (ENOENT).

- [ ] **Step 3: Implement** `Apps/PointerLocker/Resources/health-checks.js`:

```js
// Mouselook health checks. Each check watches the page for one sign that a
// service changed how it treats this browser, and reports once per page load:
//   page -> native: {type: "health", check, result: "ok" | "problem", code}
// Checks only observe: they never change the page or stop its events.
// Set by the app before this script (HealthCheck.swift):
//   window.__mouselookHealth = { checks: [...ids], phase: () => 0 | 1 | 2 }
(() => {
  "use strict";
  const config = window.__mouselookHealth;
  if (!config || window.__mouselookHealthInstalled) return;
  window.__mouselookHealthInstalled = true;

  const reported = new Set();
  const report = (check, result, code) => {
    if (reported.has(check)) return; // once per check per page load
    reported.add(check);
    try {
      window.webkit.messageHandlers.pointerLocker.postMessage({ type: "health", check, result, code });
    } catch (_) {}
  };
  const phase = () => {
    try { return config.phase(); } catch (_) { return 0; }
  };

  // Every lock request, whichever path (WebKit's or the polyfill's) serves it.
  const lockListeners = [];
  for (const name of ["requestPointerLock", "webkitRequestPointerLock"]) {
    const original = Element.prototype[name];
    if (typeof original !== "function") continue;
    Object.defineProperty(Element.prototype, name, {
      configurable: true,
      writable: true,
      value: function (...args) {
        for (const listener of lockListeners) {
          try { listener(this); } catch (_) {}
        }
        return original.apply(this, args);
      },
    });
  }
  const onLockRequest = (listener) => lockListeners.push(listener);

  const checks = {
    // GeForce NOW: its iPad/touch flow means it didn't see a desktop browser.
    "desktop-client"() {
      const ipadFlow = /Add to Home Screen|partially supported/i;
      const seen = () => !!document.body && ipadFlow.test(document.body.innerText);
      let scheduled = false;
      const observer = new MutationObserver(() => {
        if (scheduled) return;
        scheduled = true;
        setTimeout(() => {
          scheduled = false;
          if (seen()) { observer.disconnect(); report("desktop-client", "problem", "ipad-flow"); }
        }, 500);
      });
      const start = () => {
        if (seen()) return report("desktop-client", "problem", "ipad-flow");
        observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
        setTimeout(() => {
          observer.disconnect();
          if (seen()) report("desktop-client", "problem", "ipad-flow");
          else report("desktop-client", "ok", "desktop");
        }, config.desktopClientOkAfterMs ?? 10000);
      };
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
      else start();
    },

    // Play services: clicking into a playing stream should make the game ask
    // for the mouse. One miss is normal (menus); two in a row is not.
    "lock-on-click"() {
      let misses = 0;
      let waiting = null;
      onLockRequest(() => {
        if (waiting) { clearTimeout(waiting); waiting = null; }
        misses = 0;
        if (phase() === 2) report("lock-on-click", "ok", "locked");
      });
      window.addEventListener("pointerdown", (e) => {
        if (!e.isTrusted || e.button !== 0 || e.pointerType === "touch") return;
        if (waiting || document.pointerLockElement || phase() !== 2) return;
        const onVideo = document.elementsFromPoint(e.clientX, e.clientY).some((el) => el.tagName === "VIDEO");
        if (!onVideo) return;
        waiting = setTimeout(() => {
          waiting = null;
          misses += 1;
          if (misses >= 2) report("lock-on-click", "problem", "no-request");
        }, config.lockWaitMs ?? 2000);
      }, true);
    },

    // Figma: dragging a number's scrub label should request the lock.
    "scrub-lock"() {
      let press = null;
      window.addEventListener("pointerdown", (e) => {
        if (!e.isTrusted || e.button !== 0 || e.pointerType === "touch") { press = null; return; }
        const onScrub = e.target instanceof Element && e.target.closest('[class*="scrubbable"]');
        press = onScrub ? { x: e.clientX, y: e.clientY, requested: false, timer: null } : null;
      }, true);
      onLockRequest(() => {
        if (!press) return;
        press.requested = true;
        clearTimeout(press.timer);
        report("scrub-lock", "ok", "locked");
      });
      window.addEventListener("pointermove", (e) => {
        const p = press;
        if (!p || p.timer || p.requested) return;
        if (Math.hypot(e.clientX - p.x, e.clientY - p.y) <= 3) return;
        p.timer = setTimeout(() => {
          if (!p.requested) report("scrub-lock", "problem", "no-request");
        }, config.scrubWaitMs ?? 500);
      }, true);
    },
  };

  for (const id of config.checks || []) {
    try { checks[id] && checks[id](); } catch (_) {}
  }
})();
```

- [ ] **Step 4: Run the tests.** Run: `tools/test.sh js`. Expected: both JS files pass.

- [ ] **Step 5: Commit.**

```bash
git add Apps/PointerLocker/Resources/health-checks.js tests/health-checks.test.mjs package.json
git commit -m "Health checks: desktop client, lock on click, scrub lock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Profiles declare their checks; the app injects them

**Files:**
- Create: `Apps/PointerLocker/Health/HealthCheck.swift`
- Modify: `Apps/PointerLocker/Services/ServiceProfile.swift`, `GeForceNowProfile.swift`, `FigmaProfile.swift`, `Apps/PointerLocker/WebViewFactory.swift`
- Test: `tests/PointerLockerTests/HealthCheckTests.swift`

**Interfaces:**
- Consumes: Task 3's check ids and `window.__mouselookHealth` shape.
- Produces:
  - `enum HealthCheckID: String, CaseIterable { case desktopClient = "desktop-client", lockOnClick = "lock-on-click", scrubLock = "scrub-lock" }` with `var title: String` and `var problemMessage: String`.
  - `ServiceProfile.healthChecks: [HealthCheckID]` (the profile's own) and `ServiceProfile.allHealthChecks: [HealthCheckID]` (own + `.lockOnClick` for Play).
  - `ServiceProfile.healthConfigScript: String`.

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
@testable import PointerLocker

final class HealthCheckTests: XCTestCase {
    func testEachServiceRunsItsChecks() {
        XCTAssertEqual(ServiceProfile.geforceNow.allHealthChecks, [.desktopClient, .lockOnClick])
        XCTAssertEqual(ServiceProfile.figma.allHealthChecks, [.scrubLock])
        XCTAssertEqual(ServiceProfile.generic.allHealthChecks, [.lockOnClick], "every Play service checks lock on click")
    }

    func testThePageConfigNamesTheChecksAndReadsTheSessionPhase() {
        let script = ServiceProfile.geforceNow.healthConfigScript
        XCTAssertTrue(script.hasPrefix(#"window.__mouselookHealth={checks:["desktop-client","lock-on-click"],phase:()=>("#), script)
        XCTAssertTrue(script.contains("remote-video"), "uses the profile's session phase")
        XCTAssertTrue(script.hasSuffix(")};"))
    }

    func testToastsSayWhatHappened() {
        XCTAssertEqual(HealthCheckID.desktopClient.problemMessage,
                       "GeForce NOW didn't load its desktop version, so the mouse may not lock. Updating Mouselook usually fixes this.")
        XCTAssertEqual(HealthCheckID.lockOnClick.problemMessage,
                       "The game didn't ask for the mouse. Click into the game again, or check Settings ▸ Advanced.")
        XCTAssertEqual(HealthCheckID.scrubLock.problemMessage,
                       "Figma didn't lock the pointer while you dragged, so values stop at the screen edge.")
    }
}
```

- [ ] **Step 2: Run to see it fail.** Run: `tools/test.sh swift -only-testing:PointerLockerTests/HealthCheckTests`. Expected: build error, `HealthCheckID` not found.

- [ ] **Step 3: Implement** `Apps/PointerLocker/Health/HealthCheck.swift`:

```swift
import Foundation

/// A check that watches a service's page for one sign that it changed how it
/// treats this browser (health-checks.js implements them).
enum HealthCheckID: String, CaseIterable {
    case desktopClient = "desktop-client"
    case lockOnClick = "lock-on-click"
    case scrubLock = "scrub-lock"

    /// Settings ▸ Advanced ▸ Service checks.
    var title: String {
        switch self {
        case .desktopClient: "Desktop version loads"
        case .lockOnClick: "Game asks for the mouse"
        case .scrubLock: "Scrubbing locks the pointer"
        }
    }

    /// The toast shown the first time the check finds a problem in a session.
    var problemMessage: String {
        switch self {
        case .desktopClient:
            "GeForce NOW didn't load its desktop version, so the mouse may not lock. Updating Mouselook usually fixes this."
        case .lockOnClick:
            "The game didn't ask for the mouse. Click into the game again, or check Settings ▸ Advanced."
        case .scrubLock:
            "Figma didn't lock the pointer while you dragged, so values stop at the screen edge."
        }
    }
}

extension ServiceProfile {
    /// The profile's own checks plus the ones its category shares.
    var allHealthChecks: [HealthCheckID] {
        healthChecks + (category == .play ? [.lockOnClick] : [])
    }

    /// Injected before health-checks.js: which checks to run, and how to read
    /// the session phase (a function literal, so no eval under a page's CSP).
    var healthConfigScript: String {
        let ids = allHealthChecks.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        return "window.__mouselookHealth={checks:[\(ids)],phase:()=>(\(sessionPhaseScript))};"
    }
}
```

In `ServiceProfile.swift` add after `category`:

```swift
    /// Checks specific to this service (Play services also run lock-on-click).
    let healthChecks: [HealthCheckID]
```

and `healthChecks: [],` to `generic` after `category: .play` (keep argument order: `wording:`, `category:`, `healthChecks:`). In `GeForceNowProfile.swift` add `healthChecks: [.desktopClient]` after `category: .play`; in `FigmaProfile.swift` add `healthChecks: [.scrubLock]` after `category: .create`.

In `WebViewFactory.installUserScripts`, replace the polyfill `addUserScript` line with:

```swift
        let profile = ServiceProfile.current
        var source = profile.pageConfigScript(useIdentity: Settings.useServiceIdentity) + polyfill
        if let checks = resource("health-checks") {
            source += "\n" + profile.healthConfigScript + checks
        }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
```

(and remove the now-unused `let config = …` line).

- [ ] **Step 4: Run the tests.** Run: `tools/test.sh`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Apps/PointerLocker/Health/HealthCheck.swift Apps/PointerLocker/Services Apps/PointerLocker/WebViewFactory.swift tests/PointerLockerTests/HealthCheckTests.swift
git commit -m "Profiles declare their health checks; the page gets them after the polyfill

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Diagnostics log

**Files:**
- Create: `Apps/PointerLocker/Health/DiagnosticsLog.swift`
- Test: `tests/PointerLockerTests/DiagnosticsLogTests.swift`

**Interfaces:**
- Produces: `struct DiagnosticsEntry: Codable, Equatable { let date: Date; let kind: String; let detail: String }`; `final class DiagnosticsLog { static let shared: DiagnosticsLog; static let capacity = 200; static let maxDetailLength = 200; init(fileURL: URL); private(set) var entries: [DiagnosticsEntry]; func record(_ kind: String, _ detail: String, at date: Date = Date()) }`.

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
@testable import PointerLocker

final class DiagnosticsLogTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID()).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testKeepsTheNewest200() {
        let log = DiagnosticsLog(fileURL: url)
        for i in 0..<250 { log.record("check", "entry \(i)") }
        XCTAssertEqual(log.entries.count, 200)
        XCTAssertEqual(log.entries.first?.detail, "entry 50")
        XCTAssertEqual(log.entries.last?.detail, "entry 249")
    }

    func testSurvivesARelaunch() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        DiagnosticsLog(fileURL: url).record("lock", "native", at: date)
        XCTAssertEqual(DiagnosticsLog(fileURL: url).entries, [DiagnosticsEntry(date: date, kind: "lock", detail: "native")])
    }

    func testAnUnreadableFileStartsEmpty() throws {
        try Data("not json".utf8).write(to: url)
        let log = DiagnosticsLog(fileURL: url)
        XCTAssertEqual(log.entries, [])
        log.record("service", "figma")
        XCTAssertEqual(DiagnosticsLog(fileURL: url).entries.map(\.detail), ["figma"])
    }

    func testLongDetailsAreTruncated() {
        let log = DiagnosticsLog(fileURL: url)
        log.record("check", String(repeating: "a", count: 5_000))
        XCTAssertEqual(log.entries.last?.detail.count, 200)
    }
}
```

- [ ] **Step 2: Run to see it fail.** Run: `tools/test.sh swift -only-testing:PointerLockerTests/DiagnosticsLogTests`. Expected: build error, `DiagnosticsLog` not found.

- [ ] **Step 3: Implement.**

```swift
import Foundation

struct DiagnosticsEntry: Codable, Equatable {
    let date: Date
    let kind: String
    let detail: String
}

/// The last 200 things worth knowing for a bug report: check results, which
/// lock path was used, service switches, failed loads. Host names only, never
/// page content or URL paths. Saved as JSON so it survives relaunches.
final class DiagnosticsLog {
    static let shared = DiagnosticsLog(fileURL: defaultURL)
    static let capacity = 200
    static let maxDetailLength = 200

    private(set) var entries: [DiagnosticsEntry]
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        entries = data.flatMap { try? JSONDecoder().decode([DiagnosticsEntry].self, from: $0) } ?? []
    }

    func record(_ kind: String, _ detail: String, at date: Date = Date()) {
        entries.append(DiagnosticsEntry(date: date, kind: kind, detail: String(detail.prefix(Self.maxDetailLength))))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        // A failed write keeps the entries in memory for this session.
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }

    private static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.json")
    }
}
```

- [ ] **Step 4: Run the tests.** Run: `tools/test.sh swift`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Apps/PointerLocker/Health/DiagnosticsLog.swift tests/PointerLockerTests/DiagnosticsLogTests.swift
git commit -m "Diagnostics log: last 200 entries on disk, host names only

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: HealthMonitor

**Files:**
- Create: `Apps/PointerLocker/Health/HealthMonitor.swift`
- Test: `tests/PointerLockerTests/HealthMonitorTests.swift`

**Interfaces:**
- Consumes: `HealthCheckID` (Task 4), `DiagnosticsLog` (Task 5).
- Produces:
  - `enum HealthResult: String { case ok, problem }`; `struct HealthStatus: Equatable { let result: HealthResult; let code: String; let date: Date }`.
  - `struct HealthRow: Equatable, Identifiable { let id: HealthCheckID; let title: String; let status: HealthStatus? }`.
  - `final class HealthMonitor { init(log: DiagnosticsLog, now: @escaping () -> Date = Date.init, showToast: @escaping (String) -> Void); private(set) var results: [HealthCheckID: HealthStatus]; func receive(check: String, result: String, code: String, host: String, locked: Bool); func lockReleased(); func resetSession(); func rows(for checks: [HealthCheckID]) -> [HealthRow] }`.

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
@testable import PointerLocker

final class HealthMonitorTests: XCTestCase {
    private var log: DiagnosticsLog!
    private var toasts: [String] = []
    private var monitor: HealthMonitor!
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        log = DiagnosticsLog(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("hm-\(UUID()).json"))
        toasts = []
        monitor = HealthMonitor(log: log, now: { [date] in date }) { [weak self] in self?.toasts.append($0) }
    }

    func testAProblemToastsOncePerSession() {
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        XCTAssertEqual(toasts, [HealthCheckID.scrubLock.problemMessage])
        XCTAssertEqual(monitor.results[.scrubLock], HealthStatus(result: .problem, code: "no-request", date: date))
    }

    func testOkIsRecordedWithoutAToast() {
        monitor.receive(check: "desktop-client", result: "ok", code: "desktop", host: "play.geforcenow.com", locked: false)
        XCTAssertEqual(toasts, [])
        XCTAssertEqual(monitor.results[.desktopClient]?.result, .ok)
        XCTAssertEqual(log.entries.last?.kind, "check")
        XCTAssertEqual(log.entries.last?.detail, "desktop-client ok desktop play.geforcenow.com")
    }

    func testAToastWaitsWhileThePointerIsLocked() {
        monitor.receive(check: "lock-on-click", result: "problem", code: "no-request", host: "play.geforcenow.com", locked: true)
        XCTAssertEqual(toasts, [])
        monitor.lockReleased()
        XCTAssertEqual(toasts, [HealthCheckID.lockOnClick.problemMessage])
        monitor.lockReleased()
        XCTAssertEqual(toasts.count, 1)
    }

    func testANewSessionCanToastAgain() {
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        monitor.resetSession()
        XCTAssertTrue(monitor.results.isEmpty)
        monitor.receive(check: "scrub-lock", result: "problem", code: "no-request", host: "www.figma.com", locked: false)
        XCTAssertEqual(toasts.count, 2)
    }

    func testSwitchingServiceDropsQueuedToast() {
        monitor.receive(check: "lock-on-click", result: "problem", code: "no-request", host: "play.geforcenow.com", locked: true)
        monitor.resetSession()
        monitor.lockReleased()
        XCTAssertEqual(toasts, [])
    }

    func testUnknownAndMalformedReportsAreIgnored() {
        monitor.receive(check: "made-up", result: "problem", code: "x", host: "evil.example", locked: false)
        monitor.receive(check: "scrub-lock", result: "maybe", code: "x", host: "www.figma.com", locked: false)
        XCTAssertEqual(toasts, [])
        XCTAssertTrue(monitor.results.isEmpty)
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testSettingsRowsFollowTheServicesChecks() {
        monitor.receive(check: "desktop-client", result: "ok", code: "desktop", host: "play.geforcenow.com", locked: false)
        let rows = monitor.rows(for: ServiceProfile.geforceNow.allHealthChecks)
        XCTAssertEqual(rows.map(\.id), [.desktopClient, .lockOnClick])
        XCTAssertEqual(rows[0].status?.result, .ok)
        XCTAssertNil(rows[1].status, "not run yet")
    }
}
```

- [ ] **Step 2: Run to see it fail.** Run: `tools/test.sh swift -only-testing:PointerLockerTests/HealthMonitorTests`. Expected: build error, `HealthMonitor` not found.

- [ ] **Step 3: Implement.**

```swift
import Foundation

enum HealthResult: String { case ok, problem }

struct HealthStatus: Equatable {
    let result: HealthResult
    let code: String
    let date: Date
}

/// Settings ▸ Advanced ▸ Service checks: one row per check.
struct HealthRow: Equatable, Identifiable {
    let id: HealthCheckID
    let title: String
    /// nil until the check has reported on this session's pages.
    let status: HealthStatus?
}

/// Collects health check results for one browser (one session: from opening a
/// service until switching service or relaunching). The first problem from a
/// check shows a toast; while the pointer is locked, the toast waits.
final class HealthMonitor {
    private(set) var results: [HealthCheckID: HealthStatus] = [:]
    private var toasted: Set<HealthCheckID> = []
    private var queued: [HealthCheckID] = []
    private let log: DiagnosticsLog
    private let now: () -> Date
    private let showToast: (String) -> Void

    init(log: DiagnosticsLog, now: @escaping () -> Date = Date.init, showToast: @escaping (String) -> Void) {
        self.log = log
        self.now = now
        self.showToast = showToast
    }

    /// A report from the page. Unknown checks or results are ignored: pages
    /// can post to the message handler too.
    func receive(check: String, result: String, code: String, host: String, locked: Bool) {
        guard let id = HealthCheckID(rawValue: check), let result = HealthResult(rawValue: result) else { return }
        results[id] = HealthStatus(result: result, code: code, date: now())
        log.record("check", "\(id.rawValue) \(result.rawValue) \(code) \(host)", at: now())
        guard result == .problem, toasted.insert(id).inserted else { return }
        if locked { queued.append(id) } else { showToast(id.problemMessage) }
    }

    func lockReleased() {
        let pending = queued
        queued.removeAll()
        pending.forEach { showToast($0.problemMessage) }
    }

    func resetSession() {
        results.removeAll()
        toasted.removeAll()
        queued.removeAll()
    }

    func rows(for checks: [HealthCheckID]) -> [HealthRow] {
        checks.map { HealthRow(id: $0, title: $0.title, status: results[$0]) }
    }
}
```

- [ ] **Step 4: Run the tests.** Run: `tools/test.sh swift`. Expected: all pass.

- [ ] **Step 5: Commit.**

```bash
git add Apps/PointerLocker/Health/HealthMonitor.swift tests/PointerLockerTests/HealthMonitorTests.swift
git commit -m "HealthMonitor: one toast per problem per session, held while locked

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Report, Settings and wiring

**Files:**
- Create: `Apps/PointerLocker/Health/DiagnosticsReport.swift`
- Modify: `Apps/PointerLocker/BrowserViewController.swift`, `Apps/PointerLocker/RootViewController.swift` (`showBrowser`), `Apps/PointerLocker/SettingsView.swift`
- Test: `tests/PointerLockerTests/DiagnosticsReportTests.swift`

**Interfaces:**
- Consumes: `HealthMonitor`, `HealthRow`, `DiagnosticsLog`, `DiagnosticsEntry`, `BrowserViewController.lastLockMode` (Task 2), `ServiceProfile.allHealthChecks` (Task 4).
- Produces: `enum DiagnosticsReport { static func text(appVersion: String, osVersion: String, webKitVersion: String, service: ServiceProfile, identity: BrowserIdentity, lockMode: String?, rows: [HealthRow], entries: [DiagnosticsEntry]) -> String }`; `SettingsView` gains `checks: [HealthRow]` and `onCopyDiagnostics: () -> Void`.

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
@testable import PointerLocker

final class DiagnosticsReportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func report() -> String {
        DiagnosticsReport.text(
            appVersion: "0.1.0 (1)", osVersion: "26.0", webKitVersion: "21622.1",
            service: .figma, identity: ServiceProfile.figma.identity, lockMode: "polyfill",
            rows: [HealthRow(id: .scrubLock, title: HealthCheckID.scrubLock.title,
                             status: HealthStatus(result: .problem, code: "no-request", date: date))],
            entries: [DiagnosticsEntry(date: date, kind: "service", detail: "figma")])
    }

    func testTheReportHasEverySection() {
        let text = report()
        for line in ["Mouselook diagnostics", "App: 0.1.0 (1)", "iPadOS: 26.0", "WebKit: 21622.1",
                     "Service: Figma (figma)", "Lock path: polyfill",
                     "Scrubbing locks the pointer: problem (no-request)", "service figma"] {
            XCTAssertTrue(text.contains(line), "missing \(line)")
        }
        XCTAssertTrue(text.contains("Chrome/"), "names the identity it presents")
    }

    func testNoAddressesInTheReport() {
        XCTAssertFalse(report().contains("://"))
    }

    func testChecksThatHaventRunSaySo() {
        let text = DiagnosticsReport.text(
            appVersion: "1", osVersion: "26.0", webKitVersion: "1", service: .geforceNow,
            identity: ServiceProfile.geforceNow.identity, lockMode: nil,
            rows: [HealthRow(id: .desktopClient, title: HealthCheckID.desktopClient.title, status: nil)], entries: [])
        XCTAssertTrue(text.contains("Desktop version loads: not run yet"))
        XCTAssertTrue(text.contains("Lock path: not locked yet"))
    }
}
```

- [ ] **Step 2: Run to see it fail.** Run: `tools/test.sh swift -only-testing:PointerLockerTests/DiagnosticsReportTests`. Expected: build error, `DiagnosticsReport` not found.

- [ ] **Step 3: Implement the report.**

```swift
import Foundation

/// What Settings ▸ Advanced ▸ Copy diagnostics puts on the clipboard.
enum DiagnosticsReport {
    static func text(appVersion: String, osVersion: String, webKitVersion: String,
                     service: ServiceProfile, identity: BrowserIdentity, lockMode: String?,
                     rows: [HealthRow], entries: [DiagnosticsEntry]) -> String {
        let time = ISO8601DateFormatter()
        var lines = [
            "Mouselook diagnostics",
            "App: \(appVersion)",
            "iPadOS: \(osVersion)",
            "WebKit: \(webKitVersion)",
            "Service: \(service.name) (\(service.id))",
            "Browser identity: \(identity.userAgent ?? "WebKit default")",
            "Lock path: \(lockMode ?? "not locked yet")",
            "",
            "Checks",
        ]
        for row in rows {
            if let status = row.status {
                lines.append("\(row.title): \(status.result.rawValue) (\(status.code)) at \(time.string(from: status.date))")
            } else {
                lines.append("\(row.title): not run yet")
            }
        }
        lines += ["", "Log"]
        lines += entries.map { "\(time.string(from: $0.date)) \($0.kind) \($0.detail)" }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Settings UI.** In `SettingsView`, add properties `let checks: [HealthRow]` and `let onCopyDiagnostics: () -> Void` (after `onClose`), `@State private var copied = false`, and a section after the Advanced section:

```swift
                Section {
                    ForEach(checks) { row in
                        LabeledContent(row.title) {
                            switch row.status?.result {
                            case .ok?: Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .problem?: Label("Problem", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            case nil: Text("Not run yet").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(copied ? "Copied" : "Copy diagnostics") {
                        onCopyDiagnostics()
                        copied = true
                    }
                } header: {
                    Text("Service checks")
                } footer: {
                    Text("Mouselook watches for signs that the service changed how it treats this browser. Diagnostics stay on this iPad until you copy them.")
                }
```

- [ ] **Step 5: Wire it up in `BrowserViewController`.**
  - Add `private lazy var health = HealthMonitor(log: .shared) { [weak self] message in self?.toast.show(message) }`.
  - In `userContentController(_:didReceive:)`, replace the empty `switch type` with:

```swift
        switch type {
        case "health":
            health.receive(check: body["check"] as? String ?? "", result: body["result"] as? String ?? "",
                           code: body["code"] as? String ?? "", host: webView.url?.host ?? "", locked: pageWantsLock)
        default: break
        }
```

  - In `setPageLock`, after `if locked { lastLockMode = … }` add `if locked { DiagnosticsLog.shared.record("lock", native ? "native" : "polyfill") } else { health.lockReleased() }`.
  - In `handleLoadError`, after `loadFailure = failure` add:

```swift
        let nsError = error as NSError
        DiagnosticsLog.shared.record("load-failure", "\(nsError.domain) \(nsError.code) \(failure.url?.host ?? "")")
```

  - In `tearDown()` add `health.resetSession()`.
  - In `showSettings()`, pass the new arguments to `SettingsView(...)` after `onClose:`:

```swift
            checks: health.rows(for: ServiceProfile.current.allHealthChecks),
            onCopyDiagnostics: { [weak self] in self?.copyDiagnostics() }
```

  - Add:

```swift
    private func copyDiagnostics() {
        let info = Bundle.main.infoDictionary ?? [:]
        let app = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let webKit = Bundle(for: WKWebView.self).infoDictionary?["CFBundleVersion"] as? String ?? "?"
        UIPasteboard.general.string = DiagnosticsReport.text(
            appVersion: app, osVersion: UIDevice.current.systemVersion, webKitVersion: webKit,
            service: .current, identity: WebViewFactory.identity, lockMode: lastLockMode,
            rows: health.rows(for: ServiceProfile.current.allHealthChecks),
            entries: DiagnosticsLog.shared.entries)
    }
```

  In `RootViewController.showBrowser()`, after creating the browser add `DiagnosticsLog.shared.record("service", ServiceProfile.current.id)`.

- [ ] **Step 6: Run everything.** Run: `tools/test.sh`. Expected: all Swift and JS tests pass.

- [ ] **Step 7: Commit.**

```bash
git add Apps/PointerLocker tests/PointerLockerTests/DiagnosticsReportTests.swift
git commit -m "Settings shows service checks; Copy diagnostics; log lock path, switches and failed loads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Check on the simulator and the iPad, README, PR

**Files:**
- Modify: `README.md` (Debugging section: service checks and Copy diagnostics)

- [ ] **Step 1: Simulator.** Build, install and open GeForce NOW. After 10 s, ⋯ ▸ Settings… ▸ Service checks shows "Desktop version loads: OK" and "Game asks for the mouse: Not run yet". Copy diagnostics, then read the clipboard with `xcrun simctl pbpaste booted`: expect the report with `Lock path: not locked yet`, and no `://`.
- [ ] **Step 2: Problem path.** Temporarily set `identity: .macSafari` in `FigmaProfile.swift`, open a Figma file on the iPad (a Debug build installed with `-allowProvisioningUpdates`), drag a number label: expect the `scrub-lock` toast once, ⚠︎ Problem in Settings. Revert the identity change (don't commit it).
- [ ] **Step 3: Normal path on the iPad.** Release build: GeForce NOW desktop client ✓ after 10 s; lock in a game, then ✓ for "Game asks for the mouse"; Figma scrub ✓; mouse-look and scrubbing work as before.
- [ ] **Step 4: README.** Under "### Debugging", add: "**Service checks.** Mouselook watches for signs that a service changed how it treats this browser (GeForce NOW loading its iPad version, a game never asking for the mouse, Figma not locking while you scrub) and says so once per session. ⋯ ▸ Settings… ▸ Service checks shows the results; Copy diagnostics puts a report with the app, iPadOS and WebKit versions, the lock path and the last 200 events on the clipboard. Nothing leaves the iPad unless you paste it somewhere."
- [ ] **Step 5: Final run and PR.** Run `tools/test.sh` (expected: all pass), commit the README, push `claude/hardening`, and open one PR to `main` describing both parts and the on-device results.

```bash
git add README.md
git commit -m "README: service checks and Copy diagnostics

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```
