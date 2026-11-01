import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../kernel/extension_switches.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../usage_prices.dart';
import '../usage_query.dart';
import '../usage_record.dart';
import 'usage_breakdown.dart';
import 'usage_charts.dart';
import 'usage_filters.dart';
import 'usage_style.dart';

/// The token kinds of a request, as its column stacks them.
List<double> _stack(UsageCall call) => [
  call.cacheRead.toDouble(),
  call.input.toDouble(),
  call.cacheWrite.toDouble(),
  call.output.toDouble(),
];

/// A conversation's context, request by request: a column each, its
/// tokens by kind (read from the cache, not cached, written to it, the
/// answer); the main agent's or a subagent's, as switched between above
/// it; a mark where it was compacted. A column picked opens what filled
/// that request's context, part by part and name by name, below.
class UsageContextSection extends StatefulWidget {
  const UsageContextSection({
    super.key,
    required this.summary,
    this.agentLabel,
    this.height = 170,
  });

  final UsageSummary summary;
  final String Function(String agent)? agentLabel;
  final double height;

  @override
  State<UsageContextSection> createState() => _UsageContextSectionState();
}

class _UsageContextSectionState extends State<UsageContextSection> {
  /// The agent looked at: '' the main one.
  String _agent = '';

  /// Its request picked; the latest while none is.
  int? _picked;

  /// Each agent's requests that had a context: the main agent's own (and
  /// its compactions), a subagent's all.
  Map<String, List<UsageCall>> get _byAgent {
    final byAgent = <String, List<UsageCall>>{};
    for (final call in widget.summary.calls) {
      if (call.failed || call.prompt <= 0) continue;
      final agent = call.agentKey;
      if (agent.isEmpty &&
          call.requestClass != UsageClass.main &&
          call.requestClass != UsageClass.compaction) {
        continue;
      }
      (byAgent[agent] ??= []).add(call);
    }
    return byAgent;
  }

