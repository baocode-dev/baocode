import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/codicons.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../models/model_test.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'settings_widgets.dart';

/// One display contract for the model row, batch table and result hover.
/// Keep units in each value: table headings are not visible in every context.
String modelTestDuration(Duration? duration) {
  if (duration == null) return '—';
  if (duration < const Duration(seconds: 1)) {
    final ms = duration.inMicroseconds / 1000;
    return '${ms.toStringAsFixed(ms < 1 ? 2 : 0)} ms';
  }
  return '${(duration.inMicroseconds / 1000000).toStringAsFixed(2)} s';
}

/// Preview visible text without splitting combined emoji or Unicode graphemes.
String modelTestOutputPreview(String output, {int limit = 4}) {
  final text = output.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '—';
  // Inspect only enough graphemes to decide whether the preview needs ellipsis.
  final characters = text.characters.take(limit + 1).toList();
  return '${characters.take(limit).join()}${characters.length > limit ? '…' : ''}';
}

String modelTestSpeed(ModelTestResult? result) {
  final speed = result?.tokensPerSecond;
  if (speed == null) return '—';
  return '${result!.tokensEstimated ? '~' : ''}${speed.toStringAsFixed(1)} token/s';
}

String modelTestTokens(int? tokens, {bool estimated = false}) =>
    tokens == null ? '—' : '${estimated ? '~' : ''}$tokens token';

String modelTestOutputTokens(ModelTestResult? result) => modelTestTokens(
  result == null || result.output.isEmpty ? null : result.outputTokens,
  estimated: result?.tokensEstimated ?? false,
);

String modelTestStatusText(AppLocalizations l10n, ModelTestStatus? status) =>
    switch (status) {
      ModelTestStatus.queued => l10n.modelsBenchmarkQueued,
      ModelTestStatus.running => l10n.modelsBenchmarkRunning,
      ModelTestStatus.passed => l10n.modelsBenchmarkPassed,
      ModelTestStatus.failed => l10n.modelsBenchmarkFailed,
      ModelTestStatus.cancelled => l10n.modelsBenchmarkCancelled,
      null => l10n.modelsBenchmarkUntested,
    };

String? modelTestErrorText(AppLocalizations l10n, String? error) =>
    switch (error) {
      'incomplete_stream' => l10n.modelsBenchmarkIncomplete,
      'empty_output' => l10n.modelsBenchmarkEmpty,
      'timeout' => l10n.modelsBenchmarkTimeout,
      _ => error,
    };

Color? modelTestStatusColor(ModelTestStatus? status) => switch (status) {
  ModelTestStatus.passed => SettingsSwitch.onColor,
  ModelTestStatus.failed => themeColors['errorForeground'],
  _ => null,
};

