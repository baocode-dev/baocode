/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A terminal of the panel, as VS Code's TerminalInstance: it starts the
// user's shell on a pseudo terminal, is named after the process (or what the
// user renamed it to), and keeps what the process's exit left.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/terminalInstance.ts
// (`_onProcessExit`, `parseExitResult`, `rename`), terminalProcessManager.ts
// (input queued until the process is there) and
// src/vs/platform/terminal/common/terminalStrings.ts
// (`formatMessageForTerminal`).
//
// It owns its emulator, as VS Code's instance owns its xterm: what the
// process prints is parsed into [TerminalInstance.terminal] here, so that
// terminals in the background keep their screens, and so are the keyboard,
// mouse and selection, which the view drives while it shows. It follows the
// workbench's colors ([terminalColorTheme]) as VS Code's XtermTerminal
// follows `onDidColorThemeChange` (xtermTerminal.ts `_updateTheme`), and
// its find as the find widget does (terminalFindWidget.ts).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../settings/user_settings.dart';
import '../../theme/code_font.dart';
import 'pty.dart';
import 'shell_integration/shell_integration.dart';
import 'shell_integration/shell_integration_injection.dart';
import 'terminal_clipboard.dart';
import 'terminal_keyboard.dart';
import 'terminal_mouse.dart';
import 'terminal_render_adapter.dart';
import 'terminal_render_theme.dart';
import 'terminal_selection.dart';
import 'links/terminal_link_resolver.dart';
import 'links/terminal_links.dart';
import 'terminal_colors.dart';
import 'terminal_find.dart';
import 'terminal_profiles.dart';
import 'terminal_shell.dart';
import 'terminal_xterm.dart';

import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/common/platform.dart';
import 'package:bao_xterm/common/services/decoration_service.dart';
import 'package:bao_xterm/headless/terminal.dart' as internal;

/// What a new terminal runs in [root]: [terminalLaunch] in the app;
/// [shell] when a profile names it, else the user's shell; in the
/// environment [environment] asks for.
typedef TerminalLauncher = Future<PtyLaunch> Function(
  String root, {
  int columns,
  int rows,
  TerminalShell? shell,
  TerminalEnvironmentRequest? environment,
});

/// Why a terminal closed, as VS Code's `TerminalExitReason` (its values
/// are the wire's).
enum TerminalExitReason { unknown, shutdown, process, user, extension }

/// What an extension asks of a terminal it makes (VS Code's
/// `IShellLaunchConfig`, from `vscode.window.createTerminal`'s options and
/// tasks'); a terminal of the user's has none.
class TerminalLaunchConfig {
  const TerminalLaunchConfig({
    this.name,
    this.executable,
    this.arguments,
    this.cwd,
    this.env,
    this.strictEnv = false,
    this.hideFromUser = false,
    this.isTransient = false,
    this.initialText,
    this.initialTextNewLine = true,
    this.waitOnExit,
    this.extHostTerminalId,
    this.isFeatureTerminal = false,
    this.isExtensionOwnedTerminal = false,
    this.forceShellIntegration = false,
    this.titleTemplate,
    this.type,
    this.customPty,
    this.shellIntegrationNonce,
  });

  /// Its fixed name, instead of its process's.
  final String? name;

  /// The shell to run, with [arguments]; the default profile's when null.
  final String? executable;
  final List<String>? arguments;

  /// Where it starts; the workspace's folder when null.
  final String? cwd;

  /// Over the environment (a null value removes the variable), or instead
  /// of it when [strictEnv].
  final Map<String, String?>? env;
  final bool strictEnv;

  /// Not in the panel's tabs until shown (`hideFromUser`).
  final bool hideFromUser;

  /// Not kept across restarts (`isTransient`): none are here.
  final bool isTransient;

  /// Written to it before the process prints, then a new line unless
  /// [initialTextNewLine] is false (`trailingNewLine`).
  final String? initialText;
  final bool initialTextNewLine;

  /// Kept after its process exits until a key is pressed, with the message
  /// this gives for the exit code (`waitOnExit`); closed at once when null.
  final String? Function(int? exitCode)? waitOnExit;

