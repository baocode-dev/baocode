/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What a terminal knows beyond its screen, mostly from shell integration:
// the commands, the working folder, marks. Each capability is added to the
// terminal's TerminalCapabilityStore once its sequences first arrive.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/capabilities.ts, with
// `ITerminalOutputMatcher` and `ITerminalOutputMatch` from
// src/vs/platform/terminal/common/terminal.ts.
//
// `TerminalCapability` is a generic enum, so that the store's `get` is typed
// as upstream's `ITerminalCapabilityImplMap` makes it. The xterm types are
// the ported core's: markers are the internal `IMarker`.

import 'package:bao_xterm/common/buffer/types.dart' show IMarker;
import 'package:bao_xterm/common/event.dart';

import 'command_detection/prompt_input_model.dart';
import 'command_detection/terminal_command.dart';

/// Primarily driven by the shell integration feature, a terminal capability
/// is the mechanism for progressively enhancing various features that may
/// not be supported in all terminals/shells. [T] is the implementation's
/// interface (upstream `ITerminalCapabilityImplMap`).
enum TerminalCapability<T extends Object> {
  /// The terminal can reliably detect the current working directory as soon
  /// as the change happens within the buffer.
  cwdDetection<ICwdDetectionCapability>(),

  /// The terminal can reliably detect the current working directory when
  /// requested.
  naiveCwdDetection<INaiveCwdDetectionCapability>(),

  /// The terminal can reliably identify prompts, commands and command outputs
  /// within the buffer.
  commandDetection<ICommandDetectionCapability>(),

  /// The terminal can often identify prompts, commands and command outputs
  /// within the buffer. It may not be so good at remembering the position of
  /// commands that ran in the past. This state may be enabled when something
  /// goes wrong or when using conpty for example.
  partialCommandDetection<IPartialCommandDetectionCapability>(),

  /// Manages buffer marks that can be used for terminal navigation. The
  /// source of the request (task, debug, etc) provides an ID, optional
  /// marker, hoverMessage, and hidden property. When hidden is not provided,
  /// a generic decoration is added to the buffer and overview ruler.
  bufferMarkDetection<IBufferMarkCapability>(),

  /// The terminal can detect the latest environment of user's current shell.
  shellEnvDetection<IShellEnvDetectionCapability>(),

  /// The terminal can detect the prompt type being used (e.g., p10k,
  /// posh-git).
  promptTypeDetection<IPromptTypeDetectionCapability>();

  const TerminalCapability();
}

/// An object that keeps track of additional capabilities and their
/// implementations for features that are not available for all terminals.
abstract interface class ITerminalCapabilityStore {
  /// An iterable of all capabilities in the store.
  Iterable<TerminalCapability> get items;

  /// Fired when a capability is added.
  IEvent<TerminalCapabilityChangeEvent> get onDidAddCapability;

  /// Fired when a capability is removed.
  IEvent<TerminalCapabilityChangeEvent> get onDidRemoveCapability;

  /// Fired when a capability if added or removed.
  IEvent<void> get onDidChangeCapabilities;

  /// Fired when the command detection capability is added.
  IEvent<ICommandDetectionCapability> get onDidAddCommandDetectionCapability;

  /// Fired when the command detection capability is removed.
  IEvent<void> get onDidRemoveCommandDetectionCapability;

  /// Fired when the cwd detection capability is added.
  IEvent<ICwdDetectionCapability> get onDidAddCwdDetectionCapability;

  /// Fired when the cwd detection capability is removed.
  IEvent<void> get onDidRemoveCwdDetectionCapability;

  /// Create an event that's fired when a specific capability type is added.
  /// Use this over [onDidAddCapability] when the generic type needs to be
  /// retained.
  IEvent<T> createOnDidAddCapabilityOfTypeEvent<T extends Object>(
    TerminalCapability<T> type,
  );

  /// Create an event that's fired when a specific capability type is
  /// removed. Use this over [onDidRemoveCapability] when the generic type
  /// needs to be retained.
  IEvent<T> createOnDidRemoveCapabilityOfTypeEvent<T extends Object>(
    TerminalCapability<T> type,
  );

  /// Gets whether the capability exists in the store.
  bool has(TerminalCapability capability);

  /// Gets the implementation of a capability if it has been added to the
  /// store.
  T? get<T extends Object>(TerminalCapability<T> capability);
}

/// Upstream `TerminalCapabilityChangeEvent` (and
/// `AnyTerminalCapabilityChangeEvent`).
class TerminalCapabilityChangeEvent {
  const TerminalCapabilityChangeEvent(this.id, this.capability);

  final TerminalCapability id;
  final Object capability;
}

abstract interface class ICwdDetectionCapability {
  TerminalCapability<ICwdDetectionCapability> get type;
  IEvent<String> get onDidChangeCwd;
  List<String> get cwds;

  /// Whether the current cwd came from a trusted source. This is `true` only
  /// when the cwd was reported by the VS Code shell integration with a valid
  /// nonce. OSC 7, OSC 9;9 and OSC 1337 cwd updates are always considered
  /// untrusted because their protocols have no nonce.
  bool get isTrusted;
  String getCwd();
  void updateCwd(String cwd, [bool isTrusted = true]);
}

