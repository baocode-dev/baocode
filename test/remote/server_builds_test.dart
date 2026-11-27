import 'dart:io';

import 'package:bao_remote/server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory root;

  Directory build(String name, int day, {String binary = 'baocode-server'}) {
    final dir = Directory(p.join(root.path, name))..createSync();
    File(p.join(dir.path, binary))
      ..createSync()
      ..setLastModifiedSync(DateTime.utc(2025, 1, day));
    return dir;
  }

  Iterable<String> remaining() =>
      root.listSync(followLinks: false).map((entry) => p.basename(entry.path));

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode-server-builds-');
    root = Directory(p.join(temp.path, '.baocode-server'))..createSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('keeps the running build and the two newest other binaries', () {
    final current = build('current', 5);
    build('a', 4);
    build('c', 2);
    build('b', 3);
    build('d', 1);

    pruneServerBuildsForExecutable(p.join(current.path, 'baocode-server'));

    expect(remaining(), unorderedEquals(['current', 'a', 'b']));
  });

  test('an older running build still counts toward the limit', () {
    final current = build('current', 1);
    build('newest', 4);
    build('previous', 3);
    build('outdated', 2);

    pruneServerBuilds(root: root, currentDir: current);

    expect(remaining(), unorderedEquals(['current', 'newest', 'previous']));
  });

  test('keeps all builds at the limit', () {
    final current = build('current', 3);
    build('one', 1);
    build('two', 2);

    pruneServerBuilds(root: root, currentDir: current);

    expect(remaining(), unorderedEquals(['current', 'one', 'two']));
  });

  test('leaves reserved directories, incomplete installs and files alone', () {
    final current = build('current', 3);
    build('data', 1);
    build('run', 1);
    build('old', 1);
    Directory(p.join(root.path, 'partial', 'baocode-server'))
        .createSync(recursive: true);
    File(p.join(root.path, 'notes')).createSync();

    pruneServerBuilds(root: root, currentDir: current, keep: 1);

    expect(
      remaining(),
      unorderedEquals(['current', 'data', 'run', 'partial', 'notes']),
    );
  });

  test(
    'does not follow links to build directories or binaries',
    () {
      final current = build('current', 2);
      final alias = Link(p.join(root.path, 'alias'))..createSync(current.path);
      final dir = Directory(p.join(root.path, 'linked-binary'))..createSync();
      final binary = Link(p.join(dir.path, 'baocode-server'))
        ..createSync(p.join(current.path, 'baocode-server'));

      pruneServerBuilds(root: root, currentDir: current, keep: 1);

      expect(alias.existsSync(), isTrue);
      expect(binary.existsSync(), isTrue);
    },
    skip: Platform.isWindows,
  ); // Creating file symlinks can require privileges.

  test('recognizes the Windows server binary', () {
    final current = build('current', 2, binary: 'baocode-server.exe');
    build('old', 1, binary: 'baocode-server.exe');

    pruneServerBuilds(root: root, currentDir: current, keep: 1);

    expect(remaining(), ['current']);
  });

  test('outside the install root no sibling builds are removed', () {
    root = Directory(p.join(temp.path, 'other'))..createSync();
    final current = build('current', 4);
    build('one', 1);
    build('two', 2);
    build('three', 3);

    pruneServerBuildsForExecutable(p.join(current.path, 'baocode-server'));

    expect(remaining(), unorderedEquals(['current', 'one', 'two', 'three']));
  });

  test('one locked build does not stop later deletions', () {
    final current = build('current', 3);
    final locked = build('locked', 2);
    build('old', 1);

    pruneServerBuilds(
      root: root,
      currentDir: current,
      keep: 1,
      delete: (dir) {
        if (p.equals(dir.path, locked.path)) {
          throw FileSystemException('Locked', dir.path);
        }
        dir.deleteSync(recursive: true);
      },
    );

    expect(remaining(), unorderedEquals(['current', 'locked']));
  });

  test('breaks timestamp ties by descending directory name', () {
    final current = build('current', 2);
    build('a', 1);
    build('b', 1);

    pruneServerBuilds(root: root, currentDir: current, keep: 2);

    expect(remaining(), unorderedEquals(['current', 'b']));
  });

  test('a nonpositive limit still keeps the running build', () {
    final current = build('current', 2);
    for (final keep in [0, -1]) {
      build('old', 1);
      pruneServerBuilds(root: root, currentDir: current, keep: keep);
      expect(remaining(), ['current']);
    }
  });

  test('a missing install root does not prevent startup', () {
    final current = build('current', 1);
    root.deleteSync(recursive: true);

    expect(
      () => pruneServerBuilds(root: root, currentDir: current),
      returnsNormally,
    );
  });
}
