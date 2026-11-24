import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_session.dart';
import '../../chat/widgets/hover_builder.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../usage_ledger.dart';
import '../usage_record.dart';
import '../usage_trajectory.dart';
import 'usage_charts.dart';
import 'usage_filters.dart';
import 'usage_style.dart';
import 'usage_trace_view.dart';

/// Turn-aware execution trajectory and step inspector inside the Usage view.
class UsageTrajectoryView extends StatefulWidget {
  const UsageTrajectoryView({
    super.key,
    required this.session,
    this.calls = const [],
    this.ledger,
  });

  final ChatSession session;
  final List<UsageCall> calls;
  final UsageLedger? ledger;

  @override
  State<UsageTrajectoryView> createState() => _UsageTrajectoryViewState();
}

enum _InspectTab { input, output, json }

class _UsageTrajectoryViewState extends State<UsageTrajectoryView> {
  final _search = TextEditingController();
  final Set<String> _collapsed = {};
  TrajectoryFilter _filter = TrajectoryFilter.all;
  String? _selected;
  _InspectTab _tab = _InspectTab.output;
  bool _copied = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Color _color(TrajectoryStatus s) => switch (s) {
    TrajectoryStatus.running => AppColors.accent,
    TrajectoryStatus.ok => UsagePalette.cacheRead,
    TrajectoryStatus.error => UsagePalette.error,
    TrajectoryStatus.denied => UsagePalette.output,
  };

