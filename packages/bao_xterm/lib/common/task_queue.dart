// Copyright (c) 2022 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/TaskQueue.ts (c58ea36).

import 'dart:async';

import 'lifecycle.dart';
import 'services/services.dart';

/// A queued task; it returns `true` to be called again (upstream's
/// `() => boolean | void`).
typedef QueuedTask = Object? Function();

abstract interface class _ITaskQueue {
  /// Adds a task to the queue which will run in a future idle callback.
  ///
  /// To avoid perceivable stalls on the main thread, tasks with heavy workload
  /// should split their work into smaller pieces and return `true` to get
  /// called again until the work is done.
  void enqueue(QueuedTask task);

  /// Flushes the queue, running all remaining tasks synchronously.
  void flush();

  /// Clears any remaining tasks from the queue, these will not be run.
  void clear();
}

abstract interface class _ITaskDeadline {
  double timeRemaining();
}

typedef _CallbackWithDeadline = void Function(_ITaskDeadline deadline);

/// Upstream's `performance.now()`.
final Stopwatch _clock = Stopwatch()..start();

double _now() => _clock.elapsedMicroseconds / 1000.0;

abstract class _TaskQueue implements _ITaskQueue {
  _TaskQueue(this._logService);

  final List<QueuedTask> _tasks = <QueuedTask>[];
  Timer? _idleCallback;
  int _i = 0;
  final ILogService _logService;

  Timer _requestCallback(_CallbackWithDeadline callback);
  void _cancelCallback(Timer identifier);

  @override
  void enqueue(QueuedTask task) {
    _tasks.add(task);
    _start();
  }

  @override
  void flush() {
    while (_i < _tasks.length) {
      if (_tasks[_i]() != true) {
        _i++;
      }
    }
    clear();
  }

  @override
  void clear() {
    if (_idleCallback != null) {
      _cancelCallback(_idleCallback!);
      _idleCallback = null;
    }
    _i = 0;
    _tasks.clear();
  }

  void _start() {
    _idleCallback ??= _requestCallback(_process);
  }

  void _process(_ITaskDeadline deadline) {
    _idleCallback = null;
    double taskDuration;
    var longestTask = 0.0;
    var lastDeadlineRemaining = deadline.timeRemaining();
    double deadlineRemaining;
    while (_i < _tasks.length) {
      taskDuration = _now();
      if (_tasks[_i]() != true) {
        _i++;
      }
      // Unlike performance.now, a clock change during a short running task is
      // unlikely; should it lead to a negative duration, assume 1 msec.
      taskDuration = _max(1, _now() - taskDuration);
      longestTask = _max(taskDuration, longestTask);
      // Guess the following task will take a similar time to the longest task
      // in this batch, allow additional room to try avoid exceeding the
      // deadline
      deadlineRemaining = deadline.timeRemaining();
      if (longestTask * 1.5 > deadlineRemaining) {
        // Warn when the time exceeding the deadline is over 20ms, if this
        // happens in practice the task should be split into sub-tasks to
        // ensure the UI remains responsive.
        if (lastDeadlineRemaining - taskDuration < -20) {
          _logService.warn(
            'task queue exceeded allotted deadline by '
            '${(lastDeadlineRemaining - taskDuration).round().abs()}ms',
          );
        }
        _start();
        return;
      }
      lastDeadlineRemaining = deadlineRemaining;
    }
    clear();
  }

  static double _max(double a, double b) => a > b ? a : b;
}

class _Deadline implements _ITaskDeadline {
  _Deadline(this._end);

  final double _end;

  @override
  double timeRemaining() => _TaskQueue._max(0, _end - _now());
}

/// A queue that runs tasks over several timer callbacks, trying to maintain
/// above 60 frames per second.
///
/// The tasks run in the order they are enqueued, but some time later; take
/// care that they are non-urgent and do not introduce race conditions.
class PriorityTaskQueue extends _TaskQueue {
  PriorityTaskQueue(super.logService);

  @override
  Timer _requestCallback(_CallbackWithDeadline callback) {
    return Timer(Duration.zero, () => callback(_createDeadline(16)));
  }

  @override
  void _cancelCallback(Timer identifier) {
    identifier.cancel();
  }

  _ITaskDeadline _createDeadline(int duration) {
    return _Deadline(_now() + duration);
  }
}

/// A queue that runs tasks over several idle callbacks.
///
/// Upstream falls back to [PriorityTaskQueue] where `requestIdleCallback` is
/// missing, which is always the case in Dart.
typedef IdleTaskQueue = PriorityTaskQueue;

/// Tracks a single debounced task that will run on the next idle frame. When
/// called multiple times, only the last set task will run.
class DebouncedIdleTask implements IDisposable {
  DebouncedIdleTask(ILogService logService)
    : _queue = IdleTaskQueue(logService);

  final _ITaskQueue _queue;

  void set(QueuedTask task) {
    _queue.clear();
    _queue.enqueue(task);
  }

  void flush() {
    _queue.flush();
  }

  @override
  void dispose() {
    _queue.clear();
  }
}
