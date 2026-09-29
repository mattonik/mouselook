// Renders the App Store screenshots: each raw screen from store/raw/ under
// its caption from store/shots.json, at 2752 x 2064 (13-inch iPad, landscape),
// into store/out/. Uses the Playwright already installed for the tests.
//
//   node tools/app-store/render.mjs            # every shot with a raw file
//   node tools/app-store/render.mjs 03-menu    # just these
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const store = join(root, "store");
const out = join(store, "out");
const template = readFileSync(join(root, "tools/app-store/template.html"), "utf8");
const { shots } = JSON.parse(readFileSync(join(store, "shots.json"), "utf8"));
const only = process.argv.slice(2);

const escape = (text) => text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2752, height: 2064 }, deviceScaleFactor: 1 });

for (const shot of shots) {
  if (only.length && !only.includes(shot.id)) continue;
  const raw = join(store, "raw", shot.raw);
  if (!existsSync(raw)) {
    console.log(`skip ${shot.id}: no store/raw/${shot.raw}`);
    continue;
  }
  const html = template
    .replace("{{title}}", escape(shot.title))
    .replace("{{subtitle}}", escape(shot.subtitle ?? ""))
    .replace("{{screen}}", `data:image/png;base64,${readFileSync(raw).toString("base64")}`);
  await page.setContent(html, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  const png = join(out, `${shot.id}.png`);
  await page.screenshot({ path: png, type: "png" });
  // The App Store refuses images with an alpha channel: round-trip through BMP.
  const bmp = png.replace(/\.png$/, ".bmp");
  execFileSync("sips", ["-s", "format", "bmp", png, "--out", bmp], { stdio: "ignore" });
  execFileSync("sips", ["-s", "format", "png", bmp, "--out", png], { stdio: "ignore" });
  execFileSync("rm", [bmp]);
  console.log(`store/out/${shot.id}.png`);
}

await browser.close();
