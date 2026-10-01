// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/input/WriteBuffer.ts (c58ea36).
//
// A chunk is a `String` or a `Uint8List` (upstream `string | Uint8Array`).

import 'dart:async';
import 'dart:typed_data';

import '../async.dart';
import '../event.dart';
import '../lifecycle.dart';

abstract final class _Constants {
  /// Safety watermark to avoid memory exhaustion and browser engine crash on
  /// fast data input. Enable flow control to avoid this limit and make sure
  /// that your backend correctly propagates this to the underlying pty. (see
  /// docs for further instructions) Since this limit is meant as a safety
  /// parachute to prevent browser crashs, it is set to a very high number.
  /// Typically xterm.js gets unresponsive with a 100 times lower number
  /// (>500 kB).
  static const int discardWatermark = 50000000; // ~50 MB

  /// The max number of ms to spend on writes before allowing the renderer to
  /// catch up with a 0ms setTimeout. A value of < 33 to keep us close to
  /// 30fps, and a value of < 16 to try to run at 60fps. Of course, the real
  /// FPS depends on the time it takes for the renderer to draw the frame.
  static const int writeTimeoutMs = 12;

  /// Threshold of max held chunks in the write buffer, that were already
  /// processed. This is a tradeoff between extensive write buffer shifts (bad
  /// runtime) and high memory consumption by data thats not used anymore.
  static const int writeBufferLengthThreshold = 50;
}

/// Upstream's `performance.now()`.
final Stopwatch _clock = Stopwatch()..start();

double _now() => _clock.elapsedMicroseconds / 1000.0;

/// `data.length` of a `String` or `Uint8List` chunk.
int _lengthOf(Object data) =>
    data is String ? data.length : (data as Uint8List).length;

/// JavaScript's `array.shift()`: the first element, or null when empty.
T? _shift<T>(List<T> list) => list.isEmpty ? null : list.removeAt(0);

/// JavaScript truthiness of a chunk: the empty string is falsy, an empty
/// `Uint8List` (an object) is not.
bool _isTruthy(Object? chunk) =>
    chunk != null && !(chunk is String && chunk.isEmpty);

class WriteBuffer extends Disposable {
  /// [_action] parses a chunk (a `String` or a `Uint8List`); it returns a
  /// future when a handler went async (upstream `void | Promise<boolean>`).
  WriteBuffer(this._action) {
    _innerWriteTimer = register(TimeoutTimer());
    _onWriteParsed = register(Emitter<void>());
    onWriteParsed = _onWriteParsed.event;
    register(
      toDisposable(() {
        _writeBuffer.clear();
        _callbacks.clear();
        _pendingData = 0;
        _bufferOffset = 0;
      }),
    );
  }

  final Future<bool>? Function(Object data, [bool? promiseResult]) _action;

  List<Object> _writeBuffer = <Object>[];
  List<void Function()?> _callbacks = <void Function()?>[];
  int _pendingData = 0;
  int _bufferOffset = 0;
  bool _isSyncWriting = false;
  int _syncCalls = 0;
  bool _didUserInput = false;

  late final TimeoutTimer _innerWriteTimer;
  late final Emitter<void> _onWriteParsed;
  late final IEvent<void> onWriteParsed;

  void handleUserInput() {
    _didUserInput = true;
  }

  /// Flushes all pending writes synchronously. This is useful when you need
  /// to ensure all queued data is processed before performing an operation
  /// that depends upon everything being parsed like resize.
  ///
  /// Note: This is unreliable with async parser handlers as it does not wait
  /// for promises to resolve.
  void flushSync() {
    if (store.isDisposed) {
      return;
    }
    // exit early if another sync write loop is active
    if (_isSyncWriting) {
      return;
    }
    _isSyncWriting = true;

    // Process all pending chunks synchronously
    Object? chunk;
    var didProcess = false;
    while (_isTruthy(chunk = _shift(_writeBuffer))) {
      didProcess = true;
      _action(chunk!);
      final cb = _shift(_callbacks);
      if (cb != null) cb();
    }

    // Reset buffer state
    _pendingData = 0;
    _bufferOffset = 0x7FFFFFFF;
    _writeBuffer.clear();
    _callbacks.clear();

    _isSyncWriting = false;
    if (didProcess) {
      _onWriteParsed.fire(null);
    }
  }

