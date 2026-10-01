import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/extensions/ide_extensions.dart';
import 'package:baocode/ide/extensions/ide_extensions_view.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/lsp/catalog/bundled_lsp_catalog.dart';
import 'package:baocode/ide/lsp/catalog/standard_lsp.dart';
import 'package:baocode/ide/lsp/install/mason_platform.dart';
import 'package:baocode/ide/lsp/install/mason_registry.dart';
import 'package:baocode/ide/lsp/install/mason_server_provider.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/packs/language_packs.dart';
import 'package:path/path.dart' as p;

import '../lsp_ui/fake_language_features.dart';
import '../workbench/fake_files.dart';

const _catalog = '''
{
  "languages": [
    {"id": "python", "fileTypes": ["py"], "servers": ["pyright", "ruff"]},
    {"id": "toml", "fileTypes": ["toml"], "servers": ["taplo"]}
  ],
  "servers": {
    "pyright": {"command": "pyright-langserver", "mason": "pyright"},
    "ruff": {"command": "ruff", "mason": "ruff"},
    "taplo": {"command": "taplo"},
    "zls": {"command": "zls"}
  }
}''';

final _registry = MasonRegistry.fromJson({
  'packages': [
    {
      'name': 'pyright',
      'languages': ['Python'],
      'source': {'id': 'pkg:npm/pyright@1.1.400'},
      'bin': {'pyright-langserver': 'npm:pyright-langserver'},
    },
    {
      'name': 'ruff',
      'languages': ['Python'],
      'source': {
        'id': 'pkg:github/astral-sh/ruff@0.9.0',
        'asset': {'target': 'darwin_arm64', 'file': 'ruff.tar.gz'},
      },
      'bin': {'ruff': 'ruff'},
    },
  ],
});