/// Shared compact result view for both model-row and batch-table hovers.
class ModelTestDetails extends StatelessWidget {
  const ModelTestDetails({
    super.key,
    required this.result,
    this.showMetrics = true,
    this.hover = false,
    this.expanded = false,
  });
  final ModelTestResult result;
  final bool showMetrics;
  final bool hover;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final foreground = hover ? IdeHoverColors.foreground : AppColors.text;
    final style = SettingsText.description.copyWith(color: foreground);
    final mono = style.copyWith(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
    );
    final metrics = [
      (l10n.modelsBenchmarkSpeed, modelTestSpeed(result)),
      (l10n.modelsBenchmarkFirstText, modelTestDuration(result.firstText)),
      (l10n.modelsBenchmarkFirstEvent, modelTestDuration(result.firstEvent)),
      (l10n.modelsBenchmarkDuration, modelTestDuration(result.elapsed)),
      (l10n.modelsBenchmarkInputTokens, modelTestTokens(result.inputTokens)),
      (l10n.modelsBenchmarkTokens, modelTestOutputTokens(result)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SelectableText(
                '${l10n.modelsBenchmarkOutput} · ${result.model.displayName}',
                maxLines: 1,
                style: SettingsText.label.copyWith(color: foreground),
              ),
            ),
            const SizedBox(width: 8),
            SelectableText(
              modelTestStatusText(l10n, result.status),
              style: style.copyWith(color: modelTestStatusColor(result.status)),
            ),
            IdeActionButton(
              icon: Codicons.copy,
              tooltip: l10n.modelsResultCopyAll,
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: [
                    result.model.displayName,
                    modelTestStatusText(l10n, result.status),
                    for (final (label, value) in metrics) '$label: $value',
                    if (result.error != null)
                      modelTestErrorText(l10n, result.error)!,
                    result.output,
                    if (result.thinking.isNotEmpty)
                      '${l10n.modelsBenchmarkThinking}:\n${result.thinking}',
                  ].join('\n'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (showMetrics) ...[
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: IntrinsicColumnWidth(),
            },
            children: [
              for (final (label, value) in metrics)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, right: 16),
                      child: SelectableText(label, style: style),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        value,
                        textAlign: TextAlign.right,
                        style: mono,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Divider(
            height: 12,
            color: hover ? IdeHoverColors.border : themeColors['widget.border'],
          ),
        ],
        if (modelTestErrorText(l10n, result.error) case final error?)
          _ResultSection(
            key: ValueKey('${result.model.id}-error'),
            label: l10n.modelsBenchmarkFailed,
            text: error,
            style: mono,
          ),
        _ResultSection(
          key: ValueKey('${result.model.id}-output'),
          label: l10n.modelsBenchmarkOutput,
          text: result.output.isEmpty ? '—' : result.output,
          style: mono,
          initiallyExpanded: expanded,
        ),
        if (result.thinking.isNotEmpty)
          _ResultSection(
            key: ValueKey('${result.model.id}-thinking'),
            label: l10n.modelsBenchmarkThinking,
            text: result.thinking,
            style: mono,
          ),
        if (result.tokensEstimated && result.output.isNotEmpty)
          SelectableText(l10n.modelsBenchmarkEstimated, style: style),
        if (result.outputTruncated || result.thinkingTruncated)
          SelectableText(l10n.modelsBenchmarkTruncated, style: style),
      ],
    );
  }
}

/// Selection is independent from expansion; copy always copies the full text.
class _ResultSection extends StatefulWidget {
  const _ResultSection({
    super.key,
    required this.label,
    required this.text,
    required this.style,
    this.initiallyExpanded = false,
  });
  final String label;
  final String text;
  final TextStyle style;
  final bool initiallyExpanded;
  @override
  State<_ResultSection> createState() => _ResultSectionState();
}

class _ResultSectionState extends State<_ResultSection> {
  late bool _expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SelectableText(
                widget.label,
                style: widget.style.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IdeActionButton(
              icon: _expanded ? Codicons.chevronUp : Codicons.chevronDown,
              tooltip: _expanded
                  ? context.l10n.modelsResultCollapse
                  : context.l10n.modelsResultExpand,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            IdeActionButton(
              icon: Codicons.copy,
              tooltip: '${context.l10n.commonCopy}: ${widget.label}',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.text)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SelectableText(
          _expanded
              ? widget.text
              : modelTestOutputPreview(widget.text, limit: 16),
          style: widget.style,
        ),
      ],
    ),
  );
}

class ModelTestHoverDetails extends StatelessWidget {
  const ModelTestHoverDetails({
    super.key,
    required this.service,
    required this.result,
  });
  final ModelTestService service;
  final ModelTestResult result;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: math.min(400, math.max(0, MediaQuery.sizeOf(context).width - 48)),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(420, MediaQuery.sizeOf(context).height * .7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: service,
            builder: (context, _) => ModelTestDetails(
              key: ObjectKey(result),
              result: result,
              hover: true,
            ),
          ),
        ),
      ),
    ),
  );
}
