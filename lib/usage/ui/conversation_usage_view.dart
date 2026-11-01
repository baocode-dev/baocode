import 'dart:async';

import 'package:flutter/material.dart';

import '../../base/smooth_scroll.dart';
import '../../chat/chat_session.dart';
import '../../chat/widgets/scroll_edge_fade.dart';
import '../../ide/ide_button.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../usage_ledger.dart';
import '../usage_prices.dart';
import '../usage_query.dart';
import '../usage_record.dart';
import 'usage_calls.dart';
import 'usage_charts.dart';
import 'usage_context.dart';
import 'usage_filters.dart';
import 'usage_sections.dart';
import 'usage_style.dart';

/// The side panel's Usage page: what [session]'s conversation took of
/// its custom upstream, request by request, as the model proxy kept it:
/// its context as it grew and was compacted, each turn's, and every
/// call; filtered by kind, agent and model.
class ConversationUsageView extends StatefulWidget {
  const ConversationUsageView({
    super.key,
    required this.session,
    this.ledger,
    @visibleForTesting this.sessionId,
  });

  final ChatSession session;

  /// In place of [session]'s own (a preview's).
  final String? sessionId;

  /// The app's by default.
  final UsageLedger? ledger;

  @override
  State<ConversationUsageView> createState() => _ConversationUsageViewState();
}

class _ConversationUsageViewState extends State<ConversationUsageView> {
  UsageLedger get _ledger => widget.ledger ?? UsageLedger.current;

  String? _sessionId;
  List<UsageCall> _calls = const [];
  bool _loading = true;
  int _loadedVersion = -1;
  Timer? _reload;
  UsageFilter _filter = const UsageFilter();
  UsageSummary? _all;
  UsageSummary? _summary;

  @override
  void initState() {
    super.initState();
    _ledger.addListener(_ledgerChanged);
    UsagePrices.current.addListener(_repriced);
    widget.session.addListener(_sessionChanged);
    _sessionId = _idOf(widget);
    unawaited(_load());
  }

  static String? _idOf(ConversationUsageView view) =>
      view.sessionId ?? view.session.sessionId;

