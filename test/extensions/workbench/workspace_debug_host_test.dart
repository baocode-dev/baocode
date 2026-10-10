// Goal section 9.4: workspace effects of debugging, without a real adapter.

import 'dart:async';
import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/common/debug_storage.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_host.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/files/file_service.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/trust/workspace_trust.dart';
import 'package:baocode/extensions/window/json_state_store.dart';
import 'package:baocode/extensions/window/quick_input/quick_input_model.dart';
import 'package:baocode/extensions/window/quick_input/quick_input_service.dart';
import 'package:baocode/extensions/workbench/workspace_debug_host.dart';
import 'package:baocode/extensions/workspace/workspace_context.dart';
import 'package:baocode/ide/ide_editor_features.dart';
import 'package:baocode/ide/ide_editor_views.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../debug/support/fake_debug_adapter.dart';
import '../../ide/workbench/fake_files.dart';
import '../files/mem_file_system.dart';
import '../support/main_thread_harness.dart';
import '../window/fakes.dart';

class _SourceAdapter extends FakeDebugAdapter {
  String content = '';
  int seq = 10000;

  @override
  void send(Json message) {
    if (message['command'] != 'source') {
      super.send(message);
      return;
    }
    scheduleMicrotask(
      () => acceptMessage({
        'seq': seq++,
        'type': 'response',
        'request_seq': message['seq'],
        'command': 'source',
        'success': true,
        'body': {'content': content},
      }),
    );
  }
}

