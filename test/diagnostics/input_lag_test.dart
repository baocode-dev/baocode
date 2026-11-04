import 'dart:io';

import 'package:baocode/diagnostics/input_lag.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('input_lag');
    EventLog.current = EventLog(folder.path);
    InputLag.debugReset();
  });
  tearDown(() {
    EventLog.current = null;
    folder.deleteSync(recursive: true);
  });

  List<String> lines() {
    final file = File(EventLog.current!.path);
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.contains(' [input] ')) line,
    ];
  }

  testWidgets('a key whose search held it up is written, with its parts', (
    tester,
  ) async {
    final lag = InputLag('test find', describe: () => '3 matches');
    lag.begin('key');
    final found = lag.time('search', () {
      sleep(const Duration(milliseconds: 120));
      return 3;
    });
    expect(found, 3);
    await tester.pump();
    final written = lines();
    expect(written, hasLength(1));
    expect(
      written.single,
      matches(
        RegExp(
          r'\[input\] test find: a key shown after \d+ ms; '
          r'before the frame \d+ ms \(search 1\d\d\), the frame \d+ ms; '
          r'3 matches; semantics ',
        ),
      ),
    );
    expect(written.single, contains('render objects'));
  });

  testWidgets('a quick one is not, nor a search with no key a change', (
    tester,
  ) async {
    final lag = InputLag('test find');
    lag.begin('click');
    await tester.pump();
    expect(lines(), isEmpty);
    // Text the input method sent, with no key.
    lag.time('search', () => sleep(const Duration(milliseconds: 120)));
    await tester.pump();
    expect(lines().single, contains('test find: a change shown after '));
  });

  testWidgets('one at a time: a key before the frame is the same input', (
    tester,
  ) async {
    final lag = InputLag('test find');
    lag.begin('key');
    lag.begin('click');
    lag.time('search', () => sleep(const Duration(milliseconds: 60)));
    lag.time('search', () => sleep(const Duration(milliseconds: 60)));
    await tester.pump();
    expect(lines().single, contains('test find: a key shown after '));
  });
}
