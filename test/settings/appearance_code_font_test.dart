import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/chat/reply_scroll.dart';
import 'package:baocode/chat/user_message_style.dart';
import 'package:baocode/chat/widgets/chat_minimap.dart';
import 'package:baocode/chat/widgets/pixel_loader.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/settings/pages/appearance_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/window_blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    CodeFont.families.value = CodeFont.defaultFamilies;
    CodeFont.size.value = CodeFont.defaultSize;
    CodeFont.ligatures.value = true;
    CodeFont.uiScale.value = CodeFont.defaultUiScale;
    CodeFont.terminalSize.value = null;
    UserMessageStyle.current.value = UserMessageStyle.sticky;
    ReplyScroll.current.value = ReplyScroll.follow;
    ChatMinimap.enabled.value = true;
    ChatMinimap.glass.value = ChatMinimap.defaultGlass;
    ChatMinimap.elasticity.value = ChatMinimap.defaultElasticity;
    for (final role in PixelLoaderRole.values) {
      role.style.value = PixelLoaderStyle.fill;
      role.speed.value = role.defaultSpeed;
    }
  });

  Future<_RecordingSettings> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _RecordingSettings();
    addTearDown(settings.dispose);
    final themes = _Themes();
    await tester.pumpWidget(
      MaterialApp(
        // Its loaders' previews still, for the page to settle.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
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
    // The color theme's dropdown comes first, then the user messages', the
    // reply's scroll, the two loaders', then the code font's.
    final dropdown = find.byType(SettingsDropdown).at(5);
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

  testWidgets('the user messages\' style is kept in settings.json; the '
      'default is removed from it', (tester) async {
    // The app's default (tests start in sticky).
    UserMessageStyle.current.value = UserMessageStyle.bubble;
    final settings = await pumpPage(tester);
    final dropdown = find.byType(SettingsDropdown).at(1);
    Future<void> choose(String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Full width, sticks to the top');
    expect(UserMessageStyle.current.value, UserMessageStyle.sticky);
    expect(settings.written[UserMessageStyle.settingKey], 'sticky');

    await choose('Chat bubbles');
    expect(UserMessageStyle.current.value, UserMessageStyle.bubble);
    expect(settings.written.containsKey(UserMessageStyle.settingKey), isTrue);
    expect(settings.written[UserMessageStyle.settingKey], isNull);
    await leave(tester);
  });

  testWidgets('where a conversation stays as a reply comes is kept in '
      'settings.json; the default is removed from it', (tester) async {
    final settings = await pumpPage(tester);
    final dropdown = find.byType(SettingsDropdown).at(2);
    Future<void> choose(String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    expect(find.text('Automatic'), findsOneWidget);
    await choose('Stay at its start');
    expect(ReplyScroll.current.value, ReplyScroll.start);
    expect(settings.written[ReplyScroll.settingKey], 'start');

    await choose('Automatic');
    expect(ReplyScroll.current.value, ReplyScroll.follow);
    expect(settings.written.containsKey(ReplyScroll.settingKey), isTrue);
    expect(settings.written[ReplyScroll.settingKey], isNull);
    await leave(tester);
  });

  testWidgets('the minimap\'s glass opacity is kept in settings.json, the '
      'default removed from it; no slider with the minimap off', (
    tester,
  ) async {
    final settings = await pumpPage(tester);
    Finder slider() => find.byWidgetPredicate(
      (widget) =>
          widget is SettingsSlider &&
          widget.semanticLabel.startsWith('Minimap glass opacity'),
    );
    expect(tester.widget<SettingsSlider>(slider()).label, '75%');
    tester
        .widget<SettingsSlider>(slider())
        .onChanged(ChatMinimap.glassSteps.indexOf(0.5));
    await tester.pump();
    expect(ChatMinimap.glass.value, 0.5);
    expect(settings.written[ChatMinimap.glassKey], 0.5);
    expect(tester.widget<SettingsSlider>(slider()).label, '50%');
    tester
        .widget<SettingsSlider>(slider())
        .onChanged(ChatMinimap.glassSteps.indexOf(0.75));
    await tester.pump();
    expect(settings.written.containsKey(ChatMinimap.glassKey), isTrue);
    expect(settings.written[ChatMinimap.glassKey], isNull);

    ChatMinimap.enabled.value = false;
    await tester.pump();
    expect(slider(), findsNothing);
    await leave(tester);
  });

  testWidgets('the minimap\'s glass elasticity is kept in settings.json, the '
      'default removed from it', (tester) async {
    final settings = await pumpPage(tester);
    SettingsSlider slider() => tester.widget<SettingsSlider>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SettingsSlider &&
            widget.semanticLabel.startsWith('Minimap glass elasticity'),
      ),
    );
    expect(slider().label, 'Subtle');
    slider().onChanged(ChatMinimapElasticity.bouncy.index);
    await tester.pump();
    expect(ChatMinimap.elasticity.value, ChatMinimapElasticity.bouncy);
    expect(settings.written[ChatMinimap.elasticityKey], 'bouncy');
    expect(slider().label, 'Bouncy');
    slider().onChanged(ChatMinimapElasticity.subtle.index);
    await tester.pump();
    expect(settings.written.containsKey(ChatMinimap.elasticityKey), isTrue);
    expect(settings.written[ChatMinimap.elasticityKey], isNull);
    await leave(tester);
  });

  testWidgets('an agent\'s and a subagent\'s loaders are picked and paced '
      'apart, kept in settings.json; the defaults are removed from it', (
    tester,
  ) async {
    final settings = await pumpPage(tester);
    // After the color theme's, the user messages' and the reply's scroll:
    // the agent's, then the subagent's.
    Future<void> choose(int dropdown, String label) async {
      await tester.tap(find.byType(SettingsDropdown).at(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    expect(find.text('Fill and empty'), findsNWidgets(2));
    await choose(3, 'Pixel rain');
    expect(PixelLoaderRole.agent.style.value, PixelLoaderStyle.rain);
    expect(PixelLoaderRole.subagent.style.value, PixelLoaderStyle.fill);
    expect(settings.written['chat.agentLoadingStyle'], 'rain');

    SettingsSlider speed(String what) => tester.widget<SettingsSlider>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SettingsSlider &&
            widget.semanticLabel.startsWith('$what speed'),
      ),
    );
    expect(speed('Subagent Running').label, '1.3×');
    speed('Subagent Running').onChanged(PixelLoaderRole.speeds.indexOf(2.0));
    await tester.pump();
    expect(PixelLoaderRole.subagent.speed.value, 2.0);
    expect(settings.written['chat.subagentLoadingSpeed'], 2.0);
    expect(speed('Subagent Running').label, '2×');
    speed('Subagent Running').onChanged(PixelLoaderRole.speeds.indexOf(1.3));
    await tester.pump();
    expect(settings.written.containsKey('chat.subagentLoadingSpeed'), isTrue);
    expect(settings.written['chat.subagentLoadingSpeed'], isNull);

    // The ring keeps its own pace: no slider for it.
    await choose(3, 'Ring (classic)');
    expect(settings.written['chat.agentLoadingStyle'], 'circle');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SettingsSlider &&
            widget.semanticLabel.startsWith('Agent Working speed'),
      ),
      findsNothing,
    );
    await choose(3, 'Fill and empty');
    expect(settings.written.containsKey('chat.agentLoadingStyle'), isTrue);
    expect(settings.written['chat.agentLoadingStyle'], isNull);
    await leave(tester);
  });

  testWidgets('the terminal follows the interface size until Custom '
      'is chosen, which shows a size slider; following again removes it', (
    tester,
  ) async {
    final settings = await pumpPage(tester);
    final dropdown = find.byType(SettingsDropdown).last;
    Finder shown(String text) =>
        find.descendant(of: dropdown, matching: find.text(text));
    Finder slider() => find.byWidgetPredicate(
      (widget) =>
          widget is SettingsSlider &&
          widget.semanticLabel.startsWith('Terminal font size'),
    );
    expect(shown('Follow Interface Size'), findsOneWidget);
    expect(slider(), findsNothing);
    Future<void> choose(String label) async {
      await tester.ensureVisible(dropdown);
      // Laid out where it was scrolled to, before the tap.
      await tester.pump();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Custom');
    // It starts at the size it followed.
    expect(CodeFont.terminalSize.value, 13);
    expect(settings.written[CodeFont.terminalSizeSettingKey], 13);
    expect(shown('Custom'), findsOneWidget);
    expect(slider(), findsOneWidget);

    tester
        .widget<SettingsSlider>(slider())
        .onChanged(CodeFont.sizeSteps.indexOf(16));
    await tester.pump();
    expect(CodeFont.terminalSize.value, 16);
    expect(settings.written[CodeFont.terminalSizeSettingKey], 16);
    expect(tester.widget<SettingsSlider>(slider()).label, '16');

    await choose('Follow Interface Size');
    expect(CodeFont.terminalSize.value, isNull);
    expect(
      settings.written.containsKey(CodeFont.terminalSizeSettingKey),
      isTrue,
    );
    expect(settings.written[CodeFont.terminalSizeSettingKey], isNull);
    expect(slider(), findsNothing);
    await leave(tester);
  });

  testWidgets('the terminal preview is drawn at the terminal\'s size', (
    tester,
  ) async {
    await pumpPage(tester);
    double previewSize() => tester
        .widget<RichText>(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('git status -s'),
          ),
        )
        .text
        .style!
        .fontSize!;
    expect(previewSize(), 13);
    CodeFont.terminalSize.value = 20;
    await tester.pump();
    expect(previewSize(), 20);
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

  testWidgets('the windows\' blur is off until switched on in settings.json', (
    tester,
  ) async {
    addTearDown(() => WindowBlur.enabled.value = false);
    final settings = await pumpPage(tester);
    expect(WindowBlur.enabled.value, isFalse);
    expect(AppColors.sidebarSurface.a, 1);
    await tester.tap(find.text('Native Window Blur'));
    await tester.pump();
    expect(WindowBlur.enabled.value, isTrue);
    expect(settings.written[WindowBlur.settingKey], isTrue);
    expect(AppColors.sidebarSurface.a, lessThan(1));

    await tester.tap(find.text('Native Window Blur'));
    await tester.pump();
    expect(WindowBlur.enabled.value, isFalse);
    expect(settings.written.containsKey(WindowBlur.settingKey), isTrue);
    expect(settings.written[WindowBlur.settingKey], isNull);
    await leave(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
