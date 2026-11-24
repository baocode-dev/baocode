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
import 'usage_trajectory_view.dart';
import '../../theme/svg_icons.dart';

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

enum _UsageMode { overview, trajectory }

class _ConversationUsageViewState extends State<ConversationUsageView> {
  UsageLedger get _ledger => widget.ledger ?? UsageLedger.current;

  String? _sessionId;
  List<UsageCall> _calls = const [];
  bool _loading = true;
  int _loadedVersion = -1;
  Timer? _reload;
  _UsageMode? _mode;

  /// Since when the calls shown are out of date, a reload put off.
  DateTime? _staleSince;
  int _settingsVersion = 0;
  int _underwayVersion = 0;
  UsageFilter _filter = const UsageFilter();
  UsageSummary? _all;
  UsageSummary? _summary;

  @override
  void initState() {
    super.initState();
    _ledger.addListener(_ledgerChanged);
    _settingsVersion = _ledger.settingsVersion;
    _underwayVersion = _ledger.underwayVersion;
    UsagePrices.current.addListener(_repriced);
    widget.session.addListener(_sessionChanged);
    _sessionId = _idOf(widget);
    _itemCount = widget.session.itemCount;
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
      _mode = null;
      _sessionId = _idOf(widget);
      _itemCount = widget.session.itemCount;
      _calls = const [];
      _loading = true;
      unawaited(_load());
    }
    if (old.ledger != widget.ledger) {
      (old.ledger ?? UsageLedger.current).removeListener(_ledgerChanged);
      _ledger.addListener(_ledgerChanged);
      _settingsVersion = _ledger.settingsVersion;
      _underwayVersion = _ledger.underwayVersion;
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

  bool _showTrajectory({required bool hasCalls}) => switch (_mode) {
    final m? => m == _UsageMode.trajectory,
    null =>
      !hasCalls && !_loading && !_anyUnderway && widget.session.itemCount > 0,
  };

  int _itemCount = 0;

  void _sessionChanged() {
    final id = _idOf(widget);
    if (id != _sessionId) {
      _sessionId = id;
      unawaited(_load());
      return;
    }
    // Trajectory view listens to session directly with coalescing; only rebuild
    // here if item presence flips between empty and non-empty.
    final nowCount = widget.session.itemCount;
    if ((nowCount > 0) != (_itemCount > 0)) {
      _itemCount = nowCount;
      setState(() {});
    } else {
      _itemCount = nowCount;
    }
  }

  /// The ledger told of something: only what it concerns is done. With
  /// subagents at work it tells many times a minute, and summing a long
  /// conversation's calls up each time, the page froze.
  void _ledgerChanged() {
    final ledger = _ledger;
    // A call kept (in any conversation): read again once they settle.
    if (ledger.version != _loadedVersion) _loadSoon();
    final settings = ledger.settingsVersion != _settingsVersion;
    final underway = ledger.underwayVersion != _underwayVersion;
    _settingsVersion = ledger.settingsVersion;
    _underwayVersion = ledger.underwayVersion;
    if (settings) {
      // Its choices: those beside the conversation shown or not.
      setState(_summarize);
    } else if (underway && !_hasCalls) {
      // Its first call, under way: its card shown. With calls, the calls'
      // card follows what is under way by itself.
      setState(() {});
    }
  }

  /// Calls come in bursts: read once they settle; but not put off for
  /// ever while they keep coming.
  void _loadSoon() {
    final now = DateTime.now();
    final since = _staleSince ??= now;
    _reload?.cancel();
    if (now.difference(since) >= const Duration(seconds: 2)) {
      _reload = null;
      unawaited(_load());
      return;
    }
    _reload = Timer(const Duration(milliseconds: 500), () => _load());
  }

  /// [force]: summed again though nothing changed (as of now).
  Future<void> _load({bool force = false}) async {
    final id = _sessionId;
    final version = _ledger.version;
    _staleSince = null;
    final calls = id == null
        ? const <UsageCall>[]
        : await _ledger.ofSession(id);
    if (!mounted || id != _sessionId) return;
    // Another conversation's call: this one's page left as it is, but
    // for its calls under way (the calls' card reads them again, told
    // the version).
    if (!force && !_loading && calls.isNotEmpty && _same(calls, _calls)) {
      setState(() => _loadedVersion = version);
      return;
    }
    setState(() {
      _loadedVersion = version;
      _calls = calls;
      _loading = false;
      _summarize();
    });
  }

  bool get _hasCalls => _all?.calls.isNotEmpty ?? false;

  /// Whether a call of it is under way, as filtered: its page is shown
  /// before its first call is kept.
  bool get _anyUnderway {
    final id = _sessionId;
    if (id == null) return false;
    return _ledger
        .shown(_ledger.underway(id))
        .any((call) => _filter.matches(call));
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
      _callsCard(summary.calls),
    ];
  }

  Widget _callsCard(List<UsageCall> calls) => _CallsCard(
    sessionId: _sessionId,
    calls: calls,
    filter: _filter,
    ledger: _ledger,
    loadedVersion: _loadedVersion,
  );

