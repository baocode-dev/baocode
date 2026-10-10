// The Extensions view: the installed list, an Open VSX search, and the
// install, uninstall and enable actions through the backend.

import 'package:baocode/extensions/capabilities/capability_analysis.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/ui/extensions_model.dart';
import 'package:baocode/extensions/ui/extensions_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../gallery/fixture_http.dart';
import 'fake_backend.dart';

InstalledExtension _installed(
  String id, {
  String version = '1.0.0',
  String? displayName,
  String? description,
  bool enabledGlobally = true,
  bool preRelease = false,
  bool fromGallery = true,
  InstalledExtensionKind kind = InstalledExtensionKind.user,
  String? location,
}) => InstalledExtension(
  manifest: fakeManifest(
    id,
    version: version,
    displayName: displayName,
    description: description,
  ),
  location: location ?? '/extensions/$id',
  kind: kind,
  enabledGlobally: enabledGlobally,
  preRelease: preRelease,
  fromGallery: fromGallery,
);

ExtensionsModel _model(FakeBackend backend, {FixtureHttp? http}) =>
    ExtensionsModel(
      backend: backend,
      gallery: OpenVsxClient(
        http: http ?? FixtureHttp(recorded: false),
        targetPlatform: null,
      ),
      searchDelay: Duration.zero,
    );

/// A search response for what the view asks for (size 50, no category).
Map<String, Object?> _searchJson(List<Map<String, Object?>> extensions) => {
  'offset': 0,
  'totalSize': extensions.length,
  'extensions': extensions,
};

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 460, height: 700, child: child)),
);

