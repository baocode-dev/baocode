// What the perf app measures while a scenario's phase runs:
// - the frames: build (the UI isolate's build, layout and paint) and
//   raster times, and those over the display's frame budget;
// - the UI isolate's stalls: a timer due every few milliseconds, and how
//   late it fires (frames and all else the isolate does in between);
// - latencies: from something happening (a key typed, a delta read from
//   the CLI) to the end of the next frame on the UI isolate (`toScene`),
//   and, the engine's clock being the timeline's, to that frame's raster
//   finishing (`toRaster`);
// - the process's CPU time and memory: its physical footprint, the GPU's
//   part in it (see perf_memory.dart);
// - the GPU's time, the process's and WindowServer's, compositing it.

import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;

import 'package:flutter/scheduler.dart';

import 'perf_memory.dart';

/// What a latency is from.
enum PerfMark {
  /// A delta of streamed text, read from the CLI.
  delta,

  /// A key, typed.
  key,

  /// A wheel notch or a trackpad move.
  scroll,

  /// A mouse move with the button held: a sash, a selection, an agent
  /// dragged.
  drag,

  /// Something else a scenario does and waits to see, e.g. a click.
  action,
}

/// Percentiles of [values], rounded to 0.01.
Map<String, num> stats(List<double> values) {
  if (values.isEmpty) return const {'n': 0};
  final sorted = [...values]..sort();
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  double round(double v) => (v * 100).roundToDouble() / 100;
  final mean = sorted.fold(0.0, (a, b) => a + b) / sorted.length;
  return {
    'n': sorted.length,
    'mean': round(mean),
    'p50': round(at(0.5)),
    'p90': round(at(0.9)),
    'p99': round(at(0.99)),
    'max': round(sorted.last),
  };
}

double _ms(int micros) => micros / 1000;

int _mb(int bytes) => (bytes / 1048576).round();

class PerfProbe {
  PerfProbe._();

  static final PerfProbe instance = PerfProbe._();

  bool _installed = false;
  PerfRecording? _recording;

  /// The frame budget: the display's refresh rate's.
  double get budgetMs {
    final rate = PlatformDispatcher.instance.displays.firstOrNull?.refreshRate;
    return 1000 / (rate == null || rate < 30 ? 60 : rate);
  }

  double get refreshRate => 1000 / budgetMs;

  /// Whether FrameTiming's timestamps are on the timeline's clock (the
  /// engine sets it so): checked on the first frames, a frame callback's
  /// time falling within one of theirs.
  bool? clockShared;
  final List<int> _calibration = [];

  void install() {
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  /// Records until [PerfRecording.stop]; one at a time.
  PerfRecording start(String label) {
    assert(_recording == null, 'already recording ${_recording?.label}');
    return _recording = PerfRecording._(this, label);
  }

  /// [kind] happened now: the next frame shows it.
  void mark(PerfMark kind) => _recording?._mark(kind);

  /// The scenario asked for frames itself (to let the app settle): the
  /// phase's frames say nothing of what the app asks for at rest.
  void forceFrames() => _recording?.forced = true;

  /// Something outside the scenario happened ([why]): another app came to
  /// the front, say. The phase under way is marked: its figures may say
  /// more about that than about the app.
  void disturb(String why) {
    stderr.writeln(
      'BAOCODE_PERF_LOG disturbed: $why'
      '${_recording == null ? '' : ' (${_recording!.label}, ${_recording!._watch.elapsedMilliseconds}ms in)'}',
    );
    _recording?.disturbed.add(why);
  }

  /// The latencies' end: called after each frame is composited (persistent
  /// frame callbacks run in order, the renderer's first).
  void _onFrame(Duration _) {
    final now = Timeline.now;
    if (clockShared == null && _calibration.length < 30) {
      _calibration.add(now);
    }
    _recording?._frame(now);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (clockShared == null && _calibration.isNotEmpty) {
      for (final timing in timings) {
        final start = timing.timestampInMicroseconds(FramePhase.buildStart);
        // The callback runs after the scene went to the raster thread,
        // which may have started on it meanwhile.
        final end = timing.timestampInMicroseconds(FramePhase.rasterFinish);
        if (_calibration.any((t) => t >= start && t <= end)) {
          clockShared = true;
          break;
        }
      }
      if (clockShared == null && _calibration.length >= 30) {
        clockShared = false;
      }
    }
    _recording?._timings.addAll(timings);
  }
}

class PerfRecording {
  PerfRecording._(this._probe, this.label)
    : _startGpu = PerfProcess.gpuNs(),
      _startUs = Timeline.now,
      _startCpu = PerfProcess.cpuMs(),
      _startFootprint = PerfProcess.footprint() {
    _watch.start();
    _beat();
  }

