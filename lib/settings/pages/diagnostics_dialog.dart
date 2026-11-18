import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../diagnostics/diagnostics_bundle.dart';
import '../../diagnostics/diagnostics_upload.dart';
import '../../diagnostics/key_watch.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_editor_placeholder.dart' show ideFormatSize;
import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import '../../platform/event_log.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'model_dialogs.dart';

/// Settings → Updates → Upload…: a note for the logs, what is sent, the
/// minidumps to send too (where there are any: Windows'), then the
/// report's id once uploaded, to copy.
Future<void> showDiagnosticsDialog(
  BuildContext context,
  DiagnosticsUploader uploader,
) => showGeneralDialog<void>(
  context: context,
  // Closed by its buttons, Escape or the close button: a click beside it
  // would lose what was typed.
  barrierDismissible: false,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => DiagnosticsDialog(uploader: uploader),
);

class DiagnosticsDialog extends StatefulWidget {
  const DiagnosticsDialog({super.key, required this.uploader});

  final DiagnosticsUploader uploader;

  @override
  State<DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<DiagnosticsDialog> {
  final _note = TextEditingController();
  List<DiagnosticsLog>? _logs;
  var _dumps = false;
  var _sending = false;
  DiagnosticsResult? _result;

  /// What went wrong other than the server's answer.
  Object? _error;
  var _copied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_list());
  }

  @override
  void dispose() {
    // Closed while it sends: not sent.
    if (_sending) widget.uploader.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<void> _list() async {
    final logs = await widget.uploader.logs();
    if (mounted) setState(() => _logs = logs);
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _result = null;
      _error = null;
    });
    // A key the app has as held, never let go (N2S9TV9F), goes with them.
    appEvent('keys', 'at the upload: ${KeyWatch.describe()}');
    DiagnosticsResult? result;
    Object? error;
    try {
      result = await widget.uploader.upload(
        note: _note.text,
        dumps: _dumps,
        locale: context.l10n.localeName,
      );
    } on Object catch (caught) {
      error = caught;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = result;
      _error = error;
    });
  }

  Future<void> _copy(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (mounted) setState(() => _copied = true);
  }

  static String _failure(AppLocalizations l10n, DiagnosticsFailed failed) =>
      switch (failed.reason) {
        DiagnosticsFailure.tooLarge => l10n.diagnosticsTooLarge,
        DiagnosticsFailure.rateLimited => l10n.diagnosticsRateLimited,
        DiagnosticsFailure.refused => l10n.diagnosticsRefused(
          failed.status ?? 0,
        ),
        DiagnosticsFailure.server => l10n.diagnosticsServerError(
          failed.status == null ? '-' : 'HTTP ${failed.status}',
        ),
        DiagnosticsFailure.network => l10n.diagnosticsFailed(
          '${failed.error ?? '-'}',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_result case DiagnosticsUploaded(:final id, :final omittedDumps)) {
      return _uploaded(context, id, omittedDumps);
    }
    final colors = themeColors;
    final logs = _logs;
    final texts = [...?logs?.where((log) => !log.isDump)];
    final dumps = [...?logs?.where((log) => log.isDump)];
    int total(List<DiagnosticsLog> logs) =>
        logs.fold(0, (sum, log) => sum + log.size);
    final problem = switch ((_result, _error)) {
      (final DiagnosticsFailed failed, _) => _failure(l10n, failed),
      (_, final error?) => l10n.diagnosticsFailed('$error'),
      _ => null,
    };
    return ModelDialogFrame(
      title: l10n.diagnosticsDialogTitle,
      actions: [
        IdeButton(
          label: _sending
              ? l10n.diagnosticsUploading
              : problem == null
              ? l10n.diagnosticsSend
              : l10n.diagnosticsRetry,
          spinning: _sending,
          onPressed: logs == null || _sending ? null : () => unawaited(_send()),
        ),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdeInputBox(
              controller: _note,
              placeholder: l10n.diagnosticsNotePlaceholder,
              semanticsLabel: l10n.diagnosticsNotePlaceholder,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
            ),
            if (logs != null) ...[
              const SizedBox(height: 10),
              Text(
                texts.isEmpty
                    ? l10n.diagnosticsNoFiles
                    : l10n.diagnosticsFiles(
                        texts.length,
                        ideFormatSize(total(texts)),
                      ),
                style: _text(),
              ),
              if (dumps.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    ModelCheckbox(
                      checked: _dumps,
                      semanticLabel: l10n.diagnosticsDumps(
                        dumps.length,
                        ideFormatSize(total(dumps)),
                      ),
                      onChanged: _sending
                          ? null
                          : (checked) => setState(() => _dumps = checked),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MouseRegion(
                        cursor: _sending
                            ? MouseCursor.defer
                            : SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _sending
                              ? null
                              : () => setState(() => _dumps = !_dumps),
                          child: ExcludeSemantics(
                            child: Text(
                              l10n.diagnosticsDumps(
                                dumps.length,
                                ideFormatSize(total(dumps)),
                              ),
                              style: _text(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2),
                  child: Text(l10n.diagnosticsDumpsDetail, style: _muted()),
                ),
              ],
            ],
            const SizedBox(height: 10),
            Text(l10n.diagnosticsPrivacy, style: _muted()),
            if (problem != null) ...[
              const SizedBox(height: 10),
              SelectableText(
                problem,
                style: _text(color: colors['errorForeground']),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _uploaded(BuildContext context, String id, int omittedDumps) {
    final l10n = context.l10n;
    return ModelDialogFrame(
      title: l10n.diagnosticsDialogTitle,
      onSubmit: () => Navigator.pop(context),
      actions: [
        IdeButton(
          label: _copied ? l10n.diagnosticsCopied : l10n.diagnosticsCopyId,
          onPressed: () => unawaited(_copy(id)),
        ),
        IdeButton(
          label: l10n.commonClose,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.diagnosticsUploaded, style: _text()),
          const SizedBox(height: 6),
          SelectableText(
            id,
            style: _text(size: 20).copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(l10n.diagnosticsUploadedDetail, style: _muted()),
          if (omittedDumps > 0) ...[
            const SizedBox(height: 6),
            Text(l10n.diagnosticsOmittedDumps(omittedDumps), style: _muted()),
          ],
        ],
      ),
    );
  }

  static TextStyle _text({Color? color, double size = 13}) => TextStyle(
    fontSize: size,
    height: 18 / 13,
    color: color ?? themeColors['editorWidget.foreground'],
  );

  static TextStyle _muted() =>
      _text(color: themeColors['descriptionForeground'], size: 12);
}
