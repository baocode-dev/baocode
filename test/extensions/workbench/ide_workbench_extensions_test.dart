// The IDE workbench over a workspace's extensions: the Extensions view and
// an extension's page, the extensions' status bar entries, the OUTPUT tab,
// their commands in the Command Palette, and recommendations for the files
// opened.

import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/debug/ui/debug_toolbar.dart';
import 'package:baocode/debug/ui/debug_view.dart';
import 'package:baocode/debug/ui/run_and_debug_view.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/debug_editor_glue.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../debug/support/fake_debug_adapter.dart';
import '../../ide/workbench/fake_files.dart';
import '../gallery/fixture_http.dart';
import '../ui/fake_backend.dart';

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {
    'security.workspace.trust.startupPrompt': 'never',
  };

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

WorkspaceExtensions _extensions({
  List<InstalledExtension> installed = const [],
}) {
  final gallery = OpenVsxClient(
    http: FixtureHttp(recorded: false),
    targetPlatform: null,
  );
  final extensions = WorkspaceExtensions(
    app: ExtensionsApp(
      userSettings: _Settings(),
      dataDirectory: '/data',
      gallery: gallery,
      loadRuntime: () async => throw StateError('No runtime under test'),
    ),
    root: testRoot,
    management: FakeBackend(installed: installed, galleryClient: gallery),
  );
  addTearDown(extensions.dispose);
  return extensions;
}

InstalledExtension _installed(String id, String displayName) =>
    InstalledExtension(
      manifest: fakeManifest(id, displayName: displayName),
      location: '/extensions/$id',
    );

IdeWorkbenchState _workbench(WidgetTester tester) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

