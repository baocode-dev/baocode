
    /* The repository's stars on GitHub: the count the page was built with,
       then GitHub's own, kept an hour so each visit doesn't ask again. */
    (() => {
      const el = document.querySelector("[data-gh-stars]");
      if (!el) return;
      const show = (n) => { el.textContent = n < 1000 ? String(n) : `${(n / 1000).toFixed(n < 10000 ? 1 : 0).replace(/\.0$/, "")}k`; };
      const key = "baocode.ghStars";
      try {
        const kept = JSON.parse(localStorage.getItem(key));
        if (kept && Date.now() - kept.at < 3600e3) return show(kept.n);
      } catch {}
      fetch("https://api.github.com/repos/baocode-dev/baocode")
        .then((res) => (res.ok ? res.json() : null))
        .then((repo) => {
          if (typeof repo?.stargazers_count !== "number") return;
          show(repo.stargazers_count);
          try { localStorage.setItem(key, JSON.stringify({ n: repo.stargazers_count, at: Date.now() })); } catch {}
        })
        .catch(() => {});
    })();
  