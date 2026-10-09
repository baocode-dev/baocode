// The command registry: the extension's commands, the built-in ones and
// BaoCode's, and how one runs (activating `onCommand:` first).


import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/builtin_commands.dart';
import 'package:baocode/extensions/commands/command_contributions.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/commands/workbench_builtin_commands.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/contextkey/js_values.dart';
import 'package:baocode/extensions/main_thread/main_thread_commands.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';

Map<String, Object?> _extension(String id, {List<Object?>? commands}) => {
  'identifier': {'value': id},
  'name': id.split('.').last,
  'displayName': id,
  'extensionLocation': VsUri.file('/ext/$id').toJson(),
  'contributes': {
    'commands': commands ?? const [],
  },
};

final class _Activation implements CommandActivation {
  final events = <String>[];

  /// `*` takes as long as starting the extension host does.
  Duration starDelay = Duration.zero;

  @override
  Future<void> activateByEvent(String activationEvent) async {
    events.add(activationEvent);
    if (activationEvent == '*') await Future<void>.delayed(starDelay);
  }

  @override
  bool activationEventIsDone(String activationEvent) =>
      events.contains(activationEvent);

  @override
  bool extensionHostIsReady = true;
}

void main() {
  test('runs an extension command through the executor', () async {
    final registry = ExtensionCommandRegistry();
    final calls = <String>[];
    registry.registerExtensionCommand('ext.one', (id, args) async {
      calls.add('$id ${jsToString(args.isEmpty ? null : args.first)}');
      return 'done';
    });
    expect(registry.isExtensionCommand('ext.one'), isTrue);
    expect(await registry.executeCommand('ext.one', ['x']), 'done');
    expect(calls, ['ext.one x']);
  });

  test('activates onCommand before running, once', () async {
    final activation = _Activation();
    final registry = ExtensionCommandRegistry(activation: activation);
    registry.registerExtensionCommand('ext.a', (id, args) async => 1);
    await registry.executeCommand('ext.a');
    await registry.executeCommand('ext.a');
    expect(activation.events, ['onCommand:ext.a']);
  });

  test('a command registered after the call still runs (registration race)',
      () async {
    final activation = _Activation()
      ..extensionHostIsReady = false
      ..starDelay = const Duration(milliseconds: 20);
    final registry = ExtensionCommandRegistry(activation: activation);
    // Nothing registered: the call waits for `*` or the registration.
    final result = registry.executeCommand('ext.late');
    await Future<void>.delayed(Duration.zero);
    registry.registerExtensionCommand('ext.late', (id, args) async => 'late');
    expect(await result, 'late');
    expect(activation.events, ['onCommand:ext.late', '*']);
  });

  test('a BaoCode command runs through its IdeCommand', () async {
    final ran = <Object?>[];
    final registry = ExtensionCommandRegistry(
      appCommands: () => {
        'workbench.action.files.save': IdeCommand(
          id: 'workbench.action.files.save',
          label: 'Save',
          run: () => ran.add(null),
          runWithArgs: ran.add,
        ),
      },
    );
    await registry.executeCommand('workbench.action.files.save', ['a']);
    expect(ran, ['a']);
    expect(registry.hasCommand('workbench.action.files.save'), isTrue);
  });

  test('a built-in handler wins over a disabled app command', () async {
    final registry = ExtensionCommandRegistry(
      appCommands: () => {
        'type': IdeCommand(
          id: 'type',
          label: 'Type',
          run: () {},
          enabled: false,
        ),
      },
    );
    final typed = <String>[];
    registry.builtins.register('type', (args) {
      typed.add('${(args.first as Map)['text']}');
      return null;
    });
    await registry.executeCommand('type', [
      {'text': 'a'},
    ]);
    expect(typed, ['a']);
  });

  test('an unknown command rejects', () async {
    final registry = ExtensionCommandRegistry();
    await expectLater(
      registry.executeCommand('nope'),
      throwsA(isA<CommandError>()),
    );
  });

  test('contributes.commands: titles, categories, icons, enablement', () {
    final registry = ExtensionCommandRegistry();
    registry.setExtensions([
      _extension(
        'pub.ext',
        commands: [
          {
            'command': 'ext.hello',
            'title': 'Hello',
            'category': 'Ext',
            'icon': r'$(smiley)',
            'enablement': 'editorTextFocus',
          },
          {
            'command': 'ext.other',
            'title': {'value': 'Otro', 'original': 'Other'},
            'icon': {'light': 'light.svg', 'dark': 'dark.svg'},
          },
          {'command': 'ext.broken'},
        ],
      ),
    ]);
    final hello = registry.contribution('ext.hello')!;
    expect(hello.title, 'Hello');
    expect(hello.category, 'Ext');
    expect(hello.paletteTitle, 'Ext: Hello');
    expect((hello.icon! as ThemeIconRef).id, 'smiley');
    expect(hello.enablement!.serialize(), 'editorTextFocus');
    final other = registry.contribution('ext.other')!;
    expect(other.title, 'Otro');
    expect((other.icon! as ImageIcon).dark.toString(), 'file:///ext/pub.ext/dark.svg');
    expect(registry.contribution('ext.broken'), isNull);
    expect(registry.contributions.messages, hasLength(1));
  });

  group('MainThreadCommands', () {
    MainThreadCommands actor(
      ExtensionCommandRegistry registry,
      ScriptedRpc rpc, {
      CommandActivation? activation,
    }) => MainThreadCommands(
      registry,
      ExtHostCommandsProxy(rpc.protocol),
      activation: activation,
    );

    test(r'$registerCommand / $unregisterCommand / $getCommands', () async {
      final rpc = ScriptedRpc();
      final registry = ExtensionCommandRegistry(
        appCommands: () => {
          'workbench.action.files.save': IdeCommand(
            id: 'workbench.action.files.save',
            label: 'Save',
            run: () {},
          ),
        },
      );
      final target = actor(registry, rpc);
      target.$registerCommand('ext.one');
      expect(registry.commandIds, contains('ext.one'));
      rpc.replies[r'ExtHostCommands.$executeContributedCommand'] = 're';
      expect(
        await target.$executeCommand('ext.one', const ['a'], false),
        're',
      );
      expect(rpc.callsTo(r'ExtHostCommands.$executeContributedCommand'), [
        ['ext.one', 'a'],
      ]);
      expect(await target.$getCommands(), contains('ext.one'));
      expect(await target.$getCommands(), contains('workbench.action.files.save'));
      target.$unregisterCommand('ext.one');
      expect(registry.isExtensionCommand('ext.one'), isFalse);
    });

    test(r'$executeCommand revives URIs and sends the retry error', () async {
      final rpc = ScriptedRpc();
      final registry = ExtensionCommandRegistry();
      final activation = _Activation();
      final target = actor(registry, rpc, activation: activation);
      final seen = <Object?>[];
      registry.builtins.register('builtin.open', (args) {
        seen.addAll(args);
        return null;
      });
      await target.$executeCommand('builtin.open', [
        VsUri.file('/tmp/a.txt').toJson(),
      ], false);
      expect(seen.single, isA<VsUri>());
      expect((seen.single! as VsUri).fsPath(), '/tmp/a.txt');
      // `retry` with arguments and an unknown command: activates it, and
      // the extension host reruns the command without retry.
      await expectLater(
        target.$executeCommand('ext.late', const ['a'], true),
        throwsA(
          isA<RpcRemoteError>().having(
            (e) => e.message,
            'message',
            r'$executeCommand:retry',
          ),
        ),
      );
      expect(activation.events, ['onCommand:ext.late']);
      // Without arguments it runs (and fails: nothing has it).
      await expectLater(
        target.$executeCommand('ext.late', const [], true),
        throwsA(isA<RpcRemoteError>()),
      );
    });

    test(r'$executeCommand runs a contributed command', () async {
      final rpc = ScriptedRpc();
      final registry = ExtensionCommandRegistry();
      final target = actor(registry, rpc);
      rpc.replies[r'ExtHostCommands.$executeContributedCommand'] = 'ok';
      target.$registerCommand('ext.one');
      expect(
        await target.$executeCommand('ext.one', const [1], false),
        'ok',
      );
      // A failing built-in rejects with the message as an Error.
      target.$registerCommand('ext.boom');
      rpc.errors[r'ExtHostCommands.$executeContributedCommand'] = 'boom!';
      await expectLater(
        target.$executeCommand('ext.boom', const [1], false),
        throwsA(
          isA<RpcRemoteError>().having((e) => e.message, 'message', 'boom!'),
        ),
      );
    });
  });

  group('built-in commands', () {
    test('setContext stringifies URIs', () async {
      final contextKeys = ContextKeyService();
      final builtins = BuiltinCommands();
      final stop = registerWorkbenchBuiltinCommands(
        builtins,
        contextKeys: contextKeys,
      );
      await builtins.lookup('_setContext')!([
        'myKey',
        VsUri.file('/tmp/a b.txt').toJson(),
      ]);
      expect(contextKeys.getContextKeyValue('myKey'), 'file:///tmp/a%20b.txt');
      await builtins.lookup('setContext')!(['other', 3]);
      expect(contextKeys.getContextKeyValue('other'), 3);
      stop();
      expect(builtins.has('_setContext'), isFalse);
    });

    test('getContextKeyInfo lists the declared keys', () async {
      final key = RawContextKey<bool>('my.flag', false, 'A flag');
      final builtins = BuiltinCommands();
      registerWorkbenchBuiltinCommands(
        builtins,
        contextKeys: ContextKeyService(),
      );
      final infos = await builtins.lookup('getContextKeyInfo')!(const [])
          as List;
      expect(
        infos,
        contains(
          containsPair('key', 'my.flag'),
        ),
      );
      expect(key.key, 'my.flag');
    });

    test('calls the workbench ports', () async {
      final contextKeys = ContextKeyService();
      final builtins = BuiltinCommands();
      final opened = <Object?>[];
      final views = <String>[];
      final stop = registerWorkbenchBuiltinCommands(
        builtins,
        contextKeys: contextKeys,
        workbench: _Workbench(opened, views),
      );
      await builtins.lookup('vscode.open')!([
        VsUri.file('/tmp/a.txt').toJson(),
      ]);
      expect(opened, ['open file:///tmp/a.txt']);
      await builtins.lookup('vscode.open')!(['https://example.com/x']);
      expect(opened.last, 'external https://example.com/x');
      // Another scheme opens in an editor (`EditorOpener`); the app's own
      // goes to its URL handler.
      await builtins.lookup('vscode.open')!([
        VsUri('git', path: '/tmp/a.txt'),
      ]);
      expect(opened.last, 'open git:/tmp/a.txt');
      await builtins.lookup('vscode.open')!(['baocode://acme.ext/callback']);
      expect(opened.last, 'external baocode://acme.ext/callback');
      await builtins.lookup('vscode.diff')!([
        VsUri.file('/tmp/a.txt').toJson(),
        VsUri.file('/tmp/b.txt').toJson(),
        'a ↔ b',
      ]);
      expect(opened.last, 'diff file:///tmp/a.txt file:///tmp/b.txt a ↔ b');
      await builtins.lookup('workbench.view.extension.myview')!([]);
      expect(views, ['workbench.view.extension.myview']);
      await builtins.lookup('workbench.view.scm')!([]);
      expect(views.last, 'workbench.view.scm');
      stop();
    });

    test('runs the editor ports with the extension host\'s arguments', () {
      final builtins = BuiltinCommands();
      final typed = <String>[];
      final moves = <Map<String, Object?>>[];
      registerWorkbenchBuiltinCommands(
        builtins,
        contextKeys: ContextKeyService(),
        editor: _Editor(typed, moves),
      );
      builtins.lookup('type')!([
        {'text': 'hi'},
      ]);
      builtins.lookup('default:replacePreviousChar')!([
        {'text': 'x', 'replaceCharCnt': 2},
      ]);
      builtins.lookup('cursorMove')!([
        {'to': 'wrappedLineEnd', 'by': 'wrappedLine', 'value': 2},
      ]);
      builtins.lookup('revealLine')!([
        {'lineNumber': 12, 'at': 'top'},
      ]);
      expect(typed, ['hi', 'replace x 2', 'reveal 12 top']);
      expect(moves.single['to'], 'wrappedLineEnd');
    });
  });
}

