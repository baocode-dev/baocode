import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/file_service.dart';
import '../../ide/ide_hover.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../widgets/hover_scrollbar.dart';
import '../widgets/shell_highlight.dart';
import '../widgets/terminal_output.dart';
import '../chat_models.dart' show CommandStatus;

/// A background command as a terminal shows it: what it is for and how it
/// is doing above, the command, then its output, read on its host only
/// while visible.
class TerminalPreview extends StatefulWidget {
  const TerminalPreview({
    super.key,
    required this.task,
    this.command,
    required this.files,
    required this.onStop,
  });

  final KernelTask task;

  /// The command line it runs, where its tool call is known.
  final String? command;
  final IdeFileService files;
  final VoidCallback onStop;

  @override
  State<TerminalPreview> createState() => _TerminalPreviewState();
}

class _TerminalPreviewState extends State<TerminalPreview> {
  final _scroll = ScrollController();
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
    _sync();
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
  }

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
    final follow = !_scroll.hasClients || _scroll.position.extentAfter < 32;
    try {
      final output = await widget.files.read(path, force: true);
      if (!mounted || generation != _generation) return;
      // Bound rendering cost while keeping the end, like terminal scrollback.
      final text = output.length > 200000
          ? output.substring(output.length - 200000)
          : output;
      if (_text != text || _error != null) {
        setState(() {
          _text = text;
          _error = null;
        });
        if (follow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          });
        }
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
    _scroll.dispose();
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
    final output = _text.isNotEmpty ? _text : task.summary ?? '';
    final mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      height: 1.5,
    );
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
          child: SelectionArea(
            child: HoverScrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.command case final command?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: r'$ ',
                                style: TextStyle(color: AppColors.textFaint),
                              ),
                              ...highlightShell(command),
                            ],
                          ),
                          style: mono.copyWith(color: AppColors.text),
                        ),
                      ),
                    if (output.isEmpty)
                      Text(
                        _running
                            ? l10n.sidePanelWaitingOutput
                            : l10n.sidePanelOutputUnavailable,
                        style: mono.copyWith(
                          color: AppColors.textFaint,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Text.rich(
                        terminalOutput(output).span,
                        style: mono.copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
