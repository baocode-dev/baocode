/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What is typed at the prompt: the input between the command start and the
// end of the prompt, with the cursor's place in it and any ghost text (a
// suggestion the shell shows dim or italic after the cursor), read from the
// buffer as it changes.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/commandDetection/
// promptInputModel.ts, on the ported xterm core's internal terminal.
//
// Upstream's `@throttle(0)` on `_sync` always runs the sync right away (the
// next run is due the moment the last one ran), so the sync here is a plain
// call. The log service is the terminal's own.

import 'dart:math' as math;

import '../../../xterm/common/buffer/cell_data.dart';
import '../../../xterm/common/buffer/types.dart';
import '../../../xterm/common/event.dart';
import '../../../xterm/common/lifecycle.dart';
import '../../../xterm/common/services/services.dart';
import '../../../xterm/headless/terminal.dart';
import '../capabilities.dart';
import 'terminal_command.dart';

enum PromptInputState { unknown, input, execute }

/// The fish shell's `TerminalShellType` (upstream `PosixShellType.Fish`).
const fishShellType = 'fish';

/// A model of the prompt input state using shell integration and analyzing
/// the terminal buffer. This may not be 100% accurate but provides a best
/// guess.
abstract interface class IPromptInputModel implements IPromptInputModelState {
  PromptInputState get state;

  IEvent<IPromptInputModelState> get onDidStartInput;
  IEvent<IPromptInputModelState> get onDidChangeInput;
  IEvent<IPromptInputModelState> get onDidFinishInput;

  /// Fires immediately before [onDidFinishInput] when a SIGINT/Ctrl+C/^C is
  /// detected.
  IEvent<IPromptInputModelState> get onDidInterrupt;

  /// Gets the prompt input as a user-friendly string where `|` is the cursor
  /// position and `[` and `]` wrap any ghost text.
  ///
  /// [emptyStringWhenEmpty]: if true, an empty string is returned when the
  /// prompt input is empty (as opposed to '|').
  String getCombinedString([bool emptyStringWhenEmpty = false]);

  /// [shellType] is a `TerminalShellType` value, such as [fishShellType].
  void setShellType([String? shellType]);
}

abstract interface class IPromptInputModelState {
  /// The full prompt input include ghost text.
  String get value;

  /// The prompt input up to the cursor index, this will always exclude the
  /// ghost text.
  String get prefix;

  /// The prompt input from the cursor to the end, this _does not_ include
  /// ghost text.
  String get suffix;

  /// The index of the cursor in [value].
  int get cursorIndex;

  /// The index of the start of ghost text in [value]. This is -1 when there
  /// is no ghost text.
  int get ghostTextIndex;
}

/// A snapshot of an [IPromptInputModel] (upstream a frozen object literal).
class PromptInputModelState implements IPromptInputModelState {
  const PromptInputModelState({
    required this.value,
    required this.prefix,
    required this.suffix,
    required this.cursorIndex,
    required this.ghostTextIndex,
  });

  @override
  final String value;
  @override
  final String prefix;
  @override
  final String suffix;
  @override
  final int cursorIndex;
  @override
  final int ghostTextIndex;
}

class ISerializedPromptInputModel {
  const ISerializedPromptInputModel({
    required this.modelState,
    required this.commandStartX,
    required this.lastPromptLine,
    required this.continuationPrompt,
    required this.lastUserInput,
  });

  final IPromptInputModelState modelState;
  final int commandStartX;
  final String? lastPromptLine;
  final String? continuationPrompt;
  final String lastUserInput;
}

