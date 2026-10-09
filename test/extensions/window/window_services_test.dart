// The window area's services: the JSON state store, the status bar's
// entries and their order, the URL service (trust, buffering, activation),
// the progress service (its locations and the window stack), the running
// extensions' ordering, the label service's formatters and the app-wide
// extension storage.

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/window/extension_storage.dart';
import 'package:baocode/extensions/window/json_state_store.dart';
import 'package:baocode/extensions/window/label_service.dart';
import 'package:baocode/extensions/window/progress_service.dart';
import 'package:baocode/extensions/window/runtime_extensions.dart';
import 'package:baocode/extensions/window/status_bar_service.dart';
import 'package:baocode/extensions/window/url_service.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

void main() {
  group('JsonStateStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('window-state');
    });

    tearDown(() => dir.delete(recursive: true));

    test('writes atomically and reads back', () async {
      final store = JsonStateStore(p.join(dir.path, 'state.json'));
      await store.load();
      store.set('a', 'one');
      store.setJson('b', {'n': 1});
      await store.flush();
      final file = File(p.join(dir.path, 'state.json'));
      expect(jsonDecode(await file.readAsString()), {
        'a': 'one',
        'b': '{"n":1}',
      });
      final again = JsonStateStore(p.join(dir.path, 'state.json'));
      await again.load();
      expect(again.get('a'), 'one');
      expect(again.getJson('b'), {'n': 1});
      await store.dispose();
      await again.dispose();
    });

    test('a broken file starts empty and changes are broadcast', () async {
      final path = p.join(dir.path, 'state.json');
      await File(path).writeAsString('{ not json');
      final store = JsonStateStore(path);
      await store.load();
      expect(store.keys, isEmpty);
      final changes = <JsonStateChange>[];
      final subscription = store.changes.listen(changes.add);
      store.set('k', 'v');
      store.remove('k');
      await pumpEventQueue();
      expect(changes, [(key: 'k', value: 'v'), (key: 'k', value: null)]);
      await subscription.cancel();
      await store.dispose();
    });
  });

  group('ExtensionStatusBarService', () {
    test('orders entries and hides them by id', () {
      final service = ExtensionStatusBarService();
      service.setOrUpdateEntry(
        entryId: 'a',
        id: 'a',
        extensionId: 'baocode-test.a',
        name: 'A',
        text: '1',
        tooltip: null,
        alignLeft: true,
        priority: 1,
      );
      service.setOrUpdateEntry(
        entryId: 'b',
        id: 'b',
        extensionId: 'baocode-test.b',
        name: 'B',
        text: '2',
        tooltip: null,
        alignLeft: true,
        priority: 5,
      );
      service.setOrUpdateEntry(
        entryId: 'c',
        id: 'c',
        extensionId: 'baocode-test.c',
        name: 'C',
        text: '3',
        tooltip: null,
        alignLeft: false,
        priority: 0,
      );
      expect(
        [for (final e in service.visible(left: true)) e.entryId],
        ['b', 'a'],
      );
      expect(
        [for (final e in service.visible(left: false)) e.entryId],
        ['c'],
      );
      service.setHidden('c', true);
      expect(service.visible(left: false), isEmpty);
      expect(service.isHidden('c'), isTrue);
      expect(service.entries.length, 3);
      service.dispose();
    });

    test('alignment and priority are set once, at creation', () {
      final service = ExtensionStatusBarService();
      service.setOrUpdateEntry(
        entryId: 'a',
        id: 'a',
        extensionId: null,
        name: 'A',
        text: '1',
        tooltip: null,
        alignLeft: true,
        priority: 7,
      );
      service.setOrUpdateEntry(
        entryId: 'a',
        id: 'a',
        extensionId: null,
        name: 'A2',
        text: '2',
        tooltip: null,
        alignLeft: false,
        priority: 0,
      );
      final entry = service.entry('a')!;
      expect(entry.alignLeft, isTrue);
      expect(entry.priority, 7);
      expect(entry.text, '2');
      service.dispose();
    });

    test('the error and warning backgrounds become an entry kind', () {
      final service = ExtensionStatusBarService();
      service.setOrUpdateEntry(
        entryId: 'e',
        id: 'e',
        extensionId: null,
        name: 'E',
        text: 'x',
        tooltip: null,
        alignLeft: true,
        priority: 0,
        backgroundColor: const {'id': 'statusBarItem.errorBackground'},
      );
      expect(service.entry('e')!.kind, ExtensionStatusBarKind.error);
      service.dispose();
    });

    test('the aria label names the icons and the tooltip', () {
      final service = ExtensionStatusBarService();
      service.setOrUpdateEntry(
        entryId: 'a',
        id: 'a',
        extensionId: null,
        name: 'A',
        text: r'$(git-branch) main',
        tooltip: 'The branch',
        alignLeft: true,
        priority: 0,
      );
      expect(service.entry('a')!.ariaLabel, 'git branch main, The branch');
      service.dispose();
    });

    test('contributes.statusBarItems needs the proposal and adds entries',
        () {
      final service = ExtensionStatusBarService();
      final description = {
        'identifier': {'value': 'baocode-test.static'},
        'name': 'static',
        'publisher': 'baocode-test',
        'displayName': 'Static',
        'enabledApiProposals': ['contribStatusBarItems'],
        'contributes': {
          'statusBarItems': [
            {
              'id': 'hello',
              'name': 'Hello',
              'text': r'$(beaker) run',
              'alignment': 'left',
              'priority': 3,
              'command': 'static.run',
            },
          ],
        },
      };
      service.setContributions([description]);
      expect(
        service.entry('baocode-test.static.hello')?.text,
        r'$(beaker) run',
      );
      expect(
        service.entry('baocode-test.static.hello')?.command?['id'],
        'static.run',
      );
      service.setContributions(const []);
      expect(service.entry('baocode-test.static.hello'), isNull);
      service.dispose();
    });

    test('stringHash matches JavaScript', () {
      // `stringHash('vscode.git', 0) | 0`, from upstream's hash.ts run in
      // node.
      expect(stringHash('vscode.git'), 517599863);
    });
  });

  group('ExtensionUrlService', () {
    test('routes a URI to a registered extension handler', () async {
      // Trusted through the dialog, as the first URI of an extension is.
      final urls = ExtensionUrlService(
        dialogs: FakeDialogs()..answers.add((button: 0, checked: false)),
      );
      final host = FakeUrlHost('ws-1');
      urls.addHost(host);
      final handled = <String>[];
      urls.registerExtensionHandler(
        host,
        'baocode-test.oauth',
        'OAuth',
        (uri) async => handled.add(uri.toString()),
      );
      final uri = VsUri.parse('baocode://baocode-test.oauth/callback?code=1');
      expect(await urls.open(uri), isTrue);
      // `URI.toString()` escapes `=` (upstream's `encodeURIComponentFast`).
      expect(handled, ['baocode://baocode-test.oauth/callback?code%3D1']);
    });

    test('buffers a URI until the handler registers, activating onUri',
        () async {
      final urls = ExtensionUrlService(
        dialogs: FakeDialogs()..answers.add((button: 0, checked: false)),
      );
      final host = FakeUrlHost('ws-1')
        ..extensions['baocode-test.oauth'] = {
          'identifier': {'value': 'baocode-test.oauth'},
          'name': 'oauth',
          'publisher': 'baocode-test',
          'displayName': 'OAuth',
        };
      urls.addHost(host);
      final uri = VsUri.parse('baocode://baocode-test.oauth/callback');
      expect(await urls.open(uri), isTrue);
      expect(host.events, ['onUri:baocode-test.oauth']);
      final handled = <String>[];
      urls.registerExtensionHandler(
        host,
        'baocode-test.oauth',
        'OAuth',
        (uri) async => handled.add(uri.path),
      );
      await pumpEventQueue();
      expect(handled, ['/callback']);
    });

    test('asks before an untrusted extension opens a URI, and remembers',
        () async {
      final dialogs = FakeDialogs()
        ..answers.add((button: 0, checked: true));
      final store = JsonStateStore(
        '${Directory.systemTemp.path}/baocode-window-url-'
        '${DateTime.now().microsecondsSinceEpoch}.json',
      );
      addTearDown(store.dispose);
      final urls = ExtensionUrlService(dialogs: dialogs, trustStore: store);
      final host = FakeUrlHost('ws-1');
      urls.addHost(host);
      final handled = <String>[];
      urls.registerExtensionHandler(
        host,
        'baocode-test.oauth',
        'OAuth',
        (uri) async => handled.add(uri.path),
      );
      final first = VsUri.parse('baocode://baocode-test.oauth/a');
      expect(await urls.open(first), isTrue);
      expect(handled, ['/a']);
      expect(dialogs.prompts, hasLength(1));
      expect(
        dialogs.prompts.first.message,
        "Allow 'OAuth' extension to open this URI?",
      );
      // Trusted now: no second prompt.
      final second = VsUri.parse('baocode://baocode-test.oauth/b');
      expect(await urls.open(second), isTrue);
      expect(handled, ['/a', '/b']);
      expect(dialogs.prompts, hasLength(1));
    });

    test('a denied URI is not handled', () async {
      final dialogs = FakeDialogs()..answers.add((button: null, checked: false));
      final urls = ExtensionUrlService(dialogs: dialogs);
      final host = FakeUrlHost('ws-1');
      urls.addHost(host);
      final handled = <String>[];
      urls.registerExtensionHandler(
        host,
        'baocode-test.oauth',
        'OAuth',
        (uri) async => handled.add(uri.path),
      );
      expect(
        await urls.open(VsUri.parse('baocode://baocode-test.oauth/a')),
        isTrue,
      );
      expect(handled, isEmpty);
    });

    test('a URI of an unknown extension is offered for install', () async {
      final commands = FakeCommands();
      final urls = ExtensionUrlService(
        dialogs: FakeDialogs(),
        commands: commands,
      );
      urls.addHost(FakeUrlHost('ws-1'));
      expect(
        await urls.open(VsUri.parse('baocode://other.extension/x')),
        isTrue,
      );
      expect(commands.runs.single.$1, 'workbench.extensions.installExtension');
      expect(commands.runs.single.$2.first, 'other.extension');
    });

    test('create adds the window id and the app scheme', () {
      final urls = ExtensionUrlService();
      final created = urls.create(
        VsUri.parse('https://example.com/a?b=1'),
        windowId: 'ws 1',
      );
      expect(created.scheme, 'baocode');
      expect(created.authority, 'example.com');
      expect(created.path, '/a');
      expect(created.query, 'b=1&windowId=ws%201');
    });

    test('takes a URI request of the platform', () async {
      final urls = ExtensionUrlService(
        dialogs: FakeDialogs()..answers.add((button: 0, checked: false)),
      );
      final host = FakeUrlHost('ws-1');
      urls.addHost(host);
      final handled = <String>[];
      urls.registerExtensionHandler(
        host,
        'baocode-test.oauth',
        'OAuth',
        (uri) async => handled.add(uri.path),
      );
      expect(
        urls.handleOpenRequest([
          ExtensionUrlService.requestMarker,
          'baocode://baocode-test.oauth/from-system',
        ]),
        isTrue,
      );
      await pumpEventQueue();
      expect(handled, ['/from-system']);
      expect(urls.handleOpenRequest(['/a/file']), isFalse);
    });
  });

  group('ExtensionProgressService', () {
    test('notification progress shows, reports and closes', () async {
      final notifications = IdeNotifications();
      final progress = ExtensionProgressService(
        notifications: notifications,
        minNotificationShown: Duration.zero,
      );
      final steps = <ExtensionProgressStep>[];
      final task = progress.start(
        location: ExtensionProgressLocation.notification,
        title: 'Indexing',
      );
      task.report((message: 'file one', increment: 10, total: 100));
      await pumpEventQueue();
      expect(notifications.notifications, hasLength(1));
      expect(notifications.notifications.first.message, 'Indexing: file one');
      expect(
        notifications.notifications.first.progress?.worked,
        10,
      );
      task.report((message: null, increment: 20, total: 100));
      expect(
        notifications.notifications.first.progress?.worked,
        30,
      );
      task.done();
      await pumpEventQueue(times: 20);
      expect(notifications.notifications, isEmpty);
      expect(steps, isEmpty);
      progress.dispose();
    });

    test('window progress shows in the status bar with the source in its tooltip',
        () async {
      final notifications = IdeNotifications();
      final progress = ExtensionProgressService(
        notifications: notifications,
        minNotificationShown: Duration.zero,
        windowProgressDelay: Duration.zero,
        minWindowProgressShown: Duration.zero,
      );
      final task = progress.start(
        location: ExtensionProgressLocation.window,
        title: 'Building',
        source: 'Fixture',
        delay: Duration.zero,
      );
      task.report((message: 'linking', increment: null, total: null));
      await pumpEventQueue();
      // It shows as a silent notification and, while hidden, in the bar.
      final entry = progress.windowEntry;
      expect(entry, isNotNull);
      expect(entry!.text, 'Building: linking');
      expect(entry.tooltip, '[Fixture] Building: linking');
      task.done();
      await pumpEventQueue(times: 20);
      expect(progress.windowEntry, isNull);
      progress.dispose();
    });

    test('a view id keeps composite progress', () async {
      final progress = ExtensionProgressService(
        notifications: IdeNotifications(),
        activityProgressDelay: Duration.zero,
        minActivityProgressShown: Duration.zero,
      );
      final task = progress.start(
        location: 'workbench.view.explorer',
        title: 'Scanning',
        delay: null,
      );
      task.report((message: null, increment: 25, total: 100));
      await pumpEventQueue();
      expect(progress.progressOf('workbench.view.explorer')?.worked, 25);
      expect(progress.hasActivityProgress('workbench.view.explorer'), isTrue);
      task.done();
      await pumpEventQueue(times: 20);
      expect(progress.progressOf('workbench.view.explorer'), isNull);
      expect(progress.hasActivityProgress('workbench.view.explorer'), isFalse);
      progress.dispose();
    });

    test('a bad location throws', () {
      final progress = ExtensionProgressService(
        notifications: IdeNotifications(),
      );
      expect(
        () => progress.start(location: 999),
        throwsA(isA<ArgumentError>()),
      );
      progress.dispose();
    });
  });

  group('ExtensionRuntimeService', () {
    test('orders the slowest activation first and groups the errors', () {
      final service = ExtensionRuntimeService();
      service.didActivate(
        'a.x',
        'A',
        'ws',
        codeLoadingTime: 10,
        activateCallTime: 5,
        activateResolvedTime: 1,
        reason: const ExtensionActivationReason(
          startup: true,
          extensionId: 'a.x',
          activationEvent: '*',
        ),
      );
      service.willActivate('b.y', 'B', 'ws');
      service.didActivate(
        'b.y',
        'B',
        'ws',
        codeLoadingTime: 100,
        activateCallTime: 50,
        activateResolvedTime: 2,
        reason: const ExtensionActivationReason(
          startup: false,
          extensionId: 'a.x',
          activationEvent: 'onLanguage:typescript',
        ),
      );
      service.runtimeError(
        'a.x',
        'A',
        'ws',
        const ExtensionRuntimeException('boom', 'stack'),
      );
      expect([for (final e in service.sorted()) e.id], ['b.y', 'a.x']);
      expect(service.withErrors.map((e) => e.id), ['a.x']);
      expect(service.extension('b.y')!.syncTime, 150);
      expect(
        service.extension('b.y')!.activationTimes!.reason.description,
        'Activated by onLanguage:typescript on a.x',
      );
      expect(service.extension('a.x')!.activationTimes!.reason.description,
          'Startup Activation');
      service.dispose();
    });

    test('a failed activation is kept with its missing dependency', () {
      final service = ExtensionRuntimeService();
      service.activationError(
        'a.x',
        'A',
        'ws',
        const ExtensionActivationError('failed', null, missing: 'b.y'),
      );
      expect(service.extension('a.x')!.activationError!.missing, 'b.y');
      service.clearErrors('a.x');
      expect(service.extension('a.x')!.errors, isEmpty);
      service.dispose();
    });
  });

  group('ExtensionLabelService', () {
    test('formats by the registered formatter, the longest authority first',
        () {
      final labels = ExtensionLabelService();
      labels.registerFormatter({
        'scheme': 'vscode-remote',
        'formatting': {'label': r'${authority}${path}', 'separator': '/'},
      });
      labels.registerFormatter({
        'scheme': 'vscode-remote',
        'authority': 'ssh-remote+*',
        'formatting': {
          'label': r'${authoritySuffix}${path}',
          'separator': '/',
          'stripPathSegments': 1,
        },
      });
      expect(
        labels.uriLabel(VsUri.parse('vscode-remote://ssh-remote+box/x/y/z')),
        'box/y/z',
      );
      expect(
        labels.uriLabel(VsUri.parse('vscode-remote://other/x/y')),
        'other/x/y',
      );
      labels.dispose();
    });

    test('a formatter without a scheme match formats nothing', () {
      final labels = ExtensionLabelService();
      labels.registerFormatter({
        'scheme': 'wsl',
        'formatting': {'label': r'${path}'},
      });
      expect(labels.uriLabel(VsUri.file('/tmp/a')), isNull);
      labels.dispose();
    });

    test('query placeholders and tildify', () {
      final labels = ExtensionLabelService(userHome: '/Users/me');
      labels.registerFormatter({
        'scheme': 'github',
        'formatting': {
          'label': r'${path} (${query.git-ref})',
          'tildify': true,
          'separator': '/',
        },
      });
      final uri = VsUri(
        'github',
        path: '/Users/me/project',
        query: '{"git-ref":"main"}',
      );
      expect(labels.uriLabel(uri), '~/project (main)');
      labels.dispose();
    });
  });

  group('ExtensionStorageService', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('window-storage');
    });

    tearDown(() => dir.delete(recursive: true));

    test('keeps global and workspace state under the User directory',
        () async {
      final storage = ExtensionStorageService(userDir: dir.path);
      await storage.setExtensionState(
        'baocode-test.a',
        {'n': 1},
        global: true,
        workspaceId: 'ws-1',
      );
      await storage.setExtensionState(
        'baocode-test.a',
        ['x'],
        global: false,
        workspaceId: 'ws-1',
      );
      expect(
        await storage.getExtensionStateRaw(
          'baocode-test.a',
          global: true,
          workspaceId: 'ws-1',
        ),
        '{"n":1}',
      );
      expect(
        await storage.getExtensionStateRaw(
          'baocode-test.a',
          global: false,
          workspaceId: 'ws-1',
        ),
        '["x"]',
      );
      await storage.flush();
      expect(
        File(p.join(dir.path, 'globalStorage', 'state.json')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(dir.path, 'workspaceStorage', 'ws-1', 'state.json'),
        ).existsSync(),
        isTrue,
      );
      // A second workspace does not see the first's.
      expect(
        await storage.getExtensionStateRaw(
          'baocode-test.a',
          global: false,
          workspaceId: 'ws-2',
        ),
        isNull,
      );
    });

    test('sync keys are stored by extension id and version', () async {
      final storage = ExtensionStorageService(userDir: dir.path);
      await storage.setKeysForSync('Baocode-Test.A', '1.2.3', ['k']);
      expect(storage.getKeysForSync('baocode-test.a', '1.2.3'), ['k']);
      await storage.flush();
    });
  });
}