void main() {
  late IdeWorkspace workspace;
  late TreeFiles disk;
  late ConfigurationService configuration;
  late TestSettings user;
  late TestSettings settings;
  late WorkspaceContextService context;
  late WorkspaceTrustStore trustStore;
  late WorkspaceTrustService trust;
  late ContextKeyService keys;
  late ExtensionCommandRegistry commands;
  late ExtensionQuickInputService inputs;
  late FakeDialogs dialogs;
  late WorkspaceDebugHost host;
  late List<String> activations;
  final root = p.join(p.separator, 'debug-workspace');
  final program = p.join(root, 'main.js');
  final folder = VsUri.file(root);

  setUp(() async {
    disk = TreeFiles({program: 'one\ntwo\nthree\n'});
    workspace = IdeWorkspace(
      root,
      files: disk,
      extensionLanguageId: (_) => 'javascript',
    );
    user = TestSettings({
      'launch': {'configurations': <Object?>[]},
    });
    settings = TestSettings({'debug.inlineValues': 'on'});
    configuration = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: user,
      workspace: settings,
    );
    context = WorkspaceContextService(ExtHostWorkspace.folder(root));
    trustStore = WorkspaceTrustStore(TestTrustStorage());
    trust = WorkspaceTrustService(
      store: trustStore,
      workspaceUris: () => [folder],
      workspaceId: 'debug',
    );
    await trust.initialize();
    keys = ContextKeyService();
    commands = ExtensionCommandRegistry();
    inputs = ExtensionQuickInputService();
    dialogs = FakeDialogs();
    activations = [];
    host = WorkspaceDebugHost(
      workspace: workspace,
      configuration: configuration,
      context: context,
      keys: keys,
      commands: commands,
      inputs: inputs,
      dialogs: dialogs,
      trust: trust,
      activate: (event) async => activations.add(event),
      extensions: () => [
        {
          'identifier': {'value': 'acme.debug'},
          'extensionLocation': VsUri.file(p.join(root, 'extension')).toJson(),
        },
      ],
    );
  });

  tearDown(() {
    host.dispose();
    inputs.dispose();
    commands.dispose();
    keys.dispose();
    trust.dispose();
    trustStore.dispose();
    context.dispose();
    configuration.dispose();
    user.dispose();
    settings.dispose();
    workspace.dispose();
  });

  IdeEditorView show(
    IdeDocument doc, {
    void Function()? focus,
    void Function(int, int, {bool center})? reveal,
  }) {
    final controller = EditorSurfaceController(document: doc.model);
    final features = IdeEditorFeatures(
      controller: controller,
      types: EditorDecorationTypeRegistry(),
    );
    addTearDown(() {
      features.dispose();
      controller.dispose();
    });
    final view = IdeEditorView(
      document: doc,
      controller: controller,
      features: features,
      visibleLines: () => (first: 1, last: 3),
      hasFocus: () => false,
      focus: focus ?? () {},
      reveal: reveal ?? (_, _, {center = false}) {},
    );
    workspace.editorViews.show(view);
    return view;
  }

  test(
    'workspace variables use the active document and its primary selection',
    () async {
      await workspace.open(program);
      final view = show(workspace.active!);
      view.controller.setSelections([
        const TextSelection(baseOffset: 4, extentOffset: 7),
      ]);
      final editor = host.activeEditor!;
      expect(editor.uri, VsUri.file(program));
      expect(editor.languageId, 'javascript');
      expect(editor.lineNumber, 2);
      expect(editor.column, 4);
      expect(editor.selectedText, 'two');
      expect(host.lastActiveWorkspaceRoot, folder);
      expect(host.workspaceFolders.single.uri, folder);
      expect(
        host.extensionInstallFolder('ACME.DEBUG'),
        p.join(root, 'extension'),
      );
      expect(host.settings().inlineValues, 'on');
      expect(host.userLaunchConfiguration, contains('configurations'));
      workspace.edit(program, 'changed');
      expect(host.isDirty(VsUri.file(program)), isTrue);
      await workspace.openRevision(
        program,
        label: 'old',
        read: () async => 'old',
      );
      expect(host.activeEditor, isNull);
    },
  );

  test('trust is denied without consent and activation/commands/when reach real services', () async {
    expect(await host.requestWorkspaceTrust('Run code?'), isFalse);
    await trustStore.setUrisTrust([folder], true);
    expect(await host.requestWorkspaceTrust('Run code?'), isTrue);
    await host.activateByEvent('onDebugResolve:node');
    expect(activations, ['onDebugResolve:node']);
    commands.registerExtensionCommand(
      'debug.input',
      (_, args) async => args.single,
    );
    expect(await host.executeCommand('debug.input', ['value']), 'value');
    final enabled = keys.createKey<bool>('debug.enabled', false);
    expect(host.evaluateWhen('debug.enabled'), isFalse);
    enabled.set(true);
    expect(host.evaluateWhen('debug.enabled'), isTrue);
    expect(host.evaluateWhen('debug.enabled && !debug.hidden'), isTrue);
  });

  test('input and picker accept values, cancel, supersede and settle on host disposal', () async {
    final text = host.showInputBox(
      prompt: 'Program',
      value: 'initial',
      password: true,
    );
    final box = inputs.current! as ExtensionInputBox;
    expect(box.prompt, 'Program');
    expect(box.password, isTrue);
    box.value = 'answer';
    box.accept();
    expect(await text, 'answer');
    expect(inputs.current, isNull);
    final choice = host.pick<int>([
      const DebugPickItem('One', 1),
      const DebugPickItem(
        'Two',
        2,
        description: 'second',
        separatorBefore: 'Group',
      ),
    ], placeholder: 'Select');
    final pick = inputs.current! as ExtensionQuickPick;
    expect(pick.items, hasLength(3));
    expect(pick.items[1], isA<ExtensionQuickPickSeparator>());
    pick.activeItems = [pick.items.last as ExtensionQuickPickItem];
    pick.accept();
    expect(await choice, 2);
    final cancel = host.showInputBox();
    inputs.hideCurrent();
    expect(await cancel, isNull);
    final superseded = host.pick<int>([const DebugPickItem('One', 1)]);
    final last = host.showInputBox();
    expect(await superseded, isNull);
    host.dispose();
    expect(await last, isNull);
    expect(await host.showInputBox(), isNull);
    expect(inputs.current, isNull);
  });

  test(
    'save failure cancels and missing task/terminal backends reject explicitly',
    () async {
      await workspace.open(program);
      workspace.edit(program, 'saved by debug');
      await host.saveAll();
      expect(disk.contents[program], 'saved by debug');
      workspace.edit(program, 'unsaved');
      disk.contents[program] = 'external change';
      await expectLater(host.saveAll(), throwsA(isA<DebugCancelledError>()));
      expect(await host.runTask(null, null), TaskRunResult.success);
      await expectLater(host.runTask(null, 'build'), throwsUnsupportedError);
      expect(() => host.runInTerminal({}, 'session'), throwsUnsupportedError);
      host.taskRunner = (root, task, checkErrors) async =>
          TaskRunResult.failure;
      expect(await host.runTask(null, 'build'), TaskRunResult.failure);
      host.terminalRunner = (args, session) async => 4242;
      expect(await host.runInTerminal({}, 'session'), 4242);
      expect(await host.confirm('Continue?'), isFalse);
      dialogs.answers.add((button: 0, checked: false));
      expect(await host.confirm('Continue?'), isTrue);
    },
  );

  test(
    'debug source reloads through DAP and reveals only its mounted view',
    () async {
      final adapter = _SourceAdapter();
      final fixture = await createFakeDebugService(
        factory: FakeAdapterFactory((_) => adapter),
      );
      addTearDown(fixture.service.dispose);
      expect(
        await fixture.service.startDebugging(null, {
          'type': 'fake',
          'request': 'launch',
          'name': 'Source',
          'program': fakeProgramPath,
        }),
        isTrue,
      );
      await until(() => fixture.service.model.getSessions().isNotEmpty);
      final session = fixture.service.model.getSessions().single;
      final source = VsUri(
        'debug',
        path: '/source.js',
        query: 'session=${session.getId()}&ref=1',
      );
      adapter.content = 'one\ntwo\nthree\n';
      await workspace.open(program);
      var wrongReveal = false;
      show(
        workspace.active!,
        reveal: (_, _, {center = false}) => wrongReveal = true,
      );
      await host.openDebugSource(
        session,
        source,
        selection: const DebugRange(2, 1, 2, 4),
        preserveFocus: false,
      );
      expect(wrongReveal, isFalse);
      final doc = workspace.active!;
      expect(doc.readOnly, isTrue);
      expect(doc.text, 'one\ntwo\nthree\n');
      final reveals = <(int, int)>[];
      var focused = false;
      show(
        doc,
        focus: () => focused = true,
        reveal: (start, end, {center = false}) => reveals.add((start, end)),
      );
      expect(reveals, [(4, 7)]);
      expect(focused, isTrue);
      adapter.content = 'reloaded';
      await workspace.reloadRevisions();
      expect(doc.text, 'reloaded');
      await fixture.service.stopSession(null);
      await until(() => fixture.service.model.getSessions().isEmpty);
    },
  );

  test(
    'manifest mapping retains debugger/breakpoint contributions and activation',
    () {
      final extensions = debuggerExtensions([
        {
          'identifier': {'value': 'acme.debug'},
          'isBuiltin': true,
          'activationEvents': ['onDebug'],
          'contributes': {
            'debuggers': [
              {'type': 'node', 'label': 'Node.js'},
            ],
            'breakpoints': [
              {'language': 'javascript'},
            ],
          },
        },
        {'name': 'empty'},
      ]);
      expect(extensions, hasLength(1));
      expect(extensions.single.id, 'acme.debug');
      expect(extensions.single.isBuiltin, isTrue);
      expect(extensions.single.debuggers.single['type'], 'node');
      expect(extensions.single.breakpoints.single['language'], 'javascript');
      expect(extensions.single.activationEvents, ['onDebug']);
    },
  );

  test('launch files distinguish missing resources from IO errors', () async {
    final provider = MemFileSystemProvider();
    final files = FileService()..registerProvider('memfs', provider);
    addTearDown(files.dispose);
    addTearDown(provider.dispose);
    final launches = WorkspaceLaunchFiles(files);
    final uri = VsUri('memfs', path: '/project/.vscode/launch.json');
    expect(await launches.read(uri), isNull);
    await launches.write(uri, '{"version":"0.2.0"}');
    expect(await launches.read(uri), '{"version":"0.2.0"}');
    await expectLater(
      launches.read(VsUri('memfs', path: '/project')),
      throwsA(isA<FileOperationException>()),
    );
  });

  test('debug state persists independently and removes deleted keys', () async {
    final dir = await Directory.systemTemp.createTemp('workspace-debug-state-');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'debug.json');
    final first = JsonStateStore(path);
    await first.load();
    final storage = WorkspaceDebugStorage(first);
    storage.store(DebugStorage.watchExpressionsKey, '[{"name":"count"}]');
    storage.store('removed', 'old');
    storage.remove('removed');
    await first.dispose();
    final next = JsonStateStore(path);
    await next.load();
    addTearDown(next.dispose);
    expect(
      WorkspaceDebugStorage(next).get(DebugStorage.watchExpressionsKey),
      '[{"name":"count"}]',
    );
    expect(next.get('removed'), isNull);
  });
}
