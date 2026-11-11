/// The limit resets Anthropic grants a Claude subscription (`cedar_ember`
/// in `/api/oauth/usage?cedar_ember=1`): each, used, sets the windows it
/// lists back to nothing used, as Claude Code's own offer of one does.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// One grant: how many resets are left of it, until when, and what a reset
/// of it clears.
class ClaudeResetGrant {
  const ClaudeResetGrant({
    required this.id,
    required this.left,
    this.label,
    this.startsAt,
    this.endsAt,
    this.clears = const [],
    this.used = const {},
    this.paused = false,
    this.usableNow = true,
  });

  final String id;

  /// As the server words it (in English): `One full limit reset …`.
  final String? label;
  final int left;
  final DateTime? startsAt;

  /// Until when it can be used.
  final DateTime? endsAt;

  /// The windows a reset sets back: `five_hour`, `seven_day`,
  /// `seven_day_overage_included` (the weekly one of a model, Fable's)…
  final List<String> clears;

  /// How much of each window is used now, 0 to 100.
  final Map<String, int> used;
  final bool paused;
  final bool usableNow;

  bool liveAt(DateTime now) =>
      left > 0 &&
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (endsAt == null || endsAt!.isAfter(now));

  static final _id = RegExp(r'^[a-z0-9_-]{1,40}$');

  static ClaudeResetGrant? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final left = json['resets_left'];
    if (id is! String || !_id.hasMatch(id) || left is! num) return null;
    return ClaudeResetGrant(
      id: id,
      left: left.toInt(),
      label: switch (json['label']) {
        final String label when label.trim().isNotEmpty => label.trim(),
        _ => null,
      },
      startsAt: _time(json['starts_at']),
      endsAt: _time(json['ends_at']),
      clears: [
        if (json['clears'] case final List clears)
          for (final window in clears)
            if (window is String) window,
      ],
      used: {
        if (json['percent_used'] case final Map used)
          for (final MapEntry(:key, :value) in used.entries)
            if (key is String && value is num) key: value.round(),
      },
      paused: json['paused'] == true,
      usableNow: json['usable_now'] != false,
    );
  }
}

/// An account's resets, as last asked.
class ClaudeResets {
  const ClaudeResets({
    required this.at,
    required this.eligible,
    this.reason,
    this.grants = const [],
    this.nextGrantId,
    this.cooldownUntil,
    this.scopedModel,
  });

  /// When it was asked.
  final DateTime at;

  /// Whether this sign-in may use one at all; [reason] why not.
  final bool eligible;
  final String? reason;
  final List<ClaudeResetGrant> grants;

  /// The one the server takes next: the only one it lets be used, others
  /// refused as `not_next_grant`.
  final String? nextGrantId;
  final DateTime? cooldownUntil;

  /// The model whose weekly limit is its own (`Fable`): what
  /// `seven_day_overage_included` is.
  final String? scopedModel;

  /// Those with resets left, not expired: the soonest to expire first.
  List<ClaudeResetGrant> get live =>
      [
        for (final grant in grants)
          if (grant.liveAt(at)) grant,
      ]..sort((a, b) {
        final x = a.endsAt, y = b.endsAt;
        if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
        return x.compareTo(y);
      });

  int get count => live.fold(0, (sum, grant) => sum + grant.left);

  /// The grant a reset is taken from now, if one can be.
  ClaudeResetGrant? get next {
    if (!eligible || cooldownUntil?.isAfter(at) == true) return null;
    for (final grant in live) {
      if (grant.id == nextGrantId && !grant.paused && grant.usableNow) {
        return grant;
      }
    }
    return null;
  }

  /// From a `/api/oauth/usage?cedar_ember=1` answer; null when it has no
  /// such block (not offered to this account, or not asked).
  static ClaudeResets? fromUsage(Object? json, DateTime now) {
    if (json is! Map) return null;
    final block = json['cedar_ember'];
    if (block is! Map) return null;
    return ClaudeResets(
      at: now,
      eligible: block['eligible'] == true,
      reason: switch (block['ineligible_reason']) {
        final String reason when reason.isNotEmpty => reason,
        _ => null,
      },
      grants: [
        if (block['grants'] case final List grants)
          for (final grant in grants) ?ClaudeResetGrant.fromJson(grant),
      ],
      nextGrantId: switch (block['next_grant_id']) {
        final String id when id.isNotEmpty => id,
        _ => null,
      },
      cooldownUntil: _time(block['cooldown_until']),
      scopedModel: [
        if (json['limits'] case final List limits)
          for (final limit in limits)
            if (limit
                case {
                  'kind': 'weekly_scoped',
                  'scope': {'model': {'display_name': final String name}},
                }
                when name.isNotEmpty)
              name,
      ].firstOrNull,
    );
  }
}

