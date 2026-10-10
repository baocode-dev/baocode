/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadLabelService.ts.

import 'package:bao_exthost/bao_exthost.dart';

import '../window/label_service.dart';
import 'main_thread_context.dart';

final class MainThreadLabelService extends MainThreadLabelServiceUnsupported {
  MainThreadLabelService(this._labels);

  final ExtensionLabelService _labels;
  final Map<num, void Function()> _formatters = {};

  static RpcActor customer(MainThreadContext context) {
    final actor = MainThreadLabelService(
      context.service<ExtensionLabelService>(),
    );
    context.onDispose(actor.dispose);
    return MainThreadLabelServiceActor(actor);
  }

  @override
  void $registerResourceLabelFormatter(
    num handle,
    Map<String, Object?> formatter,
  ) {
    // Registered ones come before those of package.json files.
    _formatters.remove(handle)?.call();
    _formatters[handle] = _labels.registerFormatter({
      ...formatter,
      'priority': true,
    });
  }

  @override
  void $unregisterResourceLabelFormatter(num handle) =>
      _formatters.remove(handle)?.call();

  void dispose() {
    for (final remove in _formatters.values) {
      remove();
    }
    _formatters.clear();
  }
}
