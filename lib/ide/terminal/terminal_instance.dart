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
// (`_onProcessExit`, `parseExitResult`, `rename`) and
// terminalProcessManager.ts (input queued until the process is there).
//
// The emulator is not here yet: what the process prints comes out of
// [TerminalInstance.output] (the emulator is to take it where [_printed]
// is, so that terminals in the background keep their screens); what the
// user types goes in by [TerminalInstance.write], and the view's grid by
// [TerminalInstance.resize].

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'pty.dart';

/// What a new terminal runs in [root]: [terminalLaunch] in the app.
typedef TerminalLauncher = Future<PtyLaunch> Function(
  String root, {
  int columns,
  int rows,
});

/// Where terminals' processes come from, as VS Code's terminal backend:
/// [launch] says what a new terminal runs and [start] runs it on a pseudo
/// terminal. Widget tests give fakes, never a real shell.
class TerminalBackend {
  const TerminalBackend({
    this.launch = terminalLaunch,
    this.start = startPty,
    this._supported,
  });

  final TerminalLauncher launch;
  final PtyStarter start;
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
  }) {
    unawaited(_start());
  }

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
    if (!_exited) _pty?.resize(columns, rows);
    notifyListeners();
  }

  /// Gives it the keyboard, now or once its view is built.
  void focus() => focusNode.requestFocus();

  Future<void> _start() async {
    try {
      final launch = await backend.launch(root, columns: _columns, rows: _rows);
      if (_disposed) return;
      _launch = launch;
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

  /// What the process printed. The emulator is to parse it here.
  void _printed(Uint8List data) => _output.add(data);

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
    notifyListeners();
    onExit?.call(this);
  }

  /// Hangs up its process (still running) and lets go of it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_exited) _pty?.kill();
    unawaited(_printing?.cancel());
    unawaited(_output.close());
    focusNode.dispose();
    super.dispose();
  }
}

/// The command line in VS Code's exit message: the executable, then each
/// argument quoted (joined by commas, as its `join()` does).
String _commandLine(PtyLaunch launch) =>
    launch.executable + launch.arguments.map((a) => " '$a'").join(',');
