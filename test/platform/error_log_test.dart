import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/error_log.dart';
import 'package:baocode/update/version.dart';

/// Fails to build, as Quill's editor did on a suggested prompt with a
/// Windows path in it.
class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => Text(jsonDecode(r'"C:\Users"'));
}

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('error_log'));
  tearDown(() => folder.deleteSync(recursive: true));

  ErrorLog log({int maxBytes = 1024 * 1024}) => ErrorLog(
    '${folder.path}/logs',
    maxBytes: maxBytes,
    clock: () => DateTime(2026, 10, 8, 22, 30),
  );

  testWidgets('a widget that fails to build is written, with what it was '
      'building and where', (tester) async {
    final errors = log();
    final original = FlutterError.onError;
    FlutterError.onError = errors.recordFlutterError;
    await tester.pumpWidget(const _Throws());
    FlutterError.onError = original;

    final text = File(errors.path).readAsStringSync();
    expect(
      text,
      startsWith(
        '--- BaoCode $appVersionString · ${Platform.operatingSystem} ',
      ),
    );
    expect(
      text,
      contains('2026-10-08T22:30:00.000 [widgets library] building _Throws'),
    );
    expect(text, contains('FormatException: Unrecognized string escape'));
    expect(text, contains('_Throws.build'));
  });

  test('an error that comes every frame is written three times, then '
      'counted', () {
    final errors = log();
    for (var i = 0; i < 1000; i++) {
      errors.record(
        StateError('no size'),
        StackTrace.current,
        source: 'rendering library',
        context: 'during paint()',
      );
    }
    final text = File(errors.path).readAsStringSync();
    expect(
      '[rendering library] during paint()\nBad state: no size'
          .allMatches(text)
          .length,
      3,
    );
    expect(text, contains('the same again, 10 times: Bad state: no size'));
    expect(text, contains('the same again, 100 times'));
    expect(text, contains('the same again, 1000 times'));
    expect(text, isNot(contains('the same again, 4 times')));
  });

  test('a run before that grew too large is moved aside; a run writes no '
      'more than the most', () {
    final errors = log(maxBytes: 2000);
    Directory(errors.directory).createSync(recursive: true);
    File(errors.path).writeAsStringSync('x' * 3000);
    for (var i = 0; i < 50; i++) {
      errors.record(StateError('error $i'), null, source: 'test');
    }
    expect(File(errors.previousPath).lengthSync(), 3000);
    final text = File(errors.path).readAsStringSync();
    expect(text, contains('Bad state: error 0'));
    expect(text, endsWith('(No more this run: the log reached 2000 bytes.)\n'));
    expect(text.length, lessThan(2100));
  });

  testWidgets('the Windows app is told the folder, for its own logs', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ErrorLog.channel,
      (call) async => calls.add(call),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ErrorLog.channel,
        null,
      ),
    );
    final errors = log();

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await errors.shareWithHost();
    expect(calls, isEmpty);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await errors.shareWithHost();
    debugDefaultTargetPlatformOverride = null;
    expect(calls.single.method, 'setFolder');
    expect(calls.single.arguments, errors.directory);
  });

  test('installed, it hands what it is told on to the handlers there were', () {
    final flutter = FlutterError.onError;
    final platform = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutter;
      PlatformDispatcher.instance.onError = platform;
    });
    final reported = <Object>[];
    FlutterError.onError = (details) => reported.add(details.exception);
    PlatformDispatcher.instance.onError = (error, stack) {
      reported.add(error);
      return true;
    };
    final errors = log()..install();

    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('in a gesture')),
    );
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('in a future'),
        StackTrace.empty,
      ),
      isTrue,
    );

    expect(reported.map((error) => '$error'), [
      'Bad state: in a gesture',
      'Bad state: in a future',
    ]);
    final text = File(errors.path).readAsStringSync();
    expect(text, contains('[Flutter framework]\nBad state: in a gesture\n\n'));
    expect(text, contains('[uncaught]\nBad state: in a future\n\n'));
  });
}
