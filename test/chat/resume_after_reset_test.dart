import 'package:baocode/chat/resume_after_reset.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The scheduler's clock, moved on with the test's timers (see [elapse]).
  late DateTime now;

  // The setting, as settings.json has it.
  late ValueNotifier<bool> setting;

  setUp(() {
    now = _start;
    setting = ValueNotifier(true);
  });

  ResumeAfterReset make({PreferenceStore? store}) {
    final resumes = ResumeAfterReset(
      store: store,
      enabled: () => setting.value,
      enabledChanges: setting,
      clock: () => now,
    );
    addTearDown(resumes.dispose);
    return resumes;
  }

  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
    // What a timer started, done.
    await tester.pump();
  }

  void hit(ResumeAfterReset resumes, String id, {Duration after = _hour}) =>
      resumes.hit(sessionId: id, resetsAt: _start.add(after));

  testWidgets('a failure to keep them is logged, not left uncaught', (
    tester,
  ) async {
    final store = _FailingStore();
    final resumes = make(store: store);
    hit(resumes, 'a');
    await tester.pump();
    resumes.remove('a');
    await tester.pump();
    expect(store.writes, 2);
    expect(resumes.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on, a limit hit goes on a minute after it resets', (
    tester,
  ) async {
    final resumed = <String>[];
    final resumes = make()
      ..resume = (id) async {
        resumed.add(id);
        return true;
      };
    hit(resumes, 'a');
    await elapse(tester, const Duration(minutes: 59, seconds: 59));
    expect(resumed, isEmpty);
    await elapse(tester, const Duration(minutes: 1, seconds: 1));
    expect(resumed, ['a']);
    expect(resumes['a'], isNull);
  });

  testWidgets('off, it does not go on, and is let go as it resets', (
    tester,
  ) async {
    setting.value = false;
    final resumed = <String>[];
    final resumes = make()
      ..resume = (id) async {
        resumed.add(id);
        return true;
      };
    hit(resumes, 'a');
    expect(resumes['a'], isNotNull);
    await elapse(tester, const Duration(hours: 2));
    expect(resumed, isEmpty);
    expect(resumes.entries, isEmpty);
  });

  testWidgets('turned on after the limit was hit, it goes on all the same; '
      'turned off, not', (tester) async {
    setting.value = false;
    final resumed = <String>[];
    final resumes = make()
      ..resume = (id) async {
        resumed.add(id);
        return true;
      };
    hit(resumes, 'a');
    hit(resumes, 'b', after: const Duration(hours: 3));
    await elapse(tester, const Duration(minutes: 30));
    setting.value = true;
    await elapse(tester, const Duration(minutes: 32));
    expect(resumed, ['a']);
    setting.value = false;
    await elapse(tester, const Duration(hours: 3));
    expect(resumed, ['a']);
    expect(resumes.entries, isEmpty);
  });

  testWidgets('not continued, it is tried again, then let go', (tester) async {
    var tries = 0;
    final resumes = make()
      ..resume = (id) async {
        tries++;
        return false;
      };
    hit(resumes, 'a');
    await elapse(tester, const Duration(hours: 1, minutes: 1));
    expect(tries, 1);
    await elapse(tester, const Duration(minutes: 1));
    expect(tries, 2);
    for (var i = 0; i < 10; i++) {
      await elapse(tester, const Duration(minutes: 1));
    }
    expect(tries, resumes.attempts);
    expect(resumes['a'], isNull);
  });

  testWidgets('waits for the workspace to continue them', (tester) async {
    final resumed = <String>[];
    final resumes = make();
    hit(resumes, 'a');
    await elapse(tester, const Duration(hours: 2));
    resumes.resume = (id) async {
      resumed.add(id);
      return true;
    };
    await elapse(tester, Duration.zero);
    expect(resumed, ['a']);
  });

  testWidgets('kept between runs: one due meanwhile goes on', (tester) async {
    final store = MemoryPreferenceStore();
    final before = make(store: store);
    hit(before, 'later', after: const Duration(hours: 5));
    hit(before, 'due');
    await tester.pump();

    now = now.add(const Duration(hours: 2));
    final resumed = <String>[];
    final after = make(store: store);
    await after.load();
    expect(
      [for (final entry in after.entries) entry.sessionId],
      ['due', 'later'],
    );
    after.resume = (id) async {
      resumed.add(id);
      return true;
    };
    await elapse(tester, Duration.zero);
    expect(resumed, ['due']);
    // Their timers, gone.
    before.dispose();
    after.dispose();
  });

  test('kept between runs, the setting off: those past are let go', () async {
    final store = MemoryPreferenceStore();
    final before = make(store: store);
    hit(before, 'later', after: const Duration(hours: 5));
    hit(before, 'past');
    await Future<void>.delayed(Duration.zero);
    before.dispose();

    setting.value = false;
    now = now.add(const Duration(hours: 2));
    final after = make(store: store);
    await after.load();
    expect([for (final entry in after.entries) entry.sessionId], ['later']);
    after.dispose();
  });

  testWidgets('the computer asleep past the reset: it goes on as it wakes', (
    tester,
  ) async {
    final resumed = <String>[];
    final resumes = make()
      ..resume = (id) async {
        resumed.add(id);
        return true;
      };
    hit(resumes, 'a');
    // The clock moved on two hours; the timers, as asleep, hardly.
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(resumed, ['a']);
  });

  test('a reset said that is past is nothing to wait for', () {
    final resumes = make();
    hit(resumes, 'a', after: -_hour);
    expect(resumes['a'], isNull);
  });

  testWidgets('removed, it does not go on', (tester) async {
    final resumed = <String>[];
    final resumes = make()
      ..resume = (id) async {
        resumed.add(id);
        return true;
      };
    hit(resumes, 'a');
    resumes.remove('a');
    await elapse(tester, const Duration(hours: 2));
    expect(resumed, isEmpty);
  });
}

final _start = DateTime(2026, 10, 13, 14);
const _hour = Duration(hours: 1);

class _FailingStore extends MemoryPreferenceStore {
  int writes = 0;

  @override
  Future<void> write(Map<String, Object?> preferences) async {
    writes++;
    throw StateError('模拟恢复任务保存失败');
  }
}
