import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/configuration/ui/setting_entries.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/settings/pages/extension_setting_controls.dart';
import 'package:baocode/settings/pages/extension_settings_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/settings_dialog.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _File extends ChangeNotifier implements SettingsFile {
  _File([Map<String, Object?>? values]) : values = values ?? {};

  @override
  Map<String, Object?> values;

  final writes = <List<Object?>>[];

  @override
  Future<void> write(List<String> path, Object? value) async {
    writes.add([...path, value]);
    final target = path.length == 1
        ? values
        : (values[path[0]] as Map<String, Object?>? ?? {});
    if (path.length > 1) values[path[0]] = target;
    if (value == null) {
      target.remove(path.last);
    } else {
      target[path.last] = value;
    }
    notifyListeners();
  }
}

final _extension = <String, Object?>{
  'identifier': {'value': 'acme.tools'},
  'contributes': {
    'configuration': [
      {
        'title': 'Acme Tools',
        'order': 1,
        'properties': {
          'acme.enable': {
            'type': 'boolean',
            'default': true,
            'markdownDescription':
                'Enables Acme. See `#acme.mode#` for how it runs.',
          },
          'acme.mode': {
            'type': 'string',
            'enum': ['fast', 'thorough'],
            'enumDescriptions': ['Checks what changed.', 'Checks everything.'],
            'default': 'fast',
            'description': 'How checks run.',
          },
          'acme.port': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 65535,
            'default': 7000,
            'description': 'The server port.',
          },
          'acme.name': {
            'type': 'string',
            'pattern': r'^[a-z]+$',
            'patternErrorMessage': 'Lowercase letters only.',
            'default': 'acme',
            'description': 'The profile name.',
          },
          'acme.serverPath': {
            'type': 'string',
            'scope': 'machine',
            'default': '',
            'description': 'Where the server is.',
          },
          'acme.old': {
            'type': 'boolean',
            'deprecationMessage': 'Use acme.mode.',
            'description': 'Old switch.',
          },
          'acme.lineWidth': {
            'type': 'number',
            'scope': 'language-overridable',
            'default': 80,
            'description': 'Line width.',
          },
        },
      },
      {
        'title': 'Advanced',
        'order': 2,
        'properties': {
          'acme.args': {
            'type': 'array',
            'items': {'type': 'string'},
            'default': ['--fast'],
            'description': 'Arguments for the server.',
          },
          'acme.exclude': {
            'type': 'object',
            'additionalProperties': {'type': 'boolean'},
            'default': {'**/build': true},
            'description': 'Files the checks skip.',
          },
          'acme.rules': {
            'type': 'object',
            'properties': {
              'a': {'type': 'string'},
            },
            'description': 'Rules.',
          },
        },
      },
    ],
  },
};

CoreConfiguration? _core;
CoreConfiguration get core => _core ??= CoreConfiguration.fromJson(
  (jsonDecode(
    File('assets/exthost/core_configuration.json').readAsStringSync(),
  ) as Map).cast(),
  platform: 'darwin',
);

Finder checkbox(String label) =>
    find.byWidgetPredicate((w) => w is SettingCheckbox && w.label == label);
Finder dropdown(String current) => find.byWidgetPredicate(
  (w) => w is SettingsDropdown && w.current == current,
);
Finder textButton(String label) =>
    find.byWidgetPredicate((w) => w is SettingTextButton && w.label == label);