abstract interface class IShellEnvDetectionCapability {
  TerminalCapability<IShellEnvDetectionCapability> get type;
  IEvent<TerminalShellIntegrationEnvironment> get onDidChangeEnv;
  TerminalShellIntegrationEnvironment get env;
  void setEnvironment(Map<String, String?> envs, bool isTrusted);
  void startEnvironmentSingleVar(bool clear, bool isTrusted);
  void setEnvironmentSingleVar(String key, String? value, bool isTrusted);
  void deleteEnvironmentSingleVar(String key, String? value, bool isTrusted);
  void endEnvironmentSingleVar(bool isTrusted);
}

abstract interface class IPromptTypeDetectionCapability {
  TerminalCapability<IPromptTypeDetectionCapability> get type;
  String? get promptType;
  IEvent<String?> get onPromptTypeChanged;
  void setPromptType(String value);
}

class TerminalShellIntegrationEnvironment {
  const TerminalShellIntegrationEnvironment({
    required this.value,
    required this.isTrusted,
  });

  /// The dictionary of environment variables.
  final Map<String, String?>? value;

  /// Whether the environment came from a trusted source and is therefore
  /// safe to use its values in a manner that could lead to execution of
  /// arbitrary code. If this value is `false`, [value] should either not be
  /// used for something that could lead to arbitrary code execution, or the
  /// user should be warned beforehand.
  ///
  /// This is `true` only when the environment was reported explicitly and it
  /// used a nonce for verification.
  final bool isTrusted;
}

enum CommandInvalidationReason { windows, noProblemsReported }

class ICommandInvalidationRequest {
  const ICommandInvalidationRequest({required this.reason});

  final CommandInvalidationReason reason;
}

abstract interface class IBufferMarkCapability {
  TerminalCapability<IBufferMarkCapability> get type;
  Iterable<IMarker> markers();
  IEvent<IMarkProperties> get onMarkAdded;
  void addMark([IMarkProperties? properties]);
  IMarker? getMark(String id);
}

abstract interface class ICommandDetectionCapability {
  TerminalCapability<ICommandDetectionCapability> get type;
  IPromptInputModel get promptInputModel;
  List<ITerminalCommand> get commands;

  /// The command currently being executed, otherwise null.
  String? get executingCommand;
  ITerminalCommand? get executingCommandObject;

  /// `'low'`, `'medium'` or `'high'`.
  String? get executingCommandConfidence;

  /// The current cwd at the cursor's position.
  String? get cwd;
  bool get hasRichCommandDetection;
  ICurrentPartialCommand? get currentCommand;
  IEvent<ITerminalCommand> get onCommandStarted;
  IEvent<ITerminalCommand> get onCommandFinished;

  /// Fired with the current [PartialTerminalCommand] (upstream types it
  /// `ITerminalCommand` and casts).
  IEvent<PartialTerminalCommand> get onCommandExecuted;
  IEvent<List<ITerminalCommand>> get onCommandInvalidated;
  IEvent<ICommandInvalidationRequest> get onCurrentCommandInvalidated;
  IEvent<bool> get onSetRichCommandDetection;
  void setContinuationPrompt(String value);
  void setPromptTerminator(String value, String lastPromptLine);
  void setCwd(String value);
  void setIsWindowsPty(bool value);
  void setIsCommandStorageDisabled();

  /// Gets the working directory for a line, this will return null if it's
  /// unknown in which case the terminal's initial cwd should be used.
  String? getCwdForLine(int line);

  /// An [ITerminalCommand] or an [ICurrentPartialCommand].
  Object? getCommandForLine(int line);
  void handlePromptStart([IHandleCommandOptions? options]);
  void handleContinuationStart();
  void handleContinuationEnd();
  void handleRightPromptStart();
  void handleRightPromptEnd();
  void handleCommandStart([IHandleCommandOptions? options]);
  void handleCommandExecuted([IHandleCommandOptions? options]);
  void handleCommandFinished(int? exitCode, [IHandleCommandOptions? options]);
  void setHasRichCommandDetection(bool value);

  /// Set the command line explicitly.
  ///
  /// [isTrusted] says whether the command line is trusted via the optional
  /// nonce is send in order to prevent spoofing. This is important as some
  /// interactions do not require verification before re-running a command.
  /// Note that this is optional according to the spec, it should always be
  /// present when running the _builtin_ SI scripts.
  void setCommandLine(String commandLine, bool isTrusted);

  /// Sets the command ID to use for the next command that starts. This
  /// allows pre-assigning an ID before the shell sends the command start
  /// sequence, which is useful for linking commands across renderer and
  /// ptyHost.
  void setNextCommandId(String command, String commandId);
  ISerializedCommandDetectionCapability serialize();
  void deserialize(ISerializedCommandDetectionCapability serialized);
}

class IHandleCommandOptions {
  const IHandleCommandOptions({
    this.ignoreCommandLine,
    this.marker,
    this.markProperties,
  });

