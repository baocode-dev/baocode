/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadMeteredConnection.ts.
//
// Deviations: BaoCode cannot tell a metered connection (upstream's desktop
// asks the browser's Network Information API, often unavailable too): the
// connection is reported as not metered, and never changes.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_context.dart';

final class MainThreadMeteredConnection
    extends MainThreadMeteredConnectionUnsupported {
  MainThreadMeteredConnection(ExtHostMeteredConnectionProxy proxy) {
    unawaited(
      proxy.$initializeIsConnectionMetered(false).catchError((Object _) {}),
    );
  }

  static RpcActor customer(MainThreadContext context) =>
      MainThreadMeteredConnectionActor(
        MainThreadMeteredConnection(
          ExtHostMeteredConnectionProxy(context.rpc),
        ),
      );
}
