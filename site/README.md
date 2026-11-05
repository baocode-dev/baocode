# baocode.dev

The BaoCode website, hosted on Cloudflare, with no build step: `site/` is
served as it is, `/download` being `download.html`.

- English at the root, Chinese under `zh/` (`/zh/`, `/zh/download`,
  `/zh/changelog`); each page links to itself in the other language. A
  change to a page's copy goes into both. The Chinese pages use absolute
  paths (`/style.css`, `/shots/…`); the screenshots are shared.
- `changelog.html`, `zh/changelog.html`: made by
  `dart run tool/build_changelog.dart` from `release-notes/`. Edit those.

- `import.html`, `import.js`: a site's one-click import of an upstream,
  handed on to the app (`baocode://provider/import`); `upstreams.html`, how
  a site adds it. See `docs/upstream-import.md`.
- `site.js` keeps, on any page, where a visitor came from (`?abc` after
  any page's address, the site linking here, or direct); `head.js`,
  `activate.html`, `activate.js`, `channels.json` and `channels/`: the
  channels listed (lib/channel/). A channel asks to be listed with the
  `channel` issue template.
- `shots/`: the screenshots on the page.
- `sounds/`: the notification sound the page plays.
- `reviews/`: the avatars on the home page's reel of what users say (the
  words are in the pages, translated on the English one). "Say a word"
  under it sends a visitor's to stats.baocode.dev (`/v1/review`, in the
  private baocode.dev repository), seen on its dashboard. The README's
  picture of them, `docs/readme/reviews*.png`, is drawn as HTML and
  screenshot.
- `qr/`: the phone cards' QR codes, made by
  `dart run tool/make_download_qr.dart`.
- Copy marked `<mark class="todo">` is still to be written.
