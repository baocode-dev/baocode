import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_models.dart';
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

/// Visual execution flow diagram and subagent branch swimlane view for a session.
///
/// Supports unified multi-level folding (Turns / Flow / Details), click-to-jump
/// into the conversation history via [ChatSession.revealItem], and lazy viewport
/// virtualization when [scrollController] is supplied.
class UsageTrajectoryView extends StatefulWidget {
  const UsageTrajectoryView({
    super.key,
    required this.session,
    this.calls = const [],
    this.ledger,
    this.pageSize = 20,
    this.scrollController,
    this.padding = EdgeInsets.zero,
  });

  final ChatSession session;
  final List<UsageCall> calls;
  final UsageLedger? ledger;
  final int pageSize;

  /// When provided (e.g. inside [ConversationUsageView]), turns render inside a
  /// lazy [ListView.builder] so even bulk-expanded Details mode stays fast.
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;

  @override
  State<UsageTrajectoryView> createState() => _UsageTrajectoryViewState();
}

enum _InspectTab { input, output, json }

/// Unified fold depth for the entire trajectory.
enum _FoldLevel { turns, flow, details }

sealed class _FlowStage {
  const _FlowStage();
}

final class _SingleStage extends _FlowStage {
  const _SingleStage(this.step);
  final TrajectoryStep step;
}

final class _ParallelAgentsStage extends _FlowStage {
  const _ParallelAgentsStage(this.agents);
  final List<TrajectoryStep> agents;
}

class _UsageTrajectoryViewState extends State<UsageTrajectoryView> {
  final _search = TextEditingController();

  /// Collapsed turn IDs and subagent branch IDs.
  final Set<String> _collapsed = {};
  final Set<String> _seeded = {};

  /// Manual step-detail overrides on top of [_foldLevel]:
  /// - In `turns` / `flow`: step IDs in [_expandedDetails] are open.
  /// - In `details`: step IDs NOT in [_foldedDetails] are open.
  _FoldLevel _foldLevel = _FoldLevel.flow;
  final Set<String> _expandedDetails = {};
  final Set<String> _foldedDetails = {};

  /// Step IDs whose oversized preview was explicitly expanded in full.
  final Set<String> _fullPreviews = {};

  /// Most recently interacted step (highlighted on its turn's flow minimap).
  String? _focused;

  TrajectoryFilter _filter = TrajectoryFilter.all;
  _InspectTab _tab = _InspectTab.output;
  bool _exported = false;
  String? _copiedInspector;
  Timer? _exportReset;
  Timer? _copyReset;
  late int _shown = widget.pageSize;

  Timer? _coalesce;
  DateTime? _staleSince;
  List<TrajectoryTurn> _turns = const [];
  List<({TrajectoryTurn turn, List<TrajectoryStep> steps})> _visible = const [];
  String _cachedQuery = '';
  TrajectoryFilter _cachedFilter = TrajectoryFilter.all;

  // Cached session aggregates recomputed only on turn rebuilds.
  int _totalSteps = 0;
  int _toolSteps = 0;
  int _agentSteps = 0;
  int _errorSteps = 0;
  Map<TrajectoryKind, int> _kindCounts = const {};

