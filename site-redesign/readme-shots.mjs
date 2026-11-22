// The README's pictures of the window (readme/agent.webp, readme/ide.webp):
// the home page's window still on serve.mjs's /__shots, taken in headless
// Chrome at 2x. With serve.mjs running:
//
//   node readme-shots.mjs [<name>=<query> ...]
//
// A query is how many steps each conversation shows (usage=34, ide=21) and
// the mode (mode=ide); with none, the two pictures the README has.
import { execFileSync, spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const args = process.argv.slice(2);
const jobs = args.length ? args : ["agent=usage=34", "ide=ide=21&mode=ide"];
const out = new URL("readme/", import.meta.url).pathname;
const work = mkdtempSync(join(tmpdir(), "bao-readme-"));
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
  "--headless=new", "--remote-debugging-port=9333", `--user-data-dir=${work}`,
  "--hide-scrollbars", "--mute-audio", "--no-first-run", "about:blank",
], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch("http://127.0.0.1:9333/json")).json()).find((t) => t.type === "page"); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0;
const pending = new Map();
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}) => new Promise((r) => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); })
  .then((m) => { if (m.error) throw new Error(`${method}: ${m.error.message}`); return m.result; });
const run = async (expr) => (await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true })).result.value;

await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 1000, deviceScaleFactor: 2, mobile: false });
for (const job of jobs) {
  const [name, query] = job.split("=", 2).length === 2 ? [job.slice(0, job.indexOf("=")), job.slice(job.indexOf("=") + 1)] : [job, ""];
  await send("Page.navigate", { url: `http://localhost:4322/__shots?${query}` });
  await sleep(4000);
  const clip = await run(`(() => { const r = document.querySelector("#desktopWindow").getBoundingClientRect(); return { x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height, scale: 1 }; })()`);
  const { data } = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip });
  const png = join(work, `${name}.png`);
  writeFileSync(png, Buffer.from(data, "base64"));
  execFileSync("cwebp", ["-quiet", "-q", "88", "-m", "6", png, "-o", `${out}${name}.webp`]);
  console.log(`readme/${name}.webp`);
}
ws.close();
chrome.kill();
await sleep(500);
rmSync(work, { recursive: true, force: true });