class PromptInputModel extends Disposable implements IPromptInputModel {
  PromptInputModel(
    this._xterm,
    IEvent<ITerminalCommand> onCommandStart,
    IEvent<void> onCommandStartChanged,
    IEvent<PartialTerminalCommand> onCommandExecuted,
    IEvent<ITerminalCommand> onCommandFinished,
    this._logService,
  ) {
    register(
      EventUtils.any<void>([
        _xterm.onCursorMove,
        (listener) => _xterm.onData((_) => listener(null)),
        _xterm.onWriteParsed,
      ])((_) => _sync()),
    );
    register(_xterm.onData(_handleUserInput));

    register(onCommandStart(_handleCommandStart));
    register(onCommandStartChanged((_) => _handleCommandStartChanged()));
    register(onCommandExecuted((_) => _handleCommandExecuted()));
    register(onCommandFinished((_) => _handleCommandFinished()));

    register(
      onDidStartInput(
        (_) => _logCombinedStringIfTrace('PromptInputModel#onDidStartInput'),
      ),
    );
    register(
      onDidChangeInput(
        (_) => _logCombinedStringIfTrace('PromptInputModel#onDidChangeInput'),
      ),
    );
    register(
      onDidFinishInput(
        (_) => _logCombinedStringIfTrace('PromptInputModel#onDidFinishInput'),
      ),
    );
    register(
      onDidInterrupt(
        (_) => _logCombinedStringIfTrace('PromptInputModel#onDidInterrupt'),
      ),
    );
  }

  final Terminal _xterm;
  final ILogService _logService;

  PromptInputState _state = PromptInputState.unknown;
  @override
  PromptInputState get state => _state;

  IMarker? _commandStartMarker;
  int _commandStartX = 0;
  String? _lastPromptLine;
  String? _continuationPrompt;
  String? _shellType;

  String _lastUserInput = '';

  String _value = '';
  @override
  String get value => _value;
  @override
  String get prefix => _jsSubstring(_value, 0, _cursorIndex);
  @override
  String get suffix => _jsSubstring(
    _value,
    _cursorIndex,
    _ghostTextIndex == -1 ? null : _ghostTextIndex,
  );

  int _cursorIndex = 0;
  @override
  int get cursorIndex => _cursorIndex;

  int _ghostTextIndex = -1;
  @override
  int get ghostTextIndex => _ghostTextIndex;

  late final _onDidStartInput = register(Emitter<IPromptInputModelState>());
  @override
  late final IEvent<IPromptInputModelState> onDidStartInput =
      _onDidStartInput.event;
  late final _onDidChangeInput = register(Emitter<IPromptInputModelState>());
  @override
  late final IEvent<IPromptInputModelState> onDidChangeInput =
      _onDidChangeInput.event;
  late final _onDidFinishInput = register(Emitter<IPromptInputModelState>());
  @override
  late final IEvent<IPromptInputModelState> onDidFinishInput =
      _onDidFinishInput.event;
  late final _onDidInterrupt = register(Emitter<IPromptInputModelState>());
  @override
  late final IEvent<IPromptInputModelState> onDidInterrupt =
      _onDidInterrupt.event;

  void _logCombinedStringIfTrace(String message) {
    // Only generate the combined string if trace
    if (_logService.logLevel == LogLevelEnum.trace) {
      _logService.trace(message, [getCombinedString()]);
    }
  }

  @override
  void setShellType([String? shellType]) {
    _shellType = shellType;
  }

  void setContinuationPrompt(String value) {
    _continuationPrompt = value;
    _sync();
  }

  void setLastPromptLine(String value) {
    _lastPromptLine = value;
    _sync();
  }

  void setConfidentCommandLine(String value) {
    if (_value != value) {
      _value = value;
      _cursorIndex = -1;
      _ghostTextIndex = -1;
      _onDidChangeInput.fire(_createStateObject());
    }
  }

  @override
  String getCombinedString([bool emptyStringWhenEmpty = false]) {
    final value = _value.replaceAll('\n', '⏎');
    if (_cursorIndex == -1) {
      return value;
    }
    var result = '${_jsSubstring(value, 0, cursorIndex)}|';
    if (ghostTextIndex != -1) {
      result += '${_jsSubstring(value, cursorIndex, ghostTextIndex)}[';
      result += '${_jsSubstring(value, ghostTextIndex)}]';
    } else {
      result += _jsSubstring(value, cursorIndex);
    }
    if (result == '|' && emptyStringWhenEmpty) {
      return '';
    }
    return result;
  }

