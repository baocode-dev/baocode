/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Reads the shell integration sequences from a terminal's output (VS Code's
// OSC 633, FinalTerm's OSC 133, iTerm2's OSC 1337, OSC 7 and OSC 9;9) and
// passes them on to the capabilities, adding each on its first sequence.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/xterm/shellIntegrationAddon.ts, with
// `sanitizeCwd` from src/vs/platform/terminal/common/terminalEnvironment.ts,
// `removeAnsiEscapeCodesFromPrompt` from src/vs/base/common/strings.ts and
// the parts of `URI.parse` OSC 7 needs from src/vs/base/common/uri.ts.
//
// The addon is activated on the ported xterm core's internal terminal. There
// is no telemetry, as upstream without a telemetry service: no activation
// timeout either. `getMarkerId` (which returns nothing) is left out.

import 'dart:convert';

import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/common/lifecycle.dart';
import 'package:bao_xterm/common/public/parser_api.dart';
import 'package:bao_xterm/common/services/services.dart';
import 'package:bao_xterm/headless/terminal.dart';

import 'capabilities/buffer_mark_capability.dart';
import 'capabilities/capabilities.dart';
import 'capabilities/command_detection_capability.dart';
import 'capabilities/cwd_detection_capability.dart';
import 'capabilities/partial_command_detection_capability.dart';
import 'capabilities/prompt_type_detection_capability.dart';
import 'capabilities/shell_env_detection_capability.dart';
import 'capabilities/terminal_capability_store.dart';

// Shell integration is a feature that enhances the terminal's understanding
// of what's happening in the shell by injecting special sequences into the
// shell's prompt using the "Set Text Parameters" sequence (`OSC Ps ; Pt ST`).
//
// Definitions:
// - OSC: `\x1b]`
// - Ps:  A single (usually optional) numeric parameter, composed of one or
//        more digits.
// - Pt:  A text parameter composed of printable characters.
// - ST: `\x7`
//
// This is inspired by a feature of the same name in the FinalTerm, iTerm2
// and kitty terminals.

/// The identifier for the first numeric parameter (`Ps`) for OSC commands
/// used by shell integration.
abstract final class ShellIntegrationOscPs {
  /// Sequences pioneered by FinalTerm.
  static const finalTerm = 133;

  /// Sequences pioneered by VS Code. The number is derived from the least
  /// significant digit of "VSC" when encoded in hex ("VSC" = 0x56, 0x53,
  /// 0x43).
  static const vsCode = 633;

  /// Sequences pioneered by iTerm.
  static const iTerm = 1337;
  static const setCwd = 7;
  static const setWindowsFriendlyCwd = 9;
}

/// Sequences pioneered by FinalTerm (`OSC 133 ; <Pt> ST`).
abstract final class _FinalTermOscPt {
  /// The start of the prompt, this is expected to always appear at the start
  /// of a line.
  static const promptStart = 'A';

  /// The start of a command, ie. where the user inputs their command.
  static const commandStart = 'B';

  /// Sent just before the command output begins.
  static const commandExecuted = 'C';

  /// Sent just after a command has finished. The exit code is optional, when
  /// not specified it means no command was run (ie. enter on empty prompt or
  /// ctrl+c). Format: `OSC 133 ; D [; <ExitCode>] ST`
  static const commandFinished = 'D';
}

/// VS Code-specific shell integration sequences (`OSC 633 ; <Pt> ST`); see
/// upstream for each one's format. Some of these are based on more common
/// alternatives like those pioneered in FinalTerm. If multiple shell
/// integration scripts run, VS Code will prioritize the VS Code-specific
/// ones.
abstract final class _VSCodeOscPt {
  static const promptStart = 'A';
  static const commandStart = 'B';
  static const commandExecuted = 'C';

  /// `OSC 633 ; D [; <ExitCode>] ST`
  static const commandFinished = 'D';

  /// Explicitly set the command line, escaped as
  /// [serializeVSCodeOscMessage] does:
  /// `OSC 633 ; E [; <CommandLine> [; <Nonce>]] ST`
  static const commandLine = 'E';
  static const continuationStart = 'F';
  static const continuationEnd = 'G';
  static const rightPromptStart = 'H';
  static const rightPromptEnd = 'I';