final class _Workbench implements WorkbenchCommandsPort {
  _Workbench(this.opened, this.views);

  final List<Object?> opened;
  final List<String> views;

  @override
  Future<void> openEditor(VsUri r, {int? column, dynamic options, String? label}) async =>
      opened.add('open $r');

  @override
  Future<void> openExternal(String target) async =>
      opened.add('external $target');

  @override
  bool isExternal(VsUri resource) => resource.scheme == 'baocode';

  @override
  Future<void> openDiff(VsUri left, VsUri right, {String? label, String? description, int? column, dynamic options}) async =>
      opened.add('diff $left $right ${label ?? ''}');

  @override
  Future<void> openFolder(VsUri? folder, {bool forceNewWindow = false}) async =>
      opened.add('folder ${folder ?? 'ask'}');

  @override
  Future<void> openSettings({String? query}) async =>
      opened.add('settings $query');

  @override
  Future<void> showViewContainer(String id) async => views.add(id);

  @override
  void focusActiveEditorGroup() => opened.add('focus');

  @override
  Future<void> revealInExplorer(VsUri resource) async =>
      opened.add('reveal $resource');
}

final class _Editor implements EditorCommandsPort {
  _Editor(this.log, this.moves);

  final List<String> log;
  final List<Map<String, Object?>> moves;

  @override
  void type(String text) => log.add(text);

  @override
  void replacePreviousChar(String text, int replaceCharCnt) =>
      log.add('replace $text $replaceCharCnt');

  @override
  void compositionType(String text, {int replacePrevCharCnt = 0, int replaceNextCharCnt = 0, int positionDelta = 0}) =>
      log.add('compose $text');

  @override
  void cursorMove(Map<String, Object?> args) => moves.add(args);

  @override
  void revealLine(int lineNumber, String at) => log.add('reveal $lineNumber $at');

  @override
  Future<void> showReferences(VsUri uri, dynamic position, dynamic locations) async =>
      log.add('references $uri');

  @override
  Future<void> goToLocations(VsUri uri, dynamic position, dynamic locations, {String? multiple, String? noResultsMessage}) async =>
      log.add('goTo $uri $multiple');

  @override
  void triggerSuggest() => log.add('suggest');

  @override
  void triggerParameterHints() => log.add('parameterHints');
}
