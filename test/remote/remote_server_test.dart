@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/claude.dart' show ClaudeHistoryPage;
import 'package:bao_remote/client.dart';
import 'package:bao_remote/files.dart';
import 'package:bao_remote/git.dart';
import 'package:bao_remote/local.dart'
    show ClaudeEnvironment, CliLocator, ClaudeUnavailable, watchRecursively;
import 'package:bao_remote/lsp.dart';
import 'package:bao_remote/search.dart';
import 'package:bao_remote/server.dart' show ServerClaude;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// The server's methods, through the client, against folders of this
/// machine: what a remote project does, without SSH.
void main() {
  late RemoteHarness remote;
  late Directory project;
  late String root;

  setUp(() async {
    remote = await RemoteHarness.start();
    project = Directory.systemTemp.createTempSync('baocode-remote-project-');
    root = project.resolveSymbolicLinksSync();
  });
  tearDown(() async {
    await remote.close();
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  RemoteClient client() => remote.client;
  String at(String relative) => p.join(root, relative);

  test('the server says what it is', () {
    final hello = client().hello!;
    expect(hello.protocol, RemoteProtocol.version);
    expect(hello.version, 'test');
    expect(hello.pid, pid);
    expect(hello.dataDir, remote.dataDir.path);
    expect(hello.platform.os, Platform.isMacOS ? 'darwin' : 'linux');
  });

  group('files', () {
    test('listed folders first, read, and saved over what was read', () async {
      File(at('b.txt')).writeAsStringSync('one\r\ntwo\r\n');
      Directory(at('src')).createSync();
      final listed = await client().list(root, root);
      expect(
        [for (final f in listed) (f.name, f.isDirectory)],
        [('src', true), ('b.txt', false)],
      );

      expect(await client().read(root, at('b.txt')), 'one\r\ntwo\r\n');
      await client().write(root, at('b.txt'), 'one\ntwo\nthree\n');
      // The file's own line endings are kept.
      expect(File(at('b.txt')).readAsStringSync(), 'one\r\ntwo\r\nthree\r\n');
    });

    test('a file changed on disk since it was read is not saved', () async {
      File(at('a.txt')).writeAsStringSync('mine');
      await client().read(root, at('a.txt'));
      File(at('a.txt')).writeAsStringSync('theirs');
      await expectLater(
        client().write(root, at('a.txt'), 'mine, edited'),
        throwsA(isA<IdeFileConflictException>()),
      );
      expect(File(at('a.txt')).readAsStringSync(), 'theirs');
    });

    test('missing, binary and taken files fail by type', () async {
      await expectLater(
        client().read(root, at('nope.txt')),
        throwsA(isA<IdeFileNotFoundException>()),
      );
      File(at('bin.dat')).writeAsBytesSync([0, 1, 2, 3]);
      await expectLater(
        client().read(root, at('bin.dat')),
        throwsA(isA<IdeBinaryFileException>()),
      );
      expect(await client().read(root, at('bin.dat'), force: true), isNotEmpty);
      await client().create(root, at('new.txt'));
      await expectLater(
        client().create(root, at('new.txt')),
        throwsA(isA<IdeFileExistsException>()),
      );
    });

    test('what the user may not read or write fails as such', () async {
      Directory(at('locked')).createSync();
      File(at('secret.txt')).writeAsStringSync('no');
      Process.runSync('chmod', ['000', at('locked'), at('secret.txt')]);
      addTearDown(
        () => Process.runSync('chmod', ['755', at('locked'), at('secret.txt')]),
      );
      // Root reads anything: nothing to test.
      try {
        Directory(at('locked')).listSync();
        return;
      } on FileSystemException {
        // Refused, as it is to the user.
      }
      await expectLater(
        client().list(root, at('locked')),
        throwsA(
          isA<IdeFileAccessDeniedException>().having(
            (e) => e.path,
            'path',
            endsWith('locked'),
          ),
        ),
      );
      await expectLater(
        client().read(root, at('secret.txt')),
        throwsA(isA<IdeFileAccessDeniedException>()),
      );
    });

    test('bytes written to a new file, never over one', () async {
      final bytes = List.generate(300000, (i) => i % 256);
      await client().writeBytes(root, at('shot.png'), bytes);
      expect(File(at('shot.png')).readAsBytesSync(), bytes);
      File(at('taken.png')).writeAsBytesSync([7]);
      await expectLater(
        client().writeBytes(root, at('taken.png'), [1]),
        throwsA(isA<IdeFileExistsException>()),
      );
      expect(File(at('taken.png')).readAsBytesSync(), [7]);
      await expectLater(
        client().writeBytes(root, at('no/such/folder/a.png'), [1]),
        throwsA(isA<RemoteException>()),
      );
    });

    test('made, renamed, copied and deleted', () async {
      await client().create(root, at('dir'), directory: true);
      await client().create(root, at('dir/a.txt'));
      await client().rename(root, at('dir/a.txt'), at('dir/b.txt'));
      await client().copy(root, at('dir'), at('copy'));
      expect(File(at('copy/b.txt')).existsSync(), isTrue);
      await client().delete(root, at('dir'));
      expect(Directory(at('dir')).existsSync(), isFalse);
      await expectLater(
        client().delete(root, root),
        throwsA(isA<RemoteException>()),
      );
    });

    test('a file read a stretch at a time, and what files take', () async {
      File(at('big.bin')).writeAsBytesSync(List.generate(10, (i) => i));
      Directory(at('sub')).createSync();
      File(at('sub/a.txt')).writeAsStringSync('abc');

      final first = await client().readRange(at('big.bin'), 0, 4);
      expect(first.bytes, [0, 1, 2, 3]);
      expect(first.size, 10);
      final last = await client().readRange(at('big.bin'), 8, 4);
      expect(last.bytes, [8, 9]);
      final past = await client().readRange(at('big.bin'), 12, 4);
      expect(past.bytes, isEmpty);
      await expectLater(
        client().readRange(at('none'), 0, 4),
        throwsA(isA<IdeFileNotFoundException>()),
      );

      expect(await client().sizeOf([at('big.bin'), at('sub')]), 13);
      // Counting stops once over the limit.
      expect(await client().sizeOf([at('big.bin'), at('sub')], limit: 5), 10);
    });

    test('bytes, walks, stats, entries and real paths', () async {
      File(at('img.png')).writeAsBytesSync([137, 80, 78, 71]);
      Directory(at('node_modules/x')).createSync(recursive: true);
      File(at('node_modules/x/i.js')).writeAsStringSync('');
      File(at('lib/m.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      expect(await client().readBytes(at('img.png')), [137, 80, 78, 71]);
      final listing = await client().walk(root);
      expect(listing.paths, [at('img.png'), at('lib/m.dart')]);
      expect(listing.truncated, isFalse);
      expect(await client().stat(at('lib')), 'directory');
      expect(await client().stat(at('img.png')), 'file');
      expect(await client().stat(at('none')), isNull);
      expect(await client().entries(root), containsAll(['lib', 'img.png']));
      expect(await client().realPath(p.join(root, 'lib', '..')), root);
      await expectLater(
        client().realPath(at('none')),
        throwsA(isA<IdeFileNotFoundException>()),
      );
    });

    test('a folder is watched until the subscription ends', () async {
      final changes = <void>[];
      final subscription = client().watchDirectory(root).listen(changes.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      File(at('watched.txt')).writeAsStringSync('x');
      await until(() => changes.isNotEmpty);
      await subscription.cancel();
    });

    test('a tree is watched, its new folders too, the excluded not', () async {
      final events = <WatchEvent>[];
      final subscription = client()
          .watchTree(root, excluded: {'node_modules'})
          .listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      Directory(at('deep/er')).createSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      File(at('deep/er/x.txt')).writeAsStringSync('x');
      await until(() => events.any((e) => e.path == at('deep/er/x.txt')));
      await subscription.cancel();
    });
  });

  group('per-folder watching (as on Linux)', () {
    test('follows new folders, forgets deleted ones, skips some', () async {
      Directory(at('skip')).createSync();
      final events = <WatchEvent>[];
      final subscription = watchRecursively(
        root,
        skip: (dir) => p.basename(dir) == 'skip',
        perDirectory: true,
      ).listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      Directory(at('a/b')).createSync(recursive: true);
      await until(() => events.any((e) => e.path == at('a')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      File(at('a/b/c.txt')).writeAsStringSync('c');
      await until(() => events.any((e) => e.path == at('a/b/c.txt')));
      File(at('skip/hidden.txt')).writeAsStringSync('h');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(events.where((e) => e.path.contains('hidden')), isEmpty);
      await subscription.cancel();
    });
  });

  group('search', () {
    test('matches by file, then the end', () async {
      File(at('a.txt')).writeAsStringSync('hello\nworld hello\n');
      File(at('b.txt')).writeAsStringSync('nothing\n');
      final items = await client()
          .searchText(root, const IdeTextQuery('hello'))
          .toList();
      final matches = items.whereType<IdeFileMatches>().single;
      expect(matches.path, at('a.txt'));
      expect(
        [for (final m in matches.matches) (m.line, m.start)],
        [(0, 0), (1, 6)],
      );
      expect(items.last, isA<IdeTextSearchComplete>());
    });

    test('across lines: where the match ends comes too', () async {
      File(at('a.txt')).writeAsStringSync('one\r\n  two\n');
      final items = await client()
          .searchText(root, const IdeTextQuery('one\n  two'))
          .toList();
      final match = items.whereType<IdeFileMatches>().single.matches.single;
      expect((match.line, match.start), (0, 0));
      expect((match.endLine, match.endColumn), (1, 5));
    });

    test('an invalid pattern fails the stream', () async {
      await expectLater(
        client().searchText(root, const IdeTextQuery('(', isRegExp: true)),
        emitsError(anything),
      );
    });
  });

  group('git', () {
    setUp(() async {
      await Process.run('git', ['init', '-q'], workingDirectory: root);
    });

    test('runs there, its output and exit code as they were', () async {
      File(at('x.txt')).writeAsStringSync('x');
      final status = await client().git(['status', '--porcelain'], cwd: root);
      expect(status.exitCode, 0);
      expect(status.stdout, contains('?? x.txt'));
      final bad = await client().git(['nope-command'], cwd: root);
      expect(bad.exitCode, isNot(0));
      expect(bad.stderr, isNotEmpty);
    });

    test('a limit stops the output there, and says it was cut', () async {
      for (final name in ['a', 'b', 'c']) {
        File(at('$name.txt')).writeAsStringSync(name);
      }
      const status = ['status', '-z', '--porcelain'];
      final cut = await client().git(status, cwd: root, limit: 2);
      expect(cut.truncated, isTrue);
      expect(cut.stdout, '?? a.txt\x00?? b.txt\x00');
      final whole = await client().git(status, cwd: root, limit: 3);
      expect(whole.truncated, isFalse);
      expect('\x00'.allMatches(whole.stdout), hasLength(3));
    });

    test('changes to the repository are heard', () async {
      final heard = <String>[];
      final subscription = client().watchRepository(root).listen(heard.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      File(at('y.txt')).writeAsStringSync('y');
      await until(() => heard.isNotEmpty);
      await subscription.cancel();
      // Where: the app skips what is ignored.
      expect(heard, contains(endsWith('y.txt')));
    });

    test('git that cannot run fails as a Git error', () async {
      await expectLater(
        client().git(['status'], cwd: at('missing')),
        throwsA(isA<IdeGitException>()),
      );
    });
  });

  group('processes', () {
    test('output, input and the exit code', () async {
      final process = await client().start('/bin/sh', [
        '-c',
        'read line; echo "got \$line"; echo oops >&2; exit 7',
      ], cwd: root);
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      process.write(utf8.encode('hi\n'));
      expect(await process.exitCode, 7);
      expect(await out, 'got hi\n');
      expect(await err, 'oops\n');
    });

    test('run to the end with its input', () async {
      final result = await client().run('/bin/cat', [], stdin: 'piped');
      expect(result.exitCode, 0);
      expect(result.stdout, 'piped');
    });

    test('killed, and ended with the server', () async {
      final process = await client().start('/bin/sleep', ['30']);
      process.kill();
      expect(await process.exitCode, isNot(0));
      final other = await client().start('/bin/sleep', ['30']);
      await remote.server.shutdown();
      expect(
        await other.exitCode.timeout(const Duration(seconds: 5)),
        anyOf(RemoteProcess.lostExitCode, isNot(0)),
      );
    });
  });

  group('Claude Code', () {
    test('as root, started without allowing to skip the permissions', () {
      const args = [
        '-p',
        '--allow-dangerously-skip-permissions',
        '--permission-mode',
        'default',
      ];
      expect(
        ServerClaude.argumentsFor(args, root: true, environment: const {}),
        ['-p', '--permission-mode', 'default'],
      );
      // Not root, or a sandbox: as asked.
      expect(
        ServerClaude.argumentsFor(args, root: false, environment: const {}),
        args,
      );
      expect(
        ServerClaude.argumentsFor(
          args,
          root: true,
          environment: const {'IS_SANDBOX': '1'},
        ),
        args,
      );
      // Full access is refused there, saying why.
      expect(
        () => ServerClaude.argumentsFor(
          ['-p', '--permission-mode', 'bypassPermissions'],
          root: true,
          environment: const {},
        ),
        throwsA(
          isA<ClaudeUnavailable>().having(
            (error) => error.message,
            'message',
            'Claude Code does not run with full access as root',
          ),
        ),
      );
    });

    late Directory home;
    late File fake;

    setUp(() {
      home = Directory.systemTemp.createTempSync('baocode-remote-claude-');
      fake = File(p.join(home.path, 'fake-claude'))
        ..writeAsStringSync(r'''#!/bin/sh
settings=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--settings" ]; then settings="$arg"; fi
  prev="$arg"
done
content=""
if [ -n "$settings" ] && [ -f "$settings" ]; then content=$(cat "$settings"); fi
read line
printf '{"type":"system","args":"%s","cleared":"%s","extra":"%s","settings":%s,"pwd":"%s"}\n' \
  "$*" "${ANTHROPIC_MODEL-unset}" "$EXTRA" "${content:-null}" "$(pwd)"
printf '%s\n' "$line"
''');
      Process.runSync('chmod', ['+x', fake.path]);
      CliLocator.use({
        'PATH': '/usr/bin:/bin',
        'HOME': home.path,
        'ANTHROPIC_MODEL': 'from-the-shell',
        'BAOCODE_CLAUDE_PATH': fake.path,
        'BAOCODE_CLAUDE_DATA_PATH': p.join(home.path, '.claude'),
      });
    });
    tearDown(() {
      CliLocator.use(null);
      home.deleteSync(recursive: true);
    });

    test('starts with the arguments, environment and settings asked', () async {
      final process = await client().startClaude(
        cwd: root,
        arguments: ['-p', '--verbose'],
        settings: {
          'env': {'ANTHROPIC_API_KEY': 'secret'},
        },
        cleared: ['ANTHROPIC_MODEL'],
        environment: {'EXTRA': 'yes'},
      );
      process.write(utf8.encode('{"type":"user"}\n'));
      final lines = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      expect(await process.exitCode, 0);
      final first = jsonDecode(lines.first) as Map;
      final args = first['args'] as String;
      expect(args, startsWith('-p --verbose --settings '));
      expect(first['cleared'], '');
      expect(first['extra'], 'yes');
      expect(first['settings'], {
        'env': {'ANTHROPIC_API_KEY': 'secret'},
      });
      expect(first['pwd'], root);
      expect(lines[1], '{"type":"user"}');
      // The file with the key is gone with the process.
      final settingsPath = args.split(' ').last;
      await until(() => !File(settingsPath).existsSync());
    });

    test('not installed there: ClaudeUnavailable', () async {
      CliLocator.use({
        'PATH': '/nowhere',
        'HOME': home.path,
        'BAOCODE_CLAUDE_PATH': p.join(home.path, 'not-there'),
      });
      await expectLater(
        client().locateClaude(),
        throwsA(isA<ClaudeUnavailable>()),
      );
      await expectLater(
        client().startClaude(cwd: root, arguments: const []),
        throwsA(isA<ClaudeUnavailable>()),
      );
    });

    test('the sessions kept there are listed, read and deleted', () async {
      final sessions = Directory(p.join(home.path, '.claude', 'projects', '-x'))
        ..createSync(recursive: true);
      File(p.join(sessions.path, 'abc.jsonl')).writeAsStringSync(
        [
          jsonEncode({
            'type': 'user',
            'uuid': 'u1',
            'cwd': root,
            'timestamp': '2026-10-01T10:00:00Z',
            'message': {'role': 'user', 'content': 'Fix the bug'},
          }),
          jsonEncode({
            'type': 'assistant',
            'uuid': 'a1',
            'parentUuid': 'u1',
            'timestamp': '2026-10-01T10:00:05Z',
            'message': {'role': 'assistant', 'content': 'Done'},
          }),
          jsonEncode({
            'type': 'attachment',
            'uuid': 'g1',
            'parentUuid': 'a1',
            'attachment': {
              'type': 'goal_status',
              'condition': 'tests pass',
              'met': false,
              'sentinel': true,
            },
          }),
          // Says the words, but is not a goal record.
          jsonEncode({
            'type': 'user',
            'uuid': 'u2',
            'parentUuid': 'g1',
            'message': {'role': 'user', 'content': '"goal_status"'},
          }),
        ].join('\n'),
      );
      expect(ClaudeEnvironment.of(), completes);
      final projects = await client().claudeProjects();
      expect(projects.single.path, root);
      final session = projects.single.sessions.single;
      expect(session.id, 'abc');
      expect(session.title, 'Fix the bug');
      final history = await client().claudeHistory(session.path);
      expect(
        [for (final e in history) e['type']],
        ['user', 'assistant', 'attachment', 'user'],
      );
      final goal = await client().claudeGoal('abc');
      expect([for (final e in goal) e['uuid']], ['g1']);
      expect(await client().claudeGoal('none'), isEmpty);
      await client().claudeDelete('abc');
      expect(await client().claudeProjects(), isEmpty);
    });

    test(
      'a long session is read from its end, a page of turns at a time',
      () async {
        final sessions = Directory(
          p.join(home.path, '.claude', 'projects', '-x'),
        )..createSync(recursive: true);
        final lines = <Map<String, Object?>>[];
        String? last;
        void add(String uuid, Map<String, Object?> entry) {
          lines.add({'uuid': uuid, 'parentUuid': ?last, ...entry});
          last = uuid;
        }

        void goal(String uuid) => add(uuid, {
          'type': 'attachment',
          'attachment': {
            'type': 'goal_status',
            'condition': 'tests pass',
            'met': false,
            'sentinel': true,
          },
        });

        for (var turn = 1; turn <= 5; turn++) {
          add('u$turn', {
            'type': 'user',
            'cwd': root,
            'timestamp': '2026-10-01T10:0$turn:00Z',
            'message': {'role': 'user', 'content': 'Turn $turn'},
          });
          // A call and its result belong to the turn, not begin another.
          add('c$turn', {
            'type': 'assistant',
            'message': {
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 't$turn',
                  'name': 'Bash',
                  'input': {},
                },
              ],
            },
          });
          add('r$turn', {
            'type': 'user',
            'message': {
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 't$turn',
                  'content': 'ok',
                },
              ],
            },
          });
          add('a$turn', {
            'type': 'assistant',
            'message': {'role': 'assistant', 'content': 'Done $turn'},
          });
          if (turn == 1) goal('g1');
          if (turn == 3) goal('g2');
        }
        File(p.join(sessions.path, 'long.jsonl'))
            .writeAsStringSync(lines.map(jsonEncode).join('\n'));
        final projects = await client().claudeProjects();
        final path = projects.single.sessions.single.path;
        List<Object?> ids(ClaudeHistoryPage page) => [
          for (final entry in page.entries) entry['uuid'],
        ];

        // The last turns, cut at the user's prompts; the goal as it stood all
        // along comes with the first page.
        final last2 = await client().claudeHistoryPage(path, turns: 2);
        expect(ids(last2), [
          'g1', 'g2', //
          for (final turn in [4, 5]) ...[
            'u$turn',
            'c$turn',
            'r$turn',
            'a$turn',
          ],
        ]);
        expect(last2.earlier, 'u4');

        // Those before: goal records are not sent again.
        final before = await client().claudeHistoryPage(
          path,
          turns: 2,
          before: last2.earlier,
        );
        expect(ids(before), [
          for (final turn in [2, 3]) ...[
            'u$turn',
            'c$turn',
            'r$turn',
            'a$turn',
          ],
        ]);
        expect(before.earlier, 'u2');

        // The start of it: nothing more before.
        final start = await client().claudeHistoryPage(
          path,
          turns: 2,
          before: before.earlier,
        );
        expect(ids(start), ['u1', 'c1', 'r1', 'a1']);
        expect(start.earlier, isNull);

        // Shorter than a page: all of it.
        final whole = await client().claudeHistoryPage(path, turns: 10);
        expect(whole.entries, await client().claudeHistory(path));
        expect(whole.earlier, isNull);

        // A line that is gone (rewound meanwhile): nothing before it.
        final gone = await client().claudeHistoryPage(
          path,
          turns: 2,
          before: 'nope',
        );
        expect(gone.entries, isEmpty);
        expect(gone.earlier, isNull);
      },
    );

    test('a page leaves out what is not shown: a file read whole, the '
        "CLI's copy of a picture, a file before an edit", () async {
      final sessions = Directory(p.join(home.path, '.claude', 'projects', '-x'))
        ..createSync(recursive: true);
      final lines = [
        {
          'uuid': 'u1',
          'type': 'user',
          'cwd': root,
          'message': {'role': 'user', 'content': 'Go'},
        },
        {
          'uuid': 'r1',
          'parentUuid': 'u1',
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 't1',
                'content': 'a' * 10000,
              },
            ],
          },
          'toolUseResult': {
            'type': 'text',
            'file': {'filePath': '/x/a.txt', 'content': 'a' * 10000},
          },
        },
        {
          'uuid': 'r2',
          'parentUuid': 'r1',
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 't2',
                'content': [
                  {'type': 'text', 'text': 'shot'},
                  {
                    'type': 'image',
                    'source': {'type': 'base64', 'data': 'b' * 10000},
                  },
                ],
              },
            ],
          },
          'toolUseResult': [
            {'type': 'text', 'text': 'shot'},
            {
              'type': 'image',
              'source': {'type': 'base64', 'data': 'b' * 10000},
            },
          ],
        },
        {
          'uuid': 'r3',
          'parentUuid': 'r2',
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': 't3', 'content': 'ok'},
            ],
          },
          'toolUseResult': {
            'filePath': '/x/a.txt',
            'originalFile': 'c' * 10000,
            'structuredPatch': <Object?>[],
          },
        },
      ];
      File(p.join(sessions.path, 'slim.jsonl'))
          .writeAsStringSync(lines.map(jsonEncode).join('\n'));
      final projects = await client().claudeProjects();
      final path = projects.single.sessions.single.path;
      final page = await client().claudeHistoryPage(path, turns: 10);
      final [_, read, shot, edit] = page.entries;
      Object? content(Map<String, Object?> entry) =>
          ((entry['message']! as Map)['content'] as List).single['content'];

      expect(content(read), '${'a' * 4000}…');
      expect(read['toolUseResult'], {
        'type': 'text',
        'file': {'filePath': '/x/a.txt'},
      });
      // The picture is shown, from the call's result.
      expect(content(shot), [
        {'type': 'text', 'text': 'shot'},
        {
          'type': 'image',
          'source': {'type': 'base64', 'data': 'b' * 10000},
        },
      ]);
      expect(shot['toolUseResult'], [
        {'type': 'text', 'text': 'shot'},
      ]);
      expect(edit['toolUseResult'], {
        'filePath': '/x/a.txt',
        'structuredPatch': <Object?>[],
      });
    });

    test('a turn the agent worked long at is cut within it, its calls '
        'with their results', () async {
      final sessions = Directory(p.join(home.path, '.claude', 'projects', '-x'))
        ..createSync(recursive: true);
      final lines = <Map<String, Object?>>[];
      String? last;
      void add(String uuid, Map<String, Object?> entry) {
        lines.add({'uuid': uuid, 'parentUuid': ?last, ...entry});
        last = uuid;
      }

      Map<String, Object?> said(String message, Map<String, Object?> block) => {
        'type': 'assistant',
        'message': {
          'id': message,
          'role': 'assistant',
          'content': [block],
        },
      };
      Map<String, Object?> result(String call) => {
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': call, 'content': 'x' * 400},
          ],
        },
      };

      add('u1', {
        'type': 'user',
        'cwd': root,
        'message': {'role': 'user', 'content': 'Go'},
      });
      for (var step = 1; step <= 4; step++) {
        // Two calls at once, a line each, the first answered before the
        // second is kept.
        add(
          'a${step}a',
          said('m$step', {'type': 'tool_use', 'id': 't${step}a'}),
        );
        add('r${step}a', result('t${step}a'));
        add(
          'a${step}b',
          said('m$step', {'type': 'tool_use', 'id': 't${step}b'}),
        );
        add('r${step}b', result('t${step}b'));
      }
      File(p.join(sessions.path, 'long.jsonl'))
          .writeAsStringSync(lines.map(jsonEncode).join('\n'));
      final projects = await client().claudeProjects();
      final path = projects.single.sessions.single.path;
      List<Object?> ids(ClaudeHistoryPage page) => [
        for (final entry in page.entries) entry['uuid'],
      ];

      // Past the size, at the first line of a message: not between a
      // message's lines.
      final last2 = await client().claudeHistoryPage(
        path,
        turns: 10,
        bytes: 2000,
      );
      expect(ids(last2), [
        'a3a',
        'r3a',
        'a3b',
        'r3b',
        'a4a',
        'r4a',
        'a4b',
        'r4b',
      ]);
      expect(last2.earlier, 'a3a');

      final rest = await client().claudeHistoryPage(
        path,
        turns: 10,
        before: last2.earlier,
        bytes: 1 << 20,
      );
      expect(ids(rest), [
        'u1',
        'a1a',
        'r1a',
        'a1b',
        'r1b',
        'a2a',
        'r2a',
        'a2b',
        'r2b',
      ]);
      expect(rest.earlier, isNull);
    });
  });

  group('review', () {
    test('snapshots, diffs and restores a project there', () async {
      File(at('a.txt')).writeAsStringSync('one\n');
      final store = (await client().openReview(root))!;
      expect(store.root, root);
      final before = (await store.snapshot())!;
      File(at('a.txt')).writeAsStringSync('one\ntwo\n');
      File(at('b.txt')).writeAsStringSync('new\n');
      final after = (await store.snapshot())!;
      final changes = await store.diff(before, after);
      expect([for (final c in changes) c.path], ['a.txt', 'b.txt']);
      final counts = await store.lineCounts(before, after);
      expect(counts['a.txt'], (added: 1, removed: 0));
      final old = changes.first.before!;
      expect(utf8.decode(await store.read(old)), 'one\n');
      final taken = (await store.take('b.txt'))!;
      expect(utf8.decode(await store.read(taken)), 'new\n');
      await store.restore('a.txt', old);
      expect(File(at('a.txt')).readAsStringSync(), 'one\n');
      await store.restore('b.txt', null);
      expect(File(at('b.txt')).existsSync(), isFalse);
      expect(await store.exists('a.txt'), isTrue);
      expect(await store.contains(after, 'b.txt'), isTrue);
      await store.save('s1', 'data', blobs: [old]);
      expect(await store.load('s1'), 'data');
      await store.forget('s1');
      expect(await store.load('s1'), isNull);
      // Its repository is the server's, not the project's.
      expect(Directory(at('.git')).existsSync(), isFalse);
      expect(
        Directory(p.join(remote.dataDir.path, 'checkpoints')).existsSync(),
        isTrue,
      );
    });

    test('no store for a folder that is not there', () async {
      expect(await client().openReview(at('missing')), isNull);
    });
  });

  group('terminals', () {
    test('a shell there, its output, input, size and exit', () async {
      final pty = await client().startPty(
        cwd: root,
        columns: 90,
        rows: 20,
        shellIntegration: false,
        shell: ['/bin/sh'],
      );
      final output = StringBuffer();
      pty.output.listen((data) => output.write(utf8.decode(data)));
      pty.write(utf8.encode('stty size; pwd; exit 4\n'));
      expect(await pty.exitCode.timeout(const Duration(seconds: 10)), 4);
      expect(output.toString(), contains('20 90'));
      expect(output.toString(), contains(root));
    });

    test('with shell integration, the shell is given its nonce', () async {
      final pty = await client().startPty(cwd: root, shell: ['/bin/bash']);
      expect(pty.nonce, isNotEmpty);
      expect(pty.arguments, isNotEmpty);
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 10));
    });
  });

  group('port forwarding', () {
    test('a port there reaches one here, both ways', () async {
      final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      echo.listen((socket) => socket.listen(socket.add, onDone: socket.close));
      final forward = await client().forward(echo.port);
      expect(forward.remotePort, isNot(echo.port));
      final socket = await Socket.connect('127.0.0.1', forward.remotePort);
      socket.add(utf8.encode('ping'));
      final reply = await socket.first.timeout(const Duration(seconds: 5));
      expect(utf8.decode(reply), 'ping');
      socket.destroy();
      await forward.close();
      await echo.close();
    });

    test('a connection from here to a port there, both ways, closed by '
        'either side', () async {
      final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <Socket>[];
      final ends = <Completer<void>>[];
      echo.listen((socket) {
        accepted.add(socket);
        final end = Completer<void>();
        ends.add(end);
        socket.listen(
          socket.add,
          onDone: () {
            socket.destroy();
            end.complete();
          },
          onError: (Object _) {},
        );
      });
      final tunnel = await client().connectTcp(echo.port);
      final replies = StreamIterator(tunnel.data);
      tunnel.add(utf8.encode('ping'));
      expect(
        await replies.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(utf8.decode(replies.current), 'ping');
      // Closed there: the tunnel ends.
      accepted.single.destroy();
      await tunnel.done.timeout(const Duration(seconds: 5));

      // Closed here: the socket there ends.
      final second = await client().connectTcp(echo.port);
      await until(() => accepted.length == 2);
      await second.close();
      await ends.last.future.timeout(const Duration(seconds: 5));

      // Nothing listening there.
      await echo.close();
      await expectLater(client().connectTcp(echo.port), throwsA(anything));
    });
  });

  group('language servers', () {
    test('found on the PATH there', () async {
      ClaudeEnvironment.use({'PATH': '/usr/bin:/bin'});
      addTearDown(() => ClaudeEnvironment.use(null));
      final found = await client().locateLanguageServer('sh');
      expect(found, isA<LspServerFound>());
      final missing = await client().locateLanguageServer('no-such-ls');
      expect(missing, isA<LspServerMissing>());
    });
  });
}
