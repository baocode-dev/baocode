import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/ide/ide_fuzzy.dart';
import 'package:baocode/ide/ide_quick_open.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/project_tools.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:path/path.dart' as p;

import 'fake_files.dart';

void main() {
  group('fuzzy', () {
    test('matches in order, ignoring case, and rejects others', () {
      expect(ideFuzzyMatch('wb', 'ide_workbench.dart')!.positions, [4, 8]);
      expect(ideFuzzyMatch('IWD', 'ide_workbench.dart'), isNotNull);
      expect(ideFuzzyMatch('bw', 'ide_workbench.dart'), isNull);
      expect(ideFuzzyMatch('', 'x')!.positions, isEmpty);
      expect(ideFuzzyMatch('long', 'lo'), isNull);
    });

    test('prefers contiguous runs and word starts', () {
      final contiguous = ideFuzzyMatch('bench', 'ide_workbench.dart')!;
      expect(contiguous.positions, [8, 9, 10, 11, 12]);
      final scattered = ideFuzzyMatch('bench', 'b_e_n_c_h_x')!;
      expect(contiguous.score, greaterThan(scattered.score - 100));
      final start = ideFuzzyMatch('ts', 'tab_state.dart')!;
      final middle = ideFuzzyMatch('ts', 'hints.dart')!;
      expect(start.score, greaterThan(middle.score));
    });

    test('file names outrank folder matches; paths split positions', () {
      final name = scoreFilePath('edit', 'lib/ide/ide_editor.dart')!;
      final folder = scoreFilePath('edit', 'lib/editor/x/main.dart')!;
      expect(name.score, greaterThan(folder.score));
      expect(name.description, isEmpty);
      expect(folder.label, isEmpty);
      expect(folder.description, [4, 5, 6, 7]);
      final path = scoreFilePath('ide/main', 'lib/ide/main.dart')!;
      expect(path.label, [0, 1, 2, 3]);
      // The separator itself belongs to neither part.
      expect(path.description, [4, 5, 6]);
    });

    test('quick open queries parse :line[:column]', () {
      final plain = IdeQuickOpenQuery.parse('main dart');
      expect(
        (plain.filter, plain.line, plain.column),
        ('maindart', null, null),
      );
      final line = IdeQuickOpenQuery.parse('main.dart:12');
      expect((line.filter, line.line, line.column), ('main.dart', 12, null));
      final column = IdeQuickOpenQuery.parse('main.dart:12:3');
      expect((column.filter, column.line, column.column), ('main.dart', 12, 3));
      final bare = IdeQuickOpenQuery.parse(':7,2');
      expect((bare.filter, bare.line, bare.column), ('', 7, 2));
      expect(IdeQuickOpenQuery.parse('a:b').filter, 'a:b');
    });
  });

  group('commands', () {
    test('keybinding labels follow the platform', () {
      const palette = IdeKeybinding(
        LogicalKeyboardKey.keyP,
        primary: true,
        shift: true,
      );
      expect(palette.label(mac: true), '⇧⌘P');
      expect(palette.label(mac: false), 'Ctrl+Shift+P');
      const line = IdeKeybinding(LogicalKeyboardKey.keyG, control: true);
      expect(line.label(mac: true), '⌃G');
      expect(line.label(mac: false), 'Ctrl+G');
      const tab = IdeKeybinding(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      );
      expect(tab.label(mac: false), 'Ctrl+Shift+Tab');
      final activator = palette.activator(mac: true) as SingleActivator;
      expect(
        (activator.meta, activator.control, activator.shift),
        (true, false, true),
      );
    });

    test('shortcut labels skip other platforms and use the override', () {
      final command = IdeCommand(
        id: 'x',
        label: 'Replace',
        keybindings: const [
          IdeKeybinding(
            LogicalKeyboardKey.keyF,
            primary: true,
            alt: true,
            mac: true,
          ),
          IdeKeybinding(LogicalKeyboardKey.keyH, primary: true),
        ],
        run: () {},
      );
      expect(command.shortcutLabel(mac: true), '⌥⌘F');
      expect(command.shortcutLabel(mac: false), 'Ctrl+H');
      expect(
        IdeCommand(
          id: 'y',
          label: 'Y',
          keybindingLabel: '⌘K ⌘W',
          run: () {},
        ).shortcutLabel(),
        '⌘K ⌘W',
      );
      // As keybindings.json entries: one for macOS only, one for all.
      expect(command.keybindingEntries, const [
        KeybindingEntry(command: 'x', mac: 'alt+cmd+f'),
        KeybindingEntry(command: 'x', key: 'ctrl+h', mac: 'cmd+h'),
      ]);
    });

    test('palette lists recent commands first, then filters fuzzily', () {
      var ran = <String>[];
      IdeCommand command(String id, String label, {String? category}) =>
          IdeCommand(
            id: id,
            label: label,
            category: category,
            run: () => ran.add(id),
          );
      final commands = [
        command('a', 'Toggle Sidebar', category: 'View'),
        command('b', 'Save', category: 'File'),
        command('c', 'Close Editor', category: 'View'),
        IdeCommand(id: 'd', label: 'Disabled', enabled: false, run: () {}),
      ];
      final recent = IdeRecentList()..add('c');
      final all = commandQuickPicks(
        '',
        commands: commands,
        recent: recent,
        onRun: (c) => c.run(),
      );
      expect(all.map((i) => i.label), [
        'View: Close Editor',
        'File: Save',
        'View: Toggle Sidebar',
      ]);
      expect(all.first.group, 'recently used');
      expect(all[1].group, 'other commands');

      final filtered = commandQuickPicks(
        'tgsb',
        commands: commands,
        recent: recent,
        onRun: (c) => c.run(),
      );
      expect(filtered.single.label, 'View: Toggle Sidebar');
      expect(filtered.single.labelMatches, isNotEmpty);
      filtered.single.onAccept!();
      expect(ran, ['a']);
      final none = commandQuickPicks(
        'zzz',
        commands: commands,
        recent: recent,
        onRun: (_) {},
      );
      expect(none.single.onAccept, isNull);
      ran = [];
    });

    test('go to line clamps, counts from the end and needs an editor', () {
      final calls = <(int, int?)>[];
      List<String> labels(String text, int? count) => [
        for (final item in gotoLineQuickPicks(
          text,
          lineCount: count,
          onGo: (line, column) => calls.add((line, column)),
        ))
          item.label,
      ];
      expect(labels('', 10).single, startsWith('Current Line: 1'));
      expect(labels('4', 10), ['Go to line 4.']);
      expect(labels('4:2', 10), ['Go to line 4 and character 2.']);
      expect(labels('99', 10), ['Go to line 10.']);
      expect(labels('-1', 10), ['Go to line 10.']);
      expect(labels('3', null).single, contains('Open a text editor'));
      gotoLineQuickPicks(
        '7,3',
        lineCount: 10,
        onGo: (l, c) => calls.add((l, c)),
      ).single.onAccept!();
      expect(calls, [(7, 3)]);
    });
  });

  test('duplicate tab names get the shortest distinguishing folders', () {
    final descriptions = ideTabDescriptions([
      inRoot('lib/a/main.dart'),
      inRoot('lib/b/main.dart'),
      inRoot('other.dart'),
      inRoot('x/lib/a/main.dart'),
      inRoot('README.md'),
      inRoot('docs/README.md'),
    ], testRoot);
    expect(descriptions, [
      'lib/a',
      'lib/b',
      null,
      '…/lib/a',
      'project',
      'docs',
    ]);
  });

  test('status labels: encoding, line endings, find counter', () {
    expect(ideEncodingLabel('\uFEFFx'), 'UTF-8 with BOM');
    expect(ideEncodingLabel('x'), 'UTF-8');
    expect(ideEolLabel(DocumentSnapshot('a\nb\n')), 'LF');
    expect(ideEolLabel(DocumentSnapshot('a\r\nb\r\n')), 'CRLF');
    expect(ideEolLabel(DocumentSnapshot('a\r\nb\n')), 'Mixed');
    expect(ideEolLabel(DocumentSnapshot('no newline')), 'LF');
    expect(IdeFindWidget.matchesLabel(0, -1), 'No results');
    expect(IdeFindWidget.matchesLabel(17, 2), '3 of 17');
    expect(IdeFindWidget.matchesLabel(17, -1), '? of 17');
    expect(IdeFindWidget.matchesLabel(999, 0), '1 of 999+');
  });

  test('git HEAD parsing', () {
    expect(parseGitHead('ref: refs/heads/feature/ide\n'), 'feature/ide');
    expect(parseGitHead('0123456789abcdef0123456789abcdef01234567'), '0123456');
    expect(parseGitHead('garbage'), isNull);
  });

  test('local listing skips excluded folders and reads the branch', () async {
    final dir = await Directory.systemTemp.createTemp('baocode-ide-index-');
    addTearDown(() => dir.delete(recursive: true));
    final root = dir.path;
    Future<void> write(String relative, String text) async {
      final file = File(p.joinAll([root, ...relative.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    await write('lib/main.dart', 'void main() {}');
    await write('lib/src/deep/x.dart', '');
    await write('README.md', '');
    await write('build/out.dart', '');
    await write('node_modules/m/index.js', '');
    await write('.dart_tool/cache', '');
    await write('.git/HEAD', 'ref: refs/heads/topic\n');
    final listing = await listProjectFiles(IdeFileService(root), root);
    expect(
      [for (final path in listing.paths) p.relative(path, from: root)],
      [
        'README.md',
        p.join('lib', 'main.dart'),
        p.join('lib', 'src', 'deep', 'x.dart'),
      ],
    );
    expect(listing.truncated, isFalse);
    final limited = await listProjectFiles(
      IdeFileService(root),
      root,
      limit: 2,
    );
    expect(limited.paths, hasLength(2));
    expect(limited.truncated, isTrue);
    expect(await readGitBranch(p.join(root, 'lib')), 'topic');
  });

  test('generic listing walks any file service', () async {
    final files = TreeFiles({
      inRoot('a.txt'): '',
      inRoot('src/b.dart'): '',
      inRoot('build/c.dart'): '',
    });
    final listing = await listProjectFiles(files, testRoot);
    expect(listing.paths, [inRoot('a.txt'), inRoot('src/b.dart')]);
    final index = IdeFileIndex(files, testRoot);
    addTearDown(index.dispose);
    expect(index.loaded, isFalse);
    await index.refresh();
    expect(index.relativePaths, ['a.txt', 'src/b.dart']);
  });
}
