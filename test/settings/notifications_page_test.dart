import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/notifications/attention_host.dart';
import 'package:baocode/notifications/attention_settings.dart';
import 'package:baocode/settings/pages/notifications_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:path/path.dart' as p;

class _FakeHost implements AttentionHost {
  final List<Object> sounds = [];
  String? picked;

  @override
  Future<void> playSound({String? path, Uint8List? bytes}) async =>
      sounds.add(path ?? bytes!);

  @override
  Future<void> quit() async {}

  @override
  Future<String?> pickSound() async => picked;

  @override
  Future<void> notify({
    required String id,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> requestAttention() async {}

  @override
  Future<void> setBadge(int count) async {}

  @override
  Future<void> setTray(TrayState? state) async {}

  @override
  set onOpen(void Function(String? id)? handler) {}
}

void main() {
  late Directory data;
  late UserSettings settings;
  late _FakeHost host;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-notifications');
    settings = UserSettings(p.join(data.path, 'settings.json'));
    await settings.load();
    host = _FakeHost();
  });

  tearDown(() async {
    settings.dispose();
    await data.delete(recursive: true);
  });

  /// Lets the disk catch up until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('timed out');
  }

  testWidgets('choices are kept in settings.json, defaults unwritten', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationsSettingsPage(settings: settings, host: host),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Notify me when an agent needs me'), findsOneWidget);
    expect(find.text('Show the icon in the menu bar'), findsOneWidget);

    // A turn's end is not notified.
    await tester.tap(find.text('Finishes a turn'));
    await settle(tester, () => settings[AttentionSettings.eventsKey] is List);
    expect(settings[AttentionSettings.eventsKey], ['needsInput']);
    await tester.tap(find.text('Finishes a turn'));
    await settle(
      tester,
      () => !settings.values.containsKey(AttentionSettings.eventsKey),
    );

    Future<void> choose(Finder dropdown, String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    final when = find.byType(SettingsDropdown).first;
    await choose(when, 'Always');
    await settle(tester, () => settings[AttentionSettings.whenKey] == 'always');

    // A sound picked is heard; the default is not written.
    final sound = find.byType(SettingsDropdown).last;
    expect(tester.widget<SettingsDropdown>(sound).current, 'Microwave Ding');
    await choose(sound, 'None');
    await settle(tester, () => settings[AttentionSettings.soundKey] == 'none');
    expect(host.sounds, isEmpty);
    await tester.pump();
    expect(tester.widget<SettingsDropdown>(sound).current, 'None');

    host.picked = p.join(data.path, 'bell.wav');
    await choose(sound, 'Choose a File…');
    await settle(
      tester,
      () => settings[AttentionSettings.soundKey] == host.picked,
    );
    expect(host.sounds, [host.picked]);
    await tester.pump();
    expect(tester.widget<SettingsDropdown>(sound).current, 'bell');

    await choose(sound, 'Microwave Ding');
    await settle(
      tester,
      () => !settings.values.containsKey(AttentionSettings.soundKey),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(host.sounds.last, isA<Uint8List>());

    await tester.tap(find.text('Play'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(host.sounds, hasLength(3));

    await choose(sound, 'man-oh-yeah');
    await settle(
      tester,
      () =>
          settings[AttentionSettings.soundKey] ==
          NotificationSoundValue.manOhYeah,
    );
    await tester.pump();
    expect(tester.widget<SettingsDropdown>(sound).current, 'man-oh-yeah');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(host.sounds.last, isA<Uint8List>());
    expect((host.sounds.last as Uint8List).take(4), [82, 73, 70, 70]);

    await tester.tap(find.text('Play'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(host.sounds, hasLength(5));

    await choose(sound, 'Gulp Gulp Gulp Gulp');
    await settle(
      tester,
      () =>
          settings[AttentionSettings.soundKey] ==
          NotificationSoundValue.gulpGulpGulpGulp,
    );
    await tester.pump();
    expect(
      tester.widget<SettingsDropdown>(sound).current,
      'Gulp Gulp Gulp Gulp',
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final gulpBytes = File('assets/sounds/gulp-gulp-gulp-gulp.wav')
        .readAsBytesSync();
    expect(host.sounds.last, gulpBytes);

    await tester.tap(find.text('Play'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(host.sounds, hasLength(7));
    expect(host.sounds.last, gulpBytes);

    await tester.tap(find.text('Show the icon in the menu bar'));
    await settle(tester, () => settings[AttentionSettings.trayKey] == false);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
