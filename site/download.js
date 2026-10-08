// The download page: this machine's build first. Links, sizes and the
// version come from the release manifest (site.js).
(async () => {
  const isWin = /win/i.test(navigator.userAgentData?.platform || navigator.platform || '');
  const list = document.querySelector('[data-platforms]');
  if (isWin) list.prepend(list.querySelector('[data-os="windows"]'));
  // Only Chromium tells an Intel Mac from Apple silicon (Safari says Intel
  // on both); where it does, an Intel Mac's build is the one offered first.
  try {
    const { architecture } = await navigator.userAgentData.getHighEntropyValues(['architecture']);
    const mine = document.querySelector(`[data-arch="${architecture}"]`);
    if (!mine) return;
    for (const a of document.querySelectorAll('[data-arch]')) a.classList.toggle('primary', a === mine);
    mine.parentElement.prepend(mine);
  } catch {}
})();

// A download clicked: once it is on its way, a word of thanks and a polite
// ask for a star on GitHub. Once a browser; Escape, Maybe later or a click
// outside closes it.
(() => {
  const dialog = document.querySelector('[data-star]');
  if (!dialog?.showModal) return;
  const key = 'baocode.starAsked';
  const asked = () => { try { return localStorage.getItem(key) === '1'; } catch { return false; } };
  for (const a of document.querySelectorAll('.platform a[data-file]')) {
    a.addEventListener('click', () => {
      if (asked()) return;
      try { localStorage.setItem(key, '1'); } catch {}
      setTimeout(() => dialog.showModal(), 600);
    });
  }
  dialog.querySelector('[data-star-close]').addEventListener('click', () => dialog.close());
  dialog.querySelector('[data-star-go]').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', (e) => { if (e.target === dialog) dialog.close(); });
})();
