import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/explorer_line_count.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:path/path.dart' as p;

import 'workbench/fake_files.dart';

void main() {
  group('IdeExplorerLineCount', () {
    test('formatBadge formats compact line counts correctly', () {
      expect(IdeExplorerLineCount.formatBadge(0), '0');
      expect(IdeExplorerLineCount.formatBadge(1), '1');
      expect(IdeExplorerLineCount.formatBadge(42), '42');
      expect(IdeExplorerLineCount.formatBadge(99), '99');
      expect(IdeExplorerLineCount.formatBadge(100), '1h');
      expect(IdeExplorerLineCount.formatBadge(642), '6h');
      expect(IdeExplorerLineCount.formatBadge(999), '9h');
      expect(IdeExplorerLineCount.formatBadge(1000), '1k');
      expect(IdeExplorerLineCount.formatBadge(1300), '1.3k');
      expect(IdeExplorerLineCount.formatBadge(1400), '1.4k');
      expect(IdeExplorerLineCount.formatBadge(1500), '1.5k');
      expect(IdeExplorerLineCount.formatBadge(4200), '4.2k');
      expect(IdeExplorerLineCount.formatBadge(9999), '10k');
      expect(IdeExplorerLineCount.formatBadge(10000), '10k');
      expect(IdeExplorerLineCount.formatBadge(12500), '12.5k');
      expect(IdeExplorerLineCount.formatBadge(50000), '50k');
    });

    test('countLines counts newlines in byte buffer', () {
      expect(IdeExplorerLineCount.countLines(Uint8List(0)), 0);
      expect(
        IdeExplorerLineCount.countLines(utf8.encode('single line')),
        1,
      );
      expect(
        IdeExplorerLineCount.countLines(utf8.encode('line 1\nline 2')),
        2,
      );
      expect(
        IdeExplorerLineCount.countLines(utf8.encode('line 1\r\nline 2\r\n')),
        3,
      );
    });

    test('shouldIgnore filters based on extension, folders, and enabled state', () {
      final lineCount = IdeExplorerLineCount(
        files: TreeFiles(const {}),
        paths: p.posix,
      );

      // Allowed extensions
      expect(lineCount.shouldIgnore('/project/src/index.ts'), isFalse);
      expect(lineCount.shouldIgnore('/project/src/App.tsx'), isFalse);
      expect(lineCount.shouldIgnore('/project/lib/main.dart'), isFalse);

      // Disallowed extensions
      expect(lineCount.shouldIgnore('/project/assets/image.png'), isTrue);
      expect(lineCount.shouldIgnore('/project/binary.exe'), isTrue);

      // Ignored folders
      expect(lineCount.shouldIgnore('/project/node_modules/pkg/index.js'), isTrue);
      expect(lineCount.shouldIgnore('/project/.git/config'), isTrue);
      expect(lineCount.shouldIgnore('/project/build/out.js'), isTrue);

      // Disabled setting
      lineCount.enabled = false;
      expect(lineCount.shouldIgnore('/project/src/index.ts'), isTrue);
    });

    test('decorationFor loads, caches and produces line decoration', () async {
      final tree = TreeFiles({
        '/project/lib/small.dart': 'a\nb\nc\n', // 4 lines
        '/project/lib/hundreds.dart': List.filled(642, 'x').join('\n'), // 642 lines
      });

      final lineCount = IdeExplorerLineCount(
        files: tree,
        paths: p.posix,
      );
      addTearDown(lineCount.dispose);

      // Initial query triggers async fetch and returns null
      var decoration = lineCount.decorationFor('/project/lib/hundreds.dart');
      expect(decoration, isNull);

      // Wait for fetch and notification
      await pumpEventQueue();

      decoration = lineCount.decorationFor('/project/lib/hundreds.dart');
      expect(decoration, isNotNull);
      expect(decoration!.letter, '6h');
      expect(decoration.tooltip, '642 lines');

      // Small file
      lineCount.decorationFor('/project/lib/small.dart');
      await pumpEventQueue();

      final smallDeco = lineCount.decorationFor('/project/lib/small.dart');
      expect(smallDeco, isNotNull);
      expect(smallDeco!.letter, '4');
      expect(smallDeco.tooltip, '4 lines');

      // Invalidation clears cache
      lineCount.invalidate('/project/lib/hundreds.dart');
      expect(lineCount.decorationFor('/project/lib/hundreds.dart'), isNull);
    });

    test('merges line decoration with git decoration into combined badge', () async {
      final tree = TreeFiles({
        '/project/src/PayableDetail.tsx': List.filled(642, 'code').join('\n'),
      });

      final lineCount = IdeExplorerLineCount(
        files: tree,
        paths: p.posix,
      );
      addTearDown(lineCount.dispose);

      lineCount.decorationFor('/project/src/PayableDetail.tsx');
      await pumpEventQueue();

      final lineDeco = lineCount.decorationFor('/project/src/PayableDetail.tsx')!;
      expect(lineDeco.letter, '6h');

      // Untracked Git decoration
      const gitDeco = IdeGitDecoration(
        colorId: 'gitDecoration.untrackedResourceForeground',
        letter: 'U',
        tooltip: 'Untracked',
      );

      final merged = lineDeco.merge(gitDeco);
      expect(merged.letter, '6h, U');
      expect(merged.tooltip, '642 lines • Untracked');
      expect(merged.colorId, 'gitDecoration.untrackedResourceForeground');
    });

    test('exceeding maxFileSize marks file too large', () async {
      final tree = TreeFiles({
        '/project/src/huge.ts': 'x\n' * 50,
      });

      final lineCount = IdeExplorerLineCount(
        files: tree,
        paths: p.posix,
        maxFileSize: 10, // tiny limit for test
      );
      addTearDown(lineCount.dispose);

      lineCount.decorationFor('/project/src/huge.ts');
      await pumpEventQueue();

      final deco = lineCount.decorationFor('/project/src/huge.ts');
      expect(deco, isNotNull);
      expect(deco!.letter, isNull);
      expect(deco.tooltip, contains('File limit exceeded'));
    });
  });
}
