import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_session.dart';
import '../chat/floating/floating_layer.dart';
import '../chat/panels/limit_reset_panel.dart' show resetTime;
import '../chat/widgets/hover_builder.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_menu.dart' show IdeMenuColors;
import '../kernel/agent_kernel.dart' show KernelChoiceKind;
import '../l10n/l10n.dart';
import '../models/codex/codex_quota_format.dart';
import '../models/codex/codex_service.dart';
import '../models/codex/codex_usage.dart';
import '../models/model_provider.dart';
import '../models/model_providers.dart';
import '../models/model_runtime.dart' show codexService;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;

/// Under the composer: its branch and, on a model of ChatGPT accounts,
/// how much quota is left: the conversation's account's, and how many
/// can take a request; a click lists them all.
///
/// Kept fresh while shown: the account a reply came from by its headers,
/// the others asked again each [CodexService.usageMaxAge], and as a
/// window of one starts over.
class ChatQuotaBar extends StatefulWidget {
  const ChatQuotaBar({
    super.key,
    required this.session,
    required this.branch,
    this.providers,
    this.codex,
  });

  final ChatSession session;
  final Widget branch;
  final ModelProviders? providers;
  final CodexService? codex;

  @override
  State<ChatQuotaBar> createState() => _ChatQuotaBarState();
}

