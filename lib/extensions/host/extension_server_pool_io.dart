import 'dart:async';

import 'package:flutter/foundation.dart';

import 'extension_server_io.dart';

/// A VS Code server: the app's one on this machine (or a remote host's),
/// started when an extension host first needs it (after the runtime is
/// ready), started again when it ends, ended as the app quits.
final class ExtensionServerPool {
  ExtensionServerPool(
    Future<ExtensionServerLaunch> Function() launch, {
    this.start = ExtensionServer.start,
  }) : _make = (() async => start(await launch()));

  /// A server [connect] starts (a remote host's, through its connection).
  ExtensionServerPool.connecting(Future<ExtensionServer> Function() connect)
    : start = _noLaunch,
      _make = connect;

  static Future<ExtensionServer> _noLaunch(ExtensionServerLaunch _) =>
      throw UnsupportedError('Started by its connection');

  /// Starts it: waits for the runtime (downloading it the first time).
  final Future<ExtensionServer> Function() _make;

  @visibleForTesting
  final Future<ExtensionServer> Function(ExtensionServerLaunch launch) start;

  Future<ExtensionServer>? _server;

  /// The running server, started if none runs.
  Future<ExtensionServer> get server {
    final current = _server;
    if (current != null) return current;
    late final Future<ExtensionServer> starting;
    _server = starting = () async {
      final server = await _make();
      unawaited(
        server.exited.then((_) {
          if (identical(_server, starting)) _server = null;
        }),
      );
      return server;
    }();
    // A failed start is tried again by the next caller.
    starting.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_server, starting)) _server = null;
      },
    );
    return starting;
  }

  Future<void> dispose() async {
    final current = _server;
    _server = null;
    if (current == null) return;
    try {
      await (await current).dispose();
    } on Object {
      // Never started.
    }
  }
}
