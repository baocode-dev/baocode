
    // The page's slow animations share one beat of about 30 frames a
    // second. A timer wakes it, so the frames in between are left alone
    // (asking for every frame and skipping most still costs each one).
    // A callback returning false leaves the beat; it ends with the last.
    window.baoTicker = (() => {
      const subs = new Set();
      let armed = false;
      function fire(now) {
        armed = false;
        for (const f of [...subs]) if (f(now) === false) subs.delete(f);
        arm();
      }
      function arm() {
        if (armed || !subs.size) return;
        armed = true;
        setTimeout(() => requestAnimationFrame(fire), 26);
      }
      return { add(f) { subs.add(f); arm(); } };
    })();
  