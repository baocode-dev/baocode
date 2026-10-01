// Copyright (c) 2022 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/DecorationService.ts (c58ea36).

import '../../typings/xterm.dart' show IDecoration, IDecorationOptions, IMarker;
import '../async.dart';
import '../circular_list.dart';
import '../color.dart';
import '../event.dart';
import '../lifecycle.dart';
import '../sorted_list.dart';
import '../types.dart';
import 'services.dart';

class DecorationService extends Disposable implements IDecorationService {
  DecorationService(this._logService, this._bufferService) {
    _lineCache = register(DecorationLineCache());
    _onDecorationRegistered = register(Emitter<IInternalDecoration>());
    onDecorationRegistered = _onDecorationRegistered.event;
    _onDecorationRemoved = register(Emitter<IInternalDecoration>());
    onDecorationRemoved = _onDecorationRemoved.event;

    _decorations = SortedList<IInternalDecoration>(
      (e) => e.marker.line,
      _logService,
    );

    register(toDisposable(() => reset()));
    register(
      _bufferService.buffers.onBufferActivate((_) {
        _lineCache.attachToBufferLines(_bufferService.buffer.lines);
      }),
    );
    _lineCache.attachToBufferLines(_bufferService.buffer.lines);
  }

  final ILogService _logService;
  final IBufferService _bufferService;

  /// A list of all decorations, sorted by the marker's line value. This
  /// relies on the fact that while marker line values do change, they should
  /// all change by the same amount so this should never become out of order.
  late final SortedList<IInternalDecoration> _decorations;

  late final DecorationLineCache _lineCache;

  late final Emitter<IInternalDecoration> _onDecorationRegistered;
  @override
  late final IEvent<IInternalDecoration> onDecorationRegistered;
  late final Emitter<IInternalDecoration> _onDecorationRemoved;
  @override
  late final IEvent<IInternalDecoration> onDecorationRemoved;

  @override
  Iterable<IInternalDecoration> get decorations => _decorations.values();

  @override
  IDecoration? registerDecoration(IDecorationOptions options) {
    if (options.marker.isDisposed) {
      return null;
    }
    final decoration = Decoration(options);
    final markerDispose = decoration.marker.onDispose(
      (_) => decoration.dispose(),
    );
    late final IDisposable listener;
    listener = decoration.onDispose((_) {
      listener.dispose();
      if (_decorations.delete(decoration)) {
        _lineCache.remove(decoration);
        _onDecorationRemoved.fire(decoration);
      }
      markerDispose.dispose();
    });
    _decorations.insert(decoration);
    _lineCache.add(decoration);
    _onDecorationRegistered.fire(decoration);
    return decoration;
  }

  @override
  void reset() {
    for (final d in _decorations.values()) {
      d.dispose();
    }
    _decorations.clear();
    _lineCache.clear();
  }

  /// The decorations at a cell; [layer] is `'bottom'`, `'top'` or null (any).
  Iterable<IInternalDecoration> getDecorationsAtCell(
    int x,
    int line, [
    String? layer,
  ]) sync* {
    final bucket = _lineCache.getDecorationsOnLine(line);
    if (bucket == null) {
      return;
    }
    for (final d in bucket) {
      final xmin = d.options.x ?? 0;
      final xmax = xmin + (d.options.width ?? 1);
      if (x >= xmin &&
          x < xmax &&
          (layer == null || (d.options.layer ?? 'bottom') == layer)) {
        yield d;
      }
    }
  }

  @override
  void forEachDecorationAtCell(
    int x,
    int line,
    String? layer,
    void Function(IInternalDecoration decoration) callback,
  ) {
    final bucket = _lineCache.getDecorationsOnLine(line);
    if (bucket == null) {
      return;
    }
    for (final d in bucket) {
      final xmin = d.options.x ?? 0;
      final xmax = xmin + (d.options.width ?? 1);
      if (x >= xmin &&
          x < xmax &&
          (layer == null || (d.options.layer ?? 'bottom') == layer)) {
        callback(d);
      }
    }
  }
}

/// Per-logical-line index of decorations for fast cell lookup.
///
/// Keys are marker.line coordinates (logical buffer lines), not CircularList
/// ring slots. Multi-line decorations appear in every line bucket they span.
/// The index is kept aligned with marker.line updates via buffer line
/// trim/insert/delete events.
class DecorationLineCache extends Disposable {
  DecorationLineCache() {
    _bufferLineListeners = register(MutableDisposable<DisposableStore>());
    _lineIndexSyncTimer = register(MicrotaskTimer());
  }

