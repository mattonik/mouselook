// Exercises pointerlock-polyfill.js in headless Chromium the way the iOS app
// drives it: stub the native message handler, call the page API, then feed
// events through window.__pointerLocker.batch().
//
//   npm install && npm test
import { chromium } from "playwright";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const polyfill = readFileSync(
  new URL("../Apps/PointerLocker/Resources/pointerlock-polyfill.js", import.meta.url),
  "utf8"
);

const stub = `
  window.__native = [];
  window.webkit = { messageHandlers: { pointerLocker: {
    postMessage: (m) => window.__native.push(m.type) } } };
`;

const browser = await chromium.launch();
const page = await browser.newPage();
await page.addInitScript({ content: stub });
await page.addInitScript({ content: polyfill });
await page.goto(`data:text/html,<canvas id="c" width="200" height="200"></canvas>`);

const tick = () => page.evaluate(() => new Promise((r) => setTimeout(r, 10)));
let failures = 0;
async function test(name, fn) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`FAIL ${name}\n     ${e.message}`);
  }
}

await page.evaluate(() => {
  window.__log = [];
  const c = document.getElementById("c");
  for (const t of ["pointermove", "mousemove", "pointerdown", "pointerup",
                   "mousedown", "mouseup", "click", "auxclick", "contextmenu", "wheel"]) {
    c.addEventListener(t, (e) => window.__log.push({
      t, dx: e.movementX, dy: e.movementY, button: e.button, buttons: e.buttons,
      trusted: e.isTrusted, deltaY: e.deltaY,
      coalesced: e.getCoalescedEvents ? e.getCoalescedEvents().length : null,
    }));
  }
  window.__changes = 0;
  document.onpointerlockchange = () => window.__changes++;
});

await test("not locked initially", async () => {
  assert.equal(await page.evaluate(() => document.pointerLockElement), null);
});

await test("events before lock are ignored", async () => {
  await page.evaluate(() => window.__pointerLocker.batch([["m", 5, 5]]));
  assert.equal(await page.evaluate(() => window.__log.length), 0);
});

await test("requestPointerLock locks, notifies native, fires onpointerlockchange", async () => {
  const res = await page.evaluate(async () => {
    const p = document.getElementById("c").requestPointerLock({ unadjustedMovement: true });
    await p;
    return document.pointerLockElement?.id;
  });
  await tick();
  assert.equal(res, "c");
  assert.deepEqual(await page.evaluate(() => window.__native), ["lock"]);
  assert.equal(await page.evaluate(() => window.__changes), 1);
  assert.equal(await page.evaluate(() => window.__pointerLocker.isLocked), true);
});

await test("movement produces pointermove + mousemove with movementX/Y", async () => {
  await page.evaluate(() => { window.__log = []; window.__pointerLocker.batch([["m", 12, -7]]); });
  const log = await page.evaluate(() => window.__log);
  assert.deepEqual(log.map((e) => e.t), ["pointermove", "mousemove"]);
  for (const e of log) { assert.equal(e.dx, 12); assert.equal(e.dy, -7); }
  assert.equal(log[0].coalesced, 1);
});

await test("left click: pointerdown/mousedown/pointerup/mouseup/click", async () => {
  await page.evaluate(() => { window.__log = []; window.__pointerLocker.batch([["b", 0, true], ["b", 0, false]]); });
  const log = await page.evaluate(() => window.__log);
  assert.deepEqual(log.map((e) => e.t), ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]);
  assert.equal(log[0].buttons, 1);
  assert.equal(log[3].buttons, 0);
});

await test("chorded right button is a pointermove, plus contextmenu/auxclick", async () => {
  await page.evaluate(() => {
    window.__log = [];
    window.__pointerLocker.batch([["b", 0, true], ["b", 2, true], ["b", 2, false], ["b", 0, false]]);
  });
  const types = await page.evaluate(() => window.__log.map((e) => e.t));
  assert.deepEqual(types, [
    "pointerdown", "mousedown",
    "pointermove", "mousedown", "contextmenu",
    "pointermove", "mouseup", "auxclick",
    "pointerup", "mouseup", "click",
  ]);
});