  /// Set the value of an arbitrary property (known: `Cwd`, `IsWindows`,
  /// `ContinuationPrompt`, `HasRichCommandDetection`, `Prompt`,
  /// `PromptType`, `Task`):
  /// `OSC 633 ; P ; <Property>=<Value> ST`
  static const property = 'P';

  /// `OSC 633 ; SetMark [; Id=<string>] [; Hidden] ST`
  static const setMark = 'SetMark';

  /// `OSC 633 ; EnvJson ; <Environment> ; <Nonce> ST`
  static const envJson = 'EnvJson';

  /// `OSC 633 ; EnvSingleDelete ; <Key> ; <Value> [; <Nonce>] ST`
  static const envSingleDelete = 'EnvSingleDelete';

  /// `OSC 633 ; EnvSingleStart ; <Clear> [; <Nonce>] ST`
  static const envSingleStart = 'EnvSingleStart';

  /// `OSC 633 ; EnvSingleEntry ; <Key> ; <Value> [; <Nonce>] ST`
  static const envSingleEntry = 'EnvSingleEntry';

  /// `OSC 633 ; EnvSingleEnd [; <Nonce>] ST`
  static const envSingleEnd = 'EnvSingleEnd';
}

/// ITerm sequences
abstract final class _ITermOscPt {
  /// Sets a mark/point-of-interest in the buffer: `OSC 1337 ; SetMark ST`
  static const setMark = 'SetMark';

  /// Reports current working directory (CWD):
  /// `OSC 1337 ; CurrentDir=<Cwd> ST`
  static const currentDir = 'CurrentDir';
}

/// Which shell integration the terminal has seen (upstream in terminal.ts).
enum ShellIntegrationStatus {
  /// No shell integration sequences have been encountered.
  off,

  /// Final term shell integration sequences have been encountered.
  finalTerm,

  /// VS Code shell integration sequences have been encountered. Supercedes
  /// FinalTerm.
  vsCode,
}

/// The shell integration addon extends xterm by reading shell integration
/// sequences and creating capabilities and passing along relevant sequences
/// to the capabilities. This is meant to encapsulate all handling/parsing of
/// sequences so the capabilities don't need to.
class ShellIntegrationAddon extends Disposable {
  /// [nonce] is the terminal's `VSCODE_NONCE`: command lines, cwds and
  /// environments that come with it are trusted. [isWindows] is whether the
  /// app runs on Windows, where cwds get an uppercase drive letter.
  ShellIntegrationAddon(
    this._nonce,
    this._onDidExecuteText,
    this._logService, {
    this._isWindows = false,
  });

  final String _nonce;
  final IEvent<void>? _onDidExecuteText;
  final ILogService _logService;
  final bool _isWindows;
  Terminal? _terminal;

  late final TerminalCapabilityStore capabilities = register(
    TerminalCapabilityStore(),
  );

  final Set<String> _seenSequences = {};
  Set<String> get seenSequences => Set.unmodifiable(_seenSequences);

  ShellIntegrationStatus _status = ShellIntegrationStatus.off;
  ShellIntegrationStatus get status => _status;

  late final _onDidChangeStatus = register(Emitter<ShellIntegrationStatus>());
  late final IEvent<ShellIntegrationStatus> onDidChangeStatus =
      _onDidChangeStatus.event;
  late final _onDidChangeSeenSequences = register(Emitter<Set<String>>());
  late final IEvent<Set<String>> onDidChangeSeenSequences =
      _onDidChangeSeenSequences.event;

  void activate(Terminal xterm) {
    _terminal = xterm;
    final parser = ParserApi(xterm);
    capabilities.add(
      TerminalCapability.partialCommandDetection,
      register(PartialCommandDetectionCapability(xterm, _onDidExecuteText)),
    );
    register(
      parser.registerOscHandler(
        ShellIntegrationOscPs.vsCode,
        _handleVSCodeSequence,
      ),
    );
    register(
      parser.registerOscHandler(
        ShellIntegrationOscPs.iTerm,
        _doHandleITermSequence,
      ),
    );
    register(
      parser.registerOscHandler(
        ShellIntegrationOscPs.finalTerm,
        _handleFinalTermSequence,
      ),
    );
    register(
      parser.registerOscHandler(ShellIntegrationOscPs.setCwd, _doHandleSetCwd),
    );
    register(
      parser.registerOscHandler(
        ShellIntegrationOscPs.setWindowsFriendlyCwd,
        _doHandleSetWindowsFriendlyCwd,
      ),
    );
  }

