/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A command the shell ran, as command detection saw it: where its prompt,
// command line and output are in the buffer (markers), what it was, where
// it ran and how it exited; and the command being typed or run now.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/commandDetection/
// terminalCommand.ts, on the ported xterm core's internal terminal.

import 'dart:math' as math;

import 'package:bao_xterm/common/buffer/types.dart';
import 'package:bao_xterm/headless/terminal.dart';

import '../../uuid.dart';
import '../capabilities.dart';

/// Milliseconds since the epoch, as JavaScript's `Date.now()`.
int _now() => DateTime.now().millisecondsSinceEpoch;

/// Upstream `ITerminalCommandProperties`.
class TerminalCommandProperties {
  TerminalCommandProperties({
    required this.command,
    required this.commandLineConfidence,
    required this.isTrusted,
    required this.timestamp,
    required this.duration,
    required this.id,
    required this.marker,
    required this.cwd,
    required this.exitCode,
    required this.commandStartLineContent,
    required this.markProperties,
    required this.executedX,
    required this.startX,
    this.promptStartMarker,
    this.endMarker,
    this.executedMarker,
    this.aliases,
    this.wasReplayed,
  });

  String command;
  String commandLineConfidence;
  bool isTrusted;
  int timestamp;
  int duration;
  String? id;
  IMarker? marker;
  String? cwd;
  int? exitCode;
  String? commandStartLineContent;
  IMarkProperties? markProperties;
  int? executedX;
  int? startX;

  IMarker? promptStartMarker;
  IMarker? endMarker;
  IMarker? executedMarker;
  List<List<String>>? aliases;
  bool? wasReplayed;
}

class TerminalCommand implements ITerminalCommand {
  TerminalCommand(this._xterm, this._properties);

  /// What `onCommandStarted` fires: upstream fires a
  /// `{ marker, markProperties } as ITerminalCommand` object, the command
  /// having no line, output or exit code yet.
  TerminalCommand.started(
    Terminal xterm, {
    IMarker? marker,
    IMarkProperties? markProperties,
  }) : this(
         xterm,
         TerminalCommandProperties(
           command: '',
           commandLineConfidence: 'low',
           isTrusted: false,
           timestamp: 0,
           duration: 0,
           id: null,
           marker: marker,
           cwd: null,
           exitCode: null,
           commandStartLineContent: null,
           markProperties: markProperties,
           executedX: null,
           startX: null,
         ),
       );

  final Terminal _xterm;
  final TerminalCommandProperties _properties;

  @override
  String get command => _properties.command;
  @override
  String get commandLineConfidence => _properties.commandLineConfidence;
  @override
  bool get isTrusted => _properties.isTrusted;
  @override
  int get timestamp => _properties.timestamp;
  @override
  int get duration => _properties.duration;
  @override
  IMarker? get promptStartMarker => _properties.promptStartMarker;
  @override
  IMarker? get marker => _properties.marker;
  @override
  IMarker? get endMarker => _properties.endMarker;
  @override
  set endMarker(IMarker? value) => _properties.endMarker = value;
  @override
  IMarker? get executedMarker => _properties.executedMarker;
  @override
  List<List<String>>? get aliases => _properties.aliases;
  @override
  bool? get wasReplayed => _properties.wasReplayed;
  @override
  String? get cwd => _properties.cwd;
  @override
  int? get exitCode => _properties.exitCode;
  @override
  String? get commandStartLineContent => _properties.commandStartLineContent;
  @override
  IMarkProperties? get markProperties => _properties.markProperties;
  @override
  int? get executedX => _properties.executedX;
  @override
  int? get startX => _properties.startX;
  @override
  String? get id => _properties.id;

  static TerminalCommand? deserialize(
    Terminal xterm,
    ISerializedTerminalCommand serialized,
    bool isCommandStorageDisabled,
  ) {
    final buffer = xterm.buffers.normal;
    final cursor = buffer.ybase + buffer.y;
    final marker = serialized.startLine != null
        ? xterm.registerMarker(serialized.startLine! - cursor)
        : null;

    // Check for invalid command
    if (marker == null) {
      return null;
    }
    final promptStartMarker = serialized.promptStartLine != null
        ? xterm.registerMarker(serialized.promptStartLine! - cursor)
        : null;

    // Valid full command
    final endMarker = serialized.endLine != null
        ? xterm.registerMarker(serialized.endLine! - cursor)
        : null;
    final executedMarker = serialized.executedLine != null
        ? xterm.registerMarker(serialized.executedLine! - cursor)
        : null;
    return TerminalCommand(
      xterm,
      TerminalCommandProperties(
        command: isCommandStorageDisabled ? '' : serialized.command,
        commandLineConfidence: serialized.commandLineConfidence,
        isTrusted: serialized.isTrusted,
        id: serialized.id,
        promptStartMarker: promptStartMarker,
        marker: marker,
        startX: serialized.startX,
        endMarker: endMarker,
        executedMarker: executedMarker,
        executedX: serialized.executedX,
        timestamp: serialized.timestamp,
        duration: serialized.duration,
        cwd: serialized.cwd,
        commandStartLineContent: serialized.commandStartLineContent,
        exitCode: serialized.exitCode,
        markProperties: serialized.markProperties,
        aliases: null,
        wasReplayed: true,
      ),
    );
  }

