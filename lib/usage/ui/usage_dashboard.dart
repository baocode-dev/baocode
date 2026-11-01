import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/model_icons.dart';
import '../../settings/pages/settings_dropdown.dart';
import '../../settings/pages/settings_widgets.dart';
import '../../theme/codicons.dart';
import '../../workspace/workspace.dart';
import '../usage_ledger.dart';
import '../usage_prices.dart';
import '../usage_query.dart';
import '../usage_record.dart';
import 'usage_calls.dart';
import 'usage_charts.dart';
import 'usage_context.dart';
import 'usage_filters.dart';
import 'usage_prices_card.dart';
import 'usage_quota_section.dart';
import 'usage_sections.dart';
import 'usage_style.dart';

/// Side by side where there is room for [minWidth] each, else one under
/// the other.
class UsageColumns extends StatelessWidget {
  const UsageColumns({
    super.key,
    required this.children,
    this.minWidth = 300,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side =
          constraints.maxWidth >=
          minWidth * children.length + spacing * (children.length - 1);
      if (!side) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) SizedBox(height: spacing),
              child,
            ],
          ],
        );
      }
      // Not stretched to one height: their charts lay out by their width,
      // which an intrinsic height cannot ask of them.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: child),
          ],
        ],
      );
    },
  );
}

/// A conversation as the usage views name it: its agent's title in the
/// window, else as kept with its calls, else its id cut short.
String usageSessionLabel(
  BuildContext context,
  String session, {
  Workspace? workspace,
  String? kept,
}) {
  final thread = workspace?.threads.where((t) => t.id == session).firstOrNull;
  if (thread != null) return thread.localizedTitle(context.l10n);
  if (kept == 'New Chat') return context.l10n.agentUntitled;
  if (kept != null && kept.isNotEmpty) return kept;
  return session.length > 8 ? session.substring(0, 8) : session;
}

/// Settings → Usage: the calls to custom upstreams, over a time and by
/// the upstreams, models, kinds and conversations picked; then how they
/// are kept, and deleting them.
class UsageSettingsPage extends StatefulWidget {
  const UsageSettingsPage({super.key, this.ledger, this.workspace});

  /// The app's by default.
  final UsageLedger? ledger;

  /// The window's agents, for the conversations' titles.
  final Workspace? workspace;

  @override
  State<UsageSettingsPage> createState() => _UsageSettingsPageState();
}

class _UsageSettingsPageState extends State<UsageSettingsPage> {
  UsageLedger get _ledger => widget.ledger ?? UsageLedger.current;

  UsageRange _range = UsageRange.week;

  /// A stretch picked on the chart, over [_range].
  ({DateTime from, DateTime until})? _pinned;
  UsageFilter _filter = const UsageFilter();

  List<UsageCall> _calls = const [];
  UsageSummary? _summary;
  bool _loading = true;
  int _loadedVersion = -1;
  UsageSpace? _space;
  Timer? _reload;

  @override
  void initState() {
    super.initState();
    _ledger.addListener(_changed);
    UsagePrices.current.addListener(_repriced);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(UsageSettingsPage old) {
    super.didUpdateWidget(old);
    if (old.ledger != widget.ledger) {
      (old.ledger ?? UsageLedger.current).removeListener(_changed);
      _ledger.addListener(_changed);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _reload?.cancel();
    _ledger.removeListener(_changed);
    UsagePrices.current.removeListener(_repriced);
    super.dispose();
  }

  /// The costs, at the prices as they are now.
  void _repriced() => setState(_summarize);

  void _changed() {
    if (_ledger.version == _loadedVersion) {
      setState(() {});
      return;
    }
    // Calls come in bursts: read once they settle.
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 800), () => _load());
  }

  ({DateTime? from, DateTime? until}) get _time {
    if (_pinned case final pinned?) {
      return (from: pinned.from, until: pinned.until);
    }
    return (from: _range.from(DateTime.now()), until: null);
  }

  Future<void> _load() async {
    final version = _ledger.version;
    final time = _time;
    final calls = await _ledger.range(from: time.from, until: time.until);
    final space = await _ledger.space();
    if (!mounted) return;
    setState(() {
      _loadedVersion = version;
      _calls = calls;
      _space = space;
      _loading = false;
      _summarize();
    });
  }

  void _summarize() {
    final time = _time;
    _summary = UsageSummary.of(
      _calls,
      _filter.copyWith(from: time.from, until: time.until, clearTime: true),
    );
  }

  void _setFilter(UsageFilter filter) => setState(() {
    _filter = filter;
    _summarize();
  });