  void setNextCommandId(String command, String commandId) {
    final terminal = _terminal;
    if (terminal != null) {
      createOrGetCommandDetection(terminal)
          .setNextCommandId(command, commandId);
    }
  }

  void _markSequenceSeen(String sequence) {
    if (_seenSequences.add(sequence)) {
      _onDidChangeSeenSequences.fire(seenSequences);
    }
  }

  bool _handleFinalTermSequence(String data) {
    final didHandle = _doHandleFinalTermSequence(data);
    if (_status == ShellIntegrationStatus.off) {
      _status = ShellIntegrationStatus.finalTerm;
      _onDidChangeStatus.fire(_status);
    }
    return didHandle;
  }

  bool _doHandleFinalTermSequence(String data) {
    final terminal = _terminal;
    if (terminal == null) {
      return false;
    }

    // Pass the sequence along to the capability
    // It was considered to disable the common protocol in order to not
    // confuse the VS Code shell integration if both happen for some reason.
    // This doesn't work for powerlevel10k when instant prompt is enabled
    // though. If this does end up being a problem we could pass a type flag
    // through the capability calls
    final [command, ...args] = data.split(';');
    _logService.trace(
      'ShellIntegrationAddon#_doHandleFinalTermSequence: received sequence '
      '$command',
    );
    _markSequenceSeen(command);
    switch (command) {
      case _FinalTermOscPt.promptStart:
        createOrGetCommandDetection(terminal).handlePromptStart();
        return true;
      case _FinalTermOscPt.commandStart:
        // Ignore the command line for these sequences as it's unreliable for
        // example in powerlevel10k
        createOrGetCommandDetection(terminal).handleCommandStart(
          const IHandleCommandOptions(ignoreCommandLine: true),
        );
        return true;
      case _FinalTermOscPt.commandExecuted:
        createOrGetCommandDetection(terminal).handleCommandExecuted();
        return true;
      case _FinalTermOscPt.commandFinished:
        final exitCode = args.length == 1 ? _parseInt(args[0]) : null;
        createOrGetCommandDetection(terminal).handleCommandFinished(exitCode);
        return true;
    }
    return false;
  }

  bool _handleVSCodeSequence(String data) {
    final didHandle = _doHandleVSCodeSequence(data);
    if (_status != ShellIntegrationStatus.vsCode) {
      _status = ShellIntegrationStatus.vsCode;
      _onDidChangeStatus.fire(_status);
    }
    return didHandle;
  }

