
    // The tools BaoCode Bash runs in-process on Windows, the ones agents
    // reach for most first. Each row is doubled so the drift loops.
    (() => {
      const box = document.getElementById("winTools");
      const rows = [
        [["jq", "lucide:braces"], ["bash", "lucide:square-terminal"], ["rg", "lucide:scan-search"], ["grep", "lucide:text-search"], ["sed", "lucide:replace"],
         ["awk", "lucide:table-2"], ["find", "lucide:folder-search"], ["fd", "lucide:file-search"], ["xargs", "lucide:workflow"]],
        [["cat", "lucide:cat"], ["ls", "lucide:list-tree"], ["head", "lucide:arrow-up-to-line"], ["tail", "lucide:arrow-down-to-line"], ["wc", "lucide:hash"],
         ["sort", "lucide:arrow-down-a-z"], ["uniq", "lucide:list-filter"], ["cut", "lucide:scissors"], ["tr", "lucide:arrow-right-left"], ["diff", "lucide:git-compare"]],
        [["tar", "lucide:package"], ["cp", "lucide:copy"], ["mv", "lucide:move"], ["rm", "lucide:trash"], ["mkdir", "lucide:folder-plus"], ["rsync", "lucide:refresh-cw"],
         ["sha256sum", "lucide:fingerprint-pattern"], ["base64", "lucide:binary"], ["cygpath", "lucide:route"], ["timeout", "lucide:timer"]],
      ];
      const hi = new Set(["bash", "rg", "sed", "jq", "diff", "rsync"]);
      const tile = ([name, icon]) =>
        `<span${hi.has(name) ? ' class="hi"' : ""}><iconify-icon icon="${icon}"></iconify-icon>${name}</span>`;
      box.innerHTML = rows.map((r) => `<div class="v-win-row">${[...r, ...r].map(tile).join("")}</div>`).join("");
      new IntersectionObserver(([e]) => box.classList.toggle("is-live", e.isIntersecting)).observe(box);
    })();
  