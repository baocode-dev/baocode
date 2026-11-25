
    (function () {
      // Each language its own page (build.mjs): / and /zh/.
      const lang = document.documentElement.lang.startsWith("zh") ? "zh" : "en";

      const heroV = new URLSearchParams(location.search).get("hero");
      if (heroV) document.querySelector(".hero")?.setAttribute("data-v", heroV);

      /* The hero's download for the visitor's system. data-file lets site.js
         put the release's own link on it (or a listed channel's build), and
         data-windows its Arm64 build on Windows on Arm. */
      function detectTarget() {
        const ua = navigator.userAgent || "";
        const plat = navigator.platform || "";
        if (/Win/i.test(plat) || /Windows/i.test(ua)) {
          return { file: "windows", icon: "simple-icons:windows11", sub: "Windows 10 / 11 · x64 (.exe)" };
        }
        if (/Linux/i.test(plat) && !/Android/i.test(ua)) {
          return { file: "linux-x64", icon: "simple-icons:linux", sub: "Linux · x64 (.deb)" };
        }
        return { file: "macos-arm64", icon: "simple-icons:apple", sub: "macOS · Apple Silicon (.dmg)" };
      }
      const target = detectTarget();
      const heroBtn = document.getElementById("heroDlBtn");
      const heroIcon = document.getElementById("heroDlIcon");
      const heroSub = document.getElementById("heroDlSub");
      if (heroBtn) {
        heroBtn.href = `/dl/${target.file}`;
        heroBtn.dataset.file = target.file;
      }
      if (heroBtn && target.file === "windows") heroBtn.dataset.windows = "";
      if (heroIcon) heroIcon.setAttribute("icon", target.icon);
      if (heroSub) heroSub.textContent = target.sub;

      /* Bilingual ZH / EN switch */
      /* The words of both languages are in #i18n, for build.mjs. */

      /* On narrow screens the mode tabs switch the window's pictures. */
      document.querySelectorAll(".stage-tab").forEach((tab) => tab.addEventListener("click", () => {
        document.querySelectorAll("#windowShots img").forEach((img) => img.classList.toggle("is-on", img.dataset.demo === tab.dataset.demo));
        if (!window.baoWindowLive) document.querySelectorAll(".stage-tab").forEach((t) => t.classList.toggle("is-active", t === tab));
      }));

      /* What users say (the reviews from baocode.dev's form and the group),
         shuffled, then dealt between the two rows; each row doubled so it loops. */
      const voices = [
          {"zh":"速度非常快，内存占用非常少，我现在平常开发都使用 BaoCode，还可以躺在床上用手机就把任务完成了！","en":"Really fast and uses very little memory. I do all my everyday work in BaoCode now, and I can even finish a task from my phone in bed!","name":"QQ 用户","nameEn":"QQ user","img":3,"qq":1,"long":1},
          {"zh":"比 Cursor 快多了，也很快速准确，头个感觉可以跟 CC 一较高低的存在。","en":"Much faster than Cursor, quick and accurate too: the first I feel can hold its own against Claude Code.","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"比 Cursor 好用多了，支持，打造最佳工具，成倍放大 LLM 效率。","en":"So much better than Cursor. Keep going, build the best tool, multiply what an LLM can do.","name":"kaka1987","img":5,"gh":"kaka30000"},
          {"zh":"无敌，没别的。无敌好用。","en":"Unbeatable, nothing more to say. Unbeatably good.","name":"大木","mark":"大"},
          {"zh":"轻量，流畅，不占内存。","en":"Light, smooth, easy on memory.","name":"QQ 用户","nameEn":"QQ user","img":2,"qq":1},
          {"zh":"在 BaoCode 身上，我看到了团队倾注的热爱与匠心打磨，它是一款有追求、更焕发着蓬勃生命力的产品。","en":"In BaoCode I see the love and craft the team has poured into it: a product with ambition, and full of life.","name":"Kelen","img":1,"gh":"calonye","long":1},
          {"zh":"主题亮眼，交互棒棒的，还有最好的！高性能啊！","en":"Striking themes, lovely interactions, and best of all: the speed!","name":"zkldwxz","img":8,"gh":"zkldwxz"},
          {"zh":"牛逼","en":"Awesome.","name":"佚名","nameEn":"Anonymous","mark":"佚"},
          {"zh":"Stash 功能真是神器。","en":"Stash is a godsend.","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"丝滑，便捷，效率高，功能多，开发者堪比阿拉丁神灯！","en":"Smooth, handy, efficient, full of features. The developer is a genie in a lamp!","name":"QQ 用户","nameEn":"QQ user","img":4,"qq":1},
          {"zh":"好用，工作中的好帮手，随时随地可以开发工作。","en":"Great to use, a real help at work: I can get work done anywhere.","name":"会飞的鱼","mark":"鱼"},
          {"zh":"让 IDE 在 AI 时代下有了兼顾多者的选择，在众多重型 IDE 中脱颖而出，成为一个兼顾性能、效率与跨平台的新选择。","en":"It gives the AI era an IDE that need not choose, standing out among the heavy ones as fast, efficient and cross-platform.","name":"katkitkat","mark":"K","long":1},
          {"zh":"还是 BaoCode 的用的不烧心。","en":"BaoCode it is: no heartburn.","name":"NmouZh","img":6,"gh":"NmouZh"},
          {"zh":"好用、爱用。","en":"Great to use, love using it.","name":"roshin","img":9,"gh":"Roshin0320"},
          {"zh":"牛逼！！！","en":"Awesome!!!","name":"QQ 用户","nameEn":"QQ user","img":7,"qq":1},
          {"zh":"审美在线，非常好用，强烈推荐～同时希望作者开足马力修 bug、完善体验。","en":"Great taste, really easy to use. Highly recommended~ And I hope the author goes full throttle on fixing bugs and polishing it.","name":"QQ 用户","nameEn":"QQ user","img":10,"qq":1,"long":1},
          {"zh":"躺床上写代码，真是好体验。","en":"Writing code lying in bed: what an experience.","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"用 BaoCode vibe coding 非常丝滑，功能也很完善，非常好的项目！希望博主不要停，遥遥领先！","en":"Vibe coding in BaoCode is silky smooth, and it does it all. A great project! Keep going, way ahead of the rest!","name":"QQ 用户","nameEn":"QQ user","qq":1,"mark":"Q","long":1},
          {"zh":"原本守着 Cursor 就是想方便地看代码改动。BaoCode 一出来，我立马把 Cursor 卸了。BaoCode 可谓是 AI 时代 IDE 的首选！","en":"I stuck with Cursor only to see code changes easily. The moment BaoCode came out, I uninstalled Cursor. BaoCode is the IDE of choice for the AI era!","name":"Chun Ning SO","img":11,"gh":"xiashuidaolaoshuren","long":1},
          {"zh":"真的牛逼，非常快。","en":"Seriously awesome, and really fast.","name":"APCAN.","mark":"A"},
          {"zh":"我去，太好用了，简直了。","en":"Wow, it is just so good. Unreal.","name":"QQ 用户","nameEn":"QQ user","img":15,"qq":1},
          {"zh":"非常好用，占用很低，完全平替 Cursor。","en":"Great to use, light on resources, a full replacement for Cursor.","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"太好用了，Claude Code 和 Claude Desktop 的混合体，我已经把 Claude Desktop 抛弃了。","en":"So good: Claude Code and Claude Desktop in one. I have dropped Claude Desktop.","name":"ouli-1242","img":13,"gh":"ouli-1242","long":1},
          {"zh":"舒服型 GUI。","en":"A comfy GUI.","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"非常方便。","en":"Very convenient.","name":"Jasion.L","img":12,"gh":"asionbo"},
          {"zh":"用得非常爽，很快，回复过程中还能学习，知道它在干啥，这在其他 agent 里看不到。","en":"A joy to use, and fast. I learn as it answers and see what it is doing, which no other agent shows me.","name":"GitHub 用户","nameEn":"GitHub user","mark":"gh","long":1},
          {"zh":"超级好用，电脑没有那么卡了！","en":"Super easy to use, and my computer is not so sluggish any more!","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"确实好用，我之前用的终端有时候真的很不方便。","en":"Really good. The terminal I used before was a real pain at times.","name":"QQ 用户","nameEn":"QQ user","img":14,"qq":1},
          {"zh":"用了五分钟就粉了 BaoCode，属实好用，给大佬点赞 👍","en":"Five minutes in and I was a fan. Truly great, hats off 👍","name":"匿名","nameEn":"Anonymous","mark":"匿"},
          {"zh":"牛逼 Pro Max Ultra","en":"Awesome Pro Max Ultra","name":"匿名","nameEn":"Anonymous","mark":"匿"}
      ];
      // A new order on each visit, kept when the language changes.
      for (let i = voices.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [voices[i], voices[j]] = [voices[j], voices[i]];
      }
      const voiceBox = document.getElementById("voices");
      const renderVoices = () => {
        if (!voiceBox) return;
        const card = (v) => {
          const name = lang === "en" && v.nameEn ? v.nameEn : v.name;
          const av = v.img ? `<img class="voice-av" src="/reviews/${v.img}.webp" alt="" loading="lazy">`
            : `<span class="voice-av">${v.mark === "gh" ? '<iconify-icon icon="simple-icons:github"></iconify-icon>' : v.mark}</span>`;
          const who = v.gh ? `<a class="voice-name" href="https://github.com/${v.gh}" target="_blank" rel="noopener">${name}</a>` : `<span class="voice-name">${name}</span>`;
          const src = v.gh ? `<span class="voice-src"><iconify-icon icon="simple-icons:github"></iconify-icon>${v.gh}</span>`
            : v.qq ? `<span class="voice-src"><iconify-icon icon="simple-icons:qq"></iconify-icon>QQ</span>` : "";
          return `<figure class="voice${v.long ? " is-long" : ""}" style="margin:0"><div class="voice-who">${av}${who}${src}</div><p>${v[lang]}</p></figure>`;
        };
        const rows = [voices.filter((_, i) => i % 2 === 0), voices.filter((_, i) => i % 2 === 1)];
        voiceBox.setAttribute("aria-label", lang === "en" ? "What users say" : "用户的评价");
        voiceBox.innerHTML = rows.map((r) => `<div class="voice-row">${[...r, ...r].map(card).join("")}</div>`).join("");
      };
      if (voiceBox) new IntersectionObserver(([e]) => voiceBox.classList.toggle("is-live", e.isIntersecting)).observe(voiceBox);
      renderVoices();

      /* The model honeycomb, filling the card: the models most used in the
         middle, other models and platforms around them, the field's edge
         past the card's. It drifts slowly while on screen; each icon grows
         toward the middle and shrinks to the edge. */
      const orbit = document.getElementById("modelGrid");
      if (orbit) {
        const models = [
          ["logos:claude-icon", "Claude"], ["simple-icons:openai", "ChatGPT"], ["logos:deepseek-icon", "DeepSeek"],
          ["simple-icons:kimi", "Kimi"], ["devicon:gemini", "Gemini"], ["devicon:qwen", "Qwen"],
          ["thesvg-color:zhipu", "GLM"], ["logos:minimax-icon", "MiniMax"], ["simple-icons:openrouter", "OpenRouter"],
          ["thesvg-color:doubao", "Doubao"], ["selfhst:grok-light", "Grok", "selfhst:grok"], ["simple-icons:ollama", "Ollama"],
          ["logos:mistral-ai-icon", "Mistral"], ["logos:meta-icon", "Llama"], ["thesvg-color:siliconcloud-siliconflow", "SiliconFlow"],
          ["selfhst:perplexity-ai-light", "Perplexity", "selfhst:perplexity-ai"], ["devicon:huggingface", "Hugging Face"], ["thesvg-color:microsoft-copilot", "Copilot"],
          ["thesvg-color:stepfun", "StepFun"], ["thesvg-color:baichuan", "Baichuan"], ["thesvg-color:wenxin", "ERNIE"],
          ["logos:cohere-icon", "Cohere"], ["logos:google-cloud", "Vertex AI"], ["devicon:azure", "Azure"],
          ["thesvg-color:iflytekcloud", "Spark"], ["simple-icons:nvidia", "NVIDIA"],
        ];
        // Hex rows of 7, 6, 7, 6, 7, nearest the middle first; the outermost
        // slots, half off the card, take the list round again.
        const step = 62, slots = [];
        [-2, -1, 0, 1, 2].forEach((r) => {
          const n = r % 2 ? 6 : 7;
          for (let k = 0; k < n; k++) slots.push({ x: (k - (n - 1) / 2) * step, y: r * step * 0.866 });
        });
        const reach = (p) => Math.hypot(p.x / 190, p.y / 120);
        slots.sort((p, q) => reach(p) - reach(q));
        // A model's third name is its mark on a light page, where the first is white.
        const markOf = ([icon, , onLight]) => (window.baoTheme?.light && onLight) || icon;
        orbit.innerHTML = slots.map((_, i) => {
          const model = models[i % models.length];
          return `<i class="v-orb" title="${model[1]}"><iconify-icon icon="${markOf(model)}"></iconify-icon></i>`;
        }).join("");
        const orbs = [...orbit.children];
        window.baoTheme?.onChange(() => orbs.forEach((el, i) => el.firstChild.setAttribute("icon", markOf(models[i % models.length]))));
        const place = (now) => {
          const t = now / 1000, ox = 22 * Math.sin(t * 0.23), oy = 14 * Math.sin(t * 0.37 + 1);
          orbs.forEach((el, i) => {
            const x = slots[i].x + ox, y = slots[i].y + oy;
            const e = Math.min(1, reach({ x, y })) ** 2;
            const pull = 1 - 0.1 * e, sc = 1 - 0.6 * e;
            el.style.transform = `translate(${(x * pull).toFixed(1)}px, ${(y * pull).toFixed(1)}px) scale(${sc.toFixed(3)})`;
            el.style.opacity = (0.3 + 0.7 * (1 - e)).toFixed(3);
          });
        };
        place(0);
        let orbOn = false, orbRunning = false;
        const orbTick = (now) => {
          if (!orbOn || document.hidden) { orbRunning = false; return false; }
          place(now);
        };
        const orbRun = () => {
          if (orbRunning || !orbOn || document.hidden || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
          orbRunning = true;
          window.baoTicker.add(orbTick);
        };
        new IntersectionObserver(([e]) => { orbOn = e.isIntersecting; orbRun(); }).observe(orbit);
        document.addEventListener("visibilitychange", orbRun);
      }

      /* 5-up Mobile Lightbox */
      const shots = [
        { src: "/assets/mobile-5.webp", cap: "01 LIVE CHAT" },
        { src: "/assets/mobile-4.webp", cap: "02 CONTEXT 400K" },
        { src: "/assets/mobile-3.webp", cap: "03 MODELS & QUOTA" },
        { src: "/assets/mobile-1.webp", cap: "04 HOST & SSH" },
        { src: "/assets/mobile-2.webp", cap: "05 REMOTE FILES" }
      ];
      let shotIdx = 0;
      const lb = document.getElementById("lightbox");
      const lbImg = document.getElementById("lbImg");
      const lbCap = document.getElementById("lbCap");

      function showShot(idx) {
        shotIdx = (idx + shots.length) % shots.length;
        lbImg.src = shots[shotIdx].src;
        lbImg.alt = shots[shotIdx].cap;
        lbCap.textContent = shots[shotIdx].cap;
        lb.classList.add("is-open");
      }
      function closeShot() { lb.classList.remove("is-open"); }

      document.querySelectorAll("#mobileStrip .mobile-item").forEach((btn) => {
        btn.addEventListener("click", () => showShot(Number(btn.getAttribute("data-shot-index"))));
      });
      document.getElementById("lbPrev").addEventListener("click", (e) => { e.stopPropagation(); showShot(shotIdx - 1); });
      document.getElementById("lbNext").addEventListener("click", (e) => { e.stopPropagation(); showShot(shotIdx + 1); });
      document.getElementById("lbClose").addEventListener("click", (e) => { e.stopPropagation(); closeShot(); });
      lb.addEventListener("click", (e) => { if (e.target === lb) closeShot(); });
      window.addEventListener("keydown", (e) => {
        if (!lb.classList.contains("is-open")) return;
        if (e.key === "Escape") closeShot();
        if (e.key === "ArrowLeft") showShot(shotIdx - 1);
        if (e.key === "ArrowRight") showShot(shotIdx + 1);
      });

      // uPlot draws the cards' charts; fetched once, when the first of them
      // comes near.
      let uPlotLoading = null;
      const loadUPlot = () => uPlotLoading || (uPlotLoading = new Promise((resolve, reject) => {
        const css = document.createElement("link");
        css.rel = "stylesheet";
        css.href = "/assets/vendor/uPlot.min.css";
        document.head.appendChild(css);
        const js = document.createElement("script");
        js.src = "/assets/vendor/uPlot.iife.min.js";
        js.onload = resolve; js.onerror = reject;
        document.head.appendChild(js);
      }));
      // Their colors are the page's (--chart-*, light or dark); each is
      // drawn again when that changes.
      const chartColor = (name) => getComputedStyle(document.documentElement).getPropertyValue(`--chart-${name}`).trim();
      const onScheme = (f) => window.baoTheme?.onChange(f);

      /* The 360 FPS card: frame rate as a performance monitor plots it, with
         uPlot (loaded once the card comes near). BaoCode holds near 360;
         a typical Electron app wanders under 120 and drops on GC and
         layout. Updated on the page's 30-frame beat, only while seen. */
      const fpsBox = document.getElementById("fpsChart");
      if (fpsBox && "IntersectionObserver" in window) {
        const N = 160;
        const xs = Array.from({ length: N }, (_, i) => i);
        let bao = 358, el = 72, elDip = 0;
        const nextBao = () => {
          bao += (358 - bao) * 0.35 + (Math.random() - 0.5) * 3;
          const v = Math.random() < 0.015 ? bao - 8 - Math.random() * 10 : bao;
          return Math.min(360, v);
        };
        const nextEl = () => {
          el += (78 - el) * 0.08 + (Math.random() - 0.5) * 14;
          el = Math.max(46, Math.min(118, el));
          if (elDip > 0) { elDip--; return 18 + Math.random() * 14; }
          if (Math.random() < 0.025) elDip = 1 + Math.floor(Math.random() * 3);
          return el;
        };
        const baoYs = xs.map(nextBao), elYs = xs.map(nextEl);
        let plot = null, onScreen = false, running = false, beat = 0;

        const build = () => {
          const mono = '10px "JetBrains Mono", ui-monospace, monospace';
          const gold = chartColor("gold"), fill = chartColor("gold-fill"), clear = chartColor("gold-clear");
          const guide = chartColor("guide");
          plot = new uPlot({
            width: fpsBox.clientWidth, height: fpsBox.clientHeight,
            padding: [8, 0, 0, 0],
            legend: { show: false },
            cursor: { show: false },
            scales: { x: { time: false }, y: { range: [0, 400] } },
            axes: [
              { show: false },
              {
                side: 1, size: 30, gap: 4, font: mono, stroke: chartColor("axis"),
                splits: () => [60, 180, 360],
                ticks: { show: false },
                grid: { stroke: chartColor("grid"), width: 1 },
              },
            ],
            series: [
              {},
              { stroke: chartColor("other"), width: 1.2, points: { show: false } },
              {
                stroke: gold, width: 1.8, points: { show: false },
                fill: (u) => {
                  const g = u.ctx.createLinearGradient(0, u.bbox.top, 0, u.bbox.top + u.bbox.height);
                  g.addColorStop(0, fill);
                  g.addColorStop(1, clear);
                  return g;
                },
              },
            ],
            hooks: {
              // The 60 FPS line most apps live under.
              draw: [(u) => {
                const y = Math.round(u.valToPos(60, "y", true)) + 0.5;
                const c = u.ctx;
                c.save();
                c.setLineDash([3 * devicePixelRatio, 3 * devicePixelRatio]);
                c.strokeStyle = guide;
                c.lineWidth = devicePixelRatio;
                c.beginPath(); c.moveTo(u.bbox.left, y); c.lineTo(u.bbox.left + u.bbox.width, y); c.stroke();
                c.restore();
              }],
            },
          }, [xs, elYs, baoYs], fpsBox);
        };
        addEventListener("resize", () => plot?.setSize({ width: fpsBox.clientWidth, height: fpsBox.clientHeight }));
        onScheme(() => { if (plot) { plot.destroy(); build(); } });

        const baoEl = document.getElementById("fpsBao"), elEl = document.getElementById("fpsEl");
        const avg = (a) => Math.round(a.slice(-30).reduce((s, v) => s + v, 0) / 30);
        const tick = () => {
          if (!onScreen || document.hidden || !plot) { running = false; return false; }
          baoYs.shift(); baoYs.push(nextBao());
          elYs.shift(); elYs.push(nextEl());
          plot.setData([xs, elYs, baoYs]);
          if (++beat % 15 === 0) { baoEl.textContent = avg(baoYs); elEl.textContent = avg(elYs); }
        };
        const run = () => {
          if (running || !onScreen || document.hidden || !plot) return;
          running = true;
          window.baoTicker.add(tick);
        };
        let loading = null;
        new IntersectionObserver((e) => {
          const near = e[0].isIntersecting;
          if (near && !loading) loading = loadUPlot().then(build).then(run).catch(() => {});
        }, { rootMargin: "400px" }).observe(fpsBox);
        new IntersectionObserver((e) => { onScreen = e[0].isIntersecting; run(); }).observe(fpsBox);
        document.addEventListener("visibilitychange", run);
      }

      /* The API card: context growth as the usage page draws it, simplified.
         Each request a bar, stacked cache read / input / cache write /
         output; the context climbs turn by turn and drops at a compaction
         (a diamond on top). A new request comes in every 1.6 s while seen. */
      const ctxBox = document.getElementById("ctxChart");
      if (ctxBox && "IntersectionObserver" in window) {
        // Few bars, room between them: read at a glance, not a barcode.
        const N = 26;
        let total = 150000, pace = 26000, compacted = false;
        const nextReq = () => {
          let read, input, write, out;
          if (total > 330000 + Math.random() * 40000) {
            compacted = true;
            total = 40000 + Math.random() * 12000;
            pace = 20000 + Math.random() * 14000;
            out = 6000; input = 5000; write = 18000;
            read = total - out - input - write;
          } else {
            compacted = false;
            const grow = pace * (0.6 + Math.random() * 0.8);
            out = 5000 + Math.random() * 5000;
            input = 3000 + Math.random() * 4000;
            write = Math.max(4000, grow - out - input);
            read = total;
            total += grow;
          }
          return { read, input, write, out, compacted };
        };
        const reqs = [];
        for (let i = 0; i < N; i++) reqs.push(nextReq());
        const xs = Array.from({ length: N }, (_, i) => i);
        const stacks = () => {
          const c1 = reqs.map((r) => r.read);
          const c2 = reqs.map((r, i) => c1[i] + r.input);
          const c3 = reqs.map((r, i) => c2[i] + r.write);
          const c4 = reqs.map((r, i) => c3[i] + r.out);
          // Drawn tallest first, each from zero, so each covers the one
          // above it but for its own slice.
          return [xs, c4, c3, c2, c1];
        };
        let plot = null, onScreen = false, running = false, beat = 0;

        // The whole session's hit rate (a compaction rewrites the cache, so
        // it dips there) and the money cache reads saved (Sonnet's $3 input
        // against $0.30 a cached read), rolling to each new value.
        const hitEl = document.getElementById("apiHit"), savedEl = document.getElementById("apiSaved");
        let saved = 135.39, hit = 98.3;
        const roll = (el, next) => {
          const prev = el.dataset.v || "";
          el.dataset.v = next;
          if (prev.length !== next.length || !el.children.length) {
            el.innerHTML = [...next].map((ch) => `<span class="rd"><span class="rt"><span>${ch}</span></span></span>`).join("");
            return;
          }
          [...next].forEach((ch, i) => {
            if (ch === prev[i]) return;
            const slot = el.children[i];
            slot.innerHTML = `<span class="rt"><span>${prev[i]}</span><span>${ch}</span></span>`;
            const t = slot.firstChild;
            void t.offsetWidth;
            t.classList.add("go");
          });
        };
        const showStats = () => {
          roll(hitEl, `${hit.toFixed(1)}%`);
          roll(savedEl, `$${saved.toFixed(2)}`);
        };
        showStats();

        const build = () => {
          const mono = '10px "JetBrains Mono", ui-monospace, monospace';
          // Only the tallest layer rounds its top: the layers drawn over it
          // cover the rest of it square.
          const bars = uPlot.paths.bars({ size: [0.62, 12] });
          const capped = uPlot.paths.bars({ size: [0.62, 12], radius: 0.3 });
          const bar = (color, paths = bars) => ({ paths, fill: color, stroke: color, width: 0, points: { show: false } });
          const mark = chartColor("mark");
          plot = new uPlot({
            width: ctxBox.clientWidth, height: ctxBox.clientHeight,
            padding: [12, 0, 0, 0],
            legend: { show: false },
            cursor: { show: false },
            scales: { x: { time: false, range: [-0.5, N - 0.5] }, y: { range: [0, 420000] } },
            axes: [
              { show: false },
              {
                side: 1, size: 34, gap: 4, font: mono, stroke: chartColor("axis"),
                splits: () => [200000, 400000],
                values: (u, v) => v.map((x) => `${x / 1000}K`),
                ticks: { show: false },
                grid: { stroke: chartColor("grid"), width: 1 },
              },
            ],
            series: [{}, bar("#bd8128", capped), bar("#b0679e"), bar("#3f86d8"), bar("#2e9e72")],
            hooks: {
              // A diamond over each compaction.
              draw: [(u) => {
                const c = u.ctx, d = 3 * devicePixelRatio, y = u.bbox.top - 6 * devicePixelRatio;
                c.save();
                c.fillStyle = mark;
                reqs.forEach((r, i) => {
                  if (!r.compacted) return;
                  const x = u.valToPos(i, "x", true);
                  c.beginPath(); c.moveTo(x, y - d); c.lineTo(x + d, y); c.lineTo(x, y + d); c.lineTo(x - d, y); c.closePath(); c.fill();
                });
                c.restore();
              }],
            },
          }, stacks(), ctxBox);
        };
        addEventListener("resize", () => plot?.setSize({ width: ctxBox.clientWidth, height: ctxBox.clientHeight }));
        onScheme(() => { if (plot) { plot.destroy(); build(); } });
        const tick = () => {
          if (!onScreen || document.hidden || !plot) { running = false; return false; }
          if (++beat % 48) return;
          reqs.shift(); reqs.push(nextReq());
          const last = reqs[N - 1];
          saved += last.read / 1e6 * 2.7;
          hit = Math.min(98.9, Math.max(97.2, hit + (last.compacted ? -0.6 : Math.random() * 0.3 - 0.08)));
          plot.setData(stacks());
          showStats();
        };
        const run = () => {
          if (running || !onScreen || document.hidden || !plot) return;
          running = true;
          window.baoTicker.add(tick);
        };
        let loading = null;
        new IntersectionObserver((e) => {
          if (e[0].isIntersecting && !loading) loading = loadUPlot().then(build).then(run).catch(() => {});
        }, { rootMargin: "400px" }).observe(ctxBox);
        new IntersectionObserver((e) => { onScreen = e[0].isIntersecting; run(); }).observe(ctxBox);
        document.addEventListener("visibilitychange", run);
      }
    })();
  