  final Map<int, List<IInternalDecoration>> _decorationsByLine =
      <int, List<IInternalDecoration>>{};
  final Set<IInternalDecoration> _decorations = <IInternalDecoration>{};
  late final MutableDisposable<DisposableStore> _bufferLineListeners;
  late final MicrotaskTimer _lineIndexSyncTimer;
  List<void Function()> _lineIndexSyncCallbacks = <void Function()>[];

  void clear() {
    _lineIndexSyncCallbacks.clear();
    _lineIndexSyncTimer.cancel();
    _decorationsByLine.clear();
    _decorations.clear();
  }

  void add(IInternalDecoration decoration) {
    _decorations.add(decoration);
    _addToLineBuckets(decoration);
  }

  void remove(IInternalDecoration decoration) {
    _decorations.remove(decoration);
    _removeFromLineBuckets(decoration);
  }

  List<IInternalDecoration>? getDecorationsOnLine(int line) {
    return _decorationsByLine[line];
  }

  void attachToBufferLines(ICircularList<Object?> lines) {
    final store = DisposableStore();
    _bufferLineListeners.value = store;
    store.add(lines.onTrim((amount) => _handleBufferLinesTrim(amount)));
    store.add(lines.onInsert((event) => _handleBufferLinesInsert(event)));
    store.add(lines.onDelete((event) => _handleBufferLinesDelete(event)));
  }

  int _getDecorationHeight(IInternalDecoration decoration) {
    return decoration.options.height ?? 1;
  }

  void _addToLineBuckets(IInternalDecoration decoration) {
    final start = decoration.marker.line;
    if (start < 0) {
      return;
    }
    decoration.indexedStartLine = start;
    final height = _getDecorationHeight(decoration);
    for (var line = start; line < start + height; line++) {
      final bucket = _decorationsByLine.putIfAbsent(
        line,
        () => <IInternalDecoration>[],
      );
      bucket.add(decoration);
    }
  }

  void _removeFromLineBuckets(IInternalDecoration decoration) {
    final start = decoration.indexedStartLine;
    final height = _getDecorationHeight(decoration);
    for (var line = start; line < start + height; line++) {
      final bucket = _decorationsByLine[line];
      if (bucket == null) {
        continue;
      }
      final index = bucket.indexOf(decoration);
      if (index != -1) {
        bucket.removeAt(index);
      }
      if (bucket.isEmpty) {
        _decorationsByLine.remove(line);
      }
    }
  }

  void _reindexDecoration(IInternalDecoration decoration) {
    _removeFromLineBuckets(decoration);
    if (!decoration.marker.isDisposed && decoration.marker.line >= 0) {
      _addToLineBuckets(decoration);
    }
  }

  /// Re-index after marker line updates (buffer listeners may run before
  /// markers).
  void _scheduleLineIndexSync(void Function() callback) {
    _lineIndexSyncCallbacks.add(callback);
    _lineIndexSyncTimer.set(() {
      final callbacks = _lineIndexSyncCallbacks;
      _lineIndexSyncCallbacks = <void Function()>[];
      for (final cb in callbacks) {
        cb();
      }
    });
  }

  void _handleBufferLinesTrim(int amount) {
    if (amount <= 0 || _decorationsByLine.isEmpty) {
      return;
    }
    final newMap = <int, List<IInternalDecoration>>{};
    for (final MapEntry(key: line, value: bucket)
        in _decorationsByLine.entries) {
      final newLine = line - amount;
      if (newLine < 0) {
        continue;
      }
      _mergeLineBucket(newMap, newLine, bucket);
    }
    _decorationsByLine.clear();
    _decorationsByLine.addAll(newMap);
    for (final d in _decorations) {
      if (!d.marker.isDisposed) {
        d.indexedStartLine -= amount;
      }
    }
  }

  void _handleBufferLinesInsert(IInsertEvent event) {
    _scheduleLineIndexSync(() => _applyBufferLinesInsert(event));
  }

  void _handleBufferLinesDelete(IDeleteEvent event) {
    _scheduleLineIndexSync(() => _applyBufferLinesDelete(event));
  }

  void _mergeLineBucket(
    Map<int, List<IInternalDecoration>> newMap,
    int line,
    List<IInternalDecoration> bucket,
  ) {
    final existing = newMap[line];
    if (existing != null) {
      for (var i = 0, len = bucket.length; i < len; i++) {
        existing.add(bucket[i]);
      }
    } else {
      newMap[line] = List<IInternalDecoration>.of(bucket);
    }
  }

