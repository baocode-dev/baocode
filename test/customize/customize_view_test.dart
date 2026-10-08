import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/customize/customizations.dart';
import 'package:baocode/customize/customize_view.dart';
import 'package:baocode/ide/ide_code_editor.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/workspace.dart';

/// Skills kept in memory, by file.
class _MemoryStore implements CustomizationStore {
  final Map<String, String> files = {
    '/c/skills/pdf/SKILL.md':
        '---\nname: pdf\ndescription: Reads PDF files\n---\n\nBody\n',
  };

  @override
  String? get configDir => '/c';

  @override
  String? get homeDir => null;

  @override
  bool get supported => true;

  @override
  Future<String> config() async => '/c';

  @override
  Future<List<Customization>> list(
    CustomizationKind kind, {
    String? project,
  }) async => [
    if (kind == CustomizationKind.skills)
      for (final MapEntry(key: path, value: text) in files.entries)
        Customization(
          kind: kind,
          scope: path.startsWith('/c/')
              ? CustomizationScope.user
              : CustomizationScope.project,
          name: parseFrontMatter(text)['name'] ?? path,
          description: describeMarkdown(text),
          path: path,
          removePath: path.substring(0, path.lastIndexOf('/')),
        ),
  ];

  @override
  Future<String> read(String path) async => files[path]!;

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<String?> configFile(
    CustomizationKind kind,
    CustomizationScope scope, {
    String? project,
  }) async =>
      kind == CustomizationKind.hooks && scope == CustomizationScope.user
      ? '/c/settings.json'
      : null;

  @override
  Future<void> write(String path, String text) async => files[path] = text;

  @override
  Future<String> create(
    CustomizationKind kind,
    CustomizationScope scope,
    String name, {
    String? project,
  }) async {
    final path = scope == CustomizationScope.user
        ? '/c/skills/$name/SKILL.md'
        : '$project/.claude/skills/$name/SKILL.md';
    files[path] = template(kind, name);
    return path;
  }

  @override
  Future<void> delete(Customization item) async => files.remove(item.path);
}

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

Future<Workspace> _pumpApp(
  WidgetTester tester,
  CustomizationStore store,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KeybindingService.instance = KeybindingService();
  addTearDown(() => KeybindingService.instance = KeybindingService());
  final workspace = Workspace.mock();
  await tester.pumpWidget(
    BaoCodeApp(workspace: workspace, customizations: store),
  );
  await tester.pump();
  return workspace;
}

Finder _inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

Finder _inView(Finder finder) =>
    find.descendant(of: find.byType(CustomizeView), matching: finder);

/// The customization editor's controller: the IDE's editor's.
EditorSurfaceController _editor(WidgetTester tester) => tester
    .widget<EditorSurface>(_inView(find.byType(EditorSurface)))
    .controller;

String _editorText(WidgetTester tester) => _editor(tester).document.text;