  /// Whether to allow an empty command to be registered. This should be used
  /// to support certain shell integration scripts/features where tracking
  /// the command line may not be possible.
  final bool? ignoreCommandLine;

  /// The marker to use
  final IMarker? marker;

  /// Properties for the mark
  final IMarkProperties? markProperties;
}

abstract interface class INaiveCwdDetectionCapability {
  TerminalCapability<INaiveCwdDetectionCapability> get type;
  IEvent<String> get onDidChangeCwd;
  Future<String> getCwd();
}

abstract interface class IPartialCommandDetectionCapability {
  TerminalCapability<IPartialCommandDetectionCapability> get type;
  List<IMarker> get commands;
  IEvent<IMarker> get onCommandFinished;
}

/// Upstream `IBaseTerminalCommand`: what a command and its serialized form
/// share.
abstract interface class IBaseTerminalCommand {
  // Mandatory
  String get command;

  /// `'low'`, `'medium'` or `'high'`.
  String get commandLineConfidence;
  bool get isTrusted;

  /// Milliseconds since the epoch.
  int get timestamp;

  /// Milliseconds.
  int get duration;
  String? get id;

  // Optional serializable
  String? get cwd;
  int? get exitCode;
  String? get commandStartLineContent;
  IMarkProperties? get markProperties;
  int? get executedX;
  int? get startX;
}

abstract interface class ITerminalCommand implements IBaseTerminalCommand {
  // Optional non-serializable
  IMarker? get promptStartMarker;
  IMarker? get marker;
  abstract IMarker? endMarker;
  IMarker? get executedMarker;
  List<List<String>>? get aliases;
  bool? get wasReplayed;

  String extractCommandLine();
  String? getOutput();
  ITerminalOutputMatch? getOutputMatch(ITerminalOutputMatcher outputMatcher);
  bool hasOutput();
  int getPromptRowCount();
  int getCommandRowCount();
}

class ISerializedTerminalCommand implements IBaseTerminalCommand {
  const ISerializedTerminalCommand({
    required this.command,
    required this.commandLineConfidence,
    required this.isTrusted,
    required this.timestamp,
    required this.duration,
    required this.id,
    required this.cwd,
    required this.exitCode,
    required this.commandStartLineContent,
    required this.markProperties,
    required this.executedX,
    required this.startX,
    required this.startLine,
    required this.promptStartLine,
    required this.endLine,
    required this.executedLine,
  });

  @override
  final String command;
  @override
  final String commandLineConfidence;
  @override
  final bool isTrusted;
  @override
  final int timestamp;
  @override
  final int duration;
  @override
  final String? id;
  @override
  final String? cwd;
  @override
  final int? exitCode;
  @override
  final String? commandStartLineContent;
  @override
  final IMarkProperties? markProperties;
  @override
  final int? executedX;
  @override
  final int? startX;

  // Optional non-serializable converted for serialization
  final int? startLine;
  final int? promptStartLine;
  final int? endLine;
  final int? executedLine;
}

class IMarkProperties {
  const IMarkProperties({
    this.hoverMessage,
    this.disableCommandStorage,
    this.hidden,
    this.marker,
    this.id,
  });

  final String? hoverMessage;
  final bool? disableCommandStorage;
  final bool? hidden;
  final IMarker? marker;
  final String? id;
}

class ISerializedCommandDetectionCapability {
  const ISerializedCommandDetectionCapability({
    required this.isWindowsPty,
    required this.hasRichCommandDetection,
    required this.commands,
    required this.promptInputModel,
  });

  final bool isWindowsPty;
  final bool hasRichCommandDetection;
  final List<ISerializedTerminalCommand> commands;
  final ISerializedPromptInputModel? promptInputModel;
}

/// What to look for in a command's output (upstream in terminal.ts).
class ITerminalOutputMatcher {
  const ITerminalOutputMatcher({
    required this.lineMatcher,
    this.anchor = 'top',
    this.offset = 0,
    this.length = 0,
    this.multipleMatches,
  });

  /// A string (a regular expression's source, as JavaScript's `match`
  /// takes it) or a [RegExp] to match against the unwrapped line. If this is
  /// a regex with the multiline flag, it will scan an amount of lines equal
  /// to `\n` instances in the regex + 1.
  final Pattern lineMatcher;

  /// Which side of the output to anchor the [offset] and [length] against:
  /// `'top'` or `'bottom'`.
  final String anchor;

  /// The number of rows above or below the [anchor] to start matching
  /// against.
  final int offset;

  /// The number of rows to match against, this should be as small as
  /// possible for performance reasons. This is capped at 40.
  final int length;

  /// If multiple matches are expected - this will result in `outputLines`
  /// being returned when there's a `regexMatch` from [offset] to [length].
  final bool? multipleMatches;
}

class ITerminalOutputMatch {
  const ITerminalOutputMatch({
    required this.regexMatch,
    required this.outputLines,
  });

  final RegExpMatch regexMatch;
  final List<String> outputLines;
}