  /// Shift indexed line keys and sync start lines. O(unique indexed lines),
  /// not O(decoration count). Decorations that span the insert point are
  /// re-indexed individually (rare vs single-line hits).
  void _applyBufferLinesInsert(IInsertEvent event) {
    final index = event.index;
    final amount = event.amount;
    final spanCrossers = <IInternalDecoration>[];
    for (final d in _decorations) {
      if (d.marker.isDisposed) {
        continue;
      }
      final start = d.indexedStartLine;
      if (start < index && start + _getDecorationHeight(d) > index) {
        spanCrossers.add(d);
        _removeFromLineBuckets(d);
      }
    }
    final newMap = <int, List<IInternalDecoration>>{};
    for (final MapEntry(key: line, value: bucket)
        in _decorationsByLine.entries) {
      final newLine = line >= index ? line + amount : line;
      _mergeLineBucket(newMap, newLine, bucket);
    }
    _decorationsByLine.clear();
    _decorationsByLine.addAll(newMap);
    for (final d in _decorations) {
      if (d.marker.isDisposed) {
        continue;
      }
      if (d.indexedStartLine >= index) {
        d.indexedStartLine = d.marker.line;
      }
    }
    for (final d in spanCrossers) {
      _addToLineBuckets(d);
    }
  }

  /// Drop deleted line keys, shift keys below, sync start lines. Full
  /// re-index only when a multi-line decoration spans across the deleted
  /// range but survives.
  void _applyBufferLinesDelete(IDeleteEvent event) {
    final deleteEnd = event.index + event.amount;
    final newMap = <int, List<IInternalDecoration>>{};
    for (final MapEntry(key: line, value: bucket)
        in _decorationsByLine.entries) {
      if (line >= event.index && line < deleteEnd) {
        continue;
      }
      final newLine = line >= deleteEnd ? line - event.amount : line;
      _mergeLineBucket(newMap, newLine, bucket);
    }
    _decorationsByLine.clear();
    _decorationsByLine.addAll(newMap);
    final toReindex = <IInternalDecoration>[];
    for (final d in _decorations) {
      if (d.marker.isDisposed) {
        continue;
      }
      final start = d.indexedStartLine;
      final height = _getDecorationHeight(d);
      if (start >= deleteEnd) {
        d.indexedStartLine = d.marker.line;
      } else if (start < event.index && start + height > deleteEnd) {
        toReindex.add(d);
      }
    }
    for (final d in toReindex) {
      _reindexDecoration(d);
    }
  }
}

class Decoration extends DisposableStore implements IInternalDecoration {
  Decoration(this.options)
    : marker = options.marker,
      indexedStartLine = options.marker.line {
    onRenderEmitter = add(Emitter<Object>());
    onRender = onRenderEmitter.event;
    _onDispose = add(Emitter<void>());
    onDispose = _onDispose.event;
    final overviewRulerOptions = options.overviewRulerOptions;
    if (overviewRulerOptions != null &&
        (overviewRulerOptions.position == null ||
            overviewRulerOptions.position!.isEmpty)) {
      overviewRulerOptions.position = 'full';
    }
  }

  @override
  final IDecorationOptions options;
  @override
  final IMarker marker;

  /// The renderer's element (`HTMLElement` upstream).
  @override
  Object? element;

  /// Start line used for line-index removal when marker.line is cleared on
  /// dispose.
  @override
  int indexedStartLine;

  @override
  late final Emitter<Object> onRenderEmitter;
  @override
  late final IEvent<Object> onRender;
  late final Emitter<void> _onDispose;
  @override
  late final IEvent<void> onDispose;

  bool _isCachedBgSet = false;
  IColor? _cachedBg;
  @override
  IColor? get backgroundColorRGB {
    if (!_isCachedBgSet) {
      final backgroundColor = options.backgroundColor;
      if (backgroundColor != null && backgroundColor.isNotEmpty) {
        _cachedBg = css.toColor(backgroundColor);
      } else {
        _cachedBg = null;
      }
      _isCachedBgSet = true;
    }
    return _cachedBg;
  }

  bool _isCachedFgSet = false;
  IColor? _cachedFg;
  @override
  IColor? get foregroundColorRGB {
    if (!_isCachedFgSet) {
      final foregroundColor = options.foregroundColor;
      if (foregroundColor != null && foregroundColor.isNotEmpty) {
        _cachedFg = css.toColor(foregroundColor);
      } else {
        _cachedFg = null;
      }
      _isCachedFgSet = true;
    }
    return _cachedFg;
  }

  @override
  void dispose() {
    _onDispose.fire(null);
    super.dispose();
  }
}