  /// The extension host's id of a terminal it made (`extHostTerminalId`).
  final String? extHostTerminalId;
  final bool isFeatureTerminal;
  final bool isExtensionOwnedTerminal;
  final bool forceShellIntegration;
  final String? titleTemplate;

  /// `'Task'` for a task's terminal.
  final String? type;

  /// A Pseudoterminal: what stands for its process, given the terminal
  /// (`customPtyImplementation`); [executable] and [env] do not apply.
  final Future<Pty> Function(TerminalInstance instance)? customPty;

  /// The nonce its shell integration trusts command lines with
  /// (`shellIntegrationNonce`), when not the launch's own: a task's, whose
  /// initial text reports the command line.
  final String? shellIntegrationNonce;
}

/// The terminal profiles there are, [configured] (the user's
/// `terminal.integrated.profiles.<os>`) over VS Code's defaults:
/// [terminalProfiles] in the app.
typedef TerminalProfileDetector = Future<TerminalProfiles> Function({
  Object? configured,
});

/// Where terminals' processes come from, as VS Code's terminal backend:
/// [launch] says what a new terminal runs and [start] runs it on a pseudo
/// terminal; [linkStat] says what is at the paths links name. Widget tests
/// give fakes, never a real shell or disk.
class TerminalBackend {
  const TerminalBackend({
    this.launch = terminalLaunch,
    this.start = startPty,
    this.detectProfiles = terminalProfiles,
    this.settings,
    this.linkStat,
    this._supported,
  });

  final TerminalLauncher launch;
  final PtyStarter start;

  /// Lists the shells a terminal can start, when the profiles are asked
  /// for (a dropdown opened), not before: the app's reads the disk.
  final TerminalProfileDetector detectProfiles;

  /// settings.json, with the default profile and the user's profiles
  /// (`terminal.integrated.defaultProfile.<os>`, `.profiles.<os>`); none:
  /// the user's shell, VS Code's default profiles, and no default to set.
  final UserSettings? settings;

  /// Null checks the disk ([TerminalFileLinkResolver]'s default).
  final TerminalLinkStat? linkStat;
  final bool? _supported;

  /// Whether terminals run here ([ptySupported]): not on the web.
  bool get supported => _supported ?? ptySupported;
}

class TerminalInstance extends ChangeNotifier {
  /// Starts the process at once, [columns] by [rows] until the view says.
  TerminalInstance({
    required this.id,
    required this.root,
    this.backend = const TerminalBackend(),
    this._columns = 80,
    this._rows = 24,
    this.onExit,
    this.shell,
    this._config,
    this.environmentMutator,
  }) {
    _initPlatform();
    xterm = TerminalXterm(
      vscodeTerminalOptions(
        cols: _columns,
        rows: _rows,
        theme: terminalColorTheme.value,
      ),
    );
    terminalColorTheme.addListener(_updateTheme);
    CodeFont.families.addListener(_updateFont);
    source = TerminalCoreSource(terminal, decorationService: decorations);
    clipboard = TerminalClipboard(
      selection: selection,
      coreService: terminal.coreService,
      optionsService: terminal.optionsService,
    );
    mouse = TerminalMouse(
      bufferService: terminal.bufferService,
      coreService: terminal.coreService,
      mouseStateService: terminal.mouseStateService,
      optionsService: terminal.optionsService,
      selection: selection,
      clipboard: clipboard,
    );
    keyboard = TerminalKeyboard(
      bufferService: terminal.bufferService,
      coreService: terminal.coreService,
      optionsService: terminal.optionsService,
      selection: selection,
      clipboard: clipboard,
    );
    keyboard.onKey((_) => showCursor());
    // What the keyboard, the mouse and the app's replies send.
    terminal.onData((data) {
      writeText(data);
      _onInput.add(data);
    });
    terminal.onBinary((data) {
      write(latin1.encode(data));
      _onInput.add(data);
    });
    _writeInitialText();
    // Lines as they end, for tasks' problem matchers.
    terminal.onLineFeed((_) {
      if (!_onLineData.hasListener || _ownTextPending > 0) return;
      final buffer = terminal.buffer;
      final index = buffer.ybase + buffer.y;
      final newLine = buffer.lines.get(index);
      if (newLine != null && !newLine.isWrapped) _sendLineData(index - 1);
    });
    unawaited(_start());
  }

