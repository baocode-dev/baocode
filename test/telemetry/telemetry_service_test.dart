import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/telemetry/telemetry_io.dart';
import 'package:baocode/telemetry/telemetry_service.dart';
import 'package:baocode/update/version.dart';

/// Answers each report with [status]; throws when it is null (offline).
class FakeSender implements TelemetrySender {
  int? status = 204;
  final List<Map<String, Object?>> sent = [];
  Completer<void>? gate;

  @override
  Future<int> send(Uri url, Map<String, Object?> body) async {
    sent.add(body);
    await gate?.future;
    final status = this.status;
    if (status == null) throw const SocketException('offline');
    return status;
  }
}

class _RealHttp extends HttpOverrides {}

void main() {
  group('TelemetryService', () {
    late FakeSender sender;
    late MemoryTelemetryStore store;
    late DateTime now;

    TelemetryService serviceOf({bool Function()? inFront}) => TelemetryService(
      current: AppVersion.parse('1.2.0+12'),
      os: 'macos',
      arch: 'arm64',
      sender: sender,
      url: Uri.parse('https://example.test/v1/ping'),
      store: store,
      now: () => now,
      inFront: inFront,
      newId: () => 'id-1',
    );

    setUp(() {
      sender = FakeSender();
      store = MemoryTelemetryStore();
      now = DateTime.utc(2026, 10, 7, 9);
    });

    test('says its edition, and where its user came from once told', () async {
      Map<String, Object?>? told;
      final service = TelemetryService(
        current: AppVersion.parse('1.2.0+12'),
        os: 'macos',
        arch: 'arm64',
        sender: sender,
        url: Uri.parse('https://example.test/v1/ping'),
        store: store,
        now: () => now,
        newId: () => 'id-1',
        edition: () => 'channel',
        attribution: () => told,
      );
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent.last['edition'], 'channel');
      expect(sender.sent.last.containsKey('attribution'), isFalse);
      told = {'source': 'channel', 'value': 'youtube'};
      now = now.add(const Duration(days: 1));
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent.last['attribution'], told);
    });

    test('tells how phones connected, once it got through', () async {
      Map<String, int>? pending = {'lan': 2, 'relay': 1};
      final told = <Map<String, int>>[];
      final service = TelemetryService(
        current: AppVersion.parse('1.2.0+12'),
        os: 'macos',
        arch: 'arm64',
        sender: sender,
        url: Uri.parse('https://example.test/v1/ping'),
        store: store,
        now: () => now,
        newId: () => 'id-1',
        linkPaths: () => pending,
        linkPathsSent: (sent) {
          told.add(sent);
          pending = null;
        },
      );
      sender.status = null;
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent.last['link'], {'lan': 2, 'relay': 1});
      expect(told, isEmpty);
      sender.status = 204;
      await service.flush();
      expect(told, [
        {'lan': 2, 'relay': 1},
      ]);
      now = now.add(const Duration(days: 1));
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent.last.containsKey('link'), isFalse);
    });

    test('reports a day once, with as little as it needs', () async {
      final service = serviceOf();
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent, [
        {
          'v': 1,
          'id': 'id-1',
          'days': ['2026-10-07'],
          'version': '1.2.0+12',
          'os': 'macos',
          'arch': 'arm64',
        },
      ]);
      expect(store.installId, 'id-1');
      expect(store.pendingDays, isEmpty);
      // Again the same day: nothing new.
      now = now.add(const Duration(hours: 5));
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent, hasLength(1));
      // The next day.
      now = now.add(const Duration(days: 1));
      service.markActive();
      await pumpEventQueue();
      expect(sender.sent.last['days'], ['2026-10-08']);
    });

    test('the day is UTC\'s', () {
      expect(
        TelemetryService.dayOf(DateTime.utc(2026, 10, 7, 23, 59)),
        '2026-10-07',
      );
      expect(
        TelemetryService.dayOf(DateTime.utc(2026, 1, 2, 3).toLocal()),
        '2026-01-02',
      );
    });

    test('keeps the days not sent, and sends them later', () async {
      sender.status = null;
      final service = serviceOf();
      service.markActive();
      await pumpEventQueue();
      now = now.add(const Duration(days: 1));
      service.markActive();
      await pumpEventQueue();
      expect(store.pendingDays, ['2026-10-07', '2026-10-08']);
      // A server error is tried again as well.
      sender.status = 503;
      await service.flush();
      expect(store.pendingDays, hasLength(2));
      sender.status = 204;
      await service.flush();
      expect(sender.sent.last['days'], ['2026-10-07', '2026-10-08']);
      expect(store.pendingDays, isEmpty);
    });

    test('drops a report the server refuses', () async {
      sender.status = 400;
      serviceOf().markActive();
      await pumpEventQueue();
      expect(store.pendingDays, isEmpty);
    });

    test('keeps no more than the latest days', () async {
      sender.status = null;
      final service = serviceOf();
      for (var i = 0; i < TelemetryService.maxPendingDays + 5; i++) {
        service.markActive();
        now = now.add(const Duration(days: 1));
      }
      await pumpEventQueue();
      expect(store.pendingDays, hasLength(TelemetryService.maxPendingDays));
      expect(store.pendingDays.first, '2026-10-12');
    });

    test('a day marked while sending waits for the next report', () async {
      final service = serviceOf();
      sender.gate = Completer();
      service.markActive();
      await pumpEventQueue();
      now = now.add(const Duration(days: 1));
      service.markActive();
      sender.gate!.complete();
      await pumpEventQueue();
      expect(sender.sent, hasLength(1));
      expect(store.pendingDays, ['2026-10-08']);
      sender.gate = null;
      await service.flush();
      expect(sender.sent.last['days'], ['2026-10-08']);
    });

    testWidgets('looks at start, then every interval, while in front', (
      tester,
    ) async {
      var inFront = false;
      final service = serviceOf(inFront: () => inFront)..start();
      await tester.pump(service.firstDelay);
      expect(sender.sent, isEmpty);
      inFront = true;
      await tester.pump(service.interval);
      expect(sender.sent, hasLength(1));
      now = now.add(const Duration(days: 1));
      await tester.pump(service.interval);
      expect(sender.sent, hasLength(2));
      service.dispose();
    });

    test('install ids are random version 4 UUIDs', () {
      final id = TelemetryService.randomInstallId(Random(1));
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(TelemetryService.randomInstallId(), isNot(id));
    });
  });

  group('telemetry_io', () {
    test('the processor', () {
      expect(abiArch(Abi.macosArm64), 'arm64');
      expect(abiArch(Abi.windowsX64), 'x64');
    });

    test('posts the report as JSON', () async {
      // flutter_test's own HttpClient answers 400 to all.
      HttpOverrides.global = _RealHttp();
      addTearDown(() => HttpOverrides.global = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <Object?>[];
      server.listen((request) async {
        received
          ..add(request.method)
          ..add(request.headers.contentType?.mimeType)
          ..add(jsonDecode(await utf8.decodeStream(request)));
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      final status = await IoTelemetrySender().send(
        Uri.parse('http://127.0.0.1:${server.port}/v1/ping'),
        {'v': 1, 'id': 'x'},
      );
      expect(status, 204);
      expect(received, [
        'POST',
        'application/json',
        {'v': 1, 'id': 'x'},
      ]);
    });
  });
}
