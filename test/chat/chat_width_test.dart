import 'dart:io';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/chat_width.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/settings/pages/appearance_page.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
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
    // The window's width but its margins.
    expect(width(), 1800 - 2 * 24);
  });

  testWidgets('the slider picks a step, applied at once and kept in '
      'settings.json; the default is not written', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = await Directory.systemTemp.createTemp('baocode-chat-width');
    final settings = UserSettings(p.join(data.path, 'settings.json'));
    await tester.runAsync(settings.load);
    addTearDown(() async {
      settings.dispose();
      await data.delete(recursive: true);
    });
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
    expect(find.text('Default'), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.tapAt(tester.getCenter(slider) + const Offset(200, 0));
    await tester.pump();
    expect(ChatWidth.current.value, double.infinity);
    expect(find.text('Full width'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(settings[ChatWidth.settingKey], 'full');
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(4, 10));
    await tester.pump();
    expect(ChatWidth.current.value, ChatWidth.fallback);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(settings.values.containsKey(ChatWidth.settingKey), isFalse);
  });
}

class _Themes extends ChangeNotifier implements IdeColorThemeController {
  @override
  List<IdeColorThemeEntry> get colorThemes => const [];

  @override
  String get colorThemeId => 'Dark 2026';

  @override
  Future<void> setColorTheme(String id, {bool preview = false}) async {}
}