void main() {
  group('language servers as extensions', () {
    late Directory temp;
    late MasonServerProvider provider;
    late IdeLanguageServerExtensions extensions;

    void executable(String path) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', ['755', path]);
    }

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('ide_extensions_');
      final bin = p.join(temp.path, 'bin');
      final servers = p.join(temp.path, 'servers');
      // taplo is on PATH; ruff was installed here.
      executable(p.join(bin, 'taplo'));
      executable(p.join(servers, 'ruff', 'ruff'));
      File(p.join(servers, 'ruff', MasonInstallManifest.fileName))
          .writeAsStringSync(
            jsonEncode({
              'package': 'ruff',
              'version': '0.8.0',
              'source': 'pkg:github/astral-sh/ruff@0.8.0',
              'bin': {'ruff': 'ruff'},
            }),
          );
      provider = MasonServerProvider(
        registry: _registry,
        installRoot: servers,
        environment: () async => {'PATH': bin},
        platform: const MasonPlatform('darwin', 'arm64'),
      );
      final catalog = BundledLspCatalog(data: _catalog);
      await catalog.load();
      extensions = IdeLanguageServerExtensions(
        Future.value(
          StandardLsp(
            catalog: catalog,
            provider: provider,
            packs: LanguagePackRegistry.instance,
          ),
        ),
      );
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('installed, installable and unavailable; by name', () async {
      final list = await extensions.list();
      expect([for (final e in list) e.id], ['pyright', 'ruff', 'taplo', 'zls']);
      final [pyright, ruff, taplo, zls] = list;

      expect(pyright.state, IdeExtensionState.installable);
      expect(pyright.package, 'pyright');
      expect(pyright.version, '1.1.400');
      expect(pyright.publisher, 'npm');
      expect(pyright.description, 'Language server for Python');
      expect(pyright.missingRuntime, isNotNull);
      expect(pyright.status, contains('which was not found'));

      expect(ruff.state, IdeExtensionState.installed);
      expect(ruff.managed, isTrue);
      expect(ruff.version, '0.8.0');
      expect(ruff.publisher, 'astral-sh');
      expect(ruff.fileType, 'py');

      expect(taplo.state, IdeExtensionState.installed);
      expect(taplo.managed, isFalse);
      expect(taplo.description, 'Language server for toml');

      expect(zls.state, IdeExtensionState.unavailable);
      expect(zls.description, 'Language server');
      expect(zls.status, contains('cannot be installed automatically'));
    });

    test('uninstalls only what it installed', () async {
      final list = await extensions.list();
      await extensions.uninstall(list.firstWhere((e) => e.id == 'taplo'));
      await extensions.uninstall(list.firstWhere((e) => e.id == 'ruff'));
      final after = await extensions.list();
      expect(
        after.firstWhere((e) => e.id == 'ruff').state,
        IdeExtensionState.installable,
      );
      expect(
        after.firstWhere((e) => e.id == 'taplo').state,
        IdeExtensionState.installed,
      );
    });
  });

  group('the Extensions view', () {
    late _FakeExtensions service;
    late IdeExtensionsSession session;
    late List<String> installed;
    late List<String> errors;

    setUp(() {
      service = _FakeExtensions();
      session = IdeExtensionsSession(service);
      installed = [];
      errors = [];
    });
    tearDown(() => session.dispose());

    Future<void> pumpView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdeExtensionsView(
              session: session,
              recommended: const {'pyright', 'taplo'},
              onInstalled: installed.add,
              onError: errors.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder row(String id) => find.byWidgetPredicate(
      (widget) => widget is IdeExtensionRow && widget.extension.id == id,
    );

    testWidgets('Installed and Recommended, with counts', (tester) async {
      await pumpView(tester);
      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.widgetWithText(IdeCountBadge, '2'), findsOneWidget);
      // taplo is installed, so only pyright is recommended.
      expect(find.widgetWithText(IdeCountBadge, '1'), findsOneWidget);
      expect(row('ruff'), findsOneWidget);
      expect(row('taplo'), findsOneWidget);
      expect(row('pyright'), findsOneWidget);
      expect(row('zls'), findsNothing);
      expect(find.text('Language server for Python'), findsNWidgets(2));
      expect(find.text('astral-sh'), findsOneWidget);
    });

    testWidgets('a search lists what matches', (tester) async {
      await pumpView(tester);
      final input = find.descendant(
        of: find.byType(IdeInputBox),
        matching: find.byType(EditableText),
      );
      await tester.enterText(input, 'python');
      await tester.pumpAndSettle();
      expect(find.text('Extensions: Marketplace'), findsOneWidget);
      expect(find.text('Installed'), findsNothing);
      expect(row('pyright'), findsOneWidget);
      expect(row('ruff'), findsOneWidget);
      expect(row('taplo'), findsNothing);

      await tester.enterText(input, '@installed python');
      await tester.pumpAndSettle();
      expect(find.text('Extensions: Installed'), findsOneWidget);
      expect(row('pyright'), findsNothing);
      expect(row('ruff'), findsOneWidget);

      await tester.enterText(input, 'nothing-like-it');
      await tester.pumpAndSettle();
      expect(find.text('No extensions found.'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear Extensions Search Results'));
      await tester.pumpAndSettle();
      expect(find.text('Installed'), findsOneWidget);
    });

    testWidgets('Install shows Installing, then starts the server', (
      tester,
    ) async {
      await pumpView(tester);
      final installing = Completer<void>();
      service.installing = installing;
      await tester.tap(
        find.descendant(of: row('pyright'), matching: find.text('Install')),
      );
      await tester.pump();
      expect(
        find.descendant(of: row('pyright'), matching: find.text('Installing')),
        findsOneWidget,
      );
      installing.complete();
      await tester.pumpAndSettle();
      expect(service.installs, ['pyright']);
      expect(installed, ['pyright']);
      // Listed again: it is installed now, and no longer recommended.
      expect(find.widgetWithText(IdeCountBadge, '3'), findsOneWidget);
      expect(find.text('No extensions found.'), findsOneWidget);
    });

    testWidgets('a failed install is reported', (tester) async {
      await pumpView(tester);
      service.error = 'offline';
      await tester.tap(
        find.descendant(of: row('pyright'), matching: find.text('Install')),
      );
      await tester.pumpAndSettle();
      expect(errors, ["Error while installing 'pyright' extension. offline"]);
      expect(installed, isEmpty);
    });

    testWidgets('Manage uninstalls; the context menu copies the id', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.tap(
        find.descendant(of: row('ruff'), matching: find.byTooltip('Manage')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uninstall'));
      await tester.pumpAndSettle();
      expect(service.uninstalls, ['ruff']);

      // taplo is on PATH: nothing uninstalls it.
      await tester.tapAt(
        tester.getCenter(row('taplo')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Uninstall'), findsNothing);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy Extension ID'));
      await tester.pumpAndSettle();
      expect(copied, 'taplo');
    });
  });

  testWidgets('the workbench recommends servers the open files lack, and '
      'starts what installs', (tester) async {
    final languages = FakeLanguageFeatures();
    addTearDown(languages.dispose);
    languages.statuses[inRoot('a.py')] = const [
      LanguageServerStatus(
        serverId: 'pyright',
        state: LanguageServerState.missing,
        installable: true,
      ),
    ];
    final service = _FakeExtensions();
    await pumpWorkbench(
      tester,
      {'a.py': 'print(1)'},
      open: ['a.py'],
      languages: languages,
      extensions: service,
    );
    await chord(tester, LogicalKeyboardKey.keyX, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(find.byType(IdeExtensionsView), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    final pyright = find.byWidgetPredicate(
      (widget) => widget is IdeExtensionRow && widget.extension.id == 'pyright',
    );
    expect(pyright, findsNWidgets(1));
    await tester.tap(
      find.descendant(of: pyright, matching: find.text('Install')),
    );
    await tester.pumpAndSettle();
    expect(service.installs, ['pyright']);
    expect(languages.retried, ['pyright']);
  });
}

class _FakeExtensions implements IdeExtensions {
  final Map<String, IdeExtension> _extensions = {
    for (final extension in const [
      IdeExtension(
        id: 'pyright',
        state: IdeExtensionState.installable,
        languages: ['Python'],
        package: 'pyright',
        publisher: 'npm',
      ),
      IdeExtension(
        id: 'ruff',
        state: IdeExtensionState.installed,
        languages: ['Python'],
        package: 'ruff',
        publisher: 'astral-sh',
        managed: true,
      ),
      IdeExtension(
        id: 'taplo',
        state: IdeExtensionState.installed,
        languages: ['toml'],
      ),
      IdeExtension(id: 'zls', state: IdeExtensionState.unavailable),
    ])
      extension.id: extension,
  };

  Completer<void>? installing;
  Object? error;
  final List<String> installs = [];
  final List<String> uninstalls = [];

  IdeExtension _with(IdeExtension e, IdeExtensionState state, bool managed) =>
      IdeExtension(
        id: e.id,
        state: state,
        languages: e.languages,
        package: e.package,
        publisher: e.publisher,
        managed: managed,
      );

  @override
  Future<List<IdeExtension>> list() async => [..._extensions.values];

  @override
  Future<void> install(
    IdeExtension extension, {
    void Function(String message)? onProgress,
  }) async {
    await installing?.future;
    if (error case final error?) throw error;
    installs.add(extension.id);
    _extensions[extension.id] = _with(
      extension,
      IdeExtensionState.installed,
      true,
    );
  }

  @override
  Future<void> uninstall(IdeExtension extension) async {
    uninstalls.add(extension.id);
    _extensions[extension.id] = _with(
      extension,
      IdeExtensionState.installable,
      false,
    );
  }
}
