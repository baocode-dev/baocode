import 'dart:async';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/host/implicit_activation_events.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/host/restart_policy.dart';
import 'package:baocode/extensions/host/server_uris.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two ends of an in-memory message channel.
final class _Pipe implements MessagePassingProtocol {
  late _Pipe other;
  void Function(Uint8List)? _listener;

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      _listener = listener;

  @override
  void send(Uint8List message) =>
      scheduleMicrotask(() => other._listener?.call(message));

  static (_Pipe, _Pipe) pair() {
    final a = _Pipe();
    final b = _Pipe();
    a.other = b;
    b.other = a;
    return (a, b);
  }
}

final class _ExtensionService implements RpcActor {
  final events = <String>[];

  @override
  FutureOr<Object?> invoke(String method, List<Object?> args) {
    if (method == r'$activateByEvent') events.add(args[0] as String);
    return null;
  }
}

final class _Session implements ExtHostSession {
  _Session(this.rpc, this.remote);

  @override
  final RpcProtocol rpc;
  final RpcProtocol remote;
  final _closed = Completer<void>();
  bool terminated = false;

  @override
  Future<void> get closed => _closed.future;

  void crash() {
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> terminate() async {
    terminated = true;
    crash();
  }
}

const _service = 7;

void main() {
  group('implicit activation events', () {
    test('adds the contributions\' events to those listed', () {
      final events = readActivationEvents({
        'identifier': {'value': 'Pub.Ext'},
        'main': './out/main.js',
        'activationEvents': ['onUri', 'workspaceContains:**/*.go'],
        'contributes': {
          'commands': [
            {'command': 'ext.run', 'title': 'Run'},
          ],
          'languages': [
            {'id': 'go', 'configuration': './language-configuration.json'},
            {'id': 'gomod'},
          ],
          'views': {
            'explorer': [
              {'id': 'ext.tree', 'name': 'Tree'},
            ],
          },
          'taskDefinitions': [
            {'type': 'go'},
          ],
          'authentication': [
            {'id': 'github', 'label': 'GitHub'},
          ],
          'terminal': {
            'profiles': [
              {'id': 'ext.shell', 'title': 'Shell'},
            ],
          },
        },
      });
      expect(events, [
        'onUri:pub.ext',
        'workspaceContains:**/*.go',
        'onCommand:ext.run',
        'onLanguage:go',
        'onView:ext.tree',
        'onTaskType:go',
        'onAuthenticationRequest:github',
        'onTerminalProfile:ext.shell',
      ]);
    });

    test('none for an extension without code', () {
      expect(
        readActivationEvents({
          'identifier': {'value': 'a.theme'},
          'activationEvents': ['*'],
          'contributes': {
            'themes': [<String, Object?>{}],
          },
        }),
        isEmpty,
      );
      expect(
        createActivationEventsMap([
          {
            'identifier': {'value': 'a.theme'},
          },
          {
            'identifier': {'value': 'A.Code'},
            'main': 'x.js',
            'activationEvents': ['*'],
          },
        ]),
        {
          'a.code': ['*'],
        },
      );
    });
  });

  test('crash tracker allows two automatic restarts in five minutes', () {
    var now = DateTime(2026);
    final tracker = ExtensionHostCrashTracker(now: () => now);
    tracker.registerCrash();
    expect(tracker.shouldAutomaticallyRestart(), isTrue);
    tracker.registerCrash();
    expect(tracker.shouldAutomaticallyRestart(), isTrue);
    tracker.registerCrash();
    expect(tracker.shouldAutomaticallyRestart(), isFalse);
    now = now.add(const Duration(minutes: 5, seconds: 1));
    expect(tracker.shouldAutomaticallyRestart(), isTrue);
  });

  test('server URIs become file URIs of the same path', () {
    final remote = toServer(VsUri.file('/a/b c')).toJson();
    expect(remote['scheme'], 'vscode-remote');
    expect(
      fromServer({
        'list': [remote],
      }),
      {
        'list': [VsUri.file('/a/b c').toJson()],
      },
    );
  });

  test('init data lists every scanned extension as this host\'s', () {
    final data = buildExtHostInitData(
      product: const ExtHostProduct(commit: 'c', version: '1.135.0'),
      environment: {'pid': 12, 'appRoot': VsUri.file('/app').toJson()},
      extensions: [
        {
          'identifier': {'value': 'A.b', '_lower': 'a.b'},
          'main': 'x.js',
          'contributes': {
            'commands': [
              {'command': 'b.run'},
            ],
          },
        },
      ],
      workspace: ExtHostWorkspace.folder('/w/proj'),
      language: 'zh-cn',
      sessionId: 's',
      machineId: 'm',
    );
    final extensions = data['extensions']! as Map;
    expect(extensions['myExtensions'], [
      {'value': 'A.b', '_lower': 'a.b'},
    ]);
    expect(extensions['activationEvents'], {
      'a.b': ['onCommand:b.run'],
    });
    expect((data['workspace']! as Map)['name'], 'proj');
    expect(data['parentPid'], 12);
    expect((data['remote']! as Map)['authority'], isNull);
  });

  group('ExtensionHostManager', () {
    late List<_Session> sessions;
    late List<_ExtensionService> services;

    Future<ExtHostSession> start() async {
      final (a, b) = _Pipe.pair();
      final main = RpcProtocol(a, actorNames: const {_service: 'svc'});
      final host = RpcProtocol(b, actorNames: const {_service: 'svc'});
      final service = _ExtensionService();
      host.set(_service, service);
      services.add(service);
      final session = _Session(main, host);
      sessions.add(session);
      return session;
    }

    setUp(() {
      sessions = [];
      services = [];
    });

    test('starts lazily and sends each activation event once', () async {
      final manager = ExtensionHostManager(
        start: start,
        extensionServiceId: _service,
      );
      expect(manager.state, ExtensionHostState.stopped);
      await manager.activateByEvent('*');
      await manager.activateByEvent('*');
      await manager.activateByEvent('onLanguage:go');
      expect(sessions, hasLength(1));
      expect(services.single.events, ['*', 'onLanguage:go']);
      expect(manager.state, ExtensionHostState.running);
      manager.dispose();
      expect(sessions.single.terminated, isTrue);
    });

    test('restarts after a crash and activates again', () async {
      final manager = ExtensionHostManager(
        start: start,
        extensionServiceId: _service,
      );
      await manager.activateByEvent('onStartupFinished');
      sessions.last.crash();
      await pumpEventQueue();
      expect(sessions, hasLength(2));
      expect(services.last.events, ['onStartupFinished']);
      expect(manager.state, ExtensionHostState.running);

      sessions.last.crash();
      await pumpEventQueue();
      expect(sessions, hasLength(3));
      sessions.last.crash();
      await pumpEventQueue();
      expect(sessions, hasLength(3), reason: 'third crash in 5 minutes');
      expect(manager.state, ExtensionHostState.failed);

      await manager.restart();
      expect(sessions, hasLength(4));
      expect(services.last.events, ['onStartupFinished']);
      manager.dispose();
    });

    test('activation events asked while the start failed are sent to the '
        'next start (a runtime download that failed, retried)', () async {
      var fail = true;
      final manager = ExtensionHostManager(
        start: () => fail
            ? Future<ExtHostSession>.error(StateError('no runtime'))
            : start(),
        extensionServiceId: _service,
      );
      await expectLater(manager.activateByEvent('*'), throwsStateError);
      await expectLater(
        manager.activateByEvent('onLanguage:typescript'),
        throwsStateError,
      );
      expect(manager.state, ExtensionHostState.failed);
      fail = false;
      await manager.activateByEvent('*');
      await pumpEventQueue();
      expect(sessions, hasLength(1));
      expect(services.single.events, ['*', 'onLanguage:typescript']);
      expect(manager.state, ExtensionHostState.running);
      manager.dispose();
    });

    test('a stop is not a crash', () async {
      final manager = ExtensionHostManager(
        start: start,
        extensionServiceId: _service,
      );
      var crashes = 0;
      manager.onDidCrash.listen((_) => crashes++);
      await manager.ensureStarted();
      await manager.stop();
      await pumpEventQueue();
      expect(manager.state, ExtensionHostState.stopped);
      expect(crashes, 0);
      expect(sessions, hasLength(1));
      manager.dispose();
    });
  });
}