  bool _doHandleVSCodeSequence(String data) {
    final terminal = _terminal;
    if (terminal == null) {
      return false;
    }

    // Pass the sequence along to the capability
    final argsIndex = data.indexOf(';');
    final command = argsIndex == -1 ? data : data.substring(0, argsIndex);
    _logService.trace(
      'ShellIntegrationAddon#_doHandleVSCodeSequence: received sequence '
      '$command',
    );
    _markSequenceSeen(command);
    final args = argsIndex == -1
        ? const <String>[]
        : data.substring(argsIndex + 1).split(';');
    String? arg(int i) => i < args.length ? args[i] : null;
    switch (command) {
      case _VSCodeOscPt.promptStart:
        createOrGetCommandDetection(terminal).handlePromptStart();
        return true;
      case _VSCodeOscPt.commandStart:
        createOrGetCommandDetection(terminal).handleCommandStart();
        return true;
      case _VSCodeOscPt.commandExecuted:
        createOrGetCommandDetection(terminal).handleCommandExecuted();
        return true;
      case _VSCodeOscPt.commandFinished:
        final arg0 = arg(0);
        final exitCode = arg0 != null ? _parseInt(arg0) : null;
        createOrGetCommandDetection(terminal).handleCommandFinished(exitCode);
        return true;
      case _VSCodeOscPt.commandLine:
        final arg0 = arg(0);
        final arg1 = arg(1);
        final commandLine = arg0 != null
            ? deserializeVSCodeOscMessage(arg0)
            : '';
        createOrGetCommandDetection(terminal)
            .setCommandLine(commandLine, arg1 == _nonce);
        return true;
      case _VSCodeOscPt.continuationStart:
        createOrGetCommandDetection(terminal).handleContinuationStart();
        return true;
      case _VSCodeOscPt.continuationEnd:
        createOrGetCommandDetection(terminal).handleContinuationEnd();
        return true;
      case _VSCodeOscPt.envJson:
        final arg0 = arg(0);
        final arg1 = arg(1);
        if (arg0 != null) {
          try {
            final env = (jsonDecode(deserializeVSCodeOscMessage(arg0)) as Map)
                .map((key, value) => MapEntry(key as String, value as String?));
            createOrGetShellEnvDetection().setEnvironment(env, arg1 == _nonce);
          } catch (e) {
            _logService.warn(
              'Failed to parse environment from shell integration sequence',
              [arg0],
            );
          }
        }
        return true;
      case _VSCodeOscPt.envSingleStart:
        createOrGetShellEnvDetection().startEnvironmentSingleVar(
          arg(0) == '1',
          arg(1) == _nonce,
        );
        return true;
      case _VSCodeOscPt.envSingleDelete:
        final arg0 = arg(0);
        final arg1 = arg(1);
        final arg2 = arg(2);
        if (arg0 != null && arg1 != null) {
          final env = deserializeVSCodeOscMessage(arg1);
          createOrGetShellEnvDetection().deleteEnvironmentSingleVar(
            arg0,
            env,
            arg2 == _nonce,
          );
        }
        return true;
      case _VSCodeOscPt.envSingleEntry:
        final arg0 = arg(0);
        final arg1 = arg(1);
        final arg2 = arg(2);
        if (arg0 != null && arg1 != null) {
          final env = deserializeVSCodeOscMessage(arg1);
          createOrGetShellEnvDetection().setEnvironmentSingleVar(
            arg0,
            env,
            arg2 == _nonce,
          );
        }
        return true;
      case _VSCodeOscPt.envSingleEnd:
        createOrGetShellEnvDetection().endEnvironmentSingleVar(
          arg(0) == _nonce,
        );
        return true;
      case _VSCodeOscPt.rightPromptStart:
        createOrGetCommandDetection(terminal).handleRightPromptStart();
        return true;
      case _VSCodeOscPt.rightPromptEnd:
        createOrGetCommandDetection(terminal).handleRightPromptEnd();
        return true;
      case _VSCodeOscPt.property:
        final arg0 = arg(0);
        final deserialized = arg0 != null
            ? deserializeVSCodeOscMessage(arg0)
            : '';
        final (:key, :value) = parseKeyValueAssignment(deserialized);
        if (value == null) {
          return true;
        }
        switch (key) {
          case 'ContinuationPrompt':
            _updateContinuationPrompt(removeAnsiEscapeCodesFromPrompt(value));
            return true;
          case 'Cwd':
            // OSC 633 ; P ; Cwd=<value> ; <nonce> ST — the nonce is optional
            // and only present when emitted by a trusted shell integration
            // script. CWD updates without a matching nonce are treated as
            // untrusted to mitigate spoofing via OSC sequences injected
            // through arbitrary terminal output.
            final nonce = arg(1);
            _updateCwd(value, nonce != null && nonce == _nonce);
            return true;
          case 'IsWindows':
            createOrGetCommandDetection(terminal)
                .setIsWindowsPty(value == 'True');
            return true;
          case 'HasRichCommandDetection':
            createOrGetCommandDetection(terminal)
                .setHasRichCommandDetection(value == 'True');
            return true;
          case 'Prompt':
            // Remove escape sequences from the user's prompt
            final sanitizedValue = value.replaceAll(
              RegExp('\x1b\\[[0-9;]*m'),
              '',
            );
            _updatePromptTerminator(sanitizedValue);
            return true;
          case 'PromptType':
            createOrGetPromptTypeDetection().setPromptType(value);
            return true;
          case 'Task':
            createOrGetBufferMarkDetection(terminal);
            capabilities
                .get(TerminalCapability.commandDetection)
                ?.setIsCommandStorageDisabled();
            return true;
        }
        // Upstream's `case` has no `return` after its inner `switch`: an
        // unknown property falls through to SetMark and adds a mark.
        createOrGetBufferMarkDetection(terminal)
            .addMark(parseMarkSequence(args));
        return true;
      case _VSCodeOscPt.setMark:
        createOrGetBufferMarkDetection(terminal)
            .addMark(parseMarkSequence(args));
        return true;
    }

    // Unrecognized sequence
    return false;
  }