  /// Its initial text and exit messages are no lines of output
  /// (upstream's `LineDataEventAddon` starts once the initial text is
  /// written, and a task stops listening when the process exits): writes
  /// of them not yet parsed.
  int _ownTextPending = 0;

  void _writeOwnText(String text) {
    // Counted from when what was written before it is parsed.
    terminal
      ..write('', () => _ownTextPending++)
      ..write(text, () => _ownTextPending--);
  }

  void _writeInitialText() {
    final config = _config;
    if (config?.initialText case final text?) {
      _writeOwnText(config!.initialTextNewLine ? '$text\r\n' : text);
    }
  }

  /// VS Code's `LineDataEventAddon._sendLineData`: the line at [index] with
  /// the lines it wraps from.
  void _sendLineData(int index) {
    final lines = terminal.buffer.lines;
    var line = index < 0 ? null : lines.get(index);
    if (line == null) return;
    var data = line.translateToString(true);
    while (index > 0 && line!.isWrapped) {
      line = lines.get(--index);
      if (line == null) break;
      data = line.translateToString(false) + data;
    }
    _onLineData.add(data);
  }

  final _onLineData = StreamController<String>.broadcast(sync: true);

  /// Each line of output once it ends, wrapped lines joined (VS Code's
  /// `onLineData`).
  Stream<String> get onLineData => _onLineData.stream;

  final _onProcessReady = StreamController<int>.broadcast(sync: true);

  /// Its process's id, once it has started (`processReady`); again when
  /// it is [reuse]d.
  Stream<int> get onProcessReady => _onProcessReady.stream;

  final _onProcessExit = StreamController<int?>.broadcast(sync: true);

  /// Its process's exit code once it exited, or null when it failed to
  /// launch (VS Code's `onExit`), before the terminal service is told.
  Stream<int?> get onProcessExit => _onProcessExit.stream;

  /// VS Code's `reuseTerminal`: a new process in this terminal, as
  /// [config] says, after the last one exited (a task's terminal, shared
  /// by tasks). What it printed stays.
  void reuse(TerminalLaunchConfig config) {
    if (_disposed) return;
    if (!_exited) {
      exitReason = null;
      _pty?.kill();
    }
    unawaited(_printing?.cancel());
    _printing = null;
    _config = config;
    _exited = false;
    _exitCode = null;
    _exitMessage = null;
    _waitingForKey = false;
    exitReason = null;
    _launch = null;
    _pty = null;
    _typedAhead.clear();
    _shellIntegration?.dispose();
    _shellIntegration = null;
    _generation++;
    _writeInitialText();
    notifyListeners();
    unawaited(_start());
  }

  /// Which process is the current one: a [reuse]d terminal's old process
  /// tells nothing.
  int _generation = 0;

  /// Empties the scrollback and the screen (`clearBuffer`).
  void clearBuffer() => terminal.clear();

