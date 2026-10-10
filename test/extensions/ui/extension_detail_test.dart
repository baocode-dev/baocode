// An extension's page: its header, the README rendered as markdown, the
// Features tab, the versions menu and the pre-release choice.

import 'dart:convert';

import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/ui/extension_detail.dart';
import 'package:baocode/extensions/ui/extensions_model.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../gallery/fixture_http.dart';
import 'fake_backend.dart';

const _prettier = 'esbenp.prettier-vscode';
const _latest = '/api/esbenp/prettier-vscode/universal/latest';
const _readme = '/api/esbenp/prettier-vscode/12.4.0/file/readme.md';
const _changelog = '/api/esbenp/prettier-vscode/12.4.0/file/changelog.md';
const _manifestUrl = '/api/esbenp/prettier-vscode/12.4.0/file/package.json';
const _versionsUrl =
    '/api/v2/-/query?extensionId=esbenp.prettier-vscode&targetPlatform='
    'universal&includeAllVersions=true&size=200&offset=0';

const _extension = {
  'namespace': 'esbenp',
  'name': 'prettier-vscode',
  'version': '12.4.0',
  'targetPlatform': 'universal',
  'displayName': 'Prettier - Code formatter',
  'description': 'Code formatter using prettier',
  'downloadCount': 9413933,
  'averageRating': 4.35,
  'reviewCount': 17,
  'verified': true,
  'preRelease': false,
  'license': 'MIT',
  'repository': 'https://github.com/prettier/prettier-vscode.git',
  'categories': ['Formatters'],
  'engines': {'vscode': '^1.101.0'},
  'files': {
    'manifest': 'https://open-vsx.org/api/esbenp/prettier-vscode/12.4.0/file/package.json',
    'readme':
        'https://open-vsx.org/api/esbenp/prettier-vscode/12.4.0/file/readme.md',
    'changelog': 'https://open-vsx.org/api/esbenp/prettier-vscode/12.4.0/file/changelog.md',
    'icon':
        'https://open-vsx.org/api/esbenp/prettier-vscode/12.4.0/file/icon.png',
  },
  // It publishes a pre-release too (what makes the toggle work).
  'allVersions': {'latest': '...', '12.4.0': '...', 'pre-release': '...'},
};

const _manifest = {
  'name': 'prettier-vscode',
  'publisher': 'esbenp',
  'version': '12.4.0',
  'displayName': 'Prettier - Code formatter',
  'engines': {'vscode': '^1.101.0'},
  'activationEvents': ['onLanguage:javascript'],
  'contributes': {
    'languages': [
      {'id': 'javascript'},
    ],
  },
};

const _versions = {
  'offset': 0,
  'totalSize': 2,
  'extensions': [
    {
      'namespace': 'esbenp',
      'name': 'prettier-vscode',
      'version': '12.4.0',
      'targetPlatform': 'universal',
      'preRelease': false,
      'engines': {'vscode': '^1.101.0'},
    },
    {
      'namespace': 'esbenp',
      'name': 'prettier-vscode',
      'version': '12.5.0',
      'targetPlatform': 'universal',
      'preRelease': true,
      'engines': {'vscode': '^1.101.0'},
    },
  ],
};

const _readmeText =
    '# Prettier Formatter for Visual Studio Code\n\n'
    'An opinionated code formatter.\n';

/// The client requests as the page does, for the universal platform.
FixtureHttp _http({List<int>? readme}) => FixtureHttp(recorded: false)
  ..addJson(_latest, _extension)
  ..addJson('/api/esbenp/prettier-vscode/universal/pre-release', {
    ..._extension,
    'version': '12.5.0',
    'preRelease': true,
  })
  ..addJson('/api/esbenp/prettier-vscode/universal/12.4.0', _extension)
  ..add(_readme, readme ?? utf8.encode(_readmeText))
  ..add(_changelog, utf8.encode('# Changelog\n\n## 12.4.0\n\nFixed things.\n'))
  ..addJson(_manifestUrl, _manifest)
  ..addJson(_versionsUrl, _versions);

OpenVsxClient _client(FixtureHttp http) => OpenVsxClient(
  http: http,
  targetPlatform: ExtensionTargetPlatform.universal,
);

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 1000, height: 900, child: child)),
);