void main() {
  testWidgets('Customize lists the skills, in place of the chat', (
    tester,
  ) async {
    final store = _MemoryStore();
    final workspace = await _pumpApp(tester, store);
    await tester.tap(_inSidebar(find.text('Customize')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomizeView), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
    expect(_inView(find.text('pdf')), findsOneWidget);
    expect(_inView(find.text('Reads PDF files')), findsOneWidget);
    for (final chip in ['Plugins', 'MCPs', 'Skills', 'Subagents', 'Rules']) {
      expect(_inView(find.text(chip)), findsOneWidget);
    }

    // Searching keeps the ones that match.
    await tester.enterText(_inView(find.byType(TextField)), 'docx');
    await tester.pump();
    expect(_inView(find.text('Reads PDF files')), findsNothing);
    await tester.enterText(_inView(find.byType(TextField)), 'PDF files');
    await tester.pump();
    expect(_inView(find.text('Reads PDF files')), findsOneWidget);

    // An agent picked in the sidebar shows instead.
    await tester.tap(_inSidebar(find.textContaining('Rate limit per API key')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomizeView), findsNothing);
    expect(workspace.selected.title, 'Rate limit per API key');
  }, variant: _mac);

  testWidgets('Customize has no side panel rail, the agent\'s', (tester) async {
    await _pumpApp(tester, _MemoryStore());
    await tester.pumpAndSettle();
    expect(find.byType(SidePanelRail), findsOneWidget);
    final customize = _inSidebar(find.text('Customize'));
    await tester.tap(customize);
    await tester.pumpAndSettle();
    expect(find.byType(CustomizeView), findsOneWidget);
    expect(find.byType(SidePanelRail), findsNothing);
    await tester.tap(customize);
    await tester.pumpAndSettle();
    expect(find.byType(SidePanelRail), findsOneWidget);

    // Its panel, open, is hidden while Customize shows.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AgentSidePanelView), findsOneWidget);
    await tester.tap(customize);
    await tester.pumpAndSettle();
    expect(find.byType(AgentSidePanelView), findsNothing);
  }, variant: _mac);

  testWidgets('a skill is edited and saved with ⌘S; a new one made', (
    tester,
  ) async {
    final store = _MemoryStore();
    await _pumpApp(tester, store);
    await tester.tap(_inSidebar(find.text('Customize')));
    await tester.pumpAndSettle();

    await tester.tap(_inView(find.text('pdf')));
    await tester.pumpAndSettle();
    // The IDE's editor, the skill's text in it.
    final editor = _inView(find.byType(IdeCodeEditor));
    expect(editor, findsOneWidget);
    expect(_editorText(tester), contains('Body'));
    await tester.tap(_inView(find.byType(EditorSurface)));
    await tester.pump();
    _editor(tester)
      ..selectAll()
      ..replaceSelection(
        '---\nname: pdf\ndescription: Reads and fills PDFs\n---\n',
      );
    await tester.pump();
    expect(_inView(find.text('Unsaved changes')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(store.files['/c/skills/pdf/SKILL.md'], contains('fills PDFs'));
    expect(_inView(find.text('Saved')), findsOneWidget);

    await tester.tap(
      _inView(
        find.byWidgetPredicate(
          (widget) => widget is SidebarIconButton && widget.tooltip == 'Back',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_inView(find.text('Reads and fills PDFs')), findsOneWidget);

    // New, under the user's: named, then open to edit.
    await tester.tap(_inView(find.text('New')).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'bad name');
    await tester.pump();
    expect(
      find.text('Letters, digits, - and _ only (up to 64)'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'pdf');
    await tester.pump();
    expect(find.text('One by that name already exists'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'release-notes');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(store.files, contains('/c/skills/release-notes/SKILL.md'));
    expect(_editorText(tester), contains('name: release-notes'));
  }, variant: _mac);

  testWidgets('MCPs and hooks say where they come from; a settings file '
      'not there yet is made when saved', (tester) async {
    final store = _MemoryStore();
    await _pumpApp(tester, store);
    await tester.tap(_inSidebar(find.text('Customize')));
    await tester.pumpAndSettle();

    await tester.tap(_inView(find.text('MCPs')));
    await tester.pumpAndSettle();
    expect(_inView(find.textContaining('claude mcp add')), findsWidgets);

    await tester.tap(_inView(find.text('Plugins')));
    await tester.pumpAndSettle();
    expect(_inView(find.textContaining('/plugin')), findsOneWidget);

    await tester.tap(_inView(find.text('Hooks')));
    await tester.pumpAndSettle();
    expect(_inView(find.textContaining('"hooks"')), findsWidgets);
    await tester.tap(_inView(find.text('Edit settings.json')).first);
    await tester.pumpAndSettle();
    expect(_editorText(tester), CustomizationKind.hooks.configTemplate);
    expect(store.files, isNot(contains('/c/settings.json')));
    await tester.tap(_inView(find.text('Save')));
    await tester.pumpAndSettle();
    expect(
      store.files['/c/settings.json'],
      CustomizationKind.hooks.configTemplate,
    );
  }, variant: _mac);
}
