import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/line_diff.dart';
import 'package:baocode/chat/chat_models.dart' show DiffLineType;
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

/// The links' addresses and the inline code in [markdown], as the chat
/// parses it.
({List<String> hrefs, List<String> code}) _parsed(String markdown) {
  final hrefs = <String>[], code = <String>[];
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'a') hrefs.add(node.attributes['href']!);
    if (node.tag == 'code' && node.attributes['class'] == null) {
      code.add(node.textContent);
    }
    node.children?.forEach(visit);
  }

  MarkdownView.document().parse(markdown).forEach(visit);
  return (hrefs: hrefs, code: code);
}

void main() {
  group('a link\'s address', () {
    test('a path relative to where the agent works, alone or at lines', () {
      expect(FileLink.parseHref('lib/a.dart'), const FileLink('lib/a.dart'));
      expect(
        FileLink.parseHref('lib/a.dart#L12'),
        const FileLink('lib/a.dart', FileLineRange(12)),
      );
      expect(
        FileLink.parseHref('lib/a.dart#L12-L20'),
        const FileLink('lib/a.dart', FileLineRange(12, 20)),
      );
      expect(
        FileLink.parseHref('lib/a.dart#L12-20'),
        const FileLink('lib/a.dart', FileLineRange(12, 20)),
      );
      expect(
        FileLink.parseHref('lib/a.dart#L12C5'),
        const FileLink('lib/a.dart', FileLineRange(12, null, 5)),
      );
    });

    test('a line, a line and column, or lines after a colon', () {
      expect(
        FileLink.parseHref('lib/a.dart:12'),
        const FileLink('lib/a.dart', FileLineRange(12)),
      );
      expect(
        FileLink.parseHref('lib/a.dart:12:5'),
        const FileLink('lib/a.dart', FileLineRange(12, null, 5)),
      );
      expect(
        FileLink.parseHref('lib/a.dart:12-20'),
        const FileLink('lib/a.dart', FileLineRange(12, 20)),
      );
    });

    test('absolute paths, Windows\' and file:// ones', () {
      expect(
        FileLink.parseHref('/Users/me/p/lib/a.dart#L3'),
        const FileLink('/Users/me/p/lib/a.dart', FileLineRange(3)),
      );
      expect(
        FileLink.parseHref(r'C:\p\lib\a.dart:7'),
        const FileLink(r'C:\p\lib\a.dart', FileLineRange(7)),
      );
      expect(
        FileLink.parseHref('C:/p/lib/a.dart'),
        const FileLink('C:/p/lib/a.dart'),
      );
      expect(
        FileLink.parseHref('file:///Users/me/p/a%20b.dart#L2'),
        const FileLink('/Users/me/p/a b.dart', FileLineRange(2)),
      );
      expect(
        FileLink.parseHref('file:///C:/p/a.dart'),
        const FileLink('C:/p/a.dart'),
      );
    });

    test('spaces, escaped or in angle brackets', () {
      expect(
        FileLink.parseHref('docs/release%20notes.md#L3'),
        const FileLink('docs/release notes.md', FileLineRange(3)),
      );
      expect(
        FileLink.parseHref('<docs/release notes.md>'),
        const FileLink('docs/release notes.md'),
      );
    });

    test('a heading\'s anchor in a file is the file', () {
      expect(
        FileLink.parseHref('README.md#usage'),
        const FileLink('README.md'),
      );
    });

    test('not a file: the web, mail, other schemes, an anchor, nothing', () {
      for (final href in [
        'https://example.com/a.dart',
        'http://localhost:8080',
        'mailto:a@b.c',
        'vscode://file/a.dart',
        '#usage',
        '',
        '   ',
        null,
      ]) {
        expect(FileLink.parseHref(href), isNull, reason: '$href');
      }
    });
  });

  group('inline code', () {
    test('a path, with a line, a column or lines', () {
      expect(FileLink.parseText('lib/a.dart'), const FileLink('lib/a.dart'));
      expect(FileLink.parseText('README.md'), const FileLink('README.md'));
      expect(
        FileLink.parseText('lib/a.dart:42'),
        const FileLink('lib/a.dart', FileLineRange(42)),
      );
      expect(
        FileLink.parseText('lib/a.dart:42:7'),
        const FileLink('lib/a.dart', FileLineRange(42, null, 7)),
      );
      expect(
        FileLink.parseText('src/app.ts#L10-L12'),
        const FileLink('src/app.ts', FileLineRange(10, 12)),
      );
      expect(
        FileLink.parseText(r'C:\repo\main.rs:12:5'),
        const FileLink(r'C:\repo\main.rs', FileLineRange(12, null, 5)),
      );
      expect(FileLink.parseText('.github/workflows/ci.yml'), isNotNull);
    });

    test('code that is not a path', () {
      for (final code in [
        'foo',
        'setState()',
        'a = b',
        'x.y.z()',
        '1.5',
        '...',
        '--verbose',
        'flutter test lib/a.dart',
        'https://example.com/a.dart',
        '"lib/a.dart"',
        '/',
        'Map<String, int>',
      ]) {
        expect(FileLink.parseText(code), isNull, reason: code);
      }
    });

    test('a search\'s match may have spaces', () {
      expect(FileLink.parseText('docs/release notes.md:3'), isNull);
      expect(
        FileLink.parseText('docs/release notes.md:3', blanks: true),
        const FileLink('docs/release notes.md', FileLineRange(3)),
      );
    });
  });

  group('kept to the project', () {
    test('relative paths join it; those outside are refused', () {
      expect(
        const FileLink('lib/a.dart').resolveIn('/p'),
        p.join('/p', 'lib', 'a.dart'),
      );
      expect(const FileLink('/p/lib/a.dart').resolveIn('/p'), '/p/lib/a.dart');
      expect(const FileLink('../etc/passwd').resolveIn('/p'), isNull);
      expect(const FileLink('/etc/passwd').resolveIn('/p'), isNull);
      expect(const FileLink('~/a.dart').resolveIn('/p'), isNull);
      expect(const FileLink('lib/../../x').resolveIn('/p'), isNull);
    });

    test('a Windows project\'s paths, as its host spells them', () {
      final windows = p.Context(style: p.Style.windows);
      expect(
        const FileLink('lib/a.dart').resolveIn(r'C:\p', paths: windows),
        r'C:\p\lib\a.dart',
      );
      expect(
        const FileLink(r'C:\p\lib\a.dart').resolveIn(r'C:\p', paths: windows),
        r'C:\p\lib\a.dart',
      );
      expect(
        const FileLink(r'D:\other\a.dart').resolveIn(r'C:\p', paths: windows),
        isNull,
      );
    });
  });

  test('a Read\'s lines', () {
    expect(FileLineRange.parseDetail('L10-60'), const FileLineRange(10, 60));
    expect(FileLineRange.parseDetail('L3'), const FileLineRange(3));
    expect(FileLineRange.parseDetail('3 results'), isNull);
    expect(FileLineRange.parseDetail(null), isNull);
  });

  test('what the agent typically writes, as the chat parses it', () {
    const reply = '''
I changed [chat_screen.dart](lib/chat/chat_screen.dart#L42) and
[the strip](lib/chat/panels/activity_strip.dart#L10-L30), and added
[notes](<docs/release notes.md#L3>). The entry point is `lib/main.dart:12`,
see also `pubspec.yaml` and [the site](https://baocode.dev).

- [workbench.dart:2530](lib/workbench.dart#L2530)
- `flutter test` runs them
''';
    final (:hrefs, :code) = _parsed(reply);
    final links = [for (final href in hrefs) FileLink.parseHref(href)];
    expect(links, [
      const FileLink('lib/chat/chat_screen.dart', FileLineRange(42)),
      const FileLink(
        'lib/chat/panels/activity_strip.dart',
        FileLineRange(10, 30),
      ),
      const FileLink('docs/release notes.md', FileLineRange(3)),
      null,
      const FileLink('lib/workbench.dart', FileLineRange(2530)),
    ]);
    expect(
      [for (final text in code) FileLink.parseText(text)],
      [
        const FileLink('lib/main.dart', FileLineRange(12)),
        const FileLink('pubspec.yaml'),
        null,
      ],
    );
  });

  test('Claude Code is asked to point at files as links the chat opens', () {
    final arguments = const ClaudeLaunch(cwd: '/p').arguments;
    final at = arguments.indexOf('--append-system-prompt');
    expect(at, isNot(-1));
    // One flag: Claude Code takes the last of several.
    expect(arguments.where((a) => a == '--append-system-prompt'), hasLength(1));
    final prompt = arguments[at + 1];
    expect(prompt, contains(ClaudeLaunch.citingCode));
    expect(prompt, contains(ClaudeLaunch.fileLinks));
    expect(ClaudeLaunch.fileLinks, contains('#L42-L58'));
    // Its examples parse as it asks them to be written.
    expect(
      FileLink.parseHref('path/relative/to/working/directory#L42'),
      const FileLink('path/relative/to/working/directory', FileLineRange(42)),
    );
    final (:hrefs, code: _) = _parsed(
      '[notes.md](<docs/release notes.md#L3>) '
      '[chat_screen.dart:42](lib/chat/chat_screen.dart#L42)',
    );
    expect(
      [for (final href in hrefs) FileLink.parseHref(href)],
      [
        const FileLink('docs/release notes.md', FileLineRange(3)),
        const FileLink('lib/chat/chat_screen.dart', FileLineRange(42)),
      ],
    );
  });

  group('a file\'s diff', () {
    test('every line, those removed before those added in their place', () {
      final rows = fileDiff('a\nb\nc\n', 'a\nB\nc\nd\n');
      expect(
        [
          for (final row in rows)
            (row.type, row.text, row.original, row.modified),
        ],
        [
          (DiffLineType.context, 'a', 1, 1),
          (DiffLineType.removed, 'b', 2, null),
          (DiffLineType.added, 'B', null, 2),
          (DiffLineType.context, 'c', 3, 3),
          (DiffLineType.added, 'd', null, 4),
        ],
      );
    });

    test('a file added or deleted is all of one side', () {
      expect(
        [for (final row in fileDiff('', 'x\ny')) row.type],
        [DiffLineType.added, DiffLineType.added],
      );
      expect(
        [for (final row in fileDiff('x\r\ny\r\n', '')) (row.type, row.text)],
        [(DiffLineType.removed, 'x'), (DiffLineType.removed, 'y')],
      );
    });

    test('past a few thousand characters it is compared off this isolate, '
        'the same rows', () async {
      String text(String word) =>
          [for (var i = 0; i < 60; i++) '$word $i ${'z' * 50}'].join('\n');
      final (before, after) = (text('before'), text('after'));
      List<(DiffLineType, String)> of(List<FileDiffRow> rows) => [
        for (final row in rows) (row.type, row.text),
      ];
      expect(
        of(await fileDiffAsync(before, after)),
        of(fileDiff(before, after)),
      );
      expect(of(await fileDiffAsync('a\n', 'b\n')), of(fileDiff('a\n', 'b\n')));
    });
  });
}