  void _pick(String agent) => setState(() {
    _agent = agent;
    _picked = null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final byAgent = _byAgent;
    if (byAgent.isEmpty) return const SizedBox.shrink();
    // The main agent first, then the subagents as they started.
    final agents = byAgent.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return byAgent[a]!.first.at.compareTo(byAgent[b]!.first.at);
      });
    final agent = byAgent.containsKey(_agent) ? _agent : agents.first;
    final requests = byAgent[agent]!;
    // None picked: the latest, the context as it is now.
    final picked = (_picked ?? requests.length - 1).clamp(
      0,
      requests.length - 1,
    );
    final call = requests[picked];
    final peak = requests.fold(0, (top, c) => math.max(top, c.prompt));
    final compactions = {
      for (final (i, c) in requests.indexed)
        if (c.requestClass == UsageClass.compaction)
          i: l10n.ustatCompactedFrom(UsageFormat.tokens(c.prompt))
        else if (c.compacted)
          i: l10n.ustatCompactedAfter,
    };
    String label(String agent) => agent.isEmpty
        ? l10n.ustatMainAgent
        : (widget.agentLabel?.call(agent) ?? agent);
    final prices = UsagePrices.current;
    String? costOf(UsageCall c) => switch (prices.priceOf(c)) {
      final price? => UsagePrices.money(price.cost(c), price.currency),
      null => null,
    };
    final series = [
      (label: l10n.ustatTokenCacheRead, color: UsagePalette.cacheRead),
      (label: l10n.ustatTokenInput, color: UsagePalette.input),
      (label: l10n.ustatTokenCacheWrite, color: UsagePalette.cacheWrite),
      (label: l10n.ustatTokenOutput, color: UsagePalette.output),
    ];
    return UsageCard(
      title: l10n.ustatContextGrowth,
      subtitle: [
        l10n.ustatContextNow(UsageFormat.tokens(requests.last.prompt)),
        l10n.ustatContextPeak(UsageFormat.tokens(peak)),
        l10n.ustatRequests(requests.length),
        if (compactions.isNotEmpty)
          l10n.ustatCompactions(
            requests
                .where((c) => c.requestClass == UsageClass.compaction)
                .length,
          ),
        if (prices.costOf(requests).text case final cost?)
          '${l10n.ustatCost} $cost',
      ].join('  ·  '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (agents.length > 1) ...[
            UsageTabs<String>(
              value: agent,
              onChanged: _pick,
              tabs: [
                for (final key in agents)
                  (
                    value: key,
                    label: label(key),
                    count: '${byAgent[key]!.length}',
                    color: UsagePalette.ofClass(
                      key.isEmpty
                          ? UsageClass.main
                          : byAgent[key]!.first.requestClass,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          UsageLegend(series: series),
          const SizedBox(height: 8),
          UsageColumnChart(
            height: widget.height,
            series: series,
            format: UsageFormat.tokens,
            selected: _picked == null ? null : picked,
            marks: compactions,
            hint: l10n.ustatContextPickHint,
            selectedHint: l10n.ustatContextUnpickHint,
            // The one picked, again: none picked.
            onTapColumn: (i) =>
                setState(() => _picked = _picked == i ? null : i),
            columns: [
              for (final (i, c) in requests.indexed)
                (
                  label: UsageFormat.clock(c.at),
                  title: [
                    '#${i + 1}  ${UsageFormat.when(c.at)}',
                    c.model,
                    ?costOf(c),
                    if (c.speed case final speed?) UsageFormat.speed(speed),
                  ].join('  ·  '),
                  values: _stack(c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: UsagePalette.grid),
          const SizedBox(height: 10),
          UsageContextBreakdown(
            call: call,
            previous: picked > 0 ? requests[picked - 1] : null,
            index: picked,
            count: requests.length,
            onStep: (step) => setState(
              () => _picked = (picked + step).clamp(0, requests.length - 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// What filled [call]'s context: its parts along a bar, then each part by
/// name: the MCP servers and their tools, the skills, the built-in tools,
/// the tools' results, CLAUDE.md and the rules, the conversation's own.
/// The MCP servers, their tools and the skills each a switch, as in
/// Settings → Customize: off, the requests after go without them.
///
/// The parts are estimated from the request's text, then scaled to what
/// the upstream counted.
class UsageContextBreakdown extends StatefulWidget {
  const UsageContextBreakdown({
    super.key,
    required this.call,
    this.previous,
    this.index,
    this.count,
    this.onStep,
    this.folded = false,
  });

  final UsageCall call;

  /// Its parts by name shown only once asked for: under a call's details,
  /// where the context's own view has them already.
  final bool folded;

  /// The agent's request before it, for what it grew by.
  final UsageCall? previous;

  /// Where it is among its agent's requests; with [onStep], stepped
  /// through (−1, 1).
  final int? index;
  final int? count;
  final ValueChanged<int>? onStep;

  @override
  State<UsageContextBreakdown> createState() => _UsageContextBreakdownState();
}

class _UsageContextBreakdownState extends State<UsageContextBreakdown>
    with UsageSwitching {
  final Set<String> _open = {};
  late bool _folded = widget.folded;

  Widget _header() {
    final l10n = context.l10n;
    final call = widget.call;
    final grew = switch (widget.previous) {
      final previous? => call.prompt - previous.prompt,
      null => null,
    };
    final index = widget.index;
    final count = widget.count;
    final step = widget.onStep;
    return Row(
      children: [
        if (index != null && count != null && step != null) ...[
          UsageIconButton(
            icon: Codicons.chevronLeft,
            tooltip: l10n.ustatPreviousRequest,
            onPressed: index > 0 ? () => step(-1) : null,
          ),
          Text(
            l10n.ustatRequestOf(index + 1, count),
            style: UsageText.tabular.copyWith(fontWeight: FontWeight.w600),
          ),
          UsageIconButton(
            icon: Codicons.chevronRight,
            tooltip: l10n.ustatNextRequest,
            onPressed: index < count - 1 ? () => step(1) : null,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            [
              UsageFormat.when(call.at),
              if (call.requestClass != UsageClass.main)
                UsageFormat.ofClass(context, call.requestClass),
              call.model,
              if (UsagePrices.current.priceOf(call) case final price?)
                UsagePrices.money(price.cost(call), price.currency),
              l10n.ustatCacheHitShort(
                UsageFormat.percent(
                  call.prompt == 0 ? 0 : call.cacheRead / call.prompt,
                ),
              ),
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UsageText.faint,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          UsageFormat.tokens(call.prompt),
          style: UsageText.heading.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (grew != null) ...[
          const SizedBox(width: 6),
          Text(
            '${grew >= 0 ? '+' : ''}${UsageFormat.tokens(grew)}',
            style: UsageText.faint.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final call = widget.call;
    final makeup = call.context;
    final children = <Widget>[
      if (widget.index != null || widget.onStep != null) ...[
        _header(),
        const SizedBox(height: 10),
      ],
    ];
    if (makeup == null || makeup.total <= 0) {
      children.add(Text(l10n.ustatNoMakeup, style: UsageText.faint));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    // The estimate's parts, in the upstream's count where it gave one.
    final whole = call.prompt > 0 ? call.prompt : makeup.total;
    final scale = whole / makeup.total;
    double scaled(int tokens) => tokens * scale;
    children.add(
      UsageStackBar(
        columns: 3,
        parts: [
          for (final (key, value) in makeup.parts)
            (
              label: UsageFormat.part(context, key),
              value: scaled(value),
              color: UsagePalette.part(key),
              text: UsageFormat.tokens(scaled(value)),
            ),
        ],
      ),
    );
    final detail = makeup.detail;
    final shape = detail?.shape;
    final groups = <Widget>[
      if (shape != null) ...[
        _mcp(shape, makeup, scaled, whole),
        _skills(shape, makeup, scaled, whole),
        _named(
          title: l10n.ustatPartTools,
          color: UsagePalette.part('tools'),
          total: scaled(makeup.tools),
          whole: whole,
          rows: [
            for (final MapEntry(:key, :value) in shape.tools.entries)
              if (UsageShape.mcpTool(key) == null)
                UsageBreakdownItem(label: key, tokens: scaled(value)),
          ],
        ),
      ],
      if (detail != null && detail.results.isNotEmpty)
        _named(
          title: l10n.ustatPartToolResult,
          color: UsagePalette.part('toolResult'),
          total: scaled(makeup.toolResult),
          whole: whole,
          rows: [
            for (final MapEntry(:key, :value) in detail.results.entries)
              UsageBreakdownItem(
                label: key,
                tokens: scaled(value),
                detail: switch (detail.uses[key]) {
                  final uses? when uses > 0 => l10n.ustatToolInputs(
                    UsageFormat.tokens(scaled(uses)),
                  ),
                  _ => null,
                },
              ),
          ],
        ),
      if (shape != null && shape.memory.isNotEmpty)
        _named(
          title: l10n.ustatPartMemory,
          color: UsagePalette.part('memory'),
          total: scaled(makeup.memory),
          whole: whole,
          rows: [
            for (final MapEntry(:key, :value) in shape.memory.entries)
              UsageBreakdownItem(
                label: usageShortPath(key),
                tooltip: key,
                tokens: scaled(value),
              ),
          ],
        ),
      _named(
        title: l10n.ustatPartMessages,
        color: UsagePalette.part('messages'),
        total: scaled(makeup.messages),
        whole: whole,
        limit: 8,
        rows: [
          for (final (key, value) in makeup.messageParts)
            if (value > 0)
              UsageBreakdownItem(
                label: UsageFormat.part(context, key),
                tokens: scaled(value),
              ),
        ],
      ),
    ];
    if (_folded) {
      children.addAll([
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => GestureDetector(
              onTap: () => setState(() => _folded = false),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Codicons.chevronRight,
                    size: 12,
                    color: hovered ? AppColors.text : AppColors.textFaint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.ustatMakeupUnfold,
                    style: UsageText.muted.copyWith(
                      color: hovered ? AppColors.text : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    children.add(const SizedBox(height: 12));
    if (shape == null) {
      children
        ..add(
          Text(
            detail?.shapeId != null
                ? l10n.ustatMakeupShapeMissing
                : l10n.ustatMakeupNoDetail,
            style: UsageText.faint,
          ),
        )
        ..add(const SizedBox(height: 10));
    }
    children.add(
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680 ? 2 : 1;
          final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
          if (columns == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, group) in groups.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  group,
                ],
              ],
            );
          }
          // Two columns, each group in the shorter: as many in each.
          final left = <Widget>[], right = <Widget>[];
          for (final (i, group) in groups.indexed) {
            (i.isEven ? left : right).add(group);
          }
          Widget column(List<Widget> groups) => SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, group) in groups.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  group,
                ],
              ],
            ),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [column(left), const SizedBox(width: 16), column(right)],
          );
        },
      ),
    );
    if (switched) {
      children.addAll([const SizedBox(height: 10), const UsageSwitchedHint()]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The MCP servers: each its tools' definitions and its instructions,
  /// a switch; opened, its tools, each a switch.
  Widget _mcp(
    UsageShape shape,
    UsageContext makeup,
    double Function(int) scaled,
    int whole,
  ) {
    final l10n = context.l10n;
    // By the name Claude Code writes in the tools' names; the name as
    // configured where its instructions give it.
    final servers = <String, UsageMcpServer>{};
    final names = <String, String>{};
    for (final key in shape.mcpNotes.keys) {
      names[ExtensionSwitches.normalize(key)] = key;
    }
    UsageMcpServer of(String server) => servers[names[server] ?? server] ??= (
      tools: <String, int>{},
      deferred: const {},
      notes: 0,
    );
    for (final MapEntry(:key, :value) in shape.tools.entries) {
      final tool = UsageShape.mcpTool(key);
      if (tool == null) continue;
      of(tool.server).tools[tool.tool] = value;
    }
    for (final MapEntry(:key, :value) in shape.mcpNotes.entries) {
      final server = of(ExtensionSwitches.normalize(key));
      servers[key] = (
        tools: server.tools,
        deferred: server.deferred,
        notes: server.notes + value,
      );
    }
    if (servers.isEmpty) return const SizedBox.shrink();
    return _named(
      title: l10n.ustatPartMcp,
      color: UsagePalette.part('mcp'),
      total: scaled(makeup.mcp),
      whole: whole,
      rows: mcpRows(servers, scaled: scaled),
    );
  }

  /// The skills as listed, each a switch but a plugin's (`plugin:skill`),
  /// which Claude Code keeps on.
  Widget _skills(
    UsageShape shape,
    UsageContext makeup,
    double Function(int) scaled,
    int whole,
  ) {
    final l10n = context.l10n;
    if (shape.skills.isEmpty) return const SizedBox.shrink();
    return _named(
      title: l10n.ustatPartSkills,
      color: UsagePalette.part('skills'),
      total: scaled(makeup.skills),
      whole: whole,
      rows: skillRows({
        for (final MapEntry(:key, :value) in shape.skills.entries)
          key: (tokens: value, plugin: key.contains(':')),
      }, scaled: scaled),
    );
  }

  Widget _named({
    required String title,
    required Color color,
    required double total,
    required int whole,
    required List<UsageBreakdownItem> rows,
    int limit = 6,
  }) {
    if (rows.isEmpty && total <= 0) return const SizedBox.shrink();
    return UsageBreakdownGroup(
      key: ValueKey(title),
      title: title,
      color: color,
      total: total,
      share: whole <= 0 ? 0 : total / whole,
      rows: rows..sort((a, b) => b.tokens.compareTo(a.tokens)),
      limit: limit,
      open: _open,
      onOpen: (key) => setState(() {
        if (!_open.remove(key)) _open.add(key);
      }),
    );
  }
}