  /// Deprecated upstream: unreliable, to be removed soon. (Not annotated
  /// `@Deprecated`, so that the ported callers analyze cleanly.)
  void writeSync(Object data, [int? maxSubsequentCalls]) {
    if (store.isDisposed) {
      return;
    }
    // stop writeSync recursions with maxSubsequentCalls argument
    // This is dangerous to use as it will lose the current data chunk
    // and return immediately.
    if (maxSubsequentCalls != null && _syncCalls > maxSubsequentCalls) {
      // comment next line if a whole loop block should only contain x
      // `writeSync` calls (total flat vs. deep nested limit)
      _syncCalls = 0;
      return;
    }
    // append chunk to buffer
    _pendingData += _lengthOf(data);
    _writeBuffer.add(data);
    _callbacks.add(null);

    // increase recursion counter
    _syncCalls++;
    // exit early if another writeSync loop is active
    if (_isSyncWriting) {
      return;
    }
    _isSyncWriting = true;

    // force sync processing on pending data chunks to avoid in-band data
    // scrambling does the same as innerWrite but without event loop
    // we have to do it here as single loop steps to not corrupt loop subject
    // by another writeSync call triggered from _action
    Object? chunk;
    while (_isTruthy(chunk = _shift(_writeBuffer))) {
      _action(chunk!);
      final cb = _shift(_callbacks);
      if (cb != null) cb();
    }
    // reset to avoid reprocessing of chunks with scheduled innerWrite call
    // stopping scheduled innerWrite by offset > length condition
    _pendingData = 0;
    _bufferOffset = 0x7FFFFFFF;

    // allow another writeSync to loop
    _isSyncWriting = false;
    _syncCalls = 0;
  }

  void write(Object data, [void Function()? callback]) {
    if (store.isDisposed) {
      return;
    }
    if (_pendingData > _Constants.discardWatermark) {
      throw StateError(
        'write data discarded, use flow control to avoid losing data',
      );
    }

    // schedule chunk processing for next event loop run
    if (_writeBuffer.isEmpty) {
      _bufferOffset = 0;

      // If this is the first write call after the user has done some input,
      // parse it immediately to minimize input latency,
      // otherwise schedule for the next event
      if (_didUserInput) {
        _didUserInput = false;
        _pendingData += _lengthOf(data);
        _writeBuffer.add(data);
        _callbacks.add(callback);
        _innerWrite();
        return;
      }

      _scheduleInnerWrite();
    }

    _pendingData += _lengthOf(data);
    _writeBuffer.add(data);
    _callbacks.add(callback);
  }

  /// Inner write call, that enters the sliced chunk processing by timing.
  ///
  /// `lastTime` indicates, when the last _innerWrite call had started.
  /// It is used to aggregate async handler execution under a timeout
  /// constraint effectively lowering the redrawing needs, schematically:
  ///
  ///     macroTask _innerWrite:
  ///       if (performance.now() - (lastTime | 0) < Constants.WRITE_TIMEOUT_MS):
  ///          schedule microTask _innerWrite(lastTime)
  ///       else:
  ///          schedule macroTask _innerWrite(0)
  ///
  ///     overall execution order on task queues:
  ///
  ///     macrotasks:  [...]  -->  _innerWrite(0)  -->  [...]  -->  screenUpdate  -->  [...]
  ///           m  t:                    |
  ///           i  a:                  [...]
  ///           c  s:                    |
  ///           r  k:              while < timeout:
  ///           o  s:                _innerWrite(timeout)
  ///
  /// `promiseResult` depicts the promise resolve value of an async handler.
  /// This value gets carried forward through all saved stack states of the
  /// paused parser for proper continuation.
  ///
  /// Note, for pure sync code `lastTime` and `promiseResult` have no meaning.
  void _scheduleInnerWrite([double lastTime = 0, bool promiseResult = true]) {
    if (store.isDisposed) {
      return;
    }
    _innerWriteTimer.cancelAndSet(
      () => _innerWrite(lastTime, promiseResult),
      0,
    );
  }

