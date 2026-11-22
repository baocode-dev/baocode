
    // Hidden from the first paint, so nothing flashes before it animates in;
    // shown anyway if the page script never gets to it.
    if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
      document.documentElement.classList.add("reveal-on");
      setTimeout(() => {
        if (!document.documentElement.classList.contains("reveal-ready")) document.documentElement.classList.remove("reveal-on");
      }, 4000);
    }
  