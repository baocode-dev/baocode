// The extensions' terminals (MainThreadTerminalService and its shell
// integration actor) over the panel's terminal service, on fake processes:
// `createTerminal` with a shell and its options, a Pseudoterminal both
// ways, `sendText`/`show`/`hide`/`dispose`, the events extensions get, the
// environment variable collections (kept across restarts) and
// `waitOnExit`.

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/main_thread/main_thread_terminal_service.dart';
import 'package:baocode/extensions/terminal/environment_variable_service.dart';
import 'package:baocode/extensions/window/json_state_store.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../ide/terminal/fake_pty.dart';
import '../../ide/terminal/fake_terminal.dart';
import '../support/scripted_rpc.dart';

const _ext = 'ExtHostTerminalService';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedRpc rpc;
  late List<FakePty> started;
  late TerminalService terminals;
  late EnvironmentVariableService environment;
  late MainThreadTerminalService service;
  late RpcActor actor;

  MainThreadTerminalService start() {
    final created = MainThreadTerminalService(
      terminals,
      environment,
      rpc.protocol,
    );
    addTearDown(created.dispose);
    return created;
  }

  setUp(() {
    rpc = ScriptedRpc();
    started = [];
    terminals = TerminalService(
      root: '/project',
      backend: fakeTerminalBackend(started),
    );
    environment = EnvironmentVariableService();
    terminals.environmentMutator = (env) => environment.mergedCollection
        .applyToProcessEnvironment(env, workspaceFolderIndex: 0);
    service = start();
    actor = MainThreadTerminalServiceActor(service);
  });

  tearDown(() {
    terminals.dispose();
    rpc.dispose();
  });

  Future<void> call(String method, List<Object?> args) async {
    await actor.invoke(method, args);
    await pumpEventQueue();
  }

  test('createTerminal: the shell, folder, name and environment asked; '
      'the extension host is told it opened, its size, its process and '
      'that it is active', () async {
    await call(r'$createTerminal', [
      'ext-1',
      {
        'name': 'Build',
        'shellPath': '/bin/bash',
        'shellArgs': ['-c', 'make'],
        'cwd': {'scheme': 'file', 'path': '/project/sub'},
        'env': {'FOO': 'bar', 'HOME': null},
      },
    ]);
    final instance = terminals.active!;
    final launch = started.single.launch!;
    expect(launch.executable, '/bin/bash');
    expect(launch.arguments, ['-c', 'make']);
    expect(launch.workingDirectory, '/project/sub');
    expect(launch.environment, {'PATH': '/usr/bin', 'FOO': 'bar'});
    expect(instance.title, 'Build');

    final opened = rpc.callsTo('$_ext.\$acceptTerminalOpened').single;
    expect(opened[0], instance.id);
    expect(opened[1], 'ext-1');
    expect(opened[2], 'Build');
    expect((opened[3]! as Map)['executable'], '/bin/bash');
    expect(rpc.callsTo('$_ext.\$acceptActiveTerminalChanged').last, [
      instance.id,
    ]);
    expect(rpc.callsTo('$_ext.\$acceptTerminalDimensions').first, [
      instance.id,
      80,
      24,
    ]);
    expect(rpc.callsTo('$_ext.\$acceptTerminalProcessId').single, [
      instance.id,
      4242,
    ]);

    // sendText by the extension host's id: line endings as Enter.
    await call(r'$sendText', ['ext-1', 'echo a\necho b', true]);
    expect(started.single.written, 'echo a\recho b\r');
    expect(rpc.callsTo('$_ext.\$acceptTerminalInteraction'), isNotEmpty);

    // Resized by the view: told.
    instance.resize(120, 40);
    await pumpEventQueue();
    expect(rpc.callsTo('$_ext.\$acceptTerminalDimensions').last, [
      instance.id,
      120,
      40,
    ]);
    expect(rpc.callsTo('$_ext.\$acceptTerminalMaximumDimensions').last, [
      instance.id,
      120,
      40,
    ]);

    // show / hide ask the panel; dispose closes it, said to be the
    // extension's doing.
    final shows = <bool>[];
    final hides = <void>[];
    terminals.onDidRequestShow.listen(shows.add);
    terminals.onDidRequestHide.listen(hides.add);
    await call(r'$show', [instance.id, true]);
    await call(r'$hide', ['ext-1']);
    expect(shows, [true]);
    expect(hides, hasLength(1));
    await call(r'$dispose', ['ext-1']);
    expect(terminals.allInstances, isEmpty);
    expect(started.single.kills, isNotEmpty);
    expect(rpc.callsTo('$_ext.\$acceptTerminalClosed').single, [
      instance.id,
      null,
      TerminalExitReason.extension.index,
    ]);
  });

  test(
    'a terminal hidden from the user is not in the tabs until shown',
    () async {
      final user = terminals.create();
      await call(r'$createTerminal', [
        'ext-hidden',
        {'name': 'Hidden', 'hideFromUser': true},
      ]);
      expect(terminals.allInstances, hasLength(2));
      expect(terminals.instances, [user]);
      expect(terminals.active, user);
      await call(r'$show', ['ext-hidden', false]);
      expect(terminals.instances, hasLength(2));
      expect(terminals.active!.title, 'Hidden');
    },
  );

  test('a Pseudoterminal: started once opened, at its size; what the '
      'extension writes is printed, what is typed goes to it, its exit '
      'closes it', () async {
    final starts = <List<Object?>>[];
    rpc.handlers['$_ext.\$startExtensionTerminal'] = (args) {
      // The extension host knew of it first.
      expect(rpc.callsTo('$_ext.\$acceptTerminalOpened'), hasLength(1));
      starts.add(args);
      return null;
    };
    await call(r'$createTerminal', [
      'ext-pty',
      {'name': 'Pty', 'isExtensionCustomPtyTerminal': true},
    ]);
    final instance = terminals.active!;
    expect(started, isEmpty, reason: 'no process of its own');
    expect(starts.single, [
      instance.id,
      {'columns': 80, 'rows': 24},
    ]);

    await call(r'$sendProcessReady', [instance.id, -1, '', null]);
    expect(rpc.callsTo('$_ext.\$acceptTerminalProcessId').single, [
      instance.id,
      -1,
    ]);
    final printed = <String>[];
    instance.output.listen((data) => printed.add(utf8.decode(data)));
    await call(r'$sendProcessData', [instance.id, 'hello\r\n']);
    expect(printed, ['hello\r\n']);
    expect(
      instance.terminal.buffer.lines.get(0)!.translateToString(true),
      'hello',
    );

    instance.writeText('q');
    await pumpEventQueue();
    expect(rpc.callsTo('$_ext.\$acceptProcessInput').single, [
      instance.id,
      'q',
    ]);

    await call(r'$sendProcessExit', [instance.id, 3]);
    expect(terminals.allInstances, isEmpty);
    expect(rpc.callsTo('$_ext.\$acceptTerminalClosed').single, [
      instance.id,
      3,
      TerminalExitReason.process.index,
    ]);
  });

  test('a Pseudoterminal the user closes is shut down', () async {
    rpc.handlers['$_ext.\$startExtensionTerminal'] = (_) => null;
    await call(r'$createTerminal', [
      'ext-pty',
      {'isExtensionCustomPtyTerminal': true},
    ]);
    final instance = terminals.active!;
    terminals.kill(instance);
    await pumpEventQueue();
    expect(rpc.callsTo('$_ext.\$acceptProcessShutdown').single, [
      instance.id,
      false,
    ]);
    expect(
      rpc.callsTo('$_ext.\$acceptTerminalClosed').single[2],
      TerminalExitReason.user.index,
    );
  });

  test('a Pseudoterminal that fails to start says why', () async {
    rpc.handlers['$_ext.\$startExtensionTerminal'] = (_) => {
      'message': 'Could not find the terminal',
    };
    await call(r'$createTerminal', [
      'ext-pty',
      {'isExtensionCustomPtyTerminal': true},
    ]);
    // An extension's terminal closes whatever the exit.
    expect(terminals.allInstances, isEmpty);
    expect(rpc.callsTo('$_ext.\$acceptTerminalClosed'), hasLength(1));
  });

  test('data events: each terminal\'s output while asked for', () async {
    final instance = terminals.create();
    await pumpEventQueue();
    await call(r'$startSendingDataEvents', []);
    started.single
      ..emitText('a')
      ..emitText('b');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rpc.callsTo('$_ext.\$acceptTerminalProcessData'), [
      [instance.id, 'ab'],
    ]);
    await call(r'$stopSendingDataEvents', []);
    started.single.emitText('c');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rpc.callsTo('$_ext.\$acceptTerminalProcessData'), hasLength(1));
  });

  test('environment variable collections: applied to new terminals but '
      'strict ones, VS Code\'s order, shell integration variables', () async {
    await call(r'$setEnvironmentVariableCollection', [
      'pub.one',
      false,
      [
        [
          'PATH',
          {'variable': 'PATH', 'value': '/one/bin:', 'type': 3},
        ],
        [
          'FOO',
          {'variable': 'FOO', 'value': 'x', 'type': 1},
        ],
      ],
      <List<Object?>>[],
    ]);
    await call(r'$setEnvironmentVariableCollection', [
      'pub.two',
      false,
      [
        [
          'PATH',
          {'variable': 'PATH', 'value': ':/two/bin', 'type': 2},
        ],
        [
          'BAR',
          {
            'variable': 'BAR',
            'value': 'a:b',
            'type': 1,
            'options': {
              'applyAtProcessCreation': false,
              'applyAtShellIntegration': true,
            },
          },
        ],
        // Only the Python environments extension may set these.
        [
          'VSCODE_PYTHON_ZSH_ACTIVATE',
          {
            'variable': 'VSCODE_PYTHON_ZSH_ACTIVATE',
            'value': 'source x',
            'type': 1,
          },
        ],
      ],
      <List<Object?>>[],
    ]);
    terminals.create();
    await pumpEventQueue();
    expect(started.single.launch!.environment, {
      'HOME': '/home/test',
      'PATH': '/one/bin:/usr/bin:/two/bin',
      'FOO': 'x',
      'VSCODE_ENV_REPLACE': r'BAR=a\x3ab',
    });

    await call(r'$createTerminal', [
      'strict',
      {
        'env': {'ONLY': '1'},
        'strictEnv': true,
      },
    ]);
    expect(started.last.launch!.environment, {'ONLY': '1'});

    await call(r'$setEnvironmentVariableCollection', [
      'pub.one',
      false,
      null,
      <List<Object?>>[],
    ]);
    terminals.create();
    await pumpEventQueue();
    expect(started.last.launch!.environment!['PATH'], '/usr/bin:/two/bin');
  });

  test('persistent collections are kept for the next session, sent to it, '
      'and dropped with their extension', () async {
    final dir = Directory.systemTemp.createTempSync('terminal-env');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'terminal.json');
    final kept = EnvironmentVariableService(store: JsonStateStore(path));
    await kept.load();
    environment = kept;
    service.dispose();
    service = start();
    actor = MainThreadTerminalServiceActor(service);
    await call(r'$setEnvironmentVariableCollection', [
      'pub.kept',
      true,
      [
        [
          'KEPT',
          {'variable': 'KEPT', 'value': '1', 'type': 1},
        ],
      ],
      <List<Object?>>[],
    ]);
    await call(r'$setEnvironmentVariableCollection', [
      'pub.gone',
      false,
      [
        [
          'GONE',
          {'variable': 'GONE', 'value': '1', 'type': 1},
        ],
      ],
      <List<Object?>>[],
    ]);
    await kept.store!.flush();

    final next = EnvironmentVariableService(store: JsonStateStore(path));
    await next.load();
    expect(next.collections.keys, ['pub.kept']);
    environment = next;
    final before = rpc.calls.length;
    start();
    await pumpEventQueue();
    expect(
      [
        for (final (method, args) in rpc.calls.skip(before))
          if (method == '$_ext.\$initEnvironmentVariableCollections') args,
      ].single,
      [
        [
          [
            'pub.kept',
            [
              [
                'KEPT',
                {'variable': 'KEPT', 'value': '1', 'type': 1},
              ],
            ],
          ],
        ],
      ],
    );
    next.retain({'pub.other'});
    expect(next.collections, isEmpty);
  });

  test('waitOnExit: the message, then a key closes it', () async {
    final instance = terminals.create(
      config: TerminalLaunchConfig(
        name: 'Task',
        waitOnExit: (code) => 'Press any key to close the terminal.',
      ),
    );
    await pumpEventQueue();
    started.single.exit(1);
    await pumpEventQueue();
    expect(terminals.allInstances, [instance]);
    expect(instance.waitingForKey, isTrue);
    final screen = [
      for (var y = 0; y < 6; y++)
        instance.terminal.buffer.lines.get(y)!.translateToString(true),
    ].join('\n');
    expect(screen, contains('terminated with exit code: 1.'));
    expect(screen, contains('Press any key to close the terminal.'));
    instance.writeText('x');
    await pumpEventQueue();
    expect(terminals.allInstances, isEmpty);
  });

  test('the default profile is the extension host\'s `env.shell`', () async {
    await pumpEventQueue();
    final profile =
        rpc.callsTo('$_ext.\$acceptDefaultProfile').last.first! as Map;
    expect(profile['path'], '/bin/zsh');
    expect(profile['isDefault'], isTrue);
  });
}
