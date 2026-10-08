import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ide/file_service.dart';
import '../../ide/ide_hover.dart';
import '../../ide/terminal/links/terminal_link_resolver.dart';
import '../../ide/terminal/links/terminal_links.dart';
import '../../ide/terminal/pty.dart';
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_view.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../widgets/shell_highlight.dart';
import '../chat_models.dart' show CommandStatus;

/// A background command in a terminal of its own: what it is for and how
/// it is doing above, then the command and its output on the terminal's
/// screen, as the panel's terminals draw theirs. The output is read on its
/// host only while visible, and only what was added is printed.
class TerminalPreview extends StatefulWidget {
  const TerminalPreview({
    super.key,
    required this.task,
    this.command,
    required this.files,
    required this.onStop,
    this.root = '',
    this.linkStat,
    this.skipShell = const [],
    this.onOpenLink,
  });

  final KernelTask task;

  /// The command line it runs, where its tool call is known.
  final String? command;
  final IdeFileService files;
  final VoidCallback onStop;

  /// The folder relative paths in the output are links into, and what is
  /// at them (null: the disk's), as for the panel's terminals.
  final String root;
  final TerminalLinkStat? linkStat;

  /// As [TerminalView.skipShell] and [TerminalView.onOpenLink].
  final List<ShortcutActivator> skipShell;
  final ValueChanged<TerminalLink>? onOpenLink;

  @override
  State<TerminalPreview> createState() => _TerminalPreviewState();
}

class _TerminalPreviewState extends State<TerminalPreview> {
  final _pty = _OutputPty();
  late final TerminalInstance _terminal = TerminalInstance(
    id: 0,
    root: widget.root,
    backend: TerminalBackend(
      launch: (root, {columns = 80, rows = 24, shell}) async =>
          PtyLaunch(executable: '', workingDirectory: root),
      start: (_) async => _pty,
      linkStat: widget.linkStat,
    ),
  );

  /// What the screen was last given ([_screenText]), to print only what
  /// was added to it.
  String? _screen;
  Timer? _ticker;
  String _text = '';
  Object? _error;
  bool _reading = false;
  bool _readAgain = false;
  int _generation = 0;

  bool get _running => widget.task.status == CommandStatus.running;

  @override
  void initState() {
    super.initState();
    // Output files end lines with `\n` alone: no terminal discipline made
    // them `\r\n`. Logs are kept longer than a shell's screen.
    _terminal.xterm.options
      ..convertEol = true
      ..scrollback = 10000;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _print();
  }

  @override
  void didUpdateWidget(TerminalPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.files != widget.files ||
        oldWidget.task.outputFile != widget.task.outputFile) {
      _generation++;
      _reading = false;
      _readAgain = false;
      _text = '';
      _error = null;
    }
    if (!identical(oldWidget.task, widget.task) ||
        oldWidget.files != widget.files) {
      _sync();
    }
    _print();
  }

  /// The screen: the command, then its output; else why there is none.
  String get _screenText {
    final l10n = context.l10n;
    final output = _text.isNotEmpty ? _text : widget.task.summary ?? '';
    return [
      if (widget.command case final command?)
        '\x1b[2m\$ \x1b[22m${highlightShellAnsi(command)}\n',
      if (output.isNotEmpty)
        output
      else
        '\x1b[2;3m${_running ? l10n.sidePanelWaitingOutput : l10n.sidePanelOutputUnavailable}\x1b[0m',
    ].join();
  }

  /// Prints what [_screenText] added; anything else it printed again, from
  /// a reset terminal (in band, after what is still to be parsed).
  void _print() {
    final screen = _screenText;
    final shown = _screen;
    if (screen == shown) return;
    _screen = screen;
    if (shown != null && screen.startsWith(shown)) {
      _pty.print(screen.substring(shown.length));
      return;
    }
    // Bound the work, keeping the end (from a line's start), as the
    // scrollback would.
    var text = screen;
    if (text.length > _printLimit) {
      final cut = text.indexOf('\n', text.length - _printLimit);
      text = text.substring(cut < 0 ? text.length - _printLimit : cut + 1);
    }
    // A log has no cursor to show.
    _pty.print('${shown == null ? '' : '\x1bc'}\x1b[?25l$text');
  }

  static const _printLimit = 200000;

  void _sync() {
    _ticker?.cancel();
    if (_running) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
        unawaited(_read());
      });
    }
    unawaited(_read());
  }

  Future<void> _read() async {
    final path = widget.task.outputFile;
    if (path == null) return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    final generation = _generation;
    try {
      final output = await widget.files.read(path, force: true);
      if (!mounted || generation != _generation) return;
      if (_text != output || _error != null) {
        setState(() {
          _text = output;
          _error = null;
        });
        _print();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (generation == _generation) {
        _reading = false;
        if (_readAgain && mounted) {
          _readAgain = false;
          unawaited(_read());
        }
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _ticker?.cancel();
    _terminal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final task = widget.task;
    final status = switch (task.status) {
      CommandStatus.running => l10n.stripRunningElapsed(
        DateTime.now().difference(task.startedAt).inSeconds,
      ),
      CommandStatus.succeeded => l10n.sidePanelTaskCompleted,
      CommandStatus.failed => l10n.sidePanelTaskFailed,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (task.description.isNotEmpty) ...[
                        TextSpan(
                          text: task.description,
                          style: TextStyle(color: AppColors.text),
                        ),
                        const TextSpan(text: '  ·  '),
                      ],
                      TextSpan(text: status),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              if (_error != null)
                IdeActionButton(
                  icon: Codicons.refresh,
                  tooltip: l10n.commonRefresh,
                  onPressed: () => unawaited(_read()),
                ),
              if (_running)
                IdeActionButton(
                  icon: Codicons.debugStop,
                  tooltip: l10n.chatStop,
                  onPressed: widget.onStop,
                ),
            ],
          ),
        ),
        if (_error != null &&
            (!_running || _error is! IdeFileNotFoundException))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${l10n.sidePanelOutputUnavailable}: '
              '${localizedFileError(l10n, _error!)}',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        Expanded(
          child: TerminalView(
            _terminal,
            skipShell: widget.skipShell,
            onKill: _running ? widget.onStop : null,
            onOpenLink: widget.onOpenLink,
          ),
        ),
      ],
    );
  }
}

/// A background command's output as a terminal's process prints: what the
/// preview [print]s of its file. Nothing typed reaches the command.
class _OutputPty extends Pty {
  final _output = StreamController<Uint8List>();

  void print(String text) {
    if (text.isNotEmpty && !_output.isClosed) _output.add(utf8.encode(text));
  }

  @override
  int get pid => 0;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int columns, int rows) {}

  @override
  void kill([PtySignal signal = PtySignal.hangup]) =>
      unawaited(_output.close());

  /// It never exits: the task's status says how the command did.
  @override
  Future<int> get exitCode => Completer<int>().future;
}