  /// xterm.js reads the platform from the browser; here, from Flutter's.
  static void _initPlatform() {
    if (_platformSet) return;
    _platformSet = true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS || TargetPlatform.iOS:
        initPlatform(userAgent: 'Macintosh', platform: 'MacIntel');
      case TargetPlatform.windows:
        initPlatform(userAgent: 'Windows', platform: 'Win32');
      case TargetPlatform.linux ||
          TargetPlatform.android ||
          TargetPlatform.fuchsia:
        initPlatform(userAgent: 'Linux', platform: 'Linux x86_64');
    }
  }

  static bool _platformSet = false;

  /// Its number, from 1 up, as VS Code's `instanceId`.
  final int id;

  /// The folder it starts in, unless [config] says another.
  final String root;

  /// What an extension asked of it; null for the user's.
  TerminalLaunchConfig? get config => _config;
  TerminalLaunchConfig? _config;

  /// The extensions' environment variable collections, applied to the
  /// environment of a terminal whose [config] is not strict.
  final void Function(Map<String, String> environment)? environmentMutator;

  final _onInput = StreamController<String>.broadcast(sync: true);

  /// What the user typed into it, and what [sendText] sent: VS Code's
  /// `onDidInputData`.
  Stream<String> get onInput => _onInput.stream;

  /// Why it closed, once it has.
  TerminalExitReason? exitReason;
  final TerminalBackend backend;

  /// Told once the process has exited, or failed to start: after [exited],
  /// [exitCode] and [exitMessage] say how. Not once it is disposed.
  final void Function(TerminalInstance instance)? onExit;

  /// The keyboard's way into the terminal: its view's focus.
  final FocusNode focusNode = FocusNode(debugLabel: 'terminal');

  /// The emulator, as VS Code's instance holds its xterm.
  late final TerminalXterm xterm;

  /// The emulator's core: the process's output parsed into a screen.
  internal.Terminal get terminal => xterm.core;

  /// The marks drawn on the screen and its scrollbar (as VS Code's
  /// decoration addon and find matches).
  DecorationService get decorations => xterm.decorationService;

  TerminalSelection get selection => xterm.selection;

  /// What the view draws.
  late final TerminalCoreSource source;

  /// The links on the screen: URLs, paths (resolved against [root]) and
  /// words, as VS Code's link detectors find them.
  late final TerminalLinkDetection links = TerminalLinkDetection(
    xterm,
    resolver: TerminalFileLinkResolver(stat: backend.linkStat),
    initialCwd: root,
    workspaceFolders: [root],
    cwdForLine: (line) =>
        _shellIntegration?.commandDetection?.getCwdForLine(line),
  );

  /// What the shell's integration reports: its commands and their marks,
  /// its folder. There from the launch on, to see the first prompt.
  ShellIntegration? get shellIntegration => _shellIntegration;
  ShellIntegration? _shellIntegration;

  final _onShellIntegrationReady = StreamController<void>.broadcast(sync: true);

  /// Fired once [shellIntegration] is there.
  Stream<void> get onShellIntegrationReady => _onShellIntegrationReady.stream;

  /// Find in the terminal: made the first time it is asked for.
  late final TerminalFind find = () {
    _findCreated = true;
    terminalColorTheme.addListener(_updateFindColors);
    return TerminalFind(
      xterm,
      decorations: terminalColorTheme.value.toSearchDecorations(),
    );
  }();
  bool _findCreated = false;

  /// Upstream `_updateTheme`: the workbench's colors as xterm.js' `theme`
  /// option, which replaces the terminal's colors (and those escape
  /// sequences set), clears the contrast cache and redraws.
  void _updateTheme() {
    xterm.options.theme = vscodeTerminalTheme(terminalColorTheme.value);
  }

  /// The code font's family (Settings -> Appearance) as the terminal's
  /// option. The interface text scale is applied by [TerminalView], where the
  /// terminal has a widget context; changing the editor code size must not
  /// remeasure terminal cells.
  void _updateFont() {
    xterm.options.fontFamily = vscodeTerminalFontFamily();
  }

  /// The find widget's theme listener, with `_updateFindColors`' new colors.
  void _updateFindColors() {
    find
      ..decorations = terminalColorTheme.value.toSearchDecorations()
      ..handleColorThemeChange();
  }

  late final TerminalClipboard clipboard;
  late final TerminalMouse mouse;
  late final TerminalKeyboard keyboard;

  final _output = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _printing;

  /// What the user typed before the process was there, as VS Code's
  /// process manager queues it.
  final List<Uint8List> _typedAhead = [];

  PtyLaunch? _launch;
  Pty? _pty;
  int _columns;
  int _rows;
  String? _userTitle;
  bool _exited = false;
  int? _exitCode;
  String? _exitMessage;
  bool _disposed = false;

  /// What it runs, once known.
  PtyLaunch? get launch => _launch;

  /// Its process, once started.
  Pty? get pty => _pty;

  /// The process's name: its executable's, without `.exe` (`zsh`,
  /// `pwsh`); empty until the launch is known.
  String get processName {
    final executable = _launch?.executable;
    if (executable == null) return '';
    final name = p.basename(executable);
    return name.toLowerCase().endsWith('.exe')
        ? name.substring(0, name.length - 4)
        : name;
  }

  /// What the user named it; null leaves it to the process.
  String? get userTitle => _userTitle;

  /// Its name in the tabs: the user's, else its [config]'s, else the
  /// process's (VS Code's default `terminal.integrated.tabs.title`,
  /// `${process}`).
  String get title =>
      _userTitle ??
      config?.name ??
      (processName.isEmpty ? 'Terminal' : processName);

  /// Whether it is kept, after its process exited, until a key is pressed
  /// (its [config]'s `waitOnExit`).
  bool get waitingForKey => _waitingForKey;
  bool _waitingForKey = false;

  /// Asked to be closed: a key was pressed after its process exited and it
  /// [waitingForKey].
  void Function(TerminalInstance instance)? onRequestClose;

  /// Names it [title]; none (or only spaces) gives it back to the process,
  /// as VS Code's rename does with no name.
  void rename(String? title) {
    final next = title == null || title.trim().isEmpty ? null : title;
    if (next == _userTitle || _disposed) return;
    _userTitle = next;
    notifyListeners();
  }

  int get columns => _columns;
  int get rows => _rows;

  /// Whether its process has exited, or never started.
  bool get exited => _exited;

  /// How the process exited: minus the signal's number when one ended it;
  /// null while it runs, or when it never started.
  int? get exitCode => _exitCode;

  /// Why it ended, when it stays for it: `The terminal process "…"
  /// terminated with exit code: N.`, or why it failed to launch.
  String? get exitMessage => _exitMessage;

  /// What the process prints, as it prints it (nothing is kept for a
  /// listener that comes later).
  Stream<Uint8List> get output => _output.stream;

  /// Sends [data] to the process as typed; kept until it has started, and
  /// dropped once it has exited (a key then closes a terminal
  /// [waitingForKey]).
  void write(Uint8List data) {
    if (_waitingForKey && !_disposed) {
      _waitingForKey = false;
      onRequestClose?.call(this);
      return;
    }
    if (_exited || _disposed || data.isEmpty) return;
    if (_pty case final pty?) {
      pty.write(data);
    } else {
      _typedAhead.add(Uint8List.fromList(data));
    }
  }

  /// [write]s [text] in UTF-8.
  void writeText(String text) => write(utf8.encode(text));

  /// VS Code's `sendText`: [text] with its line endings as Enter presses,
  /// one more when [shouldExecute] and it does not end with one; in
  /// bracketed paste when [bracketedPasteMode] and the process asked for
  /// it.
  void sendText(
    String text, {
    bool shouldExecute = false,
    bool bracketedPasteMode = false,
  }) {
    if (bracketedPasteMode &&
        terminal.coreService.decPrivateModes.bracketedPasteMode) {
      text = '\x1b[200~$text\x1b[201~';
    }
    text = text.replaceAll(RegExp(r'\r?\n'), '\r');
    if (shouldExecute && !text.endsWith('\r')) text += '\r';
    writeText(text);
    _onInput.add(text);
    if (shouldExecute) _onDidExecuteText.fire(null);
  }

  /// VS Code's `runCommand`: [commandLine] typed at the prompt and run;
  /// what was at the prompt (or anything, without shell integration) is
  /// cancelled first with ctrl+c.
  Future<void> runCommand(
    String commandLine, {
    bool shouldExecute = true,
  }) async {
    final detection = _shellIntegration?.commandDetection;
    if (shouldExecute &&
        (detection == null || detection.promptInputModel.value.isNotEmpty)) {
      sendText('\x03');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    sendText(
      commandLine,
      shouldExecute: shouldExecute,
      bracketedPasteMode: !shouldExecute,
    );
  }

  final _onDidExecuteText = Emitter<void>();

  /// Its grid, as its view lays it out; the process is told.
  void resize(int columns, int rows) {
    if (columns < 1 || rows < 1) return;
    if (columns == _columns && rows == _rows) return;
    _columns = columns;
    _rows = rows;
    terminal.resize(columns, rows);
    if (!_exited) _pty?.resize(columns, rows);
    notifyListeners();
  }

  /// Gives it the keyboard, now or once its view is built.
  void focus() => focusNode.requestFocus();

  /// Draws the cursor from now on (xterm.js' `_showCursor`, on focus and on
  /// each key sent): a terminal shows none before, as VS Code does not set
  /// `showCursorImmediately`.
  void showCursor() {
    final coreService = terminal.coreService;
    if (coreService.isCursorInitialized) return;
    coreService.isCursorInitialized = true;
    final y = terminal.buffer.y;
    terminal.onRenderEmitter.fire((start: y, end: y));
  }

  /// The shell it starts, a profile's, once known; null (or none) starts
  /// the user's.
  final Future<TerminalShell?>? shell;

  Future<void> _start() async {
    final generation = _generation;
    bool stale() => _disposed || generation != _generation;
    try {
      final config = this.config;
      final Pty pty;
      if (config?.customPty case final customPty?) {
        // After whoever made it was told it exists.
        await Future<void>.value();
        if (stale()) return;
        _shellIntegration = ShellIntegration(
          terminal,
          nonce: config!.shellIntegrationNonce ?? '',
          decorationService: decorations,
          onDidExecuteText: _onDidExecuteText.event,
        );
        _onShellIntegrationReady.add(null);
        pty = await customPty(this);
      } else {
        final executable = config?.executable;
        final TerminalShell? shell = executable != null
            ? (executable: executable, arguments: config?.arguments ?? const [])
            : this.shell == null
            ? null
            : await this.shell;
        if (stale()) return;
        final mutator = environmentMutator;
        final launch = await backend.launch(
          config?.cwd ?? root,
          columns: _columns,
          rows: _rows,
          shell: shell,
          environment: config?.env != null || mutator != null
              ? TerminalEnvironmentRequest(
                  env: config?.env,
                  strict: config?.strictEnv ?? false,
                  mutate: mutator,
                )
              : null,
        );
        if (stale()) return;
        _launch = launch;
        _shellIntegration = ShellIntegration(
          terminal,
          nonce: config?.shellIntegrationNonce ?? shellIntegrationNonce(launch),
          decorationService: decorations,
          onDidExecuteText: _onDidExecuteText.event,
        );
        _onShellIntegrationReady.add(null);
        notifyListeners();
        pty = await backend.start(launch);
      }
      if (stale()) {
        pty.kill();
        return;
      }
      _pty = pty;
      _printing = pty.output.listen(_printed);
      unawaited(
        pty.exitCode.then((code) {
          // VS Code's `_flushXtermData`: what it printed (all there before
          // its exit code) is parsed before the exit is told.
          if (generation != _generation || _disposed) return;
          if (_unparsed == 0) {
            _processExited(code);
            return;
          }
          terminal.write('', () {
            if (generation == _generation) _processExited(code);
          });
        }),
      );
      // Resized while it started: the process is told.
      final launch = _launch;
      if (launch != null &&
          (launch.columns != _columns || launch.rows != _rows)) {
        pty.resize(_columns, _rows);
      }
      for (final data in _typedAhead) {
        pty.write(data);
      }
      _typedAhead.clear();
      notifyListeners();
      _onProcessReady.add(pty.pid);
    } on Object catch (error) {
      if (stale()) return;
      var reason = '$error';
      if (reason.endsWith('.')) reason = reason.substring(0, reason.length - 1);
      _end(null, 'The terminal process failed to launch: $reason.');
    }
  }

  /// What the process printed, into the emulator. The process is paused
  /// while much of it waits to be parsed, as VS Code's flow control does.
  void _printed(Uint8List data) {
    final count = data.length;
    _unparsed += count;
    terminal.write(data, () => _parsed(count));
    if (!_paused && _unparsed > _highWatermark) {
      _paused = true;
      _pty?.pause();
    }
    _output.add(data);
  }

  void _parsed(int count) {
    _unparsed -= count;
    if (_paused && _unparsed < _lowWatermark) {
      _paused = false;
      if (!_disposed) _pty?.resume();
    }
  }

  /// VS Code's `FlowControlConstants.HighWatermarkChars` and
  /// `LowWatermarkChars`, in bytes here.
  static const _highWatermark = 100000;
  static const _lowWatermark = 5000;

  /// Printed and not yet parsed; whether the process is paused for it.
  int _unparsed = 0;
  bool _paused = false;

  void _processExited(int code) {
    if (_disposed) return;
    exitReason ??= TerminalExitReason.process;
    if (config?.waitOnExit case final waitOnExit?) {
      // VS Code's `_onProcessExit` with `waitOnExit`: the exit's message,
      // then the one asked for, and the next key closes it.
      _exited = true;
      _exitCode = code;
      _typedAhead.clear();
      // Told before the messages are written: they are no task's output.
      _onProcessExit.add(code);
      if (code > 0) {
        _writeOwnText(
          formatMessageForTerminal(
            _launch == null
                ? 'The terminal process terminated with exit code: $code.'
                : 'The terminal process "${_commandLine(_launch!)}" '
                      'terminated with exit code: $code.',
          ),
        );
      }
      if (waitOnExit(code) case final message?) {
        _writeOwnText(
          formatMessageForTerminal(message, excludeLeadingNewLine: true),
        );
      }
      _waitingForKey = true;
      notifyListeners();
      onExit?.call(this);
      return;
    }
    // node-pty reports 0 for a process a signal ended, and VS Code closes a
    // terminal quietly then: only a code above 0 is explained.
    _end(
      code,
      code > 0
          ? _launch == null
                ? 'The terminal process terminated with exit code: $code.'
                : 'The terminal process "${_commandLine(_launch!)}" '
                      'terminated with exit code: $code.'
          : null,
    );
  }

  void _end(int? code, String? message) {
    _exited = true;
    _exitCode = code;
    _exitMessage = message;
    _typedAhead.clear();
    _onProcessExit.add(code);
    if (message != null) _writeOwnText(formatMessageForTerminal(message));
    notifyListeners();
    onExit?.call(this);
  }

  /// Hangs up its process (still running) and lets go of it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    terminalColorTheme.removeListener(_updateTheme);
    CodeFont.families.removeListener(_updateFont);
    if (!_exited) _pty?.kill();
    unawaited(_printing?.cancel());
    unawaited(_output.close());
    unawaited(_onInput.close());
    unawaited(_onShellIntegrationReady.close());
    unawaited(_onLineData.close());
    unawaited(_onProcessReady.close());
    unawaited(_onProcessExit.close());
    _onDidExecuteText.dispose();
    if (_findCreated) {
      terminalColorTheme.removeListener(_updateFindColors);
      find.dispose();
    }
    _shellIntegration?.dispose();
    keyboard.dispose();
    mouse.dispose();
    clipboard.dispose();
    source.dispose();
    xterm.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// The command line in VS Code's exit message: the executable, then each
/// argument quoted (joined by commas, as its `join()` does).
String _commandLine(PtyLaunch launch) =>
    launch.executable + launch.arguments.map((a) => " '$a'").join(',');

/// A message from the app written into the terminal: an inverse ` * `, then
/// the message (VS Code's `formatMessageForTerminal`).
String formatMessageForTerminal(
  String message, {
  bool excludeLeadingNewLine = false,
  bool loudFormatting = false,
}) {
  final result = StringBuffer();
  if (!excludeLeadingNewLine) result.write('\r\n');
  result.write('\x1b[0m\x1b[7m * ');
  result.write(loudFormatting ? '\x1b[0;104m' : '\x1b[0m');
  result.write(' $message \x1b[0m\n\r');
  return result.toString();
}
