import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ColorScheme;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/theme/workbench_theme.dart'
    show ColorThemeStorage, WorkbenchThemeService;

import '../lsp_ui/fake_language_features.dart';
import '../lsp_ui/lsp_test_helpers.dart';
import 'fake_files.dart';

/// VS Code's built-in color themes, out of order.
const _themes = [
  IdeColorThemeEntry(id: 'Red', label: 'Red', type: ColorScheme.dark),
  IdeColorThemeEntry(
    id: 'Solarized Light',
    label: 'Solarized Light',
    type: ColorScheme.light,
  ),
  IdeColorThemeEntry(id: 'Dark+', label: 'Dark+', type: ColorScheme.dark),
  IdeColorThemeEntry(
    id: 'Default High Contrast Light',
    label: 'Light High Contrast',
    type: ColorScheme.highContrastLight,
  ),
  IdeColorThemeEntry(id: 'Monokai', label: 'Monokai', type: ColorScheme.dark),
  IdeColorThemeEntry(
    id: 'Light Modern',
    label: 'Light Modern',
    type: ColorScheme.light,
  ),
  IdeColorThemeEntry(
    id: 'Dark 2026',
    label: 'Dark 2026',
    type: ColorScheme.dark,
  ),
  IdeColorThemeEntry(
    id: 'Tomorrow Night Blue',
    label: 'Tomorrow Night Blue',
    type: ColorScheme.dark,
  ),
  IdeColorThemeEntry(
    id: 'Default High Contrast',
    label: 'Dark High Contrast',
    type: ColorScheme.highContrastDark,
  ),
  IdeColorThemeEntry(
    id: 'Kimbie Dark',
    label: 'Kimbie Dark',
    type: ColorScheme.dark,
  ),
  IdeColorThemeEntry(
    id: 'Dark Modern',
    label: 'Dark Modern',
    type: ColorScheme.dark,
  ),
  IdeColorThemeEntry(
    id: 'Quiet Light',
    label: 'Quiet Light',
    type: ColorScheme.light,
  ),
  IdeColorThemeEntry(
    id: 'Monokai Dimmed',
    label: 'Monokai Dimmed',
    type: ColorScheme.dark,
  ),
  IdeColorThemeEntry(
    id: 'Light 2026',
    label: 'Light 2026',
    type: ColorScheme.light,
  ),
  IdeColorThemeEntry(
    id: 'Dark (Visual Studio)',
    label: 'Dark (Visual Studio)',
    type: ColorScheme.dark,
  ),
  IdeColorThemeEntry(id: 'Abyss', label: 'Abyss', type: ColorScheme.dark),
  IdeColorThemeEntry(
    id: 'Solarized Dark',
    label: 'Solarized Dark',
    type: ColorScheme.dark,
  ),
];

/// A theme service that records `preview <id>` and `apply <id>` calls.
class _FakeColorThemes implements IdeColorThemeController {
  _FakeColorThemes([
    this.colorThemeId = 'Dark Modern',
    this.colorThemes = _themes,
  ]);

  @override
  final List<IdeColorThemeEntry> colorThemes;

  @override
  String colorThemeId;

  final List<String> calls = [];

  @override
  Future<void> setColorTheme(String id, {bool preview = false}) async {
    calls.add('${preview ? 'preview' : 'apply'} $id');
    colorThemeId = id;
  }
}

/// Records the themes kept.
class _Storage implements ColorThemeStorage {
  final List<String> kept = [];

  @override
  String? get colorThemeSetting => kept.lastOrNull;

  @override
  String? get colorThemeData => null;

  @override
  void storeColorTheme({required String setting, String? data}) =>
      kept.add(setting);
}

const _files = {'lib/main.dart': 'void main() {}\n'};

const _waiting = '(Ctrl+K) was pressed. Waiting for second key of chord...';

Finder get _picker => find.byType(IdeQuickInput);

Finder get _input =>
    find.descendant(of: _picker, matching: find.byType(TextField));