  IconData _icon(TrajectoryKind k) => switch (k) {
    TrajectoryKind.thinking => Codicons.lightbulb,
    TrajectoryKind.text => Codicons.comment,
    TrajectoryKind.tool => Codicons.tools,
    TrajectoryKind.command => Codicons.terminal,
    TrajectoryKind.diff => Codicons.diff,
    TrajectoryKind.agent => Codicons.hubot,
    TrajectoryKind.plan => Codicons.checklist,
    TrajectoryKind.notice => Codicons.info,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final turns = TrajectoryBuilder.build(widget.session, calls: widget.calls);
    final q = _search.text.trim();
    final maxMs = turns.fold(
      1,
      (m, t) => math.max(m, t.worked?.inMilliseconds ?? 0),
    );
    String fLabel(TrajectoryFilter f) => switch (f) {
      TrajectoryFilter.all => l10n.ustatAll,
      TrajectoryFilter.tools => l10n.ustatTrajTools,
      TrajectoryFilter.agents => l10n.ustatClassSubagent,
      TrajectoryFilter.errors => l10n.ustatErrors,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 150,
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.hover,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Icon(Codicons.search, size: 12, color: AppColors.textFaint),
                  const SizedBox(width: 5),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: UsageText.body,
                      decoration: InputDecoration.collapsed(
                        hintText: l10n.ustatTrajSearch,
                        hintStyle: UsageText.faint,
                      ),
                    ),
                  ),
                  if (_search.text.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _search.clear()),
                      child: Icon(
                        Codicons.close,
                        size: 12,
                        color: AppColors.textFaint,
                      ),
                    ),
                ],
              ),
            ),
            UsageSegmented<TrajectoryFilter>(
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
              segments: [
                for (final f in TrajectoryFilter.values)
                  (value: f, label: fLabel(f)),
              ],
            ),
            _chip(
              _collapsed.length < turns.length
                  ? Codicons.collapseAll
                  : Codicons.expandAll,
              () => setState(() {
                _collapsed.length < turns.length
                    ? _collapsed.addAll(turns.map((t) => t.id))
                    : _collapsed.clear();
              }),
            ),
            _chip(_copied ? Codicons.check : Codicons.export, () {
              unawaited(
                Clipboard.setData(
                  ClipboardData(text: TrajectoryBuilder.exportJson(turns)),
                ),
              );
              setState(() => _copied = true);
              Timer(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            }, l10n.ustatTrajExport),
          ],
        ),
        const SizedBox(height: 10),
        if (turns.isEmpty)
          UsageEmpty(icon: Codicons.history, title: l10n.ustatTrajEmpty)
        else
          for (final t in turns.reversed)
            if ([
                  for (final s in t.steps)
                    if (s.matchesFilter(_filter) && s.matchesQuery(q)) s,
                ]
                case final vis
                when vis.isNotEmpty ||
                    (_filter == TrajectoryFilter.all &&
                        (q.isEmpty ||
                            t.prompt.toLowerCase().contains(q.toLowerCase()))))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _turnCard(t, vis, maxMs, q.isNotEmpty),
              ),
      ],
    );
  }

  Widget _turnCard(
    TrajectoryTurn t,
    List<TrajectoryStep> vis,
    int maxMs,
    bool forceOpen,
  ) {
    final open = forceOpen || !_collapsed.contains(t.id);
    final ratio = ((t.worked?.inMilliseconds ?? 0) / maxMs).clamp(0.0, 1.0);
    return UsageCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            () => setState(
              () => open ? _collapsed.add(t.id) : _collapsed.remove(t.id),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      open ? Codicons.chevronDown : Codicons.chevronRight,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '#${t.number}',
                      style: UsageText.tabular.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _color(t.status),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UsageText.body,
                      ),
                    ),
                    if (t.errorCount > 0)
                      _meta('!${t.errorCount}', UsagePalette.error),
                    if (t.usage?.totalTokens case final tok?)
                      _meta(UsageFormat.tokens(tok)),
                    if (t.worked case final d?)
                      _meta(UsageFormat.duration(d), AppColors.text),
                  ],
                ),
                if (ratio > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 2,
                      backgroundColor: UsagePalette.grid,
                      valueColor: AlwaysStoppedAnimation(_color(t.status)),
                    ),
                  ),
              ],
            ),
          ),
          if (open) ...[
            const SizedBox(height: 6),
            for (final step in vis) _step(step, 0),
            if (t.calls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final c in t.calls)
                      Text(
                        [
                          c.model,
                          if (c.firstToken case final ttft?)
                            'TTFT ${UsageFormat.duration(ttft)}',
                          UsageFormat.duration(c.duration),
                          if (c.speed case final spd?) UsageFormat.speed(spd),
                          UsageFormat.tokens(c.total),
                        ].join(' · '),
                        style: UsageText.faint,
                      ),
                  ],
                ),
              ),
            for (final c in t.calls.where((c) => c.traceId != null))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: UsageTraceView(call: c, ledger: widget.ledger),
              ),
          ],
        ],
      ),
    );
  }

  Widget _step(TrajectoryStep s, int depth) {
    final sel = _selected == s.id, open = !_collapsed.contains(s.id);
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            () => setState(() => _selected = sel ? null : s.id),
            Row(
              children: [
                if (s.children.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(
                      () =>
                          open ? _collapsed.add(s.id) : _collapsed.remove(s.id),
                    ),
                    child: Icon(
                      open ? Codicons.chevronDown : Codicons.chevronRight,
                      size: 11,
                      color: AppColors.textFaint,
                    ),
                  )
                else
                  Icon(_icon(s.kind), size: 12, color: _color(s.status)),
                const SizedBox(width: 6),
                Text(
                  s.title,
                  style: UsageText.tabular.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (s.subtitle case final sub? when sub.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UsageText.faint,
                    ),
                  ),
                ] else
                  const Spacer(),
                if (s.tokens case final tok?)
                  _meta('${UsageFormat.tokens(tok)}t'),
                if (s.duration case final d?) _meta(UsageFormat.duration(d)),
              ],
            ),
            highlight: sel,
          ),
          if (sel) _inspector(s),
          if (s.children.isNotEmpty && open)
            Container(
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: UsagePalette.grid)),
              ),
              child: Column(
                children: [for (final c in s.children) _step(c, depth + 1)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _inspector(TrajectoryStep s) {
    final l10n = context.l10n;
    final tabs = [
      if (s.input != null)
        (value: _InspectTab.input, label: l10n.ustatTokenInput),
      if (s.output != null)
        (value: _InspectTab.output, label: l10n.ustatTokenOutput),
      (value: _InspectTab.json, label: 'JSON'),
    ];
    final active = tabs.any((t) => t.value == _tab) ? _tab : tabs.first.value;
    final jsonText = const JsonEncoder.withIndent('  ').convert(s.toJson());
    final code = switch (active) {
      _InspectTab.input => s.input ?? '',
      _InspectTab.output => s.output ?? '',
      _InspectTab.json => jsonText,
    };
    final meta = [
      s.status.name,
      if (s.duration case final d?) UsageFormat.duration(d),
      if (s.tokens case final t?) '${UsageFormat.count(t)}t',
      if (s.timestamp case final at?) UsageFormat.clockSeconds(at),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 4, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.code,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UsageSegmented<_InspectTab>(
                dense: true,
                value: active,
                segments: tabs,
                onChanged: (t) => setState(() => _tab = t),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  meta,
                  style: UsageText.faint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _chip(
                Codicons.copy,
                () =>
                    unawaited(Clipboard.setData(ClipboardData(text: jsonText))),
                'JSON',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: UsagePalette.grid),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                code.trimRight(),
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: AppFonts.monoFallbacks,
                  fontSize: 11,
                  height: 1.45,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String text, [Color? c]) => Padding(
    padding: const EdgeInsets.only(left: 7),
    child: Text(text, style: UsageText.faint.copyWith(color: c)),
  );

  Widget _row(VoidCallback onTap, Widget child, {bool highlight = false}) =>
      HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (_, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: highlight || hovered
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: child,
          ),
        ),
      );

  Widget _chip(IconData icon, VoidCallback onTap, [String? label]) =>
      HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (_, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 24,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 8),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: hovered ? AppColors.text : AppColors.textMuted,
                ),
                if (label != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: UsageText.faint.copyWith(
                      color: hovered ? AppColors.text : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