  void _updateContinuationPrompt(String value) {
    final terminal = _terminal;
    if (terminal == null) {
      return;
    }
    createOrGetCommandDetection(terminal).setContinuationPrompt(value);
  }

  void _updatePromptTerminator(String prompt) {
    final terminal = _terminal;
    if (terminal == null) {
      return;
    }
    final lastPromptLine = prompt.substring(prompt.lastIndexOf('\n') + 1);
    final lastPromptLineTrimmed = lastPromptLine.trim();
    final promptTerminator = lastPromptLineTrimmed.length == 1
        // The prompt line contains a single character, treat the full line
        // as the terminator for example "⮞ "
        ? lastPromptLine
        : lastPromptLine.substring(
            // JavaScript's `substring(-1)` is the whole string.
            lastPromptLine.lastIndexOf(' ').clamp(0, lastPromptLine.length),
          );
    if (promptTerminator.isNotEmpty) {
      createOrGetCommandDetection(terminal)
          .setPromptTerminator(promptTerminator, lastPromptLine);
    }
  }

  void _updateCwd(String value, [bool isTrusted = true]) {
    value = sanitizeCwd(value, isWindows: _isWindows);
    createOrGetCwdDetection().updateCwd(value, isTrusted);
    final commandDetection = capabilities.get(
      TerminalCapability.commandDetection,
    );
    commandDetection?.setCwd(value);
  }

  bool _doHandleITermSequence(String data) {
    final terminal = _terminal;
    if (terminal == null) {
      return false;
    }

    final command = data.split(';').first;
    _markSequenceSeen('${ShellIntegrationOscPs.iTerm};$command');
    // Upstream's SetMark `case` falls through to its `default`.
    if (command == _ITermOscPt.setMark) {
      createOrGetBufferMarkDetection(terminal).addMark();
    }
    // Checking for known `<key>=<value>` pairs. Note that unlike
    // `VSCodeOscPt.Property`, iTerm2 does not interpret backslash or
    // hex-escape sequences. See:
    // https://github.com/gnachman/iTerm2/blob/bb0882332cec5196e4de4a4225978d746e935279/sources/VT100Terminal.m#L2089-L2105
    final (:key, :value) = parseKeyValueAssignment(command);

    if (value == null) {
      // No '=' was found, so it's not a property assignment.
      return true;
    }

    switch (key) {
      case _ITermOscPt.currentDir:
        // Encountered: `OSC 1337 ; CurrentDir=<Cwd> ST`. The iTerm2 protocol
        // has no nonce, so cwd updates received this way are always
        // considered untrusted.
        _updateCwd(value, false);
        return true;
    }

    // Unrecognized sequence
    return false;
  }

  bool _doHandleSetWindowsFriendlyCwd(String data) {
    if (_terminal == null) {
      return false;
    }

    final [command, ...args] = data.split(';');
    _markSequenceSeen(
      '${ShellIntegrationOscPs.setWindowsFriendlyCwd};$command',
    );
    switch (command) {
      case '9':
        // Encountered `OSC 9 ; 9 ; <cwd> ST`. The ConEmu/Windows-friendly cwd
        // protocol has no nonce, so cwd updates received this way are always
        // considered untrusted.
        if (args.isNotEmpty) {
          _updateCwd(args[0], false);
        }
        return true;
    }

    // Unrecognized sequence
    return false;
  }

  /// Handles the sequence: `OSC 7 ; scheme://cwd ST`
  bool _doHandleSetCwd(String data) {
    if (_terminal == null) {
      return false;
    }

    final command = data.split(';').first;
    _markSequenceSeen('${ShellIntegrationOscPs.setCwd};$command');

    if (RegExp(r'^file://.*/').hasMatch(command)) {
      final path = uriPath(command);
      if (path.isNotEmpty) {
        // The `OSC 7 ; scheme://cwd ST` protocol has no nonce, so cwd
        // updates received this way are always considered untrusted.
        _updateCwd(path, false);
        return true;
      }
    }

    // Unrecognized sequence
    return false;
  }