void main() {
  testWidgets('the Extensions view lists the installed extensions, and one '
      'opens its page over the editors', (tester) async {
    final extensions = _extensions(
      installed: [_installed('acme.tools', 'Acme Tools')],
    );
    await pumpWorkbench(
      tester,
      {'a.txt': 'text'},
      open: ['a.txt'],
      extensions: extensions,
    );
    _workbench(tester).commandsById['workbench.view.extensions']!.run();
    await tester.pumpAndSettle();
    expect(find.text('Acme Tools'), findsOneWidget);

    await tester.tap(find.text('Acme Tools'));
    await tester.pumpAndSettle();
    expect(find.text('acme.tools'), findsWidgets);

    await tester.tap(find.byTooltip('Close Extension'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close Extension'), findsNothing);
  });

  testWidgets('a folder without extensions says so in the view', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.txt': 'text'});
    _workbench(tester).commandsById['workbench.view.extensions']!.run();
    await tester.pumpAndSettle();
    expect(
      find.text('Extensions are not available for this folder yet.'),
      findsOneWidget,
    );
  });

  testWidgets('an extension\'s status bar entry shows, and follows its '
      'updates', (tester) async {
    final extensions = _extensions();
    await pumpWorkbench(
      tester,
      {'a.txt': 'text'},
      open: ['a.txt'],
      extensions: extensions,
    );
    extensions.statusBar.setOrUpdateEntry(
      entryId: 'acme.tools.status',
      id: 'acme.tools.status',
      extensionId: 'acme.tools',
      name: 'Acme',
      text: 'Acme ready',
      tooltip: null,
      alignLeft: true,
    );
    await tester.pump();
    expect(find.text('Acme ready'), findsOneWidget);

    extensions.statusBar.unsetEntry('acme.tools.status');
    await tester.pump();
    expect(find.text('Acme ready'), findsNothing);
  });

  testWidgets('OUTPUT is a tab of the panel with extensions', (tester) async {
    final extensions = _extensions();
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    _workbench(tester).commandsById['workbench.action.output.toggleOutput']!
        .run();
    await tester.pumpAndSettle();
    expect(find.text('OUTPUT'), findsOneWidget);
    expect(extensions.output.panelVisible.value, isTrue);

    _workbench(tester).commandsById['workbench.actions.view.problems']!.run();
    await tester.pumpAndSettle();
    expect(extensions.output.panelVisible.value, isFalse);
  });

  testWidgets(
    'debug view, console and commands use the assembled debug service',
    (tester) async {
      final fixture = await createFakeDebugService();
      addTearDown(fixture.service.dispose);
      await pumpWorkbench(
        tester,
        {'a.txt': 'text'},
        open: ['a.txt'],
        debugService: fixture.service,
      );

      _workbench(tester).commandsById['workbench.view.debug']!.run();
      await tester.pumpAndSettle();
      expect(find.byType(DebugView), findsOneWidget);
      expect(find.byType(RunAndDebugView), findsOneWidget);
      expect(find.byType(FloatingDebugToolbar), findsOneWidget);

      _workbench(tester).commandsById['workbench.action.toggleRepl']!.run();
      await tester.pumpAndSettle();
      expect(find.byType(DebugConsolePanel), findsOneWidget);
      expect(find.text('DEBUG CONSOLE'), findsNWidgets(2));

      _workbench(tester).commandsById['workbench.view.debug']!.run();
      await tester.pumpAndSettle();
      expect(find.byType(DebugView), findsOneWidget);
    },
  );

  testWidgets('a click in the glyph margin adds a breakpoint the margin '
      'shows, and another removes it', (tester) async {
    final fixture = await createFakeDebugService();
    addTearDown(fixture.service.dispose);
    await pumpWorkbench(
      tester,
      {'a.js': 'const a = 1;\nconst b = 2;\n'},
      open: ['a.js'],
      debugService: fixture.service,
      nativeEditor: true,
    );
    // The editor knows the file's language once TextMate has it.
    for (var i = 0; i < 20 && find.byType(DebugGlyphMargin).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    final surface = find.byType(EditorSurface);
    final view = tester.state(surface) as EditorSurfaceView;
    final margin = view.glyphMarginRect(2)!;
    final dot = find.text(String.fromCharCode(Codicons.debugBreakpoint.codePoint));
    expect(dot, findsNothing);

    await tester.tapAt(tester.getTopLeft(surface) + margin.center);
    await tester.pumpAndSettle();
    final breakpoints = fixture.service.model.getBreakpoints();
    expect([for (final bp in breakpoints) bp.lineNumber], [2]);
    expect(breakpoints.single.uri.path, endsWith('/a.js'));
    expect(dot, findsOneWidget);
    expect(tester.getCenter(dot).dy, closeTo(tester.getTopLeft(surface).dy + margin.center.dy, 1));

    await tester.tapAt(tester.getTopLeft(surface) + margin.center);
    await tester.pumpAndSettle();
    expect(fixture.service.model.getBreakpoints(), isEmpty);
    expect(dot, findsNothing);
  });

  testWidgets('without extensions, the panel has no OUTPUT tab', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.txt': 'text'});
    _workbench(tester).commandsById['workbench.actions.view.problems']!.run();
    await tester.pumpAndSettle();
    expect(find.text('PROBLEMS'), findsOneWidget);
    expect(find.text('OUTPUT'), findsNothing);
    expect(IdePanelTab.values, contains(IdePanelTab.output));
  });

  testWidgets('a workbench built over extensions already running, with '
      'keybindings, attaches to them', (tester) async {
    final extensions = _extensions();
    extensions.commands.setExtensions([
      {
        'identifier': {'value': 'acme.tools'},
        'name': 'tools',
        'publisher': 'acme',
        'contributes': {
          'keybindings': [
            {'command': 'workbench.view.explorer', 'key': 'ctrl+alt+e'},
          ],
        },
      },
    ]);
    // The debug commands' names are localized.
    final fixture = await createFakeDebugService();
    addTearDown(fixture.service.dispose);
    await pumpWorkbench(
      tester,
      {'a.txt': 'text'},
      extensions: extensions,
      debugService: fixture.service,
    );
    expect(tester.takeException(), isNull);
    expect(
      _workbench(tester).commandsById['workbench.view.explorer'],
      isNotNull,
    );
  });

  testWidgets('an extension\'s commands are in the Command Palette', (
    tester,
  ) async {
    final extensions = _extensions();
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    extensions.commands.setExtensions([
      {
        'identifier': {'value': 'acme.tools'},
        'name': 'tools',
        'publisher': 'acme',
        'contributes': {
          'commands': [
            {'command': 'acme.hello', 'title': 'Say Hello', 'category': 'Acme'},
          ],
        },
      },
    ]);
    await tester.pump();
    final command = _workbench(tester).commandsById['acme.hello'];
    expect(command, isNotNull);
    expect(command!.label, 'Say Hello');
    expect(command.category, 'Acme');
  });

  testWidgets('a file whose language no installed extension provides gets '
      'its extension recommended, in the notification center', (tester) async {
    final extensions = _extensions();
    final workspace = await pumpWorkbench(
      tester,
      {'main.py': 'print(1)\n'},
      open: ['main.py'],
      extensions: extensions,
    );
    await tester.pumpAndSettle();
    final messages = [
      for (final notification in workspace.notifications.notifications)
        notification.message,
    ];
    expect(
      messages,
      contains(
        "The 'ms-python.python' extension is recommended for Python files.",
      ),
    );
    // Not as a toast.
    expect(workspace.notifications.toasts, isEmpty);
  });
}
