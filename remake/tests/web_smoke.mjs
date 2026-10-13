// Smoke test of the web export in headless Chromium (Playwright): serves remake/build/web, opens the
// game, chooses the language, starts a game, walks, and saves screenshots — desktop 16:10 with the
// keyboard, and a phone (touch) in landscape and portrait.
//     node remake/tests/web_smoke.mjs remake/build/web OUT_DIR
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require("playwright");
} catch {
  playwright = require(path.join(process.execPath, "../../lib/node_modules/playwright"));
}

const [root, out] = [process.argv[2] || "remake/build/web", process.argv[3] || "web-shots"];
fs.mkdirSync(out, { recursive: true });
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json" };
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(req.url.split("?")[0]).replace(/\/$/, "/index.html"));
  fs.readFile(p, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "Content-Type": types[path.extname(p)] || "application/octet-stream" });
    res.end(data);
  });
}).listen(0);
const url = `http://127.0.0.1:${server.address().port}/index.html`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await playwright.chromium.launch({
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
    "--autoplay-policy=no-user-gesture-required"],
});
const errors = [];

async function run(name, ctxOpts, steps) {
  const ctx = await browser.newContext(ctxOpts);
  const page = await ctx.newPage();
  page.on("console", (m) => { if (m.type() === "error") errors.push(`${name}: ${m.text()}`); });
  page.on("pageerror", (e) => errors.push(`${name}: ${e.message}`));
  await page.goto(url);
  await page.waitForSelector("canvas");
  await sleep(10000);
  await steps(page);
  await ctx.close();
}

await run("desktop", { viewport: { width: 1280, height: 800 } }, async (page) => {
  await page.screenshot({ path: `${out}/desktop_first.png` });
  await page.keyboard.press("Enter");             // Polski
  await sleep(1500);
  await page.screenshot({ path: `${out}/desktop_title.png` });
  await page.keyboard.press("Enter");             // nowa gra
  await sleep(2000);
  for (const k of ["ArrowRight", "ArrowRight", "ArrowDown"]) {
    await page.keyboard.press(k);
    await sleep(400);
  }
  await sleep(1500);
  await page.screenshot({ path: `${out}/desktop_game.png` });
  await page.keyboard.press("p");
  await sleep(800);
  await page.screenshot({ path: `${out}/desktop_pause.png` });
});

// wide screen: drop a level file on the page, play its first level with the side panels
await run("wide", { viewport: { width: 1600, height: 900 } }, async (page) => {
  await page.keyboard.press("Enter");             // Polski
  await sleep(1500);
  const level = "author: smoke test\r\n{\r\n*  $ !\r\n" + "\r\n".repeat(11) + "}\r\n";
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.items.add(new File([text], "SMOKE.HL"));
    document.dispatchEvent(new DragEvent("drop", { dataTransfer: dt, bubbles: true, cancelable: true }));
  }, level.repeat(3));
  await sleep(1500);
  await page.screenshot({ path: `${out}/wide_levels.png` });
  await page.keyboard.press("Enter");             // play level 1 of the file
  await sleep(2000);
  await page.screenshot({ path: `${out}/wide_game.png` });
});

const phone = { viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 };
await run("phone", phone, async (page) => {
  await page.touchscreen.tap(420, 200);           // first screen
  await sleep(1500);
  await page.screenshot({ path: `${out}/phone_title.png` });
  await page.touchscreen.tap(211, 8);             // nowa gra (picture 520x390 at x 162)
  await sleep(2500);
  await page.screenshot({ path: `${out}/phone_game.png` });
});

await run("portrait", { ...phone, viewport: { width: 390, height: 844 } }, async (page) => {
  await page.touchscreen.tap(195, 150);
  await sleep(1500);
  await page.screenshot({ path: `${out}/portrait_title.png` });
  await page.touchscreen.tap(37, 6);              // nowa gra (picture 390x292 at the top)
  await sleep(2500);
  await page.screenshot({ path: `${out}/portrait_game.png` });
});

await browser.close();
server.close();
if (errors.length) {
  console.log("errors:\n" + errors.join("\n"));
  process.exit(1);
}
console.log("web smoke test passed; screenshots in " + out);