  ISerializedCommandDetectionCapability serialize() {
    final terminal = _terminal;
    if (terminal == null ||
        !capabilities.has(TerminalCapability.commandDetection)) {
      return const ISerializedCommandDetectionCapability(
        isWindowsPty: false,
        hasRichCommandDetection: false,
        commands: [],
        promptInputModel: null,
      );
    }
    return createOrGetCommandDetection(terminal).serialize();
  }

  void deserialize(ISerializedCommandDetectionCapability serialized) {
    final terminal = _terminal;
    if (terminal == null) {
      throw StateError('Cannot restore commands before addon is activated');
    }
    final commandDetection = createOrGetCommandDetection(terminal);
    commandDetection.deserialize(serialized);
    final cwd = commandDetection.cwd;
    if (cwd != null && cwd.isNotEmpty) {
      // Cwd gets set when the command is deserialized, so we need to update
      // it here
      _updateCwd(cwd, false);
    }
  }

  ICwdDetectionCapability createOrGetCwdDetection() {
    final existing = capabilities.get(TerminalCapability.cwdDetection);
    if (existing != null) {
      return existing;
    }
    final cwdDetection = register(CwdDetectionCapability());
    capabilities.add(TerminalCapability.cwdDetection, cwdDetection);
    return cwdDetection;
  }

  ICommandDetectionCapability createOrGetCommandDetection(Terminal terminal) {
    final existing = capabilities.get(TerminalCapability.commandDetection);
    if (existing != null) {
      return existing;
    }
    final commandDetection = register(
      CommandDetectionCapability(terminal, _logService),
    );
    capabilities.add(TerminalCapability.commandDetection, commandDetection);
    return commandDetection;
  }

  IBufferMarkCapability createOrGetBufferMarkDetection(Terminal terminal) {
    final existing = capabilities.get(TerminalCapability.bufferMarkDetection);
    if (existing != null) {
      return existing;
    }
    final bufferMarkDetection = register(BufferMarkCapability(terminal));
    capabilities.add(
      TerminalCapability.bufferMarkDetection,
      bufferMarkDetection,
    );
    return bufferMarkDetection;
  }

  IShellEnvDetectionCapability createOrGetShellEnvDetection() {
    final existing = capabilities.get(TerminalCapability.shellEnvDetection);
    if (existing != null) {
      return existing;
    }
    final shellEnvDetection = register(ShellEnvDetectionCapability());
    capabilities.add(TerminalCapability.shellEnvDetection, shellEnvDetection);
    return shellEnvDetection;
  }

  IPromptTypeDetectionCapability createOrGetPromptTypeDetection() {
    final existing = capabilities.get(TerminalCapability.promptTypeDetection);
    if (existing != null) {
      return existing;
    }
    final promptTypeDetection = register(PromptTypeDetectionCapability());
    capabilities.add(
      TerminalCapability.promptTypeDetection,
      promptTypeDetection,
    );
    return promptTypeDetection;
  }
}

/// JavaScript's `parseInt(s)`, with NaN as null: the leading integer after
/// any whitespace.
int? _parseInt(String s) {
  final match = RegExp(r'^\s*([+-]?\d+)').firstMatch(s);
  return match == null ? null : int.tryParse(match[1]!);
}

String deserializeVSCodeOscMessage(String message) {
  return message.replaceAllMapped(
    // Backslash ('\') followed by an escape operator: either another '\', or
    // 'x' and two hex chars.
    RegExp(r'\\(\\|x([0-9a-f]{2}))', caseSensitive: false),
    // If it's a hex value, parse it to a character. Otherwise the operator is
    // '\', which we return literally, now unescaped.
    (m) =>
        m[2] != null ? String.fromCharCode(int.parse(m[2]!, radix: 16)) : m[1]!,
  );
}