// GeForce NOW's locked-mode input reads mousedown/mouseup (one per button,
// chords included), so aim-and-fire needs a mousedown/mouseup per left click
// while right stays held.
await test("hold right to aim, click left twice to fire, release right", async () => {
  await page.evaluate(() => {
    window.__log = [];
    window.__pointerLocker.batch([
      ["b", 2, true],
      ["m", 3, 0],
      ["b", 0, true], ["b", 0, false],
      ["b", 0, true], ["b", 0, false],
      ["b", 2, false],
    ]);
  });
  const log = await page.evaluate(() => window.__log
    .filter((e) => e.t.startsWith("mouse") && e.t !== "mousemove" || e.t === "mousemove" && e.buttons)
    .map((e) => [e.t, e.button, e.buttons]));
  assert.deepEqual(log, [
    ["mousedown", 2, 2],
    ["mousemove", 0, 2],                        // aiming: right still held
    ["mousedown", 0, 3], ["mouseup", 0, 2],     // shot 1
    ["mousedown", 0, 3], ["mouseup", 0, 2],     // shot 2
    ["mouseup", 2, 0],
  ]);
});

await test("side buttons (back/forward) are buttons 3 and 4", async () => {
  await page.evaluate(() => {
    window.__log = [];
    window.__pointerLocker.batch([["b", 3, true], ["b", 4, true], ["b", 4, false], ["b", 3, false]]);
  });
  const log = await page.evaluate(() => window.__log.map((e) => [e.t, e.button, e.buttons]));
  assert.deepEqual(log, [
    ["pointerdown", 3, 8], ["mousedown", 3, 8],
    ["pointermove", 4, 24], ["mousedown", 4, 24],
    ["pointermove", 4, 8], ["mouseup", 4, 8], ["auxclick", 4, 8],
    ["pointerup", 3, 0], ["mouseup", 3, 0], ["auxclick", 3, 0],
  ]);
});

await test("duplicate button state is ignored", async () => {
  await page.evaluate(() => { window.__log = []; window.__pointerLocker.batch([["b", 0, false]]); });
  assert.equal(await page.evaluate(() => window.__log.length), 0);
});

await test("wheel", async () => {
  await page.evaluate(() => { window.__log = []; window.__pointerLocker.batch([["w", 0, 40]]); });
  const log = await page.evaluate(() => window.__log);
  assert.equal(log[0].t, "wheel");
  assert.equal(log[0].deltaY, 40);
});

await test("trusted mouse events are swallowed while locked", async () => {
  await page.evaluate(() => { window.__log = []; });
  await page.mouse.click(50, 50);
  assert.equal(await page.evaluate(() => window.__log.length), 0);
});

await test("holding Escape unlocks, tapping it does not", async () => {
  await page.keyboard.down("Escape");
  await page.keyboard.up("Escape");
  await page.waitForTimeout(1100);
  assert.equal(await page.evaluate(() => window.__pointerLocker.isLocked), true);
  await page.keyboard.down("Escape");
  await page.waitForTimeout(1100);
  await page.keyboard.up("Escape");
  await tick();
  assert.equal(await page.evaluate(() => document.pointerLockElement), null);
  assert.deepEqual(await page.evaluate(() => window.__native), ["lock", "unlock"]);
});

await test("trusted events flow again after unlock", async () => {
  await page.evaluate(() => { window.__log = []; });
  await page.mouse.click(60, 60);
  const types = await page.evaluate(() => window.__log.map((e) => e.t));
  assert.ok(types.includes("click"), types.join(","));
});

await test("forceUnlock and exitPointerLock", async () => {
  await page.evaluate(() => document.getElementById("c").requestPointerLock());
  await page.evaluate(() => window.__pointerLocker.forceUnlock());
  assert.equal(await page.evaluate(() => document.pointerLockElement), null);
  await page.evaluate(() => document.getElementById("c").requestPointerLock());
  await page.evaluate(() => document.exitPointerLock());
  assert.equal(await page.evaluate(() => document.pointerLockElement), null);
});

