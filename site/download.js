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