String serializeVSCodeOscMessage(String message) {
  return message.replaceAllMapped(
    // Match backslash ('\'), semicolon (';'), or characters 0x20 and below
    RegExp('[\\\\;\x00-\x20]'),
    (m) {
      final char = m[0]!;
      // Escape backslash as '\\'
      if (char == '\\') {
        return r'\\';
      }
      // Escape other characters as '\xAB' where AB is the hex representation
      final charCode = char.codeUnitAt(0);
      return '\\x${charCode.toRadixString(16).padLeft(2, '0')}';
    },
  );
}

({String key, String? value}) parseKeyValueAssignment(String message) {
  final separatorIndex = message.indexOf('=');
  if (separatorIndex == -1) {
    return (key: message, value: null); // No '=' was found.
  }
  return (
    key: message.substring(0, separatorIndex),
    value: message.substring(1 + separatorIndex),
  );
}

IMarkProperties parseMarkSequence(List<String?> sequence) {
  String? id;
  var hidden = false;
  for (final property in sequence) {
    // Sanity check, this shouldn't happen in practice
    if (property == null) {
      continue;
    }
    if (property == 'Hidden') {
      hidden = true;
    }
    if (property.startsWith('Id=')) {
      id = property.substring(3);
    }
  }
  return IMarkProperties(id: id, hidden: hidden);
}

/// Upstream `sanitizeCwd`; [isWindows] is upstream's `OS ===
/// OperatingSystem.Windows`.
String sanitizeCwd(String cwd, {bool isWindows = false}) {
  // Sanity check that the cwd is not wrapped in quotes (see #160109)
  if (RegExp('^[\'"].*[\'"]\$').hasMatch(cwd)) {
    cwd = cwd.substring(1, cwd.length - 1);
  }
  // Make the drive letter uppercase on Windows (see #9448)
  if (isWindows && cwd.length > 1 && cwd[1] == ':') {
    return cwd[0].toUpperCase() + cwd.substring(1);
  }
  return cwd;
}

final _controlSequences = RegExp(
  [
    // CSI_SEQUENCE
    '(?:\x1b\\[|\x9b)[=?>!]?[\\d;:]*["\$#\'* ]?[a-zA-Z@^`{}|~]',
    // OSC_SEQUENCE
    '(?:\x1b\\]|\x9d).*?(?:\x1b\\\\|\x07|\x9c)',
    // ESC_SEQUENCE
    '\x1b(?:[ #%\\(\\)\\*\\+\\-\\.\\/]?[a-zA-Z0-9\\|}~@])',
  ].join('|'),
);

/// Upstream `removeAnsiEscapeCodes`.
String removeAnsiEscapeCodes(String str) {
  return str.replaceAll(_controlSequences, '');
}

/// Strips ANSI escape sequences from a UNIX-style prompt string (eg.
/// `$PS1`), and the `\[`…`\]` that wrap its non-printing parts.
String removeAnsiEscapeCodesFromPrompt(String str) {
  return removeAnsiEscapeCodes(str).replaceAll(RegExp(r'\\\[.*?\\\]'), '');
}

/// The path of [uri] as VS Code's `URI.parse(uri).path`: after the
/// authority, before any query or fragment, percent-decoded (malformed
/// escapes are kept as they are); `/` when empty for a `file` URI.
String uriPath(String uri) {
  final match = RegExp(
    r'^(([^:/?#]+?):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?',
  ).firstMatch(uri)!;
  final scheme = match[2] ?? '';
  var path = _percentDecode(match[5] ?? '');
  // Upstream `_referenceResolution`.
  if (scheme == 'https' || scheme == 'http' || scheme == 'file') {
    if (path.isEmpty) {
      path = '/';
    } else if (!path.startsWith('/')) {
      path = '/$path';
    }
  }
  return path;
}

String _percentDecode(String str) {
  return str.replaceAllMapped(
    RegExp('(%[0-9A-Za-z][0-9A-Za-z])+'),
    (m) => _decodeUriComponentGraceful(m[0]!),
  );
}

String _decodeUriComponentGraceful(String str) {
  try {
    return Uri.decodeComponent(str);
  } catch (_) {
    if (str.length > 3) {
      return str.substring(0, 3) +
          _decodeUriComponentGraceful(str.substring(3));
    }
    return str;
  }
}
