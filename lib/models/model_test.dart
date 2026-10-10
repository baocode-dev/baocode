import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'model_provider.dart';

/// The cursor-byok connectivity prompt; no history, tools or system prompt.
const modelTestPrompt =
    'Output the numbers 1 through 120 separated by a single space. '
    'No commas, no newlines, no explanation.';

enum ModelTestStatus { queued, running, passed, failed, cancelled }

/// Cancellation belongs to the run, not to the widget displaying it.
class ModelTestCancellation {
  final _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!cancelled) _done.complete();
  }
}

class ModelTestEvent {
  const ModelTestEvent({
    this.text = '',
    this.thinking = '',
    this.inputTokens,
    this.outputTokens,
    this.done = false,
  });

  final String text;
  final String thinking;
  final int? inputTokens;
  final int? outputTokens;
  final bool done;
}

typedef ModelTestRunner = Future<void> Function(
  ModelProvider provider,
  ProviderModel model,
  String prompt,
  ModelTestCancellation cancellation,
  void Function(ModelTestEvent event) emit,
);

/// Latest result only, deliberately absent from settings.json and the keychain.
class ModelTestResult {
  ModelTestResult(this.provider, this.model, this.prompt);

  final ModelProvider provider;
  final ProviderModel model;
  final String prompt;
  ModelTestStatus status = ModelTestStatus.queued;
  String output = '';
  String thinking = '';
  String? error;
  Duration elapsed = Duration.zero;
  Duration? firstEvent;
  Duration? firstText;
  int? inputTokens;
  int? reportedOutputTokens;
  int _outputBytes = 0;
  bool outputTruncated = false;
  bool thinkingTruncated = false;

  bool get active =>
      status == ModelTestStatus.queued || status == ModelTestStatus.running;
  bool get tokensEstimated => reportedOutputTokens == null;
  int get outputTokens => reportedOutputTokens ?? (_outputBytes / 4).ceil();

  /// End-to-end throughput includes waiting for the first token, as cursor-byok
  /// does. Estimates are marked in the UI, not presented as tokenizer counts.
  double? get tokensPerSecond => elapsed.inMicroseconds <= 0 || output.isEmpty
      ? null
      : outputTokens /
            (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
}

class _TestJob {
  _TestJob(this.result);
  final ModelTestResult result;
  final cancellation = ModelTestCancellation();
}

/// Process-session owner: dialogs may come and go without losing runs/results.
/// A global worker limit prevents multiple windows from flooding the upstream.
class ModelTestService extends ChangeNotifier {
  ModelTestService({
    required this._run,
    this.concurrency = 3,
    this.timeout = const Duration(seconds: 45),
  });

  final ModelTestRunner _run;
  final int concurrency;
  final Duration timeout;
  final _results = <String, ModelTestResult>{};
  final _jobs = <String, _TestJob>{};
  final _queue = Queue<_TestJob>();
  int _running = 0;
  bool _disposed = false;
  Timer? _notification;

  ModelTestResult? result(String provider, String model) =>
      _results[modelRef(provider, model)];

  void start(
    ModelProvider provider,
    Iterable<ProviderModel> models, {
    String prompt = modelTestPrompt,
  }) {
    if (_disposed || prompt.trim().isEmpty) return;
    for (final model in models) {
      final id = modelRef(provider.id, model.id);
      if (_jobs.containsKey(id)) continue;
      final result = ModelTestResult(provider, model, prompt.trim());
      final job = _TestJob(result);
      _results[id] = result;
      _jobs[id] = job;
      _queue.add(job);
    }
    notifyListeners();
    _drain();
  }

  void cancel(String provider, [String? model]) {
    for (final job in _jobs.values.toList()) {
      if (job.result.provider.id != provider ||
          model != null && job.result.model.id != model) {
        continue;
      }
      job.cancellation.cancel();
      if (_queue.remove(job)) {
        job.result.status = ModelTestStatus.cancelled;
        _jobs.remove(modelRef(provider, job.result.model.id));
      }
    }
    if (!_disposed) notifyListeners();
  }

  void _drain() {
    while (!_disposed && _running < concurrency && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _running++;
      unawaited(_execute(job));
    }
  }

  // Stream bursts update at most ten times a second, with an immediate final
  // notification. Bound stored output as custom prompts can generate anything.
  void _changed() {
    if (_disposed || _notification != null) return;
    _notification = Timer(const Duration(milliseconds: 100), () {
      _notification = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _execute(_TestJob job) async {
    final result = job.result;
    final watch = Stopwatch()..start();
    var completed = false;
    result.status = ModelTestStatus.running;
    _changed();
    void emit(ModelTestEvent event) {
      if (job.cancellation.cancelled || !result.active) return;
      result.elapsed = watch.elapsed;
      if (event.text.isNotEmpty || event.thinking.isNotEmpty) {
        result.firstEvent ??= watch.elapsed;
      }
      if (event.text.isNotEmpty) result.firstText ??= watch.elapsed;
      const limit = 65536;
      // Count the entire stream even when the retained preview reaches its cap.
      result._outputBytes += utf8.encode(event.text).length;
      final output = result.output + event.text;
      final thinking = result.thinking + event.thinking;
      result.outputTruncated |= output.length > limit;
      result.thinkingTruncated |= thinking.length > limit;
      result.output = output.length > limit
          ? output.substring(0, limit)
          : output;
      result.thinking = thinking.length > limit
          ? thinking.substring(0, limit)
          : thinking;
      if (event.inputTokens != null) result.inputTokens = event.inputTokens;
      if (event.outputTokens != null) {
        result.reportedOutputTokens = event.outputTokens;
      }
      completed |= event.done;
      _changed();
    }

    try {
      await Future.any<void>([
        _run(
          result.provider,
          result.model,
          result.prompt,
          job.cancellation,
          emit,
        ).timeout(timeout),
        job.cancellation.whenCancelled,
      ]);
      if (job.cancellation.cancelled) {
        result.status = ModelTestStatus.cancelled;
      } else if (!completed || result.output.trim().isEmpty) {
        result.status = ModelTestStatus.failed;
        result.error = !completed ? 'incomplete_stream' : 'empty_output';
      } else {
        result.status = ModelTestStatus.passed;
      }
    } on TimeoutException {
      result.status = ModelTestStatus.failed;
      result.error = 'timeout';
    } on Object catch (error) {
      result.status = job.cancellation.cancelled
          ? ModelTestStatus.cancelled
          : ModelTestStatus.failed;
      // Never retain a credential echoed by an upstream error.
      result.error = job.cancellation.cancelled ? null : '$error';
    } finally {
      watch.stop();
      job.cancellation.cancel();
      result.elapsed = watch.elapsed;
      _jobs.remove(modelRef(result.provider.id, result.model.id));
      _running--;
      if (!_disposed) {
        notifyListeners();
        _drain();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _notification?.cancel();
    for (final job in _jobs.values) {
      job.cancellation.cancel();
    }
    _queue.clear();
    _jobs.clear();
    _results.clear();
    super.dispose();
  }
}
