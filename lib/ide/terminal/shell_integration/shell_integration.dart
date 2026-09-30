/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A terminal's shell integration, as a TerminalInstance holds it: VS Code's
// shell integration addon and decoration addon on the terminal's emulator,
// with the commands, cwd and decorations they find.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts (the
// addons loaded on the terminal, `shellIntegration`), with the session
// history of src/vs/workbench/contrib/terminalContrib/history/browser/
// terminalRunRecentQuickPick.ts ([ShellIntegration.recentCommands]).

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../xterm/common/event.dart';
import '../xterm/common/lifecycle.dart';
import '../xterm/common/services/decoration_service.dart';
import '../xterm/common/services/services.dart';
import '../xterm/headless/terminal.dart';
import 'capabilities/capabilities.dart';
import 'decoration_addon.dart';
import 'shell_integration_addon.dart';
import 'shell_integration_injection.dart' show generateShellIntegrationNonce;

class ShellIntegration extends Disposable {
  /// Reads [terminal]'s output for shell integration from now on.
  ///
  /// [nonce] is the terminal's `VSCODE_NONCE` (`shellIntegrationNonce` of
  /// its launch): only command lines and cwds that come with it are
  /// trusted. Without one (no shell integration was injected), a random one
  /// no shell knows is used, as VS Code makes one for every terminal: then
  /// nothing is trusted. The decorations' overview ruler marks go to
  /// [decorationService], the one the terminal's view draws; one of its own
  /// otherwise. [isWindows] (whether the app runs on Windows, by default
  /// from Flutter) uppercases cwds' drive letters. [onDidExecuteText] fires
  /// when the app sends a command to run, for the partial command detection.
  ShellIntegration(
    this.terminal, {
    String nonce = '',
    IDecorationService? decorationService,
    bool? isWindows,
    IEvent<void>? onDidExecuteText,
    bool showGutterDecorations = true,
    bool showOverviewRulerDecorations = true,
  }) {
    addon = register(
      ShellIntegrationAddon(
        nonce.isEmpty ? generateShellIntegrationNonce() : nonce,
        onDidExecuteText,
        terminal.logService,
        isWindows: isWindows ?? defaultTargetPlatform == TargetPlatform.windows,
      ),
    );
    addon.activate(terminal);
    decorationAddon = register(
      DecorationAddon(
        addon.capabilities,
        decorationService ??
            register(
              DecorationService(terminal.logService, terminal.bufferService),
            ),
        showGutterDecorations: showGutterDecorations,
        showOverviewRulerDecorations: showOverviewRulerDecorations,
      ),
    );
    decorationAddon.activate(terminal);

    // The capabilities come with their first sequence: forward their events
    // from then on.
    final commandDetection = MutableDisposable<DisposableStore>();
    register(commandDetection);
    void attachCommandDetection(ICommandDetectionCapability capability) {
      commandDetection.value = DisposableStore()
        ..add(capability.onCommandStarted(_onCommandStarted.fire))
        ..add(capability.onCommandFinished(_onCommandFinished.fire));
    }

    register(
      capabilities.onDidAddCommandDetectionCapability(attachCommandDetection),
    );
    register(
      capabilities.onDidRemoveCommandDetectionCapability(
        (_) => commandDetection.clear(),
      ),
    );
    final cwdDetection = MutableDisposable<IDisposable>();
    register(cwdDetection);
    register(
      capabilities.onDidAddCwdDetectionCapability((capability) {
        cwdDetection.value = capability.onDidChangeCwd(_onDidChangeCwd.fire);
      }),
    );
    register(
      capabilities.onDidRemoveCwdDetectionCapability(
        (_) => cwdDetection.clear(),
      ),
    );
  }

  /// The emulator it reads.
  final Terminal terminal;

  late final ShellIntegrationAddon addon;
  late final DecorationAddon decorationAddon;

  late final _onCommandStarted = register(Emitter<ITerminalCommand>());
  late final _onCommandFinished = register(Emitter<ITerminalCommand>());
  late final _onDidChangeCwd = register(Emitter<String>());

  /// What the terminal is known to do, as VS Code's
  /// `TerminalInstance.capabilities`.
  ITerminalCapabilityStore get capabilities => addon.capabilities;

  /// Which shell integration has been seen: none, FinalTerm's (OSC 133) or
  /// VS Code's (OSC 633).
  ShellIntegrationStatus get status => addon.status;
  IEvent<ShellIntegrationStatus> get onDidChangeStatus =>
      addon.onDidChangeStatus;

  /// Null until the shell's first prompt or command sequence.
  ICommandDetectionCapability? get commandDetection =>
      capabilities.get(TerminalCapability.commandDetection);

  /// The finished commands, oldest first; each with its [ITerminalCommand.
  /// marker] (the line its command line starts on: `marker.line` is a
  /// buffer line), `exitCode` (null when none was reported, as on ctrl+c),
  /// `command`, `cwd`, `timestamp` and `duration`.
  List<ITerminalCommand> get commands => commandDetection?.commands ?? const [];

  /// Fired when the shell starts reading a command line (its prompt is
  /// done): a command with only its `marker`.
  late final IEvent<ITerminalCommand> onCommandStarted =
      _onCommandStarted.event;

  /// Fired when a command finishes, with it (also in [commands]).
  late final IEvent<ITerminalCommand> onCommandFinished =
      _onCommandFinished.event;

  /// The shell's working folder, once it reports one.
  String? get cwd {
    final cwd = capabilities.get(TerminalCapability.cwdDetection)?.getCwd();
    return cwd == null || cwd.isEmpty ? null : cwd;
  }

  /// The working folders seen, least recently first.
  List<String> get cwds =>
      capabilities.get(TerminalCapability.cwdDetection)?.cwds ?? const [];

  /// Fired with each new working folder.
  late final IEvent<String> onDidChangeCwd = _onDidChangeCwd.event;

  /// The gutter decorations to paint (see [TerminalCommandDecoration]).
  Iterable<TerminalCommandDecoration> get decorations =>
      decorationAddon.decorations;

  /// Fired when [decorations] change.
  IEvent<void> get onDidChangeDecorations =>
      decorationAddon.onDidChangeDecorations;

  /// The session's commands for "Run Recent Command", newest first: one per
  /// command line (trimmed, not empty), after the one running if any
  /// ([ICommandDetectionCapability.executingCommand] is not listed).
  List<ITerminalCommand> get recentCommands {
    final commandDetection = this.commandDetection;
    if (commandDetection == null) {
      return const [];
    }
    final seen = <String>{};
    final executingCommand = commandDetection.executingCommand;
    if (executingCommand != null && executingCommand.isNotEmpty) {
      seen.add(executingCommand);
    }
    final commands = commandDetection.commands;
    return [
      for (var i = commands.length - 1; i >= 0; i--)
        if (commands[i].command.trim() case final label
            when label.isNotEmpty && seen.add(label))
          commands[i],
    ];
  }
}
