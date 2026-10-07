# baocode.dev

The BaoCode website, hosted on Cloudflare, with no build step: `site/` is
served as it is, `/download` being `download.html`.

- English at the root, Chinese under `zh/` (`/zh/`, `/zh/download`,
  `/zh/changelog`); each page links to itself in the other language. A
  change to a page's copy goes into both. The Chinese pages use absolute
  paths (`/style.css`, `/shots/…`); the screenshots are shared.
- `changelog.html`, `zh/changelog.html`: made by
  `dart run tool/build_changelog.dart` from `release-notes/`. Edit those.

- `shots/`: the screenshots on the page.
- `sounds/`: the notification sound the page plays.
- Copy marked `<mark class="todo">` is still to be written.