  ISerializedTerminalCommand serialize(bool isCommandStorageDisabled) {
    return ISerializedTerminalCommand(
      promptStartLine: promptStartMarker?.line,
      startLine: marker?.line,
      startX: null,
      endLine: endMarker?.line,
      executedLine: executedMarker?.line,
      executedX: executedX,
      command: isCommandStorageDisabled ? '' : command,
      commandLineConfidence: isCommandStorageDisabled
          ? 'low'
          : commandLineConfidence,
      isTrusted: isTrusted,
      cwd: cwd,
      exitCode: exitCode,
      commandStartLineContent: commandStartLineContent,
      timestamp: timestamp,
      duration: duration,
      markProperties: markProperties,
      id: id,
    );
  }

  @override
  String extractCommandLine() {
    return _extractCommandLine(
      _xterm.buffer,
      _xterm.cols,
      marker,
      startX,
      executedMarker,
      executedX,
    );
  }

  @override
  String? getOutput() {
    final executedMarker = this.executedMarker;
    final endMarker = this.endMarker;
    if (executedMarker == null || endMarker == null) {
      return null;
    }
    final startLine = executedMarker.line;
    final endLine = endMarker.line;

    if (startLine == endLine) {
      return null;
    }
    final output = StringBuffer();
    var currentLine = '';
    final buffer = _xterm.buffer;
    for (var i = startLine; i < endLine; i++) {
      final line = buffer.lines.get(i);
      if (line == null) {
        continue;
      }
      // NOTE: xterm stores wrapping state on the *next* line, not the current
      // one. Use next line's `isWrapped` to determine whether this line
      // should be joined.
      final isWrapped = i + 1 < endLine
          ? buffer.lines.get(i + 1)?.isWrapped ?? false
          : false;
      currentLine += line.translateToString(!isWrapped);
      if (!isWrapped) {
        output
          ..write(currentLine)
          ..write('\n');
        currentLine = '';
      }
    }
    if (currentLine.isNotEmpty) {
      output.write(currentLine);
    }
    return output.isEmpty ? null : output.toString();
  }

  @override
  ITerminalOutputMatch? getOutputMatch(ITerminalOutputMatcher outputMatcher) {
    final executedMarker = this.executedMarker;
    final endMarker = this.endMarker;
    if (executedMarker == null || endMarker == null) {
      return null;
    }
    final endLine = endMarker.line;
    if (endLine == -1) {
      return null;
    }
    final buffer = _xterm.buffer;
    final startLine = math.max(executedMarker.line, 0);
    final matcher = outputMatcher.lineMatcher;
    final regex = matcher is RegExp ? matcher : RegExp(matcher as String);
    final linesToCheck = matcher is String
        ? 1
        : outputMatcher.length != 0
        ? outputMatcher.length
        : _countNewLines(regex);
    final lines = <String>[];
    RegExpMatch? match;
    if (outputMatcher.anchor == 'bottom') {
      for (var i = endLine - outputMatcher.offset; i >= startLine; i--) {
        var wrappedLineStart = i;
        final wrappedLineEnd = i;
        while (wrappedLineStart >= startLine &&
            (buffer.lines.get(wrappedLineStart)?.isWrapped ?? false)) {
          wrappedLineStart--;
        }
        i = wrappedLineStart;
        lines.insert(
          0,
          _getXtermLineContent(
            buffer,
            wrappedLineStart,
            wrappedLineEnd,
            _xterm.cols,
          ),
        );
        match ??= regex.firstMatch(lines[0]);
        if (lines.length >= linesToCheck) {
          break;
        }
      }
    } else {
      for (var i = startLine + outputMatcher.offset; i < endLine; i++) {
        final wrappedLineStart = i;
        var wrappedLineEnd = i;
        while (wrappedLineEnd + 1 < endLine &&
            (buffer.lines.get(wrappedLineEnd + 1)?.isWrapped ?? false)) {
          wrappedLineEnd++;
        }
        i = wrappedLineEnd;
        lines.add(
          _getXtermLineContent(
            buffer,
            wrappedLineStart,
            wrappedLineEnd,
            _xterm.cols,
          ),
        );
        match ??= regex.firstMatch(lines[lines.length - 1]);
        if (lines.length >= linesToCheck) {
          break;
        }
      }
    }
    return match != null
        ? ITerminalOutputMatch(regexMatch: match, outputLines: lines)
        : null;
  }

