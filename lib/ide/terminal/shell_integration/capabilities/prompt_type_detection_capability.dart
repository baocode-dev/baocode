/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The kind of prompt the shell reports (p10k, posh-git, ...).
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/
// promptTypeDetectionCapability.ts.

import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import 'capabilities.dart';

class PromptTypeDetectionCapability extends Disposable
    implements IPromptTypeDetectionCapability {
  @override
  TerminalCapability<IPromptTypeDetectionCapability> get type =>
      TerminalCapability.promptTypeDetection;

  String? _promptType;
  @override
  String? get promptType => _promptType;

  late final _onPromptTypeChanged = register(Emitter<String?>());
  @override
  late final IEvent<String?> onPromptTypeChanged = _onPromptTypeChanged.event;

  @override
  void setPromptType(String value) {
    _promptType = value;
    _onPromptTypeChanged.fire(value);
  }
}
