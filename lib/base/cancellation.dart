// Cancellation of long requests (VS Code's `CancellationToken`).

import 'dart:async';

/// Whether a request was cancelled (`CancellationToken`).
abstract interface class CancellationToken {
  bool get isCancellationRequested;

  /// Completes when cancelled; never when not.
  Future<void> get whenCancelled;

  static const CancellationToken none = _NoneToken();
}

final class _NoneToken implements CancellationToken {
  const _NoneToken();

  @override
  bool get isCancellationRequested => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;
}

/// `CancellationTokenSource`.
final class CancellationTokenSource implements CancellationToken {
  final _completer = Completer<void>();

  CancellationToken get token => this;

  @override
  bool get isCancellationRequested => _completer.isCompleted;

  @override
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// A cancelled request (`CancellationError`, name `Canceled`).
final class CancellationException implements Exception {
  const CancellationException();

  @override
  String toString() => 'Canceled';
}
