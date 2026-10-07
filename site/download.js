// The download page: this machine's build first. Links, sizes and the
// version come from the release manifest (site.js).
(() => {
  const isWin = /win/i.test(navigator.userAgentData?.platform || navigator.platform || '');
  const list = document.querySelector('[data-platforms]');
  if (isWin) list.prepend(list.querySelector('[data-os="windows"]'));
})();
