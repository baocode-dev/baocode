import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

List<md.Element> _elements(String markdown, String tag) {
  final nodes = MarkdownView.document(tags: true).parse(markdown);
  final result = <md.Element>[];
  void walk(md.Node node) {
    if (node is md.Element) {
      if (node.tag == tag) result.add(node);
      node.children?.forEach(walk);
    }
  }

  nodes.forEach(walk);
  return result;
}

void main() {
  test('parses local markdown images whose paths contain spaces', () {
    const path =
        '/Users/leokun/Library/Application Support/baocode/shots/01.png';
    for (final input in ['![demo]($path)', '![demo](<$path>)']) {
      final imgs = _elements(input, 'img');
      expect(imgs, hasLength(1), reason: 'Failed for $input');
      expect(FileLink.parseHref(imgs.single.attributes['src'])?.path, path);
      expect(imgs.single.attributes['alt'], 'demo');
    }
  });

  test('parses local markdown links whose paths contain spaces', () {
    const planPath =
        '/Users/leokun/Library/Application Support/baocode/antigravity/home/antigravity-cli/brain/80085e63-baed-41a6-87fb-b03622f7d0ad/.system_generated/swarm/plan.json';
    final links = _elements(
      '已命名蜂群，写入 [plan.json]($planPath)，并启动成员：',
      'a',
    );
    expect(links, hasLength(1));
    expect(links.single.textContent, 'plan.json');
    expect(FileLink.parseHref(links.single.attributes['href'])?.path, planPath);

    // Line ranges, folders, Windows paths, relative spaced paths, SSH paths, and inline-formatted labels.
    final cases = <(String, String, String, FileLineRange?)>[
      (
        '[notes.md:10](/Users/me/My Project/docs/notes.md#L10-L20)',
        'notes.md:10',
        '/Users/me/My Project/docs/notes.md',
        const FileLineRange(10, 20),
      ),
      (
        '[docs/](/Users/me/My Project/docs/)',
        'docs/',
        '/Users/me/My Project/docs/',
        null,
      ),
      (
        '[config.json](C:/Program Files/BaoCode/config.json#L5)',
        'config.json',
        'C:/Program Files/BaoCode/config.json',
        const FileLineRange(5),
      ),
      (
        '[readme](My Folder/readme.md)',
        'readme',
        'My Folder/readme.md',
        null,
      ),
      (
        '[app.log](ssh://devbox/var/my logs/app.log#L120)',
        'app.log',
        '/var/my logs/app.log',
        const FileLineRange(120),
      ),
      (
        '[`plan.json`]($planPath)',
        'plan.json',
        planPath,
        null,
      ),
    ];

    for (final (input, label, expectedPath, expectedRange) in cases) {
      final parsed = _elements(input, 'a');
      expect(parsed, hasLength(1), reason: 'Failed for $input');
      expect(parsed.single.textContent, label, reason: 'Label for $input');
      final fileLink = FileLink.parseHref(parsed.single.attributes['href']);
      expect(fileLink?.path, expectedPath, reason: 'Path for $input');
      expect(fileLink?.range, expectedRange, reason: 'Range for $input');
    }
  });

  test('does not hijack standard links with titles, prose, or inline code', () {
    // Standard links with double-quoted or single-quoted titles.
    final doubleQuoted = _elements('[site](https://example.com "Title")', 'a');
    expect(doubleQuoted, hasLength(1));
    expect(doubleQuoted.single.attributes['href'], 'https://example.com');
    expect(doubleQuoted.single.attributes['title'], 'Title');

    final singleQuoted = _elements("[file](/Users/me/a.dart 'My Title')", 'a');
    expect(singleQuoted, hasLength(1));
    expect(singleQuoted.single.attributes['href'], '/Users/me/a.dart');
    expect(singleQuoted.single.attributes['title'], 'My Title');

    // Inline code must stay code, not become a link.
    expect(_elements('`[plan.json](/Users/a b/plan.json)`', 'a'), isEmpty);
    expect(_elements('`[plan.json](/Users/a b/plan.json)`', 'code'), hasLength(1));

    // Plain parenthetical text with no path separator must not become a link.
    expect(_elements('[foo](bar baz)', 'a'), isEmpty);

    // Two normal links on the same line must stay two separate links.
    final pair = _elements('[a](/tmp/a.dart) and [b](/tmp/b.dart)', 'a');
    expect(pair, hasLength(2));
    expect(pair[0].attributes['href'], '/tmp/a.dart');
    expect(pair[1].attributes['href'], '/tmp/b.dart');
  });
}
