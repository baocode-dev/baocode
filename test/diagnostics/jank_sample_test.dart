import 'dart:io';

import 'package:baocode/diagnostics/jank_sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory folder;
  late DateTime now;
  late List<List<String>> started;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('jank_sample_test');
    now = DateTime(2026, 10, 27, 20, 5, 9);
    started = [];
  });
  tearDown(() => folder.deleteSync(recursive: true));

  JankSampler sampler({String os = 'macos', int kept = 5}) => JankSampler(
    folder.path,
    pid: 4242,
    kept: kept,
    clock: () => now,
    take: () => platformSample(
      os: os,
      pid: 4242,
      start: (executable, arguments) async =>
          started.add([executable, ...arguments]),
    ),
  );

  test(
    "samples the app's own process into hangs/, sent with the logs",
    () async {
      final name = await sampler().sample();
      expect(name, 'hangs/jank-20261027-200509-4242.txt');
      expect(started.single, [
        '/usr/bin/sample',
        '4242',
        '3',
        '-file',
        p.join(folder.path, name!),
      ]);
    },
  );

  test('not again before its gap, nor past its most in a run', () async {
    final watch = sampler();
    expect(await watch.sample(), isNotNull);
    now = now.add(const Duration(minutes: 5));
    expect(await watch.sample(), isNull);
    now = now.add(const Duration(minutes: 6));
    expect(await watch.sample(), isNotNull);
    now = now.add(const Duration(minutes: 11));
    expect(await watch.sample(), isNotNull);
    now = now.add(const Duration(hours: 1));
    expect(await watch.sample(), isNull);
    expect(started, hasLength(3));
  });

  test('none where the platform samples not', () async {
    expect(await sampler(os: 'android').sample(), isNull);
    // Windows and Linux sample from within, the app built ahead of time:
    // not under flutter test.
    expect(await sampler(os: 'linux').sample(), isNull);
    expect(started, isEmpty);
  });

  test('none named when the sample did not start', () async {
    final watch = JankSampler(
      folder.path,
      pid: 1,
      clock: () => now,
      take: () =>
          (path, seconds) async => false,
    );
    expect(await watch.sample(), isNull);
  });

  test('the oldest samples go, the hang reports stay', () async {
    final hangs = Directory(p.join(folder.path, 'hangs'))..createSync();
    for (final name in [
      'jank-20261001-100000-1.txt',
      'jank-20261002-100000-1.txt',
      'jank-20261003-100000-1.txt',
      'hang-20261001-100000-1.txt',
      'hang-20261001-100000-1.dmp',
    ]) {
      File(p.join(hangs.path, name)).writeAsStringSync('x');
    }
    await sampler(kept: 2).sample();
    expect((hangs.listSync().map((f) => p.basename(f.path)).toList()..sort()), [
      'hang-20261001-100000-1.dmp',
      'hang-20261001-100000-1.txt',
      'jank-20261003-100000-1.txt',
    ]);
  });
}
