import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/update/update_controller.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/update/update_settings.dart';
import 'package:baocode/update/version.dart';

import 'update_fakes.dart';

void main() {
  final l10n = englishLocalizations;
  late FakeBackend backend;
  late FakeInstaller installer;
  late UpdateService service;
  late IdeNotifications notifications;
  late List<Uri> opened;
  late List<String> files;
  late int quits;
  late UpdateController controller;

  void make({
    String manifest = '',
    UpdateMode mode = UpdateMode.automatic,
    UpdateStore? store,
  }) {
    backend = FakeBackend(manifest);
    installer = FakeInstaller();
    service = serviceOf(
      backend,
      installer: installer,
      mode: FakeModeSetting(mode),
      store: store,
    );
    notifications = IdeNotifications();
    opened = [];
    files = [];
    quits = 0;
    controller = UpdateController(
      service: service,
      quit: () async => quits++,
      openUrl: (url) async => opened.add(url),
      openFile: (path) async => files.add(path),
    );
  }

  tearDown(() {
    service.dispose();
    notifications.dispose();
  });

  List<String> labels(IdeNotification note) => [
    for (final action in note.primary) action.label,
  ];

  group('UpdateController', () {
    test('Check for Updates tells what it found', () async {
      make(manifest: manifestOf('1.0.0+1'));
      await controller.checkNow(notifications, l10n);
      expect(notifications.notifications.single.message, l10n.updateUpToDate);

      backend.fetchError = Exception('offline');
      await controller.checkNow(notifications, l10n);
      expect(notifications.notifications.first.severity, IdeSeverity.error);
      expect(notifications.notifications.first.message, contains('offline'));
    });

    test('says when updates are off', () async {
      make(manifest: manifestOf('1.2.0'), mode: UpdateMode.none);
      await controller.checkNow(notifications, l10n);
      expect(notifications.notifications.single.message, l10n.updateDisabled);
      expect(backend.fetches, 0);
    });

    test('offers a version found: Restart, Later, Skip', () async {
      make(manifest: manifestOf('1.2.0', notes: {'en': 'Fixes'}));
      await controller.checkNow(notifications, l10n);
      final offer = notifications.notifications.single;
      expect(offer.message, l10n.updateAvailable('1.2.0'));
      expect(offer.sticky, isTrue);
      expect(labels(offer), [
        l10n.updateRestartNow,
        l10n.updateLater,
        l10n.updateSkip,
      ]);
      expect(offer.secondary.single.label, l10n.updateReleaseNotes);
      offer.secondary.single.run();
      expect(opened, [Uri.parse('https://baocode.dev/changelog#v1.2.0')]);

      offer.primary[2].run();
      expect(service.skippedVersion, '1.2.0');
    });

    test('Release Notes opens the changelog in the app\'s language', () {
      make();
      final version = AppVersion.parse('1.2.0+13');
      expect(
        UpdateController.changelogUrl(version, 'zh'),
        Uri.parse('https://baocode.dev/zh/changelog#v1.2.0'),
      );
      expect(
        UpdateController.changelogUrl(version, 'en'),
        Uri.parse('https://baocode.dev/changelog#v1.2.0'),
      );
    });

    test('a mandatory update cannot be put off', () async {
      make(manifest: manifestOf('1.2.0', minimumVersion: '1.1.0'));
      await controller.checkNow(notifications, l10n);
      final offer = notifications.notifications.single;
      expect(offer.severity, IdeSeverity.warning);
      expect(offer.message, l10n.updateMandatory('1.2.0'));
      expect(labels(offer), [l10n.updateRestartNow]);
      expect(offer.secondary, isEmpty, reason: 'no notes');
    });

    test('Restart to Update downloads, arms the install, and quits', () async {
      make(manifest: manifestOf('1.2.0'));
      await controller.checkNow(notifications, l10n);
      notifications.clearAll();
      await controller.restart(notifications, l10n);
      expect(backend.downloads, hasLength(1));
      expect(installer.prepared, hasLength(1));
      expect(service.armed, isTrue);
      expect(quits, 1);
      expect(notifications.notifications, isEmpty, reason: 'download done');
    });

    test('where the app cannot update itself, the download page', () async {
      make(manifest: manifestOf('1.2.0'));
      installer.prepareError = const ManualUpdateRequired('read-only');
      await controller.checkNow(notifications, l10n);
      notifications.clearAll();
      await controller.restart(notifications, l10n);
      final note = notifications.notifications.single;
      expect(note.message, l10n.updateManual('read-only'));
      expect(quits, 0);
      expect(service.armed, isFalse);
      note.primary.single.run();
      expect(opened, [ManualUpdateRequired.downloadPage]);
      expect(
        '${ManualUpdateRequired.downloadPage}',
        'https://baocode.dev/download',
      );
    });

    test('a download that fails its checks is told, not installed', () async {
      make(manifest: manifestOf('1.2.0'));
      backend.downloadError = const UpdateVerificationException(
        'The download is not signed by BaoCode',
      );
      await controller.checkNow(notifications, l10n);
      notifications.clearAll();
      await controller.restart(notifications, l10n);
      final note = notifications.notifications.single;
      expect(note.severity, IdeSeverity.error);
      expect(note.message, contains('not signed'));
      expect(installer.prepared, isEmpty);
      expect(quits, 0);
    });

    testWidgets("the main window hears what the checks find", (tester) async {
      make(manifest: manifestOf('1.2.0'));
      final stop = controller.listen(notifications, () => l10n);
      service.start();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(
        notifications.notifications.single.message,
        l10n.updateReady('1.2.0'),
      );

      // An install that would not start as the app quit.
      installer.launchError = Exception('no powershell');
      service.arm(await service.prepare());
      expect(await service.launchArmed(), isFalse);
      await tester.pump();
      expect(
        notifications.notifications.first.message,
        contains('no powershell'),
      );
      stop();
      service.dispose();
      // Their toasts' timers.
      notifications.dispose();
      make();
    });

    testWidgets('an install that did not finish is told at the next launch', (
      tester,
    ) async {
      make(
        mode: UpdateMode.manual,
        store: MemoryUpdateStore()..installingVersion = '1.2.0',
      );
      installer.log = '/updates/install.log';
      service.start();
      final stop = controller.listen(notifications, () => l10n);
      expect(notifications.notifications, isEmpty, reason: 'once built');
      await tester.pump(Duration.zero);
      final note = notifications.notifications.single;
      expect(note.severity, IdeSeverity.warning);
      expect(note.message, l10n.updateUnfinished('1.2.0', '1.0.0'));
      expect(labels(note), [l10n.updateOpenDownloadPage, l10n.updateShowLog]);
      note.primary.first.run();
      expect(opened, [ManualUpdateRequired.downloadPage]);
      note.primary.last.run();
      expect(files, ['/updates/install.log']);

      // Told once: not by the next window that listens.
      stop();
      final again = controller.listen(notifications, () => l10n);
      await tester.pump(Duration.zero);
      expect(notifications.notifications, hasLength(1));
      again();
      notifications.dispose();
      make();
    });
  });
}
