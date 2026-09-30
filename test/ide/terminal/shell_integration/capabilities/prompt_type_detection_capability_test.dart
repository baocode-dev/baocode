/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/xterm/
// promptTypeDetectionCapability.test.ts.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:monad/ide/terminal/shell_integration/capabilities/prompt_type_detection_capability.dart';

void main() {
  PromptTypeDetectionCapability create() {
    final capability = PromptTypeDetectionCapability();
    addTearDown(capability.dispose);
    return capability;
  }

  test('should have correct capability type', () {
    final capability = create();
    expect(capability.type, TerminalCapability.promptTypeDetection);
  });

  test('should initialize with undefined prompt type', () {
    final capability = create();
    expect(capability.promptType, isNull);
  });

  test('should set and get prompt type', () {
    final capability = create();

    capability.setPromptType('p10k');
    expect(capability.promptType, 'p10k');

    capability.setPromptType('posh-git');
    expect(capability.promptType, 'posh-git');
  });

  test('should fire event when prompt type changes', () {
    final capability = create();
    var eventFiredCount = 0;
    String? lastEventValue;

    capability.onPromptTypeChanged((value) {
      eventFiredCount++;
      lastEventValue = value;
    });

    capability.setPromptType('starship');
    expect(eventFiredCount, 1);
    expect(lastEventValue, 'starship');

    capability.setPromptType('oh-my-zsh');
    expect(eventFiredCount, 2);
    expect(lastEventValue, 'oh-my-zsh');
  });
}
