/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadConsole.ts.
//
// Deviations: what upstream writes to the developer tools' console goes to
// the Output panel's "Extension Host" channel; errors go to the app's error
// log as upstream's `logRemoteEntryIfError` writes them to its log. No
// extension development options (all of it is always shown).

import 'package:bao_exthost/bao_exthost.dart';

import '../window/output/extension_output_service.dart';
import 'main_thread_context.dart';

final class MainThreadConsole extends MainThreadConsoleUnsupported {
  MainThreadConsole(this._output);

  final ExtensionOutputService _output;

  static RpcActor customer(MainThreadContext context) => MainThreadConsoleActor(
    MainThreadConsole(context.service<ExtensionOutputService>()),
  );

  @override
  void $logExtensionHostMessage(Map<String, Object?> msg) =>
      _output.logExtensionHostMessage(msg);
}