void main() {
  testWidgets('shows an extension from Open VSX with its README', (
    tester,
  ) async {
    final http = _http();
    final model = ExtensionsModel(
      backend: FakeBackend(),
      gallery: _client(http),
    );
    await tester.pumpWidget(
      _app(ExtensionDetailPage(model: model, id: _prettier)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Prettier - Code formatter'), findsOneWidget);
    expect(find.text('esbenp'), findsOneWidget);
    expect(find.text(_prettier), findsWidgets);
    expect(find.textContaining('downloads'), findsOneWidget);
    // The README's heading, from the markdown above.
    expect(
      find.text('Prettier Formatter for Visual Studio Code'),
      findsOneWidget,
    );
    // The sidebar.
    expect(find.text('Compatibility'), findsOneWidget);
    expect(find.text('Identifier'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    // A not-installed extension offers Install.
    expect(find.text('Install'), findsOneWidget);
  });

  testWidgets('lists the contributions of the manifest', (tester) async {
    final http = _http();
    final model = ExtensionsModel(
      backend: FakeBackend(),
      gallery: _client(http),
    );
    await tester.pumpWidget(
      _app(
        ExtensionDetailPage(
          model: model,
          id: _prettier,
          initialTab: ExtensionDetailTab.features,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Contributions'), findsOneWidget);
    expect(find.textContaining('languages'), findsWidgets);
    expect(find.text('Activation Events'), findsOneWidget);
    expect(find.text('onLanguage:javascript'), findsOneWidget);
  });

  testWidgets('offers the versions and the pre-release channel', (
    tester,
  ) async {
    final http = _http();
    final model = ExtensionsModel(
      backend: FakeBackend(),
      gallery: _client(http),
    );
    await tester.pumpWidget(
      _app(ExtensionDetailPage(model: model, id: _prettier)),
    );
    await tester.pumpAndSettle();

    expect(find.text('v12.4.0'), findsOneWidget);
    // The versions menu is filled when it opens (its entries are a future).
    await tester.tap(find.byTooltip('Version'));
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);
    expect(find.textContaining('12.4.0'), findsWidgets);
    // A pre-release is hidden until the channel is switched to.
    expect(find.textContaining('12.5.0'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pre-Release'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Version'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12.5.0'), findsWidgets);
  });

  testWidgets('a changelog that fails to load says so when its tab shows', (
    tester,
  ) async {
    final http = _http()..add(_changelog, const [], status: 500);
    final model = ExtensionsModel(
      backend: FakeBackend(),
      gallery: _client(http),
    );
    await tester.pumpWidget(
      _app(ExtensionDetailPage(model: model, id: _prettier)),
    );
    // Not shown: its failure is not an unhandled error.
    await tester.pumpAndSettle();

    await tester.tap(find.text('Changelog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('500'), findsOneWidget);
  });

  testWidgets('says so when the README is empty', (tester) async {
    final http = _http(readme: utf8.encode('   '));
    final model = ExtensionsModel(
      backend: FakeBackend(),
      gallery: _client(http),
    );
    await tester.pumpWidget(
      _app(ExtensionDetailPage(model: model, id: _prettier)),
    );
    await tester.pumpAndSettle();
    expect(find.text('This extension has no README.'), findsOneWidget);
  });

  testWidgets('shows an installed extension with its actions', (tester) async {
    final http = _http();
    final backend = FakeBackend(
      installed: [
        InstalledExtension(
          manifest: fakeManifest(
            _prettier,
            version: '12.3.0',
            displayName: 'Prettier',
          ),
          location: '/extensions/$_prettier',
        ),
      ],
    );
    final model = ExtensionsModel(backend: backend, gallery: _client(http));
    await tester.pumpWidget(
      _app(ExtensionDetailPage(model: model, id: _prettier)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uninstall'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    // Upstream's VersionWidget: the installed version, not the gallery's.
    expect(find.text('v12.3.0'), findsOneWidget);
  });

  testWidgets("shows the newest release when Open VSX's latest is a "
      'pre-release (GitLens)', (tester) async {
    final http = _http()
      ..addJson(_latest, {
        ..._extension,
        'version': '12.5.0',
        'preRelease': true,
      });
    final model = ExtensionsModel(
      backend: FakeBackend(),
      gallery: _client(http),
    );
    await tester.pumpWidget(
      _app(ExtensionDetailPage(model: model, id: _prettier)),
    );
    await tester.pumpAndSettle();

    expect(find.text('v12.4.0'), findsOneWidget);
    expect(find.text('v12.5.0'), findsNothing);
  });
}