  void _innerWrite([double lastTime = 0, bool promiseResult = true]) {
    if (store.isDisposed) {
      return;
    }
    final startTime = lastTime != 0 ? lastTime : _now();
    while (_writeBuffer.length > _bufferOffset) {
      final data = _writeBuffer[_bufferOffset];
      final result = _action(data, promiseResult);
      if (result != null) {
        // If we get a promise as return value, we re-schedule the
        // continuation as thenable on the promise and exit right away.
        //
        // The exit here means, that we block input processing at the current
        // active chunk, the exact execution position within the chunk is
        // preserved by the saved stack content in InputHandler and
        // EscapeSequenceParser.
        //
        // Resuming happens automatically from that saved stack state.
        // Also the resolved promise value is passed along the callstack to
        // `EscapeSequenceParser.parse` to correctly resume the stopped handler
        // loop.
        //
        // Exceptions on async handlers will be logged to console async, but do
        // not interrupt the input processing (continues with next handler at
        // the current input position).

        // If a promise takes long to resolve, we should schedule continuation
        // behind setTimeout. This might already be too late, if our .then
        // enters really late (executor + prev thens took very long). This
        // cannot be solved here for the handler itself (it is the handlers
        // responsibility to slice hard work), but we can at least schedule a
        // screen update as we gain control.
        void continuation(bool r) {
          if (store.isDisposed) {
            return;
          }
          if (_now() - startTime >= _Constants.writeTimeoutMs) {
            _scheduleInnerWrite(0, r);
          } else {
            _innerWrite(startTime, r);
          }
        }

        // Optimization considerations:
        // The continuation above favors FPS over throughput by eval'ing
        // `startTime` on resolve. This might schedule too many screen updates
        // with bad throughput drops (in case a slow resolving handler sliced
        // its work properly behind setTimeout calls). We cannot spot this
        // condition here, also the renderer has no way to spot nonsense
        // updates either.
        // FIXME: A proper fix for this would track the FPS at the renderer
        // entry level separately.
        //
        // If favoring of FPS shows bad throughput impact, use the following
        // instead. It favors throughput by eval'ing `startTime` upfront
        // pulling at least one more chunk into the current microtask queue
        // (executed before setTimeout).
        //
        // const continuation: (r: boolean) => void = performance.now() - startTime >=
        //     Constants.WRITE_TIMEOUT_MS
        //   ? r => setTimeout(() => this._innerWrite(0, r))
        //   : r => this._innerWrite(startTime, r);

        // Handle exceptions synchronously to current band position, idea:
        // 1. spawn a single microtask which we allow to throw hard
        // 2. spawn a promise immediately resolving to `true`
        // (executed on the same queue, thus properly aligned before
        // continuation happens)
        unawaited(
          result
              .catchError((Object err, StackTrace stack) {
                scheduleMicrotask(() => Error.throwWithStackTrace(err, stack));
                return false;
              })
              .then(continuation),
        );
        return;
      }

      final cb = _callbacks[_bufferOffset];
      if (cb != null) cb();
      _bufferOffset++;
      _pendingData -= _lengthOf(data);

      if (_now() - startTime >= _Constants.writeTimeoutMs) {
        break;
      }
    }
    if (_writeBuffer.length > _bufferOffset) {
      // Allow renderer to catch up before processing the next batch
      // trim already processed chunks if we are above threshold
      if (_bufferOffset > _Constants.writeBufferLengthThreshold) {
        _writeBuffer = _writeBuffer.sublist(_bufferOffset);
        _callbacks = _callbacks.sublist(_bufferOffset);
        _bufferOffset = 0;
      }
      _scheduleInnerWrite();
    } else {
      _writeBuffer.clear();
      _callbacks.clear();
      _pendingData = 0;
      _bufferOffset = 0;
    }
    _onWriteParsed.fire(null);
  }
}