  void _setRange(UsageRange range) {
    setState(() {
      _range = range;
      _pinned = null;
      _loading = true;
    });
    unawaited(_load());
  }

  void _pin(DateTime from, DateTime until) {
    setState(() {
      _pinned = (from: from, until: until);
      _loading = true;
    });
    unawaited(_load());
  }

  String _sessionLabel(String session, {String? kept}) => usageSessionLabel(
    context,
    session,
    workspace: widget.workspace,
    kept: kept,
  );

  // --- Deleting -------------------------------------------------------------

  Future<void> _clear(UsageClearSpec spec, String what) async {
    final l10n = context.l10n;
    final chosen = await showIdeDialog(
      context,
      message: l10n.ustatClearConfirm(what),
      detail: l10n.ustatClearDetail,
      buttons: [l10n.ustatClear],
    );
    if (chosen != 0) return;
    await _ledger.clear(spec);
    await _load();
  }

  Future<void> _clearTraces() async {
    final l10n = context.l10n;
    final chosen = await showIdeDialog(
      context,
      message: l10n.ustatClearConfirm(l10n.ustatClearTraces),
      detail: l10n.ustatClearTracesDetail,
      buttons: [l10n.ustatClear],
    );
    if (chosen != 0) return;
    await _ledger.clearTraces();
    await _load();
  }

