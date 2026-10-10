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

/// Status text remains available to filters and screen readers, not repeated
/// as a wide visual column in the compact table or hover.
class ModelTestStatusIcon extends StatelessWidget {
  const ModelTestStatusIcon({super.key, required this.status});
  final ModelTestStatus? status;
  @override
  Widget build(BuildContext context) => Semantics(
    label: modelTestStatusText(context.l10n, status),
    child: Icon(
      switch (status) {
        ModelTestStatus.passed => Codicons.check,
        ModelTestStatus.failed => Codicons.close,
        ModelTestStatus.running => Codicons.sync,
        ModelTestStatus.queued => Codicons.clock,
        ModelTestStatus.cancelled => Codicons.circleSlash,
        null => Codicons.dash,
      },
      size: 14,
      color:
          modelTestStatusColor(status) ?? themeColors['descriptionForeground'],
    ),
  );
}

/// The same compact, selectable detail appears in both benchmark entry points.
class ModelTestDetails extends StatefulWidget {
  const ModelTestDetails({
    super.key,
    required this.result,
    this.showMetrics = true,
    this.hover = false,
    this.expanded = false,
    this.onRefresh,
  });
  final ModelTestResult result;
  final bool showMetrics;
  final bool hover;
  final bool expanded;
  final VoidCallback? onRefresh;
  @override
  State<ModelTestDetails> createState() => _ModelTestDetailsState();
}

class _ModelTestDetailsState extends State<ModelTestDetails> {
  late bool _expanded = widget.expanded;
  @override
  void didUpdateWidget(ModelTestDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final l10n = context.l10n;
    final foreground = widget.hover
        ? IdeHoverColors.foreground
        : AppColors.text;
    final style = SettingsText.description.copyWith(
      color: foreground,
      fontSize: 11.5,
    );
    final mono = style.copyWith(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
    );
    final metrics = [
      (l10n.modelsBenchmarkSpeed, modelTestSpeed(result)),
      (l10n.modelsBenchmarkFirstText, modelTestDuration(result.firstText)),
      (l10n.modelsBenchmarkDuration, modelTestDuration(result.elapsed)),
    ];
    final secondary =
        '${l10n.modelsBenchmarkFirstEvent} ${modelTestDuration(result.firstEvent)}  ·  '
        '${modelTestTokens(result.inputTokens)} / ${modelTestOutputTokens(result)}';
    final error = modelTestErrorText(l10n, result.error);
    String preview(String value) =>
        _expanded ? value : modelTestOutputPreview(value, limit: 24);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SelectableText(
                result.model.displayName,
                maxLines: 1,
                style: style.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            ModelTestStatusIcon(status: result.status),
            if (widget.onRefresh != null) ...[
              const SizedBox(width: 4),
              IdeActionButton(
                icon: Codicons.refresh,
                size: 20,
                iconSize: 13,
                tooltip: l10n.modelsResultRetest,
                onPressed: result.active ? null : widget.onRefresh,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (widget.showMetrics) ...[
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
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SelectableText(label, style: style),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
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
          SelectableText(
            secondary,
            style: style.copyWith(
              color: themeColors['descriptionForeground'],
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText.rich(
                TextSpan(
                  style: mono,
                  children: [
                    if (error != null)
                      TextSpan(
                        text: '${preview(error)}\n',
                        style: TextStyle(color: themeColors['errorForeground']),
                      ),
                    TextSpan(
                      text: preview(
                        result.output.isEmpty ? '—' : result.output,
                      ),
                    ),
                    if (result.thinking.isNotEmpty)
                      TextSpan(
                        text:
                            '\n${l10n.modelsCompactThinking} · ${preview(result.thinking)}',
                        style: TextStyle(
                          color: themeColors['descriptionForeground'],
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IdeActionButton(
              icon: _expanded ? Codicons.chevronUp : Codicons.chevronDown,
              size: 18,
              iconSize: 12,
              tooltip: _expanded
                  ? l10n.modelsResultCollapse
                  : l10n.modelsResultExpand,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ),
        if (result.outputTruncated || result.thinkingTruncated)
          SelectableText(l10n.modelsBenchmarkTruncated, style: style),
      ],
    );
  }
}

/// Results open only by explicit click. The transparent dismissible barrier
/// keeps selection/expansion stable; leaving with the pointer is not dismissal.
Future<void> showModelTestResultPanel(
  BuildContext context, {
  required ModelTestService service,
  required String providerId,
  required String modelId,
  required VoidCallback? onRefresh,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.commonDismiss,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: FocusScope(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: _ResultPanelPlacement(anchor),
          child: Material(
            type: MaterialType.transparency,
            child: IdeHoverBox(
              child: ListenableBuilder(
                listenable: service,
                builder: (context, _) {
                  final result = service.result(providerId, modelId)!;
                  return ModelTestHoverDetails(
                    service: service,
                    result: result,
                    onRefresh: onRefresh,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ResultPanelPlacement extends SingleChildLayoutDelegate {
  _ResultPanelPlacement(this.anchor);
  final Rect anchor;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (anchor.right - childSize.width).clamp(
      8.0,
      math.max(8.0, size.width - childSize.width - 8),
    );
    final top = anchor.top >= childSize.height + 8
        ? anchor.top - childSize.height - 4
        : anchor.bottom + 4;
    return Offset(
      left.toDouble(),
      top
          .clamp(8.0, math.max(8.0, size.height - childSize.height - 8))
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_ResultPanelPlacement oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class ModelTestHoverDetails extends StatelessWidget {
  const ModelTestHoverDetails({
    super.key,
    required this.service,
    required this.result,
    this.onRefresh,
  });
  final VoidCallback? onRefresh;
  final ModelTestService service;
  final ModelTestResult result;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: math.min(300, math.max(0, MediaQuery.sizeOf(context).width - 32)),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(300, MediaQuery.sizeOf(context).height * .65),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: service,
            builder: (context, _) => ModelTestDetails(
              key: ObjectKey(result),
              result: result,
              hover: true,
              onRefresh: onRefresh,
            ),
          ),
        ),
      ),
    ),
  );
}
