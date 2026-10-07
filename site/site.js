// Until a screenshot exists, its frame shows the file it is waiting for.
for (const img of document.querySelectorAll('figure img')) {
  const missing = () => img.parentElement.classList.add('missing');
  img.addEventListener('error', missing);
  if (img.complete && !img.naturalWidth) missing();
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
