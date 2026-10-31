import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../usage_record.dart';
import 'usage_charts.dart';
import 'usage_style.dart';

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
          ConstrainedBox(
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
  });

  /// Oldest first, as counted.
  final List<UsageCall> calls;
  final int pageSize;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          _CallRow(
            call: calls[calls.length - 1 - i],
            open: identical(_open, calls[calls.length - 1 - i]),
            session: widget.showSession
                ? widget.sessionLabel?.call(calls[calls.length - 1 - i])
                : null,
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

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.call,
    required this.open,
    required this.onTap,
    this.session,
  });

  final UsageCall call;
  final bool open;
  final String? session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failed = call.failed;
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
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
                  const SizedBox(height: 3),
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
                ],
              ),
            ),
          ),
        ),
        if (open) UsageCallDetail(call: call),
      ],
    );
  }
}

/// All that is kept of a call: when and what it asked, who asked, how it
/// was answered; what filled its context; the tools'.
class UsageCallDetail extends StatelessWidget {
  const UsageCallDetail({super.key, required this.call});

  final UsageCall call;

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
            UsageStackBar(
              height: 8,
              parts: [
                for (final (key, value) in context0.parts)
                  (
                    label: UsageFormat.part(context, key),
                    value: value.toDouble(),
                    color: UsagePalette.part(key),
                    text: '≈${UsageFormat.tokens(value)}',
                  ),
              ],
            ),
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
