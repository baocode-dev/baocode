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

import 'package:bao_xterm/common/platform.dart';
import 'package:bao_xterm/common/services/decoration_service.dart';
import 'package:bao_xterm/headless/terminal.dart' as internal;

/// What a new terminal runs in [root]: [terminalLaunch] in the app;
/// [shell] when a profile names it, else the user's shell.
typedef TerminalLauncher = Future<PtyLaunch> Function(
  String root, {
  int columns,
  int rows,
  TerminalShell? shell,
});

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
    terminal.onData(writeText);
    terminal.onBinary((data) => write(latin1.encode(data)));
    unawaited(_start());
  }

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

  /// The folder it starts in.
  final String root;
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

  /// Its name in the tabs: the user's, else the process's (VS Code's
  /// default `terminal.integrated.tabs.title`, `${process}`).
  String get title =>
      _userTitle ?? (processName.isEmpty ? 'Terminal' : processName);

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
  /// dropped once it has exited.
  void write(Uint8List data) {
    if (_exited || _disposed || data.isEmpty) return;
    if (_pty case final pty?) {
      pty.write(data);
    } else {
      _typedAhead.add(Uint8List.fromList(data));
    }
  }

  /// [write]s [text] in UTF-8.
  void writeText(String text) => write(utf8.encode(text));

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
    try {
      final shell = this.shell == null ? null : await this.shell;
      if (_disposed) return;
      final launch = await backend.launch(
        root,
        columns: _columns,
        rows: _rows,
        shell: shell,
      );
      if (_disposed) return;
      _launch = launch;
      _shellIntegration = ShellIntegration(
        terminal,
        nonce: shellIntegrationNonce(launch),
        decorationService: decorations,
      );
      notifyListeners();
      final pty = await backend.start(launch);
      if (_disposed) {
        pty.kill();
        return;
      }
      _pty = pty;
      _printing = pty.output.listen(_printed);
      unawaited(pty.exitCode.then(_processExited));
      if (launch.columns != _columns || launch.rows != _rows) {
        pty.resize(_columns, _rows);
      }
      for (final data in _typedAhead) {
        pty.write(data);
      }
      _typedAhead.clear();
      notifyListeners();
    } on Object catch (error) {
      if (_disposed) return;
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
    if (message != null) terminal.write(formatMessageForTerminal(message));
    notifyListeners();
    onExit?.call(this);
  }

  /// Hangs up its process (still running) and lets go of it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    terminalColorTheme.removeListener(_updateTheme);
    if (!_exited) _pty?.kill();
    unawaited(_printing?.cancel());
    unawaited(_output.close());
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
