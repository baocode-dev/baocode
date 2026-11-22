
    (function () {
      const root = document.documentElement;
      if (!root.classList.contains("reveal-on")) return;
      root.classList.add("reveal-ready");
      const show = (el) => {
        el.classList.add("is-in");
        const d = parseFloat(getComputedStyle(el).getPropertyValue("--d")) || 0;
        setTimeout(() => el.classList.add("rv-done"), d + 1500);
      };

      // Hero: in order, once the first frame is down.
      const hero = document.querySelectorAll(".hero-pill, .h1, .hero-sub, .dl-hero-wrap, .mode-bar, #baocodeWindowMount, .window-shots");
      // A beat after the first paint, so the transition runs from the hidden state.
      setTimeout(() => hero.forEach(show), 60);

      // Sections: each as it comes into view; cards of a row one after another.
      const stagger = [
        [".cap-card", 3, 90],
        [".mobile-item", 5, 70],
        [".phil-card", 2, 110],
        [".dl-os", 4, 70]
      ];
      stagger.forEach(([sel, perRow, step]) => {
        document.querySelectorAll(sel).forEach((el, i) => el.style.setProperty("--d", `${(i % perRow) * step}ms`));
      });
      const targets = document.querySelectorAll(".sec-head, .sec-head-only, .cap-card, .mobile-item, .phil-card, .dl-os");
      if (!("IntersectionObserver" in window)) { targets.forEach(show); return; }
      const io = new IntersectionObserver((entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          show(e.target);
          io.unobserve(e.target);
        });
      }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
      targets.forEach((el) => io.observe(el));
    })();
  