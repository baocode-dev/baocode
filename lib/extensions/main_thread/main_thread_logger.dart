/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadLogService.ts.
//
// Deviations: the logger service is ExtensionOutputService (one per
// workspace); `$createLogger`'s loggers write upstream's FileLogger lines
// in Dart (OutputLogWriter); the `_extensionTests.*LogLevel` commands are
// not registered.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../window/output/extension_output_service.dart';
import 'main_thread_context.dart';

final class MainThreadLogger extends MainThreadLoggerUnsupported {
  /// Sends each log level change to the extension host through [rpc].
  MainThreadLogger(this._output, RpcProtocol rpc) {
    final proxy = ExtHostLogLevelServiceShapeProxy(rpc);
    _stop = _output.addLogLevelListener(
      (level, resource) => unawaited(
        proxy.$setLogLevel(level.index, resource).catchError((Object _) {}),
      ),
    );
  }

  final ExtensionOutputService _output;
  late final VoidCallback _stop;

  static RpcActor customer(MainThreadContext context) {
    final logger = MainThreadLogger(
      context.service<ExtensionOutputService>(),
      context.rpc,
    );
    context.onDispose(logger.dispose);
    return MainThreadLoggerActor(logger);
  }

  @override
  void $log(VsUri file, List<List<Object?>> messages) =>
      _output.log(file, messages);

  @override
  Future<void> $flush(VsUri file) => _output.flushLogger(file);

  @override
  Future<void> $createLogger(
    VsUri file,
    Map<String, Object?>? options,
  ) async => _output.createLogger(file, options);

  @override
  Future<void> $registerLogger(Map<String, Object?> logger) async =>
      _output.registerLogger(ExtensionLoggerResource.fromJson(logger));

  @override
  Future<void> $deregisterLogger(VsUri resource) async =>
      _output.deregisterLogger(resource);

  @override
  Future<void> $setVisibility(VsUri resource, bool visible) async =>
      _output.setLoggerVisibility(resource, visible);

  void dispose() => _stop();
}