  @override
  void didUpdateWidget(ConversationUsageView old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
      _filter = const UsageFilter();
      _sessionId = _idOf(widget);
      _calls = const [];
      _loading = true;
      unawaited(_load());
    }
    if (old.ledger != widget.ledger) {
      (old.ledger ?? UsageLedger.current).removeListener(_ledgerChanged);
      _ledger.addListener(_ledgerChanged);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _reload?.cancel();
    _ledger.removeListener(_ledgerChanged);
    UsagePrices.current.removeListener(_repriced);
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  /// The costs, at the prices as they are now.
  void _repriced() => setState(_summarize);

  void _sessionChanged() {
    final id = _idOf(widget);
    if (id == _sessionId) return;
    _sessionId = id;
    unawaited(_load());
  }

  void _ledgerChanged() {
    if (_ledger.version == _loadedVersion) {
      // Its choices: those beside the conversation shown or not.
      setState(_summarize);
      return;
    }
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 500), () => _load());
  }

  /// [force]: summed again though nothing changed (as of now).
  Future<void> _load({bool force = false}) async {
    final id = _sessionId;
    final version = _ledger.version;
    final calls = id == null
        ? const <UsageCall>[]
        : await _ledger.ofSession(id);
    if (!mounted || id != _sessionId) return;
    _loadedVersion = version;
    // Another conversation's call: this one's page left as it is.
    if (!force && !_loading && calls.isNotEmpty && _same(calls, _calls)) {
      return;
    }
    setState(() {
      _loadedVersion = version;
      _calls = calls;
      _loading = false;
      _summarize();
    });
  }

  /// Whether [a] and [b] are the same calls, though read again.
  static bool _same(List<UsageCall> a, List<UsageCall> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].at.millisecondsSinceEpoch != b[i].at.millisecondsSinceEpoch) {
        return false;
      }
    }
    return true;
  }

  void _summarize() {
    final now = DateTime.now();
    final calls = _ledger.shown(_calls);
    _all = UsageSummary.of(calls, const UsageFilter(), now: now);
    _summary = UsageSummary.of(calls, _filter, now: now);
  }

  void _setFilter(UsageFilter filter) => setState(() {
    _filter = filter;
    _summarize();
  });

  /// An agent as named: the main one, or a subagent by its kind and its
  /// id cut short.
  String _agentLabel(String agent) {
    if (agent.isEmpty) return context.l10n.ustatMainAgent;
    final type = _all?.byAgent[agent]?.label ?? context.l10n.ustatClassSubagent;
    final short = agent.length > 6 ? agent.substring(0, 6) : agent;
    return '$type · $short';
  }

  Widget _filters(UsageSummary all) {
    final l10n = context.l10n;
    final filter = _filter;
    final agents = UsageSummary.ranked(all.byAgent);
    final models = all.models.toList()..sort();
    return UsageFilterBar(
      trailing: [
        if (filter.narrowed)
          UsageIconButton(
            icon: Codicons.clearAll,
            tooltip: l10n.ustatResetFilters,
            onPressed: () => _setFilter(const UsageFilter()),
          ),
        UsageIconButton(
          icon: Codicons.refresh,
          tooltip: l10n.ustatRefresh,
          onPressed: () => unawaited(_load(force: true)),
        ),
      ],
      children: [
        UsageMultiPicker<UsageClass>(
          icon: Codicons.typeHierarchy,
          label: l10n.ustatKind,
          selected: filter.classes,
          choices: [
            for (final kind in UsageClass.values)
              if (all.byClass.containsKey(kind))
                (
                  value: kind,
                  label: UsageFormat.ofClass(context, kind),
                  color: UsagePalette.ofClass(kind),
                ),
          ],
          onChanged: (picked) => _setFilter(filter.copyWith(classes: picked)),
        ),
        UsageMultiPicker<String>(
          icon: Codicons.hubot,
          label: l10n.ustatAgent,
          selected: filter.agents,
          choices: [
            for (final group in agents)
              (value: group.key, label: _agentLabel(group.key), color: null),
          ],
          onChanged: (picked) => _setFilter(filter.copyWith(agents: picked)),
        ),
        if (models.length > 1)
          UsageMultiPicker<String>(
            icon: Codicons.sparkle,
            label: l10n.ustatModel,
            selected: filter.models,
            choices: [
              for (final model in models)
                (value: model, label: model, color: null),
            ],
            onChanged: (picked) => _setFilter(filter.copyWith(models: picked)),
          ),
        UsageFilterChip(
          icon: Codicons.error,
          chevron: false,
          label: l10n.ustatFailedOnly,
          active: filter.failedOnly,
          onTap: (_) =>
              _setFilter(filter.copyWith(failedOnly: !filter.failedOnly)),
        ),
      ],
    );
  }

  List<Widget> _sections(UsageSummary summary) {
    final l10n = context.l10n;
    final prompts = UsageSummary.ranked(summary.byPrompt)
      ..sort((a, b) => b.totals.first!.compareTo(a.totals.first!));
    return [
      UsageOverview(summary: summary, minWidth: 128),
      UsageContextSection(summary: summary, agentLabel: _agentLabel),
      if (prompts.isNotEmpty)
        UsageRankCard(
          summary: summary,
          title: l10n.ustatByTurn,
          subtitle: l10n.ustatByTurnDetail,
          builder: (context, byCost) => UsageRankList(
            limit: 5,
            moreLabel: (n) => l10n.ustatShowAll(n),
            lessLabel: l10n.ustatShowLess,
            // As they came, not ranked.
            items: UsageRanking(prompts, byCost: byCost, sort: false).items(
              (group, rank) => rankOf(
                context,
                group,
                rank: rank,
                label: UsageFormat.when(group.totals.first!),
                detail: l10n.ustatTurnDetail(
                  UsageFormat.duration(
                    group.totals.ended!.difference(group.totals.first!),
                  ),
                  group.totals.maxPrompt == 0
                      ? '—'
                      : UsageFormat.tokens(group.totals.maxPrompt),
                ),
              ),
            ),
          ),
        ),
      UsageTimeSection(summary: summary, height: 140),
      UsageCard(
        title: l10n.ustatCallsTitle,
        subtitle: l10n.ustatRecentCallsDetail(summary.calls.length),
        child: UsageCallsList(
          calls: summary.calls,
          showSession: false,
          ledger: _ledger,
        ),
      ),
    ];
  }

  Widget _empty() {
    final l10n = context.l10n;
    if (!_ledger.enabled) {
      return UsageEmpty(
        icon: Codicons.graph,
        title: l10n.ustatRecordOff,
        detail: l10n.ustatRecordOffDescription,
        action: IdeButton(
          label: l10n.ustatTurnOn,
          onPressed: () =>
              unawaited(_ledger.save(UsageLedger.enabledKey, null)),
        ),
      );
    }
    return UsageEmpty(
      icon: Codicons.graph,
      title: _sessionId == null
          ? l10n.ustatConversationNew
          : l10n.ustatConversationEmpty,
      detail: l10n.ustatConversationEmptyDetail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = _all;
    final summary = _summary;
    final hasCalls = all != null && all.calls.isNotEmpty && summary != null;
    // Its filters stay at the top, what scrolls fading out under them.
    return ColoredBox(
      color: AppColors.code,
      child: SmoothScrolling(
        builder: (context, controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasCalls)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: _filters(all),
              ),
            Expanded(
              child: ScrollEdgeFade(
                fadeLength: hasCalls ? 28 : 40,
                child: ListView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(16, hasCalls ? 12 : 14, 16, 32),
                  children: [
                    if (!hasCalls)
                      _loading ? const SizedBox(height: 120) : _empty()
                    else if (summary.calls.isEmpty)
                      UsageEmpty(
                        icon: Codicons.filter,
                        title: l10n.ustatEmptyFiltered,
                      )
                    else
                      for (final (i, section) in _sections(
                        summary,
                      ).indexed) ...[
                        if (i > 0) const SizedBox(height: 12),
                        section,
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
