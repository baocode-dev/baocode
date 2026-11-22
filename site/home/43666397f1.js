
    // The hero's sky. One shader: an edgeless aurora glow drifting sideways,
    // and broad beams fanning down from above the headline with light
    // flowing out along them. Everything soft and slow; dithered so the dark
    // gradients don't band. Runs only while on screen; one still frame when
    // motion is turned down.
    (function () {
      const sky = document.querySelector(".hero-sky");
      const hero = document.querySelector(".hero");
      const canvas = sky && sky.querySelector("canvas");
      const gl = canvas && canvas.getContext("webgl", { premultipliedAlpha: true, antialias: false });
      if (!gl || !hero) return;
      const still = matchMedia("(prefers-reduced-motion: reduce)").matches;

      const vs = "attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }";
      const fs = `
        precision highp float;
        uniform vec2 uRes; uniform vec2 uSrc; uniform vec4 uBox; uniform float uT; uniform float uPx;
        float beam(vec2 d, float cosA, float sA, float sB, float spd) {
          return clamp(0.45 + 0.15 * sin(cosA * sA + uT * spd) + 0.3 + 0.2 * cos(-cosA * sB + uT * spd), 0.0, 1.0);
        }
        void main() {
          vec2 px = gl_FragCoord.xy;
          float W = uRes.x, H = uRes.y;

          // Beams: angle from straight down, soft bands across it.
          vec2 d = px - uSrc;
          float dist = length(d);
          float cosA = dot(d / max(dist, 1.0), vec2(0.0, -1.0));
          float rays = 0.55 * beam(d, cosA, 36.22, 21.11, 0.45) + 0.45 * beam(d, cosA, 22.4, 18.02, 0.3);
          rays *= smoothstep(0.25, 0.85, cosA);
          rays *= clamp(1.0 - dist / (H * 1.3), 0.0, 1.0);
          rays *= smoothstep(0.0, 120.0 * uPx, dist);
          // Light flowing outward along them.
          rays *= 0.84 + 0.16 * sin(dist / uPx * 0.022 - uT * 1.6);
          rays = pow(rays, 1.3);

          // Aurora: a soft glow along the top with no edge anywhere, fading
          // evenly up and down; patches of it drift sideways and swell and
          // ebb.
          float u = px.x / W;
          float yt = (H - px.y) / uPx;
          float aurI = exp(-pow((yt - 90.0) / 80.0, 2.0));
          aurI *= 0.45 + 0.55 * (0.5 + 0.5 * sin(u * 4.2 + uT * 0.12)) * (0.6 + 0.4 * sin(u * 2.3 - uT * 0.09 + 1.0));
          aurI *= smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u);
          vec3 teal = vec3(0.36, 0.78, 0.68), gold = vec3(0.90, 0.73, 0.49), vio = vec3(0.58, 0.52, 0.92);
          float cu = u + 0.08 * sin(uT * 0.07);
          vec3 aurCol = cu < 0.5 ? mix(teal, gold, smoothstep(0.12, 0.5, cu)) : mix(gold, vio, smoothstep(0.5, 0.88, cu));
          aurCol = mix(aurCol, vec3(0.86), 0.22);
          vec3 aur = aurCol * aurI * 0.22;

          // The words: beams dim behind them.
          float e = length((px - uBox.xy) / uBox.zw);
          rays *= mix(0.55, 1.0, smoothstep(0.8, 1.3, e));

          vec3 col = vec3(0.96, 0.87, 0.72) * rays * 0.2 + aur;
          float n = fract(sin(dot(px, vec2(12.9898, 78.233))) * 43758.5453);
          col += (n - 0.5) / 255.0;
          col = max(col, 0.0);
          gl_FragColor = vec4(col, max(col.r, max(col.g, col.b)));
        }`;
      function shader(type, src) {
        const sh = gl.createShader(type);
        gl.shaderSource(sh, src); gl.compileShader(sh);
        return sh;
      }
      const prog = gl.createProgram();
      gl.attachShader(prog, shader(gl.VERTEX_SHADER, vs));
      gl.attachShader(prog, shader(gl.FRAGMENT_SHADER, fs));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return;
      gl.useProgram(prog);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      const loc = gl.getAttribLocation(prog, "p");
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      const u = (k) => gl.getUniformLocation(prog, k);
      const uRes = u("uRes"), uSrc = u("uSrc"), uBox = u("uBox"), uT = u("uT"), uPx = u("uPx");

      let visible = true;
      function layout() {
        const top = hero.querySelector(".hero-top") || hero;
        const hr = hero.getBoundingClientRect();
        const tr = top.getBoundingClientRect();
        hero.style.setProperty("--warp-h", `${Math.round(tr.bottom - hr.top + 160)}px`);
        const r = sky.getBoundingClientRect();
        // Soft light needs few pixels: half of them, scaled up, looks the same.
        const k = 0.5;
        canvas.width = Math.round(r.width * k);
        canvas.height = Math.round(r.height * k);
        gl.viewport(0, 0, canvas.width, canvas.height);
        const gy = (y) => (r.height - y) * k;
        gl.uniform2f(uRes, canvas.width, canvas.height);
        gl.uniform1f(uPx, k);
        gl.uniform2f(uSrc, (r.width / 2) * k, gy(-40));
        gl.uniform4f(uBox, (tr.left + tr.width / 2 - r.left) * k, gy(tr.top + tr.height / 2 - r.top),
          (tr.width / 2 + 24) * k, (tr.height / 2 + 6) * k);
        draw(lastT);
      }
      let lastT = 12;
      function draw(sec) {
        lastT = sec;
        gl.uniform1f(uT, sec);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }
      // On the page's 30-frame beat, with the window's little canvases:
      // slow light looks no different, and it costs a fifth. Off screen or
      // in a hidden tab it stops altogether.
      let running = false;
      function frame(now) {
        if (!visible || document.hidden) { running = false; return false; }
        draw(12 + now / 1000);
      }
      function run() {
        if (running || !visible || document.hidden) return;
        running = true;
        window.baoTicker.add(frame);
      }

      layout();
      requestAnimationFrame(() => sky.classList.add("is-on"));
      addEventListener("resize", layout);
      document.fonts?.ready.then(layout);
      if (still) return;
      if ("IntersectionObserver" in window) {
        new IntersectionObserver((e) => { visible = e[0].isIntersecting; run(); }).observe(sky);
      }
      document.addEventListener("visibilitychange", run);
      run();
    })();
  