  ISerializedPromptInputModel serialize() {
    return ISerializedPromptInputModel(
      modelState: _createStateObject(),
      commandStartX: _commandStartX,
      lastPromptLine: _lastPromptLine,
      continuationPrompt: _continuationPrompt,
      lastUserInput: _lastUserInput,
    );
  }

  void deserialize(ISerializedPromptInputModel serialized) {
    _value = serialized.modelState.value;
    _cursorIndex = serialized.modelState.cursorIndex;
    _ghostTextIndex = serialized.modelState.ghostTextIndex;
    _commandStartX = serialized.commandStartX;
    _lastPromptLine = serialized.lastPromptLine;
    _continuationPrompt = serialized.continuationPrompt;
    _lastUserInput = serialized.lastUserInput;
  }

  void _handleCommandStart(ITerminalCommand command) {
    if (_state == PromptInputState.input) {
      return;
    }

    _state = PromptInputState.input;
    _commandStartMarker = command.marker;
    _commandStartX = _xterm.buffer.x;
    _value = '';
    _cursorIndex = 0;
    _onDidStartInput.fire(_createStateObject());
    _onDidChangeInput.fire(_createStateObject());

    // Trigger a sync if prompt terminator is set as that could adjust the
    // command start X
    final lastPromptLine = _lastPromptLine;
    if (lastPromptLine != null && lastPromptLine.isNotEmpty) {
      if (_commandStartX != lastPromptLine.length) {
        final line = _commandStartMarker == null
            ? null
            : _xterm.buffer.lines.get(_commandStartMarker!.line);
        if (line?.translateToString(true).startsWith(lastPromptLine) ?? false) {
          _commandStartX = lastPromptLine.length;
          _sync();
        }
      }
    }
  }

  void _handleCommandStartChanged() {
    if (_state != PromptInputState.input) {
      return;
    }

    _commandStartX = _xterm.buffer.x;
    _onDidChangeInput.fire(_createStateObject());
    _sync();
  }

  void _handleCommandExecuted() {
    if (_state == PromptInputState.execute) {
      return;
    }

    _cursorIndex = -1;

    // Remove any ghost text from the input if it exists on execute
    if (_ghostTextIndex != -1) {
      _value = _jsSubstring(_value, 0, _ghostTextIndex);
      _ghostTextIndex = -1;
    }

    final event = _createStateObject();
    if (_lastUserInput == '\u0003') {
      _lastUserInput = '';
      _onDidInterrupt.fire(event);
    }

    _state = PromptInputState.execute;
    _onDidFinishInput.fire(event);
    _onDidChangeInput.fire(event);
  }

  void _handleCommandFinished() {
    // Clear the prompt input value when command finishes to prepare for the
    // next command. This prevents runCommand from detecting leftover text and
    // sending ^C unnecessarily
    _value = '';
    _onDidChangeInput.fire(_createStateObject());
  }

  void _sync() {
    try {
      _doSync();
    } catch (e) {
      _logService.error('Error while syncing prompt input model', [e]);
    }
  }

