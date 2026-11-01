import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/codex/codex_service.dart';
import '../../models/codex/codex_usage.dart';
import '../../models/model_provider.dart';
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart' show codexService;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import 'interaction_panel.dart';

/// A day of [resetCreditPlan]: how many credits to use then, and by when
/// the last of them has to be.
typedef ResetCreditDay = ({DateTime day, int count, DateTime deadline});

/// When to use reset credits expiring at [expiries] so that none goes to
/// waste: spread evenly from [now]'s day to the last one's, none later
/// than the day it expires. By day, the first first.
List<ResetCreditDay> resetCreditPlan(List<DateTime> expiries, DateTime now) {
  DateTime dayOf(DateTime at) {
    final local = at.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  final sorted = [
    for (final at in expiries)
      if (at.isAfter(now)) at,
  ]..sort();
  if (sorted.isEmpty) return const [];
  final today = dayOf(now);
  final span = dayOf(sorted.last).difference(today).inDays;
  final days = <DateTime, ({int count, DateTime deadline})>{};
  for (final (i, expiry) in sorted.indexed) {
    final spread = today.add(Duration(days: i * (span + 1) ~/ sorted.length));
    final due = dayOf(expiry);
    final day = due.isBefore(spread) ? due : spread;
    final known = days[day];
    days[day] = (
      count: (known?.count ?? 0) + 1,
      deadline: known == null || expiry.isBefore(known.deadline)
          ? expiry
          : known.deadline,
    );
  }
  return [
    for (final day in days.keys.toList()..sort())
      (day: day, count: days[day]!.count, deadline: days[day]!.deadline),
  ];
}

/// Over the composer while its model is of ChatGPT accounts some of whose
/// reset credits expire within [within]: a plan to use them up before
/// then, and a way to have them used by themselves. Not shown again in
/// this run once put off.
class ResetCreditsHint extends StatelessWidget {
  const ResetCreditsHint({
    super.key,
    required this.model,
    this.providers,
    this.codex,
    this.clock,
  });

  /// The composer's model (`@<provider>/<model>`).
  final String? model;
  final ModelProviders? providers;
  final CodexService? codex;
  final DateTime Function()? clock;

  static const within = Duration(days: 7);

  /// At most this many days of the plan are listed.
  static const maxDays = 5;

  /// Put off with "Got It", in every chat until the app starts again.
  @visibleForTesting
  static final putOff = ValueNotifier(false);

  static String _time(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _day(AppLocalizations l10n, DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (day.difference(today).inDays) {
      0 => l10n.resetCreditsHintToday,
      1 => l10n.resetCreditsHintTomorrow,
      _ => '${day.month}/${day.day}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final providers = this.providers ?? ModelProviders.current;
    final codex = this.codex ?? codexService;
    return ListenableBuilder(
      listenable: Listenable.merge([providers, codex, putOff]),
      builder: (context, _) {
        final provider = providers.provider(parseModelRef(model)?.provider);
        if (putOff.value ||
            provider == null ||
            !provider.protocol.usesAccounts) {
          return const SizedBox.shrink();
        }
        final now = (clock ?? DateTime.now)();
        final expiries = <DateTime>[
          for (final account in provider.accounts)
            if (account.enabled && !codex.signedOut(provider.id, account.id))
              for (final credit
                  in codex.resetCredits(provider.id, account.id) ??
                      const <CodexResetCredit>[])
                if (credit.expiresAt case final at?
                    when at.isAfter(now) && at.difference(now) <= within)
                  at,
        ];
        if (expiries.isEmpty) return const SizedBox.shrink();
        final plan = resetCreditPlan(expiries, now);
        final l10n = context.l10n;
        final accent = AppColors.accent;
        final detail = TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          height: 1.5,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: .35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Codicons.history, size: 15, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.resetCreditsHint(expiries.length),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final day in plan.take(maxDays))
                        Text(
                          [
                            l10n.resetCreditsHintDay(
                              _day(l10n, day.day, now),
                              day.count,
                            ),
                            l10n.resetCreditsHintBy(_time(day.deadline)),
                          ].join(' · '),
                          style: detail,
                        ),
                      if (plan.length > maxDays) Text('…', style: detail),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PanelButton(
                  label: l10n.resetCreditsHintLater,
                  onTap: () => putOff.value = true,
                ),
                if (!provider.autoResetCredits) ...[
                  const SizedBox(width: 6),
                  PanelButton(
                    label: l10n.resetCreditsHintAuto,
                    primary: true,
                    onTap: () => unawaited(
                      providers.save(provider.copyWith(autoResetCredits: true)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
