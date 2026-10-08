import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/settings/pages/appearance_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    CodeFont.families.value = CodeFont.defaultFamilies;
    CodeFont.size.value = CodeFont.defaultSize;
    CodeFont.ligatures.value = true;
    CodeFont.uiScale.value = CodeFont.defaultUiScale;
  });

  Future<_RecordingSettings> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _RecordingSettings();
    addTearDown(settings.dispose);
    final themes = _Themes();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppearanceSettingsPage(
            themes: themes,
            changes: themes,
            settings: settings,
          ),
        ),
      ),
    );
    return settings;
  }

  testWidgets('a code font preset is kept in settings.json; the default is '
      'removed from it', (tester) async {
    final settings = await pumpPage(tester);
    // The color theme's dropdown comes first, then the code font's.
    final dropdown = find.byType(SettingsDropdown).at(1);
    Future<void> choose(String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Consolas');
    expect(CodeFont.families.value.first, 'Consolas');
    expect(
      settings.written[CodeFont.familySettingKey],
      'Consolas, JetBrains Mono, Fira Code, Menlo, Cascadia Mono',
    );

    await choose('Default');
    expect(CodeFont.families.value, CodeFont.defaultFamilies);
    expect(settings.written.containsKey(CodeFont.familySettingKey), isTrue);
    expect(settings.written[CodeFont.familySettingKey], isNull);
    await leave(tester);
  });

  testWidgets('ligatures are switched in settings.json; on is removed from '
      'it', (tester) async {
    final settings = await pumpPage(tester);
    await tester.tap(find.text('Font Ligatures'));
    await tester.pump();
    expect(CodeFont.ligatures.value, isFalse);
    expect(settings.written[CodeFont.ligaturesSettingKey], isFalse);

    await tester.tap(find.text('Font Ligatures'));
    await tester.pump();
    expect(CodeFont.ligatures.value, isTrue);
    expect(settings.written.containsKey(CodeFont.ligaturesSettingKey), isTrue);
    expect(settings.written[CodeFont.ligaturesSettingKey], isNull);
    await leave(tester);
  });

  testWidgets(
    'the preview is the sample alone: no gutter, guides or scrolling',
    (tester) async {
      await pumpPage(tester);
      final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
      expect(surface.lineNumbers, isFalse);
      expect(surface.glyphMargin, isFalse);
      expect(surface.folding, isFalse);
      expect(surface.indentGuides, isFalse);
      expect(surface.scrollBeyondLastLine, isFalse);
      await leave(tester);
    },
  );
}

/// Leaves the page, then lets the editor's highlighting finish: its
/// tokenizer's timers outlive the page otherwise.
Future<void> leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 20));
}

/// settings.json as the page writes it: the value each key was last given,
/// null when it was removed. The file's own reads and writes are JsoncFile's
/// tests'.
class _RecordingSettings extends UserSettings {
  _RecordingSettings() : super('/unused/settings.json');

  final written = <String, Object?>{};

  @override
  Future<void> update(String key, Object? value) async {
    written[key] = value;
  }
}

class _Themes extends ChangeNotifier implements IdeColorThemeController {
  @override
  List<IdeColorThemeEntry> get colorThemes => const [];

  @override
  String get colorThemeId => 'Dark 2026';

  @override
  Future<void> setColorTheme(String id, {bool preview = false}) async {}
}