  @override
  bool hasOutput() {
    final executedMarker = this.executedMarker;
    final endMarker = this.endMarker;
    return !(executedMarker?.isDisposed ?? false) &&
        !(endMarker?.isDisposed ?? false) &&
        (executedMarker != null &&
            endMarker != null &&
            executedMarker.line < endMarker.line);
  }

  @override
  int getPromptRowCount() {
    return _getPromptRowCount(this, _xterm.buffer);
  }

  @override
  int getCommandRowCount() {
    return _getCommandRowCount(this);
  }
}

abstract interface class ICurrentPartialCommand {
  abstract IMarker? promptStartMarker;

  abstract IMarker? commandStartMarker;
  abstract int? commandStartX;
  abstract String? commandStartLineContent;

  abstract int? commandRightPromptStartX;
  abstract int? commandRightPromptEndX;

  abstract IMarker? commandLines;

  abstract IMarker? commandExecutedMarker;
  abstract int? commandExecutedX;

  abstract IMarker? commandFinishedMarker;

  abstract IMarker? currentContinuationMarker;
  abstract List<({IMarker marker, int end})>? continuations;

  abstract String? command;

  /// Whether the command line is trusted via a nonce.
  abstract bool? isTrusted;

  /// Something invalidated the command before it finished, this will prevent
  /// the onCommandFinished event from firing.
  abstract bool? isInvalid;

  int getPromptRowCount();
  int getCommandRowCount();
}

class PartialTerminalCommand implements ICurrentPartialCommand {
  PartialTerminalCommand(this._xterm, [String? id]) : id = id ?? generateUuid();

  final Terminal _xterm;

  @override
  IMarker? promptStartMarker;

  @override
  IMarker? commandStartMarker;
  @override
  int? commandStartX;
  @override
  String? commandStartLineContent;

  @override
  int? commandRightPromptStartX;
  @override
  int? commandRightPromptEndX;

  @override
  IMarker? commandLines;

  @override
  IMarker? commandExecutedMarker;
  @override
  int? commandExecutedX;

  int? _commandExecutedTimestamp;
  int? _commandDuration;

  @override
  IMarker? commandFinishedMarker;

  @override
  IMarker? currentContinuationMarker;
  @override
  List<({IMarker marker, int end})>? continuations;

  String? cwd;
  @override
  String? command;

  /// `'low'`, `'medium'` or `'high'`.
  String? commandLineConfidence;
  String? id;

  @override
  bool? isTrusted;
  @override
  bool? isInvalid;

  /// Track temporarily if the command was recently cleared, this can be used
  /// for marker adjustments
  bool? wasCleared;

  ISerializedTerminalCommand? serialize(String? cwd) {
    final commandStartMarker = this.commandStartMarker;
    if (commandStartMarker == null) {
      return null;
    }

    return ISerializedTerminalCommand(
      promptStartLine: promptStartMarker?.line,
      startLine: commandStartMarker.line,
      startX: commandStartX,
      endLine: null,
      executedLine: null,
      executedX: null,
      command: '',
      commandLineConfidence: 'low',
      isTrusted: true,
      cwd: cwd,
      exitCode: null,
      commandStartLineContent: null,
      timestamp: 0,
      duration: 0,
      markProperties: null,
      id: id,
    );
  }

  TerminalCommand? promoteToFullCommand(
    String? cwd,
    int? exitCode,
    bool ignoreCommandLine,
    IMarkProperties? markProperties,
  ) {
    // When the command finishes and executed never fires the placeholder
    // selector should be used.
    if (exitCode == null && this.command == null) {
      this.command = '';
    }

    final command = this.command;
    if ((command != null && !command.startsWith('\\')) || ignoreCommandLine) {
      return TerminalCommand(
        _xterm,
        TerminalCommandProperties(
          command: ignoreCommandLine ? '' : (command ?? ''),
          commandLineConfidence: ignoreCommandLine
              ? 'low'
              : (commandLineConfidence ?? 'low'),
          isTrusted: isTrusted ?? false,
          id: id,
          promptStartMarker: promptStartMarker,
          marker: commandStartMarker,
          startX: commandStartX,
          endMarker: commandFinishedMarker,
          executedMarker: commandExecutedMarker,
          executedX: commandExecutedX,
          timestamp: _now(),
          duration: _commandDuration ?? 0,
          cwd: cwd,
          exitCode: exitCode,
          commandStartLineContent: commandStartLineContent,
          markProperties: markProperties,
        ),
      );
    }

    return null;
  }

