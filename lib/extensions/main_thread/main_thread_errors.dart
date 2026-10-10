/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadErrors.ts.
//
// Deviations: `onUnexpectedError` (the developer tools' console and
// telemetry upstream) is the app's error log and the Output panel's
// "Extension Host" channel.

import 'package:bao_exthost/bao_exthost.dart';

import '../window/output/extension_output_service.dart';
import 'main_thread_context.dart';

final class MainThreadErrors extends MainThreadErrorsUnsupported {
  MainThreadErrors(this._output);

  final ExtensionOutputService _output;

  static RpcActor customer(MainThreadContext context) => MainThreadErrorsActor(
    MainThreadErrors(context.service<ExtensionOutputService>()),
  );

  @override
  void $onUnexpectedError(Object? err) => _output.onUnexpectedError(err);
}
