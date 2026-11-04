import 'dart:async';
import 'dart:io' show ProcessInfo;
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../platform/event_log.dart';
import 'jank_sample.dart';

/// Writes to the event log ([appEvent], under `slow`) a frame that held
/// the UI thread [FrameWatch.slow] or longer, or took as long to draw:
/// what its parts took, and what the app had then (the semantics tree and
/// its size, the render tree's, the conversations shown, memory). And
/// when the semantics tree comes and goes: something reading the window
/// (Windows' input methods, a screen reader) turns it on.
///
/// What a hang report (windows/runner/hang_watchdog.h) does not tell: the
/// state it came in, and the slow frames before it. A line only for a slow
/// frame, and not more than one each [_gap] (but those of a second or
/// more) nor [_most] in a run: a few kilobytes where all is well.
///
/// And, under `jank`, a stretch of frames each too short for a line of its
/// own but slow one after another (scrolling that stutters for minutes, the
/// CPU busy): what they took, as [JankWindow] sums them up; on the
/// desktops, with a sample of the app's stacks then ([JankSampler]), which
/// names the code they were in.
class FrameWatch {
  FrameWatch._(this.slow);

  /// Notes on what the app shows, each by what shows it (a conversation's
  /// view: its size): read only for a slow frame's line. Never what the
  /// user wrote.
  static final Map<Object, String Function()> notes = {};

  static FrameWatch? _current;

  /// Starts watching, once.
  static void start({Duration slow = const Duration(milliseconds: 250)}) {
    if (_current != null) return;
    final watch = _current = FrameWatch._(slow.inMicroseconds);
    final binding = WidgetsBinding.instance;
    // The dispatcher's frame callbacks are the scheduler's once it asks
    // for a frame: wrapped from the first.
    binding.addPersistentFrameCallback(watch._drawn);
    binding.addTimingsCallback(watch._timings);
    binding.addSemanticsEnabledListener(watch._semanticsChanged);
    if (binding.semanticsEnabled) watch._semanticsChanged();
  }

  static const _gap = Duration(seconds: 2);
  static const _most = 400;

  /// In microseconds.
  final int slow;

  final _clock = Stopwatch()..start();
  bool _wrapped = false;

  // This frame's times, in microseconds of [_clock]: its start, its
  // animations done, the build begun, built, laid out, painted and its
  // semantics sent (the scheduler's persistent callbacks run).
  int _begin = -1, _began = 0, _draw = 0, _built = 0;

  int _written = 0;
  int _lastWritten = -1 << 62;

  void _drawn(Duration _) {
    _built = _clock.elapsedMicroseconds;
    if (_wrapped) return;
    final dispatcher = PlatformDispatcher.instance;
    final begin = dispatcher.onBeginFrame;
    final draw = dispatcher.onDrawFrame;
    if (begin == null || draw == null) return;
    _wrapped = true;
    dispatcher
      ..onBeginFrame = (timeStamp) {
        _begin = _clock.elapsedMicroseconds;
        begin(timeStamp);
        _began = _clock.elapsedMicroseconds;
      }
      ..onDrawFrame = () {
        _draw = _clock.elapsedMicroseconds;
        draw();
        _ended();
      };
  }

  final JankWindow _jank = JankWindow();
  int _jankWritten = 0;
  int _lastJankWritten = -1 << 62;

  /// At most one `jank` line each [_jankGap], [_jankMost] in a run.
  static const _jankGap = Duration(seconds: 30);
  static const _jankMost = 200;

  void _ended() {
    if (_begin < 0) return;
    final end = _clock.elapsedMicroseconds;
    final took = end - _begin;
    _jank.addParts(
      took: took,
      animations: _began - _begin,
      microtasks: _draw - _began,
      build: _built - _draw,
      after: end - _built,
    );
    if (took < slow) return;
    String ms(int micros) => '${(micros / 1000).round()}';
    _write(
      took,
      'frame ${ms(took)} ms: animations ${ms(_began - _begin)}, '
      'microtasks ${ms(_draw - _began)}, '
      'build to semantics ${ms(_built - _draw)}, '
      'after ${ms(end - _built)}',
    );
  }

