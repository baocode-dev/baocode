// The window area's actors driven the way the extension host drives them:
// `MainThreadXxxActor.invoke(method, args)` with the exact JSON
// src/vs/workbench/api/common/extHost.protocol.ts describes, and the calls
// back (through a fake `RpcProtocol`) checked.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/main_thread/main_thread_clipboard.dart';
import 'package:baocode/extensions/main_thread/main_thread_context.dart';
import 'package:baocode/extensions/main_thread/main_thread_dialogs.dart';
import 'package:baocode/extensions/main_thread/main_thread_label_service.dart';
import 'package:baocode/extensions/main_thread/main_thread_message_service.dart';
import 'package:baocode/extensions/main_thread/main_thread_progress.dart';
import 'package:baocode/extensions/main_thread/main_thread_status_bar.dart';
import 'package:baocode/extensions/main_thread/main_thread_storage.dart';
import 'package:baocode/extensions/main_thread/main_thread_window.dart';
import 'package:baocode/extensions/window/extension_storage.dart';
import 'package:baocode/extensions/window/label_service.dart';
import 'package:baocode/extensions/window/progress_service.dart';
import 'package:baocode/extensions/window/status_bar_service.dart';
import 'package:baocode/extensions/window/url_service.dart';
import 'package:baocode/extensions/window/window_ports.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/platform/error_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';
import 'fakes.dart';

/// A `SerializedError` as the extension host sends it.
Map<String, Object?> serializedErrorJSON(String message) => {
  'name': 'Error',
  'message': message,
  'stack': 'Error: $message\n    at Object.<anonymous>',
};

/// The calls an actor made back into the extension host, answered by a
/// scripted peer.
final class FakeRpc {
  final scripted = ScriptedRpc();

  RpcProtocol get protocol => scripted.protocol;

  /// Every call, as (`Actor.$method`, args).
  List<(String, List<Object?>)> get calls => scripted.calls;

  /// The arguments of the calls to any method of [actor].
  List<List<Object?>> callsTo(String actor) => [
    for (final (key, args) in scripted.calls)
      if (key.startsWith('$actor.')) args,
  ];

  /// A session's context over this RPC.
  MainThreadContext context() => MainThreadContext(rpc: protocol, services: {});
}

