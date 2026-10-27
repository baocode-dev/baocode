// Where the visitor came to the site from, kept for
// good in IndexedDB and localStorage both, one at a time: a channel's id
// after the ? of any page's address (never after the #), the latest
// channel replacing the one before, then taken off the address; with none ever,
// the site that first linked here, else direct. A visit without one
// changes nothing. The channel build's first start opens /activate, which
// reads it back and writes nothing; nor does /import, whose address is a
// visitor's key. `ready`: what is kept once this page has kept it, null
// when the browser keeps nothing.
const attribution = (() => {
  const KEY = 'attribution';
  const VALUE = /^[\p{L}\p{N}._-]{1,128}$/u;
  // What ad networks add to a link they show: not a channel.
  const CLICK_IDS = new Set(['gclid', 'gbraid', 'wbraid', 'dclid', 'fbclid', 'msclkid', 'yclid', 'ttclid', 'twclid', 'li_fat_id', '_gl']);
  const SOURCES = ['channel', 'referrer', 'direct'];
  const valid = (r) => !!r && typeof r === 'object' && SOURCES.includes(r.source) && typeof r.at === 'string'
    && (r.source === 'direct' ? r.value == null : typeof r.value === 'string' && VALUE.test(r.value));

  // A browser that blocks storage may never answer: given up on after a while.
  const within = (promise, ms, fallback) => Promise.race([promise, new Promise((done) => setTimeout(() => done(fallback), ms))]);
  const store = (mode, use) => new Promise((resolve, reject) => {
    const open = indexedDB.open('baocode', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('kv');
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const db = open.result;
      const tx = db.transaction('kv', mode);
      const request = use(tx.objectStore('kv'));
      tx.oncomplete = () => { db.close(); resolve(request.result); };
      tx.onerror = tx.onabort = () => { db.close(); reject(tx.error); };
    };
  });
  const fromDb = () => within(store('readonly', (kv) => kv.get(KEY)).catch(() => null), 1500, null);
  const toDb = (r) => within(store('readwrite', (kv) => kv.put(r, KEY)).then(() => true, () => false), 1500, false);
  const fromLocal = () => { try { return JSON.parse(localStorage.getItem(`baocode.${KEY}`)); } catch { return null; } };
  const toLocal = (r) => { try { localStorage.setItem(`baocode.${KEY}`, JSON.stringify(r)); return true; } catch { return false; } };
  // Written by /dl/ for a download from another site's frame (below), whose
  // storage was that site's alone.
  const fromCookie = () => {
    try { return JSON.parse(decodeURIComponent(document.cookie.match(/(?:^|; )attribution=([^;]*)/)?.[1] || 'null')); } catch { return null; }
  };

  /** The latest of those kept, if any is: one may not have been written last time. */
  const kept = async () => [await fromDb(), fromLocal(), fromCookie()].filter(valid).sort((a, b) => (a.at > b.at ? -1 : 1))[0] || null;

  // ?ch=abc, ?utm_source=abc, else the first other: ?abc, ?abc=, ?from=abc.
  // Lower case, blanks and a trailing / (a link pasted sloppily) taken off.
  const channelIn = (search) => {
    const params = new URLSearchParams(search);
    const picks = [params.get('ch'), params.get('utm_source')];
    for (const [name, value] of params) {
      const key = name.toLowerCase();
      if (key === 'ch' || key.startsWith('utm_') || CLICK_IDS.has(key)) continue;
      picks.push(value || name);
      break;
    }
    for (const pick of picks) {
      const value = pick?.trim().replace(/\/+$/, '').toLowerCase();
      if (value && VALUE.test(value)) return value;
    }
    return null;
  };
  const referrer = () => {
    try {
      const host = new URL(document.referrer).hostname.toLowerCase().replace(/^www\./, '');
      if (host === 'baocode.dev' || host.endsWith('.baocode.dev')) return null;
      return VALUE.test(host) ? host : null;
    } catch {
      return null;
    }
  };

  const ready = (async () => {
    if (document.querySelector('[data-activate], [data-import]')) return kept();
    let source = await kept();
    const channel = channelIn(location.search);
    const now = new Date().toISOString();
    if (channel && !(source?.source === 'channel' && source.value === channel)) {
      source = { source: 'channel', value: channel, at: now };
    } else if (!source) {
      const host = referrer();
      source = { source: host ? 'referrer' : 'direct', value: host, at: now };
      // Kept from being cleared to make room; Firefox would ask for it, so not there.
      if (!/Firefox\//.test(navigator.userAgent)) navigator.storage?.persist?.().catch(() => {});
    }
    // Both again each time: one cleared, the other puts it back.
    const [inDb, inLocal] = [await toDb(source), toLocal(source)];
    if (!inDb && !inLocal) return null;
    // Taken, the channel comes off the address bar, the rest of the query
    // with it (no page here reads one): the path and the # stay, and the
    // page is not loaded again, nor a step added to Back.
    if (channel) history.replaceState(history.state, '', location.pathname + location.hash);
    return source;
  })();

  // In another site's frame, what this page keeps is kept for that site
  // alone (the browser keeps a frame's storage apart): /activate, opened
  // on its own by the channel build's first start, would find nothing. So
  // there a download, a channel kept, goes by /dl/ in a tab of its own,
  // the channel with it: the Worker keeps it in a cookie of baocode.dev's
  // own (site-worker/index.js), and picks the build. A link off the site
  // (GitHub, the Chrome Web Store by /dl/) opens in a tab of its own too:
  // most sites refuse to show in a frame.
  let framedChannel = null;
  if (window.top !== window) {
    ready.then((r) => { framedChannel = r?.source === 'channel' ? r.value : null; });
    const DESKTOP = new Set(['windows', 'windows-arm64', 'macos-arm64', 'macos-x64', 'linux-x64', 'linux-arm64']);
    const newTab = (a) => { a.target = '_blank'; a.rel = 'noopener'; };
    document.addEventListener('click', (event) => {
      const a = event.target.closest?.('a[href]');
      if (!a) return;
      if (a.hasAttribute('data-file')) {
        if (!framedChannel || !DESKTOP.has(a.dataset.file)) return;
        a.href = `https://baocode.dev/dl/${a.dataset.file}?ch=${encodeURIComponent(framedChannel)}`;
        newTab(a);
      } else if (a.origin !== location.origin || a.pathname.startsWith('/dl/')) {
        newTab(a);
      }
    }, true);
  }

  return { kept, ready };
})();

// A channel listed in channels.json shows in three
// places: its logo and name in place of the brand's, "<its logo> <its
// name> × <our logo> BaoCode" for the home page's title, and its subtitle
// in place of ours; the visitor's kept source decides, as for the
// download. Only listed ones, words as text, the logo from /channels/: an
// address anyone can make up never puts anything on the page. head.js has
// the places hidden meanwhile, and channels.json asked for.
const listedChannel = attribution.ready.then(async (kept) => {
  if (kept?.source !== 'channel') return null;
  const channels = await (window.channelsJson || fetch('/channels.json').then((res) => res.json()).catch(() => null));
  // Own keys only: ?constructor is not a channel.
  const channel = channels && Object.hasOwn(channels, kept.value) ? channels[kept.value] : null;
  return channel && typeof channel === 'object' ? channel : null;
});
listedChannel.then((channel) => {
  if (!channel) return;
  const lang = document.documentElement.lang.startsWith('zh') ? 'zh' : 'en';
  const words = (field) => (typeof channel[field]?.[lang] === 'string' ? channel[field][lang].trim() : '');
  const logo = typeof channel.logo === 'string' && /^\/channels\/[\w.-]+$/.test(channel.logo) ? channel.logo : null;
  const name = words('name');
  const subtitle = words('subtitle');
  const span = (className, text) => Object.assign(document.createElement('span'), { className, textContent: text });
  // A logo and a name; whole on its line.
  const side = (src, text) => {
    const el = span('channel', '');
    if (src) el.append(Object.assign(document.createElement('img'), { src, alt: '', className: 'channel-logo' }));
    el.append(text);
    return el;
  };
  if (name) {
    for (const el of document.querySelectorAll('.top .brand')) el.replaceChildren(...side(logo, name).childNodes);
    for (const el of document.querySelectorAll('[data-channel-title]')) {
      el.replaceChildren(side(logo, name), ' ', span('channel-x', '×'), ' ', side('/icon.png', 'BaoCode'));
    }
  }
  if (subtitle) for (const el of document.querySelectorAll('[data-channel-subtitle]')) el.textContent = subtitle;
}).finally(() => document.documentElement.classList.remove('channel-pending'));

// Until a screenshot exists, its frame shows the file it is waiting for.
for (const img of document.querySelectorAll('figure img')) {
  const missing = () => img.parentElement.classList.add('missing');
  img.addEventListener('error', missing);
  if (img.complete && !img.naturalWidth) missing();
}

// A block's Copy button: copies its text, and says so for a moment.
for (const button of document.querySelectorAll('[data-copy]')) {
  const label = button.textContent;
  button.addEventListener('click', async () => {
    const text = button.parentElement.querySelector('pre').innerText;
    try { await navigator.clipboard.writeText(text); } catch { return; }
    button.textContent = button.dataset.done;
    clearTimeout(button.reset);
    button.reset = setTimeout(() => { button.textContent = label; }, 1600);
  });
}

// A button's style to pick (/upstreams): copies the prompt above with that
// button in it, its HTML as a site would write it: a link, its images from
// baocode.dev, the import link for its href.
for (const pick of document.querySelectorAll('.pick')) {
  const hint = pick.dataset.hint;
  pick.addEventListener('click', async () => {
    const styles = pick.closest('.styles'), sample = pick.querySelector('.sample');
    const a = document.createElement('a');
    a.setAttribute('href', `{${styles.dataset.href}}`);
    a.setAttribute('target', '_blank');
    a.setAttribute('rel', 'noopener noreferrer');
    a.setAttribute('style', sample.getAttribute('style'));
    a.innerHTML = sample.innerHTML;
    for (const img of a.querySelectorAll('img')) {
      img.setAttribute('src', 'https://baocode.dev' + img.getAttribute('src'));
      img.setAttribute('srcset', img.getAttribute('srcset').replaceAll('/brand/', 'https://baocode.dev/brand/'));
    }
    const style = styles.dataset.template
      .replace('{url}', `${styles.dataset.page}#${pick.id}`)
      .replace('{name}', pick.dataset.style)
      .replace('{html}', a.outerHTML)
      .replace('{note}', pick.dataset.note).trimEnd();
    const prompt = document.querySelector('[data-prompt] pre').innerText.trimEnd();
    try { await navigator.clipboard.writeText(prompt.replace('\n\n4. ', `\n\n${style}\n\n4. `)); } catch { return; }
    pick.dataset.hint = pick.dataset.done;
    pick.classList.add('copied');
    clearTimeout(pick.reset);
    pick.reset = setTimeout(() => { pick.dataset.hint = hint; pick.classList.remove('copied'); }, 1600);
  });
}

// The notification sound, played on the page.
for (const button of document.querySelectorAll('[data-sound]')) {
  const audio = new Audio(button.dataset.sound);
  audio.preload = 'none';
  audio.addEventListener('ended', () => button.classList.remove('playing'));
  button.addEventListener('click', () => {
    if (!audio.paused) { audio.pause(); audio.currentTime = 0; button.classList.remove('playing'); return; }
    audio.play().then(() => button.classList.add('playing'), () => {});
  });
}

// The release published on dl.baocode.dev, once its manifest loads: the
// version, the day it was published, and each download's link (ending in its
// hash, so a release redone is not served from the CDN's cache of the old
// one) and size. Until then, and if it does not load, the page's own.
(async () => {
  if (!document.querySelector('[data-file], [data-version], [data-updated]')) return;
  try {
    const ctl = new AbortController();
    setTimeout(() => ctl.abort(), 4000);
    const res = await fetch('https://dl.baocode.dev/releases/latest.json', { signal: ctl.signal, cache: 'no-store' });
    const m = await res.json();
    const v = String(m.version).split('+')[0];
    const zh = document.documentElement.lang.startsWith('zh');
    for (const el of document.querySelectorAll('[data-version]')) el.textContent = zh ? `版本 ${v}` : `Version ${v}`;
    const published = new Date(m.pubDate);
    if (!isNaN(published)) {
      const [y, mo, d] = [published.getFullYear(), published.getMonth(), published.getDate()];
      const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      for (const el of document.querySelectorAll('[data-updated]')) {
        el.textContent = zh ? `更新于 ${y} 年 ${mo + 1} 月 ${d} 日` : `Updated ${d} ${months[mo]} ${y}`;
      }
    }
    showDownloads(m.downloads, v);
  } catch {}
})();

// The phone app's, as the desktop's: its own manifest, its own version.
(async () => {
  if (!document.querySelector('[data-file="android"], [data-file="ios"]')) return;
  try {
    const ctl = new AbortController();
    setTimeout(() => ctl.abort(), 4000);
    const res = await fetch('https://dl.baocode.dev/releases/mobile/latest.json', { signal: ctl.signal, cache: 'no-store' });
    const m = await res.json();
    const v = String(m.version).split('+')[0];
    const zh = document.documentElement.lang.startsWith('zh');
    for (const el of document.querySelectorAll('[data-mobile-version]')) el.textContent = zh ? `版本 ${v}` : `Version ${v}`;
    showDownloads(m.downloads, v);
  } catch {}
})();

// The browser extension's version, from its own manifest. Its links stay
// /dl/browser-extension and /dl/chrome-web-store: the zip is too small to
// be worth a size, and the store's page is the Worker's to know.
(async () => {
  if (!document.querySelector('[data-extension-version]')) return;
  try {
    const ctl = new AbortController();
    setTimeout(() => ctl.abort(), 4000);
    const res = await fetch('https://dl.baocode.dev/releases/extension/latest.json', { signal: ctl.signal, cache: 'no-store' });
    const m = await res.json();
    const zh = document.documentElement.lang.startsWith('zh');
    for (const el of document.querySelectorAll('[data-extension-version]')) el.textContent = zh ? `版本 ${m.version}` : `Version ${m.version}`;
  } catch {}
})();

// The home page's Windows button: on Windows on Arm, its Arm64 build. Only
// Chromium says which (Edge, Chrome); elsewhere it stays x64, which Windows
// on Arm runs too, emulated. Its link is the manifest's once that is read
// (showDownloads, by data-file), else the Worker's.
(async () => {
  const a = document.querySelector('a[data-windows]');
  if (!a || !/win/i.test(navigator.userAgentData?.platform || navigator.platform || '')) return;
  try {
    const { architecture } = await navigator.userAgentData.getHighEntropyValues(['architecture']);
    if (architecture !== 'arm') return;
    a.dataset.file = 'windows-arm64';
    a.href = '/dl/windows-arm64';
  } catch {}
})();

// Each download's link and size, as a manifest gives them.
function showDownloads(downloads, v) {
  for (const [os, file] of Object.entries(downloads || {})) {
    if (!file?.url) continue;
    for (const a of document.querySelectorAll(`[data-file="${os}"]`)) {
      a.href = file.url;
      if (a.classList.contains('button')) a.title = `≈ ${Math.round(file.size / 1e6)} MB`;
      if (a.hasAttribute('data-name')) a.textContent = `BaoCode ${v}`;
    }
    for (const el of document.querySelectorAll(`[data-size="${os}"]`)) {
      el.textContent = `≈ ${Math.round(file.size / 1e6)} MB`;
    }
  }
  // Whoever came through a channel listed with its account site gets the
  // channel build, where the manifest has one: anyone else could not use
  // it (lib/channel/), and gets the standard build.
  listedChannel.then((channel) => {
    if (typeof channel?.account?.url !== 'string') return;
    for (const [os, file] of Object.entries(downloads || {})) {
      if (!file.channel?.url) continue;
      for (const a of document.querySelectorAll(`[data-file="${os}"]`)) a.href = file.channel.url;
    }
  });
}

// The background grid: tilted, zooming in for ever. Each level of lines is
// twice the spacing of the one below; as the view zooms one octave, every
// level grows into the next, so the loop has no seam. A level's strength
// depends only on its spacing on screen: fine ones fade in from nothing.
(() => {
  const canvas = document.querySelector('canvas.grid');
  const ctx = canvas.getContext('2d');
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const ANGLE = -14 * Math.PI / 180;   // the tilt
  const OCTAVE = 14;                   // seconds to zoom 2×
  const BASE = 12;                     // the finest spacing, in CSS px
  const ALPHA = .07;                   // strongest line
  let w = 0, h = 0, dpr = 1;
  function resize() {
    dpr = Math.min(devicePixelRatio || 1, 2);
    w = innerWidth; h = innerHeight;
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
  }
  const smooth = (a, b, x) => { const t = Math.min(Math.max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t); };
  const strength = (s) => ALPHA * smooth(BASE, BASE * 6, s) * (1 - .6 * smooth(400, 1600, s));
  function draw(seconds) {
    const z = (seconds / OCTAVE) % 1;
    const scale = 2 ** z;
    const reach = Math.hypot(w, h) / 2 + 2;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.translate(w / 2, h / 2);
    ctx.rotate(ANGLE);
    ctx.lineWidth = 1 / dpr;
    for (let s = BASE * scale; s < reach * 4; s *= 2) {
      const a = strength(s);
      if (a < .002) continue;
      ctx.strokeStyle = `rgba(27, 26, 23, ${a})`;
      ctx.beginPath();
      const n = Math.ceil(reach / s);
      for (let i = -n; i <= n; i++) {
        const x = Math.round(i * s * dpr) / dpr;
        ctx.moveTo(x, -reach); ctx.lineTo(x, reach);
        ctx.moveTo(-reach, x); ctx.lineTo(reach, x);
      }
      ctx.stroke();
    }
  }
  resize();
  addEventListener('resize', () => { resize(); if (still) draw(0); });
  if (still) { draw(0); return; }
  const t0 = performance.now();
  const frame = (now) => { draw((now - t0) / 1000); requestAnimationFrame(frame); };
  requestAnimationFrame(frame);
})();