  void _doSync() {
    if (_state != PromptInputState.input) {
      return;
    }

    var commandStartY = _commandStartMarker?.line;
    if (commandStartY == null) {
      return;
    }

    final buffer = _xterm.buffer;
    var line = buffer.lines.get(commandStartY);
    final absoluteCursorY = buffer.ybase + buffer.y;
    int? cursorIndex;

    var commandLine = line?.translateToString(true, _commandStartX);
    if (_shellType == fishShellType &&
        (line == null || commandLine == null || commandLine.isEmpty)) {
      commandStartY += 1;
      line = buffer.lines.get(commandStartY);
      if (line != null) {
        commandLine = line.translateToString(true);
        cursorIndex = absoluteCursorY == commandStartY
            ? buffer.x
            : commandLine.trimRight().length;
      }
    }
    if (line == null || commandLine == null) {
      _logService.trace('PromptInputModel#_sync: no line');
      return;
    }

    var value = commandLine;
    var ghostTextIndex = -1;
    if (cursorIndex == null) {
      if (absoluteCursorY == commandStartY) {
        cursorIndex = math.min(
          _getRelativeCursorIndex(_commandStartX, buffer, line),
          commandLine.length,
        );
      } else {
        cursorIndex = commandLine.trimRight().length;
      }
    }

    // From command start line to cursor line
    for (var y = commandStartY + 1; y <= absoluteCursorY; y++) {
      final nextLine = buffer.lines.get(y);
      final lineText = nextLine?.translateToString(true);
      if (lineText != null && lineText.isNotEmpty && nextLine != null) {
        // Check if the line wrapped without a new line (continuation) or
        // we're on the last line and the continuation prompt is not present,
        // so we need to add the value
        if (nextLine.isWrapped ||
            (absoluteCursorY == y &&
                (_continuationPrompt?.isNotEmpty ?? false) &&
                !_lineContainsContinuationPrompt(lineText))) {
          value += lineText;
          final relativeCursorIndex = _getRelativeCursorIndex(
            0,
            buffer,
            nextLine,
          );
          if (absoluteCursorY == y) {
            cursorIndex = cursorIndex! + relativeCursorIndex;
          } else {
            cursorIndex = cursorIndex! + lineText.length;
          }
        } else if (_shellType == fishShellType) {
          if (value.endsWith('\\')) {
            // Trim off the trailing backslash
            value = value.substring(0, value.length - 1);
            value += lineText.trim();
            cursorIndex = cursorIndex! + lineText.trim().length - 1;
          } else {
            if (RegExp(r'^ {6,}').hasMatch(lineText)) {
              // Was likely a new line
              value += '\n${lineText.trim()}';
              cursorIndex = cursorIndex! + lineText.trim().length + 1;
            } else {
              value += lineText;
              cursorIndex = cursorIndex! + lineText.length;
            }
          }
        }
        // Verify continuation prompt if we have it, if this line doesn't have
        // it then the user likely just pressed enter.
        else if (_continuationPrompt == null ||
            _lineContainsContinuationPrompt(lineText)) {
          final trimmedLineText = _trimContinuationPrompt(lineText);
          value += '\n$trimmedLineText';
          if (absoluteCursorY == y) {
            final continuationCellWidth = _getContinuationPromptCellWidth(
              nextLine,
              lineText,
            );
            final relativeCursorIndex = _getRelativeCursorIndex(
              continuationCellWidth,
              buffer,
              nextLine,
            );
            cursorIndex = cursorIndex! + relativeCursorIndex + 1;
          } else {
            cursorIndex = cursorIndex! + trimmedLineText.length + 1;
          }
        }
      }
    }

    // Below cursor line
    for (var y = absoluteCursorY + 1; y < buffer.ybase + _xterm.rows; y++) {
      final belowCursorLine = buffer.lines.get(y);
      final lineText = belowCursorLine?.translateToString(true);
      if (lineText != null && lineText.isNotEmpty && belowCursorLine != null) {
        if (_shellType == fishShellType) {
          value += lineText;
        } else if (_continuationPrompt == null ||
            _lineContainsContinuationPrompt(lineText)) {
          value += '\n${_trimContinuationPrompt(lineText)}';
        } else {
          value += lineText;
        }
      } else {
        break;
      }
    }

    if (_logService.logLevel == LogLevelEnum.trace) {
      _logService.trace('PromptInputModel#_sync: ${getCombinedString()}');
    }

    // Adjust trailing whitespace
    {
      var trailingWhitespace = _value.length - _value.trimRight().length;

      // Handle backspace key
      if (_lastUserInput == '\x7F') {
        _lastUserInput = '';
        if (cursorIndex == _cursorIndex - 1) {
          // If trailing whitespace is being increased by removing a
          // non-whitespace character
          if (_value.trimRight().length > value.trimRight().length &&
              value.trimRight().length <= cursorIndex!) {
            trailingWhitespace = math.max(
              (_value.length - 1) - value.trimRight().length,
              0,
            );
          }
          // Standard case; subtract from trailing whitespace
          else {
            trailingWhitespace = math.max(trailingWhitespace - 1, 0);
          }
        }
      }

      // Handle delete key
      if (_lastUserInput == '\x1b[3~') {
        _lastUserInput = '';
        if (cursorIndex == _cursorIndex) {
          trailingWhitespace = math.max(trailingWhitespace - 1, 0);
        }
      }

      final valueLines = value.split('\n');
      final isMultiLine = valueLines.length > 1;
      final valueEndTrimmed = value.trimRight();
      if (!isMultiLine) {
        // Adjust trimmed whitespace value based on cursor position
        if (valueEndTrimmed.length < value.length) {
          // Handle space key
          if (_lastUserInput == ' ') {
            _lastUserInput = '';
            if (cursorIndex! > valueEndTrimmed.length &&
                cursorIndex > _cursorIndex) {
              trailingWhitespace++;
            }
          }
          trailingWhitespace = math.max(
            math.max(cursorIndex! - valueEndTrimmed.length, trailingWhitespace),
            0,
          );
        }

        // Handle case where a non-space character is inserted in the middle
        // of trailing whitespace
        final charBeforeCursor =
            cursorIndex! <= 0 || cursorIndex - 1 >= value.length
            ? null
            : value[cursorIndex - 1];
        if (trailingWhitespace > 0 &&
            cursorIndex == _cursorIndex + 1 &&
            _lastUserInput != '' &&
            charBeforeCursor != ' ') {
          trailingWhitespace = _value.length - _cursorIndex;
        }
      }

      if (isMultiLine) {
        valueLines[valueLines.length - 1] = valueLines.last.trimRight();
        final continuationOffset =
            (valueLines.length - 1) * (_continuationPrompt?.length ?? 0);
        trailingWhitespace = math.max(
          0,
          cursorIndex! - value.length - continuationOffset,
        );
      }

      // As JavaScript's `repeat`, which throws on a negative count (the sync
      // is then abandoned and the error logged).
      RangeError.checkNotNegative(trailingWhitespace, 'trailingWhitespace');
      value =
          valueLines.map((e) => e.trimRight()).join('\n') +
          ' ' * trailingWhitespace;
    }

    ghostTextIndex = _scanForGhostText(buffer, line, cursorIndex!);

    if (_value != value ||
        _cursorIndex != cursorIndex ||
        _ghostTextIndex != ghostTextIndex) {
      _value = value;
      _cursorIndex = cursorIndex;
      _ghostTextIndex = ghostTextIndex;
      _onDidChangeInput.fire(_createStateObject());
    }
  }