/// The row texts in order: each label (with its description), then its
/// separator's label.
List<String> _rows(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.descendant(of: _picker, matching: find.byType(ListView)),
      matching: find.byType(Text),
    ),
  ))
    text.textSpan?.toPlainText() ?? text.data!,
];

/// The separators drawn as a line above their row.
int _separatorLines(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.descendant(of: _picker, matching: find.byType(ListView)),
        matching: find.byType(DecoratedBox),
      ),
    )
    .where(
      (box) => switch (box.decoration) {
        BoxDecoration(:final border?) => border.top != BorderSide.none,
        _ => false,
      },
    )
    .length;

String? _active(WidgetTester tester) =>
    tester.state<IdeQuickInputState>(_picker).activeItem?.label;

/// Presses [key], then runs what is due now (applying a theme waits for a
/// zero timeout, as upstream).
Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(Duration.zero);
}

/// Ctrl+K Ctrl+T.
Future<void> _openPicker(WidgetTester tester) async {
  await chord(tester, LogicalKeyboardKey.keyK, control: true);
  await chord(tester, LogicalKeyboardKey.keyT, control: true);
}

void main() {
  test('lists light, dark and high contrast themes as upstream sorts them', () {
    final pick = ideColorThemePick(_FakeColorThemes());
    expect(
      [
        for (final entry in pick.items)
          switch (entry) {
            IdeQuickPickSeparator(:final label) => '-- $label',
            IdeQuickPickItem(:final label, :final description) =>
              description == null ? label : '$label ($description)',
          },
      ],
      [
        '-- light themes',
        'Quiet Light (Default Light)',
        'Light 2026',
        'Light Modern',
        'Solarized Light',
        '-- dark themes',
        'Monokai (Default Dark)',
        'Abyss',
        'Dark (Visual Studio)',
        'Dark 2026',
        'Dark Modern',
        'Dark+',
        'Kimbie Dark',
        'Monokai Dimmed',
        'Red',
        'Solarized Dark',
        'Tomorrow Night Blue',
        '-- high contrast themes',
        'Dark High Contrast (Default High Contrast)',
        'Light High Contrast (Default High Contrast Light)',
      ],
    );
    expect(
      pick.placeholder,
      'Select Color Theme (detect system color mode disabled)',
    );
    expect(pick.activeItems!.single.label, 'Dark Modern');
    // No group for a type without themes.
    final darkOnly = ideColorThemePick(
      _FakeColorThemes('Red', [
        for (final theme in _themes)
          if (theme.type == ColorScheme.dark) theme,
      ]),
    );
    expect(
      [
        for (final separator
            in darkOnly.items.whereType<IdeQuickPickSeparator>())
          separator.label,
      ],
      ['dark themes'],
    );
  });

  testWidgets('Ctrl+K Ctrl+T opens the picker from the workbench, with '
      'separators and the current theme active', (tester) async {
    final themes = _FakeColorThemes();
    await pumpWorkbench(tester, _files, colorThemes: themes);

    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    expect(find.text(_waiting), findsOneWidget);
    expect(_picker, findsNothing);
    await chord(tester, LogicalKeyboardKey.keyT, control: true);
    expect(_picker, findsOneWidget);
    expect(find.text(_waiting), findsNothing);
    expect(
      find.descendant(
        of: _picker,
        matching: find.text(
          'Select Color Theme (detect system color mode disabled)',
        ),
      ),
      findsOneWidget,
    );
    // The list builds the rows it shows.
    expect(_rows(tester).take(16), [
      'Quiet Light  Default Light',
      'light themes',
      'Light 2026',
      'Light Modern',
      'Solarized Light',
      'Monokai  Default Dark',
      'dark themes',
      'Abyss',
      'Dark (Visual Studio)',
      'Dark 2026',
      'Dark Modern',
      'Dark+',
      'Kimbie Dark',
      'Monokai Dimmed',
      'Red',
      'Solarized Dark',
    ]);
    // A line above each group but the first.
    expect(_separatorLines(tester), 1);
    expect(_active(tester), 'Dark Modern');

    // Upstream reports the active item as the picker shows: the current
    // theme is previewed again after 200ms.
    await tester.pump(const Duration(milliseconds: 199));
    expect(themes.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(themes.calls, ['preview Dark Modern']);

    await _key(tester, LogicalKeyboardKey.pageDown);
    expect(_rows(tester).skip(_rows(tester).length - 4), [
      'Tomorrow Night Blue',
      'Dark High Contrast  Default High Contrast',
      'high contrast themes',
      'Light High Contrast  Default High Contrast Light',
    ]);
    expect(_separatorLines(tester), 2);

    await _key(tester, LogicalKeyboardKey.escape);
    expect(_picker, findsNothing);
    expect(themes.calls, ['preview Dark Modern', 'apply Dark Modern']);
  });

  testWidgets('the palette lists Preferences: Color Theme with its chord and '
      'opens the picker', (tester) async {
    final themes = _FakeColorThemes('Abyss');
    await pumpWorkbench(
      tester,
      _files,
      open: ['lib/main.dart'],
      colorThemes: themes,
    );
    final command = workbenchState(tester).commands
        .firstWhere((command) => command.id == 'workbench.action.selectTheme');
    expect(command.title, 'Preferences: Color Theme');
    expect(command.shortcutLabel(mac: true), '⌘K ⌘T');
    expect(command.shortcutLabel(mac: false), 'Ctrl+K Ctrl+T');

    await chord(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
    await tester.enterText(_input, '>color theme');
    await tester.pump();
    expect(
      find.descendant(of: _picker, matching: find.text('Ctrl+K Ctrl+T')),
      findsOneWidget,
    );
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_picker, findsOneWidget);
    expect(_active(tester), 'Abyss');
    expect(tester.widget<TextField>(_input).controller!.text, isEmpty);
    await _key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(themes.calls, ['apply Abyss']);
  });

  testWidgets('macOS labels and presses the chord with ⌘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final themes = _FakeColorThemes();
    await pumpWorkbench(tester, _files, colorThemes: themes);
    runCommand(tester, 'workbench.action.showCommands');
    await tester.pump();
    await tester.enterText(_input, '>color theme');
    await tester.pump();
    expect(
      find.descendant(of: _picker, matching: find.text('⌘K ⌘T')),
      findsOneWidget,
    );
    await _key(tester, LogicalKeyboardKey.escape);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await _key(tester, LogicalKeyboardKey.keyK);
    expect(
      find.text('(⌘K) was pressed. Waiting for second key of chord...'),
      findsOneWidget,
    );
    await _key(tester, LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(_active(tester), 'Dark Modern');
    await _key(tester, LogicalKeyboardKey.escape);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('arrow and page keys preview after upstream\'s 200ms; Enter '
      'applies and persists', (tester) async {
    final themes = _FakeColorThemes();
    await pumpWorkbench(tester, _files, colorThemes: themes);
    await _openPicker(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(themes.calls, ['preview Dark Modern']);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_active(tester), 'Dark+');
    await tester.pump(const Duration(milliseconds: 100));
    // A newer active item replaces the pending preview.
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_active(tester), 'Kimbie Dark');
    await tester.pump(const Duration(milliseconds: 200));
    expect(themes.calls, ['preview Dark Modern', 'preview Kimbie Dark']);

    await _key(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 200));
    await _key(tester, LogicalKeyboardKey.pageDown);
    expect(_active(tester), 'Light High Contrast');
    await tester.pump(const Duration(milliseconds: 200));
    await _key(tester, LogicalKeyboardKey.pageUp);
    expect(_active(tester), 'Solarized Light');
    await tester.pump(const Duration(milliseconds: 200));
    expect(themes.calls, [
      'preview Dark Modern',
      'preview Kimbie Dark',
      'preview Dark+',
      'preview Default High Contrast Light',
      'preview Solarized Light',
    ]);

    // Enter applies at once, dropping the pending preview.
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_active(tester), 'Monokai');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_picker, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(themes.calls.skip(5), ['apply Monokai']);

    // A click on a row applies its theme too.
    await _openPicker(tester);
    expect(_active(tester), 'Monokai');
    await tester.tap(
      find.descendant(of: _picker, matching: find.text('Abyss')),
    );
    await tester.pump();
    expect(_picker, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(themes.calls.skip(6), ['apply Abyss']);
  });

  testWidgets('Escape, a click outside or another quick input restores the '
      'theme the picker started with', (tester) async {
    final themes = _FakeColorThemes();
    await pumpWorkbench(tester, _files, colorThemes: themes);
    await _openPicker(tester);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(themes.calls, ['preview Dark+']);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(_picker, findsNothing);
    expect(themes.calls, ['preview Dark+', 'apply Dark Modern']);

    // A click outside, before the preview ran.
    themes.calls.clear();
    await _openPicker(tester);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await tester.tapAt(const Offset(700, 700));
    await tester.pump();
    expect(_picker, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(themes.calls, ['apply Dark Modern']);

    // Quick Open replaces the picker.
    themes.calls.clear();
    await _openPicker(tester);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 200));
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pump(Duration.zero);
    expect(
      find.descendant(
        of: _picker,
        matching: find.textContaining('Search files by name'),
      ),
      findsOneWidget,
    );
    expect(themes.calls, ['preview Dark 2026', 'apply Dark Modern']);
    await _key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(themes.calls, hasLength(2));
  });

  testWidgets('filtering matches labels and descriptions, sorts matches by '
      'label without separators and previews the first', (tester) async {
    final themes = _FakeColorThemes();
    await pumpWorkbench(tester, _files, colorThemes: themes);
    await _openPicker(tester);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(_input, 'dark');
    await tester.pump();
    expect(_rows(tester), [
      'Dark+',
      'Dark 2026',
      'Dark Modern',
      'Dark High Contrast  Default High Contrast',
      'Dark (Visual Studio)',
      'Kimbie Dark',
      'Solarized Dark',
      'Monokai  Default Dark',
    ]);
    expect(_active(tester), 'Dark+');
    final highlighted = <String>[];
    tester
        .widget<Text>(
          find.descendant(of: _picker, matching: find.text('Dark+')),
        )
        .textSpan!
        .visitChildren((span) {
          if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) {
            highlighted.add(span.text!);
          }
          return true;
        });
    expect(highlighted.join(), 'Dark');
    await tester.pump(const Duration(milliseconds: 200));
    expect(themes.calls, ['preview Dark Modern', 'preview Dark+']);

    // Descriptions match too; camel case humps as well.
    await tester.enterText(_input, 'default');
    await tester.pump();
    expect(_rows(tester), [
      'Quiet Light  Default Light',
      'Monokai  Default Dark',
      'Dark High Contrast  Default High Contrast',
      'Light High Contrast  Default High Contrast Light',
    ]);
    await tester.enterText(_input, 'tnb');
    await tester.pump();
    expect(_rows(tester), ['Tomorrow Night Blue']);

    // Nothing matches: nothing is active, and the current theme is
    // previewed; Enter only closes.
    await tester.enterText(_input, 'zzz');
    await tester.pump();
    expect(_rows(tester), isEmpty);
    expect(_active(tester), isNull);
    await tester.pump(const Duration(milliseconds: 200));
    expect(themes.calls.last, 'preview Dark Modern');
    final count = themes.calls.length;
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_picker, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(themes.calls, hasLength(count));

    // Clearing the filter lists the groups again.
    await _openPicker(tester);
    await tester.enterText(_input, 'red');
    await tester.pump();
    await tester.enterText(_input, '');
    await tester.pump();
    expect(_rows(tester), contains('dark themes'));
    expect(_active(tester), 'Quiet Light');
    await _key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the editor hands Ctrl+K Ctrl+T to the workbench and keeps '
      'its own chords; unbound ones are swallowed', (tester) async {
    final themes = _FakeColorThemes();
    final languages = FakeLanguageFeatures();
    addTearDown(languages.dispose);
    final workspace = await pumpWorkbench(
      tester,
      _files,
      open: ['lib/main.dart'],
      nativeEditor: true,
      languages: languages,
      colorThemes: themes,
    );
    await tester.pump();
    editorState(tester).focus();
    await tester.pump();
    expect(editorState(tester).languageSession, isNotNull);

    await press(tester, LogicalKeyboardKey.keyK, primary: true);
    expect(find.text(_waiting), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyT, primary: true);
    expect(_picker, findsOneWidget);
    expect(find.text(_waiting), findsNothing);
    // Closed before the first preview was due.
    await _key(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    expect(_picker, findsNothing);
    expect(themes.calls, ['apply Dark Modern']);

    // The editor's own chord (Show Hover) says nothing.
    await press(tester, LogicalKeyboardKey.keyK, primary: true);
    await press(tester, LogicalKeyboardKey.keyI, primary: true);
    expect(find.textContaining('was pressed'), findsNothing);
    expect(find.textContaining('is not a command'), findsNothing);

    await press(tester, LogicalKeyboardKey.keyK, primary: true);
    await press(tester, LogicalKeyboardKey.keyX);
    expect(
      find.text('The key combination (Ctrl+K, X) is not a command.'),
      findsOneWidget,
    );
    expect(workspace.active!.model.snapshot.text, 'void main() {}\n');
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('is not a command'), findsNothing);
  });

  testWidgets('chord mode ends after 5 seconds; unbound chords are not '
      'commands', (tester) async {
    final themes = _FakeColorThemes();
    await pumpWorkbench(tester, _files, colorThemes: themes);
    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pump(const Duration(milliseconds: 4500));
    expect(find.text(_waiting), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_waiting), findsNothing);
    await chord(tester, LogicalKeyboardKey.keyT, control: true);
    expect(_picker, findsNothing);

    // Modifiers alone wait for the second key.
    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    await _key(tester, LogicalKeyboardKey.shiftLeft);
    await chord(tester, LogicalKeyboardKey.keyY, control: true);
    expect(
      find.text('The key combination (Ctrl+K, Ctrl+Y) is not a command.'),
      findsOneWidget,
    );
    expect(_picker, findsNothing);
    expect(themes.calls, isEmpty);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('with the workbench theme service: previews, restores and '
      'keeps the choice', (tester) async {
    final themes = WorkbenchThemeService.instance;
    final storage = _Storage();
    themes.storage = storage;
    await tester.runAsync(themes.initialize);
    storage.kept.clear();
    await pumpWorkbench(tester, _files, colorThemes: themes);

    // Loading a theme reads its file: let that run.
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    await _openPicker(tester);
    expect(_active(tester), 'Dark 2026');
    for (var i = 0; i < 4; i++) {
      await _key(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_active(tester), 'Solarized Light');
    await settle();
    expect(themes.colorThemeId, 'Solarized Light');
    expect(themes.colors.dark, isFalse);
    expect(storage.kept, isEmpty, reason: 'a preview is not kept');
    await _key(tester, LogicalKeyboardKey.escape);
    await settle();
    expect(themes.colorThemeId, 'Dark 2026');

    await _openPicker(tester);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_active(tester), 'Dark Modern');
    await _key(tester, LogicalKeyboardKey.enter);
    await settle();
    expect(_picker, findsNothing);
    expect(themes.colorThemeId, 'Dark Modern');
    expect(storage.kept.last, 'Dark Modern');
  });

  testWidgets('without color themes the command is disabled', (tester) async {
    await pumpWorkbench(tester, _files);
    final command = workbenchState(tester).commands
        .firstWhere((command) => command.id == 'workbench.action.selectTheme');
    expect(command.enabled, isFalse);
    await chord(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
    await tester.enterText(_input, '>color theme');
    await tester.pump();
    expect(
      find.descendant(of: _picker, matching: find.text('No matching commands')),
      findsOneWidget,
    );
    await _key(tester, LogicalKeyboardKey.escape);
    // Other commands start with Ctrl+K; Ctrl+K Ctrl+T runs none.
    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    await chord(tester, LogicalKeyboardKey.keyT, control: true);
    expect(_picker, findsNothing);
    expect(find.byType(IdeWorkbench), findsOneWidget);
  });
}