  void markExecutedTime() {
    _commandExecutedTimestamp ??= _now();
  }

  void markFinishedTime() {
    if (_commandDuration == null && _commandExecutedTimestamp != null) {
      _commandDuration = _now() - _commandExecutedTimestamp!;
    }
  }

  String extractCommandLine() {
    return _extractCommandLine(
      _xterm.buffer,
      _xterm.cols,
      commandStartMarker,
      commandStartX,
      commandExecutedMarker,
      commandExecutedX,
    );
  }

  @override
  int getPromptRowCount() {
    return _getPromptRowCount(this, _xterm.buffer);
  }

  @override
  int getCommandRowCount() {
    return _getCommandRowCount(this);
  }
}

String _extractCommandLine(
  IBuffer buffer,
  int cols,
  IMarker? commandStartMarker,
  int? commandStartX,
  IMarker? commandExecutedMarker,
  int? commandExecutedX,
) {
  if (commandStartMarker == null ||
      commandExecutedMarker == null ||
      commandStartX == null ||
      commandExecutedX == null) {
    return '';
  }
  final content = StringBuffer();
  for (var i = commandStartMarker.line; i <= commandExecutedMarker.line; i++) {
    final line = buffer.lines.get(i);
    if (line != null) {
      content.write(
        line.translateToString(
          true,
          i == commandStartMarker.line ? commandStartX : 0,
          i == commandExecutedMarker.line ? commandExecutedX : cols,
        ),
      );
    }
  }
  return content.toString();
}

/// Upstream `getXtermLineContent` (terminalCommand.ts and
/// commandDetectionCapability.ts have the same).
String getXtermLineContent(
  IBuffer buffer,
  int lineStart,
  int lineEnd,
  int cols,
) => _getXtermLineContent(buffer, lineStart, lineEnd, cols);

String _getXtermLineContent(
  IBuffer buffer,
  int lineStart,
  int lineEnd,
  int cols,
) {
  // Cap the maximum number of lines generated to prevent potential
  // performance problems. This is more of a sanity check as the wrapped line
  // should already be trimmed down at this point.
  final maxLineLength = 2048 / cols * 2;
  final end = math.min(lineEnd, lineStart + maxLineLength);
  final content = StringBuffer();
  for (var i = lineStart; i <= end; i++) {
    // Make sure only 0 to cols are considered as resizing when windows mode
    // is enabled will retain buffer data outside of the terminal width as
    // reflow is disabled.
    final line = buffer.lines.get(i);
    if (line != null) {
      content.write(line.translateToString(true, 0, cols));
    }
  }
  return content.toString();
}

int _countNewLines(RegExp regex) {
  if (!regex.isMultiLine) {
    return 1;
  }
  final source = regex.pattern;
  var count = 1;
  var i = source.indexOf(r'\n');
  while (i != -1) {
    count++;
    i = source.indexOf(r'\n', i + 1);
  }
  return count;
}

/// [command] is an [ITerminalCommand] or an [ICurrentPartialCommand].
int _getPromptRowCount(Object command, IBuffer buffer) {
  final (marker, promptStartMarker) = switch (command) {
    ITerminalCommand() => (command.marker, command.promptStartMarker),
    ICurrentPartialCommand() => (
      command.commandStartMarker,
      command.promptStartMarker,
    ),
    _ => (null, null),
  };
  if (marker == null || promptStartMarker == null) {
    return 1;
  }
  var promptStartLine = promptStartMarker.line;
  // Trim any leading whitespace-only lines to retain vertical space
  while (promptStartLine < marker.line &&
      (buffer.lines.get(promptStartLine)?.translateToString(true) ?? '')
          .isEmpty) {
    promptStartLine++;
  }
  return marker.line - promptStartLine + 1;
}

/// [command] is an [ITerminalCommand] or an [ICurrentPartialCommand].
int _getCommandRowCount(Object command) {
  final (marker, executedMarker, executedX) = switch (command) {
    ITerminalCommand() => (
      command.marker,
      command.executedMarker,
      command.executedX,
    ),
    ICurrentPartialCommand() => (
      command.commandStartMarker,
      command.commandExecutedMarker,
      command.commandExecutedX,
    ),
    _ => (null, null, null),
  };
  if (marker == null || executedMarker == null) {
    return 1;
  }
  final commandExecutedLine = math.max(executedMarker.line, marker.line);
  var commandRowCount = commandExecutedLine - marker.line + 1;
  // Trim the last line if the cursor X is in the left-most cell
  if (executedX == 0) {
    commandRowCount--;
  }
  return commandRowCount;
}

/// Whether [command] is a finished [ITerminalCommand] rather than the
/// [ICurrentPartialCommand].
bool isFullTerminalCommand(Object command) => command is ITerminalCommand;