  final PerfProbe _probe;
  final String label;
  final int _startUs;
  int? _stopUs;
  final double? _startCpu;
  final ({int own, int windowServer})? _startGpu;
  final int _startFootprint;
  int _peakFootprint = 0;
  final Stopwatch _watch = Stopwatch();
  final List<FrameTiming> _timings = [];
  int _frames = 0;

  /// Marks not yet seen in a frame, by when they were made.
  final List<(PerfMark, int)> _pending = [];
  final Map<PerfMark, List<double>> _toScene = {};
  final Map<PerfMark, List<int>> _marked = {};
  int _unseen = 0;

  /// Late heartbeats, in ms.
  final List<double> _late = [];
  Timer? _heartbeat;
  static const _beatInterval = Duration(milliseconds: 4);

  /// Figures the scenario adds itself, e.g. how long a file took to open.
  final Map<String, Object> extra = {};

  /// What disturbed it (see [PerfProbe.disturb]).
  final Set<String> disturbed = {};

  /// Whether the scenario asked for frames itself (see
  /// [PerfProbe.forceFrames]).
  bool forced = false;

  void _beat() {
    final due = _watch.elapsedMicroseconds + _beatInterval.inMicroseconds;
    _heartbeat = Timer(_beatInterval, () {
      _late.add(
        _ms(_watch.elapsedMicroseconds - due).clamp(0, double.infinity),
      );
      if (_late.length % 16 == 0) {
        final footprint = PerfProcess.footprint();
        if (footprint > _peakFootprint) _peakFootprint = footprint;
      }
      _beat();
    });
  }

  void _mark(PerfMark kind) {
    final now = Timeline.now;
    _pending.add((kind, now));
    (_marked[kind] ??= []).add(now);
  }

  void _frame(int now) {
    _frames++;
    for (final (kind, at) in _pending) {
      final waited = now - at;
      // Seen by no frame for a second: it showed nothing.
      if (waited > 1000000) {
        _unseen++;
      } else {
        (_toScene[kind] ??= []).add(_ms(waited));
      }
    }
    _pending.clear();
  }

  /// Stops, waits for the engine to report the last frames' timings, and
  /// gives what was measured.
  Future<Map<String, Object>> stop() async {
    _stopUs = Timeline.now;
    _heartbeat?.cancel();
    final cpu = PerfProcess.cpuMs();
    final wall = _watch.elapsedMicroseconds;
    final gpu = PerfProcess.gpuNs();
    final footprint = PerfProcess.footprint();
    if (footprint > _peakFootprint) _peakFootprint = footprint;
    final parts = await PerfProcess.parts();
    final frames = _frames;
    final toScene = {
      for (final MapEntry(:key, :value) in _toScene.entries)
        key.name: stats(value),
    };
    // The timings come in batches, a while after their frames.
    final more = Completer<void>();
    Timer(const Duration(milliseconds: 600), more.complete);
    SchedulerBinding.instance.scheduleFrame();
    await more.future;
    _probe._recording = null;
    return _report(
      wallUs: wall,
      cpu: cpu,
      gpu: gpu,
      frames: frames,
      toScene: toScene,
      footprint: footprint,
      parts: parts,
    );
  }