void main() {
  testWidgets('lists the installed extensions', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed('esbenp.prettier-vscode', displayName: 'Prettier'),
        _installed('redhat.vscode-yaml', displayName: 'YAML'),
      ],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    expect(find.text('Prettier'), findsOneWidget);
    expect(find.text('YAML'), findsOneWidget);
    expect(find.text('esbenp'), findsOneWidget);
    expect(find.text('1.0.0'), findsNWidgets(2));
    // The two panes, each with how many it holds.
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('built-in extensions are under @builtin, not Installed, as '
      'upstream', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed('esbenp.prettier-vscode', displayName: 'Prettier'),
        _installed(
          'vscode.typescript-language-features',
          displayName: 'TypeScript and JavaScript Language Features',
          kind: InstalledExtensionKind.builtin,
        ),
      ],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();
    expect(find.text('Prettier'), findsOneWidget);
    expect(
      find.text('TypeScript and JavaScript Language Features'),
      findsNothing,
    );
    expect(model.installedEntries.map((e) => e.id), [
      'esbenp.prettier-vscode',
    ]);

    model.setQuery('@builtin ');
    await tester.pumpAndSettle();
    expect(
      find.text('TypeScript and JavaScript Language Features'),
      findsOneWidget,
    );
    expect(find.text('Prettier'), findsNothing);
  });

  testWidgets('filters the installed list', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed('esbenp.prettier-vscode', displayName: 'Prettier'),
        _installed('redhat.vscode-yaml', displayName: 'YAML'),
      ],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@installed yaml');
    await tester.pumpAndSettle();
    expect(find.text('YAML'), findsOneWidget);
    expect(find.text('Prettier'), findsNothing);
    expect(find.text('Installed'), findsNothing);

    // `@installed` alone shows every one of them.
    await tester.enterText(find.byType(TextField), '@installed ');
    await tester.pumpAndSettle();
    expect(find.text('Prettier'), findsOneWidget);
    expect(find.text('YAML'), findsOneWidget);
  });

  testWidgets('searches Open VSX and installs a result', (tester) async {
    final http = FixtureHttp(recorded: false)
      ..addJson(
        '/api/-/search?offset=0&query=python&size=50&sortBy=relevance'
            '&sortOrder=desc',
        _searchJson([
          {
            'namespace': 'ms-python',
            'name': 'python',
            'version': '2026.4.0',
            'displayName': 'Python',
            'description': 'Python language support.',
            'downloadCount': 120000000,
            'verified': true,
          },
          {
            'namespace': 'ms-python',
            'name': 'vscode-black-formatter',
            'version': '2026.2.0',
            'displayName': 'Black Formatter',
            'downloadCount': 4000000,
          },
        ]),
      );
    final backend = FakeBackend();
    final model = _model(backend, http: http);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'python');
    await tester.pumpAndSettle();
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('Black Formatter'), findsOneWidget);
    // The title says the results are from Open VSX.
    expect(find.text('Open VSX'), findsOneWidget);

    await tester.tap(find.text('Install').first);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('installFromGallery ms-python.python'));
  });

  testWidgets('shows an error when installing fails', (tester) async {
    final http = FixtureHttp(recorded: false)
      ..addJson(
        '/api/-/search?offset=0&query=python&size=50&sortBy=relevance'
            '&sortOrder=desc',
        _searchJson([
          {'namespace': 'ms-python', 'name': 'python', 'version': '2026.4.0'},
        ]),
      );
    final backend = FakeBackend()
      ..failNextInstall = const FormatException('disk full');
    final errors = <String>[];
    final model = _model(backend, http: http);
    await tester.pumpWidget(
      _app(ExtensionsView(model: model, onError: errors.add)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'python');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install').first);
    await tester.pumpAndSettle();
    expect(errors, hasLength(1));
    expect(errors.single, contains('ms-python.python'));
    expect(errors.single, contains('disk full'));
  });

  testWidgets('uninstalls from the manage menu', (tester) async {
    final backend = FakeBackend(
      installed: [_installed('esbenp.prettier-vscode', displayName: 'Prettier')],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uninstall').last);
    await tester.pumpAndSettle();

    expect(backend.calls, contains('uninstall esbenp.prettier-vscode'));
    expect(backend.installed, isEmpty);
    expect(find.text('Prettier'), findsNothing);
    expect(find.text('No extensions found.'), findsWidgets);
  });

  testWidgets('disables globally and in the workspace', (tester) async {
    final backend = FakeBackend(
      installed: [_installed('esbenp.prettier-vscode', displayName: 'Prettier')],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable (Workspace)'));
    await tester.pumpAndSettle();
    expect(
      backend.calls,
      contains('setEnabled esbenp.prettier-vscode false workspace'),
    );
    expect(find.text('Disabled (Workspace)'), findsOneWidget);

    // Disabled globally, the row only says "Disabled", and the menu offers
    // to enable it again.
    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable').last);
    await tester.pumpAndSettle();
    expect(
      backend.calls,
      contains('setEnabled esbenp.prettier-vscode false global'),
    );
    expect(find.text('Disabled'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(
      backend.calls,
      contains('setEnabled esbenp.prettier-vscode true global'),
    );
    // The workspace still disables it, so the row still says so.
    expect(find.text('Disabled (Workspace)'), findsOneWidget);
  });

  testWidgets('runs the view actions from the title bar', (tester) async {
    var installedFromVsix = 0;
    var imported = 0;
    final backend = FakeBackend();
    final model = _model(backend);
    await tester.pumpWidget(
      _app(
        ExtensionsView(
          model: model,
          onInstallFromVsix: () => installedFromVsix++,
          onImport: () => imported++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More Actions...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install from VSIX...'));
    await tester.pumpAndSettle();
    expect(installedFromVsix, 1);

    await tester.tap(find.byTooltip('More Actions...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from VS Code...'));
    await tester.pumpAndSettle();
    expect(imported, 1);
  });

  testWidgets('shows a capability badge for an extension that is not fully '
      'supported', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed(
          'acme.tree-and-panel',
          displayName: 'Tree and Panel',
          location: 'test/fixtures/extensions/capabilities/tree-and-panel',
        ),
      ],
    );
    final model = _model(backend);
    // The analysis reads the folder, so it needs real IO and real time.
    await tester.runAsync(() async {
      await model.refreshInstalled();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(
      model.capabilities['acme.tree-and-panel']?.level,
      ExtensionCapabilityLevel.partial,
    );

    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();
    // A row shows only the badge's icon; its tooltip has the words.
    expect(find.text('Partly supported'), findsNothing);
    expect(
      find.byTooltip(
        'Partly supported: Runs, but some of its UI cannot be shown: '
        'BaoCode has no webviews.',
      ),
      findsOneWidget,
    );
  });
}
