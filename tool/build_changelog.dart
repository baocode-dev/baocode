// Writes the site's changelog from the release notes: site/changelog.html
// (English, baocode.dev/changelog) and site/zh/changelog.html (Chinese,
// baocode.dev/zh/changelog). Every version with notes in
// release-notes/<x.y.z>.<en|zh>.md, newest first, each at #v<x.y.z>, which
// the app's update notification links to (UpdateController.changelogUrl).
// A version without notes in a language shows its English ones there, as
// the app does (UpdateManifest.notesFor). Run from anywhere in the
// repository after writing a release's notes, and commit the pages with
// them:
//
//   dart run tool/build_changelog.dart
//
// The site has no build step: Cloudflare serves site/ as it is.
// test/tool/build_changelog_test.dart fails while the pages in site/ are
// not what the notes make.
import 'dart:io';

import 'package:baocode/update/version.dart';
import 'package:markdown/markdown.dart' as md;

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/build_changelog.dart');
    exit(1);
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final pages = changelogPages(readReleaseNotes(root));
  for (final MapEntry(key: path, value: html) in pages.entries) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(html);
    stdout.writeln(file.path);
  }
}

/// The notes in [root]'s release-notes/, by version, then by language.
Map<AppVersion, Map<String, String>> readReleaseNotes(Directory root) {
  final directory = Directory('${root.path}/release-notes');
  final notes = <AppVersion, Map<String, String>>{};
  if (!directory.existsSync()) return notes;
  final name = RegExp(r'^(\d+\.\d+\.\d+)\.(en|zh)\.md$');
  for (final file in directory.listSync().whereType<File>()) {
    final match = name.firstMatch(file.uri.pathSegments.last);
    if (match == null) continue;
    final text = file.readAsStringSync().trim();
    if (text.isEmpty) continue;
    (notes[AppVersion.parse(match[1]!)] ??= {})[match[2]!] = text;
  }
  return notes;
}

/// The changelog's pages for [notes], by their path in the repository.
Map<String, String> changelogPages(Map<AppVersion, Map<String, String>> notes) {
  final versions = notes.keys.toList()..sort((a, b) => b.compareTo(a));
  return {
    for (final page in _Page.values)
      page.path: _html(page, [
        for (final version in versions)
          (version, notes[version]![page.language] ?? notes[version]!['en']),
      ]),
  };
}

enum _Page {
  en(
    path: 'site/changelog.html',
    language: 'en',
    htmlLang: 'en',
    home: '/',
    title: 'BaoCode Changelog',
    heading: 'Changelog',
    lead: 'What changed in each version of BaoCode.',
    download: 'Download',
    empty: 'No versions yet.',
  ),
  zh(
    path: 'site/zh/changelog.html',
    language: 'zh',
    htmlLang: 'zh-CN',
    home: '/zh/',
    title: 'BaoCode 更新日志',
    heading: '更新日志',
    lead: 'BaoCode 每个版本的变化。',
    download: '下载',
    empty: '还没有版本。',
  );

  const _Page({
    required this.path,
    required this.language,
    required this.htmlLang,
    required this.home,
    required this.title,
    required this.heading,
    required this.lead,
    required this.download,
    required this.empty,
  });

  final String path;
  final String language;
  final String htmlLang;

  /// Where the page's language starts on the site: its links go there.
  final String home;
  final String title;
  final String heading;
  final String lead;
  final String download;
  final String empty;

  /// The page in the other language, which the header links to.
  _Page get other => this == en ? zh : en;

  String get url => '${home}changelog';

  /// The other language's name, as its speakers write it.
  String get name => this == en ? 'English' : '中文';
}

String _html(_Page page, List<(AppVersion, String?)> releases) {
  final entries = [
    for (final (version, notes) in releases)
      if (notes != null)
        '  <section class="release" id="v${version.marketing}">\n'
            '    <h2 class="plain"><a href="#v${version.marketing}">'
            '${version.marketing}</a></h2>\n'
            '${_markdown(notes)}'
            '  </section>\n',
  ];
  return '''
<!doctype html>
<html lang="${page.htmlLang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${page.title}</title>
<meta name="description" content="${page.lead}">
<link rel="icon" href="/icon.png">
<link rel="stylesheet" href="/style.css">
<link rel="alternate" hreflang="en" href="https://baocode.dev${_Page.en.url}">
<link rel="alternate" hreflang="zh" href="https://baocode.dev${_Page.zh.url}">
</head>
<body>
<!-- Made by tool/build_changelog.dart from release-notes/: edit those, not this. -->
<canvas class="grid" aria-hidden="true"></canvas>
<svg class="sprite" aria-hidden="true">
  <!-- Lucide (ISC), https://lucide.dev -->
  <symbol id="ic-github" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5c.08-1.25-.27-2.48-1-3.5c.28-1.15.28-2.35 0-3.5c0 0-1 0-3 1.5c-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.4 5.4 0 0 0 4 9c0 3.5 3 5.5 6 5.5c-.39.49-.68 1.05-.85 1.65S8.93 17.38 9 18v4"/><path d="M9 18c-4.51 2-5-2-7-2"/></g></symbol>
</svg>
<header class="top">
  <a class="brand" href="${page.home}"><img src="/icon.png" alt="">BaoCode</a>
  <a href="${page.home}download">${page.download}</a>
  <a href="${page.url}" aria-current="page">${page.heading}</a>
  <a href="https://github.com/baocode-dev/baocode"><svg class="ic" aria-hidden="true"><use href="#ic-github"/></svg>GitHub</a>
  <a class="lang" href="${page.other.url}" hreflang="${page.other.language}" lang="${page.other.htmlLang}">${page.other.name}</a>
</header>

<main class="page changelog">
  <h1>${page.heading}</h1>
  <p class="subtitle">${page.lead}</p>

${entries.isEmpty ? '  <p>${page.empty}</p>\n' : entries.join('\n')}</main>

<script src="/site.js"></script>
</body>
</html>
''';
}

/// [notes] as HTML, indented into its section.
String _markdown(String notes) {
  final html = md.markdownToHtml(
    notes,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  return [
    for (final line in html.trimRight().split('\n'))
      line.isEmpty ? '\n' : '    $line\n',
  ].join();
}