await test("unlocking with buttons held releases them first", async () => {
  const log = await page.evaluate(async () => {
    document.getElementById("c").requestPointerLock();
    window.__pointerLocker.batch([["b", 2, true], ["b", 0, true]]);
    window.__log = [];
    window.__pointerLocker.forceUnlock();
    return window.__log.map((e) => [e.t, e.button, e.buttons]);
  });
  // Released as the last of a chord: right first (a move), then left (up).
  assert.deepEqual(log.filter(([t]) => /up|move/.test(t)), [
    ["pointermove", 2, 1], ["mouseup", 2, 1],
    ["pointerup", 0, 0], ["mouseup", 0, 0],
  ]);
  assert.equal(log.some(([t]) => /click|contextmenu/.test(t)), false, "a forced release is not a click");
});

await test("held keys are released when the page loses focus", async () => {
  await page.evaluate(() => {
    window.__ups = [];
    document.addEventListener("keyup", (e) => window.__ups.push([e.code, e.key, e.keyCode]));
  });
  await page.keyboard.down("KeyW"); // real (trusted) key presses
  await page.keyboard.down("Shift");
  const ups = await page.evaluate(() => {
    window.dispatchEvent(new Event("blur"));
    window.dispatchEvent(new Event("blur")); // nothing left to release
    return window.__ups;
  });
  assert.deepEqual(ups, [["KeyW", "w", 87], ["ShiftLeft", "Shift", 16]]);
  await page.keyboard.up("Shift");
  await page.keyboard.up("KeyW");
});

await test("removing the locked element releases the lock", async () => {
  await page.evaluate(() => document.getElementById("c").requestPointerLock());
  await page.evaluate(() => document.getElementById("c").remove());
  await tick();
  assert.equal(await page.evaluate(() => window.__pointerLocker.isLocked), false);
});

await test("maxTouchPoints is spoofed to 0", async () => {
  assert.equal(await page.evaluate(() => navigator.maxTouchPoints), 0);
});

// Native element fullscreen moves the WKWebView out of the app's view
// controller (and back at 0x0), so the polyfill emulates it in-page.
await test("requestFullscreen is emulated: element fills the viewport, events fire", async () => {
  const r = await page.evaluate(async () => {
    document.body.insertAdjacentHTML("beforeend",
      `<main id="fs" style="width:50px;height:40px;margin:30px"><video id="v"></video></main>`);
    const el = document.getElementById("fs");
    const events = [];
    document.addEventListener("fullscreenchange", () => events.push(["fullscreenchange", document.fullscreenElement?.id]));
    document.addEventListener("webkitfullscreenchange", () => events.push(["webkitfullscreenchange"]));
    await el.requestFullscreen({ keyboardLock: "browser" }); // as GeForce NOW calls it
    await new Promise((res) => setTimeout(res, 20));
    const rect = el.getBoundingClientRect();
    return {
      events, enabled: document.fullscreenEnabled,
      el: document.fullscreenElement?.id, webkitEl: document.webkitFullscreenElement?.id,
      webkitIs: document.webkitIsFullScreen,
      rect: [rect.x, rect.y, rect.width, rect.height], viewport: [innerWidth, innerHeight],
    };
  });
  assert.equal(r.enabled, true);
  assert.equal(r.el, "fs");
  assert.equal(r.webkitEl, "fs");
  assert.equal(r.webkitIs, true);
  assert.deepEqual(r.rect, [0, 0, ...r.viewport]);
  assert.deepEqual(r.events, [["fullscreenchange", "fs"], ["webkitfullscreenchange"]]);
});

await test("exitFullscreen restores the element and clears fullscreenElement", async () => {
  const r = await page.evaluate(async () => {
    const el = document.getElementById("fs");
    await document.exitFullscreen();
    await new Promise((res) => setTimeout(res, 20));
    const rect = el.getBoundingClientRect();
    return { el: document.fullscreenElement, rect: [rect.width, rect.height] };
  });
  assert.equal(r.el, null);
  assert.deepEqual(r.rect, [50, 40]);
});

await test("removing the fullscreen element exits fullscreen", async () => {
  const r = await page.evaluate(async () => {
    const el = document.getElementById("fs");
    await el.requestFullscreen();
    el.remove();
    await new Promise((res) => setTimeout(res, 20));
    return document.fullscreenElement;
  });
  assert.equal(r, null);
});

