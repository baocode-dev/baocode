import 'package:flutter/foundation.dart' show Listenable;

import '../chat/chat_session.dart';
import '../kernel/agent_kernel.dart' show KernelChoiceKind;
import '../kernel/kernel_types.dart';
import '../models/codex/codex_service.dart';
import '../models/model_provider.dart';
import '../models/model_providers.dart';

/// A conversation's quota as the phone reads it (see
/// [LinkSessionUpdate.quota]): on a model of ChatGPT accounts, theirs, as
/// the bar under the composer has it (ChatQuotaBar); on Claude's own, the
/// plan's limits, as its kernel tells them.
class LinkQuota {
  LinkQuota({required this.providers, required this.codex});

  final ModelProviders providers;
  final CodexService codex;

  /// Tells when what [of] gives may have changed, but for the session's
  /// own (its limits, its model).
  late final Listenable changes = Listenable.merge([providers, codex]);

  /// The provider of [session]'s model, when it has ChatGPT accounts.
  ModelProvider? _provider(ChatSession session) {
    final ref = parseModelRef(session.selected(KernelChoiceKind.model));
    return switch (providers.provider(ref?.provider)) {
      final provider?
          when provider.protocol.usesAccounts && provider.accounts.isNotEmpty =>
        provider,
      _ => null,
    };
  }

  /// [session]'s quota now; null when it has none told here (another
  /// provider's model, an API key).
  Map<String, Object?>? of(ChatSession session) {
    if (_provider(session) case final provider?) {
      return _accounts(session, provider);
    }
    // Another provider's model: its limits are its own.
    if (parseModelRef(session.selected(KernelChoiceKind.model)) != null) {
      return null;
    }
    final limits = session.stats?.limits ?? const <RateLimitWindow>[];
    if (limits.isEmpty) return null;
    final now = DateTime.now();
    final full = [
      for (final limit in limits)
        if (limit.utilization >= 1 && (limit.resetsAt?.isAfter(now) ?? false))
          limit.resetsAt!,
    ];
    final back =
        session.usageLimitResetsAt ??
        full.fold<DateTime?>(
          null,
          (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
        );
    return {
      'provider': session.models?.selected.group?.label ?? 'Claude',
      'back': ?back?.millisecondsSinceEpoch,
      'accounts': [
        {
          'windows': [for (final limit in limits) _limit(limit)],
        },
      ],
    };
  }

  /// Asked again: the accounts', [force]d however lately they were
  /// learned; the plan's only [force]d, as the user asks (with no agent
  /// running, its kernel starts one to ask), and at most so often.
  Future<void> refresh(ChatSession session, {bool force = true}) async {
    if (_provider(session) case final provider?) {
      await codex.refreshUsage(provider, force: force);
    } else if (force &&
        parseModelRef(session.selected(KernelChoiceKind.model)) == null) {
      await session.refreshUsage();
    }
  }

  Map<String, Object?> _accounts(ChatSession session, ModelProvider provider) {
    final current = codex.accountFor(provider, session: session.sessionId)?.id;
    return {
      'provider': provider.name,
      'back': ?codex.backAt(provider)?.millisecondsSinceEpoch,
      'accounts': [
        for (final account in provider.accounts)
          if (codex.usage(provider.id, account.id) case final usage)
            {
              'name': account.displayName,
              'plan': ?(usage?.plan ?? account.plan),
              if (account.id == current) 'current': true,
              if (!account.enabled || codex.signedOut(provider.id, account.id))
                'off': true,
              'until': ?codex
                  .limitedUntil(provider.id, account.id)
                  ?.millisecondsSinceEpoch,
              'error': ?codex.error(provider.id, account.id),
              'at': ?usage?.at.millisecondsSinceEpoch,
              'windows': [
                for (final window in usage?.windows ?? const [])
                  {
                    'minutes': ?window.minutes,
                    'left': window.leftPercent.round(),
                    'resets': ?window.resetsAt?.millisecondsSinceEpoch,
                  },
              ],
            },
      ],
    };
  }

  /// A limit as Claude Code names it (`5-hour limit`, `Weekly Opus
  /// limit`): how long, and of what, for the phone to say in its words.
  static Map<String, Object?> _limit(RateLimitWindow limit) {
    final label = limit.label;
    final scoped = RegExp(r'^Weekly (.+) limit$').firstMatch(label);
    final resets = limit.resetsAt;
    // Past its reset, the window starts over.
    final over = resets != null && !resets.isAfter(DateTime.now());
    return {
      ...switch (label) {
        '5-hour limit' => {'minutes': 300},
        'Weekly limit' => {'minutes': 10080},
        _ when scoped != null => {'minutes': 10080, 'name': scoped.group(1)},
        _ => {'name': label},
      },
      'left': over
          ? 100
          : ((1 - limit.utilization) * 100).clamp(0, 100).round(),
      'resets': ?resets?.millisecondsSinceEpoch,
    };
  }
}