  void _timings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final summary = _jank.add(
        _clock.elapsedMicroseconds,
        ui: timing.buildDuration.inMicroseconds,
        raster: timing.rasterDuration.inMicroseconds,
      );
      if (summary != null) _writeJank(summary);
      final raster = timing.rasterDuration.inMicroseconds;
      if (raster < slow) continue;
      _write(
        raster,
        'raster ${timing.rasterDuration.inMilliseconds} ms '
        '(build ${timing.buildDuration.inMilliseconds} ms)',
      );
    }
  }

  void _write(int took, String what) {
    final now = _clock.elapsedMicroseconds;
    if (_written >= _most) return;
    if (took < Duration.microsecondsPerSecond &&
        now - _lastWritten < _gap.inMicroseconds) {
      return;
    }
    _written++;
    _lastWritten = now;
    appEvent('slow', '$what; ${describeState()}');
  }

  void _writeJank(String summary) {
    final now = _clock.elapsedMicroseconds;
    if (_jankWritten >= _jankMost ||
        now - _lastJankWritten < _jankGap.inMicroseconds) {
      return;
    }
    _jankWritten++;
    _lastJankWritten = now;
    final state = describeState();
    // Which code it is, a sample of the app's stacks says: taken as it
    // goes on.
    final sampler = _sampler ??= switch (EventLog.current?.directory) {
      final folder? => JankSampler(folder),
      null => null,
    };
    unawaited(() async {
      final sample = await sampler?.sample();
      appEvent(
        'jank',
        [summary, if (sample != null) 'sample $sample', state].join('; '),
      );
    }());
  }

  JankSampler? _sampler;

  void _semanticsChanged() {
    final on = WidgetsBinding.instance.semanticsEnabled;
    appEvent('semantics', on ? 'on' : 'off');
  }

  /// The trees' sizes, the conversations shown, memory, the app's state,
  /// and in a tree past [heavyObjects], where most of it is: a slow
  /// frame's, and a hang's as it ends (hang_watch.dart).
  static String describeState() {
    final binding = WidgetsBinding.instance;
    var objects = 0, nodes = 0;
    void visit(RenderObject object) {
      objects++;
      object.visitChildren(visit);
    }

    bool count(SemanticsNode node) {
      nodes++;
      node.visitChildren(count);
      return true;
    }

    for (final view in binding.renderViews) {
      visit(view);
      if (view.owner?.semanticsOwner?.rootSemanticsNode case final root?) {
        count(root);
      }
    }
    final shown = [
      for (final note in notes.values)
        if (note() case final text when text.isNotEmpty) text,
    ];
    final root = binding.rootElement;
    return [
      binding.semanticsEnabled ? 'semantics on, $nodes nodes' : 'semantics off',
      '$objects render objects',
      if (shown.isNotEmpty) 'chats ${shown.join(' / ')}',
      '${ProcessInfo.currentRss >> 20} MB',
      binding.lifecycleState?.name ?? 'no lifecycle',
      if (root != null && objects >= heavyObjects && _heavyDue())
        'heaviest ${heaviest(root)}',
    ].join('; ');
  }

  /// Past this many render objects, [describeState] also says where most of
  /// them are ([heaviest]). Some page of 1.8.0's held 42,000 (ZR8D6WP1, 15,000
  /// semantics nodes, frames of 1.5 s) and nothing told which.
  static const heavyObjects = 20000;

  /// [heaviest] walks the whole element tree: not more than once each
  /// [_heavyGap], [_heavyMost] in a run.
  static const _heavyGap = Duration(seconds: 30);
  static const _heavyMost = 20;
  static final _heavyClock = Stopwatch()..start();
  static int _heavyAt = -1 << 62;
  static int _heavyWritten = 0;

  static bool _heavyDue() {
    final now = _heavyClock.elapsedMicroseconds;
    if (_heavyWritten >= _heavyMost ||
        now - _heavyAt < _heavyGap.inMicroseconds) {
      return false;
    }
    _heavyWritten++;
    _heavyAt = now;
    return true;
  }

  /// Where most of the element tree under [root] is: down the child that
  /// holds half or more of it each time, to where none does (a list of
  /// many, a page of parts). The closest [names] widgets over that one
  /// (those built by code, the app's and the framework's), it, and its
  /// children's widgets, the largest [kinds] of them:
  /// `12000 elements, under A > B > C: Column, 9000 in 1500 children
  /// (_Row ×1500 8900, …)`.
  static String heaviest(Element root, {int names = 10, int kinds = 3}) {
    final sizes = Map<Element, int>.identity();
    int measure(Element element) {
      var size = 1;
      element.visitChildren((child) => size += measure(child));
      sizes[element] = size;
      return size;
    }

    final total = measure(root);
    final path = <String>[];
    var at = root;
    while (true) {
      final size = sizes[at]!;
      Element? top;
      var topSize = 0;
      at.visitChildren((child) {
        final childSize = sizes[child]!;
        if (childSize > topSize) {
          top = child;
          topSize = childSize;
        }
      });
      final next = top;
      if (next == null || topSize * 2 < size) break;
      if (at is StatelessElement || at is StatefulElement) {
        final name = at.widget.runtimeType.toString();
        if (path.isEmpty || path.last != name) path.add(name);
      }
      at = next;
    }
    final byKind = <String, (int, int)>{};
    var children = 0;
    at.visitChildren((child) {
      children++;
      final kind = child.widget.runtimeType.toString();
      final (count, size) = byKind[kind] ?? (0, 0);
      byKind[kind] = (count + 1, size + sizes[child]!);
    });
    final ranked = byKind.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final over = path.length > names ? path.sublist(path.length - names) : path;
    return [
      '$total elements',
      if (over.isNotEmpty) ', under ${over.join(' > ')}',
      ': ${at.widget.runtimeType}, ${sizes[at]} in $children children',
      if (ranked.isNotEmpty)
        ' (${[for (final MapEntry(key: kind, value: (count, size)) in ranked.take(kinds)) '$kind ×$count $size', if (ranked.length > kinds) '…'].join(', ')})',
    ].join();
  }
}

