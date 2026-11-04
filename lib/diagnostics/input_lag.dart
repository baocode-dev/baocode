import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../platform/event_log.dart';
import 'frame_watch.dart';
import 'jank_sample.dart';

/// Writes to the event log ([appEvent], under `input`) a key or a click in
/// an input that took [slow] or longer to show: from it to the end of the
/// frame after it, the parts its host timed ([time]: the search), and what
/// the host had then ([describe]).
///
/// What [FrameWatch] misses: a frame for each key, none of 250 ms, with
/// pauses between them. The IDE's find grew slow to type in and to click
/// as a window stayed open, until it was opened again, and nothing was
/// written (2MSCSKQ2).
class InputLag {
  InputLag(
    this.name, {
    this.slow = const Duration(milliseconds: 100),
    this.describe,
  });

  /// What the input is (`ide find`).
  final String name;

  final Duration slow;

  /// What the host has then: sizes and counts, never what the user wrote.
  String Function()? describe;

  /// Past this, a sample of the app's stacks for the seconds after, which
  /// the next keys (still slow) are in.
  static const _sampled = Duration(milliseconds: 250);

  static const _gap = Duration(seconds: 2);
  static const _most = 200;
  static int _written = 0;
  static int _lastWritten = -1 << 62;
  static JankSampler? _sampler;

  static final _clock = Stopwatch()..start();

  int _start = -1;
  int _frameStart = -1;
  String _what = '';
  final Map<String, int> _parts = {};

  /// A key or a click ([what]) in the input: timed to the end of the frame
  /// after it, unless one is timed already.
  void begin(String what) {
    final scheduler = SchedulerBinding.instance;
    // Hidden, the app draws no frames until it is shown again.
    if (_start >= 0 || !scheduler.framesEnabled) return;
    _start = _clock.elapsedMicroseconds;
    _frameStart = -1;
    _what = what;
    _parts.clear();
    scheduler.scheduleFrameCallback((_) {
      if (_frameStart < 0) _frameStart = _clock.elapsedMicroseconds;
    });
    scheduler.addPostFrameCallback((_) => _end());
    // A frame even when nothing changed: the end is timed by it.
    scheduler.scheduleFrame();
  }

  /// Runs [work], timed as [part] of what is timed; begun as a `change`
  /// when nothing is (text the input method sent).
  T time<T>(String part, T Function() work) {
    begin('change');
    if (_start < 0) return work();
    final start = _clock.elapsedMicroseconds;
    try {
      return work();
    } finally {
      _parts[part] = (_parts[part] ?? 0) + _clock.elapsedMicroseconds - start;
    }
  }

  void _end() {
    final start = _start;
    if (start < 0) return;
    final end = _clock.elapsedMicroseconds;
    final took = end - start;
    final frameStart = _frameStart;
    _start = -1;
    if (took < slow.inMicroseconds) return;
    if (_written >= _most) return;
    if (took < Duration.microsecondsPerSecond &&
        end - _lastWritten < _gap.inMicroseconds) {
      return;
    }
    _written++;
    _lastWritten = end;
    String ms(int micros) => '${(micros / 1000).round()}';
    final parts = [
      for (final MapEntry(:key, :value) in _parts.entries) '$key ${ms(value)}',
    ];
    final message = [
      '$name: a $_what shown after ${ms(took)} ms',
      if (frameStart >= 0)
        'before the frame ${ms(frameStart - start)} ms'
            '${parts.isEmpty ? '' : ' (${parts.join(', ')})'}, '
            'the frame ${ms(end - frameStart)} ms'
      else if (parts.isNotEmpty)
        parts.join(', '),
      if (describe?.call() case final state? when state.isNotEmpty) state,
      FrameWatch.describeState(),
    ];
    if (took < _sampled.inMicroseconds) {
      appEvent('input', message.join('; '));
      return;
    }
    final sampler = _sampler ??= switch (EventLog.current?.directory) {
      final folder? => JankSampler(folder),
      null => null,
    };
    unawaited(() async {
      if (await sampler?.sample() case final sample?) {
        message.insert(1, 'sample $sample (the ${sampler!.seconds} s after)');
      }
      appEvent('input', message.join('; '));
    }());
  }

  /// Starts over, for tests.
  static void debugReset() {
    _written = 0;
    _lastWritten = -1 << 62;
  }
}
