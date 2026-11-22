// Serves dist/ as Cloudflare Pages does: /x is x.html, /x/ is x/index.html.
// Downloads (/dl/…) go to the real site's, so the buttons can be tried.
import { createServer } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("dist/", import.meta.url));
const port = Number(process.env.PORT || 4322);
const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json",
  ".svg": "image/svg+xml", ".png": "image/png", ".webp": "image/webp", ".woff2": "font/woff2", ".mp3": "audio/mpeg", ".wav": "audio/wav" };

// dl.baocode.dev lets only baocode.dev read its manifests: here they are
// read through this server.
const DL = "https://dl.baocode.dev/releases/";

// The headers _headers gives every page (/*), the policy above all, so
// what it would block on the site is blocked here too. Read each time, as
// build.mjs rewrites it.
function common() {
  const headers = {};
  const rules = readFileSync(join(root, "_headers"), "utf8").split(/\n\s*\n/).find((b) => /^\/\*\s*$/m.test(b)) ?? "";
  for (const [, name, value] of rules.matchAll(/^\s+([A-Za-z-]+):\s*(.+)$/gm)) {
    if (name !== "Strict-Transport-Security") headers[name] = value;
  }
  return headers;
}

createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (path.startsWith("/dl/")) { res.writeHead(302, { location: `https://baocode.dev${path}` }); return res.end(); }
  // The README's pictures: the home page in English, its window still at
  // the steps asked for (window.baoShot), the window alone on show.
  //   /__shots?usage=35&ide=20&mode=ide
  if (path === "/__shots") {
    const q = new URL(req.url, "http://x").searchParams;
    const html = readFileSync(join(root, "index.html"), "utf8").replace('<script src="/head.js"></script>',
      `<script src="/__shot.js?${q}"></script>\n  <script src="/head.js"></script>\n  <link rel="stylesheet" href="/__shot.css" />`);
    res.writeHead(200, { ...common(), "content-type": TYPES[".html"], "cache-control": "no-store" });
    return res.end(html);
  }
  if (path === "/__shot.js") {
    const q = new URL(req.url, "http://x").searchParams;
    const steps = Object.fromEntries(["usage", "ide"].filter((k) => q.has(k)).map((k) => [k, Number(q.get(k))]));
    res.writeHead(200, { "content-type": TYPES[".js"], "cache-control": "no-store" });
    return res.end(`window.baoShot = ${JSON.stringify(steps)};
try { localStorage.setItem("baocode.lang", "en"); } catch {}
addEventListener("load", () => {
  ${q.get("mode") === "ide" ? 'document.getElementById("tbToIde")?.click();' : ""}
  document.getElementById("ideCtxClose")?.click();
  document.getElementById("desktopWindow")?.scrollIntoView({ block: "center" });
});
`);
  }
  if (path === "/__shot.css") {
    res.writeHead(200, { "content-type": TYPES[".css"], "cache-control": "no-store" });
    return res.end(`.hdr { display: none !important; }
#baocodeWindowMount { opacity: 1 !important; transform: none !important; filter: none !important; transition: none !important; }
html { scroll-behavior: auto !important; }
`);
  }
  if (path.startsWith("/releases/")) {
    const r = await fetch(`https://dl.baocode.dev${path}`).catch(() => null);
    res.writeHead(r?.status || 502, { "content-type": "application/json", "cache-control": "no-store" });
    return res.end(r ? Buffer.from(await r.arrayBuffer()) : "");
  }
  const file = normalize(join(root, path));
  if (!file.startsWith(root)) { res.writeHead(403); return res.end(); }
  const pick = [file, `${file}.html`, join(file, "index.html")].find((f) => existsSync(f) && statSync(f).isFile());
  if (!pick) { res.writeHead(404); return res.end("404"); }
  res.writeHead(200, { ...common(), "content-type": TYPES[extname(pick)] || "application/octet-stream", "cache-control": "no-store" });
  const body = readFileSync(pick);
  res.end(pick.endsWith(".js") ? body.toString().replaceAll(DL, "/releases/") : body);
}).listen(port, () => console.log(`http://localhost:${port}/`));