  Map<String, Object> _report({
    required int wallUs,
    required double? cpu,
    required ({int own, int windowServer})? gpu,
    required int frames,
    required Map<String, Object> toScene,
    required int footprint,
    required Map<String, int>? parts,
  }) {
    final shared = _probe.clockShared ?? false;
    // On a shared clock, only this phase's frames; else all reported while
    // it ran, a few of just before and after among them.
    final timings = [
      for (final t in _timings)
        if (!shared ||
            (t.timestampInMicroseconds(FramePhase.vsyncStart) >= _startUs &&
                t.timestampInMicroseconds(FramePhase.vsyncStart) <= _stopUs!))
          t,
    ];
    final budget = _probe.budgetMs;
    final build = [
      for (final t in timings) _ms(t.buildDuration.inMicroseconds),
    ];
    final raster = [
      for (final t in timings) _ms(t.rasterDuration.inMicroseconds),
    ];
    final total = [for (final t in timings) _ms(t.totalSpan.inMicroseconds)];
    final wallMs = _ms(wallUs);

    // From each mark to the raster end of the first frame built after it.
    final toRaster = <String, Object>{};
    if (shared) {
      final starts = [
        for (final t in timings)
          (
            t.timestampInMicroseconds(FramePhase.buildStart),
            t.timestampInMicroseconds(FramePhase.rasterFinish),
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      for (final MapEntry(:key, :value) in _marked.entries) {
        final latencies = <double>[];
        var i = 0;
        for (final at in value) {
          while (i < starts.length && starts[i].$1 < at) {
            i++;
          }
          if (i == starts.length) break;
          final waited = starts[i].$2 - at;
          if (waited < 1000000) latencies.add(_ms(waited));
        }
        toRaster[key.name] = stats(latencies);
      }
    }

    final stalled = _late
        .where((late) => late > budget)
        .fold(0.0, (a, b) => a + b);
    return {
      'wallMs': wallMs.round(),
      'frames': {
        'count': timings.length,
        'perSecond': (timings.length / wallMs * 1000).round(),
        'budgetMs': (budget * 100).round() / 100,
        'buildMs': stats(build),
        'rasterMs': stats(raster),
        'totalMs': stats(total),
        // Frames whose UI or raster work alone took more than the budget:
        // each misses at least one refresh.
        'janky': timings
            .where(
              (t) =>
                  _ms(t.buildDuration.inMicroseconds) > budget ||
                  _ms(t.rasterDuration.inMicroseconds) > budget,
            )
            .length,
        'over33ms': total.where((ms) => ms > 33.4).length,
        'uiFramesSeen': frames,
      },
      'uiIsolate': {
        // How late a timer due every 4ms fired.
        'lateMs': stats(_late),
        // Of the time it ran, how much the isolate was held for longer than
        // a frame: what the user feels as hitches.
        'stalledMs': stalled.round(),
        'stalls50ms': _late.where((late) => late > 50).length,
        // The isolate's share in frames, build to composite.
        'framesBusyPct': (build.fold(0.0, (a, b) => a + b) / wallMs * 100)
            .round(),
      },
      if (toScene.isNotEmpty) 'toSceneMs': toScene,
      if (toRaster.isNotEmpty) 'toRasterMs': toRaster,
      if (_unseen > 0) 'unseenMarks': _unseen,
      if (disturbed.isNotEmpty) 'disturbed': disturbed.toList(),
      if (forced) 'forcedFrames': true,
      if (cpu != null && _startCpu != null)
        'cpu': {
          'ms': (cpu - _startCpu).round(),
          // Of one core, all the process's threads: UI, raster, workers.
          'pctOfCore': ((cpu - _startCpu) / wallMs * 100).round(),
        },
      if ((gpu, _startGpu) case (final end?, final start?))
        'gpu': {
          // Of the GPU's time: busy for the app's frames, and for
          // WindowServer's (the app's window and all others, composited).
          'pct': ((end.own - start.own) / 1000 / wallUs * 1000).round() / 10,
          'windowServerPct':
              ((end.windowServer - start.windowServer) / 1000 / wallUs * 1000)
                  .round() /
              10,
        },
      // The physical footprint: at the start, its peak (sampled every
      // 64ms), at the end, and the end's parts.
      'memoryMb': {
        'start': _mb(_startFootprint),
        'peak': _mb(_peakFootprint),
        'end': _mb(footprint),
        'growth': _mb(footprint - _startFootprint),
        if (parts != null)
          for (final MapEntry(:key, :value) in parts.entries) key: _mb(value),
      },
      ...extra,
    };
  }
}
