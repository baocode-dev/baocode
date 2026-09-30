/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The commands the shell ran, from its prompt, command start, executed and
// finished sequences: each with markers for its prompt, command line and
// output, and its cwd and exit code; the one being typed or run is the
// current command.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/
// commandDetectionCapability.ts, on the ported xterm core's internal
// terminal.
//
// Only the Unix heuristics are ported: `setIsWindowsPty` records the flag
// (for serialize) and keeps them (see PARITY.md), and the terminal's size,
// which only they use, is not tracked. `getLinesForCommand` (for quick
// fixes) is left out.

import 'dart:async';
import 'dart:math' as math;

import '../../xterm/common/buffer/types.dart';
import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import '../../xterm/common/public/parser_api.dart';
import '../../xterm/common/services/services.dart';
import '../../xterm/headless/terminal.dart';
import '../../xterm/typings/xterm.dart' show IFunctionIdentifier;
import 'capabilities.dart';
import 'command_detection/prompt_input_model.dart';
import 'command_detection/terminal_command.dart';

class CommandDetectionCapability extends Disposable
    implements ICommandDetectionCapability {
  CommandDetectionCapability(this._terminal, this._logService) {
    _currentCommand = PartialTerminalCommand(_terminal);
    _promptInputModel = register(
      PromptInputModel(
        _terminal,
        onCommandStarted,
        onCommandStartChanged,
        onCommandExecuted,
        onCommandFinished,
        _logService,
      ),
    );
    register(
      _promptInputModel.onDidInterrupt(
        (_) => _isCurrentCommandInterrupted = true,
      ),
    );

    // Pull command line from the buffer if it was not set explicitly
    register(
      onCommandExecuted((command) {
        if (command.commandLineConfidence != 'high') {
          // Upstream's `ITerminalCommand` branch is left out: the event only
          // fires with the current (partial) command.
          command.command = command.extractCommandLine();
          command.commandLineConfidence = 'low';

          if (
          // Markers exist
          command.promptStartMarker != null &&
              command.commandStartMarker != null &&
              command.commandExecutedMarker != null &&
              // Single line command
              !command.command!.contains('\n') &&
              // Start marker is not on the left-most column
              command.commandStartX != null &&
              command.commandStartX! > 0) {
            command.commandLineConfidence = 'medium';
          }
        }
      }),
    );

    register(
      ParserApi(_terminal).registerCsiHandler(
        IFunctionIdentifier(final_: 'J'),
        (params) {
          if (params.isNotEmpty && params[0] == 2) {
            if (!_terminal.optionsService.rawOptions.scrollOnEraseInDisplay) {
              _clearCommandsInViewport();
            }
            _currentCommand.wasCleared = true;
          }
          // We don't want to override xterm.js' default behavior, just augment
          // it
          return false;
        },
      ),
    );

    _ptyHeuristics = register(_UnixPtyHeuristics(_terminal, this));

    register(_terminal.onCursorMove((_) => _handleCursorMove()));
    register(toDisposable(() => _handleCursorMoveTimer?.cancel()));
  }

  final Terminal _terminal;
  final ILogService _logService;

  @override
  TerminalCapability<ICommandDetectionCapability> get type =>
      TerminalCapability.commandDetection;

  late final PromptInputModel _promptInputModel;
  @override
  IPromptInputModel get promptInputModel => _promptInputModel;

  final List<TerminalCommand> _commands = [];
  String? _cwd;
  String? _promptTerminator;
  late PartialTerminalCommand _currentCommand;
  final List<IMarker> _commandMarkers = [];
  bool _isCommandStorageDisabled = false;
  IHandleCommandOptions? _handleCommandStartOptions;
  bool _hasRichCommandDetection = false;
  @override
  bool get hasRichCommandDetection => _hasRichCommandDetection;
  ({String command, String? commandId})? _nextCommandId;
  bool _isCurrentCommandInterrupted = false;
  bool _isWindowsPty = false;
  Timer? _handleCursorMoveTimer;

  late final _UnixPtyHeuristics _ptyHeuristics;

  @override
  List<TerminalCommand> get commands => List.unmodifiable(_commands);
  @override
  String? get executingCommand => _currentCommand.command;
  @override
  ITerminalCommand? get executingCommandObject {
    if (_currentCommand.commandStartMarker != null) {
      // HACK: This does a lot more than the consumer of the API needs. It's
      // also a little misleading since it's not promoting the current command
      // yet.
      return _currentCommand.promoteToFullCommand(
        _cwd,
        null,
        _handleCommandStartOptions?.ignoreCommandLine ?? false,
        null,
      );
    }
    return null;
  }

  @override
  String? get executingCommandConfidence {
    final Object casted = _currentCommand;
    return casted is ITerminalCommand ? casted.commandLineConfidence : null;
  }

  @override
  PartialTerminalCommand get currentCommand => _currentCommand;
  @override
  String? get cwd => _cwd;
  String? get promptTerminator => _promptTerminator;

  late final _onCommandStarted = register(Emitter<ITerminalCommand>());
  @override
  late final IEvent<ITerminalCommand> onCommandStarted =
      _onCommandStarted.event;
  late final _onCommandStartChanged = register(Emitter<void>());
  late final IEvent<void> onCommandStartChanged = _onCommandStartChanged.event;
  late final _onBeforeCommandFinished = register(Emitter<ITerminalCommand>());
  late final IEvent<ITerminalCommand> onBeforeCommandFinished =
      _onBeforeCommandFinished.event;
  late final _onCommandFinished = register(Emitter<ITerminalCommand>());
  @override
  late final IEvent<ITerminalCommand> onCommandFinished =
      _onCommandFinished.event;
  late final _onCommandExecuted = register(Emitter<PartialTerminalCommand>());
  @override
  late final IEvent<PartialTerminalCommand> onCommandExecuted =
      _onCommandExecuted.event;
  late final _onCommandInvalidated = register(
    Emitter<List<ITerminalCommand>>(),
  );
  @override
  late final IEvent<List<ITerminalCommand>> onCommandInvalidated =
      _onCommandInvalidated.event;
  late final _onCurrentCommandInvalidated = register(
    Emitter<ICommandInvalidationRequest>(),
  );
  @override
  late final IEvent<ICommandInvalidationRequest> onCurrentCommandInvalidated =
      _onCurrentCommandInvalidated.event;
  late final _onSetRichCommandDetection = register(Emitter<bool>());
  @override
  late final IEvent<bool> onSetRichCommandDetection =
      _onSetRichCommandDetection.event;

  /// Upstream `@debounce(500)`.
  void _handleCursorMove() {
    _handleCursorMoveTimer?.cancel();
    _handleCursorMoveTimer = Timer(
      const Duration(milliseconds: 500),
      _handleCursorMoveDebounced,
    );
  }

  void _handleCursorMoveDebounced() {
    if (store.isDisposed) {
      return;
    }
    // Early versions of conpty do not have real support for an alt buffer,
    // in addition certain commands such as tsc watch will write to the top of
    // the normal buffer. The following checks when the cursor has moved while
    // the normal buffer is empty and if it is above the current command, all
    // decorations within the viewport will be invalidated.
    //
    // This function is debounced so that the cursor is only checked when it
    // is stable so conpty's screen reprinting will not trigger decoration
    // clearing.
    //
    // This is mostly a workaround for Windows but applies to all OS' because
    // of the tsc watch case.
    final commandStartMarker = _currentCommand.commandStartMarker;
    if (identical(_terminal.buffer, _terminal.buffers.normal) &&
        commandStartMarker != null) {
      if (_terminal.buffer.ybase + _terminal.buffer.y <
          commandStartMarker.line) {
        _clearCommandsInViewport();
        _currentCommand.isInvalid = true;
        _onCurrentCommandInvalidated.fire(
          const ICommandInvalidationRequest(
            reason: CommandInvalidationReason.windows,
          ),
        );
      }
    }
  }

  void _clearCommandsInViewport() {
    // Find the number of commands on the tail end of the array that are
    // within the viewport
    var count = 0;
    for (var i = _commands.length - 1; i >= 0; i--) {
      final line = _commands[i].marker?.line;
      if (line != null && line != 0 && line < _terminal.buffer.ybase) {
        break;
      }
      count++;
    }
    // Remove them
    if (count > 0) {
      final removed = _commands.sublist(_commands.length - count);
      _commands.removeRange(_commands.length - count, _commands.length);
      _onCommandInvalidated.fire(removed);
    }
  }

  @override
  void setContinuationPrompt(String value) {
    _promptInputModel.setContinuationPrompt(value);
  }

  // TODO: Simplify this, can everything work off the last line?
  @override
  void setPromptTerminator(String promptTerminator, String lastPromptLine) {
    _logService.debug('CommandDetectionCapability#setPromptTerminator', [
      promptTerminator,
    ]);
    _promptTerminator = promptTerminator;
    _promptInputModel.setLastPromptLine(lastPromptLine);
  }

  @override
  void setCwd(String value) {
    _cwd = value;
  }

  @override
  void setIsWindowsPty(bool value) {
    // The Windows heuristics are not ported: the flag is only recorded.
    _isWindowsPty = value;
  }

  @override
  void setHasRichCommandDetection(bool value) {
    _hasRichCommandDetection = value;
    _onSetRichCommandDetection.fire(value);
  }

  @override
  void setIsCommandStorageDisabled() {
    _isCommandStorageDisabled = true;
  }

  @override
  Object? getCommandForLine(int line) {
    // Handle the current partial command first, anything below it's prompt
    // is considered part of the current command
    final promptStartMarker = _currentCommand.promptStartMarker;
    if (promptStartMarker != null && line >= promptStartMarker.line) {
      return _currentCommand;
    }

    // No commands
    if (_commands.isEmpty) {
      return null;
    }

    // Line is before any registered commands
    if ((_commands[0].promptStartMarker ?? _commands[0].marker!).line > line) {
      return null;
    }

    // Iterate backwards through commands to find the right one
    for (var i = _commands.length - 1; i >= 0; i--) {
      if ((_commands[i].promptStartMarker ?? _commands[i].marker!).line <=
          line) {
        return _commands[i];
      }
    }

    return null;
  }

  @override
  String? getCwdForLine(int line) {
    // Handle the current partial command first, anything below it's prompt
    // is considered part of the current command
    final promptStartMarker = _currentCommand.promptStartMarker;
    if (promptStartMarker != null && line >= promptStartMarker.line) {
      return _cwd;
    }

    final command = getCommandForLine(line);
    if (command is ITerminalCommand) {
      return command.cwd;
    }

    return null;
  }

  @override
  void handlePromptStart([IHandleCommandOptions? options]) {
    _isCurrentCommandInterrupted = false;
    // Adjust the last command's finished marker when needed. The standard
    // position for the finished marker `D` to appear is at the same position
    // as the following prompt started `A`. Only do this when it would not
    // extend past the current cursor position.
    final lastCommand = _commands.isEmpty ? null : _commands.last;
    final lastEndMarker = lastCommand?.endMarker;
    final lastExecutedMarker = lastCommand?.executedMarker;
    if (lastEndMarker != null &&
        lastExecutedMarker != null &&
        lastEndMarker.line == lastExecutedMarker.line &&
        lastExecutedMarker.line < _terminal.buffer.ybase + _terminal.buffer.y) {
      _logService.debug(
        'CommandDetectionCapability#handlePromptStart adjusted commandFinished',
        ['${lastEndMarker.line} -> ${lastExecutedMarker.line + 1}'],
      );
      lastCommand!.endMarker = cloneMarker(_terminal, lastExecutedMarker, 1);
    }

    _currentCommand.promptStartMarker =
        options?.marker ??
        // Generally the prompt start should happen at the exact place the
        // endmarker happened. However, after ctrl+l is used to clear the
        // display, we want to ensure the actual prompt start marker position
        // is used. This is mostly a workaround for Windows but we apply it
        // generally.
        (!(_currentCommand.wasCleared ?? false) &&
                lastCommand?.endMarker != null
            ? cloneMarker(_terminal, lastCommand!.endMarker!)
            : _terminal.registerMarker(0));
    _currentCommand.wasCleared = false;
  }

  @override
  void handleContinuationStart() {
    _currentCommand.currentContinuationMarker = _terminal.registerMarker(0);
    _logService.debug('CommandDetectionCapability#handleContinuationStart', [
      _currentCommand.currentContinuationMarker,
    ]);
  }

  @override
  void handleContinuationEnd() {
    final currentContinuationMarker = _currentCommand.currentContinuationMarker;
    if (currentContinuationMarker == null) {
      _logService.warn(
        'CommandDetectionCapability#handleContinuationEnd Received '
        'continuation end without start',
      );
      return;
    }
    final continuations = _currentCommand.continuations ??= [];
    continuations.add((
      marker: currentContinuationMarker,
      end: _terminal.buffer.x,
    ));
    _currentCommand.currentContinuationMarker = null;
    _logService.debug('CommandDetectionCapability#handleContinuationEnd', [
      continuations.last,
    ]);
  }

  @override
  void handleRightPromptStart() {
    _currentCommand.commandRightPromptStartX = _terminal.buffer.x;
    _logService.debug('CommandDetectionCapability#handleRightPromptStart', [
      _currentCommand.commandRightPromptStartX,
    ]);
  }

  @override
  void handleRightPromptEnd() {
    _currentCommand.commandRightPromptEndX = _terminal.buffer.x;
    _logService.debug('CommandDetectionCapability#handleRightPromptEnd', [
      _currentCommand.commandRightPromptEndX,
    ]);
  }

  @override
  void handleCommandStart([IHandleCommandOptions? options]) {
    _handleCommandStartOptions = options;
    _currentCommand.cwd = _cwd;
    // Only update the column if the line has already been set
    _currentCommand.commandStartMarker =
        options?.marker ?? _currentCommand.commandStartMarker;
    // Upstream compares the marker's buffer line with the cursor's viewport
    // row; kept as it is.
    if (_currentCommand.commandStartMarker != null &&
        _currentCommand.commandStartMarker!.line == _terminal.buffer.y) {
      _currentCommand.commandStartX = _terminal.buffer.x;
      _onCommandStartChanged.fire(null);
      _logService.debug('CommandDetectionCapability#handleCommandStart', [
        _currentCommand.commandStartX,
        _currentCommand.commandStartMarker?.line,
      ]);
      return;
    }
    _ptyHeuristics.handleCommandStart(options);
  }

  /// Sets the command ID to use for the next command that starts. This is
  /// useful when you want to pre-assign an ID before the shell sends the
  /// command start sequence.
  @override
  void setNextCommandId(String command, String commandId) {
    _nextCommandId = (command: command, commandId: commandId);
  }

  @override
  void handleCommandExecuted([IHandleCommandOptions? options]) {
    _ensureCurrentCommandId();
    _ptyHeuristics.handleCommandExecuted(options);
    _currentCommand.markExecutedTime();
  }

  @override
  void handleCommandFinished(int? exitCode, [IHandleCommandOptions? options]) {
    // Command executed may not have happened yet, if not handle it now so the
    // expected events properly propagate. This may cause the output to show
    // up in the computed command line, but the command line confidence will
    // be low in the extension host for example and therefore cannot be
    // trusted anyway.
    if (_currentCommand.commandExecutedMarker == null) {
      handleCommandExecuted();
    }
    _currentCommand.markFinishedTime();

    _logService.debug('CommandDetectionCapability#handleCommandFinished', [
      _terminal.buffer.x,
      options?.marker?.line,
      _currentCommand.command,
      _currentCommand,
    ]);

    // HACK: Handle a special case on some versions of bash where identical
    // commands get merged in the output of `history`, this detects that case
    // and sets the exit code to the last command's exit code. This covered
    // the majority of cases but will fail if the same command runs with a
    // different exit code, that will need a more robust fix where we send the
    // command ID and exit code over to the capability to adjust there. A
    // canceled command's exit code should remain undefined.
    if (exitCode == null && !_isCurrentCommandInterrupted) {
      final lastCommand = _commands.isNotEmpty ? _commands.last : null;
      final command = _currentCommand.command;
      if (command != null &&
          command.isNotEmpty &&
          lastCommand?.command == command) {
        exitCode = lastCommand!.exitCode;
      }
    }

    if (_currentCommand.commandStartMarker == null) {
      return;
    }

    _currentCommand.commandFinishedMarker =
        options?.marker ?? _terminal.registerMarker(0);

    final newCommand = _currentCommand.promoteToFullCommand(
      _cwd,
      exitCode,
      _handleCommandStartOptions?.ignoreCommandLine ?? false,
      options?.markProperties,
    );

    if (newCommand != null) {
      _commands.add(newCommand);
      _onBeforeCommandFinished.fire(newCommand);
      // NOTE: onCommandFinished used to not fire if the command was invalid,
      // but this causes problems especially with the associated execution
      // event never firing in the extension API. See
      // https://github.com/microsoft/vscode/issues/252489
      _logService.debug('CommandDetectionCapability#onCommandFinished', [
        newCommand,
      ]);
      _onCommandFinished.fire(newCommand);
    }
    // Create new command for next execution
    _currentCommand = PartialTerminalCommand(_terminal);
    _handleCommandStartOptions = null;
  }

  void _ensureCurrentCommandId() {
    final commandId = _nextCommandId?.commandId;
    if (commandId != null && commandId.isNotEmpty) {
      // Assign the pre-set command ID to the current command. The timing of
      // setNextCommandId (called right before runCommand) and
      // _ensureCurrentCommandId (called on command executed) ensures we're
      // matching the right command without needing string comparison.
      if (_currentCommand.id != commandId) {
        _currentCommand.id = commandId;
      }
      _nextCommandId = null;
    }
  }

  @override
  void setCommandLine(String commandLine, bool isTrusted) {
    _logService.debug('CommandDetectionCapability#setCommandLine', [
      commandLine,
      isTrusted,
    ]);
    _currentCommand.command = commandLine;
    _currentCommand.commandLineConfidence = 'high';
    _currentCommand.isTrusted = isTrusted;

    if (isTrusted) {
      _promptInputModel.setConfidentCommandLine(commandLine);
    }
  }

  @override
  ISerializedCommandDetectionCapability serialize() {
    final commands = [
      for (final e in _commands) e.serialize(_isCommandStorageDisabled),
    ];
    final partialCommand = _currentCommand.serialize(_cwd);
    if (partialCommand != null) {
      commands.add(partialCommand);
    }
    return ISerializedCommandDetectionCapability(
      isWindowsPty: _isWindowsPty,
      hasRichCommandDetection: _hasRichCommandDetection,
      commands: commands,
      promptInputModel: _promptInputModel.serialize(),
    );
  }

  @override
  void deserialize(ISerializedCommandDetectionCapability serialized) {
    if (serialized.isWindowsPty) {
      setIsWindowsPty(serialized.isWindowsPty);
    }
    if (serialized.hasRichCommandDetection) {
      setHasRichCommandDetection(serialized.hasRichCommandDetection);
    }
    final buffer = _terminal.buffers.normal;
    for (final e in serialized.commands) {
      // Partial command
      if (e.endLine == null || e.endLine == 0) {
        // Check for invalid command
        final startLine = e.startLine;
        if (startLine == null) {
          continue;
        }
        final marker = _terminal.registerMarker(
          startLine - (buffer.ybase + buffer.y),
        );
        _currentCommand.commandStartMarker = _terminal.registerMarker(
          startLine - (buffer.ybase + buffer.y),
        );
        _currentCommand.commandStartX = e.startX;
        _currentCommand.promptStartMarker = e.promptStartLine != null
            ? _terminal.registerMarker(
                e.promptStartLine! - (buffer.ybase + buffer.y),
              )
            : null;
        _cwd = e.cwd;
        _onCommandStarted.fire(
          TerminalCommand.started(_terminal, marker: marker),
        );
        continue;
      }

      // Full command
      final newCommand = TerminalCommand.deserialize(
        _terminal,
        e,
        _isCommandStorageDisabled,
      );
      if (newCommand == null) {
        continue;
      }

      _commands.add(newCommand);
      _logService.debug('CommandDetectionCapability#onCommandFinished', [
        newCommand,
      ]);
      _onCommandFinished.fire(newCommand);
    }
    final promptInputModel = serialized.promptInputModel;
    if (promptInputModel != null) {
      _promptInputModel.deserialize(promptInputModel);
    }
  }
}

