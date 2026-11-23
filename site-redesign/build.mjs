// Builds the redesigned site into dist/, a whole copy of site/ to replace it
// with: site/ as it is (its pages at the same addresses, its files), the
// new shared files over it, and the home page made from zcode-style.html in
// each language, / in English and /zh/ in Chinese.
//
//   node build.mjs          then   node serve.mjs   (http://localhost:4322)
//
// The template's words are in its #i18n block, both languages: an element
// with data-i18n="key" gets the key's words as its text, data-i18n-attr=
// "attr:key;…" its attributes'. The release's version and day, until
// site.js has read latest.json, are the ones site/'s own pages show.
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const site = join(here, "..", "site");
const dist = join(here, "dist");

rmSync(dist, { recursive: true, force: true });
cpSync(site, dist, { recursive: true });
// readme/: the README's pictures, served from here as GitHub is slow to
// show its own to many.
// Of assets/, the files the new pages name (the old drafts beside them name others).
const named = ["zcode-style.html", "flutter-window.js", "flutter-window.css", "style.css"].map((f) => readFileSync(join(here, f), "utf8")).join("\n");
const wanted = (src) => statSync(src).isDirectory() || named.includes(`assets/${relative(join(here, "assets"), src)}`);
for (const file of ["style.css", "site.js", "flutter-window.js", "flutter-window.css", "assets", "readme"]) {
  cpSync(join(here, file), join(dist, file), { recursive: true, filter: file === "assets" ? wanted : undefined });
}

const template = readFileSync(join(here, "zcode-style.html"), "utf8");
const block = /\s*<script type="application\/json" id="i18n">([\s\S]*?)<\/script>/;
const words = JSON.parse(template.match(block)[1]);
const page = template.replace(block, "");

const escapeText = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escapeAttr = (s) => escapeText(s).replace(/"/g, "&quot;");

// What site/'s pages show of the release, in each language.
const shown = (file, attr) => {
  const m = readFileSync(join(site, file), "utf8").match(new RegExp(`${attr}>([^<]*)<`));
  if (!m) throw new Error(`${file} has no ${attr}`);
  return m[1];
};
const release = {
  en: { "data-version": shown("index.html", "data-version"), "data-updated": shown("index.html", "data-updated"),
    "data-mobile-version": shown("download.html", "data-mobile-version"), "data-extension-version": shown("download.html", "data-extension-version") },
  zh: { "data-version": shown("zh/index.html", "data-version"), "data-updated": shown("zh/index.html", "data-updated"),
    "data-mobile-version": shown("zh/download.html", "data-mobile-version"), "data-extension-version": shown("zh/download.html", "data-extension-version") },
};

// The site's own pages, each at /<page> and /zh/<page>.
const PAGES = ["download", "changelog", "upstreams", "push", "browser-privacy", "mobile-privacy"];

function make(lang) {
  const dict = words[lang];
  const zh = lang === "zh";
  let html = page;
  const missing = new Set();

  html = html.replace(/<html lang="[^"]*">/, `<html lang="${zh ? "zh-CN" : "en"}">`);
  html = html.replace(/<title>[^<]*<\/title>/, `<title>${escapeText(dict.title)}</title>`);
  html = html.replace("<!-- build:head -->", [
    `<meta name="description" content="${escapeAttr(dict.metaDesc)}" />`,
    `  <link rel="alternate" hreflang="en" href="https://baocode.dev/" />`,
    `  <link rel="alternate" hreflang="zh" href="https://baocode.dev/zh/" />`,
  ].join("\n"));

  // Words: an element's text (it holds no other element), then attributes.
  html = html.replace(/(<([a-z0-9]+)\b[^>]*\bdata-i18n="([^"]+)"[^>]*>)([^<]*)(<\/\2>)/g, (all, open, tag, key, text, close) => {
    if (dict[key] === undefined) { missing.add(key); return all; }
    return open + escapeText(dict[key]) + close;
  });
  html = html.replace(/<[a-z0-9]+\b[^>]*\bdata-i18n-attr="([^"]+)"[^>]*>/g, (tag, spec) => {
    for (const pair of spec.split(";")) {
      const [attr, key] = pair.split(":");
      if (dict[key] === undefined) { missing.add(key); continue; }
      tag = tag.replace(new RegExp(`\\b${attr}="[^"]*"`), `${attr}="${escapeAttr(dict[key])}"`);
    }
    return tag;
  });
  if (missing.size) throw new Error(`${lang}: no words for ${[...missing].join(", ")}`);

  // The release as site/ shows it.
  for (const [attr, text] of Object.entries(release[lang])) {
    html = html.replace(new RegExp(`(\\b${attr}>)[^<]*(<)`, "g"), `$1${escapeText(text)}$2`);
  }

  // Links: home, the other language, and the site's pages in this one.
  html = html.replaceAll('href="/" data-home', `href="${zh ? "/zh/" : "/"}"`);
  html = html.replace(/<a class="pill-outline lang" href="\/" hreflang="en" lang="en" data-lang-link>/,
    zh ? '<a class="pill-outline lang" href="/" hreflang="en" lang="en">' : '<a class="pill-outline lang" href="/zh/" hreflang="zh" lang="zh-CN">');
  if (zh) html = html.replace(new RegExp(`href="/(${PAGES.join("|")})([#"])`, "g"), 'href="/zh/$1$2');

  return html;
}