/// Frames summed up [span] at a time: a summary of a span in which at
/// least [least] of them, and a quarter, were slow (over [slowFrame] on the
/// UI thread or in raster), else nothing. A pause of [pause] or more without
/// frames starts it over: the app at rest is not slow.
class JankWindow {
  JankWindow({
    this.span = const Duration(seconds: 5),
    this.slowFrame = const Duration(milliseconds: 32),
    this.least = 10,
    this.pause = const Duration(seconds: 1),
  });

  final Duration span;
  final Duration slowFrame;
  final int least;
  final Duration pause;

  int _start = -1;
  int _last = -1;
  int _frames = 0;
  int _slow = 0;
  int _uiSum = 0, _uiMax = 0;
  int _rasterSum = 0, _rasterMax = 0;

  // Where the slow frames' UI time went, as FrameWatch measures it.
  int _parted = 0;
  int _animations = 0, _microtasks = 0, _build = 0, _after = 0;

  /// A frame drawn at [now] (microseconds, of any clock), and what it took
  /// on the UI thread and in raster: the span's summary once it is over and
  /// was slow.
  String? add(int now, {required int ui, required int raster}) {
    if (_start >= 0 && now - _last >= pause.inMicroseconds) _reset(-1);
    if (_start < 0) _reset(now);
    _last = now;
    _frames++;
    final threshold = slowFrame.inMicroseconds;
    if (ui >= threshold || raster >= threshold) _slow++;
    _uiSum += ui;
    _rasterSum += raster;
    if (ui > _uiMax) _uiMax = ui;
    if (raster > _rasterMax) _rasterMax = raster;
    if (now - _start < span.inMicroseconds) return null;
    final summary = _slow >= least && _slow * 4 >= _frames
        ? _summary(now)
        : null;
    _reset(-1);
    return summary;
  }

  /// A frame's UI time in its parts (see FrameWatch): kept for the slow ones.
  void addParts({
    required int took,
    required int animations,
    required int microtasks,
    required int build,
    required int after,
  }) {
    if (took < slowFrame.inMicroseconds) return;
    _parted++;
    _animations += animations;
    _microtasks += microtasks;
    _build += build;
    _after += after;
  }

  void _reset(int start) {
    _start = start;
    _last = start;
    _frames = _slow = 0;
    _uiSum = _uiMax = _rasterSum = _rasterMax = 0;
    _parted = _animations = _microtasks = _build = _after = 0;
  }

  String _summary(int now) {
    String ms(int micros) => '${(micros / 1000).round()}';
    String average(int sum, int count) => ms(count == 0 ? 0 : sum ~/ count);
    final seconds = ((now - _start) / Duration.microsecondsPerSecond).round();
    return [
      '$seconds s: $_frames frames, $_slow over ${slowFrame.inMilliseconds} ms',
      'ui avg ${average(_uiSum, _frames)} max ${ms(_uiMax)} ms',
      'raster avg ${average(_rasterSum, _frames)} max ${ms(_rasterMax)} ms',
      if (_parted > 0)
        'slow ui frames avg: animations ${average(_animations, _parted)}, '
            'microtasks ${average(_microtasks, _parted)}, '
            'build to semantics ${average(_build, _parted)}, '
            'after ${average(_after, _parted)}',
    ].join('; ');
  }
}
