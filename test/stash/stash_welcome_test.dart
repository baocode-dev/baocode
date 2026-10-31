import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/platform/app_platform.dart';
import 'package:baocode/settings/pages/stash_hotkey_field.dart';
import 'package:baocode/stash/stash_controller.dart';
import 'package:baocode/stash/stash_disk.dart';
import 'package:baocode/stash/stash_host.dart';
import 'package:baocode/stash/stash_settings.dart';
import 'package:baocode/stash/stash_store.dart';
import 'package:baocode/stash/stash_welcome.dart';
import 'package:baocode/tips/welcome_dialog.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, Object?> settings;
  late ChangeNotifier settingsChanges;
  late StashController controller;

  setUp(() {
    settings = {};
    settingsChanges = ChangeNotifier();
    controller = StashController(
      store: StashStore(MemoryStashDisk()),
      workspace: Workspace.mock(),
      host: StashHost(channel: const MethodChannel('test/stash-welcome')),
      settings: () => settings,
      updateSetting: (key, value) async {
        if (value == null) {
          settings.remove(key);
        } else {
          settings[key] = value;
        }
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        settingsChanges.notifyListeners();
      },
      settingsChanges: settingsChanges,
    );
  });

  tearDown(() => controller.dispose());

  Future<({Future<void> closed})> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    final closed = showStashWelcome(context, controller: controller);
    await tester.pump();
    // In, the cards then the lines.
    await tester.pump(const Duration(milliseconds: 1500));
    // In, what goes on moves on the shared clock's frames, not every vsync.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
    return (closed: closed);
  }

  String label(String hotkey) =>
      StashSettings.label(hotkey, mac: AppPlatform.isMacOS);

  testWidgets('says what Stash is and asks for its shortcut: the one '
      'suggested a click away, kept in the settings', (tester) async {
    final (:closed) = await open(tester);
    expect(find.text('Meet Stash'), findsOneWidget);
    expect(find.text('Note it down'), findsOneWidget);
    expect(find.text('Hand it to an agent'), findsOneWidget);
    expect(find.text('See how it goes'), findsOneWidget);
    expect(find.text('Set a shortcut to note things down'), findsOneWidget);
    expect(find.textContaining('set it later in Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final suggested = label(StashSettings.suggestedHotkey);
    // Under the lines, scrolled to in a short window.
    await tester.ensureVisible(find.text('Use $suggested'));
    await tester.tap(find.text('Use $suggested'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings[StashSettings.hotkeyKey], StashSettings.suggestedHotkey);
    expect(find.text('Shortcut set'), findsOneWidget);
    expect(find.textContaining('Press $suggested in any app'), findsOneWidget);
    expect(find.textContaining('set it later in Settings'), findsNothing);
    // On the field, and in the picture.
    expect(find.text(suggested), findsNWidgets(2));

    await tester.tap(find.text('Get Started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await closed;
    expect(find.text('Meet Stash'), findsNothing);
  });

  testWidgets('wider than tall, its picture beside the text; a click '
      'beside it does not close it', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(
      find
          .descendant(
            of: find.byType(WelcomeFrame),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(card.width, greaterThan(card.height));
    // The title on the right half, the picture on the left.
    final title = tester.getRect(find.text('Meet Stash'));
    expect(title.left, greaterThan(card.center.dx));

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Meet Stash'), findsOneWidget);
  });

  testWidgets('the shortcut recorded in place; Escape there stops the '
      'recording, not the dialog', (tester) async {
    final (:closed) = await open(tester);
    final field = find.byType(StashHotkeyField);
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pump();
    expect(find.text('Press the keys…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Meet Stash'), findsOneWidget);
    expect(settings, isEmpty);

    await tester.tap(field);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings[StashSettings.hotkeyKey], 'alt+k');
    expect(find.text('Shortcut set'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await closed;
    expect(find.text('Meet Stash'), findsNothing);
  });
}