void main() {
  late _File user;
  late _File workspace;
  late ConfigurationRegistry registry;
  late List<(ExtensionSettingsTarget, String)> opened;

  setUp(() {
    user = _File();
    workspace = _File();
    registry = core.registry(extensions: [_extension]);
    opened = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    String query = '',
    ExtensionSettingsFilter? filter,
    bool withWorkspace = true,
  }) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ExtensionSettingsPage(
            initialQuery: query,
            initialFilter: filter,
            source: ExtensionSettingsSource(
              registry: registry,
              user: user,
              workspace: withWorkspace ? workspace : null,
              extensionNames: const {'acme.tools': 'Acme Tools'},
              openSettingsJson: (target, key) => opened.add((target, key)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('model', () {
    test('display names as upstream words them', () {
      expect(wordifyKey('editor.tabSize'), 'Editor › Tab Size');
      expect(wordifyKey('typescriptJsonPHP'), 'TypeScript JSON PHP');
      expect(settingKeyToDisplayFormat('editor.tabSize'), (
        category: 'Editor',
        label: 'Tab Size',
      ));
      expect(
        settingKeyToDisplayFormat(
          'python.analysis.typeCheckingMode',
          'ms-python.python',
        ),
        (category: 'Analysis', label: 'Type Checking Mode'),
      );
      expect(
        fixSettingLinks('See `#editor.tabSize#`.'),
        'See [Editor: Tab Size](#editor.tabSize "editor.tabSize").',
      );
    });

    test('controls by schema', () {
      SettingControl of(String key) =>
          controlOf(key, registry.properties[key]!.schema);
      expect(of('editor.tabSize'), SettingControl.number);
      expect(of('editor.insertSpaces'), SettingControl.boolean);
      expect(of('files.exclude'), SettingControl.booleanObject);
      expect(of('files.eol'), SettingControl.enumeration);
      expect(of('editor.codeActionsOnSave'), SettingControl.complex);
      expect(of('acme.args'), SettingControl.stringArray);
      expect(of('acme.port'), SettingControl.integer);
    });

    test('validation messages', () {
      final l10n = englishLocalizations;
      final port = registry.properties['acme.port']!.schema;
      expect(
        validateSetting(port, 0, l10n),
        'Value must be greater than or equal to 1.',
      );
      expect(validateSetting(port, 1.5, l10n), 'Value must be an integer.');
      expect(validateSetting(port, 80, l10n), isNull);
      expect(
        validateSetting({'type': 'string', 'maxLength': 2}, 'abc', l10n),
        'Value must be 2 or fewer characters long.',
      );
      expect(
        validateSetting({'type': 'string', 'pattern': '^a'}, 'b', l10n),
        'Value must match regex `^a`.',
      );
    });

    test('query filters', () {
      final q = SettingsQuery.parse(
        '@modified tab  @lang:python @ext:a.b @id:x,y',
      );
      expect(q.modified, isTrue);
      expect(q.words, ['tab']);
      expect(q.language, 'python');
      expect(q.extensions, {'a.b'});
      expect(q.ids, {'x', 'y'});
    });
  });

  testWidgets('lists an extension\'s settings under its name and nodes', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Acme Tools'), findsOneWidget);
    expect(find.text('acme.tools'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.textContaining('Port', findRichText: true), findsWidgets);
    // VS Code's own settings are under the dropdown's other choices.
    expect(find.textContaining('Tab Size', findRichText: true), findsNothing);
    // Deprecated and not set: hidden.
    expect(find.text('Old switch.'), findsNothing);
    user.values['acme.old'] = true;
    user.notifyListeners();
    await tester.pump();
    expect(find.text('Use acme.mode.'), findsOneWidget);
  });

  testWidgets('a checkbox writes the user setting; the default resets it', (
    tester,
  ) async {
    await pump(tester, query: 'enables');
    final box = checkbox('Enable');
    expect(
      tester.getSemantics(box),
      isSemantics(label: 'Enable', isChecked: true),
    );
    await tester.tap(box);
    await tester.pump();
    expect(user.values, {'acme.enable': false});
    expect(find.bySemanticsLabel('Modified'), findsOneWidget);
    expect(tester.getSemantics(box), isSemantics(isChecked: false));
    await tester.tap(box);
    await tester.pump();
    // Back to the default: removed, as upstream does in User.
    expect(user.writes.last, ['acme.enable', null]);
    expect(user.values, isEmpty);
  });

  testWidgets('an enum is a dropdown with the choice\'s description', (
    tester,
  ) async {
    await pump(tester, query: '@id:acme.mode');
    expect(find.text('Checks what changed.'), findsOneWidget);
    await tester.tap(dropdown('fast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('thorough').last);
    await tester.pumpAndSettle();
    expect(user.values, {'acme.mode': 'thorough'});
    expect(find.text('Checks everything.'), findsOneWidget);
  });

  testWidgets('numbers and strings are validated as typed', (tester) async {
    await pump(tester, query: 'server port');
    expect(find.text('The server port.'), findsOneWidget);
    expect(find.text('The profile name.'), findsNothing);
    await search(tester, '@id:acme.port,acme.name');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '7000',
      ),
      '0',
    );
    await tester.pump();
    expect(
      find.text('Value must be greater than or equal to 1.'),
      findsOneWidget,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(user.writes, isEmpty);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '0',
      ),
      '8080',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(user.values, {'acme.port': 8080});

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'acme',
      ),
      'Acme1',
    );
    await tester.pump();
    expect(find.text('Lowercase letters only.'), findsOneWidget);
  });

  testWidgets('a string list adds, and an object of booleans turns off', (
    tester,
  ) async {
    await pump(tester, query: '@ext:acme.tools advanced');
    await search(tester, '@id:acme.args,acme.exclude');
    expect(find.text('--fast'), findsOneWidget);
    await tester.tap(textButton('Add Item'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextField && w.autofocus),
      '--verbose',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(user.values['acme.args'], ['--fast', '--verbose']);

    expect(find.text('**/build'), findsOneWidget);
    await tester.tap(checkbox('**/build'));
    await tester.pump();
    expect(user.values['acme.exclude'], {'**/build': false});
  });

  testWidgets('what has no control is edited in settings.json', (tester) async {
    await pump(tester, query: '@id:acme.rules');
    await tester.tap(textButton('Edit in settings.json'));
    await tester.pump();
    expect(user.writes.single, ['acme.rules', <String, Object?>{}]);
    expect(opened.single, (ExtensionSettingsTarget.user, 'acme.rules'));
  });

  testWidgets('a #setting# link shows that setting', (tester) async {
    await pump(tester, query: '@id:acme.enable');
    await tester.tapOnText(find.textRange.ofSubstring('Mode'));
    await tester.pump();
    expect(find.text('Checks what changed.'), findsOneWidget);
    expect(find.text('Enables Acme. See '), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '@id:acme.mode',
    );
  });

  testWidgets('Workspace: no machine settings; writes there', (tester) async {
    user.values['acme.mode'] = 'thorough';
    await pump(tester, query: '@ext:acme.tools');
    expect(find.text('Where the server is.'), findsOneWidget);
    await tester.tap(find.text('Workspace'));
    await tester.pump();
    expect(find.text('Where the server is.'), findsNothing);
    // The user's value is what the workspace inherits.
    expect(dropdown('thorough'), findsOneWidget);
    expect(
      find.textContaining('Also modified in: User', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(checkbox('Enable'));
    await tester.pump();
    expect(workspace.values, {'acme.enable': false});
    expect(user.values, {'acme.mode': 'thorough'});
  });

  testWidgets('@lang: lists language settings and writes into [lang]', (
    tester,
  ) async {
    await pump(
      tester,
      query: '@lang:python',
      filter: ExtensionSettingsFilter.all,
    );
    expect(
      find.text('Settings for python: values are written to "[python]".'),
      findsOneWidget,
    );
    await search(
      tester,
      '@lang:python @id:acme.lineWidth,acme.enable,editor.insertSpaces',
    );
    expect(find.text('Line width.'), findsOneWidget);
    // Not language-overridable.
    expect(
      find.textContaining('Enables Acme', findRichText: true),
      findsNothing,
    );
    await tester.tap(checkbox('Editor: Insert Spaces'));
    await tester.pump();
    expect(user.values, {
      '[python]': {'editor.insertSpaces': false},
    });
  });

  testWidgets('Reset Setting from the gear menu', (tester) async {
    user.values['acme.port'] = 9000;
    await pump(tester, query: '@modified');
    expect(find.text('The server port.'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is SettingIconButton && w.tooltip == 'More Actions...',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Setting'));
    await tester.pumpAndSettle();
    expect(user.values, isEmpty);
    expect(find.text('No settings found'), findsWidgets);
  });

  testWidgets('VS Code\'s own settings, with upstream defaults', (
    tester,
  ) async {
    await pump(tester, filter: ExtensionSettingsFilter.core, query: 'tab size');
    expect(find.text('Editor'), findsOneWidget);
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '4',
    );
    expect(field, findsWidgets);
    await search(tester, '@id:files.exclude');
    expect(find.text('**/.git'), findsOneWidget);
  });

  testWidgets('without a source it says so', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Material(child: ExtensionSettingsPage())),
    );
    expect(
      find.text('Extension settings are not available yet.'),
      findsOneWidget,
    );
  });

  testWidgets('the settings dialog lists the page', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionSettingsScope(
          source: ExtensionSettingsSource(registry: registry, user: user),
          child: SettingsDialog(
            pageBuilder: (context, section) =>
                section == SettingsSection.extensionSettings
                ? const ExtensionSettingsPage()
                : Text('page ${section.name}'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Extension Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Acme Tools'), findsOneWidget);
  });

  testWidgets('renders (build/exthost-screens/settings_extensions.png)', (
    tester,
  ) async {
    final screens = Platform.environment['BAOCODE_EXTHOST_SCREENS'];
    if (screens != null) {
      await tester.runAsync(() async {
        for (final (family, path) in [
          ('Snapshot', '/System/Library/Fonts/Supplemental/Arial.ttf'),
          (AppFonts.mono, '/System/Library/Fonts/Menlo.ttc'),
          (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
        ]) {
          if (!File(path).existsSync()) continue;
          await (FontLoader(family)
                ..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
              .load();
        }
      });
    }
    user.values.addAll({
      'acme.port': 8080,
      'acme.args': ['--fast', '--verbose'],
    });
    workspace.values['acme.mode'] = 'thorough';
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> shoot(String name, Widget page) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: screens == null ? null : 'Snapshot'),
          home: RepaintBoundary(
            key: key,
            child: Material(color: AppColors.code, child: page),
          ),
        ),
      );
      await tester.pump();
      if (screens == null) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$screens/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    ExtensionSettingsSource source() => ExtensionSettingsSource(
      registry: registry,
      user: user,
      workspace: workspace,
      extensionNames: const {'acme.tools': 'Acme Tools'},
    );
    await shoot(
      'settings_extensions.png',
      ExtensionSettingsPage(key: const ValueKey(1), source: source()),
    );
    expect(find.text('Acme Tools'), findsOneWidget);
    await shoot(
      'settings_extensions_core.png',
      ExtensionSettingsPage(
        key: const ValueKey(2),
        source: source(),
        initialFilter: ExtensionSettingsFilter.core,
        initialQuery: 'editor tab',
      ),
    );
  });
}
