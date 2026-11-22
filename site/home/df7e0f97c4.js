
    (function () {
      const hdr = document.querySelector(".hdr");
      if (!hdr) return;
      const sync = () => hdr.classList.toggle("is-stuck", scrollY > 8);
      addEventListener("scroll", sync, { passive: true });
      sync();
    })();
  