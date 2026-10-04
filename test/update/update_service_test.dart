import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/update/update_settings.dart';
import 'package:baocode/update/version.dart';

import 'update_fakes.dart';

void main() {
  group('UpdateMode', () {
    test('reads update.mode, the default otherwise', () {
      expect(UpdateMode.parse('default'), UpdateMode.automatic);
      expect(UpdateMode.parse('manual'), UpdateMode.manual);
      expect(UpdateMode.parse(' none '), UpdateMode.none);
      expect(UpdateMode.parse(null), UpdateMode.automatic);
      expect(UpdateMode.parse('start'), UpdateMode.automatic);
      expect(UpdateMode.parse(3), UpdateMode.automatic);
    });
  });

  group('UpdateService', () {
    test('finds a newer version for its platform', () async {
      final backend = FakeBackend(manifestOf('1.2.0+12'));
      final store = MemoryUpdateStore();
      final service = serviceOf(backend, store: store);
      final result = await service.check(manual: true);
      expect(result, isA<UpdateFound>());
      final offer = (result as UpdateFound).offer;
      expect(offer.release.version, AppVersion.parse('1.2.0+12'));
      expect(offer.release.platform, 'windows-x64');
      expect(offer.downloaded, isFalse);
      expect(offer.mandatory, isFalse);
      expect(service.status, UpdateStatus.available);
      expect(store.lastChecked, isNotNull);
      // Asked for: not downloaded until Restart to Update.
      await pumpEventQueue();
      expect(backend.downloads, isEmpty);
    });

    test('is up to date with the same, an older, or no download', () async {
      for (final manifest in [
        manifestOf('1.0.0+1'),
        manifestOf('0.9.0'),
        manifestOf('1.2.0', platforms: ['macos-universal']),
      ]) {
        final service = serviceOf(FakeBackend(manifest));
        expect(await service.check(manual: true), isA<UpdateUpToDate>());
        expect(service.status, UpdateStatus.upToDate);
        expect(service.release, isNull);
      }
    });

    test('a failed check reports its error, and only when asked', () async {
      final backend = FakeBackend('')..fetchError = Exception('offline');
      final service = serviceOf(backend);
      final result = await service.check(manual: true);
      expect(result, isA<UpdateCheckFailed>());
      expect(service.status, UpdateStatus.failed);
      expect('${service.error}', contains('offline'));

      backend
        ..fetchError = null
        ..manifest = 'not json';
      expect(await service.check(manual: true), isA<UpdateCheckFailed>());
      expect(service.error, isA<UpdateManifestException>());
    });

    test("a wrong entry for this platform is a failed check", () async {
      final backend = FakeBackend(
        manifestOf('1.2.0').replaceFirst(
          'https://baocode.dev/releases/1.2.0/windows-x64.bin',
          'https://evil.example/windows-x64.bin',
        ),
      );
      final result = await serviceOf(backend).check(manual: true);
      expect(
        (result as UpdateCheckFailed).error,
        isA<UpdateManifestException>(),
      );
    });

    test('none: no checks at all, not even asked for', () async {
      final backend = FakeBackend(manifestOf('1.2.0'));
      final service = serviceOf(
        backend,
        mode: FakeModeSetting(UpdateMode.none),
      );
      expect(await service.check(manual: true), isA<UpdatesDisabled>());
      expect(await service.check(), isA<UpdatesDisabled>());
      expect(backend.fetches, 0);
    });

    test('manual: only when asked', () async {
      final backend = FakeBackend(manifestOf('1.2.0'));
      final service = serviceOf(
        backend,
        mode: FakeModeSetting(UpdateMode.manual),
      );
      expect(await service.check(), isA<UpdatesDisabled>());
      expect(backend.fetches, 0);
      expect(await service.check(manual: true), isA<UpdateFound>());
      expect(backend.fetches, 1);
    });

    test('a build without updates has none', () async {
      final backend = FakeBackend(manifestOf('1.2.0'));
      final service = serviceOf(backend, platform: null)..start();
      expect(await service.check(manual: true), isA<UpdatesUnsupported>());
      expect(backend.fetches, 0);
      expect(backend.cleanedUp, isEmpty);
    });

    testWidgets('default: checks 30 seconds after launch, then every 6 hours', (
      tester,
    ) async {
      final backend = FakeBackend(manifestOf('1.0.0+1'));
      final service = serviceOf(backend)..start();
      await tester.pump(const Duration(seconds: 29));
      expect(backend.fetches, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(backend.fetches, 1);
      expect(backend.cleanedUp, [AppVersion.parse('1.0.0+1')]);
      await tester.pump(const Duration(hours: 5, minutes: 59));
      expect(backend.fetches, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(backend.fetches, 2);
      await tester.pump(const Duration(hours: 6));
      expect(backend.fetches, 3);
      service.dispose();
    });

    testWidgets('follows update.mode as it changes', (tester) async {
      final backend = FakeBackend(manifestOf('1.0.0+1'));
      final mode = FakeModeSetting(UpdateMode.manual);
      final service = serviceOf(backend, mode: mode)..start();
      await tester.pump(const Duration(hours: 7));
      expect(backend.fetches, 0);

      mode.mode = UpdateMode.automatic;
      await tester.pump(const Duration(seconds: 30));
      expect(backend.fetches, 1);

      mode.mode = UpdateMode.none;
      await tester.pump(const Duration(hours: 13));
      expect(backend.fetches, 1);
      service.dispose();
    });

    testWidgets('default: downloads what it finds and offers it once', (
      tester,
    ) async {
      final backend = FakeBackend(manifestOf('1.2.0+12'));
      final service = serviceOf(backend)..start();
      final offers = <UpdateOffer>[];
      service.offers.listen(offers.add);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(backend.downloads, hasLength(1));
      expect(service.status, UpdateStatus.ready);
      expect(offers, hasLength(1));
      expect(offers.single.downloaded, isTrue);
      expect(offers.single.release.version, AppVersion.parse('1.2.0+12'));

      // Put off: not offered again this run.
      await tester.pump(const Duration(hours: 6));
      await tester.pump();
      expect(backend.fetches, 2);
      expect(offers, hasLength(1));
      expect(backend.downloads, hasLength(1), reason: 'downloaded already');
      service.dispose();
    });

    testWidgets('a skipped version is not offered', (tester) async {
      final backend = FakeBackend(manifestOf('1.2.0+12'));
      final store = MemoryUpdateStore()..skippedVersion = '1.2.0+12';
      final service = serviceOf(backend, store: store)..start();
      final offers = <UpdateOffer>[];
      service.offers.listen(offers.add);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(offers, isEmpty);
      expect(backend.downloads, isEmpty);

      // A newer one is.
      backend.manifest = manifestOf('1.3.0');
      await tester.pump(const Duration(hours: 6));
      await tester.pump();
      expect(offers.single.release.version, AppVersion.parse('1.3.0'));
      service.dispose();
    });

    test('skip keeps the version skipped', () async {
      final store = MemoryUpdateStore();
      final service = serviceOf(FakeBackend(manifestOf('1.2.0')), store: store);
      final result = await service.check(manual: true) as UpdateFound;
      service.skip(result.offer.release);
      expect(store.skippedVersion, '1.2.0');
      expect(service.skippedVersion, '1.2.0');
    });

    testWidgets('a mandatory update is offered every check, skipped or not', (
      tester,
    ) async {
      final backend = FakeBackend(manifestOf('1.2.0', minimumVersion: '1.1.0'));
      final store = MemoryUpdateStore()..skippedVersion = '1.2.0';
      final service = serviceOf(backend, store: store)..start();
      final offers = <UpdateOffer>[];
      service.offers.listen(offers.add);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(offers.single.mandatory, isTrue);
      await tester.pump(const Duration(hours: 6));
      await tester.pump();
      expect(offers, hasLength(2));
      service.dispose();
    });

    test('minimumVersion: mandatory only below it', () async {
      Future<bool> mandatory(String current, String? minimum) async {
        final service = serviceOf(
          FakeBackend(manifestOf('2.0.0', minimumVersion: minimum)),
          current: current,
        );
        final result = await service.check(manual: true) as UpdateFound;
        return result.offer.mandatory;
      }

      expect(await mandatory('1.0.0', '1.1.0'), isTrue);
      expect(await mandatory('1.1.0', '1.1.0'), isFalse);
      expect(await mandatory('1.2.0', '1.1.0'), isFalse);
      expect(await mandatory('1.0.0', null), isFalse);
    });

    test('downloads once, however often asked, with its progress', () async {
      final backend = FakeBackend(manifestOf('1.2.0'))..gate = Completer();
      final service = serviceOf(backend);
      await service.check(manual: true);
      final first = service.download();
      final second = service.download();
      await pumpEventQueue();
      expect(service.status, UpdateStatus.downloading);
      expect(service.progress, 0.5);
      // A check meanwhile leaves it downloading.
      await service.check(manual: true);
      expect(service.status, UpdateStatus.downloading);
      backend.gate!.complete();
      expect(await first, await second);
      expect(backend.downloads, hasLength(1));
      expect(service.status, UpdateStatus.ready);
      expect(service.offer!.downloaded, isTrue);
      expect(service.progress, isNull);
    });

    test('a failed download is told, and tried again when asked', () async {
      final backend = FakeBackend(manifestOf('1.2.0'))
        ..downloadError = const UpdateVerificationException('bad');
      final service = serviceOf(backend);
      await service.check(manual: true);
      await expectLater(
        service.download(),
        throwsA(isA<UpdateVerificationException>()),
      );
      expect(service.status, UpdateStatus.failed);
      backend.downloadError = null;
      await service.download();
      expect(service.status, UpdateStatus.ready);
      expect(backend.downloads, hasLength(2));
    });

    test('prepares, arms and launches the install as the app quits', () async {
      final installer = FakeInstaller();
      final service = serviceOf(
        FakeBackend(manifestOf('1.2.0')),
        installer: installer,
      );
      await expectLater(service.prepare(), throwsStateError);
      await service.check(manual: true);
      final update = await service.prepare();
      expect(installer.prepared, ['/updates/1.2.0/windows-x64.bin']);

      // A quit cancelled installs nothing.
      service.arm(update);
      expect(service.armed, isTrue);
      service.disarm();
      expect(await service.launchArmed(), isTrue);
      expect(installer.launches, 0);

      service.arm(update);
      expect(await service.launchArmed(), isTrue);
      expect(installer.launches, 1);
      expect(service.armed, isFalse);
    });

    test('an install that will not start keeps the app, and says so', () async {
      final installer = FakeInstaller()..launchError = Exception('no shell');
      final service = serviceOf(
        FakeBackend(manifestOf('1.2.0')),
        installer: installer,
      );
      final failures = <Object>[];
      service.failures.listen(failures.add);
      await service.check(manual: true);
      service.arm(await service.prepare());
      expect(await service.launchArmed(), isFalse);
      await pumpEventQueue();
      expect('${failures.single}', contains('no shell'));
      expect(service.status, UpdateStatus.failed);
    });
  });
}