/// Non-Windows-specific behavior.
class _UnixPtyHeuristics extends Disposable {
  _UnixPtyHeuristics(this._terminal, this._capability);

  final Terminal _terminal;
  final CommandDetectionCapability _capability;

  void handleCommandStart(IHandleCommandOptions? options) {
    final currentCommand = _capability._currentCommand;
    currentCommand.commandStartX = _terminal.buffer.x;
    currentCommand.commandStartMarker =
        options?.marker ?? _terminal.registerMarker(0);

    // Clear executed as it must happen after command start
    currentCommand.commandExecutedMarker?.dispose();
    currentCommand.commandExecutedMarker = null;
    currentCommand.commandExecutedX = null;
    for (final m in _capability._commandMarkers) {
      m.dispose();
    }
    _capability._commandMarkers.clear();

    _capability._onCommandStarted.fire(
      TerminalCommand.started(
        _terminal,
        marker: options?.marker ?? currentCommand.commandStartMarker,
        markProperties: options?.markProperties,
      ),
    );
    _capability._logService.debug(
      'CommandDetectionCapability#handleCommandStart',
      [currentCommand.commandStartX, currentCommand.commandStartMarker?.line],
    );
  }

  void handleCommandExecuted(IHandleCommandOptions? options) {
    final currentCommand = _capability._currentCommand;
    currentCommand.commandExecutedMarker =
        options?.marker ?? _terminal.registerMarker(0);
    currentCommand.commandExecutedX = _terminal.buffer.x;
    _capability._logService.debug(
      'CommandDetectionCapability#handleCommandExecuted',
      [
        currentCommand.commandExecutedX,
        currentCommand.commandExecutedMarker?.line,
      ],
    );

    // Sanity check optional props
    if (currentCommand.commandStartMarker == null ||
        currentCommand.commandExecutedMarker == null ||
        currentCommand.commandStartX == null) {
      return;
    }

    final promptInputModel = _capability._promptInputModel;
    final value = promptInputModel.value;
    currentCommand.command = promptInputModel.ghostTextIndex > -1
        // JavaScript's `substring` clamps the end to the string.
        ? value.substring(
            0,
            math.min(promptInputModel.ghostTextIndex, value.length),
          )
        : value;
    _capability._onCommandExecuted.fire(currentCommand);
  }
}

/// A marker on [marker]'s line (plus [offset]).
IMarker cloneMarker(Terminal xterm, IMarker marker, [int offset = 0]) {
  return xterm.registerMarker(
    marker.line - (xterm.buffer.ybase + xterm.buffer.y) + offset,
  );
}
