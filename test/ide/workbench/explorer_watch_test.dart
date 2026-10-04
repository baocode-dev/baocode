import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:path/path.dart' as p;

import 'fake_files.dart';

/// The explorer follows changes made outside it through its folders'
/// watches: the root's and the expanded folders'.
void main() {
  const settle = Duration(milliseconds: 300);

  test('files made or deleted outside show up; collapsed folders are not '
      'watched, and read again when expanded', () async {
    final files = TreeFiles({
      inRoot('lib/a.dart'): 'a',
      inRoot('README.md'): 'r',
    });
    final watches = <String, StreamController<void>>{};
    final explorer = IdeExplorerController(
      files: files,
      root: testRoot,
      watch: (directory) =>
          (watches[directory] = StreamController<void>()).stream,
    );
    List<String> names() => [
      for (final row in explorer.rows) p.relative(row.path, from: testRoot),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(watches.keys, [testRoot]);
    expect(names(), ['lib', 'README.md']);

    // Made by an agent at the root.
    files.contents[inRoot('NOTES.md')] = 'n';
    watches[testRoot]!.add(null);
    await Future<void>.delayed(settle);
    expect(names(), ['lib', 'NOTES.md', 'README.md']);

    // An expanded folder is watched too.
    final lib = inRoot('lib');
    await explorer.expand(lib);
    expect(watches[lib]!.hasListener, isTrue);
    files.contents[inRoot('lib/b.dart')] = 'b';
    files.contents.remove(inRoot('lib/a.dart'));
    files.contents[inRoot('lib/keep.dart')] = 'k';
    watches[lib]!.add(null);
    await Future<void>.delayed(settle);
    expect(names(), [
      'lib',
      p.join('lib', 'b.dart'),
      p.join('lib', 'keep.dart'),
      'NOTES.md',
      'README.md',
    ]);

    // A burst of events reads once.
    final before = files.listCalls;
    for (var i = 0; i < 5; i++) {
      watches[lib]!.add(null);
    }
    await Future<void>.delayed(settle);
    expect(files.listCalls - before, 1);

    // Collapsed, it is not watched; expanded again, it is read again.
    explorer.collapse(lib);
    expect(watches[lib]!.hasListener, isFalse);
    files.contents.remove(inRoot('lib/b.dart'));
    await explorer.expand(lib);
    await Future<void>.delayed(Duration.zero);
    expect(names(), [
      'lib',
      p.join('lib', 'keep.dart'),
      'NOTES.md',
      'README.md',
    ]);

    explorer.dispose();
    expect(watches[testRoot]!.hasListener, isFalse);
    expect(watches[lib]!.hasListener, isFalse);
  });
}
