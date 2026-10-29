import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/diagnostics/hang_watch.dart';
import 'package:baocode/platform/event_log.dart';

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('hang_watch'));
  tearDown(() {
    EventLog.current = null;
    folder.deleteSync(recursive: true);
  });

  testWidgets('the Windows and macOS apps are told the folder, for their '
      'own logs', (tester) async {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      logsChannel,
      (call) async => calls.add(call),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(logsChannel, null);
      logsChannel.setMethodCallHandler(null);
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await shareLogsFolder('/logs');
    expect(calls, isEmpty);

    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      await shareLogsFolder('/logs');
    }
    debugDefaultTargetPlatformOverride = null;
    expect([for (final call in calls) call.method], ['setFolder', 'setFolder']);
    expect([for (final call in calls) call.arguments], ['/logs', '/logs']);
  });

  testWidgets('a hang that ends is written with what the app shows', (
    tester,
  ) async {
    EventLog.current = EventLog(
      folder.path,
      clock: () => DateTime(2026, 10, 28, 14, 17),
    );
    await handleHostCall(
      const MethodCall('hangEnded', {
        'seconds': 12.34,
        'sample': 'hangs/hang-20261028-141700-42.txt',
      }),
    );
    await handleHostCall(const MethodCall('hangEnded', {'seconds': 5}));
    final lines = File(EventLog.current!.path)
        .readAsLinesSync()
        .where((line) => line.contains(' [hang] '))
        .toList();
    expect(lines, hasLength(2));
    expect(
      lines.first,
      startsWith(
        '2026-10-28T14:17:00.000 [hang] answering again after 12.3 s; '
        'sample hangs/hang-20261028-141700-42.txt; semantics ',
      ),
    );
    expect(lines.first, contains('render objects'));
    expect(lines.last, contains('[hang] answering again after 5.0 s; '));
    expect(
      () => handleHostCall(const MethodCall('other')),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
