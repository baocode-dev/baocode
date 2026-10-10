/// How much of a ChatGPT account's Codex quota is used: its windows (five
/// hours, a week), as `/wham/usage` answers and each reply's
/// `x-codex-*` headers tell.
library;

/// One window of a quota: how much of it is used, and when it starts
/// over.
class CodexWindow {
  const CodexWindow({required this.usedPercent, this.minutes, this.resetsAt});

  /// 0 to 100.
  final double usedPercent;

  /// How long it is: 300 for five hours, 10080 for a week.
  final int? minutes;
  final DateTime? resetsAt;

  double get leftPercent => (100 - usedPercent).clamp(0, 100).toDouble();

  /// As `/wham/usage` has it (`used_percent`, `limit_window_seconds`,
  /// `reset_at` or `reset_after_seconds`).
  static CodexWindow? fromJson(Object? json, DateTime now) {
    if (json is! Map) return null;
    final used = json['used_percent'];
    if (used is! num) return null;
    return CodexWindow(
      usedPercent: used.toDouble(),
      minutes: switch (json['limit_window_seconds']) {
        final num seconds when seconds > 0 => (seconds / 60).round(),
        _ => null,
      },
      resetsAt: _resetsAt(json['reset_at'], json['reset_after_seconds'], now),
    );
  }

  /// As a reply's headers have it (`x-codex-primary-used-percent`…).
  static CodexWindow? fromHeaders(
    String? Function(String name) header,
    String prefix,
    DateTime now,
  ) {
    final used = double.tryParse(header('$prefix-used-percent') ?? '');
    if (used == null) return null;
    return CodexWindow(
      usedPercent: used,
      minutes: int.tryParse(header('$prefix-window-minutes') ?? ''),
      resetsAt: _resetsAt(
        num.tryParse(header('$prefix-reset-at') ?? ''),
        num.tryParse(header('$prefix-reset-after-seconds') ?? ''),
        now,
      ),
    );
  }

  static DateTime? _resetsAt(Object? at, Object? after, DateTime now) {
    if (at is num && at > 0) {
      return DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000);
    }
    if (after is num && after >= 0) {
      return now.add(Duration(seconds: after.toInt()));
    }
    return null;
  }
}

/// An account's quota, as last known.
class CodexUsage {
  const CodexUsage({
    required this.at,
    this.plan,
    this.primary,
    this.secondary,
    this.limitReached = false,
    this.credits,
  });

  /// When it was learned.
  final DateTime at;
  final String? plan;

  /// The shorter window (five hours).
  final CodexWindow? primary;

  /// The longer one (a week).
  final CodexWindow? secondary;

  /// Out of quota: no request goes through until a window starts over.
  final bool limitReached;

  /// The credits left beyond the plan, as the backend words them; null
  /// without any.
  final String? credits;

  List<CodexWindow> get windows => [?primary, ?secondary];

  /// The most used of its windows, 0 to 100; null when none is known.
  double? get mostUsed => windows.isEmpty
      ? null
      : windows.map((w) => w.usedPercent).reduce((a, b) => a > b ? a : b);

  /// Until when it can take no request: the latest reset of a window used
  /// up, when the limit is reached.
  DateTime? get limitedUntil {
    final full = [
      for (final window in windows)
        if (window.usedPercent >= 100 || limitReached) ?window.resetsAt,
    ];
    if (full.isEmpty) return null;
    return full.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// As `/wham/usage` answers.
  static CodexUsage fromJson(Object? json, DateTime now) {
    final map = json is Map ? json : const {};
    final limits = map['rate_limit'] is Map ? map['rate_limit'] as Map : null;
    final credits = map['credits'] is Map ? map['credits'] as Map : null;
    return CodexUsage(
      at: now,
      plan: switch (map['plan_type']) {
        final String plan when plan.isNotEmpty => plan,
        _ => null,
      },
      primary: CodexWindow.fromJson(limits?['primary_window'], now),
      secondary: CodexWindow.fromJson(limits?['secondary_window'], now),
      limitReached:
          limits?['limit_reached'] == true || limits?['allowed'] == false,
      credits: switch (credits) {
        {'unlimited': true} => 'unlimited',
        {'has_credits': true, 'balance': final Object balance?} => '$balance',
        _ => null,
      },
    );
  }

  /// As a reply's headers tell, over [previous] (what they do not tell
  /// kept); null when they tell nothing.
  static CodexUsage? fromHeaders(
    String? Function(String name) header,
    DateTime now, {
    CodexUsage? previous,
  }) {
    final primary = CodexWindow.fromHeaders(header, 'x-codex-primary', now);
    final secondary = CodexWindow.fromHeaders(header, 'x-codex-secondary', now);
    if (primary == null && secondary == null) return null;
    return CodexUsage(
      at: now,
      plan: switch (header('x-codex-plan-type')) {
        final String plan when plan.isNotEmpty => plan,
        _ => previous?.plan,
      },
      primary: primary ?? previous?.primary,
      secondary: secondary ?? previous?.secondary,
      credits: previous?.credits,
    );
  }
}
