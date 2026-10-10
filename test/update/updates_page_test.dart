import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/ide/ide_button.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/pages/updates_page.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/update/update_controller.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/update/update_settings.dart';
import 'package:baocode/update/version.dart';

import 'update_fakes.dart';

void main() {
  final l10n = englishLocalizations;
  late Directory data;
  late UserSettings settings;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-updates-page');
    settings = UserSettings(p.join(data.path, 'settings.json'));
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await data.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await tester.pump();
  }

  Finder button(String label) => find.widgetWithText(IdeButton, label);

  testWidgets('a build without updates says so', (tester) async {
    await show(tester, UpdatesSettingsPage(settings: settings));
    expect(find.text(l10n.updatesSettingsTitle), findsOneWidget);
    expect(
      find.text('${currentAppVersion.marketing} · ${l10n.updateUnsupported}'),
      findsOneWidget,
    );
    expect(
      tester.widget<IdeButton>(button(l10n.updateCheckNow)).onPressed,
      isNull,
    );
  });

  testWidgets('checks, shows what it found and its notes, restarts', (
    tester,
  ) async {
    final backend = FakeBackend(
      manifestOf('1.2.0+12', notes: {'en': 'Faster startup.'}),
    );
    final installer = FakeInstaller();
    final service = serviceOf(backend, installer: installer);
    var quits = 0;
    final controller = UpdateController(
      service: service,
      quit: () async => quits++,
      openUrl: (_) async {},
    );
    await show(
      tester,
      UpdatesSettingsPage(updates: controller, settings: settings),
    );
    expect(find.text('1.0.0 · ${l10n.updateNeverChecked}'), findsOneWidget);

    await tester.tap(button(l10n.updateCheckNow));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.updateAvailable('1.2.0')), findsOneWidget);
    expect(find.text(l10n.updateReleaseNotesFor('1.2.0')), findsOneWidget);
    expect(find.text('Faster startup.'), findsOneWidget);
    expect(find.textContaining('Last checked'), findsOneWidget);

    await tester.tap(button(l10n.updateRestartNow));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.updateReady('1.2.0')), findsOneWidget);
    expect(service.armed, isTrue);
    expect(quits, 1);
    service.dispose();
  });

  testWidgets('up to date, this version\'s notes are shown', (tester) async {
    final backend = FakeBackend(
      manifestOf('1.0.0', notes: {'en': 'First release.'}),
    );
    final service = serviceOf(backend);
    final controller = UpdateController(
      service: service,
      quit: () async {},
      openUrl: (_) async {},
    );
    await show(
      tester,
      UpdatesSettingsPage(updates: controller, settings: settings),
    );
    expect(find.text('First release.'), findsNothing);

    await tester.tap(button(l10n.updateCheckNow));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.updateUpToDate), findsOneWidget);
    expect(find.text(l10n.updateReleaseNotesFor('1.0.0')), findsOneWidget);
    expect(find.text('First release.'), findsOneWidget);

    // Not an older version's.
    backend.manifest = manifestOf('0.9.0', notes: {'en': 'Older.'});
    await tester.tap(button(l10n.updateCheckNow));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.updateUpToDate), findsOneWidget);
    expect(find.textContaining('Older'), findsNothing);
    expect(find.text('First release.'), findsNothing);
    service.dispose();
  });

  testWidgets('a problem restarting is shown on the page', (tester) async {
    final installer = FakeInstaller()
      ..prepareError = const ManualUpdateRequired('read-only');
    final service = serviceOf(
      FakeBackend(manifestOf('1.2.0')),
      installer: installer,
    );
    final controller = UpdateController(
      service: service,
      quit: () async {},
      openUrl: (_) async {},
    );
    await service.check(manual: true);
    await show(
      tester,
      UpdatesSettingsPage(updates: controller, settings: settings),
    );
    await tester.tap(button(l10n.updateRestartNow));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.updateManual('read-only')), findsOneWidget);
    expect(button(l10n.updateOpenDownloadPage), findsOneWidget);
    service.dispose();
  });

  testWidgets('update.mode is kept in settings.json, the default unwritten', (
    tester,
  ) async {
    await show(tester, UpdatesSettingsPage(settings: settings));
    final dropdown = find.byType(SettingsDropdown);
    expect(
      tester.widget<SettingsDropdown>(dropdown).current,
      l10n.updateModeDefault,
    );

    Future<void> choose(String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(done(), isTrue);
      await tester.pump();
    }

    await choose(l10n.updateModeManual);
    await settle(() => settings[UpdateMode.settingKey] == 'manual');
    await choose(l10n.updateModeNone);
    await settle(() => settings[UpdateMode.settingKey] == 'none');
    expect(
      tester.widget<SettingsDropdown>(dropdown).current,
      l10n.updateModeNone,
    );
    await choose(l10n.updateModeDefault);
    await settle(() => !settings.values.containsKey(UpdateMode.settingKey));
  });
}