  void _handleUserInput(String e) {
    _lastUserInput = e;
  }

  /// Detect ghost text by looking for italic or dim text in or after the
  /// cursor and non-italic/dim text in the first non-whitespace cell
  /// following command start and before the cursor.
  int _scanForGhostText(IBuffer buffer, IBufferLine line, int cursorIndex) {
    if (value.trim().isEmpty) {
      return -1;
    }
    // Check last non-whitespace character has non-ghost text styles
    var ghostTextIndex = -1;
    var proceedWithGhostTextCheck = false;
    var x = buffer.x;
    while (x > 0) {
      final cell = _getCell(line, --x);
      if (cell == null) {
        break;
      }
      if (cell.getChars().trim().isNotEmpty) {
        proceedWithGhostTextCheck = !_isCellStyledLikeGhostText(cell);
        break;
      }
    }

    // Check to the end of the line for possible ghost text. For example
    // pwsh's ghost text can look like this `Get-|Ch[ildItem]`
    if (proceedWithGhostTextCheck) {
      var potentialGhostIndexOffset = 0;
      var x = buffer.x;

      while (x < line.length) {
        final cell = _getCell(line, x++);
        if (cell == null || cell.getCode() == 0) {
          break;
        }
        if (_isCellStyledLikeGhostText(cell)) {
          ghostTextIndex = cursorIndex + potentialGhostIndexOffset;
          break;
        }

        potentialGhostIndexOffset += cell.getChars().length;
      }
    }

    // Ghost text may not be italic or dimmed, but will have a different
    // style than the rest of the line that precedes it.
    if (ghostTextIndex == -1) {
      ghostTextIndex = _scanForGhostTextAdvanced(buffer, line, cursorIndex);
    }

    if (ghostTextIndex > -1 &&
        _jsSubstring(value, ghostTextIndex).endsWith(' ')) {
      _value = value.trim();
      if (_jsSubstring(value, ghostTextIndex).isEmpty) {
        ghostTextIndex = -1;
      }
    }
    return ghostTextIndex;
  }

