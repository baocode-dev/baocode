// The download page: this machine's build first. Links, sizes and the
// version come from the release manifest (site.js).
(async () => {
  const platform = navigator.userAgentData?.platform || navigator.platform || '';
  const isWin = /win/i.test(platform);
  const isLinux = /linux/i.test(platform) && !/android/i.test(navigator.userAgent);
  const list = document.querySelector('[data-platforms]');
  if (isWin) list.prepend(list.querySelector('[data-os="windows"]'));
  if (isLinux) list.prepend(list.querySelector('[data-os="linux"]'));
  // Only Chromium tells an Intel Mac from Apple silicon (Safari says Intel
  // on both), an arm64 Linux from an x64 one, or Windows on Arm; where it
  // does, this machine's build is the one offered first.
  try {
    const { architecture } = await navigator.userAgentData.getHighEntropyValues(['architecture']);
    const os = isWin ? 'windows' : isLinux ? 'linux' : 'macos';
    const mine = document.querySelector(`[data-os="${os}"] [data-arch="${architecture}"]`);
    if (!mine) return;
    for (const a of mine.parentElement.querySelectorAll('[data-arch]')) a.classList.toggle('primary', a === mine);
    mine.parentElement.prepend(mine);
  } catch {}
})();

// The phone app's cards: a touch screen has no hover to bring a card's QR
// code up with, so a tap on the card opens it (a tap elsewhere, or Escape,
// closes it). Its own buttons are left alone — a phone that downloads the
// APK itself has no use for a code to scan, and tapping Download should
// download. What a mouse does the page's own CSS sees to.
(() => {
  if (matchMedia('(hover: hover)').matches) return;
  const cards = document.querySelectorAll('[data-phones] .platform');
  if (!cards.length) return;
  const close = () => { for (const card of cards) card.classList.remove('qr-open'); };
  for (const card of cards) {
    card.addEventListener('click', (e) => {
      // Its own button downloads the app; nothing to scan, so the code goes.
      if (e.target.closest('a, button')) { close(); return; }
      const open = card.classList.contains('qr-open');
      close();
      if (!open) card.classList.add('qr-open');
    });
  }
  document.addEventListener('click', (e) => {
    if (!e.target.closest('[data-phones] .platform')) close();
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
})();

// A download clicked: once it is on its way, a word of thanks and a polite
// ask for a star on GitHub. Once a browser; Escape, Maybe later or a click
// outside closes it.
(() => {
  const dialog = document.querySelector('[data-star]');
  if (!dialog?.showModal) return;
  const key = 'baocode.starAsked';
  const asked = () => { try { return localStorage.getItem(key) === '1'; } catch { return false; } };
  for (const a of document.querySelectorAll('[data-platforms] a[data-file]')) {
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
