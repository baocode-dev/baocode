import 'dart:io';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/chat_width.dart';
import 'package:baocode/chat/widgets/chat_minimap.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/settings/pages/appearance_page.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  tearDown(() => ChatWidth.current.value = ChatWidth.fallback);

  test('settings.json\'s values: a width, full; unset or narrower is the '
      'default', () {
    expect(ChatWidth.parse(null), ChatWidth.fallback);
    expect(ChatWidth.parse('wide'), ChatWidth.fallback);
    expect(ChatWidth.parse(400), ChatWidth.fallback);
    expect(ChatWidth.parse(1040), 1040);
    expect(ChatWidth.parse('full'), double.infinity);
    expect(ChatWidth.setting(ChatWidth.fallback), isNull);
    expect(ChatWidth.setting(1040), 1040);
    expect(ChatWidth.setting(double.infinity), 'full');
    // A width set by hand shows at the step nearest it.
    expect(ChatWidth.stepOf(ChatWidth.fallback), 0);
    expect(ChatWidth.stepOf(1000), 2);
    expect(ChatWidth.stepOf(1600), 3);
    expect(ChatWidth.stepOf(double.infinity), 4);
  });

  testWidgets('the composer grows with the setting', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ChatSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(session: session),
      ),
    );
    double width() => tester.getSize(find.byType(ChatComposer).last).width;
    expect(width(), ChatWidth.fallback);
    ChatWidth.current.value = 1200;
    await tester.pump();
    expect(width(), 1200);
    ChatWidth.current.value = double.infinity;
    await tester.pump();
    // The window's width but its margins: the minimap's room is beside the
    // history only, not beside the composer.
    expect(width(), 1800 - 2 * 24);
    ChatMinimap.enabled.value = false;
    addTearDown(() => ChatMinimap.enabled.value = true);
    await tester.pump();
    expect(width(), 1800 - 2 * 24);
  });

  test('settings.json\'s chat.minimap: unset is on, only off is written', () {
    expect(ChatMinimap.parse(null), isTrue);
    expect(ChatMinimap.parse('x'), isTrue);
    expect(ChatMinimap.parse(false), isFalse);
    expect(ChatMinimap.setting(true), isNull);
    expect(ChatMinimap.setting(false), isFalse);
  });

  test('settings.json\'s chat.minimapGlass: a step, unset or not a number '
      'is 75%, only another is written', () {
    expect(ChatMinimap.parseGlass(null), 0.75);
    expect(ChatMinimap.parseGlass('x'), 0.75);
    expect(ChatMinimap.parseGlass(0), 0);
    expect(ChatMinimap.parseGlass(0.6), 0.5);
    expect(ChatMinimap.parseGlass(9), 1.5);
    expect(ChatMinimap.glassSetting(0.75), isNull);
    expect(ChatMinimap.glassSetting(1), 1);
    expect(ChatMinimap.glassSetting(0.25), 0.25);
  });

  test('settings.json\'s chat.minimapElasticity: a level\'s name, unset or '
      'another is subtle, only another level is written', () {
    expect(ChatMinimap.parseElasticity(null), ChatMinimapElasticity.subtle);
    expect(ChatMinimap.parseElasticity('x'), ChatMinimapElasticity.subtle);
    expect(ChatMinimap.parseElasticity('off'), ChatMinimapElasticity.off);
    expect(ChatMinimap.parseElasticity('bouncy'), ChatMinimapElasticity.bouncy);
    expect(ChatMinimap.elasticitySetting(ChatMinimapElasticity.subtle), isNull);
    expect(ChatMinimap.elasticitySetting(ChatMinimapElasticity.off), 'off');
    // Off, the edges go together; more of it, the edge behind lags more.
    expect(
      ChatMinimapElasticity.off.leading,
      ChatMinimapElasticity.off.trailing,
    );
    double lag(ChatMinimapElasticity level) =>
        1 / level.trailing - 1 / level.leading;
    for (var i = 1; i < ChatMinimapElasticity.values.length; i++) {
      expect(
        lag(ChatMinimapElasticity.values[i]),
        greaterThan(lag(ChatMinimapElasticity.values[i - 1])),
      );
    }
  });

  testWidgets('the slider picks a step, applied at once and kept in '
      'settings.json; the default is not written', (tester) async {
    // Tall enough for the whole page: one scrolled to its lower part trips
    // the semantics check as the code preview leaves the list's cache.
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('baocode-chat-width'),
    ))!;
    final settings = UserSettings(p.join(data.path, 'settings.json'));
    await tester.runAsync(settings.load);
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
    // The code font's dropdown shows Default too: the width's slider's only.
    expect(
      find.descendant(
        of: find.byType(SettingsSlider),
        matching: find.text('Default'),
      ),
      findsOneWidget,
    );
    // The width's slider: the page's first; the code size's and the text
    // size's come after it.
    final slider = find.descendant(
      of: find.byType(SettingsSlider).first,
      matching: find.byType(Slider),
    );
    await tester.tapAt(tester.getTopRight(slider) + const Offset(-4, 10));
    await tester.pump();
    expect(ChatWidth.current.value, double.infinity);
    expect(find.text('Full width'), findsOneWidget);
    await settle(tester, () => settings[ChatWidth.settingKey] == 'full');
    expect(settings[ChatWidth.settingKey], 'full');
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(4, 10));
    await tester.pump();
    expect(ChatWidth.current.value, ChatWidth.fallback);
    await settle(
      tester,
      () => !settings.values.containsKey(ChatWidth.settingKey),
    );
    expect(settings.values.containsKey(ChatWidth.settingKey), isFalse);
    // Dragging the thumb with the mouse picks nothing: only a click does.
    final drag = await tester.startGesture(
      tester.getTopLeft(slider) + const Offset(14, 10),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 8; i++) {
      await drag.moveTo(tester.getTopLeft(slider) + Offset(14 + i * 18.0, 10));
      await tester.pump();
      expect(ChatWidth.current.value, ChatWidth.fallback);
    }
    await drag.up();
    await tester.pump();
    expect(ChatWidth.current.value, ChatWidth.fallback);
    // Removed outside the test's fake clock, where its file IO can finish.
    await tester.runAsync(() => data.delete(recursive: true));
    // The settings page's code preview highlights on timers: leave it, and
    // let them finish, before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });
}

/// Lets settings.json's reads and writes finish: each is real IO, run in
/// the real clock, and the next starts once the fake clock pumps.
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

class _Themes extends ChangeNotifier implements IdeColorThemeController {
  @override
  List<IdeColorThemeEntry> get colorThemes => const [];

  @override
  String get colorThemeId => 'Dark 2026';

  @override
  Future<void> restoreColorTheme() async {}

  @override
  IdeColorThemeSelection get colorThemeSelection =>
      (id: colorThemeId, automatic: false);

  @override
  Future<void> setColorTheme(
    String id, {
    bool preview = false,
    bool automatic = false,
  }) async {}
}
