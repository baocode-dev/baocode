import 'dart:io';

import 'package:baocode/chat/selection_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory folder;
  late DateTime now;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('selection_recorder');
    now = DateTime(2026, 11, 16, 12);
    SelectionRecorder.debugReset();
  });
  tearDown(() {
    SelectionRecorder.debugReset();
    folder.deleteSync(recursive: true);
  });

  SelectionRecorder recorder({int size = 400}) => SelectionRecorder(
    size: size,
    listSize: 3,
    clock: () => now,
    folder: () => folder.path,
  );

  Future<String> read(String name) async {
    // Written in the background.
    for (var i = 0; i < 50; i++) {
      final file = File(p.join(folder.path, name));
      if (file.existsSync() && file.lengthSync() > 0) {
        return file.readAsStringSync();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('$name not written');
  }

  test('keeps the newest steps and list changes, and when the list went '
      'off', () async {
    final steps = recorder(size: 3);
    for (var i = 1; i <= 5; i++) {
      steps.step('step $i');
    }
    for (var i = 1; i <= 4; i++) {
      steps.listChanged('change $i');
    }
    steps.listOff('1 unregistered');
    steps.listChanged('change 5');
    steps.listOff('2 unregistered'); // Kept from the first time.
    final name = steps.dump('a drag selected nothing', ['now this'])!;
    final text = await read(name);
    expect(text, isNot(contains('step 1')));
    expect(text, isNot(contains('step 2')));
    expect(text, contains('step 5'));
    expect(text, contains('now this'));
    expect(text, contains(': 1 unregistered'));
    expect(text, isNot(contains(': 2 unregistered')));
    // The changes up to it, then the latest.
    final upTo = text.substring(
      text.indexOf('its changes up to then:'),
      text.indexOf('its latest changes:'),
    );
    expect(upTo, contains('change 2'));
    expect(upTo, contains('change 4'));
    expect(upTo, isNot(contains('change 1')));
    expect(upTo, isNot(contains('change 5')));
    expect(steps.listIsOff, isTrue);
    steps.listWhole();
    expect(steps.listIsOff, isFalse);
  });

  test('writes not more than a few a run, one a minute, and keeps the '
      'newest', () async {
    final steps = recorder();
    expect(steps.dump('first', const []), isNotNull);
    expect(steps.dump('too soon', const []), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(steps.dump('second', const []), isNotNull);
    now = now.add(const Duration(minutes: 1));
    final third = steps.dump('third', const []);
    expect(third, isNotNull);
    now = now.add(const Duration(minutes: 1));
    expect(steps.dump('fourth', const []), isNull);
    await read(third!);

    SelectionRecorder.debugReset();
    final kept = SelectionRecorder.kept;
    final hangs = Directory(p.join(folder.path, 'hangs'));
    for (var i = 0; i < kept + 2; i++) {
      File(p.join(hangs.path, 'selection-20261101-00000$i-1.txt'))
          .writeAsStringSync('old');
    }
    now = now.add(const Duration(minutes: 1));
    await read(steps.dump('newest', const [])!);
    final left = [
      for (final file in hangs.listSync())
        if (p.basename(file.path).startsWith('selection-')) file,
    ];
    expect(left, hasLength(kept));
  });

  test('writes nothing without a logs folder', () {
    final steps = SelectionRecorder(folder: () => null);
    expect(steps.dump('a drag selected nothing', const []), isNull);
  });
}
