# baocode.dev

The BaoCode website, hosted on Cloudflare: `site/` is served as it is,
`/download` being `download.html`.

- The home page, `index.html` and `zh/index.html`, is made from
  `site-redesign/zcode-style.html` (both languages' words in its `#i18n`
  block) by `node site-redesign/build.mjs`, into `site-redesign/dist/`
  with the rest of `site/`; `rsync -a site-redesign/dist/ site/` puts it
  here. `node site-redesign/serve.mjs` serves `dist/` as the site does,
  its Content-Security-Policy too. Its scripts and styles go to `home/`,
  the icons it shows are bundled, nothing is loaded from elsewhere. The
  other pages share `style.css` (its source `site-redesign/style.css`).

- English at the root, Chinese under `zh/` (`/zh/`, `/zh/download`,
  `/zh/changelog`); each page links to itself in the other language. A
  change to a page's copy goes into both. The Chinese pages use absolute
  paths (`/style.css`, `/mocks/…`); the figures are shared.
- `changelog.html`, `zh/changelog.html`: made by
  `dart run tool/build_changelog.dart` from `release-notes/`. Edit those.

- `import.html`, `import.js`: a site's one-click import of an upstream,
  handed on to the app (`baocode://provider/import`); `upstreams.html`, how
  a site adds it. See `docs/upstream-import.md`.
- Light or dark: the system's, or the one picked with the header's button
  (kept as `baocode.theme`), set by `head.js` as `<html data-theme>` before
  the page shows; the styles' light colors are under
  `:root[data-theme="light"]`, and the home page's scripts follow
  `window.baoTheme`.
- `site.js` keeps, on any page, where a visitor came from (`?abc` after
  any page's address, the site linking here, or direct); `head.js`,
  `activate.html`, `activate.js`, `channels.json` and `channels/`: the
  channels listed (lib/channel/). A channel asks to be listed with the
  `channel` issue template.
- `readme/`: the README's pictures, by `node site-redesign/readme-shots.mjs`.
- `mocks/`: the windows in the old home page's figures, drawn in HTML (not
  screenshots) and framed by it: each drawn at its own width (`data-w`) and
  scaled to the frame's by `mock.js`; both languages in one file (`.z`,
  `.e`, `?lang=en`), a theme by `?theme=light|kimbie|dark`, a part shown by
  `?show=`. Their icons are codicons, in a font of only those used:
  `tool/make_mock_icons.py` (needs fonttools) remakes it and its rules in
  `mock.css` after an icon is added.
- `shots/`: screenshots, `main.png` the README's.
- `sounds/`: the notification sound the page plays.
- `reviews/`: the avatars on the home page's reel of what users say (the
  words are in `site-redesign/zcode-style.html`). "Say a word"
  under it sends a visitor's to stats.baocode.dev (`/v1/review`, in the
  private baocode.dev repository), seen on its dashboard.
- `push.html`, `zh/push.html`: pushing the iPhone app from the user's own
  scripts (`push.baocode.dev/v1/notify/<key>`, in the private baocode.dev
  repository), linked from the app's notification settings.
- `qr/`: the phone cards' QR codes, made by
  `dart run tool/make_download_qr.dart`.
- Copy marked `<mark class="todo">` is still to be written.
