/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Commands guessed without shell integration: where the cursor was when
// enter was pressed.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/
// partialCommandDetectionCapability.ts.

import '../../xterm/common/buffer/types.dart';
import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import '../../xterm/common/public/parser_api.dart';
import '../../xterm/headless/terminal.dart';
import '../../xterm/typings/xterm.dart' show IFunctionIdentifier;
import 'capabilities.dart';

/// The minimum size of the prompt in which to assume the line is a command.
const _minimumPromptLength = 2;

/// This capability guesses where commands are based on where the cursor was
/// when enter was pressed. It's very hit or miss but it's often correct and
/// better than nothing.
class PartialCommandDetectionCapability extends DisposableStore
    implements IPartialCommandDetectionCapability {
  PartialCommandDetectionCapability(
    this._terminal, [
    IEvent<void>? onDidExecuteText,
  ]) {
    add(_terminal.onData(_onData));
    add(
      ParserApi(_terminal).registerCsiHandler(
        IFunctionIdentifier(final_: 'J'),
        (params) {
          if (params.isNotEmpty && (params[0] == 2 || params[0] == 3)) {
            _clearCommandsInViewport();
          }
          // We don't want to override xterm.js' default behavior, just augment
          // it
          return false;
        },
      ),
    );
    if (onDidExecuteText != null) {
      add(onDidExecuteText((_) => _onEnter()));
    }
  }

  final Terminal _terminal;

  @override
  TerminalCapability<IPartialCommandDetectionCapability> get type =>
      TerminalCapability.partialCommandDetection;

  final List<IMarker> _commands = [];

  @override
  List<IMarker> get commands => List.unmodifiable(_commands);

  late final _onCommandFinished = add(Emitter<IMarker>());
  @override
  late final IEvent<IMarker> onCommandFinished = _onCommandFinished.event;

  void _onData(String data) {
    if (data == '\x0d') {
      _onEnter();
    }
  }

  void _onEnter() {
    if (_terminal.buffer.x >= _minimumPromptLength) {
      final marker = _terminal.registerMarker(0);
      _commands.add(marker);
      _onCommandFinished.fire(marker);
    }
  }

  void _clearCommandsInViewport() {
    // Find the number of commands on the tail end of the array that are
    // within the viewport
    var count = 0;
    for (var i = _commands.length - 1; i >= 0; i--) {
      if (_commands[i].line < _terminal.buffer.ybase) {
        break;
      }
      count++;
    }
    // Remove them
    _commands.removeRange(_commands.length - count, _commands.length);
  }
}
