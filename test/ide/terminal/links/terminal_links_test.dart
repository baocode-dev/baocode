// Tests of TerminalLinkDetection (terminal_links.dart): the detectors
// together on a headless terminal, as the renderer asks for a row's links
// and for the link under a cell. Files exist through a fake stat.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/terminal_link_parsing.dart';
import 'package:baocode/ide/terminal/links/terminal_link_resolver.dart';
import 'package:baocode/ide/terminal/links/terminal_links.dart';
import 'package:bao_xterm/headless/public/terminal.dart';
import 'package:bao_xterm/typings/xterm_headless.dart' hide Terminal;

IBufferRange range((int, int) start, (int, int) end) => IBufferRange(
  start: IBufferCellPosition(x: start.$1, y: start.$2),
  end: IBufferCellPosition(x: end.$1, y: end.$2),
);

void main() {
  late Terminal xterm;
  late Map<String, bool> files;
  late TerminalLinkDetection links;

  TerminalLinkDetection create({
    bool enableFileLinks = true,
    String initialCwd = '/work',
  }) => TerminalLinkDetection(
    xterm,
    resolver: TerminalFileLinkResolver(
      os: OperatingSystem.linux,
      userHome: '/home',
      stat: (path) async => files[path],
    ),
    initialCwd: initialCwd,
    os: OperatingSystem.linux,
    enableFileLinks: enableFileLinks,
    workspaceFolders: ['/work'],
  );

  Future<void> write(String data) {
    final written = Completer<void>();
    xterm.write(data, written.complete);
    return written.future;
  }

  setUp(() {
    xterm = Terminal(ITerminalOptions(cols: 50, rows: 10));
    files = {'/work/src/foo.ts': false, '/work/src': true, '/tmp': true};
    links = create();
  });

  tearDown(() {
    xterm.dispose();
  });

  group('TerminalLinkDetection', () {
    test('gives a row its links by priority, without overlaps', () async {
      await write('see src/foo.ts:12:5 and https://x.org/a');
      final found = await links.provideLinks(0);
      expect(
        [for (final link in found) (link.type, link.text, link.range)],
        [
          (
            TerminalLinkType.localFile,
            'src/foo.ts:12:5',
            range((5, 1), (19, 1)),
          ),
          (TerminalLinkType.url, 'https://x.org/a', range((25, 1), (39, 1))),
          (TerminalLinkType.search, 'see', range((1, 1), (3, 1))),
          (TerminalLinkType.search, 'and', range((21, 1), (23, 1))),
        ],
      );
    });

    test('finds the link under a cell', () async {
      await write('see src/foo.ts:12:5 and https://x.org/a');

      final file = (await links.linkAt(10, 0))!;
      expect(file.type, TerminalLinkType.localFile);
      expect(file.path, '/work/src/foo.ts');
      expect(file.uri, Uri.parse('file:///work/src/foo.ts'));
      expect((file.line, file.column), (12, 5));
      expect(file.label, 'Open file in editor');
      expect(file.isHighConfidence, isTrue);

      final url = (await links.linkAt(30, 0))!;
      expect(url.type, TerminalLinkType.url);
      expect(url.uri, Uri.parse('https://x.org/a'));
      expect(url.path, isNull);
      expect(url.line, isNull);
      expect(url.label, 'Follow link');

      final word = (await links.linkAt(0, 0))!;
      expect(word.type, TerminalLinkType.search);
      expect(word.searchText, 'see');
      expect(word.label, 'Search workspace');
      expect(word.isHighConfidence, isFalse);

      expect(await links.linkAt(3, 0), isNull);
      expect(await links.linkAt(0, 5), isNull);
    });

    test('gives every row of a wrapped line the whole line\'s links', () async {
      await write('${'x' * 45} https://example.com/some/long/path');
      final url = (await links.linkAt(2, 1))!;
      expect(url.type, TerminalLinkType.url);
      expect(url.text, 'https://example.com/some/long/path');
      expect(url.range, range((47, 1), (30, 2)));
      expect((await links.linkAt(46, 0))!.range, url.range);
      expect(await links.linkAt(45, 0), isNull);
      expect(await links.linkAt(30, 1), isNull);
    });

    test('folders are revealed in the workspace, opened outside', () async {
      await write('ls ./src /tmp');
      final inside = (await links.linkAt(4, 0))!;
      expect(inside.type, TerminalLinkType.localFolder);
      expect(inside.inWorkspace, isTrue);
      expect(inside.path, '/work/src');
      expect(inside.label, 'Focus folder in explorer');
      final outside = (await links.linkAt(10, 0))!;
      expect(outside.type, TerminalLinkType.localFolder);
      expect(outside.inWorkspace, isFalse);
      expect(outside.label, 'Open folder in new window');
    });

    test('opens a ripgrep result at its line and column', () async {
      await write('src/foo.ts\r\n  7:3  error  Unexpected');
      final link = (await links.linkAt(3, 1))!;
      expect(link.type, TerminalLinkType.localFile);
      expect(link.path, '/work/src/foo.ts');
      expect((link.line, link.column), (7, 3));
      expect(link.text, '7:3');
      // The whole line is the link.
      expect(link.range, range((1, 2), (24, 2)));
    });

    test('opens a git diff hunk at the new file\'s range', () async {
      await write('+++ b/src/foo.ts\r\n@@ -1,2 +10,4 @@ class Foo');
      final link = (await links.linkAt(0, 1))!;
      expect(link.type, TerminalLinkType.localFile);
      expect(link.path, '/work/src/foo.ts');
      expect((link.line, link.column, link.endLine), (10, 1, 14));
    });

    test('without file links, paths are words', () async {
      links = create(enableFileLinks: false);
      await write('see src/foo.ts:12:5');
      final link = (await links.linkAt(6, 0))!;
      expect(link.type, TerminalLinkType.search);
      expect(link.text, 'src/foo.ts:12:5');
      expect(link.searchText, 'src/foo.ts:12:5');
    });

    test('resolves relative paths once the cwd is known', () async {
      links = create(initialCwd: '');
      await write('src/foo.ts');
      expect((await links.linkAt(0, 0))!.type, TerminalLinkType.search);
      links.initialCwd = '/work';
      expect((await links.linkAt(0, 0))!.type, TerminalLinkType.localFile);
    });

    test('a word link searches with its context\'s line', () async {
      await write('"bar.ts", line 10');
      final link = (await links.linkAt(2, 0))!;
      expect(link.type, TerminalLinkType.search);
      expect(link.text, 'bar.ts');
      expect(link.searchText, 'bar.ts:10');
    });

    test('word separators can change', () async {
      await write('a.b');
      expect((await links.linkAt(0, 0))!.text, 'a.b');
      links.wordSeparators = '.';
      expect((await links.linkAt(0, 0))!.text, 'a');
    });
  });

  group('terminalSearchLinkText', () {
    String text(String link, {String? contextLine}) => terminalSearchLinkText(
      link,
      contextLine: contextLine,
      os: OperatingSystem.linux,
      workspaceFolders: ['/code/baocode'],
    );

    test('drops file:// and ./ prefixes', () {
      expect(text('file:///foo.ts'), 'foo.ts');
      expect(text('./foo.ts'), 'foo.ts');
      expect(text('../../foo.ts'), 'foo.ts');
    });

    test('drops trailing text after the line and column', () {
      expect(text('Test.tsx:12:45.'), 'Test.tsx:12:45');
      expect(text('foo.rb:12:in'), 'foo.rb:12');
    });

    test('takes the line from the context', () {
      expect(text('foo', contextLine: '"foo", line 10'), 'foo:10');
      expect(text('foo', contextLine: 'foo(3, 4)'), 'foo:3:4');
    });

    test('drops a workspace folder name', () {
      expect(text('baocode/lib/a.dart'), 'lib/a.dart');
    });
  });
}