/// What using one came to: `reset` when it did, else the server's word
/// for why not (`not_limited`, `already_used`, `unavailable`…).
class ClaudeResetOutcome {
  const ClaudeResetOutcome(this.result, {this.reason, this.cleared = const []});

  final String result;
  final String? reason;
  final List<String> cleared;

  bool get reset => result == 'reset';

  /// The server's [reason] when the grant asked for is not the next: only
  /// that one can be used.
  static const notNext = 'not_next_grant';

  static ClaudeResetOutcome fromJson(Object? json) => switch (json) {
    {'result': final String result} when result.isNotEmpty =>
      ClaudeResetOutcome(
        result,
        reason: switch (json['reason']) {
          final String reason when reason.isNotEmpty => reason,
          _ => null,
        },
        cleared: [
          if (json['cleared'] case final List cleared)
            for (final window in cleared)
              if (window is String) window,
        ],
      ),
    _ => const ClaudeResetOutcome('error', reason: 'unreadable answer'),
  };
}

/// Why the resets could not be asked for, or one used.
class ClaudeResetsException implements Exception {
  const ClaudeResetsException(this.message, {this.signedOut = false});

  final String message;

  /// The sign-in is expired or refused: Claude Code renews it as it runs.
  final bool signedOut;

  @override
  String toString() => message;
}

/// Where the resets are asked for, and one used: Claude Code's sign-in on
/// this machine, as its CLI asks.
abstract interface class ClaudeResetsApi {
  /// The `/api/oauth/usage?cedar_ember=1` answer; null with no Claude.ai
  /// sign-in here (an API key, or none).
  Future<Map<String, Object?>?> usage();

  /// Uses one of [grantId], once whatever [requestId] is sent again.
  Future<Map<String, Object?>> claim(String grantId, String requestId);
}

/// The resets of Claude Code's sign-in here: asked as the models page
/// shows, one used only as the user confirms it.
class ClaudeResetsService extends ChangeNotifier {
  ClaudeResetsService(this._api, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ClaudeResetsApi _api;
  final DateTime Function() _now;

  /// Not asked again within this: the endpoint limits how often.
  static const fresh = Duration(minutes: 1);

  ClaudeResets? get resets => _resets;
  ClaudeResets? _resets;

  /// Why the last asking failed.
  String? get error => _error;
  String? _error;

  /// The sign-in has to be renewed (by Claude Code running) first.
  bool get signedOut => _signedOut;
  bool _signedOut = false;

  bool get loading => _loading != null;
  Future<void>? _loading;
  DateTime? _askedAt;

  bool get using => _using;
  bool _using = false;

  Future<void> refresh({bool force = false}) {
    if (_loading case final loading?) return loading;
    if (!force && _askedAt != null && _now().difference(_askedAt!) < fresh) {
      return Future.value();
    }
    final loading = _load();
    _loading = loading;
    notifyListeners();
    return loading.whenComplete(() {
      _loading = null;
      notifyListeners();
    });
  }

  Future<void> _load() async {
    _askedAt = _now();
    try {
      final usage = await _api.usage();
      _resets = usage == null ? null : ClaudeResets.fromUsage(usage, _now());
      _error = null;
      _signedOut = false;
    } on ClaudeResetsException catch (error) {
      _error = error.message;
      _signedOut = error.signedOut;
    }
  }

  /// Uses one of [grant], as it still is the one next once asked again: what
  /// the server answered. Never sent twice: a failure is told, not retried.
  Future<ClaudeResetOutcome> use(ClaudeResetGrant grant) async {
    if (_using) return const ClaudeResetOutcome('busy');
    _using = true;
    notifyListeners();
    try {
      await refresh(force: true);
      final next = _resets?.next;
      if (next == null) {
        return ClaudeResetOutcome(
          'unavailable',
          reason: _error ?? 'no longer offered',
        );
      }
      // Another one is next now: as the server would refuse it.
      if (next.id != grant.id) {
        return const ClaudeResetOutcome(
          'ineligible',
          reason: ClaudeResetOutcome.notNext,
        );
      }
      final outcome = ClaudeResetOutcome.fromJson(
        await _api.claim(grant.id, _requestId()),
      );
      return outcome;
    } on ClaudeResetsException catch (error) {
      return ClaudeResetOutcome('error', reason: error.message);
    } finally {
      _using = false;
      // What is left of them, and of the windows, now.
      unawaited(refresh(force: true));
    }
  }

  static final _random = Random.secure();

  /// A version-4 UUID, as the CLI's are.
  static String _requestId() {
    final bytes = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return [
      hex.sublist(0, 4).join(),
      hex.sublist(4, 6).join(),
      hex.sublist(6, 8).join(),
      hex.sublist(8, 10).join(),
      hex.sublist(10).join(),
    ].join('-');
  }
}

/// An RFC 3339 time.
DateTime? _time(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => DateTime.tryParse(
    text.trim(),
  ),
  _ => null,
};