// WKWebView in desktop mode reports "MacIntel" on the main thread but "iPad"
// inside workers, and GeForce NOW reads navigator.platform from a worker built
// from a Blob URL that it revokes right after construction. Chromium can't be
// made to report "iPad" in a worker, so the tests check that the worker's
// getter was replaced (not native) as well as the value it returns.
const workerPage = await browser.newPage();
await workerPage.addInitScript({ content: stub });
await workerPage.addInitScript({ content: polyfill });
await workerPage.route("https://pointerlocker.test/**", (r) =>
  r.fulfill({ contentType: "text/html", body: "<!doctype html><title>t</title>" }));
await workerPage.goto("https://pointerlocker.test/");

const platformFromWorker = (shared) => workerPage.evaluate((shared) => new Promise((resolve, reject) => {
  const probe = "[navigator.platform, !/\\[native code\\]/.test(" +
    "Object.getOwnPropertyDescriptor(WorkerNavigator.prototype, 'platform').get)]";
  const src = shared
    ? `onconnect = (e) => e.ports[0].postMessage(${probe});`
    : `postMessage(${probe});`;
  const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
  const w = shared ? new SharedWorker(url) : new Worker(url);
  URL.revokeObjectURL(url);
  const port = shared ? w.port : w;
  port.onmessage = (e) => resolve(e.data);
  w.onerror = () => reject(new Error("worker failed to start"));
  setTimeout(() => reject(new Error("worker timed out")), 2000);
}), shared);

await test("worker navigator.platform is spoofed to MacIntel", async () => {
  assert.deepEqual(await platformFromWorker(false), ["MacIntel", true]);
});

await test("shared worker navigator.platform is spoofed to MacIntel", async () => {
  assert.deepEqual(await platformFromWorker(true), ["MacIntel", true]);
});

await test("workers still run their own code", async () => {
  const r = await workerPage.evaluate(() => new Promise((resolve) => {
    const w = new Worker(URL.createObjectURL(new Blob(
      ["onmessage = (e) => postMessage(e.data * 2);"], { type: "text/javascript" })));
    w.onmessage = (e) => resolve(e.data);
    w.postMessage(21);
  }));
  assert.equal(r, 42);
});

// Debug overlay (debug-hud.js), injected after the polyfill when enabled.
const hud = readFileSync(
  new URL("../Apps/PointerLocker/Resources/debug-hud.js", import.meta.url), "utf8");
const hudPage = await browser.newPage();
await hudPage.addInitScript({ content: stub });
await hudPage.addInitScript({ content: polyfill });
await hudPage.addInitScript({ content: hud });
await hudPage.goto(`data:text/html,<canvas id="c" width="200" height="200"></canvas>`);
const hudText = () => hudPage.evaluate(async () => {
  window.__pointerLockerHUD.render();
  return document.getElementById("pointerlocker-hud").textContent;
});

await test("HUD tracks peer connections created by the page", async () => {
  const n = await hudPage.evaluate(() => {
    const pc = new RTCPeerConnection();
    return [pc instanceof RTCPeerConnection, window.__pointerLockerHUD.peerCount];
  });
  assert.deepEqual(n, [true, 1]);
});

await test("HUD shows native lock state and held buttons and keys as the page sees them", async () => {
  await hudPage.evaluate(async () => {
    window.__pointerLockerHUD.native({ pageLock: true, systemLock: false, mice: 1, rawRate: 250 });
    await document.getElementById("c").requestPointerLock();
    window.__pointerLocker.batch([["b", 2, true], ["b", 0, true], ["m", 5, 0]]);
    document.dispatchEvent(new KeyboardEvent("keydown", { code: "KeyW", bubbles: true }));
  });
  const text = await hudText();
  assert.match(text, /page ● +system ○ +mice 1/);
  assert.match(text, /raw 250\/s/);
  assert.match(text, /held L R/);
  assert.match(text, /keys KeyW/);
});

await test("HUD counts clicks per button and clears released ones", async () => {
  await hudPage.evaluate(() => {
    window.__pointerLocker.batch([["b", 0, false], ["b", 2, false], ["w", 0, 40]]);
    document.dispatchEvent(new KeyboardEvent("keyup", { code: "KeyW", bubbles: true }));
  });
  const text = await hudText();
  assert.match(text, /held -/);
  assert.match(text, /keys -/);
  assert.match(text, /clicks L1 M0 R1 B0 F0 +wheel 1/);
});

await browser.close();
if (failures) {
  console.log(`\n${failures} test(s) failed`);
  process.exit(1);
}
console.log("\nall tests passed");