  int _scanForGhostTextAdvanced(
    IBuffer buffer,
    IBufferLine line,
    int cursorIndex,
  ) {
    var ghostTextIndex = -1;
    var currentPos = buffer.x; // Start scanning from the cursor position

    // Map to store styles and their corresponding positions
    final styleMap = <String, List<int>>{};

    // Identify the last non-whitespace character in the line
    var lastNonWhitespaceCell = _getCell(line, currentPos);
    var nextCell = lastNonWhitespaceCell;

    // Scan from the cursor position to the end of the line
    while (nextCell != null && currentPos < line.length) {
      final styleKey = _getCellStyleAsString(nextCell);

      // Track all occurrences of each unique style in the line
      styleMap[styleKey] = [...?styleMap[styleKey], currentPos];

      // Move to the next cell
      nextCell = _getCell(line, ++currentPos);

      // Update `lastNonWhitespaceCell` only if the new cell contains visible
      // characters
      if (nextCell != null && nextCell.getChars().trim().isNotEmpty) {
        lastNonWhitespaceCell = nextCell;
      }
    }

    // If there's no valid last non-whitespace cell OR the first and last
    // styles match (indicating no ghost text)
    if (lastNonWhitespaceCell == null ||
        lastNonWhitespaceCell.getChars().trim().isEmpty ||
        _cellStylesMatch(
          _getCell(line, _commandStartX),
          lastNonWhitespaceCell,
        )) {
      return -1;
    }

    // Retrieve the positions of all cells with the same style as
    // `lastNonWhitespaceCell`
    final positionsWithGhostStyle =
        styleMap[_getCellStyleAsString(lastNonWhitespaceCell)];
    if (positionsWithGhostStyle != null) {
      // Ghost text must start at the cursor or one char after (e.g. a space)
      // To account for cursor movement, we also ensure there are not 5+
      // spaces preceding the ghost text position
      if (positionsWithGhostStyle[0] > buffer.x + 1 &&
          _isPositionRightPrompt(line, positionsWithGhostStyle[0])) {
        return -1;
      }
      // Ensure these positions are contiguous
      for (var i = 1; i < positionsWithGhostStyle.length; i++) {
        if (positionsWithGhostStyle[i] != positionsWithGhostStyle[i - 1] + 1) {
          // Discontinuous styles, so may be syntax highlighting vs ghost text
          return -1;
        }
      }
      // Calculate the ghost text start index
      if (buffer.ybase + buffer.y == _commandStartMarker?.line) {
        ghostTextIndex = positionsWithGhostStyle[0] - _commandStartX;
      } else {
        ghostTextIndex = positionsWithGhostStyle[0];
      }
    }

    // Upstream then checks that no earlier cell in the line, back to the
    // command start, has `lastNonWhitespaceCell`'s style; but its guard reads
    // `!checkCell?.getChars.length` (the function's arity, 0), so every cell
    // is skipped and the check never rejects. Left out to behave the same.

    return ghostTextIndex >= cursorIndex ? ghostTextIndex : -1;
  }

