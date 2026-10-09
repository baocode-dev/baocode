import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/commands/workbench_builtin_commands.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/editors/document_registry.dart';
import 'package:baocode/extensions/editors/documents_and_editors_service.dart';
import 'package:baocode/extensions/files/file_service.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/views/views_service.dart';
import 'package:baocode/extensions/workbench/ide_builtin_commands.dart';
import 'package:baocode/extensions/workbench/ide_documents.dart';
import 'package:baocode/extensions/workbench/ide_text_editors.dart';
import 'package:baocode/ide/ide_editor_features.dart';
import 'package:baocode/ide/ide_editor_views.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ide/workbench/fake_files.dart';

final class _Management implements ExtensionManagementBackend {
  final calls = <String>[];

  @override
  Future<InstalledExtension> installFromGallery(
    String id, {
    String? version,
    bool preRelease = false,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    calls.add('gallery $id ${version ?? '-'} $preRelease');
    throw StateError('not installed');
  }

  @override
  Future<void> uninstall(String id) async => calls.add('uninstall $id');

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const a = '/p/a.ts';
  late IdeWorkspace workspace;
  late IdeTextEditors editors;
  late DocumentsAndEditorsService documentsAndEditors;
  late IdeDocumentsPort documents;
  late ExtensionCommandRegistry commands;
  late ExtensionViewsService views;
  late IdeBuiltinCommands builtins;
  late _Management management;
  late ContextKeyService contextKeys;
  late void Function() unregister;
  final opened = <String>[];

  setUp(() {
    opened.clear();
    workspace = IdeWorkspace(
      '/p',
      files: TreeFiles({a: 'one\n  two\nthree\n'}),
      extensionLanguageId: (_) => 'typescript',
    );
    editors = IdeTextEditors(workspace);
    documentsAndEditors = DocumentsAndEditorsService(
      documents: ExtensionDocumentRegistry(),
      editors: editors,
    );
    documents = IdeDocumentsPort(
      workspace: workspace,
      state: documentsAndEditors.state,
      languageIdFor: (_) => 'typescript',
    );
    commands = ExtensionCommandRegistry();
    views = ExtensionViewsService();
    management = _Management();
    contextKeys = ContextKeyService();
    builtins = IdeBuiltinCommands(
      workspace: workspace,
      editors: editors,
      documents: documents,
      files: FileService(),
      views: views,
      commands: commands,
      management: management,
      openUri: (target) async => opened.add(target),
    );
    unregister = registerWorkbenchBuiltinCommands(
      commands.builtins,
      contextKeys: contextKeys,
      workbench: builtins,
      editor: builtins,
      extensions: builtins,
    );
  });

  tearDown(() {
    unregister();
    builtins.dispose();
    documents.dispose();
    documentsAndEditors.dispose();
    editors.dispose();
    views.dispose();
    commands.dispose();
    contextKeys.dispose();
    workspace.dispose();
  });

  /// [doc] on screen in a widgetless editor, focused.
  IdeEditorView show(IdeDocument doc) {
    final controller = EditorSurfaceController(document: doc.model);
    final features = IdeEditorFeatures(
      controller: controller,
      types: workspace.editorViews.decorationTypes,
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
      hasFocus: () => true,
      focus: () {},
      reveal: (_, _, {center = false}) {},
    );
    workspace.editorViews.show(view);
    return view;
  }

  test(
    'typing goes through an extension\'s `type`; default:type types',
    () async {
      await workspace.open(a);
      final view = show(workspace.active!);
      view.controller.setSelections([const TextSelection.collapsed(offset: 0)]);

      // No extension overrides it: the editor types.
      view.controller.type('x');
      expect(view.document.text, startsWith('xone'));

      final typed = <Object?>[];
      final stop = commands.registerExtensionCommand('type', (id, args) async {
        typed.add(args.single);
        // As VSCodeVim does in Insert mode.
        await commands.executeCommand('default:type', args);
        return null;
      });
      view.controller.type('y');
      await pumpEventQueue();
      expect(typed, [
        {'text': 'y'},
      ]);
      expect(view.document.text, startsWith('xyone'));

      // `replacePreviousChar` as an input method sends it.
      await commands.executeCommand('default:replacePreviousChar', [
        {'text': 'Z', 'replaceCharCnt': 2},
      ]);
      expect(view.document.text, startsWith('Zone'));

      stop();
      view.controller.type('w');
      expect(typed, hasLength(1));
      expect(view.document.text, startsWith('Zwone'));
    },
  );

  test('cursorMove and revealLine move the focused editor', () async {
    await workspace.open(a);
    final view = show(workspace.active!);
    view.controller.setSelections([const TextSelection.collapsed(offset: 0)]);

    await commands.executeCommand('cursorMove', [
      {'to': 'down', 'by': 'line', 'value': 1},
    ]);
    await commands.executeCommand('cursorMove', [
      {'to': 'wrappedLineFirstNonWhitespaceCharacter'},
    ]);
    // Line 2's `two`, after its indentation.
    expect(view.controller.selections.single.extentOffset, 6);
    await commands.executeCommand('cursorMove', [
      {'to': 'wrappedLineEnd', 'select': true},
    ]);
    final s = view.controller.selections.single;
    expect(view.document.text.substring(s.start, s.end), 'two');
  });

  test('_workbench.open: a file at a selection; a virtual document', () async {
    await commands.executeCommand('_workbench.open', [
      VsUri.file(a),
      [
        null,
        {
          'preserveFocus': true,
          'selection': {
            'startLineNumber': 2,
            'startColumn': 3,
            'endLineNumber': 2,
            'endColumn': 6,
          },
        },
      ],
    ]);
    expect(workspace.active?.path, a);

    documents.register('acme', (uri) async => 'virtual ${uri.path}');
    await commands.executeCommand('vscode.open', [
      VsUri('acme', path: '/notes.txt'),
    ]);
    expect(workspace.active?.text, 'virtual /notes.txt');
    expect(workspace.active?.readRevision, isNotNull);

    await commands.executeCommand('vscode.open', [
      VsUri.parse('https://example.com/a'),
    ]);
    expect(opened, ['https://example.com/a']);
  });

  test('a diff of a virtual document against a file', () async {
    documents.register('git', (uri) async => 'one\ntwo\n');
    await commands.executeCommand('vscode.diff', [
      VsUri('git', path: a, query: 'HEAD'),
      VsUri.file(a),
      'a.ts (Working Tree)',
    ]);
    final active = workspace.active!;
    expect(active.diff, isNotNull);
    expect(active.path, a);
  });

  test('references and locations', () async {
    final shown = <(String, int)>[];
    builtins.onShowReferences = (title, locations) =>
        shown.add((title, locations.length));
    Map<String, Object?> location(int line) => {
      'uri': VsUri.file(a),
      'range': {
        'startLineNumber': line,
        'startColumn': 1,
        'endLineNumber': line,
        'endColumn': 2,
      },
    };
    final position = {'lineNumber': 1, 'column': 1};
    await commands.executeCommand('editor.action.showReferences', [
      VsUri.file(a),
      position,
      [location(1), location(3)],
    ]);
    expect(shown, [('2 references', 2)]);

    // One location: opened.
    await commands.executeCommand('editor.action.goToLocations', [
      VsUri.file(a),
      position,
      [location(3)],
      'peek',
    ]);
    expect(workspace.active?.path, a);
    expect(shown, hasLength(1));

    // None: the message.
    await commands.executeCommand('editor.action.goToLocations', [
      VsUri.file(a),
      position,
      <Object?>[],
      'peek',
      'No definition found',
    ]);
    expect(
      workspace.notifications.notifications.map((n) => n.message),
      contains('No definition found'),
    );
  });

  test('installing and uninstalling for extensions', () async {
    await expectLater(
      commands.executeCommand('workbench.extensions.installExtension', [
        'acme.tool@1.2.0',
        {'installPreReleaseVersion': true},
      ]),
      throwsStateError,
    );
    await commands.executeCommand('workbench.extensions.uninstallExtension', [
      'acme.tool',
    ]);
    expect(management.calls, [
      'gallery acme.tool 1.2.0 true',
      'uninstall acme.tool',
    ]);
  });
}
