// The files the agent read found by the paths it names them by, those
// paths gone wrong too.

import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = '/Users/me/Desktop';
const _read = '/Users/me/Documents/app/lib/chat/step_folds.dart';

void main() {
  /// The scope of a conversation in [_root] whose agent read [_read].
  FileOpenScope scope(List<FileOpenRequest> opened) => FileOpenScope(
    root: _root,
    onOpen: opened.add,
    existence: FileExistence((path) async => path == _read),
    seen: const [_read],
    child: const SizedBox(),
  );

  test('a path relative to another folder opens the file read', () async {
    final opened = <FileOpenRequest>[];
    final files = scope(opened);
    expect(
      files.openLink(
        FileLink(
          'Documents/app/lib/chat/step_folds.dart',
          FileLineRange(12, 27),
        ),
      ),
      isTrue,
    );
    await pumpEventQueue();
    expect(opened.single.path, _read);
    expect(opened.single.range, FileLineRange(12, 27));
    // Known now: it resolves there at once.
    expect(files.resolve('app/lib/chat/step_folds.dart'), _read);
  });

  test('a file outside the project opens by its absolute path, read or '
      'not, as the agent\'s tools reach it', () {
    final files = scope([]);
    expect(files.resolve(_read), _read);
    expect(files.resolve('../Documents/app/lib/chat/step_folds.dart'), _read);
    expect(
      files.resolve('/Users/me/Documents/other.dart'),
      '/Users/me/Documents/other.dart',
    );
    expect(
      files.resolve('../Documents/other.dart'),
      '/Users/me/Documents/other.dart',
    );
  });

  test('a path going up from a folder the shell went into opens the file '
      'read', () async {
    final opened = <FileOpenRequest>[];
    final files = scope(opened);
    // Relative to /Users/me/Documents/app/web/sdk: from the root it would
    // be /Users/lib/..., which is not there.
    expect(files.openLink(FileLink('../../lib/chat/step_folds.dart')), isTrue);
    await pumpEventQueue();
    expect(opened.single.path, _read);
    // Out of its `..`s, a file alone names none read: too loose a match.
    expect(files.resolve('../../step_folds.dart'), isNot(_read));
  });

  test('only whole names match, and only files read', () async {
    final files = scope([]);
    await pumpEventQueue();
    expect(files.resolve('_folds.dart'), '$_root/_folds.dart');
    expect(files.resolve('lib/other/step_folds.dart'), isNot(_read));
  });

  group('another machine\'s file', () {
    const onHost = '/home/me/app/a.md';
    const here = '/Users/me/Downloads/b.md';
    final onOther = <(String, String, FileLineRange?)>[];
    setUp(onOther.clear);

    /// A conversation of an agent on SSH host `devbox`, in `/home/me/app`.
    FileOpenScope remote(List<FileOpenRequest> opened) => FileOpenScope(
      root: '/home/me/app',
      host: 'devbox',
      local: false,
      onOpen: opened.add,
      existence: FileExistence((path) async => path == onHost),
      existsHere: (path) async => path == here,
      openOnHost: (host, path, range) => onOther.add((host, path, range)),
      child: const SizedBox(),
    );

    void click(FileOpenScope files, String href) =>
        (files.linkRecognizer(href)! as TapGestureRecognizer).onTap!();

    test('`local:` in an SSH project shows the user\'s computer\'s, '
        'read-only', () {
      final opened = <FileOpenRequest>[];
      click(remote(opened), 'local:$here#L4');
      expect(opened.single.path, here);
      expect(opened.single.local, isTrue);
      expect(opened.single.readOnly, isTrue);
      expect(opened.single.range, FileLineRange(4));
    });

    test('`local:` in a local project, `ssh://` to the project\'s host: '
        'as the path alone', () async {
      final opened = <FileOpenRequest>[];
      click(scope(opened), 'local:$_read');
      click(remote(opened), 'ssh://devbox$onHost#L2');
      await pumpEventQueue();
      expect([for (final request in opened) request.path], [_read, onHost]);
      expect(opened.every((request) => !request.local), isTrue);
      expect(opened.last.range, FileLineRange(2));
    });

    test('`ssh://` to another host is read from it', () {
      final opened = <FileOpenRequest>[];
      click(remote(opened), 'ssh://db1/var/log/x.log#L9');
      // From a local project's agent, which went there with ssh.
      final local = FileOpenScope(
        root: _root,
        onOpen: opened.add,
        existence: FileExistence((_) async => false),
        openOnHost: (host, path, range) => onOther.add((host, path, range)),
        child: const SizedBox(),
      );
      click(local, 'ssh://devbox$onHost');
      expect(opened, isEmpty);
      expect(onOther, [
        ('db1', '/var/log/x.log', FileLineRange(9)),
        ('devbox', onHost, null),
      ]);
      // Where those cannot be read, a click does nothing; the menu stays.
      expect(
        (scope(opened).linkRecognizer('ssh://db1/a.md')!
                as TapGestureRecognizer)
            .onTap,
        isNull,
      );
    });

    test('a path alone in an SSH project, not on the host but here, shows '
        'here', () async {
      final opened = <FileOpenRequest>[];
      final files = remote(opened);
      files.openLink(const FileLink(here));
      files.openLink(const FileLink(onHost));
      files.openLink(const FileLink('/nowhere/c.md'));
      await pumpEventQueue();
      expect(
        [for (final request in opened) (request.path, request.local)],
        unorderedEquals([
          (here, true),
          (onHost, false),
          // Nowhere: where the agent works, which says it is not there.
          ('/nowhere/c.md', false),
        ]),
      );
    });
  });
}