void main() {
  group('MainThreadMessageService', () {
    late IdeNotifications notifications;
    late FakeDialogs dialogs;
    late MainThreadMessageService service;
    late RpcActor actor;

    setUp(() {
      notifications = IdeNotifications();
      dialogs = FakeDialogs();
      service = MainThreadMessageService(
        ExtensionMessageUi(
          notifications: notifications,
          dialogs: dialogs,
          commands: FakeCommands(),
        ),
      );
      actor = MainThreadMessageServiceActor(service);
    });

    tearDown(() => notifications.dispose());

    test('a non-modal message with buttons is a notification', () async {
      final answer = actor.invoke(r'$showMessage', [
        2, // Severity.Warning
        'Something happened',
        {
          'source': {
            'label': 'Fixture',
            'identifier': {
              'value': 'baocode-test.fixture',
              '_lower': 'baocode-test.fixture',
            },
          },
        },
        [
          {'title': 'Yes', 'isCloseAffordance': false, 'handle': 1},
          {'title': 'No', 'isCloseAffordance': false, 'handle': 2},
        ],
      ]);
      await pumpEventQueue();
      expect(notifications.notifications, hasLength(1));
      final notification = notifications.notifications.first;
      expect(notification.severity, IdeSeverity.warning);
      expect(notification.message, 'Something happened');
      expect(notification.source, 'Fixture');
      expect([for (final a in notification.primary) a.label], ['Yes', 'No']);
      // Its gear has Manage Extension.
      expect(
        [for (final a in notification.secondary) a.label],
        ['Manage Extension'],
      );
      notification.primary[0].run();
      expect(await answer, 1);
    });

    test('closing without a button answers undefined', () async {
      final answer = actor.invoke(r'$showMessage', [
        1,
        'No buttons',
        <String, Object?>{},
        const <Map<String, Object?>>[],
      ]);
      await pumpEventQueue();
      expect(notifications.notifications.first.source, 'Extension');
      notifications.close(notifications.notifications.first);
      await pumpEventQueue();
      expect(await answer, isNull);
    });

    test(
      'a modal message is a dialog, Cancel close-affordance included',
      () async {
        dialogs.answers.add((button: 0, checked: false));
        final answer = actor.invoke(r'$showMessage', [
          3, // Severity.Error
          'Really?',
          {'modal': true, 'detail': 'A detail line'},
          [
            {'title': 'Yes', 'isCloseAffordance': false, 'handle': 11},
            {'title': 'No', 'isCloseAffordance': true, 'handle': 12},
          ],
        ]);
        await pumpEventQueue();
        expect(dialogs.prompts.single.message, 'Really?');
        expect(dialogs.prompts.single.detail, 'A detail line');
        expect(dialogs.prompts.single.buttons, ['Yes']);
        expect(dialogs.prompts.single.cancel, 'No');
        expect(dialogs.prompts.single.severity, ExtensionSeverity.error);
        expect(await answer, 11);
      },
    );

    test('a modal message without buttons has an OK cancel button', () async {
      dialogs.answers.add((button: null, checked: false));
      final answer = actor.invoke(r'$showMessage', [
        1,
        'Ping',
        {'modal': true},
        const <Map<String, Object?>>[],
      ]);
      await pumpEventQueue();
      expect(dialogs.prompts.single.cancel, 'OK');
      expect(await answer, isNull);
    });
  });

  group('MainThreadStatusBar', () {
    late ExtensionStatusBarService service;

    setUp(() => service = ExtensionStatusBarService());
    tearDown(() => service.dispose());

    test('sets, updates and disposes an entry', () async {
      final rpc = FakeRpc();
      final actor = MainThreadStatusBarActor(
        MainThreadStatusBar(
          service,
          ExtHostStatusBarProxy(rpc.protocol),
          rpc.context(),
        ),
      );
      actor.invoke(r'$setEntry', [
        'entry-1',
        'status-1',
        'baocode-test.fixture',
        'Fixture',
        r'$(beaker) 3',
        {'value': 'A **tooltip**'},
        false,
        {
          'id': 'fixture.run',
          'title': 'Run',
          'arguments': ['a'],
        },
        const {'id': 'statusBarItem.warningForeground'},
        const {'id': 'statusBarItem.warningBackground'},
        true,
        7,
        {'label': 'Fixture status'},
      ]);
      final entry = service.entry('entry-1')!;
      expect(entry.text, r'$(beaker) 3');
      expect(entry.kind, ExtensionStatusBarKind.warning);
      expect(entry.alignLeft, isTrue);
      expect(entry.priority, 7);
      expect(entry.ariaLabel, 'Fixture status');
      expect(entry.tooltipIsMarkdown, isTrue);
      expect(entry.command?['id'], 'fixture.run');
      expect(entry.toDto(), {
        'entryId': 'entry-1',
        'alignLeft': true,
        'priority': 7,
        'name': 'Fixture',
        'text': r'$(beaker) 3',
        'tooltip': 'A **tooltip**',
        'command': 'fixture.run',
        'accessibilityInformation': {'label': 'Fixture status'},
      });
      actor.invoke(r'$disposeEntry', ['entry-1']);
      expect(service.entry('entry-1'), isNull);
    });

    test('the aria label falls back to the text and tooltip', () async {
      final rpc = FakeRpc();
      final actor = MainThreadStatusBarActor(
        MainThreadStatusBar(
          service,
          ExtHostStatusBarProxy(rpc.protocol),
          rpc.context(),
        ),
      );
      actor.invoke(r'$setEntry', [
        'entry-1',
        'status-1',
        null,
        'Fixture',
        r'$(sync~spin) Indexing',
        'Working on it',
        true,
        null,
        null,
        null,
        false,
        null,
        null,
      ]);
      expect(
        service.entry('entry-1')!.ariaLabel,
        'sync Indexing, Working on it',
      );
      expect(service.entry('entry-1')!.hasTooltipProvider, isTrue);
    });
  });

  group('MainThreadProgress', () {
    late IdeNotifications notifications;
    late ExtensionProgressService progress;
    late FakeRpc rpc;

    setUp(() {
      notifications = IdeNotifications();
      progress = ExtensionProgressService(
        notifications: notifications,
        minNotificationShown: Duration.zero,
        windowProgressDelay: Duration.zero,
        minWindowProgressShown: Duration.zero,
      );
      rpc = FakeRpc();
    });

    tearDown(() {
      notifications.dispose();
      progress.dispose();
    });

    test('notification progress reports and ends', () async {
      final actor = MainThreadProgressActor(
        MainThreadProgress(progress, ExtHostProgressProxy(rpc.protocol)),
      );
      await actor.invoke(r'$startProgress', [
        3,
        {
          'location': 15, // ProgressLocation.Notification
          'title': 'Indexing',
          'cancellable': true,
        },
        'baocode-test.fixture',
      ]);
      expect(notifications.notifications, hasLength(1));
      expect(notifications.notifications.first.message, 'Indexing');
      actor.invoke(r'$progressReport', [
        3,
        {'message': 'src/a.dart', 'increment': 25, 'total': 100},
      ]);
      expect(notifications.notifications.first.message, 'Indexing: src/a.dart');
      expect(notifications.notifications.first.progress?.worked, 25);
      // Cancel asks the extension host.
      notifications.notifications.first.primary.last.run();
      await pumpEventQueue();
      expect(rpc.callsTo('ExtHostProgress').single, [3]);
      actor.invoke(r'$progressEnd', [3]);
      await pumpEventQueue(times: 20);
      expect(notifications.notifications, isEmpty);
    });

    test('a view id location keeps composite progress', () async {
      final actor = MainThreadProgressActor(
        MainThreadProgress(progress, ExtHostProgressProxy(rpc.protocol)),
      );
      await actor.invoke(r'$startProgress', [
        4,
        {'location': 'workbench.view.explorer', 'title': 'Scanning'},
        null,
      ]);
      actor.invoke(r'$progressReport', [
        4,
        {'increment': 30, 'total': 100},
      ]);
      expect(progress.progressOf('workbench.view.explorer')?.worked, 30);
      actor.invoke(r'$progressEnd', [4]);
      await pumpEventQueue(times: 20);
      expect(progress.progressOf('workbench.view.explorer'), isNull);
    });

    test('a bad location is recorded, not thrown', () async {
      final errorLog = _RecordingErrorLog();
      final actor = MainThreadProgressActor(
        MainThreadProgress(
          progress,
          ExtHostProgressProxy(rpc.protocol),
          errorLog: errorLog,
        ),
      );
      await actor.invoke(r'$startProgress', [
        5,
        {'location': 20, 'title': 'Nope'}, // ProgressLocation.Dialog
        null,
      ]);
      expect(errorLog.recorded.single, contains('Bad progress location: 20'));
    });
  });

  group('MainThreadWindow', () {
    test('reports the initial focus and pushes changes', () async {
      final focus = FakeWindowFocus();
      final rpc = FakeRpc();
      final opener = FakeOpener();
      final actor = MainThreadWindowActor(
        MainThreadWindow(
          focus,
          ExtHostWindowProxy(rpc.protocol),
          opener: opener,
          urls: ExtensionUrlService(dialogs: FakeDialogs()),
        ),
      );
      expect(await actor.invoke(r'$getInitialState', const []), {
        'isFocused': true,
        'isActive': true,
      });
      focus.set(focused: false);
      focus.set(active: false);
      await pumpEventQueue();
      expect(
        [for (final (key, _) in rpc.calls) key],
        [
          r'ExtHostWindow.$onDidChangeWindowFocus',
          r'ExtHostWindow.$onDidChangeWindowActive',
        ],
      );
      await focus.dispose();
    });

    test('opens a URL outside and command URIs without running them', () async {
      final opener = FakeOpener();
      final actor = MainThreadWindowActor(
        MainThreadWindow(
          FakeWindowFocus(),
          ExtHostWindowProxy(FakeRpc().protocol),
          opener: opener,
        ),
      );
      final vsUri = VsUri.parse('https://example.com/a');
      expect(
        await actor.invoke(r'$openUri', [
          vsUri.toJson(),
          'https://example.com/a',
          <String, Object?>{},
        ]),
        isTrue,
      );
      expect(opener.opened.single.toString(), 'https://example.com/a');
      expect(
        await actor.invoke(r'$openUri', [
          VsUri.parse('command:fixture.run').toJson(),
          null,
          <String, Object?>{},
        ]),
        isTrue,
      );
      expect(opener.opened, hasLength(1));
    });

    test('an app URI goes to the URL service', () async {
      final urls = ExtensionUrlService(
        dialogs: FakeDialogs()..answers.add((button: 0, checked: false)),
      );
      final host = FakeUrlHost('ws-1');
      urls.addHost(host);
      final handled = <String>[];
      urls.registerExtensionHandler(
        host,
        'baocode-test.fixture',
        'Fixture',
        (uri) async => handled.add(uri.path),
      );
      final opener = FakeOpener();
      final actor = MainThreadWindowActor(
        MainThreadWindow(
          FakeWindowFocus(),
          ExtHostWindowProxy(FakeRpc().protocol),
          opener: opener,
          urls: urls,
        ),
      );
      expect(
        await actor.invoke(r'$openUri', [
          VsUri.parse('baocode://baocode-test.fixture/cb').toJson(),
          null,
          <String, Object?>{},
        ]),
        isTrue,
      );
      expect(handled, ['/cb']);
      expect(opener.opened, isEmpty);
    });

    test(
      'asExternalUri returns the URI, and no tunnel hides local ports',
      () async {
        final actor = MainThreadWindowActor(
          MainThreadWindow(
            FakeWindowFocus(),
            ExtHostWindowProxy(FakeRpc().protocol),
            opener: FakeOpener(),
          ),
        );
        final uri = VsUri.parse('http://localhost:3000/a');
        final external = await actor.invoke(r'$asExternalUri', [
          uri.toJson(),
          {'allowTunneling': true},
        ]);
        expect(external, isA<VsUri>());
      expect('$external', '$uri');
      },
    );
  });

  group('MainThreadClipboard', () {
    test('reads and writes the system clipboard', () async {
      final clipboard = FakeClipboard();
      final actor = MainThreadClipboardActor(MainThreadClipboard(clipboard));
      await actor.invoke(r'$writeText', ['hello']);
      expect(clipboard.text, 'hello');
      expect(await actor.invoke(r'$readText', const []), 'hello');
    });
  });

  group('MainThreadStorage', () {
    late Directory dir;
    late ExtensionStorageService storage;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('window-storage-actor');
      storage = ExtensionStorageService(userDir: dir.path);
    });

    tearDown(() => dir.delete(recursive: true));

    test(
      'initializes, sets and pushes a shared value to other hosts',
      () async {
        final rpc = FakeRpc();
        final actor = MainThreadStorageActor(
          MainThreadStorage(
            storage,
            ExtHostStorageProxy(rpc.protocol),
            workspaceId: 'ws-1',
          ),
        );
        expect(
          await actor.invoke(r'$initializeExtensionStorage', [true, 'a.b']),
          isNull,
        );
        await actor.invoke(r'$setValue', [
          true,
          'a.b',
          {'key': 'value'},
        ]);
        await storage.global.flush();
        expect(
          await actor.invoke(r'$initializeExtensionStorage', [true, 'a.b']),
          '{"key":"value"}',
        );
        // A second host of another workspace reads the same global state.
        final other = MainThreadStorageActor(
          MainThreadStorage(
            storage,
            ExtHostStorageProxy(FakeRpc().protocol),
            workspaceId: 'ws-2',
          ),
        );
        expect(
          await other.invoke(r'$initializeExtensionStorage', [true, 'a.b']),
          '{"key":"value"}',
        );
        // And a change in one goes to the other's extension.
        await other.invoke(r'$setValue', [
          true,
          'a.b',
          {'key': 'other'},
        ]);
        await storage.global.flush();
        await pumpEventQueue();
        // As upstream, every change of a watched shared key is pushed,
        // this host's own write included.
        expect(rpc.callsTo('ExtHostStorage'), [
          [true, 'a.b', '{"key":"value"}'],
          [true, 'a.b', '{"key":"other"}'],
        ]);
      },
    );

    test('workspace state stays in the workspace', () async {
      final actor = MainThreadStorageActor(
        MainThreadStorage(
          storage,
          ExtHostStorageProxy(FakeRpc().protocol),
          workspaceId: 'ws-1',
        ),
      );
      await actor.invoke(r'$setValue', [
        false,
        'a.b',
        ['x'],
      ]);
      await storage.flush();
      expect(
        await actor.invoke(r'$initializeExtensionStorage', [false, 'a.b']),
        '["x"]',
      );
      final other = MainThreadStorageActor(
        MainThreadStorage(
          storage,
          ExtHostStorageProxy(FakeRpc().protocol),
          workspaceId: 'ws-2',
        ),
      );
      expect(
        await other.invoke(r'$initializeExtensionStorage', [false, 'a.b']),
        isNull,
      );
    });

    test('registers the keys to sync', () async {
      final actor = MainThreadStorageActor(
        MainThreadStorage(
          storage,
          ExtHostStorageProxy(FakeRpc().protocol),
          workspaceId: 'ws-1',
        ),
      );
      actor.invoke(r'$registerExtensionStorageKeysToSync', [
        {'id': 'a.b', 'version': '1.0.0'},
        ['k1', 'k2'],
      ]);
      await pumpEventQueue();
      await storage.flush();
      expect(storage.getKeysForSync('a.b', '1.0.0'), ['k1', 'k2']);
    });
  });

  group('MainThreadDialogs', () {
    test('open and save dialogs ask the app pickers', () async {
      final pickers = FakePickers()
        ..openResult = ['/tmp/a.dart', '/tmp/b.dart'];
      final downloads = MainThreadDialogsActor(
        MainThreadDialogs(pickers, defaultDirectory: '/tmp'),
      );
      final result = await downloads.invoke(r'$showOpenDialog', [
        {
          'canSelectFiles': true,
          'canSelectMany': true,
          'filters': {
            'Dart': ['dart'],
          },
          'defaultUri': VsUri.file('/tmp').toJson(),
        },
      ]);
      expect(
        pickers.openCalls.single,
        'files=true folders=false many=true dir=/tmp',
      );
      expect((result! as List).map((uri) => (uri as VsUri).path), [
        '/tmp/a.dart',
        '/tmp/b.dart',
      ]);
      pickers.saveResult = '/tmp/out.txt';
      final saved = await downloads.invoke(r'$showSaveDialog', [
        {
          'saveLabel': 'Save it',
          'defaultUri': VsUri.file('/tmp/out.txt').toJson(),
        },
      ]);
      expect(pickers.saveCalls.single, 'dir=/tmp name=out.txt');
      expect((saved! as VsUri).path, '/tmp/out.txt');
    });

    test('a cancelled dialog answers undefined', () async {
      final pickers = FakePickers();
      final actor = MainThreadDialogsActor(
        MainThreadDialogs(pickers, defaultDirectory: null),
      );
      expect(await actor.invoke(r'$showOpenDialog', const [null]), isNull);
      expect(await actor.invoke(r'$showSaveDialog', const [null]), isNull);
    });
  });

  group('MainThreadLabelService', () {
    test('registers and unregisters a formatter', () async {
      final labels = ExtensionLabelService();
      final actor = MainThreadLabelServiceActor(MainThreadLabelService(labels));
      actor.invoke(r'$registerResourceLabelFormatter', [
        1,
        {
          'scheme': 'wsl',
          'formatting': {'label': r'WSL: ${path}', 'separator': '/'},
        },
      ]);
      expect(labels.formatters.single['priority'], isTrue);
      actor.invoke(r'$unregisterResourceLabelFormatter', [1]);
      expect(labels.formatters, isEmpty);
      labels.dispose();
    });
  });
}

/// An [ErrorLog]-like recorder: [MainThreadProgress] takes the app's log as
/// an interface, so the test records instead of writing.
final class _RecordingErrorLog implements ErrorLog {
  final List<String> recorded = [];

  @override
  void record(
    Object error,
    StackTrace? stack, {
    String? context,
    required String source,
  }) => recorded.add('$error');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
