// The download page: this machine's build first, then the version, links
// and sizes from the update manifest once it is served (dl.baocode.dev).
(() => {
  const isWin = /win/i.test(navigator.userAgentData?.platform || navigator.platform || '');
  const list = document.querySelector('[data-platforms]');
  if (isWin) list.prepend(list.querySelector('[data-os="win"]'));

  const mb = (bytes) => `${Math.round(bytes / 1e6)} MB`;
  (async () => {
    try {
      const ctl = new AbortController();
      setTimeout(() => ctl.abort(), 4000);
      const res = await fetch('https://dl.baocode.dev/releases/latest.json', { signal: ctl.signal, cache: 'no-store' });
      const m = await res.json();
      const v = String(m.version).split('+')[0];
      document.querySelector('[data-version]').textContent = `Version ${v}`;
      const win = m.platforms?.['windows-x64'];
      if (win) {
        document.querySelector('[data-file="win"]').href = win.url;
        document.querySelector('[data-size="win"]').textContent = mb(win.size);
      }
      // The manifest has the zip the app updates from; the page offers the
      // disk image beside it.
      if (m.platforms?.['macos-universal']) {
        document.querySelector('[data-file="mac"]').href = `https://dl.baocode.dev/releases/${v}/BaoCode-${v}.dmg`;
      }
    } catch {}
  })();
})();