// The site's Content-Security-Policy (_headers) takes the pages' scripts and
// styles only from files of its own: the home page's inline ones go to
// files under /home/, named by their content so they can be cached for good.
// Each build's own: those of builds before (site/ has them) go.
rmSync(join(dist, "home"), { recursive: true, force: true });
mkdirSync(join(dist, "home"), { recursive: true });
const hashed = (text, ext) => {
  const name = `/home/${createHash("sha256").update(text).digest("hex").slice(0, 10)}.${ext}`;
  writeFileSync(join(dist, name), text);
  return name;
};
function ownFiles(html) {
  html = html.replace(/<style>([\s\S]*?)<\/style>/g, (all, css) => `<link rel="stylesheet" href="${hashed(css, "css")}" />`);
  return html.replace(/<script>([\s\S]*?)<\/script>/g, (all, js) => `<script src="${hashed(js, "js")}"></script>`);
}

// The icons (iconify-icon), each the page or the window may show, put in
// before the element is defined (IconifyPreload): none is fetched from
// api.iconify.design as the page runs. Their names are written whole, as
// "prefix:name"; the window's file icons are micon('name').
async function icons() {
  const sources = [page, readFileSync(join(here, "flutter-window.js"), "utf8")].join("\n");
  const wanted = new Map();
  const want = (prefix, name) => (wanted.get(prefix) ?? wanted.set(prefix, new Set()).get(prefix)).add(name);
  for (const [, prefix, name] of sources.matchAll(/["'`]([a-z0-9]+(?:-[a-z0-9]+)*):([a-z0-9]+(?:-[a-z0-9]+)*)\\?["'`]/g)) want(prefix, name);
  for (const [, name] of sources.matchAll(/micon\('([a-z0-9-]+)'\)/g)) want("material-icon-theme", name);
  const sets = [];
  const missing = [];
  for (const [prefix, names] of wanted) {
    const res = await fetch(`https://api.iconify.design/${prefix}.json?icons=${[...names].join(",")}`);
    if (res.status === 404) continue; // Not a set: CSS or such, "margin:0".
    if (!res.ok) throw new Error(`icons ${prefix}: ${res.status}`);
    const set = await res.json();
    if (typeof set !== "object" || !set.icons) continue;
    if (set.not_found?.length) missing.push(...set.not_found.map((n) => `${prefix}:${n}`));
    delete set.not_found;
    sets.push(set);
  }
  const count = sets.reduce((n, s) => n + Object.keys(s.icons).length + Object.keys(s.aliases ?? {}).length, 0);
  console.log(`icons: ${count} in ${sets.length} sets${missing.length ? `; not in Iconify: ${missing.join(", ")}` : ""}`);
  return hashed(`window.IconifyPreload = ${JSON.stringify(sets)};\n`, "js");
}
const iconsFile = await icons();

// iconify-icon puts a style of its own in each icon's shadow root, empty
// at first: those (an icon inline or not), by their hashes, are let through.
const iconStyles = ["", ...["-0.125em", "0"].map((align) => `:host{display:inline-block;vertical-align:${align}}span,svg{display:block;margin:auto}`)]
  .map((css) => `'sha256-${createHash("sha256").update(css).digest("base64")}'`);
// The header's GitHub stars are asked of api.github.com as the page loads.
let headers = readFileSync(join(dist, "_headers"), "utf8");
for (const [from, to] of [["style-src 'self';", `style-src 'self' ${iconStyles.join(" ")};`], ["connect-src 'self'", "connect-src 'self' https://api.github.com"]]) {
  if (headers.includes(to)) continue; // A build before wrote it into site/.
  if (!headers.includes(from)) throw new Error(`_headers: no ${from}`);
  headers = headers.replace(from, to);
}
writeFileSync(join(dist, "_headers"), headers);

// The stars as they are now, for the page to show before GitHub answers.
const stars = await fetch("https://api.github.com/repos/baocode-dev/baocode").then((r) => r.json()).then((r) => r.stargazers_count).catch(() => null);
const starsText = typeof stars !== "number" ? null : stars < 1000 ? String(stars) : `${(stars / 1000).toFixed(stars < 10000 ? 1 : 0).replace(/\.0$/, "")}k`;

for (const [lang, file] of [["en", "index.html"], ["zh", join("zh", "index.html")]]) {
  let html = ownFiles(make(lang)).replace("<!-- build:icons -->", `<script src="${iconsFile}" defer></script>`);
  if (starsText) html = html.replace(/(<span data-gh-stars>)[^<]*/, `$1${starsText}`);
  if (/<script>|<style>|https:\/\/(code\.iconify|cdn\.jsdelivr)/.test(html)) throw new Error(`${file}: still inline or from a CDN`);
  mkdirSync(dirname(join(dist, file)), { recursive: true });
  writeFileSync(join(dist, file), html);
}
console.log("dist/ built:", existsSync(join(dist, "zh", "download.html")) ? "home + site/'s pages" : "home");