  static const _previewMaxChars = 1600;
  static const _previewMaxLines = 18;
  static const _previewMaxDiffLines = 36;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _rebuildTurns();
  }

  @override
  void didUpdateWidget(UsageTrajectoryView old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
      _collapsed.clear();
      _seeded.clear();
      _expandedDetails.clear();
      _foldedDetails.clear();
      _fullPreviews.clear();
      _foldLevel = _FoldLevel.flow;
      _focused = null;
      _shown = widget.pageSize;
      _rebuildTurns();
    } else if (!identical(old.calls, widget.calls)) {
      _rebuildTurns();
    }
  }

  @override
  void dispose() {
    _coalesce?.cancel();
    _exportReset?.cancel();
    _copyReset?.cancel();
    widget.session.removeListener(_onSession);
    _search.dispose();
    super.dispose();
  }

  /// Coalesces live streaming deltas (max 1 rebuild / 250ms, capped at 1s).
  void _onSession() {
    final now = DateTime.now();
    final since = _staleSince ??= now;
    _coalesce?.cancel();
    if (now.difference(since) >= const Duration(seconds: 1)) {
      _coalesce = null;
      if (mounted) setState(_rebuildTurns);
      return;
    }
    _coalesce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(_rebuildTurns);
    });
  }

  void _rebuildTurns() {
    _staleSince = null;
    _turns = TrajectoryBuilder.build(widget.session, calls: widget.calls);
    var total = 0, tools = 0, agents = 0, errors = 0;
    final kinds = <TrajectoryKind, int>{};
    void walk(List<TrajectoryStep> list) {
      for (final s in list) {
        total++;
        kinds[s.kind] = (kinds[s.kind] ?? 0) + 1;
        if (s.kind == TrajectoryKind.tool ||
            s.kind == TrajectoryKind.command ||
            s.kind == TrajectoryKind.diff) {
          tools++;
        }
        if (s.kind == TrajectoryKind.agent) agents++;
        if (s.isError) errors++;
        if (s.children.isNotEmpty) walk(s.children);
      }
    }

    for (final t in _turns) {
      walk(t.steps);
    }
    _totalSteps = total;
    _toolSteps = tools;
    _agentSteps = agents;
    _errorSteps = errors;
    _kindCounts = kinds;

    // For long sessions in default Flow mode, collapse older turns initially.
    if (_foldLevel == _FoldLevel.flow && _turns.length > 3) {
      for (var i = 0; i < _turns.length - 1; i++) {
        final id = _turns[i].id;
        if (_seeded.add(id)) _collapsed.add(id);
      }
      _seeded.add(_turns.last.id);
    } else if (_foldLevel == _FoldLevel.turns) {
      for (final t in _turns) {
        if (_seeded.add(t.id)) _collapsed.add(t.id);
      }
    }
    _refilter();
  }

  void _refilter() {
    final q = _search.text.trim().toLowerCase();
    _cachedQuery = q;
    _cachedFilter = _filter;
    if (_filter == TrajectoryFilter.all && q.isEmpty) {
      _visible = [for (final t in _turns.reversed) (turn: t, steps: t.steps)];
      return;
    }
    _visible = [
      for (final t in _turns.reversed)
        if ([for (final s in t.steps) ?s.filtered(_filter, q)] case final vis
            when vis.isNotEmpty ||
                (_filter == TrajectoryFilter.all &&
                    t.prompt.toLowerCase().contains(q)))
          (turn: t, steps: vis),
    ];
  }

  bool _isDetailOpen(TrajectoryStep s) {
    if (!s.hasInput && !s.hasOutput) return _expandedDetails.contains(s.id);
    return switch (_foldLevel) {
      _FoldLevel.details => !_foldedDetails.contains(s.id),
      _FoldLevel.turns || _FoldLevel.flow => _expandedDetails.contains(s.id),
    };
  }

  void _setFoldLevel(_FoldLevel level) => setState(() {
    _foldLevel = level;
    _expandedDetails.clear();
    _foldedDetails.clear();
    switch (level) {
      case _FoldLevel.turns:
        _collapsed
          ..clear()
          ..addAll(_turns.map((t) => t.id));
      case _FoldLevel.flow:
      case _FoldLevel.details:
        _collapsed.clear();
    }
  });

  void _toggleStepDetail(TrajectoryStep s, {bool reveal = true}) {
    final open = _isDetailOpen(s);
    setState(() {
      if (_foldLevel == _FoldLevel.details) {
        if (open) {
          _foldedDetails.add(s.id);
        } else {
          _foldedDetails.remove(s.id);
        }
      } else {
        if (open) {
          _expandedDetails.remove(s.id);
        } else {
          _expandedDetails.add(s.id);
        }
      }
      _focused = open ? (_focused == s.id ? null : _focused) : s.id;
    });
    if (reveal) _revealIndex(s.itemIndex);
  }

  void _closeStepDetail(TrajectoryStep s) => setState(() {
    if (_foldLevel == _FoldLevel.details) {
      _foldedDetails.add(s.id);
    } else {
      _expandedDetails.remove(s.id);
    }
    if (_focused == s.id) _focused = null;
  });

  void _toggleTurnDetails(TrajectoryTurn t, List<TrajectoryStep> vis) {
    final ids = <String>[];
    void collect(List<TrajectoryStep> list) {
      for (final s in list) {
        ids.add(s.id);
        if (s.children.isNotEmpty) collect(s.children);
      }
    }

    collect(vis);
    if (ids.isEmpty) return;
    final allOpen = vis.every((s) => _allSubtreeDetailsOpen(s));
    setState(() {
      _collapsed.remove(t.id);
      if (_foldLevel == _FoldLevel.details) {
        if (allOpen) {
          _foldedDetails.addAll(ids);
        } else {
          _foldedDetails.removeAll(ids);
        }
      } else {
        if (allOpen) {
          _expandedDetails.removeAll(ids);
        } else {
          _expandedDetails.addAll(ids);
        }
      }
    });
  }

  bool _allSubtreeDetailsOpen(TrajectoryStep s) =>
      _isDetailOpen(s) && s.children.every(_allSubtreeDetailsOpen);

  bool _anySubtreeDetailOpen(List<TrajectoryStep> list) {
    for (final s in list) {
      if (_isDetailOpen(s) || _anySubtreeDetailOpen(s.children)) return true;
    }
    return false;
  }

  void _revealIndex(int? index) {
    if (index == null) return;
    widget.session.revealItem(index);
  }

  /// Groups consecutive subagent steps into parallel fan-out/fan-in stages.
  static List<_FlowStage> _groupStages(List<TrajectoryStep> steps) {
    final out = <_FlowStage>[];
    var i = 0;
    while (i < steps.length) {
      if (steps[i].kind == TrajectoryKind.agent) {
        var j = i + 1;
        while (j < steps.length && steps[j].kind == TrajectoryKind.agent) {
          j++;
        }
        if (j - i >= 2) {
          out.add(_ParallelAgentsStage(steps.sublist(i, j)));
        } else {
          out.add(_SingleStage(steps[i]));
        }
        i = j;
      } else {
        out.add(_SingleStage(steps[i]));
        i++;
      }
    }
    return out;
  }

  List<TrajectoryStep> _openStepsIn(List<TrajectoryStep> list) {
    final out = <TrajectoryStep>[];
    void walk(List<TrajectoryStep> steps) {
      for (final s in steps) {
        if (_isDetailOpen(s)) out.add(s);
        if (s.children.isNotEmpty) walk(s.children);
      }
    }

    walk(list);
    return out;
  }

  static bool _hasSubtreeError(TrajectoryStep s) =>
      s.isError || s.children.any(_hasSubtreeError);

  static int _maxStepMs(List<TrajectoryStep> list) {
    var top = 0;
    for (final s in list) {
      final ms = s.duration?.inMilliseconds ?? 0;
      if (ms > top) top = ms;
      final childMax = _maxStepMs(s.children);
      if (childMax > top) top = childMax;
    }
    return top;
  }

  Color _statusColor(TrajectoryStatus s) => switch (s) {
    TrajectoryStatus.running => AppColors.accent,
    TrajectoryStatus.ok => UsagePalette.cacheRead,
    TrajectoryStatus.error => UsagePalette.error,
    TrajectoryStatus.denied => UsagePalette.output,
  };

  Color _kindColor(TrajectoryKind k, [ToolKind? toolKind]) => switch (k) {
    TrajectoryKind.thinking => UsagePalette.fees,
    TrajectoryKind.text => AppColors.textMuted,
    TrajectoryKind.tool => switch (toolKind) {
      ToolKind.edit => UsagePalette.cacheRead,
      ToolKind.mcp => UsagePalette.series(5),
      ToolKind.agent => UsagePalette.cacheWrite,
      _ => UsagePalette.input,
    },
    TrajectoryKind.command => UsagePalette.output,
    TrajectoryKind.diff => UsagePalette.cacheRead,
    TrajectoryKind.agent => UsagePalette.cacheWrite,
    TrajectoryKind.plan => UsagePalette.series(5),
    TrajectoryKind.notice => AppColors.textMuted,
  };

  Color _stepAccent(TrajectoryStep s) => switch (s.status) {
    TrajectoryStatus.error => UsagePalette.error,
    TrajectoryStatus.denied => UsagePalette.output,
    TrajectoryStatus.running => AppColors.accent,
    TrajectoryStatus.ok => _kindColor(s.kind, s.toolKind),
  };

  IconData _stepIcon(TrajectoryStep s) => switch (s.kind) {
    TrajectoryKind.thinking => Codicons.lightbulb,
    TrajectoryKind.text => Codicons.commentDiscussion,
    TrajectoryKind.command => Codicons.terminal,
    TrajectoryKind.diff => Codicons.diff,
    TrajectoryKind.agent => Codicons.hubot,
    TrajectoryKind.plan => Codicons.checklist,
    TrajectoryKind.notice =>
      s.status == TrajectoryStatus.error ? Codicons.error : Codicons.info,
    TrajectoryKind.tool => switch (s.toolKind) {
      ToolKind.read => Codicons.file,
      ToolKind.grep || ToolKind.search => Codicons.search,
      ToolKind.listDir => Codicons.folder,
      ToolKind.edit => Codicons.edit,
      ToolKind.command => Codicons.terminal,
      ToolKind.web => Codicons.globe,
      ToolKind.agent => Codicons.hubot,
      ToolKind.mcp => Codicons.plug,
      ToolKind.todo => Codicons.checklist,
      ToolKind.message => Codicons.mail,
      ToolKind.question => Codicons.question,
      ToolKind.goal => Codicons.target,
      ToolKind.browser => Codicons.browser,
      ToolKind.image => Codicons.fileMedia,
      ToolKind.other || null => Codicons.tools,
    },
  };

  String _kindLabel(AppLocalizations l10n, TrajectoryKind k) => switch (k) {
    TrajectoryKind.thinking => l10n.ustatTrajThinking,
    TrajectoryKind.tool => l10n.ustatTrajTools,
    TrajectoryKind.command => l10n.ustatTrajCommand,
    TrajectoryKind.diff => l10n.ustatTrajDiff,
    TrajectoryKind.agent => l10n.ustatClassSubagent,
    TrajectoryKind.text => l10n.ustatPartAssistant,
    TrajectoryKind.plan => l10n.ustatTrajPlan,
    TrajectoryKind.notice => l10n.ustatTrajNotice,
  };

  String _stepTitle(AppLocalizations l10n, TrajectoryStep s) => switch (s) {
    TrajectoryStep(kind: TrajectoryKind.thinking, title: 'Thinking') =>
      l10n.ustatTrajThinking,
    TrajectoryStep(kind: TrajectoryKind.text, title: 'Assistant') =>
      l10n.ustatTrajAssistant,
    TrajectoryStep(kind: TrajectoryKind.text, title: 'Queued') =>
      l10n.ustatTrajQueued,
    TrajectoryStep(kind: TrajectoryKind.agent, title: 'Subagent') =>
      l10n.ustatClassSubagent,
    _ => s.title,
  };

  int _filterCount(TrajectoryFilter f) => switch (f) {
    TrajectoryFilter.all => _totalSteps,
    TrajectoryFilter.tools => _toolSteps,
    TrajectoryFilter.agents => _agentSteps,
    TrajectoryFilter.errors => _errorSteps,
  };

  void _selectStepFromRibbon(TrajectoryTurn turn, TrajectoryStep step) {
    final open = _isDetailOpen(step);
    setState(() {
      _collapsed.remove(turn.id);
      if (_foldLevel == _FoldLevel.details) {
        if (open) {
          _foldedDetails.add(step.id);
        } else {
          _foldedDetails.remove(step.id);
        }
      } else {
        if (open) {
          _expandedDetails.remove(step.id);
        } else {
          _expandedDetails.add(step.id);
        }
      }
      _focused = open ? (_focused == step.id ? null : _focused) : step.id;
    });
    _revealIndex(step.itemIndex ?? turn.itemIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final q = _search.text.trim().toLowerCase();
    if (q != _cachedQuery || _filter != _cachedFilter) _refilter();
    final filtering = q.isNotEmpty || _filter != TrajectoryFilter.all;
    final shownCount = math.min(_visible.length, _shown);
    final remaining = _visible.length - shownCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final narrow = width < 400;
        final canParallel = width >= 520;

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(l10n, narrow: narrow),
            if (_turns.isNotEmpty && _kindCounts.isNotEmpty) _legend(l10n),
            const SizedBox(height: 10),
          ],
        );

        Widget emptyOrList() {
          if (_turns.isEmpty) {
            return UsageEmpty(
              icon: Codicons.history,
              title: l10n.ustatTrajEmpty,
            );
          }
          if (_visible.isEmpty) {
            return UsageEmpty(
              icon: Codicons.filter,
              title: l10n.ustatTrajNoMatches,
              action: _actionChip(
                Codicons.clearAll,
                () => setState(() {
                  _search.clear();
                  _filter = TrajectoryFilter.all;
                  _refilter();
                }),
                label: l10n.ustatResetFilters,
              ),
            );
          }
          return const SizedBox.shrink();
        }

        // Virtualized ListView.builder when hosted with a scrollController.
        if (widget.scrollController case final controller?) {
          if (_turns.isEmpty || _visible.isEmpty) {
            return ListView(
              controller: controller,
              padding: widget.padding,
              children: [header, emptyOrList()],
            );
          }
          final itemCount = 1 + shownCount + (remaining > 0 ? 1 : 0);
          return ListView.builder(
            controller: controller,
            padding: widget.padding,
            addAutomaticKeepAlives: false,
            itemCount: itemCount,
            itemBuilder: (_, index) {
              if (index == 0) return header;
              final turnIdx = index - 1;
              if (turnIdx < shownCount) {
                final entry = _visible[turnIdx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _turnCard(
                    entry.turn,
                    entry.steps,
                    filtering,
                    narrow: narrow,
                    canParallel: canParallel,
                  ),
                );
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: _actionChip(
                  Codicons.chevronDown,
                  () => setState(() => _shown = _visible.length),
                  label: l10n.ustatShowAll(remaining),
                ),
              );
            },
          );
        }

        // Standalone non-scrollable layout (e.g. inside SingleChildScrollView).
        return Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (_turns.isEmpty || _visible.isEmpty)
                emptyOrList()
              else ...[
                for (final entry in _visible.take(shownCount))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _turnCard(
                      entry.turn,
                      entry.steps,
                      filtering,
                      narrow: narrow,
                      canParallel: canParallel,
                    ),
                  ),
                if (remaining > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _actionChip(
                      Codicons.chevronDown,
                      () => setState(() => _shown = _visible.length),
                      label: l10n.ustatShowAll(remaining),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar(AppLocalizations l10n, {required bool narrow}) {
    String fLabel(TrajectoryFilter f) => switch (f) {
      TrajectoryFilter.all => l10n.ustatAll,
      TrajectoryFilter.tools => l10n.ustatTrajTools,
      TrajectoryFilter.agents => l10n.ustatClassSubagent,
      TrajectoryFilter.errors => l10n.ustatErrors,
    };

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: narrow ? double.infinity : 156,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
          ),
          child: Row(
            children: [
              Icon(Codicons.search, size: 12, color: AppColors.textFaint),
              const SizedBox(width: 5),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(_refilter),
                  style: UsageText.body,
                  decoration: InputDecoration.collapsed(
                    hintText: l10n.ustatTrajSearch,
                    hintStyle: UsageText.faint,
                  ),
                ),
              ),
              if (_search.text.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _search.clear();
                    _refilter();
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Codicons.close,
                      size: 12,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _FilterSegmented(
            value: _filter,
            onChanged: (f) => setState(() {
              _filter = f;
              _refilter();
            }),
            segments: [
              for (final f in TrajectoryFilter.values)
                (
                  value: f,
                  label: fLabel(f),
                  count: _filterCount(f),
                  alert: f == TrajectoryFilter.errors && _errorSteps > 0,
                ),
            ],
          ),
        ),
        if (_turns.isNotEmpty)
          UsageSegmented<_FoldLevel>(
            value: _foldLevel,
            onChanged: _setFoldLevel,
            segments: [
              (value: _FoldLevel.turns, label: l10n.ustatTrajFoldTurns),
              (value: _FoldLevel.flow, label: l10n.ustatTrajFoldFlow),
              (value: _FoldLevel.details, label: l10n.ustatTrajFoldDetails),
            ],
          ),
        _actionChip(
          _exported ? Codicons.check : Codicons.export,
          () {
            unawaited(
              Clipboard.setData(
                ClipboardData(text: TrajectoryBuilder.exportJson(_turns)),
              ),
            );
            _exportReset?.cancel();
            setState(() => _exported = true);
            _exportReset = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _exported = false);
            });
          },
          label: l10n.ustatTrajExport,
          active: _exported,
        ),
      ],
    );
  }

  Widget _legend(AppLocalizations l10n) {
    const order = [
      TrajectoryKind.thinking,
      TrajectoryKind.tool,
      TrajectoryKind.command,
      TrajectoryKind.diff,
      TrajectoryKind.agent,
      TrajectoryKind.text,
      TrajectoryKind.plan,
    ];
    final series = <UsageSeries>[];
    final values = <String>[];
    for (final k in order) {
      final count = _kindCounts[k] ?? 0;
      if (count == 0) continue;
      series.add((label: _kindLabel(l10n, k), color: _kindColor(k)));
      values.add('$count');
    }
    if (series.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
      child: UsageLegend(series: series, values: values),
    );
  }

  Widget _turnCard(
    TrajectoryTurn t,
    List<TrajectoryStep> vis,
    bool forceOpen, {
    required bool narrow,
    required bool canParallel,
  }) {
    final l10n = context.l10n;
    final open = forceOpen || !_collapsed.contains(t.id);
    final statusColor = _statusColor(t.status);
    final tokens = t.effectiveTokens;
    final startedAt = t.effectiveStartedAt;
    final duration = t.effectiveDuration;
    final maxStepMs = math.max(
      duration?.inMilliseconds ?? 0,
      _maxStepMs(t.steps),
    );
    final anyOpen = open && _anySubtreeDetailOpen(vis);

    return UsageCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _interactiveRow(
            onTap: () {
              setState(
                () => open ? _collapsed.add(t.id) : _collapsed.remove(t.id),
              );
              _revealIndex(t.itemIndex);
            },
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      open ? Codicons.chevronDown : Codicons.chevronRight,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    _turnBadge(t.number, statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UsageText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (t.errorCount > 0) ...[
                      const SizedBox(width: 6),
                      _errorCountPill(t.errorCount),
                    ],
                    if (!narrow && startedAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        UsageFormat.when(startedAt),
                        style: UsageText.faint.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (!narrow && tokens != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${UsageFormat.tokens(tokens)} tok',
                        style: UsageText.tabular.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (duration != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        UsageFormat.duration(duration),
                        style: UsageText.tabular.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                if (t.steps.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.only(left: 17),
                    child: _TurnFlowStrip(
                      steps: t.steps,
                      selectedId: _focused,
                      colorOf: _stepAccent,
                      onSelect: (step) => _selectStepFromRibbon(t, step),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 17),
                  child: Row(
                    children: [
                      Expanded(
                        child: _turnMetaStrip(
                          l10n,
                          t,
                          startedAt: narrow ? startedAt : null,
                          showTokens: narrow && tokens != null,
                          tokens: tokens,
                        ),
                      ),
                      if (open && vis.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _inlineTextToggle(
                          icon: anyOpen
                              ? Codicons.collapseAll
                              : Codicons.expandAll,
                          label: anyOpen
                              ? l10n.ustatTrajCollapseAll
                              : l10n.ustatTrajExpandAll,
                          onTap: () => _toggleTurnDetails(t, vis),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (open && vis.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 10),
              height: 1,
              color: UsagePalette.grid,
            ),
            _flowGraph(
              l10n,
              vis,
              turnStart: startedAt,
              maxStepMs: maxStepMs,
              forceOpen: forceOpen,
              narrow: narrow,
              canParallel: canParallel,
            ),
          ],
        ],
      ),
    );
  }

  /// Main visual execution flow diagram with directional arrows and
  /// fork/join subagent swimlanes.
  Widget _flowGraph(
    AppLocalizations l10n,
    List<TrajectoryStep> steps, {
    required DateTime? turnStart,
    required int maxStepMs,
    required bool forceOpen,
    required bool narrow,
    required bool canParallel,
  }) {
    final stages = _groupStages(steps);
    // Aligns with main node icon center (1px border + 8px pad + 10px half-icon).
    const spineX = 19.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0)
            _flowEdgeBetween(
              prev: stages[i - 1],
              next: stages[i],
              spineX: spineX,
            ),
          switch (stages[i]) {
            _SingleStage(:final step) when step.kind == TrajectoryKind.agent =>
              _singleSubagentBranch(
                l10n,
                step,
                spineX: spineX,
                hasNext: i < stages.length - 1,
                turnStart: turnStart,
                maxStepMs: maxStepMs,
                forceOpen: forceOpen,
                narrow: narrow,
              ),
            _SingleStage(:final step) => _mainFlowNode(
              l10n,
              step,
              turnStart: turnStart,
              maxStepMs: maxStepMs,
              narrow: narrow,
            ),
            _ParallelAgentsStage(:final agents) => _parallelSubagentFork(
              l10n,
              agents,
              spineX: spineX,
              hasNext: i < stages.length - 1,
              turnStart: turnStart,
              maxStepMs: maxStepMs,
              forceOpen: forceOpen,
              narrow: narrow,
              canParallel: canParallel,
            ),
          },
        ],
      ],
    );
  }

  Color get _edgeColor => AppColors.textFaint.withValues(alpha: 0.45);

  static DateTime? _stageEnd(_FlowStage stage) => switch (stage) {
    _SingleStage(:final step) => step.endedAt,
    _ParallelAgentsStage(:final agents) => agents.fold<DateTime?>(null, (m, a) {
      final end = a.endedAt;
      if (end == null) return m;
      return m == null || end.isAfter(m) ? end : m;
    }),
  };

  static DateTime? _stageStart(_FlowStage stage) => switch (stage) {
    _SingleStage(:final step) => step.timestamp,
    _ParallelAgentsStage(:final agents) => agents.fold<DateTime?>(null, (m, a) {
      final at = a.timestamp;
      if (at == null) return m;
      return m == null || at.isBefore(m) ? at : m;
    }),
  };

  Widget _flowEdgeBetween({
    required _FlowStage prev,
    required _FlowStage next,
    required double spineX,
  }) {
    // Subagent stages already draw their own top fork / bottom join connectors.
    if (prev is _ParallelAgentsStage ||
        next is _ParallelAgentsStage ||
        (prev is _SingleStage && prev.step.kind == TrajectoryKind.agent) ||
        (next is _SingleStage && next.step.kind == TrajectoryKind.agent)) {
      return const SizedBox.shrink();
    }
    final nextError = next is _SingleStage && next.step.isError;
    final prevEnd = _stageEnd(prev);
    final nextStart = _stageStart(next);
    final gap = switch ((prevEnd, nextStart)) {
      (final end?, final start?) when start.isAfter(end) => start.difference(
        end,
      ),
      _ => null,
    };
    final showGap = gap != null && gap >= const Duration(seconds: 1);
    return SizedBox(
      height: showGap ? 18 : 15,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StraightArrowPainter(
                x: spineX,
                color: nextError
                    ? UsagePalette.error.withValues(alpha: 0.78)
                    : _edgeColor,
              ),
            ),
          ),
          if (showGap)
            Positioned(
              left: spineX + 10,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+${UsageFormat.duration(gap)}',
                  style: UsageText.faint.copyWith(
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A flow node card on the main execution spine.
  Widget _mainFlowNode(
    AppLocalizations l10n,
    TrajectoryStep s, {
    required DateTime? turnStart,
    required int maxStepMs,
    required bool narrow,
  }) {
    final open = _isDetailOpen(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nodeCard(
          l10n,
          s,
          open: open,
          focused: _focused == s.id,
          maxStepMs: maxStepMs,
          narrow: narrow,
        ),
        if (open) _inspector(l10n, s, turnStart: turnStart),
      ],
    );
  }

  /// A single subagent visually forked off the main spine into its own
  /// swimlane branch and joined back into the main flow below.
  Widget _singleSubagentBranch(
    AppLocalizations l10n,
    TrajectoryStep agent, {
    required double spineX,
    required bool hasNext,
    required DateTime? turnStart,
    required int maxStepMs,
    required bool forceOpen,
    required bool narrow,
  }) {
    final hasError = _hasSubtreeError(agent);
    final branchColor = hasError ? UsagePalette.error : UsagePalette.cacheWrite;
    const laneLeft = 34.0;
    final openSteps = _openStepsIn([agent]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: CustomPaint(
            painter: _BranchForkPainter(
              spineX: spineX,
              targetX: laneLeft + 19,
              color: branchColor.withValues(alpha: 0.72),
              spineColor: _edgeColor,
            ),
          ),
        ),
        Stack(
          children: [
            Positioned(
              left: spineX - 0.75,
              top: 0,
              bottom: 0,
              width: 1.5,
              child: CustomPaint(
                painter: _DashedSpinePainter(color: _edgeColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: laneLeft),
              child: _subagentSwimlaneCard(
                l10n,
                agent,
                maxStepMs: maxStepMs,
                forceOpen: forceOpen,
                narrow: narrow,
              ),
            ),
          ],
        ),
        if (hasNext)
          SizedBox(
            height: 18,
            child: CustomPaint(
              painter: _BranchJoinPainter(
                spineX: spineX,
                sourceX: laneLeft + 19,
                color: branchColor.withValues(alpha: 0.72),
                spineColor: _edgeColor,
              ),
            ),
          ),
        for (final step in openSteps)
          _inspector(l10n, step, turnStart: turnStart),
      ],
    );
  }

  /// Two or more consecutive subagents rendered as parallel forked swimlanes
  /// (side-by-side when width allows, stacked branches when narrow).
  Widget _parallelSubagentFork(
    AppLocalizations l10n,
    List<TrajectoryStep> agents, {
    required double spineX,
    required bool hasNext,
    required DateTime? turnStart,
    required int maxStepMs,
    required bool forceOpen,
    required bool narrow,
    required bool canParallel,
  }) {
    if (!canParallel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < agents.length; i++)
            _singleSubagentBranch(
              l10n,
              agents[i],
              spineX: spineX,
              hasNext: hasNext || i < agents.length - 1,
              turnStart: turnStart,
              maxStepMs: maxStepMs,
              forceOpen: forceOpen,
              narrow: narrow,
            ),
        ],
      );
    }

    // Show up to 3 lanes side-by-side per row so each lane stays scannable.
    final rows = <List<TrajectoryStep>>[];
    for (var i = 0; i < agents.length; i += 3) {
      rows.add(agents.sublist(i, math.min(i + 3, agents.length)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++)
          _parallelSwimlaneRow(
            l10n,
            rows[r],
            spineX: spineX,
            hasNext: hasNext || r < rows.length - 1,
            turnStart: turnStart,
            maxStepMs: maxStepMs,
            forceOpen: forceOpen,
          ),
      ],
    );
  }

  Widget _parallelSwimlaneRow(
    AppLocalizations l10n,
    List<TrajectoryStep> lanes, {
    required double spineX,
    required bool hasNext,
    required DateTime? turnStart,
    required int maxStepMs,
    required bool forceOpen,
  }) {
    const gap = 8.0;
    final laneColors = [
      for (final a in lanes)
        (_hasSubtreeError(a) ? UsagePalette.error : UsagePalette.cacheWrite)
            .withValues(alpha: 0.7),
    ];
    final openSteps = _openStepsIn(lanes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: CustomPaint(
            painter: _ParallelFanOutPainter(
              spineX: spineX,
              laneCount: lanes.length,
              gap: gap,
              colors: laneColors,
            ),
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lanes.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: Stack(
                    children: [
                      if (hasNext)
                        Positioned(
                          left: 18.25,
                          top: 24,
                          bottom: 0,
                          width: 1.5,
                          child: ColoredBox(color: laneColors[i]),
                        ),
                      _subagentSwimlaneCard(
                        l10n,
                        lanes[i],
                        maxStepMs: maxStepMs,
                        forceOpen: forceOpen,
                        narrow: true,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasNext)
          SizedBox(
            height: 22,
            child: CustomPaint(
              painter: _ParallelFanInPainter(
                spineX: spineX,
                laneCount: lanes.length,
                gap: gap,
                colors: laneColors,
              ),
            ),
          ),
        for (final step in openSteps)
          _inspector(l10n, step, turnStart: turnStart),
      ],
    );
  }

  /// Dedicated visual swimlane card for a Subagent and its internal step flow.
  Widget _subagentSwimlaneCard(
    AppLocalizations l10n,
    TrajectoryStep agent, {
    required int maxStepMs,
    required bool forceOpen,
    required bool narrow,
  }) {
    final selected = _isDetailOpen(agent);
    final focused = _focused == agent.id;
    final hasChildren = agent.children.isNotEmpty;
    final open = forceOpen || !_collapsed.contains(agent.id);
    final hasError = _hasSubtreeError(agent);
    final laneColor = hasError ? UsagePalette.error : UsagePalette.cacheWrite;
    final errorCount = _countErrors(agent.children) + (agent.isError ? 1 : 0);
    final durRatio = _durationRatio(agent.duration, maxStepMs);

    final cardFill = Color.alphaBlend(
      focused
          ? AppColors.accent.withValues(alpha: 0.09)
          : laneColor.withValues(alpha: 0.055),
      UsageCard.background,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: focused || selected
              ? AppColors.accent.withValues(alpha: focused ? 0.75 : 0.45)
              : laneColor.withValues(alpha: hasError ? 0.55 : 0.28),
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (_, hovered) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleStepDetail(agent),
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
                decoration: BoxDecoration(
                  color: hovered
                      ? laneColor.withValues(alpha: 0.09)
                      : laneColor.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(8),
                    bottom: Radius.circular(hasChildren && open ? 0 : 8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _nodeIcon(
                          icon: Codicons.hubot,
                          color: laneColor,
                          size: 18,
                          iconSize: 11,
                          surface: cardFill,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _stepTitle(l10n, agent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UsageText.body.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: hasError
                                  ? UsagePalette.error
                                  : AppColors.text,
                            ),
                          ),
                        ),
                        if (errorCount > 0) ...[
                          const SizedBox(width: 5),
                          _errorCountPill(errorCount),
                        ],
                        if (agent.status == TrajectoryStatus.running) ...[
                          const SizedBox(width: 5),
                          _statusPill(l10n.ustatTrajRunning, AppColors.accent),
                        ],
                        if (hasChildren) ...[
                          const SizedBox(width: 5),
                          _branchToggle(
                            count: agent.children.length,
                            open: open,
                            color: laneColor,
                            onTap: () => setState(() {
                              if (open) {
                                _collapsed.add(agent.id);
                              } else {
                                _collapsed.remove(agent.id);
                              }
                            }),
                          ),
                        ],
                      ],
                    ),
                    if (agent.subtitle case final sub? when sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 25),
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UsageText.muted.copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                    if (agent.timestamp != null ||
                        agent.duration != null ||
                        agent.tokens != null ||
                        agent.agentModel != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (agent.timestamp case final at?) ...[
                            Text(
                              UsageFormat.clockSeconds(at),
                              style: UsageText.faint.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (agent.agentModel case final model?
                              when model.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                model,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UsageText.faint,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (agent.tokens case final tok?) ...[
                            Text(
                              '${UsageFormat.tokens(tok)} tok',
                              style: UsageText.faint.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Spacer(),
                          if (durRatio != null) ...[
                            UsageMiniBar(
                              fraction: durRatio,
                              color: laneColor,
                              width: narrow ? 32 : 42,
                              height: 4,
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (agent.duration case final d?)
                            Text(
                              UsageFormat.duration(d),
                              style: UsageText.tabular.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (agent.isError &&
                        agent.errorPreview != null &&
                        agent.errorPreview!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _inlineErrorLine(agent.errorPreview!),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (hasChildren && open) ...[
            Container(height: 1, color: laneColor.withValues(alpha: 0.20)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < agent.children.length; i++)
                    _swimlaneChildStep(
                      l10n,
                      agent.children[i],
                      isFirst: i == 0,
                      isLast: i == agent.children.length - 1,
                      railColor: laneColor.withValues(alpha: 0.42),
                      surface: cardFill,
                      narrow: narrow,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Compact connected step inside a subagent's swimlane.
  Widget _swimlaneChildStep(
    AppLocalizations l10n,
    TrajectoryStep s, {
    required bool isFirst,
    required bool isLast,
    required Color railColor,
    required Color surface,
    required bool narrow,
  }) {
    final open = _isDetailOpen(s);
    final focused = _focused == s.id;
    final accent = _stepAccent(s);
    final isCodeSub =
        s.kind == TrajectoryKind.tool || s.kind == TrajectoryKind.command;
    final displayTitle = _stepTitle(l10n, s);

    return Stack(
      children: [
        if (!isFirst)
          Positioned(
            left: 8.25,
            top: 0,
            height: 13,
            width: 1.5,
            child: ColoredBox(color: railColor),
          ),
        if (!isLast)
          Positioned(
            left: 8.25,
            top: 13,
            bottom: 0,
            width: 1.5,
            child: ColoredBox(color: railColor),
          ),
        Positioned(
          left: 0,
          top: 4,
          child: _nodeIcon(
            icon: _stepIcon(s),
            color: accent,
            size: 18,
            iconSize: 10,
            selected: focused || open,
            surface: surface,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 24, bottom: isLast ? 0 : 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _interactiveRow(
                onTap: () => _toggleStepDetail(s),
                highlight: focused,
                tint: s.isError
                    ? UsagePalette.error.withValues(alpha: 0.09)
                    : open
                    ? AppColors.accent.withValues(alpha: 0.06)
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    if (s.kind == TrajectoryKind.diff && s.fileName != null)
                      Expanded(
                        child: Text(
                          s.fileName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.uiCodeStyle(11).copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      )
                    else if (s.subtitle != null && s.subtitle!.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: narrow ? 76 : 124,
                              ),
                              child: Text(
                                displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: UsageText.body.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: s.isError
                                      ? UsagePalette.error
                                      : AppColors.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                s.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: isCodeSub
                                    ? AppFonts.uiCodeStyle(10.5)
                                          .copyWith(color: AppColors.textMuted)
                                    : UsageText.faint,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UsageText.body.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: s.isError
                                ? UsagePalette.error
                                : AppColors.text,
                          ),
                        ),
                      ),
                    if (s.kind == TrajectoryKind.diff &&
                        (s.diffAdded != null || s.diffRemoved != null)) ...[
                      const SizedBox(width: 5),
                      _diffCounts(
                        s.diffAdded ?? 0,
                        s.diffRemoved ?? 0,
                        compact: true,
                      ),
                    ],
                    if (s.status == TrajectoryStatus.error) ...[
                      const SizedBox(width: 5),
                      Icon(Codicons.error, size: 12, color: UsagePalette.error),
                    ] else if (s.status == TrajectoryStatus.denied) ...[
                      const SizedBox(width: 5),
                      _statusPill(l10n.ustatTrajDenied, UsagePalette.output),
                    ] else if (s.status == TrajectoryStatus.running) ...[
                      const SizedBox(width: 5),
                      _statusPill(l10n.ustatTrajRunning, AppColors.accent),
                    ],
                    if (s.duration case final d?) ...[
                      const SizedBox(width: 6),
                      Text(
                        UsageFormat.duration(d),
                        style: UsageText.tabular.copyWith(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ] else if (s.timestamp case final at?) ...[
                      const SizedBox(width: 6),
                      Text(
                        UsageFormat.clockSeconds(at),
                        style: UsageText.faint.copyWith(
                          fontSize: 10,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (s.isError &&
                  s.errorPreview != null &&
                  s.errorPreview!.isNotEmpty &&
                  !open)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleStepDetail(s),
                    child: _inlineErrorLine(s.errorPreview!),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Visual flow node card for non-subagent steps on the main lane.
  Widget _nodeCard(
    AppLocalizations l10n,
    TrajectoryStep s, {
    required bool open,
    required bool focused,
    required int maxStepMs,
    required bool narrow,
  }) {
    final accent = _stepAccent(s);
    final isCodeSub =
        s.kind == TrajectoryKind.tool || s.kind == TrajectoryKind.command;
    final displayTitle = _stepTitle(l10n, s);
    final durRatio = _durationRatio(s.duration, maxStepMs);

    Widget content() {
      if (s.kind == TrajectoryKind.diff && s.fileName != null) {
        return Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  s.fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.uiCodeStyle(11.5).copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (s.directory case final dir? when dir.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    dir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UsageText.faint,
                  ),
                ),
              ],
            ],
          ),
        );
      }

      final hasSub = s.subtitle != null && s.subtitle!.isNotEmpty;
      if (!hasSub) {
        return Expanded(
          child: Text(
            displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UsageText.body.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: s.isError ? UsagePalette.error : AppColors.text,
            ),
          ),
        );
      }

      return Expanded(
        child: Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: narrow ? 92 : 148),
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UsageText.body.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: s.isError ? UsagePalette.error : AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                s.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isCodeSub
                    ? AppFonts.uiCodeStyle(11)
                          .copyWith(color: AppColors.textMuted)
                    : UsageText.muted.copyWith(fontSize: 11.5),
              ),
            ),
            if (!narrow && s.detail != null && s.detail!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(s.detail!, style: UsageText.faint),
            ],
          ],
        ),
      );
    }

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (_, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleStepDetail(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(8, 6, 9, 6),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.accent.withValues(alpha: 0.11)
                : s.isError
                ? UsagePalette.error.withValues(alpha: hovered ? 0.12 : 0.08)
                : hovered
                ? AppColors.hover
                : AppColors.code.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: focused
                  ? AppColors.accent.withValues(alpha: 0.75)
                  : open
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : s.isError
                  ? UsagePalette.error.withValues(alpha: 0.55)
                  : s.status == TrajectoryStatus.running
                  ? AppColors.accent.withValues(alpha: 0.50)
                  : UsagePalette.grid,
              width: focused || s.isError ? 1.25 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _nodeIcon(
                    icon: _stepIcon(s),
                    color: accent,
                    size: 20,
                    iconSize: 11,
                    selected: focused || open,
                  ),
                  const SizedBox(width: 8),
                  content(),
                  if (s.kind == TrajectoryKind.diff &&
                      (s.diffAdded != null || s.diffRemoved != null)) ...[
                    const SizedBox(width: 6),
                    _diffCounts(s.diffAdded ?? 0, s.diffRemoved ?? 0),
                  ],
                  if (s.matchCount case final matches? when matches > 0) ...[
                    const SizedBox(width: 6),
                    _countBadge('$matches'),
                  ],
                  if (s.status == TrajectoryStatus.error) ...[
                    const SizedBox(width: 6),
                    Icon(Codicons.error, size: 12, color: UsagePalette.error),
                  ] else if (s.status == TrajectoryStatus.denied) ...[
                    const SizedBox(width: 6),
                    _statusPill(l10n.ustatTrajDenied, UsagePalette.output),
                  ] else if (s.status == TrajectoryStatus.running) ...[
                    const SizedBox(width: 6),
                    _statusPill(l10n.ustatTrajRunning, AppColors.accent),
                  ],
                  if (!narrow && s.tokens != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${UsageFormat.tokens(s.tokens!)} tok',
                      style: UsageText.faint.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (!narrow && s.timestamp != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      UsageFormat.clockSeconds(s.timestamp!),
                      style: UsageText.faint.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (durRatio != null && !narrow) ...[
                    const SizedBox(width: 8),
                    UsageMiniBar(
                      fraction: durRatio,
                      color: accent,
                      width: 36,
                      height: 4,
                    ),
                  ],
                  if (s.duration case final d?) ...[
                    const SizedBox(width: 6),
                    Text(
                      UsageFormat.duration(d),
                      style: UsageText.tabular.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ] else if (narrow && s.timestamp != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      UsageFormat.clockSeconds(s.timestamp!),
                      style: UsageText.faint.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
              if (s.isError &&
                  s.errorPreview != null &&
                  s.errorPreview!.isNotEmpty &&
                  !open) ...[
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: _inlineErrorLine(s.errorPreview!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static int _countErrors(List<TrajectoryStep> list) => list.fold(
    0,
    (n, s) => n + (s.isError ? 1 : 0) + _countErrors(s.children),
  );

  static double? _durationRatio(Duration? d, int maxMs) {
    if (d == null || maxMs <= 0) return null;
    final ms = d.inMilliseconds;
    if (ms <= 0) return null;
    return (ms / maxMs).clamp(0.06, 1.0);
  }

  Widget _inlineErrorLine(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: UsagePalette.error.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppFonts.uiCodeStyle(10.5).copyWith(color: UsagePalette.error),
    ),
  );

  Widget _inlineTextToggle({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (_, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: hovered ? AppColors.text : AppColors.textFaint,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: UsageText.faint.copyWith(
                color: hovered ? AppColors.text : AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _nodeIcon({
    required IconData icon,
    required Color color,
    required double size,
    required double iconSize,
    bool selected = false,
    Color? surface,
  }) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        color.withValues(alpha: selected ? 0.24 : 0.14),
        surface ?? AppColors.code,
      ),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Icon(icon, size: iconSize, color: color),
  );

  Widget _turnBadge(int number, Color color) => Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
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
        Text(
          '#$number',
          style: UsageText.tabular.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _errorCountPill(int count) => Container(
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: UsagePalette.error.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Codicons.error, size: 11, color: UsagePalette.error),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: UsageText.tabular.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: UsagePalette.error,
          ),
        ),
      ],
    ),
  );

  Widget _turnMetaStrip(
    AppLocalizations l10n,
    TrajectoryTurn t, {
    required DateTime? startedAt,
    required bool showTokens,
    required int? tokens,
  }) {
    final items = <Widget>[
      if (startedAt != null)
        _miniStat(Codicons.clock, UsageFormat.when(startedAt)),
      if (t.totalSteps > 0)
        _miniStat(Codicons.layers, l10n.ustatTrajSteps(t.totalSteps)),
      if (t.toolCount > 0) _miniStat(Codicons.tools, '${t.toolCount}'),
      if (t.agentCount > 0)
        _miniStat(
          Codicons.hubot,
          '${t.agentCount}',
          color: UsagePalette.cacheWrite,
        ),
      if (t.diffAdded > 0 || t.diffRemoved > 0)
        _diffCounts(t.diffAdded, t.diffRemoved, compact: true),
      if (showTokens && tokens != null)
        _miniStat(null, '${UsageFormat.tokens(tokens)} tok'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }

  Widget _miniStat(IconData? icon, String text, {Color? color}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 11, color: color ?? AppColors.textFaint),
        const SizedBox(width: 3),
      ],
      Text(
        text,
        style: UsageText.faint.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  Widget _statusPill(String label, Color color) => Container(
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(5),
    ),
    alignment: Alignment.center,
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    ),
  );

  Widget _diffCounts(int added, int removed, {bool compact = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (added > 0)
        Text(
          '+$added',
          style: UsageText.tabular.copyWith(
            fontSize: compact ? 10.5 : 11,
            fontWeight: FontWeight.w600,
            color: AppColors.added,
          ),
        ),
      if (added > 0 && removed > 0) const SizedBox(width: 4),
      if (removed > 0)
        Text(
          '-$removed',
          style: UsageText.tabular.copyWith(
            fontSize: compact ? 10.5 : 11,
            fontWeight: FontWeight.w600,
            color: AppColors.removed,
          ),
        ),
    ],
  );

  Widget _countBadge(String text) => Container(
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: AppColors.hover,
      borderRadius: BorderRadius.circular(5),
    ),
    alignment: Alignment.center,
    child: Text(
      text,
      style: UsageText.tabular.copyWith(
        fontSize: 10.5,
        color: AppColors.textMuted,
      ),
    ),
  );

  Widget _branchToggle({
    required int count,
    required bool open,
    required Color color,
    required VoidCallback onTap,
  }) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (_, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: hovered ? 0.22 : 0.13),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              open ? Codicons.chevronDown : Codicons.chevronRight,
              size: 10,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: UsageText.tabular.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static ({String text, bool truncated}) _clipPreview(String text) {
    final trimmed = text.trimRight();
    var cut = trimmed.length;
    var truncated = false;
    if (cut > _previewMaxChars) {
      cut = _previewMaxChars;
      truncated = true;
    }
    var lines = 0;
    for (var i = 0; i < cut; i++) {
      if (trimmed.codeUnitAt(i) == 10) {
        lines++;
        if (lines >= _previewMaxLines) {
          cut = i;
          truncated = true;
          break;
        }
      }
    }
    return (
      text: truncated ? trimmed.substring(0, cut) : trimmed,
      truncated: truncated,
    );
  }

  Widget _inspector(
    AppLocalizations l10n,
    TrajectoryStep s, {
    DateTime? turnStart,
  }) {
    final tabs = [
      if (s.hasInput) (value: _InspectTab.input, label: l10n.ustatTokenInput),
      if (s.hasOutput)
        (value: _InspectTab.output, label: l10n.ustatTokenOutput),
      (value: _InspectTab.json, label: 'JSON'),
    ];
    final active = tabs.any((t) => t.value == _tab) ? _tab : tabs.first.value;
    String encode() => const JsonEncoder.withIndent('  ').convert(s.toJson());
    final rawCode = switch (active) {
      _InspectTab.input => s.input ?? '',
      _InspectTab.output => s.output ?? '',
      _InspectTab.json => encode(),
    };
    final copyKey = '${s.id}:${active.name}';
    final copied = _copiedInspector == copyKey;
    final fullKey = '${s.id}:${active.name}';
    final showFull = _fullPreviews.contains(fullKey);

    final offsetLabel = switch ((turnStart, s.timestamp)) {
      (final start?, final at?) when !at.isBefore(start) =>
        '+${UsageFormat.duration(at.difference(start))}',
      _ => null,
    };
    final metaParts = [
      if (s.timestamp case final at?)
        offsetLabel == null
            ? UsageFormat.clockSeconds(at)
            : '${UsageFormat.clockSeconds(at)} ($offsetLabel)',
      if (s.duration case final d?) UsageFormat.duration(d),
      if (s.tokens case final t?) '${UsageFormat.count(t)} tok',
      if (s.agentModel case final model? when model.isNotEmpty) model,
    ];

    final showDiffLines =
        s.kind == TrajectoryKind.diff &&
        active == _InspectTab.output &&
        s.diffLines != null &&
        s.diffLines!.isNotEmpty;

    final diffLines = showDiffLines ? s.diffLines! : const <DiffLine>[];
    final diffTruncated =
        showDiffLines && !showFull && diffLines.length > _previewMaxDiffLines;
    final visibleDiffLines = diffTruncated
        ? diffLines.sublist(0, _previewMaxDiffLines)
        : diffLines;

    final clipped = showDiffLines || showFull
        ? (text: rawCode.trimRight(), truncated: false)
        : _clipPreview(rawCode);

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.code,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: s.isError
              ? UsagePalette.error.withValues(alpha: 0.45)
              : AppColors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_stepIcon(s), size: 12, color: _stepAccent(s)),
                      const SizedBox(width: 5),
                      Text(
                        _stepTitle(l10n, s),
                        style: UsageText.tabular.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  UsageSegmented<_InspectTab>(
                    dense: true,
                    value: active,
                    segments: tabs,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  if (metaParts.isNotEmpty)
                    Text(
                      metaParts.join(' · '),
                      style: UsageText.faint.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.itemIndex case final idx?) ...[
                    _actionChip(
                      Codicons.target,
                      () => _revealIndex(idx),
                      dense: true,
                    ),
                    const SizedBox(width: 4),
                  ],
                  _actionChip(
                    copied ? Codicons.check : Codicons.copy,
                    () {
                      unawaited(
                        Clipboard.setData(ClipboardData(text: rawCode)),
                      );
                      _copyReset?.cancel();
                      setState(() => _copiedInspector = copyKey);
                      _copyReset = Timer(
                        const Duration(milliseconds: 1500),
                        () {
                          if (mounted) setState(() => _copiedInspector = null);
                        },
                      );
                    },
                    label: l10n.ustatTraceCopyBody,
                    active: copied,
                    dense: true,
                  ),
                  const SizedBox(width: 4),
                  _actionChip(
                    Codicons.close,
                    () => _closeStepDetail(s),
                    dense: true,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: UsagePalette.grid),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDiffLines)
                    _diffPreview(visibleDiffLines)
                  else
                    _codePreview(
                      clipped.text,
                      commandPrompt:
                          s.kind == TrajectoryKind.command &&
                          active == _InspectTab.input,
                      errorTone: s.isError && active == _InspectTab.output,
                    ),
                  if (diffTruncated || clipped.truncated) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _actionChip(
                        Codicons.chevronDown,
                        () => setState(() => _fullPreviews.add(fullKey)),
                        label: l10n.ustatTrajShowFull,
                        dense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codePreview(
    String text, {
    required bool commandPrompt,
    required bool errorTone,
  }) {
    final base = AppFonts.uiCodeStyle(11).copyWith(
      height: 1.48,
      color: errorTone ? UsagePalette.error : AppColors.text,
    );
    if (!commandPrompt || text.isEmpty) {
      return SelectableText(text, style: base);
    }
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(
            text: r'$ ',
            style: base.copyWith(color: AppColors.textFaint),
          ),
          TextSpan(text: text, style: base),
        ],
      ),
    );
  }

  Widget _diffPreview(List<DiffLine> lines) {
    final mono = AppFonts.uiCodeStyle(11).copyWith(height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in lines)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: switch (l.type) {
              DiffLineType.added => AppColors.addedBackground,
              DiffLineType.removed => AppColors.removedBackground,
              DiffLineType.context => Colors.transparent,
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${l.lineNumber}',
                    textAlign: TextAlign.right,
                    style: mono.copyWith(
                      color: AppColors.textFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  switch (l.type) {
                    DiffLineType.added => '+',
                    DiffLineType.removed => '-',
                    DiffLineType.context => ' ',
                  },
                  style: mono.copyWith(
                    fontWeight: FontWeight.w600,
                    color: switch (l.type) {
                      DiffLineType.added => AppColors.added,
                      DiffLineType.removed => AppColors.removed,
                      DiffLineType.context => AppColors.textFaint,
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    l.text,
                    style: mono.copyWith(color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _interactiveRow({
    required VoidCallback onTap,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    bool highlight = false,
    Color? tint,
  }) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (_, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: padding,
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.accent.withValues(alpha: 0.12)
              : hovered
              ? AppColors.hover
              : (tint ?? Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
    ),
  );

  Widget _actionChip(
    IconData icon,
    VoidCallback onTap, {
    String? label,
    bool active = false,
    bool dense = false,
  }) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (_, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: dense ? 22 : 26,
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 6 : (dense ? 7 : 9),
        ),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.14)
              : hovered
              ? AppColors.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(dense ? 6 : 13),
          border: Border.all(
            color: active
                ? AppColors.accent.withValues(alpha: 0.5)
                : AppColors.border.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: active
                  ? AppColors.accent
                  : hovered
                  ? AppColors.text
                  : AppColors.textMuted,
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: UsageText.faint.copyWith(
                  color: active || hovered
                      ? AppColors.text
                      : AppColors.textMuted,
                  fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Paints a short vertical directional arrow between consecutive main-lane nodes.
class _StraightArrowPainter extends CustomPainter {
  _StraightArrowPainter({required this.x, required this.color});

  final double x;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tipY = size.height - 1.5;
    canvas.drawLine(Offset(x, 0), Offset(x, tipY - 2), stroke);
    _drawDownArrow(canvas, Offset(x, tipY), color);
  }

  @override
  bool shouldRepaint(_StraightArrowPainter old) =>
      old.x != x || old.color != color;
}

/// Paints a smooth fork curve from the main spine into a single subagent lane.
class _BranchForkPainter extends CustomPainter {
  _BranchForkPainter({
    required this.spineX,
    required this.targetX,
    required this.color,
    required this.spineColor,
  });

  final double spineX, targetX;
  final Color color, spineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final spinePaint = Paint()
      ..color = spineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(spineX, 0), Offset(spineX, size.height), spinePaint);

    final forkPaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tipY = size.height - 1.5;
    final path = Path()
      ..moveTo(spineX, 2)
      ..cubicTo(
        spineX,
        size.height * 0.6,
        targetX,
        size.height * 0.3,
        targetX,
        tipY - 2,
      );
    canvas.drawPath(path, forkPaint);
    _drawDownArrow(canvas, Offset(targetX, tipY), color);
  }

  @override
  bool shouldRepaint(_BranchForkPainter old) =>
      old.spineX != spineX ||
      old.targetX != targetX ||
      old.color != color ||
      old.spineColor != spineColor;
}

/// Paints a smooth join curve returning from a subagent lane back to main spine.
class _BranchJoinPainter extends CustomPainter {
  _BranchJoinPainter({
    required this.spineX,
    required this.sourceX,
    required this.color,
    required this.spineColor,
  });

  final double spineX, sourceX;
  final Color color, spineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final spinePaint = Paint()
      ..color = spineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final tipY = size.height - 1.5;
    canvas.drawLine(Offset(spineX, 0), Offset(spineX, tipY - 2), spinePaint);

    final joinPaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(sourceX, 0)
      ..cubicTo(
        sourceX,
        size.height * 0.65,
        spineX,
        size.height * 0.35,
        spineX,
        tipY - 2,
      );
    canvas.drawPath(path, joinPaint);
    _drawDownArrow(canvas, Offset(spineX, tipY), color);
  }

  @override
  bool shouldRepaint(_BranchJoinPainter old) =>
      old.spineX != spineX ||
      old.sourceX != sourceX ||
      old.color != color ||
      old.spineColor != spineColor;
}

/// Paints a vertical dashed spine beside an active subagent branch.
class _DashedSpinePainter extends CustomPainter {
  _DashedSpinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    for (var y = 2.0; y < size.height - 2; y += 6) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + 3, size.height - 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedSpinePainter old) => old.color != color;
}

/// Paints parallel fan-out Bezier curves from [spineX] to each swimlane column.
class _ParallelFanOutPainter extends CustomPainter {
  _ParallelFanOutPainter({
    required this.spineX,
    required this.laneCount,
    required this.gap,
    required this.colors,
  });

  final double spineX, gap;
  final int laneCount;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (laneCount <= 0 || size.width <= 0) return;
    final laneW = (size.width - gap * (laneCount - 1)) / laneCount;
    final tipY = size.height - 1.5;
    for (var i = 0; i < laneCount; i++) {
      final targetX = i * (laneW + gap) + math.min(19.0, laneW / 2);
      final color = colors[i];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(spineX, 0)
        ..cubicTo(
          spineX,
          size.height * 0.55,
          targetX,
          size.height * 0.35,
          targetX,
          tipY - 2,
        );
      canvas.drawPath(path, paint);
      _drawDownArrow(canvas, Offset(targetX, tipY), color);
    }
  }

  @override
  bool shouldRepaint(_ParallelFanOutPainter old) =>
      old.spineX != spineX ||
      old.laneCount != laneCount ||
      old.colors != colors;
}

/// Paints parallel fan-in Bezier curves converging from swimlanes back to [spineX].
class _ParallelFanInPainter extends CustomPainter {
  _ParallelFanInPainter({
    required this.spineX,
    required this.laneCount,
    required this.gap,
    required this.colors,
  });

  final double spineX, gap;
  final int laneCount;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (laneCount <= 0 || size.width <= 0) return;
    final laneW = (size.width - gap * (laneCount - 1)) / laneCount;
    final tipY = size.height - 1.5;
    for (var i = 0; i < laneCount; i++) {
      final sourceX = i * (laneW + gap) + math.min(19.0, laneW / 2);
      final color = colors[i];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(sourceX, 0)
        ..cubicTo(
          sourceX,
          size.height * 0.65,
          spineX,
          size.height * 0.45,
          spineX,
          tipY - 2,
        );
      canvas.drawPath(path, paint);
    }
    _drawDownArrow(canvas, Offset(spineX, tipY), colors.first);
  }

  @override
  bool shouldRepaint(_ParallelFanInPainter old) =>
      old.spineX != spineX ||
      old.laneCount != laneCount ||
      old.colors != colors;
}

void _drawDownArrow(Canvas canvas, Offset tip, Color color) {
  final path = Path()
    ..moveTo(tip.dx - 3.2, tip.dy - 4.2)
    ..lineTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + 3.2, tip.dy - 4.2)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

/// Segmented filter track with live per-filter tabular counts.
class _FilterSegmented extends StatelessWidget {
  const _FilterSegmented({
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final TrajectoryFilter value;
  final List<({TrajectoryFilter value, String label, int count, bool alert})>
  segments;
  final ValueChanged<TrajectoryFilter> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.hover,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final seg in segments)
          _FilterPill(
            label: seg.label,
            count: seg.count,
            alert: seg.alert,
            selected: seg.value == value,
            onTap: () => onChanged(seg.value),
          ),
      ],
    ),
  );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.alert,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool alert;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (_, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (alert) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: UsagePalette.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected || hovered
                      ? AppColors.text
                      : AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    color: alert ? UsagePalette.error : AppColors.textFaint,
                    fontSize: 10.5,
                    fontWeight: alert ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Interactive visual execution flow minimap for a turn's chronological steps.
class _TurnFlowStrip extends StatefulWidget {
  const _TurnFlowStrip({
    required this.steps,
    required this.selectedId,
    required this.colorOf,
    required this.onSelect,
  });

  final List<TrajectoryStep> steps;
  final String? selectedId;
  final Color Function(TrajectoryStep) colorOf;
  final ValueChanged<TrajectoryStep> onSelect;

  @override
  State<_TurnFlowStrip> createState() => _TurnFlowStripState();
}

class _TurnFlowStripState extends State<_TurnFlowStrip> {
  int? _hovered;

  static double _weight(TrajectoryStep s) {
    if (s.kind == TrajectoryKind.agent) {
      return 1.6 + math.min(s.children.length, 6) * 0.25;
    }
    if (s.kind == TrajectoryKind.diff) return 1.25;
    if (s.kind == TrajectoryKind.command) return 1.2;
    return 1.0;
  }

  int _selectedIndex() {
    final id = widget.selectedId;
    if (id == null) return -1;
    for (var i = 0; i < widget.steps.length; i++) {
      final s = widget.steps[i];
      if (s.id == id || _containsId(s.children, id)) return i;
    }
    return -1;
  }

  static bool _containsId(List<TrajectoryStep> list, String id) {
    for (final s in list) {
      if (s.id == id || _containsId(s.children, id)) return true;
    }
    return false;
  }

  int? _indexAt(double dx, double width) {
    final steps = widget.steps;
    if (steps.isEmpty || width <= 0) return null;
    final gap = steps.length > 28 ? 1.0 : 2.0;
    final totalGap = gap * (steps.length - 1);
    final room = math.max(1.0, width - totalGap);
    final weights = [for (final s in steps) _weight(s)];
    final totalW = weights.fold(0.0, (a, b) => a + b);
    var x = 0.0;
    for (var i = 0; i < steps.length; i++) {
      final segW = weights[i] / totalW * room;
      if (dx <= x + segW + gap / 2) return i;
      x += segW + gap;
    }
    return steps.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final selectedIdx = _selectedIndex();
    final weights = [for (final s in steps) _weight(s)];
    final colors = [
      for (final s in steps)
        s.isError || s.children.any((c) => c.isError)
            ? UsagePalette.error
            : widget.colorOf(s),
    ];

    return LayoutBuilder(
      builder: (_, constraints) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (e) {
          final i = _indexAt(e.localPosition.dx, constraints.maxWidth);
          if (i != _hovered) setState(() => _hovered = i);
        },
        onExit: (_) => setState(() => _hovered = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final i = _indexAt(d.localPosition.dx, constraints.maxWidth);
            if (i != null && i < steps.length) widget.onSelect(steps[i]);
          },
          child: SizedBox(
            height: 10,
            width: double.infinity,
            child: CustomPaint(
              painter: _FlowStripPainter(
                weights: weights,
                colors: colors,
                selected: selectedIdx,
                hovered: _hovered,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowStripPainter extends CustomPainter {
  _FlowStripPainter({
    required this.weights,
    required this.colors,
    required this.selected,
    required this.hovered,
  });

  final List<double> weights;
  final List<Color> colors;
  final int selected;
  final int? hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final n = weights.length;
    if (n == 0 || size.width <= 0) return;
    final gap = n > 28 ? 1.0 : 2.0;
    final room = math.max(1.0, size.width - gap * (n - 1));
    final total = weights.fold(0.0, (a, b) => a + b);
    final hasFocus = selected >= 0 || hovered != null;

    var x = 0.0;
    for (var i = 0; i < n; i++) {
      final w = math.max(1.5, weights[i] / total * room);
      final active = i == selected || i == hovered;
      final barH = active ? 8.0 : 5.0;
      final y = (size.height - barH) / 2;
      final alpha = active ? 1.0 : (hasFocus ? 0.42 : 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, barH),
          Radius.circular(math.min(2.5, w / 2)),
        ),
        Paint()..color = colors[i].withValues(alpha: alpha),
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(_FlowStripPainter old) =>
      old.selected != selected ||
      old.hovered != hovered ||
      old.weights.length != weights.length ||
      old.colors != colors;
}