class _ChatQuotaBarState extends State<ChatQuotaBar>
    with WidgetsBindingObserver {
  late ModelProviders _providers;
  late CodexService _codex;

  /// The provider of the model picked, when its accounts are shown.
  String? _providerId;
  Timer? _poll;
  Timer? _reset;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  void _listen() {
    _providers = widget.providers ?? ModelProviders.current;
    _codex = widget.codex ?? codexService;
    widget.session.addListener(_sessionChanged);
    _providers.addListener(_providersChanged);
    _codex.addListener(_quotaChanged);
    _providerId = _provider?.id;
    _watch();
  }

  void _unlisten(ChatSession session) {
    session.removeListener(_sessionChanged);
    _providers.removeListener(_providersChanged);
    _codex.removeListener(_quotaChanged);
  }

  @override
  void didUpdateWidget(ChatQuotaBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.providers != widget.providers ||
        oldWidget.codex != widget.codex) {
      _unlisten(oldWidget.session);
      _listen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unlisten(widget.session);
    _poll?.cancel();
    _reset?.cancel();
    super.dispose();
  }

  /// The provider of the model picked, when it has ChatGPT accounts.
  ModelProvider? get _provider {
    final ref = parseModelRef(widget.session.selected(KernelChoiceKind.model));
    return switch (_providers.provider(ref?.provider)) {
      final provider?
          when provider.protocol.usesAccounts && provider.accounts.isNotEmpty =>
        provider,
      _ => null,
    };
  }

  /// The session tells of each streamed word: only another provider
  /// picked matters here; the account a reply took, the quota tells.
  void _sessionChanged() {
    final id = _provider?.id;
    if (id == _providerId) return;
    _providerId = id;
    setState(() {});
    _watch();
  }

  /// An account added or taken out of use: its quota asked for.
  void _providersChanged() {
    _providerId = _provider?.id;
    setState(() {});
    _watch();
  }

  /// One learned may start over at another time.
  void _quotaChanged() {
    setState(() {});
    _watch(ask: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hidden =
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (hidden == _hidden) return;
    _hidden = hidden;
    _watch();
  }

  /// Asks for the quota not known or old ([ask]), and times the next
  /// asking: every [CodexService.usageMaxAge], and as the first window
  /// starts over. None while the app is hidden.
  void _watch({bool ask = true}) {
    final provider = _provider;
    if (provider == null || _hidden) {
      _poll?.cancel();
      _poll = null;
      _reset?.cancel();
      _reset = null;
      return;
    }
    if (ask) _refresh(provider);
    _poll ??= Timer.periodic(CodexService.usageMaxAge, (_) {
      if (_provider case final provider?) _refresh(provider);
    });
    _reset?.cancel();
    _reset = null;
    final now = DateTime.now();
    DateTime? next;
    for (final account in provider.accounts) {
      for (final at in [
        ?_codex.limitedUntil(provider.id, account.id),
        for (final window
            in _codex.usage(provider.id, account.id)?.windows ??
                const <CodexWindow>[])
          ?window.resetsAt,
      ]) {
        if (at.isAfter(now) && (next == null || at.isBefore(next))) next = at;
      }
    }
    // Further on, the poll is there first.
    if (next != null && next.difference(now) < CodexService.usageMaxAge) {
      _reset = Timer(next.difference(now) + const Duration(seconds: 2), () {
        _reset = null;
        if (!mounted) return;
        setState(() {});
        _watch();
      });
    }
  }

  void _refresh(ModelProvider provider, {bool force = false}) {
    unawaited(
      _codex.refreshUsage(provider, force: force).catchError((Object error) {
        // Each account's failure is kept as its error.
        debugPrint('Quota of ${provider.name} not asked: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return widget.branch;
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(240, constraints.maxWidth),
            ),
            child: widget.branch,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth - 2),
              child: _QuotaPill(
                provider: provider,
                codex: _codex,
                session: widget.session.sessionId,
                onRefresh: () => _refresh(provider, force: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How much the conversation's account has left; a click lists them all.
class _QuotaPill extends StatefulWidget {
  const _QuotaPill({
    required this.provider,
    required this.codex,
    required this.session,
    required this.onRefresh,
  });

  final ModelProvider provider;
  final CodexService codex;
  final String? session;
  final VoidCallback onRefresh;

  @override
  State<_QuotaPill> createState() => _QuotaPillState();
}

class _QuotaPillState extends State<_QuotaPill> {
  final _tapRegion = Object();
  final _focus = FocusNode(skipTraversal: true);
  bool _open = false;

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Each account's short name: its address's before the @, numbered
  /// where two are alike.
  static Map<String, String> _names(List<ProviderAccount> accounts) {
    String short(ProviderAccount account) {
      final name = account.displayName.split('@').first;
      return name.characters.length > 16
          ? '${name.characters.take(15)}…'
          : name;
    }

    final names = [for (final account in accounts) short(account)];
    return {
      for (final (index, account) in accounts.indexed)
        account.id: names.where((name) => name == names[index]).length > 1
            ? '${names[index]} (${index + 1})'
            : names[index],
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = widget.provider;
    final codex = widget.codex;
    final now = DateTime.now();
    final inUse = [
      for (final account in provider.accounts)
        if (account.enabled && !codex.signedOut(provider.id, account.id))
          account,
    ];
    final free = inUse
        .where((account) => codex.limitedUntil(provider.id, account.id) == null)
        .length;
    final current = codex.accountFor(provider, session: widget.session);
    final back = codex.backAt(provider);
    final usage = current == null ? null : codex.usage(provider.id, current.id);
    final String label;
    final bool warn;
    if (back != null) {
      warn = true;
      label = l10n.quotaBarAllOut(resetTime(back.toLocal(), l10n, now: now));
    } else if (current == null) {
      warn = true;
      label = l10n.quotaBarNone;
    } else {
      label = [
        if (provider.accounts.length > 1)
          ?_names(provider.accounts)[current.id],
        if (usage == null || usage.windows.isEmpty)
          l10n.modelsAccountQuotaUnknown
        else
          for (final (window, fallback) in [
            (usage.primary, l10n.modelsQuotaShortWindow),
            (usage.secondary, l10n.modelsQuotaLongWindow),
          ])
            if (window != null)
              l10n.quotaBarWindowLeft(
                _windowName(l10n, window, fallback),
                window.leftPercent.round(),
              ),
        if (inUse.length > 1) l10n.quotaBarAvailable(free, inUse.length),
      ].join(' · ');
      warn = (usage?.mostUsed ?? 0) >= 90;
    }
    final color = warn ? AppColors.caution : AppColors.textMuted;
    final colors = themeColors;
    Widget pill = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _open
              ? colors['toolbar.activeBackground']
              : hovered
              ? colors['toolbar.hoverBackground']
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              warn ? Codicons.warning : Codicons.dashboard,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
    pill = FocusableActionDetector(
      focusNode: _focus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            _setOpen(false);
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _focus.requestFocus();
          _setOpen(!_open);
        },
        child: Semantics(
          button: true,
          label: '${provider.name}: $label',
          excludeSemantics: true,
          child: pill,
        ),
      ),
    );
    return FloatingLayer(
      visible: _open,
      tapRegionGroupId: _tapRegion,
      onTapOutside: () => _setOpen(false),
      builder: (context) => _QuotaPanel(
        provider: provider,
        codex: codex,
        session: widget.session,
        onRefresh: widget.onRefresh,
      ),
      child: TapRegion(groupId: _tapRegion, child: pill),
    );
  }
}

String _windowName(AppLocalizations l10n, CodexWindow? window, String other) {
  final name = quotaWindowName(l10n, window?.minutes);
  return name.isEmpty ? other : name;
}

/// Each account, how much of each window it has left and when that
/// starts over; the conversation's marked.
class _QuotaPanel extends StatelessWidget {
  const _QuotaPanel({
    required this.provider,
    required this.codex,
    required this.session,
    required this.onRefresh,
  });

  final ModelProvider provider;
  final CodexService codex;
  final String? session;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Its quota as it comes: in the overlay, it is not built again with
    // the pill.
    return ListenableBuilder(
      listenable: codex,
      builder: (context, _) {
        final current = codex.accountFor(provider, session: session)?.id;
        return Container(
          width: 320,
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            color: IdeMenuColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: IdeMenuColors.border),
            boxShadow: themeColors.highContrast ? null : IdeHoverColors.shadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IdeActionButton(
                      icon: Codicons.refresh,
                      tooltip: l10n.quotaBarRefresh,
                      iconSize: 14,
                      onPressed: onRefresh,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final account in provider.accounts)
                        _AccountQuota(
                          key: ValueKey(account.id),
                          account: account,
                          current: account.id == current,
                          usage: codex.usage(provider.id, account.id),
                          error: codex.error(provider.id, account.id),
                          limitedUntil: codex.limitedUntil(
                            provider.id,
                            account.id,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountQuota extends StatelessWidget {
  const _AccountQuota({
    super.key,
    required this.account,
    required this.current,
    required this.usage,
    required this.error,
    required this.limitedUntil,
  });

  final ProviderAccount account;
  final bool current;
  final CodexUsage? usage;
  final String? error;
  final DateTime? limitedUntil;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final usage = this.usage;
    final faint = TextStyle(color: AppColors.textFaint, fontSize: 11);
    final states = [
      if (!account.enabled) l10n.modelsAccountDisabled,
      if (limitedUntil case final until?)
        l10n.quotaBarBackAt(resetTime(until.toLocal(), l10n, now: now)),
    ];
    return Opacity(
      opacity: account.enabled ? 1 : 0.6,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    account.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                ),
                if (current) ...[
                  const SizedBox(width: 6),
                  Text(
                    l10n.quotaBarThisChat,
                    style: TextStyle(color: AppColors.accent, fontSize: 11),
                  ),
                ],
                if (usage?.plan ?? account.plan case final plan?) ...[
                  const SizedBox(width: 6),
                  Text(plan, style: faint),
                ],
              ],
            ),
            if (states.isNotEmpty)
              Text(
                states.join(' · '),
                style: TextStyle(color: AppColors.caution, fontSize: 11),
              ),
            if (usage == null || usage.windows.isEmpty)
              Text(l10n.modelsAccountQuotaUnknown, style: faint)
            else
              for (final (window, fallback) in [
                (usage.primary, l10n.modelsQuotaShortWindow),
                (usage.secondary, l10n.modelsQuotaLongWindow),
              ])
                if (window != null)
                  _WindowLine(
                    name: _windowName(l10n, window, fallback),
                    window: window,
                  ),
            if (error case final error?)
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: themeColors['errorForeground'],
                  fontSize: 11,
                ),
              ),
            if (usage != null)
              Text(
                l10n.modelsQuotaLastUpdated(
                  resetTime(usage.at.toLocal(), l10n, now: now),
                ),
                style: faint,
              ),
          ],
        ),
      ),
    );
  }
}

/// A window: a bar of what is left, how much, and when it starts over.
class _WindowLine extends StatelessWidget {
  const _WindowLine({required this.name, required this.window});

  final String name;
  final CodexWindow window;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final left = window.leftPercent;
    final color = left <= 10
        ? themeColors['errorForeground']
        : left <= 30
        ? AppColors.caution
        : AppColors.added;
    final style = TextStyle(color: AppColors.textMuted, fontSize: 11);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Container(
            width: 72,
            height: 4,
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              color: AppColors.textFaint.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              widthFactor: left / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              [
                l10n.modelsQuotaRemaining(left.round()),
                if (window.resetsAt case final at?)
                  quotaResets(l10n, at, DateTime.now()),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
