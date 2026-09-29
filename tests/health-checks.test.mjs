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
    `{ checks: ["desktop-client"], phase: () => 0, desktopClientPollMs: 50 }`);
  await wait(400);
  assert.deepEqual(await health(p), [{ type: "health", check: "desktop-client", result: "problem", code: "ipad-flow" }]);
  await p.close();
});

await test("desktop-client: iPad flow appearing later is caught", async () => {
  const p = await open(`<main></main>`, `{ checks: ["desktop-client"], phase: () => 0, desktopClientPollMs: 50 }`);
  await p.evaluate(() => setTimeout(() => { document.querySelector("main").textContent = "Add to Home Screen"; }, 100));
  await wait(900);
  assert.equal((await health(p))[0]?.result, "problem");
  await p.close();
});

await test("desktop-client: a session starting proves the desktop client", async () => {
  const p = await open(`<main>Knihovna</main>`, `{ checks: ["desktop-client"], phase: () => window.__phase || 0, desktopClientPollMs: 50 }`);
  await wait(150);
  assert.deepEqual(await health(p), [], "no English iPad text isn't proof of anything");
  await p.evaluate(() => { window.__phase = 1; });
  await wait(150);
  assert.deepEqual(await health(p), [{ type: "health", check: "desktop-client", result: "ok", code: "session" }]);
  await p.close();
});

await test("desktop-client: page text is only watched for a while; a session still proves the client", async () => {
  const p = await open(`<main></main>`,
    `{ checks: ["desktop-client"], phase: () => window.__phase || 0, desktopClientPollMs: 50, desktopClientWatchMs: 100 }`);
  await wait(300);
  await p.evaluate(() => { document.querySelector("main").textContent = "Add to Home Screen"; });
  await wait(700);
  assert.deepEqual(await health(p), [], "text after the watch window isn't read");
  await p.evaluate(() => { window.__phase = 1; });
  await wait(150);
  assert.deepEqual(await health(p), [{ type: "health", check: "desktop-client", result: "ok", code: "session" }]);
  await p.close();
});

await test("desktop-client: without a session or iPad text it stays unreported", async () => {
  const p = await open(`<main>Bibliothèque</main>`, `{ checks: ["desktop-client"], phase: () => 0, desktopClientPollMs: 50 }`);
  await wait(400);
  assert.deepEqual(await health(p), []);
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

await test("lock-on-click: misses far apart don't add up", async () => {
  const p = await open(stream, `{ checks: ["lock-on-click"], phase: () => 2, lockWaitMs: 50, lockMissWindowMs: 200 }`);
  await p.mouse.click(50, 50); await wait(400);
  await p.mouse.click(60, 60); await wait(100);
  assert.deepEqual(await health(p), [], "each miss is on its own");
  await p.mouse.click(70, 70); await wait(100);
  assert.deepEqual(await health(p), [{ type: "health", check: "lock-on-click", result: "problem", code: "no-request" }],
    "two close together still count");
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

await test("scrub-lock: letting go before the wait is up doesn't count", async () => {
  const p = await open(scrub, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(15, 10); await p.mouse.up();
  await wait(200);
  assert.deepEqual(await health(p), []);
  await p.close();
});

await test("scrub-lock: a tiny wiggle or a press elsewhere doesn't count", async () => {
  const p = await open(scrub + `<p style="height:100px">text</p>`, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(12, 11); await wait(150); await p.mouse.up();
  await p.mouse.move(10, 80); await p.mouse.down(); await p.mouse.move(60, 80, { steps: 5 }); await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), []);
  await p.close();
});

// Figma's newer X/Y fields: hashed class names, an ew-resize label next to the input.
const newScrub = `<div class="qw5a"><div id="label" class="_1rk7okh2 qw5m0k0" style="cursor:ew-resize;display:inline-block;width:40px;height:20px">X</div><input value="100"></div>`;
await test("scrub-lock: a new-style scrub label (resize cursor next to a number field) is recognised", async () => {
  const p = await open(newScrub, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(30, 10, { steps: 5 });
  await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), [{ type: "health", check: "scrub-lock", result: "problem", code: "no-request" }]);
  await p.close();
});

await test("scrub-lock: a resize handle without a number field doesn't count", async () => {
  const p = await open(`<div><div style="cursor:ew-resize;width:40px;height:20px"></div></div><p>panel</p>`,
    `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(10, 10); await p.mouse.down(); await p.mouse.move(30, 10, { steps: 5 });
  await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), []);
  await p.close();
});

await test("scrub-lock: a panel's resize handle doesn't count, even with number fields in the panel", async () => {
  const panel = `<div style="position:relative;height:600px"><div style="position:absolute;left:0;top:0;width:8px;height:600px;cursor:ew-resize"></div>`
    + `<div style="margin-left:20px"><input value="1"><input value="2"></div></div>`;
  const p = await open(panel, `{ checks: ["scrub-lock"], phase: () => 0, scrubWaitMs: 100 }`);
  await p.mouse.move(11, 100); await p.mouse.down(); await p.mouse.move(40, 100, { steps: 5 });
  await wait(150); await p.mouse.up();
  assert.deepEqual(await health(p), []);
  await p.close();
});

await test("a check that throws doesn't break the page or other checks", async () => {
  const p = await open(`<p>Tap Share, then Add to Home Screen</p>`,
    `{ checks: ["desktop-client"], get phase() { throw new Error("boom"); }, desktopClientPollMs: 50 }`);
  await wait(300);
  assert.equal((await health(p))[0]?.result, "problem");
  assert.equal(await p.evaluate(() => typeof window.__pointerLocker.batch), "function");
  await p.close();
});

await test("checks don't change the page", async () => {
  const p = await open(`<main>Library</main>`, `{ checks: ["desktop-client"], phase: () => 0, desktopClientPollMs: 50 }`);
  const before = await p.evaluate(() => document.documentElement.outerHTML);
  await wait(200);
  assert.equal(await p.evaluate(() => document.documentElement.outerHTML), before);
  await p.close();
});

await browser.close();
if (failures) { console.log(`\n${failures} test(s) failed`); process.exit(1); }
console.log("\nall health check tests passed");
