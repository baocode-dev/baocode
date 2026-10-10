// The Extensions view: the installed list, an Open VSX search, and the
// install, uninstall and enable actions through the backend.

import 'package:baocode/extensions/capabilities/capability_analysis.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/ui/extensions_model.dart';
import 'package:baocode/extensions/ui/extensions_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../gallery/fixture_http.dart';
import 'fake_backend.dart';

InstalledExtension _installed(
  String id, {
  String version = '1.0.0',
  String? displayName,
  String? description,
  bool enabled = true,
  bool preRelease = false,
  bool fromGallery = true,
  Map<String, Object?> manifest = const {},
}) => InstalledExtension(
  manifest: fakeManifest(
    id,
    version: version,
    displayName: displayName,
    description: description,
    manifest: manifest,
  ),
  location: '/extensions/$id',
  enabled: enabled,
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

/// A search response for what the view asks for (size 50, themes).
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
    expect(find.text('Popular Themes'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a name and a publisher take their row\'s width, not half '
      'of it', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed(
          'streetsidesoftware.code-spell-checker',
          displayName: 'Code Spell Checker Plus',
        ),
      ],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    for (final text in ['Code Spell Checker Plus', 'streetsidesoftware']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    }
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
        '/api/-/search?category=Themes&offset=0&query=python&size=50'
        '&sortBy=relevance'
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
        '/api/-/search?category=Themes&offset=0&query=python&size=50'
        '&sortBy=relevance'
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
      installed: [
        _installed('esbenp.prettier-vscode', displayName: 'Prettier'),
      ],
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

  testWidgets('disables and enables from the manage menu', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed('esbenp.prettier-vscode', displayName: 'Prettier'),
      ],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable').last);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('setEnabled esbenp.prettier-vscode false'));
    expect(find.text('Disabled'), findsOneWidget);

    await tester.tap(find.byTooltip('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('setEnabled esbenp.prettier-vscode true'));
    expect(find.text('Disabled'), findsNothing);
  });

  testWidgets('runs the view actions from the title bar', (tester) async {
    var installedFromVsix = 0;
    final backend = FakeBackend();
    final model = _model(backend);
    await tester.pumpWidget(
      _app(
        ExtensionsView(
          model: model,
          onInstallFromVsix: () => installedFromVsix++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More Actions...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install from VSIX...'));
    await tester.pumpAndSettle();
    expect(installedFromVsix, 1);
  });

  testWidgets('shows a capability badge for an extension that is not fully '
      'supported', (tester) async {
    final backend = FakeBackend(
      installed: [
        _installed(
          'acme.night',
          displayName: 'Night',
          manifest: {
            'main': './out/extension.js',
            'contributes': {
              'themes': [
                {'label': 'Night', 'uiTheme': 'vs-dark', 'path': './n.json'},
              ],
            },
          },
        ),
      ],
    );
    final model = _model(backend);
    await tester.pumpWidget(_app(ExtensionsView(model: model)));
    await tester.pumpAndSettle();
    expect(
      model.capabilities['acme.night']?.level,
      ExtensionCapabilityLevel.partial,
    );
    // A row shows only the badge's icon; its tooltip has the words.
    expect(find.text('Partly supported'), findsNothing);
    expect(
      find.byTooltip(
        'Partly supported: Its themes apply; the rest of it does nothing in '
        'BaoCode.',
      ),
      findsOneWidget,
    );
  });
}
