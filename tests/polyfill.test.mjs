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

await test("removing the locked element releases the lock", async () => {
  await page.evaluate(() => document.getElementById("c").requestPointerLock());
  await page.evaluate(() => document.getElementById("c").remove());
  await tick();
  assert.equal(await page.evaluate(() => window.__pointerLocker.isLocked), false);
});

await test("maxTouchPoints is spoofed to 0", async () => {
  assert.equal(await page.evaluate(() => navigator.maxTouchPoints), 0);
});

await browser.close();
if (failures) {
  console.log(`\n${failures} test(s) failed`);
  process.exit(1);
}
console.log("\nall tests passed");
