// In each page's <head>, before it shows.

// The visitor's language: the page in it, if this one is in the other.
// Chinese for those whose system puts Chinese before English, English for
// anyone else; the language they last picked (the header's link) over
// both. Every page is at /<page> and /zh/<page> but for /import and
// /activate, which the app opens in its own language. Search engines are
// left on the page they asked for, to list each.
(() => {
  const path = location.pathname;
  const zh = path === '/zh' || path.startsWith('/zh/');
  document.addEventListener('click', (event) => {
    const link = event.target.closest?.('a.lang[hreflang]');
    if (link) try { localStorage.setItem('baocode.lang', link.hreflang); } catch {}
  }, true);
  if (/^\/(zh\/)?(import|activate)(\.html)?$/.test(path)) return;
  if (navigator.webdriver || /bot|crawl|spider|slurp|preview|facebookexternalhit/i.test(navigator.userAgent)) return;
  let picked = null;
  try { picked = localStorage.getItem('baocode.lang'); } catch {}
  const system = (navigator.languages || [navigator.language])
    .map((tag) => String(tag).toLowerCase())
    .find((tag) => tag.startsWith('zh') || tag.startsWith('en'));
  const wanted = picked === 'zh' || picked === 'en' ? picked : system?.startsWith('zh') ? 'zh' : 'en';
  if ((wanted === 'zh') === zh) return;
  const there = zh ? path.replace(/^\/zh(\/|$)/, '/') : `/zh${path}`;
  location.replace(there + location.search + location.hash);
})();

// Light or dark, as <html data-theme>, before anything is drawn: the
// system's, or the one picked last with the header's button (kept as
// baocode.theme). The button goes round from the system's to the other of
// the two, the same one, and back. window.baoTheme tells the pages' scripts
// which it is, and calls them back when it changes.
(() => {
  const root = document.documentElement;
  const system = matchMedia('(prefers-color-scheme: light)');
  const listeners = new Set();
  let pick = null;
  try { pick = localStorage.getItem('baocode.theme'); } catch {}
  if (pick !== 'light' && pick !== 'dark') pick = 'auto';
  const WORDS = {
    zh: { auto: '外观：跟随系统', light: '外观：浅色', dark: '外观：深色' },
    en: { auto: 'Appearance: system', light: 'Appearance: light', dark: 'Appearance: dark' },
  };
  function label() {
    const words = WORDS[root.lang.startsWith('zh') ? 'zh' : 'en'][pick];
    for (const button of document.querySelectorAll('[data-theme-toggle]')) {
      button.setAttribute('aria-label', words);
      button.dataset.tip = words;
    }
  }
  function apply(changed) {
    const was = root.dataset.theme;
    root.dataset.theme = pick === 'light' || (pick === 'auto' && system.matches) ? 'light' : 'dark';
    root.dataset.themePick = pick;
    label();
    if (!changed || was === root.dataset.theme) return;
    // All of it at once, no color easing over at its own pace.
    root.classList.add('theme-switching');
    requestAnimationFrame(() => requestAnimationFrame(() => root.classList.remove('theme-switching')));
    for (const f of listeners) f();
  }
  system.addEventListener('change', () => apply(true));
  document.addEventListener('click', (event) => {
    if (!event.target.closest?.('[data-theme-toggle]')) return;
    const same = system.matches ? 'light' : 'dark';
    const other = system.matches ? 'dark' : 'light';
    pick = pick === 'auto' ? other : pick === other ? same : 'auto';
    try {
      if (pick === 'auto') localStorage.removeItem('baocode.theme');
      else localStorage.setItem('baocode.theme', pick);
    } catch {}
    apply(true);
  });
  document.addEventListener('DOMContentLoaded', label);
  window.baoTheme = {
    get light() { return root.dataset.theme === 'light'; },
    onChange(f) { listeners.add(f); },
  };
  apply(false);
})();

// A visitor who may be a listed channel's has the places a channel changes
// (the brand, the home page's title and subtitle) hidden until site.js has
// filled them in, so ours never flash first; and channels.json is asked
// for already. Never hidden for long, whatever happens.
(() => {
  let kept = null;
  try { kept = JSON.parse(localStorage.getItem('baocode.attribution')); } catch {}
  // A channel kept, or one in the address, replacing whatever is.
  if (kept?.source !== 'channel' && location.search.length < 2) return;
  const root = document.documentElement;
  root.classList.add('channel-pending');
  window.channelsJson = fetch('/channels.json').then((res) => res.json()).catch(() => null);
  setTimeout(() => root.classList.remove('channel-pending'), 2000);
})();
