import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

/// What every main thread actor of one extension host shares: the host's
/// [rpc], the workspace's services, and a place to put what must be undone
/// when the host ends (`extHostCustomer`'s disposables).
///
/// Actors are made once per extension host session, before it runs
/// anything ([mainThreadCustomers]), and disposed with it.
final class MainThreadContext {
  MainThreadContext({required this.rpc, required this.services});

  final RpcProtocol rpc;

  /// The app's services, by type ([service]).
  final Map<Type, Object> services;

  /// The service of type [T]; throws when the workbench gave none.
  T service<T extends Object>() {
    final s = services[T];
    if (s == null) throw StateError('No $T for the extension host');
    return s as T;
  }

  /// The service of type [T], or null.
  T? maybeService<T extends Object>() => services[T] as T?;

  final _disposables = <FutureOr<void> Function()>[];
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Runs [dispose] when the session ends.
  void onDispose(FutureOr<void> Function() dispose) {
    if (_disposed) {
      unawaited(Future.sync(dispose));
    } else {
      _disposables.add(dispose);
    }
  }

  /// Keeps [subscription] until the session ends.
  void listen<T>(StreamSubscription<T> subscription) =>
      onDispose(subscription.cancel);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final d in _disposables.reversed.toList()) {
      try {
        await d();
      } on Object {
        // One failing does not keep the rest.
      }
    }
    _disposables.clear();
  }
}

/// Makes the actor of one `MainContext` identifier for a session.
typedef MainThreadCustomer = RpcActor Function(MainThreadContext context);