  Widget _empty() {
    final l10n = context.l10n;
    if (!_ledger.enabled) {
      return UsageEmpty(
        icon: SvgIcons.usage,
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
      icon: SvgIcons.usage,
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
    final hasItems = widget.session.itemCount > 0;
    final trajectory = _showTrajectory(hasCalls: hasCalls);
    // Its filters stay at the top, what scrolls fading out under them.
    return ColoredBox(
      color: AppColors.code,
      child: SmoothScrolling(
        builder: (context, controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasCalls || hasItems)
              Padding(
                // The cards under them a row's gap away, at rest.
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UsageSegmented<_UsageMode>(
                      value: trajectory
                          ? _UsageMode.trajectory
                          : _UsageMode.overview,
                      onChanged: (m) => setState(() => _mode = m),
                      segments: [
                        (
                          value: _UsageMode.overview,
                          label: l10n.ustatViewOverview,
                        ),
                        (
                          value: _UsageMode.trajectory,
                          label: l10n.ustatViewTrajectory,
                        ),
                      ],
                    ),
                    if (!trajectory && hasCalls) ...[
                      const SizedBox(height: 8),
                      _filters(all),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: ScrollEdgeFade(
                fadeLength: hasCalls || trajectory ? 28 : 40,
                child: trajectory
                    ? UsageTrajectoryView(
                        session: widget.session,
                        calls: _calls,
                        ledger: _ledger,
                        scrollController: controller,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      )
                    : ListView(
                        controller: controller,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          hasCalls ? 12 : 14,
                          16,
                          32,
                        ),
                        children: [
                          // Its first call, under way.
                          if (!hasCalls && !_loading && _anyUnderway)
                            _callsCard(const [])
                          else if (!hasCalls)
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

/// The conversation's calls' card: [calls], and above them its calls under
/// way, read again each second while there are any. It follows them by
/// itself, so that the page above it (its charts over every call) is not
/// built again each second, nor each time a call begins or ends.
class _CallsCard extends StatefulWidget {
  const _CallsCard({
    required this.sessionId,
    required this.calls,
    required this.filter,
    required this.ledger,
    required this.loadedVersion,
  });

  final String? sessionId;

  /// Kept, and filtered.
  final List<UsageCall> calls;
  final UsageFilter filter;
  final UsageLedger ledger;

  /// The ledger's version [calls] were read at: behind the ledger's, they
  /// are about to be read again.
  final int loadedVersion;

  @override
  State<_CallsCard> createState() => _CallsCardState();
}

class _CallsCardState extends State<_CallsCard> {
  /// Its calls under way, as last read.
  List<UsageCall> _underway = const [];
  Timer? _tick;
  int _version = -1;

  @override
  void initState() {
    super.initState();
    widget.ledger.addListener(_changed);
    _version = widget.ledger.underwayVersion;
    _read();
  }

  @override
  void didUpdateWidget(_CallsCard old) {
    super.didUpdateWidget(old);
    if (old.ledger != widget.ledger) {
      old.ledger.removeListener(_changed);
      widget.ledger.addListener(_changed);
      _version = widget.ledger.underwayVersion;
    }
    // The calls read again: those over are among them now.
    if (old.sessionId != widget.sessionId ||
        old.loadedVersion != widget.loadedVersion ||
        !identical(old.calls, widget.calls)) {
      _read();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.ledger.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final ledger = widget.ledger;
    if (ledger.underwayVersion == _version) return;
    _version = ledger.underwayVersion;
    final before = _underway;
    // A call over is kept first: left where it is till the calls are read
    // again with it among them (it would blink out first).
    _read(keepGone: ledger.version != widget.loadedVersion);
    if (!_same(before, _underway)) setState(() {});
  }

  /// [call] as the same as it goes on, and once kept.
  static Object _keyOf(UsageCall call) =>
      (call.at.millisecondsSinceEpoch, call.agentId, call.model);

  static bool _same(List<UsageCall> a, List<UsageCall> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_keyOf(a[i]) != _keyOf(b[i])) return false;
    }
    return true;
  }

  /// Reads its calls under way again. [keepGone]: those over kept as they
  /// were last read.
  void _read({bool keepGone = false}) {
    final id = widget.sessionId;
    final now = id == null ? const <UsageCall>[] : widget.ledger.underway(id);
    if (keepGone && _underway.isNotEmpty) {
      final still = {for (final call in now) _keyOf(call)};
      _underway = [
        for (final call in _underway)
          if (!still.contains(_keyOf(call))) call,
        ...now,
      ]..sort((a, b) => a.at.compareTo(b.at));
    } else {
      _underway = now;
    }
    if (_underway.isEmpty) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _read(keepGone: true)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final underway = [
      for (final call in widget.ledger.shown(_underway))
        if (widget.filter.matches(call)) call,
    ];
    return UsageCard(
      title: l10n.ustatCallsTitle,
      subtitle: l10n.ustatRecentCallsDetail(widget.calls.length),
      child: UsageCallsList(
        calls: widget.calls,
        underway: underway,
        showSession: false,
        ledger: widget.ledger,
      ),
    );
  }
}
