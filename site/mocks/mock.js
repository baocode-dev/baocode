// A picture of the app (mock.css): ?lang=en for its English words,
// ?theme=light|kimbie for another theme than Bao Dark (or the page's own
// data-theme), ?show=<part> for what is shown only when asked. Scaled to
// fill its frame, the window W wide (data-w) whatever the frame's width.
(() => {
  const root = document.documentElement;
  const q = new URLSearchParams(location.search);
  if (q.get('lang') === 'en') { root.classList.add('en'); root.lang = 'en'; }
  const theme = q.get('theme');
  if (theme === 'dark') delete root.dataset.theme;
  else if (/^[a-z]+$/.test(theme || '')) root.dataset.theme = theme;
  for (const part of q.getAll('show')) if (/^[a-z]+$/.test(part)) root.classList.add(`show-${part}`);
  const w = Number(root.dataset.w);
  // A transform, not zoom: zoomed, the text would stop at Chrome's least
  // font size and overflow a phone's frame.
  const fit = () => { root.style.setProperty('--fit', innerWidth / w); };
  fit();
  addEventListener('resize', fit);
})();