  /// 5+ spaces preceding the position, following the command start,
  /// indicates that we're likely in a right prompt at the current position
  bool _isPositionRightPrompt(IBufferLine line, int position) {
    var count = 0;
    for (var i = position - 1; i >= _commandStartX; i--) {
      final cell = _getCell(line, i);
      // treat missing cell or whitespace-only cell as empty; reset count on
      // first non-empty
      if (cell == null || cell.getChars().trim().isEmpty) {
        count++;
        // If we've already found 5 consecutive empties we can early-return
        if (count >= 5) {
          return true;
        }
      } else {
        // consecutive sequence broken
        count = 0;
      }
    }
    return false;
  }

  String _getCellStyleAsString(CellData cell) {
    return '${cell.getFgColor()}${cell.getBgColor()}${cell.isBold()}'
        '${cell.isItalic()}${cell.isDim()}${cell.isUnderline()}'
        '${cell.isBlink()}${cell.isInverse()}${cell.isInvisible()}'
        '${cell.isStrikethrough()}${cell.isOverline()}'
        '${cell.getFgColorMode()}${cell.getBgColorMode()}';
  }

  bool _cellStylesMatch(CellData? a, CellData? b) {
    if (a == null || b == null) {
      return false;
    }
    return a.getFgColor() == b.getFgColor() &&
        a.getBgColor() == b.getBgColor() &&
        a.isBold() == b.isBold() &&
        a.isItalic() == b.isItalic() &&
        a.isDim() == b.isDim() &&
        a.isUnderline() == b.isUnderline() &&
        a.isBlink() == b.isBlink() &&
        a.isInverse() == b.isInverse() &&
        a.isInvisible() == b.isInvisible() &&
        a.isStrikethrough() == b.isStrikethrough() &&
        a.isOverline() == b.isOverline() &&
        a.getBgColorMode() == b.getBgColorMode() &&
        a.getFgColorMode() == b.getFgColorMode();
  }

  String _trimContinuationPrompt(String lineText) {
    if (_lineContainsContinuationPrompt(lineText)) {
      lineText = _jsSubstring(lineText, _continuationPrompt!.length);
    }
    return lineText;
  }

  bool _lineContainsContinuationPrompt(String lineText) {
    final continuationPrompt = _continuationPrompt;
    return continuationPrompt != null &&
        continuationPrompt.isNotEmpty &&
        lineText.startsWith(continuationPrompt.trimRight());
  }

  int _getContinuationPromptCellWidth(IBufferLine line, String lineText) {
    final continuationPrompt = _continuationPrompt;
    if (continuationPrompt == null ||
        continuationPrompt.isEmpty ||
        !lineText.startsWith(continuationPrompt.trimRight())) {
      return 0;
    }
    var buffer = '';
    var x = 0;
    while (buffer != continuationPrompt) {
      final cell = _getCell(line, x++);
      if (cell == null) {
        break;
      }
      buffer += cell.getChars();
    }
    return x;
  }

  int _getRelativeCursorIndex(
    int startCellX,
    IBuffer buffer,
    IBufferLine line,
  ) {
    return line.translateToString(false, startCellX, buffer.x).length;
  }

  bool _isCellStyledLikeGhostText(CellData cell) {
    return cell.isItalic() != 0 || cell.isDim() != 0;
  }

  IPromptInputModelState _createStateObject() {
    return PromptInputModelState(
      value: _value,
      prefix: prefix,
      suffix: suffix,
      cursorIndex: _cursorIndex,
      ghostTextIndex: _ghostTextIndex,
    );
  }
}

/// The public API's `IBufferLine.getCell`: a new cell, null outside the
/// line.
CellData? _getCell(IBufferLine line, int x) {
  if (x < 0 || x >= line.length) {
    return null;
  }
  return line.loadCell(x, CellData()) as CellData;
}

/// JavaScript's `String.prototype.substring`: the bounds are clamped to the
/// string and swapped when reversed, where Dart's would throw.
String _jsSubstring(String s, int start, [int? end]) {
  var from = start.clamp(0, s.length);
  var to = (end ?? s.length).clamp(0, s.length);
  if (from > to) {
    (from, to) = (to, from);
  }
  return s.substring(from, to);
}
