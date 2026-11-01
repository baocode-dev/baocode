import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../models/model_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../usage_ledger.dart';
import '../usage_prices.dart';
import '../usage_record.dart';
import 'usage_charts.dart';
import 'usage_context.dart';
import 'usage_style.dart';
import 'usage_trace_view.dart';

/// A kind of request, as a small tag: its color's dot and name.
class UsageClassTag extends StatelessWidget {
  const UsageClassTag(this.kind, {super.key, this.text});

  final UsageClass kind;

  /// In place of the kind's name (a subagent's type).
  final String? text;

  @override
  Widget build(BuildContext context) {
    final color = UsagePalette.ofClass(kind);
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                text ?? UsageFormat.ofClass(context, kind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 10.5,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The calls, newest first, [pageSize] at a time: each its time, kind,
/// model and tokens on a line, what it took under; a click opens all
/// that is kept of it.
class UsageCallsList extends StatefulWidget {
  const UsageCallsList({
    super.key,
    required this.calls,
    this.pageSize = 40,
    this.sessionLabel,
    this.showSession = true,
    this.ledger,
  });

  /// Oldest first, as counted.
  final List<UsageCall> calls;
  final int pageSize;

  /// Where their traces are: the app's by default.
  final UsageLedger? ledger;

  /// The conversation of a session's id, as shown.
  final String Function(UsageCall call)? sessionLabel;
  final bool showSession;

  @override
  State<UsageCallsList> createState() => _UsageCallsListState();
}

class _UsageCallsListState extends State<UsageCallsList> {
  late int _shown = widget.pageSize;
  UsageCall? _open;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final calls = widget.calls;
    if (calls.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(l10n.ustatNoCalls, style: UsageText.faint),
      );
    }
    final count = calls.length < _shown ? calls.length : _shown;
    return LayoutBuilder(
      builder: (context, constraints) => _list(
        context,
        count,
        wide: constraints.maxWidth >= _wideWidth,
        barColumn: constraints.maxWidth >= _barColumnWidth,
      ),
    );
  }

  /// Wide enough for a call a row, its numbers in columns.
  static const _wideWidth = 680.0;

  /// Wide enough for its bar a column of its own (else under the model).
  static const _barColumnWidth = 900.0;

  Widget _list(
    BuildContext context,
    int count, {
    required bool wide,
    required bool barColumn,
  }) {
    final l10n = context.l10n;
    final calls = widget.calls;
    // The bars' scale: the largest of them all, not only of those shown,
    // so that showing more keeps them as they were.
    var scale = 0;
    for (final call in calls) {
      if (call.total > scale) scale = call.total;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) _CallHeader(barColumn: barColumn),
        for (var i = 0; i < count; i++)
          _CallRow(
            wide: wide,
            barColumn: barColumn,
            scale: scale,
            call: calls[calls.length - 1 - i],
            open: identical(_open, calls[calls.length - 1 - i]),
            session: widget.showSession
                ? widget.sessionLabel?.call(calls[calls.length - 1 - i])
                : null,
            ledger: widget.ledger,
            onTap: () => setState(() {
              final call = calls[calls.length - 1 - i];
              _open = identical(_open, call) ? null : call;
            }),
          ),
        if (count < calls.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: () => setState(() => _shown += widget.pageSize),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      l10n.ustatShowMoreCalls(calls.length - count),
                      style: UsageText.muted.copyWith(
                        color: hovered ? AppColors.text : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The columns of a wide [UsageCallsList]: the numbers' widths.
abstract final class _Columns {
  static const time = 60.0;
  static const kind = 88.0;
  static const number = 50.0;

  /// A time's, a speed's: shorter numbers.
  static const time2 = 44.0;
  static const speed = 40.0;
  static const total = 52.0;
  static const cost = 56.0;
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.barColumn});

  final bool barColumn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget number(String label, [double width = _Columns.number]) => SizedBox(
      width: width,
      child: Text(label, textAlign: TextAlign.right, style: UsageText.faint),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: UsagePalette.grid)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          SizedBox(
            width: _Columns.time,
            child: Text(l10n.ustatFieldTime, style: UsageText.faint),
          ),
          SizedBox(
            width: _Columns.kind,
            child: Text(l10n.ustatFieldClass, style: UsageText.faint),
          ),
          Expanded(
            flex: 2,
            child: Text(l10n.ustatFieldModel, style: UsageText.faint),
          ),
          if (barColumn)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(l10n.ustatColumnMix, style: UsageText.faint),
              ),
            ),
          number(l10n.ustatTokenInput),
          number(l10n.ustatTokenCacheRead),
          number(l10n.ustatTokenCacheWrite),
          number(l10n.ustatTokenOutput),
          // Its time to first token in its detail where narrower: room
          // for the cost.
          if (barColumn) number(l10n.ustatFieldFirstToken, _Columns.time2),
          number(l10n.ustatFieldDuration, _Columns.time2),
          number(l10n.ustatFieldSpeed, _Columns.speed),
          const SizedBox(width: 18),
          number(l10n.ustatColumnTotal, _Columns.total),
          number(l10n.ustatCost, _Columns.cost),
        ],
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.wide,
    required this.barColumn,
    required this.scale,
    required this.call,
    required this.open,
    required this.onTap,
    this.session,
    this.ledger,
  });

  final bool wide;
  final bool barColumn;

  /// The largest call's total: a bar's whole length.
  final int scale;
  final UsageCall call;
  final bool open;
  final String? session;
  final VoidCallback onTap;
  final UsageLedger? ledger;

  /// What it cost, at its model's price; null unpriced.
  String? get _cost => switch (UsagePrices.current.priceOf(call)) {
    final price? => UsagePrices.money(price.cost(call), price.currency),
    null => null,
  };

  Widget _tag(BuildContext context) => UsageClassTag(
    call.requestClass,
    text: call.requestClass.agent
        ? call.agentType ?? UsageFormat.ofClass(context, call.requestClass)
        : null,
  );

  Widget _marks(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (call.traceId != null)
          IdeHover(
            message: l10n.ustatTraceKept,
            child: Icon(
              Codicons.debugAlt,
              size: 12,
              color: AppColors.textFaint,
            ),
          ),
        if (call.failed)
          IdeHover(
            message: '${call.status} · ${call.error ?? ''}',
            child: Icon(Codicons.error, size: 12, color: UsagePalette.error),
          ),
      ],
    );
  }

  /// A call a row: its numbers in the header's columns.
  Widget _wide(BuildContext context, bool hovered) {
    final number = UsageText.tabular.copyWith(color: AppColors.textMuted);
    Widget cell(String text, [double width = _Columns.number]) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: number,
      ),
    );
    String count(int n) => n == 0 ? '—' : UsageFormat.tokens(n);
    final model = Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: ModelIcon(
                provider: call.provider,
                model: call.model,
                size: 12,
              ),
            ),
          ),
          TextSpan(text: call.model, style: UsageText.body),
          TextSpan(
            text:
                '  ${call.providerName ?? call.provider}'
                '${session == null ? '' : ' · $session'}',
            style: UsageText.faint,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: open || hovered ? AppColors.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            open ? Codicons.chevronDown : Codicons.chevronRight,
            size: 12,
            color: AppColors.textFaint,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: _Columns.time,
            child: Text(
              UsageFormat.when(call.at),
              maxLines: 1,
              style: UsageText.tabular.copyWith(color: AppColors.textMuted),
            ),
          ),
          SizedBox(
            width: _Columns.kind,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _tag(context),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: barColumn
                ? model
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      model,
                      UsageCallBar(
                        call: call,
                        scale: scale,
                        height: 4,
                        slop: 4,
                      ),
                    ],
                  ),
          ),
          if (barColumn)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: UsageCallBar(call: call, scale: scale),
              ),
            ),
          cell(count(call.input)),
          cell(count(call.cacheRead)),
          cell(count(call.cacheWrite)),
          cell(count(call.output)),
          if (barColumn)
            cell(UsageFormat.duration(call.firstToken), _Columns.time2),
          cell(UsageFormat.duration(call.duration), _Columns.time2),
          cell(UsageFormat.speed(call.speed, unit: false), _Columns.speed),
          SizedBox(
            width: 18,
            child: Align(
              alignment: Alignment.centerRight,
              child: _marks(context),
            ),
          ),
          SizedBox(
            width: _Columns.total,
            child: Text(
              UsageFormat.tokens(call.total),
              textAlign: TextAlign.right,
              style: UsageText.tabular.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: _Columns.cost,
            child: Text(
              _cost ?? '—',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: UsageText.tabular.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failed = call.failed;
    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: _wide(context, hovered),
            ),
          ),
          if (open) UsageCallDetail(call: call, ledger: ledger),
        ],
      );
    }
    final facts = [
      '${l10n.ustatTokenInput} ${UsageFormat.tokens(call.input)}',
      if (call.cacheRead > 0)
        '${l10n.ustatTokenCacheRead} ${UsageFormat.tokens(call.cacheRead)}',
      if (call.cacheWrite > 0)
        '${l10n.ustatTokenCacheWrite} ${UsageFormat.tokens(call.cacheWrite)}',
      '${l10n.ustatTokenOutput} ${UsageFormat.tokens(call.output)}',
      if (call.firstToken case final first?)
        'TTFT ${UsageFormat.duration(first)}',
      UsageFormat.duration(call.duration),
      if (call.speed case final speed?) UsageFormat.speed(speed),
      ?_cost,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: open || hovered ? AppColors.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        open ? Codicons.chevronDown : Codicons.chevronRight,
                        size: 12,
                        color: AppColors.textFaint,
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 78,
                        child: Text(
                          UsageFormat.when(call.at),
                          style: UsageText.tabular.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      UsageClassTag(
                        call.requestClass,
                        text: call.requestClass.agent
                            ? call.agentType ??
                                  UsageFormat.ofClass(
                                    context,
                                    call.requestClass,
                                  )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      ModelIcon(
                        provider: call.provider,
                        model: call.model,
                        size: 12,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: call.model, style: UsageText.body),
                              TextSpan(
                                text:
                                    '  ${call.providerName ?? call.provider}'
                                    '${session == null ? '' : ' · $session'}',
                                style: UsageText.faint,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (call.traceId != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: IdeHover(
                            message: l10n.ustatTraceKept,
                            child: Icon(
                              Codicons.debugAlt,
                              size: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                      if (failed)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Codicons.error,
                            size: 12,
                            color: UsagePalette.error,
                          ),
                        ),
                      Text(
                        UsageFormat.tokens(call.total),
                        style: UsageText.tabular.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Padding(
                    padding: const EdgeInsets.only(left: 16 + 78),
                    child: Text(
                      failed
                          ? '${call.status} · ${call.error ?? ''}'
                          : facts.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: failed
                          ? UsageText.faint.copyWith(color: UsagePalette.error)
                          : UsageText.faint.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                    ),
                  ),
                  if (!failed)
                    Padding(
                      padding: const EdgeInsets.only(left: 16 + 78, top: 3),
                      child: UsageCallBar(call: call, scale: scale, height: 4),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (open) UsageCallDetail(call: call, ledger: ledger),
      ],
    );
  }
}

/// All that is kept of a call: when and what it asked, who asked, how it
/// was answered; what filled its context; the tools'.
class UsageCallDetail extends StatelessWidget {
  const UsageCallDetail({super.key, required this.call, this.ledger});

  final UsageCall call;
  final UsageLedger? ledger;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final context0 = call.context;
    String? ms(Duration? d) => d == null ? null : UsageFormat.duration(d);
    final facts = <(String, String?)>[
      (l10n.ustatFieldTime, call.at.toLocal().toString().substring(0, 23)),
      (
        l10n.ustatFieldStatus,
        '${call.status}${call.stopReason == null ? '' : ' · ${call.stopReason}'}',
      ),
      (
        l10n.ustatFieldUpstream,
        '${call.providerName ?? call.provider} (${call.protocol ?? '—'})',
      ),
      (
        l10n.ustatFieldModel,
        call.upstreamModel == null
            ? call.model
            : '${call.model} → ${call.upstreamModel}',
      ),
      (
        l10n.ustatFieldEffort,
        [?call.effort, if (call.fast) 'fast'].join(' · '),
      ),
      (l10n.ustatFieldClass, UsageFormat.ofClass(context, call.requestClass)),
      (l10n.ustatFieldSession, call.session),
      (l10n.ustatFieldAgent, [?call.agentType, ?call.agentId].join(' · ')),
      (l10n.ustatFieldTask, call.task),
      (l10n.ustatFieldAccount, call.account),
      (l10n.ustatFieldUpstreamLatency, ms(call.headers)),
      (l10n.ustatFieldFirstToken, ms(call.firstToken)),
      (l10n.ustatFieldDuration, ms(call.duration)),
      (
        l10n.ustatFieldSpeed,
        call.speed == null ? null : '${call.speed!.toStringAsFixed(1)} tok/s',
      ),
      (
        l10n.ustatCost,
        switch (UsagePrices.current.priceOf(call)) {
          final price? => UsagePrices.money(price.cost(call), price.currency),
          null => null,
        },
      ),
      (l10n.ustatTokenInput, UsageFormat.count(call.input)),
      (l10n.ustatTokenCacheRead, UsageFormat.count(call.cacheRead)),
      (l10n.ustatTokenCacheWrite, UsageFormat.count(call.cacheWrite)),
      (l10n.ustatTokenOutput, UsageFormat.count(call.output)),
      if (call.reasoning > 0)
        (l10n.ustatTokenReasoning, UsageFormat.count(call.reasoning)),
      (
        l10n.ustatFieldMessages,
        '${call.messages} · ${l10n.ustatFieldTools} ${call.toolCount}',
      ),
      (
        l10n.ustatFieldBytes,
        '${UsageFormat.bytes(call.requestBytes)} ↑  ${UsageFormat.bytes(call.responseBytes)} ↓',
      ),
      if (call.compacted) (l10n.ustatFieldCompacted, '✓'),
      (l10n.ustatFieldError, call.error),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 4, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.partBorder, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 560 ? 2 : 1;
              final width =
                  (constraints.maxWidth - 24 * (columns - 1)) / columns;
              return Wrap(
                spacing: 24,
                runSpacing: 3,
                children: [
                  for (final (label, value) in facts)
                    if (value != null && value.isNotEmpty)
                      SizedBox(
                        width: width,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 92,
                              child: Text(label, style: UsageText.faint),
                            ),
                            Expanded(
                              child: SelectableText(
                                value,
                                style: UsageText.tabular.copyWith(
                                  color: label == l10n.ustatFieldError
                                      ? UsagePalette.error
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              );
            },
          ),
          if (context0 != null && context0.total > 0) ...[
            const SizedBox(height: 12),
            Text(l10n.ustatContextMakeup, style: UsageText.label),
            const SizedBox(height: 6),
            UsageContextBreakdown(call: call, folded: true),
          ],
          if (call.traceId != null) ...[
            const SizedBox(height: 12),
            Text(l10n.ustatTraceTitle, style: UsageText.label),
            const SizedBox(height: 6),
            UsageTraceView(call: call, ledger: ledger),
          ],
          if (call.toolResults.isNotEmpty ||
              call.toolCalls.isNotEmpty ||
              call.toolTimes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(:key, :value) in call.toolCalls.entries)
                  _Pill('${l10n.ustatToolCalled} $key ×$value'),
                for (final MapEntry(:key, :value) in call.toolResults.entries)
                  _Pill(
                    '$key ${l10n.ustatToolResult} ≈${UsageFormat.tokens(value)}',
                  ),
                for (final MapEntry(:key, :value) in call.toolTimes.entries)
                  _Pill(
                    '$key ${UsageFormat.duration(Duration(milliseconds: value))}',
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: IdeHover(
              message: l10n.ustatCopyJson,
              child: HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: () => unawaited(
                    Clipboard.setData(
                      ClipboardData(
                        text: const JsonEncoder.withIndent('  ')
                            .convert(call.toJson()),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Codicons.copy,
                        size: 12,
                        color: hovered ? AppColors.text : AppColors.textFaint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'JSON',
                        style: UsageText.faint.copyWith(
                          color: hovered ? AppColors.text : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.hover,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(text, style: UsageText.faint),
  );
}

/// A call's tokens along one bar, in the context chart's order (cache
/// read, input, cache write, output): as long as its total is of [scale],
/// the largest call's; a hover reads each.
class UsageCallBar extends StatelessWidget {
  const UsageCallBar({
    super.key,
    required this.call,
    required this.scale,
    this.height = 6,
    this.slop = 8,
  });

  final UsageCall call;
  final int scale;
  final double height;

  /// Hoverable above and below it, all told: a bar is thin.
  final double slop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final parts = [
      (call.cacheRead, UsagePalette.cacheRead, l10n.ustatTokenCacheRead),
      (call.input, UsagePalette.input, l10n.ustatTokenInput),
      (call.cacheWrite, UsagePalette.cacheWrite, l10n.ustatTokenCacheWrite),
      (call.output, UsagePalette.output, l10n.ustatTokenOutput),
    ];
    final total = call.total;
    if (total <= 0) return SizedBox(height: height);
    final number = UsageText.tabular.copyWith(fontWeight: FontWeight.w600);
    final faint = UsageText.faint.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final price = UsagePrices.current.priceOf(call);
    return IdeHover(
      followMouse: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (price != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${l10n.ustatCost}  '
                '${UsagePrices.money(price.cost(call), price.currency)}',
                style: number,
              ),
            ),
          for (final (value, color, label) in parts)
            if (value > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    child: Text(label, style: UsageText.muted),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      UsageFormat.tokens(value),
                      textAlign: TextAlign.right,
                      style: number,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      UsageFormat.percent(value / total),
                      textAlign: TextAlign.right,
                      style: faint,
                    ),
                  ),
                ],
              ),
        ],
      ),
      child: SizedBox(
        height: height + slop,
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.centerLeft,
            child: UsageMiniBar(
              fraction: scale <= 0 ? 0 : total / scale,
              color: UsagePalette.cacheRead,
              width: constraints.maxWidth,
              height: height,
              segments: [
                for (final (value, color, _) in parts)
                  (value.toDouble(), color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
