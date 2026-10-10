/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Debug adapters reached directly rather than through the extension host:
// an executable speaking DAP on its stdio, or a DAP server on a socket.
// For tests against real adapters (lldb-dap, js-debug's DAP server) and
// for tools; extensions' adapters come through the extension host, which
// starts them itself.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/node/debugAdapter.ts
// (`ExecutableDebugAdapter`, `SocketDebugAdapter`).
//
// Deviations: no `runtime`/`program` resolution from contributions; the
// command line is given as it is to run.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../common/debug_types.dart';
import 'dap_framing.dart';
import 'debug_adapter.dart';

/// A debug adapter as a process with DAP on its stdin/stdout.
final class StdioDebugAdapterTransport extends EmitterDebugAdapterTransport {
  StdioDebugAdapterTransport(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.environment,
    this.onStderr,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;

  /// The adapter's stderr, as it comes (for a log).
  final void Function(String text)? onStderr;

  Process? _process;
  StreamSubscription<List<int>>? _stdout;
  StreamSubscription<String>? _stderr;

  /// The process id, once started.
  int? get pid => _process?.pid;

  @override
  Future<void> start() async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } on ProcessException catch (e) {
      fireError(e);
      rethrow;
    }
    _process = process;
    final reader = DapMessageReader(
      onMessage: acceptMessage,
      onError: fireError,
    );
    _stdout = process.stdout.listen(reader.add);
    _stderr = process.stderr
        .transform(utf8.decoder)
        .listen((text) => onStderr?.call(text));
    unawaited(
      process.exitCode.then((code) {
        if (identical(_process, process)) {
          _process = null;
          fireExit(code);
        }
      }),
    );
  }

  @override
  void send(Json message) {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.add(encodeDapMessage(message));
    } on Object catch (e) {
      fireError(e);
    }
  }

  @override
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    try {
      await process.stdin.close();
    } on Object {
      // Gone already.
    }
    // Give it a moment to exit on its own (after `disconnect`).
    final exited = await process.exitCode
        .timeout(const Duration(seconds: 2), onTimeout: () => -1);
    if (exited == -1) process.kill();
  }

  @override
  void dispose() {
    unawaited(_stdout?.cancel());
    unawaited(_stderr?.cancel());
    _process?.kill();
    _process = null;
    super.dispose();
  }
}

/// A debug adapter listening on a socket (`DebugAdapterServer`).
final class SocketDebugAdapterTransport extends EmitterDebugAdapterTransport {
  SocketDebugAdapterTransport(this.host, this.port);

  final String host;
  final int port;
  Socket? _socket;

  @override
  Future<void> start() async {
    final socket = await Socket.connect(host, port);
    _socket = socket;
    final reader = DapMessageReader(
      onMessage: acceptMessage,
      onError: fireError,
    );
    socket.listen(
      reader.add,
      onError: fireError,
      onDone: () {
        if (identical(_socket, socket)) {
          _socket = null;
          fireExit(0);
        }
      },
    );
  }

  @override
  void send(Json message) {
    try {
      _socket?.add(encodeDapMessage(message));
    } on Object catch (e) {
      fireError(e);
    }
  }

  @override
  Future<void> stop() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
    socket?.destroy();
  }

  @override
  void dispose() {
    _socket?.destroy();
    _socket = null;
    super.dispose();
  }
}
