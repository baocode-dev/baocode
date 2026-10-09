/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTelemetry.ts.
//
// BaoCode's product sends no VS Code telemetry (`supportsTelemetry` is
// false, as in VSCodium): the host is told the level is NONE as it starts,
// so `vscode.env.isTelemetryEnabled` is false and extensions' telemetry
// loggers drop their events; the level never changes, so no configuration
// listener is needed. `$publicLog` and `$publicLog2` are intentionally
// inert: upstream hands them to a telemetry service that, at level NONE,
// sends nothing.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_context.dart';

/// `TelemetryLevel`.
abstract final class ExtensionTelemetryLevel {
  static const none = 0;
  static const crash = 1;
  static const error = 2;
  static const usage = 3;
}

final class MainThreadTelemetry extends MainThreadTelemetryUnsupported {
  MainThreadTelemetry(ExtHostTelemetryProxy proxy) {
    unawaited(
      proxy
          .$initializeTelemetryLevel(ExtensionTelemetryLevel.none, false)
          .catchError((Object _) {}),
    );
  }

  static RpcActor customer(MainThreadContext context) =>
      MainThreadTelemetryActor(
        MainThreadTelemetry(ExtHostTelemetryProxy(context.rpc)),
      );

  /// Inert: telemetry is off (see above).
  @override
  void $publicLog(String eventName, Object? data) {}

  /// Inert: telemetry is off (see above).
  @override
  void $publicLog2(String eventName, Object? data) {}
}
