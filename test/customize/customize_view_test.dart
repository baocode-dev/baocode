import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_markdown/bao_markdown.dart' show MarkdownEditor;

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/customize/customizations.dart';
import 'package:baocode/customize/customize_view.dart';
import 'package:baocode/customize/mcp_probe.dart';
import 'package:baocode/settings/pages/customize_page.dart';
import 'package:baocode/ide/ide_code_editor.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/ide/ide_switch.dart';
import 'package:baocode/kernel/extension_switches.dart';
import 'package:baocode/ide/markdown/markdown_preview.dart';
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
  bool get isLocal => true;

  @override
  Future<String> config() async => '/c';

  /// The MCP servers listed.
  List<Customization> servers = const [];

  @override
  Future<List<Customization>> list(
    CustomizationKind kind, {
    String? project,
  }) async => [
    if (kind == CustomizationKind.mcps) ...servers,
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
  Future<String?> commandFile(String name, {String? project}) async => null;

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

/// A markdown customization's preview's editor (bao_markdown's).
MarkdownEditor _markdown(WidgetTester tester) =>
    tester.widget<MarkdownEditor>(_inView(find.byType(MarkdownEditor)));

void main() {
  testWidgets('Customize lists the skills, in place of the chat', (
    tester,
  ) async {
    final store = _MemoryStore();
    final workspace = await _pumpApp(tester, store);
    await tester.tap(_inSidebar(find.text('Skills')));
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
    final customize = _inSidebar(find.text('Skills'));
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
    await tester.tap(_inSidebar(find.text('Skills')));
    await tester.pumpAndSettle();

    await tester.tap(_inView(find.text('pdf')));
    await tester.pumpAndSettle();
    // Markdown, so the IDE's markdown editor, the skill's text in it.
    final preview = _inView(find.byType(IdeMarkdownPreview));
    expect(preview, findsOneWidget);
    expect(_inView(find.byType(IdeCodeEditor)), findsNothing);
    // Its actions flush right, not halfway (#149); the preview on the
    // page's edge, its scroll bar there; Save only once there is something
    // to save.
    final edge = tester.getTopRight(find.byType(CustomizeView)).dx;
    expect(tester.getTopRight(preview).dx, edge);
    expect(
      tester.getTopRight(_inView(find.byIcon(Icons.more_horiz_rounded))).dx,
      moreOrLessEquals(edge - 24, epsilon: 8),
    );
    expect(_inView(find.text('Save')), findsNothing);
    expect(_markdown(tester).controller.text, contains('Body'));
    // Its front matter a form: a value edited in its field, written back
    // as Enter ends it.
    final fields = _inView(find.byType(IdeInputBox));
    expect(fields, findsNWidgets(2));
    await tester.enterText(
      find.descendant(of: fields.at(1), matching: find.byType(TextField)),
      'Reads PDFs: all of them\n',
    );
    await tester.pump();
    expect(
      _markdown(tester).controller.text,
      contains('description: "Reads PDFs: all of them"\n'),
    );
    expect(_inView(find.text('Unsaved changes')), findsOneWidget);
    // Edited there: unsaved, then saved with ⌘S.
    await tester.tap(_inView(find.byType(MarkdownEditor)));
    await tester.pump();
    final markdown = _markdown(tester).controller;
    markdown.replace(markdown.length, markdown.length, '\nMore');
    await tester.pump();
    expect(_inView(find.text('Unsaved changes')), findsOneWidget);
    expect(_inView(find.text('Save')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(store.files['/c/skills/pdf/SKILL.md'], endsWith('\nMore'));

    // Its source: the IDE's editor, the same text.
    await tester.tap(_inView(find.text('Markdown')));
    await tester.pumpAndSettle();
    expect(_inView(find.byType(IdeMarkdownPreview)), findsNothing);
    expect(_inView(find.byType(IdeCodeEditor)), findsOneWidget);
    expect(_editorText(tester), endsWith('\nMore'));
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
      find.text(
        'Starts with a letter or digit; no spaces or / \\ : * ? " < > | '
        '(up to 64)',
      ),
      findsOneWidget,
    );
    // Not the official naming: let through, with a note.
    await tester.enterText(find.byType(TextField).last, '发布说明');
    await tester.pump();
    expect(
      find.text(
        'Officially lowercase, digits and - only; claude.ai may reject it',
      ),
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
    expect(_markdown(tester).controller.text, contains('name: release-notes'));
  }, variant: _mac);

  testWidgets('MCPs and hooks say where they come from; a settings file '
      'not there yet is made when saved', (tester) async {
    final store = _MemoryStore();
    await _pumpApp(tester, store);
    await tester.tap(_inSidebar(find.text('Skills')));
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

  testWidgets('MCP servers show whether they answer; one that failed says '
      'why, its log open, and is tested again', (tester) async {
    Customization server(String name, {bool? enabled}) => Customization(
      kind: CustomizationKind.mcps,
      scope: CustomizationScope.user,
      name: name,
      description: 'npx $name',
      path: '/home/.claude.json',
      editable: false,
      detail: '{}',
      enabled: enabled,
      server: {
        'command': 'npx',
        'args': [name],
      },
    );
    final store = _MemoryStore()
      ..servers = [
        server('ok'),
        server('broken'),
        server('off', enabled: false),
      ];
    final asked = <String>[];
    CustomizeView.mcpProber = (config, {cwd}) async {
      final name = (config['args'] as List).single as String;
      asked.add(name);
      await Future<void>.delayed(const Duration(seconds: 1));
      return name == 'ok'
          ? const McpProbeResult(
              McpProbeStatus.connected,
              server: 'ok-server 1.0',
            )
          : const McpProbeResult(
              McpProbeStatus.failed,
              exitCode: 1,
              log: 'npm warn\nError: Cannot find module x',
            );
    };
    await _pumpApp(tester, store);
    await tester.tap(_inSidebar(find.text('Skills')));
    await tester.pumpAndSettle();
    await tester.tap(_inView(find.text('MCPs')));
    await tester.pump();
    await tester.pump();

    // Asked at once, those turned off not at all.
    expect(asked, ['ok', 'broken']);
    expect(_inView(find.text('Connecting…')), findsNWidgets(2));
    expect(_inView(find.text('Disabled')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_inView(find.text('Connected')), findsOneWidget);
    expect(_inView(find.text('Failed')), findsOneWidget);
    expect(
      _inView(find.text('Exited with code 1 · Error: Cannot find module x')),
      findsOneWidget,
    );
    // Not asked again as the list comes back.
    await tester.tap(_inView(find.text('Skills')));
    await tester.pumpAndSettle();
    await tester.tap(_inView(find.text('MCPs')));
    await tester.pumpAndSettle();
    expect(asked, hasLength(2));

    // Its log, in full, over its entry; tested again from there.
    await tester.tap(_inView(find.text('broken')));
    await tester.pumpAndSettle();
    expect(
      _inView(find.text('npm warn\nError: Cannot find module x')),
      findsOneWidget,
    );
    // Its button flush right in the panel, not halfway (#149).
    expect(
      tester.getTopRight(_inView(find.text('Test connection'))).dx,
      moreOrLessEquals(
        tester.getTopRight(_inView(find.byType(EditorSurface))).dx,
        epsilon: 32,
      ),
    );
    await tester.tap(_inView(find.text('Test connection')));
    await tester.pump();
    expect(asked, ['ok', 'broken', 'broken']);
    expect(_inView(find.text('Connecting…')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_inView(find.text('Failed')), findsOneWidget);
  }, variant: _mac);

  testWidgets('switches: a skill, an MCP server and one of its tools, kept '
      'as they are turned', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore()
      ..servers = [
        const Customization(
          kind: CustomizationKind.mcps,
          scope: CustomizationScope.user,
          name: 'git',
          path: '/home/.claude.json',
          editable: false,
          server: {'command': 'git-mcp'},
        ),
      ];
    CustomizeView.mcpProber = (config, {cwd}) async => const McpProbeResult(
      McpProbeStatus.connected,
      tools: [
        (name: 'status', description: 'Shows the status'),
        (name: 'push', description: ''),
      ],
    );
    var kept = ExtensionSwitches.none;
    ExtensionSwitches.current = () => kept;
    ExtensionSwitches.save = (switches) async => kept = switches;
    addTearDown(() {
      ExtensionSwitches.current = () => ExtensionSwitches.none;
      ExtensionSwitches.save = null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CustomizeSettingsPage(customizations: store)),
      ),
    );
    await tester.pumpAndSettle();
    Finder switchOf(String label) => find.byWidgetPredicate(
      (widget) => widget is IdeSwitch && widget.semanticLabel == label,
    );
    bool on(String label) => tester.widget<IdeSwitch>(switchOf(label)).value;

    // All on to start.
    expect(on('pdf'), isTrue);
    await tester.tap(switchOf('pdf'));
    await tester.pumpAndSettle();
    expect(kept.disabledSkills, {'pdf'});
    expect(on('pdf'), isFalse);

    // A server's tools, as asking it found them, each with a switch.
    await tester.tap(find.text('MCPs'));
    await tester.pumpAndSettle();
    expect(find.text('status'), findsNothing);
    await tester.tap(find.text('2 tools'));
    await tester.pumpAndSettle();
    expect(find.text('Shows the status'), findsOneWidget);
    await tester.tap(switchOf('push'));
    await tester.pumpAndSettle();
    expect(kept.disabledTools, {
      'git': {'push'},
    });
    // The server off: its tools shown off, not to be turned.
    await tester.tap(switchOf('git'));
    await tester.pumpAndSettle();
    expect(kept.disabledServers, {'git'});
    expect(on('status'), isFalse);
    expect(tester.widget<IdeSwitch>(switchOf('status')).enabled, isFalse);
  });

  testWidgets('Settings → Customize edits a skill in place, without a title '
      'bar', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CustomizeSettingsPage(customizations: store)),
      ),
    );
    await tester.pumpAndSettle();
    // The same view as Customize beside the chat, its own title bar off.
    expect(find.byType(CustomizeView), findsOneWidget);
    expect(find.text('Close Customize'), findsNothing);
    expect(find.text('pdf'), findsOneWidget);

    await tester.tap(find.text('pdf'));
    await tester.pumpAndSettle();
    expect(_markdown(tester).controller.text, contains('Body'));
  });
}
