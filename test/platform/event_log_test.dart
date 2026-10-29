import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/diagnostics/app_event_watch.dart';
import 'package:baocode/diagnostics/diagnostics_bundle.dart';
import 'package:baocode/platform/error_log.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:baocode/update/version.dart';

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('event_log'));
  tearDown(() {
    EventLog.current = null;
    folder.deleteSync(recursive: true);
  });

  EventLog log({int maxBytes = 1024 * 1024}) => EventLog(
    '${folder.path}/logs',
    maxBytes: maxBytes,
    clock: () => DateTime(2026, 10, 16, 12, 33, 19),
  );

  test('a run starts with the version and the system, each event timed '
      'under its category', () {
    final events = log()
      ..record('window', '-> showStash')
      ..record('theme', 'Dark+ (dark)');

    final lines = File(events.path).readAsLinesSync();
    expect(
      lines.first,
      startsWith(
        '--- BaoCode $appVersionString · ${Platform.operatingSystem} ',
      ),
    );
    expect(lines.first, endsWith('pid $pid ---'));
    expect(lines.skip(1), [
      '2026-10-16T12:33:19.000 [window] -> showStash',
      '2026-10-16T12:33:19.000 [theme] Dark+ (dark)',
    ]);
  });

  test('a run goes on after the last one in the same file', () {
    log().record('app', 'first run');
    log().record('app', 'second run');

    final text = File(log().path).readAsStringSync();
    expect(RegExp('--- BaoCode').allMatches(text), hasLength(2));
    expect(text.indexOf('first run'), lessThan(text.indexOf('second run')));
  });

  test('past its size the file moves aside and a new one keeps the latest', () {
    final events = log(maxBytes: 300);
    for (var i = 0; i < 12; i++) {
      events.record('views', 'event number $i');
    }

    final current = File(events.path).readAsStringSync();
    final previous = File(events.previousPath).readAsStringSync();
    expect(current, contains('event number 11'));
    expect(previous, isNot(contains('event number 11')));
    expect(File(events.path).lengthSync(), lessThanOrEqualTo(300));
    expect(File(events.previousPath).lengthSync(), lessThanOrEqualTo(300));
    // Both are uploaded with the diagnostics.
    expect(listDiagnosticsLogs('${folder.path}/logs').map((log) => log.name), [
      'events.1.log',
      'events.log',
    ]);
  });

  test('a run that said how it ended: nothing said of it next time', () {
    log()
      ..record('app', 'started')
      ..record(EventLog.exitCategory, 'quit');
    log().record('app', 'started');

    final text = File(log().path).readAsStringSync();
    expect(text, isNot(contains('the run before')));
  });

  test('a run that ended without a word: the next says so, as it starts', () {
    log().record('app', 'started');
    log().record('app', 'started again');

    final lines = File(log().path).readAsLinesSync();
    final second = lines.lastIndexWhere((line) => line.startsWith('--- '));
    expect(
      lines[second + 1],
      '2026-10-16T12:33:19.000 [app] the run before (pid $pid) ended '
      'without saying how, after 2026-10-16T12:33:19.000: killed '
      '(kill -9, out of memory), a crash, or the system going down',
    );
    expect(lines[second + 2], endsWith('[app] started again'));
  });

  test("with the crash report the system kept, where there is one", () {
    log().record('app', 'started');
    DateTime? asked;
    EventLog(
      '${folder.path}/logs',
      clock: () => DateTime(2026, 10, 16, 12, 40),
      crashSince: (since) {
        asked = since;
        return 'BaoCode-2026-10-16-123320.ips: EXC_BAD_ACCESS (SIGSEGV)';
      },
    ).record('app', 'started again');

    expect(asked, DateTime(2026, 10, 16, 12, 33, 19));
    expect(
      File(log().path).readAsStringSync(),
      contains(
        'ended without saying how, after 2026-10-16T12:33:19.000: crash '
        'report BaoCode-2026-10-16-123320.ips: EXC_BAD_ACCESS (SIGSEGV)\n',
      ),
    );
  });

  test('a line the native side wrote counts as how the run ended', () {
    log().record('app', 'started');
    File(log().path).writeAsStringSync(
      '2026-10-16T12:34:00.123 [exit] crashed: SIGSEGV at libapp.so+0x10\n',
      mode: FileMode.append,
    );
    log().record('app', 'started again');

    expect(
      File(log().path).readAsStringSync(),
      isNot(contains('the run before')),
    );
  });

  test('a first run says nothing of one before', () {
    log().record('app', 'started');
    expect(
      File(log().path).readAsStringSync(),
      isNot(contains('the run before')),
    );
  });

  test('an error written to errors.log shows on the timeline too', () {
    final events = EventLog.current = log();
    ErrorLog('${folder.path}/logs')
        .record(StateError('no view\nmore detail'), null, source: 'uncaught');

    expect(
      File(events.path).readAsStringSync(),
      contains('[error] [uncaught] Bad state: no view\n'),
    );
  });

  test('without an event log, nothing is written', () {
    appEvent('app', 'nowhere');
    expect(Directory('${folder.path}/logs').existsSync(), isFalse);
  });

  testWidgets('the views are told as drawn: their size and what their last '
      'frame painted', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('drawn'),
      ),
    );

    final states = appViewStates();
    final size = tester.view.physicalSize;
    expect(
      states,
      startsWith(
        'view ${tester.view.viewId} '
        '${size.width.round()}x${size.height.round()}'
        '@${tester.view.devicePixelRatio} laid out',
      ),
    );
    expect(states, isNot(contains('not drawn')));
    expect(states, matches(RegExp(r', [1-9]\d* pictures; frames on')));
  });
}