  void _clearMenu(Rect anchor) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final time = _time;
    final filtered =
        _filter.providers.isNotEmpty ||
        _filter.models.isNotEmpty ||
        _filter.session != null;
    unawaited(
      showIdeMenu(
        context,
        anchor: anchor,
        entries: ideMenuGroups([
          [
            for (final days in const [7, 30, 90])
              IdeMenuAction(
                l10n.ustatClearOlderThan(days),
                onSelected: () => unawaited(
                  _clear(
                    UsageClearSpec(
                      until: DateTime(
                        today.year,
                        today.month,
                        today.day - days + 1,
                      ),
                    ),
                    l10n.ustatClearOlderThan(days),
                  ),
                ),
              ),
          ],
          [
            IdeMenuAction(
              l10n.ustatClearShown,
              enabled: _summary?.calls.isNotEmpty ?? false,
              onSelected: () => unawaited(
                _clear(
                  UsageClearSpec(
                    from: time.from,
                    until: time.until,
                    providers: _filter.providers,
                    models: _filter.models,
                    session: _filter.session,
                  ),
                  filtered
                      ? l10n.ustatClearShownFiltered
                      : l10n.ustatClearShown,
                ),
              ),
            ),
          ],
          [
            IdeMenuAction(
              l10n.ustatClearTraces,
              enabled: (_space?.traces ?? 0) > 0,
              onSelected: () => unawaited(_clearTraces()),
            ),
          ],
          [
            IdeMenuAction(
              l10n.ustatClearAll,
              onSelected: () =>
                  unawaited(_clear(const UsageClearSpec(), l10n.ustatClearAll)),
            ),
          ],
        ]),
      ),
    );
  }

  // --- Building -------------------------------------------------------------

  String _retentionLabel(int days) => days == 0
      ? context.l10n.ustatKeepForever
      : context.l10n.ustatKeepDays(days);

  Widget _filters(UsageSummary summary) {
    final l10n = context.l10n;
    final filter = _filter;
    final sessions = UsageSummary.ranked(
      UsageSummary.of(
        _calls,
        UsageFilter(from: _time.from, until: _time.until),
      ).bySession,
    );
    final providers = summary.providers.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final models = summary.models.toList()..sort();
    return UsageFilterBar(
      trailing: [
        UsageTraceToggle(
          on: _ledger.trace,
          count: _ledger.traced,
          onChanged: (on) =>
              unawaited(_ledger.save(UsageLedger.traceKey, on ? true : null)),
        ),
        const SizedBox(width: 4),
        if (filter.narrowed || filter.session != null)
          UsageIconButton(
            icon: Codicons.clearAll,
            tooltip: l10n.ustatResetFilters,
            onPressed: () => _setFilter(const UsageFilter()),
          ),
        UsageIconButton(
          icon: Codicons.refresh,
          tooltip: l10n.ustatRefresh,
          onPressed: () => unawaited(_load()),
        ),
      ],
      children: [
        UsageRangePicker(value: _range, onChanged: _setRange),
        if (_pinned case final pinned?)
          UsageFilterChip(
            icon: Codicons.close,
            chevron: false,
            active: true,
            label:
                '${UsageFormat.when(pinned.from)} – ${UsageFormat.when(pinned.until)}',
            tooltip: l10n.ustatUnpin,
            onTap: (_) => _setRange(_range),
          ),
        UsageMultiPicker<String>(
          icon: Codicons.server,
          label: l10n.ustatUpstream,
          selected: filter.providers,
          choices: [
            for (final MapEntry(:key, :value) in providers)
              (value: key, label: value, color: null),
          ],
          onChanged: (picked) => _setFilter(filter.copyWith(providers: picked)),
        ),
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
        UsageMultiPicker<UsageClass>(
          icon: Codicons.typeHierarchy,
          label: l10n.ustatKind,
          selected: filter.classes,
          choices: [
            for (final kind in UsageClass.values)
              (
                value: kind,
                label: UsageFormat.ofClass(context, kind),
                color: UsagePalette.ofClass(kind),
              ),
          ],
          onChanged: (picked) => _setFilter(filter.copyWith(classes: picked)),
        ),
        UsageMultiPicker<String>(
          icon: Codicons.commentDiscussion,
          label: l10n.ustatConversation,
          selected: {?filter.session},
          choices: [
            for (final group in sessions)
              (
                value: group.key,
                label: _sessionLabel(group.key, kept: group.label),
                color: null,
              ),
          ],
          // One at a time: the last picked.
          onChanged: (picked) => _setFilter(
            filter.copyWith(
              session: picked.isEmpty
                  ? null
                  : picked.firstWhere(
                      (s) => s != filter.session,
                      orElse: () => picked.first,
                    ),
              clearSession: true,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _dashboard(UsageSummary summary) {
    final l10n = context.l10n;
    final filter = _filter;
    final session = filter.session;
    final sessionSummary = session == null ? null : summary;
    return [
      UsageOverview(summary: summary),
      UsageTimeSection(summary: summary, height: 160, onPickBucket: _pin),
      if (UsageQuotaSection.of(summary) case final quota?)
        UsageQuotaSection(quota: quota),
      UsageColumns(
        children: [
          UsageClassSection(
            summary: summary,
            selected: filter.classes,
            onToggle: (kind) {
              final classes = {...filter.classes};
              if (!classes.remove(kind)) classes.add(kind);
              _setFilter(filter.copyWith(classes: classes));
            },
          ),
          UsageRankCard(
            summary: summary,
            title: l10n.ustatByUpstream,
            builder: (context, byCost) => UsageRankList(
              selected: filter.providers,
              onTap: (item) {
                final picked = {...filter.providers};
                if (!picked.remove(item.key)) picked.add(item.key);
                _setFilter(filter.copyWith(providers: picked));
              },
              moreLabel: (n) => l10n.ustatShowAll(n),
              lessLabel: l10n.ustatShowLess,
              items: UsageRanking(summary.byProvider.values, byCost: byCost)
                  .items(
                    (group, rank) => rankOf(
                      context,
                      group,
                      rank: rank,
                      leading: ProviderIcon(group.key, size: 13),
                    ),
                  ),
            ),
          ),
        ],
      ),
      UsageColumns(
        children: [
          UsageRankCard(
            summary: summary,
            title: l10n.ustatByModel,
            builder: (context, byCost) => UsageRankList(
              selected: filter.models,
              onTap: (item) {
                final picked = {...filter.models};
                if (!picked.remove(item.key)) picked.add(item.key);
                _setFilter(filter.copyWith(models: picked));
              },
              moreLabel: (n) => l10n.ustatShowAll(n),
              lessLabel: l10n.ustatShowLess,
              items: UsageRanking(summary.byModel.values, byCost: byCost).items(
                (group, rank) => rankOf(
                  context,
                  group,
                  rank: rank,
                  leading: ModelIcon(
                    provider: group.provider ?? '',
                    model: group.key,
                    size: 13,
                  ),
                ),
              ),
            ),
          ),
          UsageRankCard(
            summary: summary,
            title: l10n.ustatByConversation,
            builder: (context, byCost) => UsageRankList(
              selected: {?session},
              onTap: (item) => _setFilter(
                filter.copyWith(
                  session: item.key == session ? null : item.key,
                  clearSession: true,
                ),
              ),
              empty: l10n.ustatNoConversations,
              moreLabel: (n) => l10n.ustatShowAll(n),
              lessLabel: l10n.ustatShowLess,
              items: UsageRanking(summary.bySession.values, byCost: byCost)
                  .items(
                    (group, rank) => rankOf(
                      context,
                      group,
                      rank: rank,
                      label: _sessionLabel(group.key, kept: group.label),
                    ),
                  ),
            ),
          ),
        ],
      ),
      if (sessionSummary != null)
        UsageContextSection(
          summary: sessionSummary,
          agentLabel: (agent) {
            final type = sessionSummary.byAgent[agent]?.label;
            final short = agent.length > 6 ? agent.substring(0, 6) : agent;
            return type == null ? short : '$type · $short';
          },
        ),
      UsageToolsSection(summary: summary),
      UsageCard(
        title: l10n.ustatRecentCalls,
        subtitle: l10n.ustatRecentCallsDetail(summary.calls.length),
        child: UsageCallsList(
          calls: summary.calls,
          showSession: session == null,
          ledger: _ledger,
          sessionLabel: (call) => switch (call.session) {
            // Its conversation's title, as last kept: a call's own is
            // only on its first of the day.
            final id? => _sessionLabel(
              id,
              kept: summary.bySession[id]?.label ?? call.sessionTitle,
            ),
            null => '',
          },
        ),
      ),
      UsagePricesCard(summary: summary),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ledger = _ledger;
    final summary = _summary;
    final space = _space;
    return SettingsPage(
      title: l10n.settingsSectionUsage,
      description: l10n.ustatDescription,
      children: [
        if (!ledger.enabled)
          SettingsCard(
            children: [
              SettingsSwitchRow(
                label: l10n.ustatRecord,
                description: l10n.ustatRecordOffDescription,
                value: false,
                onChanged: (on) => unawaited(
                  ledger.save(UsageLedger.enabledKey, on ? null : false),
                ),
              ),
            ],
          ),
        if (summary != null) ...[
          _filters(summary),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _loading ? 0.5 : 1,
            child: summary.calls.isEmpty
                ? UsageCard(
                    child: UsageEmpty(
                      icon: Codicons.graph,
                      title: _calls.isEmpty
                          ? l10n.ustatEmptyTitle
                          : l10n.ustatEmptyFiltered,
                      detail: _calls.isEmpty ? l10n.ustatEmptyDetail : null,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, section) in _dashboard(
                        summary,
                      ).indexed) ...[
                        if (i > 0) const SizedBox(height: 12),
                        section,
                      ],
                    ],
                  ),
          ),
        ] else
          const SizedBox(height: 120),
        SettingsGroup(
          title: l10n.ustatDataTitle,
          description: l10n.ustatDataDescription,
          children: [
            if (ledger.enabled)
              SettingsSwitchRow(
                label: l10n.ustatRecord,
                description: l10n.ustatRecordDescription,
                value: true,
                onChanged: (on) => unawaited(
                  ledger.save(UsageLedger.enabledKey, on ? null : false),
                ),
              ),
            SettingsSwitchRow(
              label: l10n.ustatDetailed,
              description: l10n.ustatDetailedDescription,
              value: ledger.detailed,
              onChanged: (on) => unawaited(
                ledger.save(UsageLedger.detailedKey, on ? null : false),
              ),
            ),
            SettingsSwitchRow(
              label: l10n.ustatTrace,
              description: l10n.ustatTraceDescription,
              value: ledger.trace,
              onChanged: (on) => unawaited(
                ledger.save(UsageLedger.traceKey, on ? true : null),
              ),
            ),
            SettingsRow(
              label: l10n.ustatRetention,
              description: l10n.ustatRetentionDescription,
              trailing: SettingsDropdown(
                current: _retentionLabel(ledger.retentionDays),
                semanticLabel: l10n.ustatRetention,
                entries: () => [
                  for (final days in UsageLedger.retentionChoices)
                    IdeMenuAction(
                      _retentionLabel(days),
                      checked: days == ledger.retentionDays,
                      onSelected: () => unawaited(
                        ledger.save(
                          UsageLedger.retentionKey,
                          days == UsageLedger.defaultRetention ? null : days,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SettingsRow(
              label: l10n.ustatSpace(UsageFormat.bytes(space?.bytes ?? 0)),
              description: space == null || space.days == 0
                  ? l10n.ustatSpaceEmpty
                  : [
                      l10n.ustatSpaceDetail(space.days, space.oldest ?? ''),
                      if (space.traces > 0)
                        l10n.ustatSpaceTraces(
                          UsageFormat.bytes(space.traceBytes),
                          space.traces,
                        ),
                    ].join(),
              trailing: Builder(
                builder: (context) => IdeButton(
                  label: l10n.ustatClearEllipsis,
                  icon: Codicons.trash,
                  secondary: true,
                  onPressed: (space?.bytes ?? 0) == 0
                      ? null
                      : () {
                          final box = context.findRenderObject()! as RenderBox;
                          _clearMenu(box.localToGlobal(Offset.zero) & box.size);
                        },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
