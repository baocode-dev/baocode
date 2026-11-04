import 'dart:async';

import 'package:flutter/foundation.dart';

import '../workspace/preference_store.dart';

/// Whether an agent that hits the account's usage limit goes on by itself
/// once the limit resets: the `chat.resumeAfterLimitReset` setting, a
/// switch in the model picker beside Claude's own models.
abstract final class ResumeAfterResetSetting {
  static const settingKey = 'chat.resumeAfterLimitReset';

  /// Written when on; off, the setting is left out.
  static const on = true;

  /// Off unless set to true.
  static bool enabled(Object? setting) => setting == true;

  /// The setting as it is now, what tells it changed, and what sets it;
  /// main() points them at settings.json.
  static bool Function() current = () => false;
  static Listenable? changes;
  static void Function(bool on)? write;
}

/// An agent stopped at the usage limit, until it resets.
@immutable
class ResumeEntry {
  const ResumeEntry({required this.sessionId, required this.resetsAt});

  final String sessionId;
  final DateTime resetsAt;

  Map<String, Object?> toJson() => {
    'session': sessionId,
    'resetsAt': resetsAt.toUtc().toIso8601String(),
  };

  static ResumeEntry? fromJson(Object? json) => switch (json) {
    {'session': final String sessionId, 'resetsAt': final String resetsAt} =>
      switch (DateTime.tryParse(resetsAt)) {
        final at? => ResumeEntry(sessionId: sessionId, resetsAt: at.toLocal()),
        null => null,
      },
    _ => null,
  };
}

/// Continues [sessionId]'s agent: whether it was (or need not be any
/// more: it went on already, or is gone); false to be tried again.
typedef ResumeAgent = Future<bool> Function(String sessionId);

/// The agents stopped at the account's usage limit: with
/// [ResumeAfterResetSetting] on, each sent a message to continue once it
/// resets, by [resume] (the workspace's). Kept between runs: one due while
/// the app was closed goes on once it is open again.
class ResumeAfterReset extends ChangeNotifier {
  ResumeAfterReset({
    this._store,
    bool Function()? enabled,
    Listenable? enabledChanges,
    this.margin = const Duration(seconds: 60),
    this.retryAfter = const Duration(minutes: 1),
    this.attempts = 5,
    DateTime Function()? clock,
  }) : _enabled = enabled ?? (() => ResumeAfterResetSetting.current()),
       _enabledChanges = enabledChanges ?? ResumeAfterResetSetting.changes,
       _clock = clock ?? DateTime.now {
    _enabledChanges?.addListener(_settingChanged);
  }

  /// The app's; main() gives it a file to keep them in.
  static ResumeAfterReset current = ResumeAfterReset();

  /// Where the app keeps them, in its state folder.
  static const fileName = 'resume_after_reset.json';

  final PreferenceStore? _store;
  final bool Function() _enabled;
  final Listenable? _enabledChanges;
  final DateTime Function() _clock;

  /// Whether those listed go on once the limit resets.
  bool get enabled => _enabled();

  /// How long after the reset an agent goes on: the account's usage is
  /// not started over that very second.
  final Duration margin;

  /// How long before an agent that could not go on is tried again, and
  /// how many times in all.
  final Duration retryAfter;
  final int attempts;

  /// Continues an agent; none till the workspace has listed them.
  ResumeAgent? get resume => _resume;
  ResumeAgent? _resume;
  set resume(ResumeAgent? resume) {
    _resume = resume;
    _arm();
  }

  final Map<String, ResumeEntry> _entries = {};
  final Map<String, int> _failed = {};
  final Map<String, DateTime> _retryAt = {};

  /// The agents continued here since a turn of theirs last went through,
  /// and how many times: one stopped at the limit again goes on again.
  final Map<String, int> _resumed = {};
  Timer? _timer;
  bool _firing = false;
  bool _disposed = false;

  /// All of them, those resetting first first.
  List<ResumeEntry> get entries =>
      _entries.values.toList()
        ..sort((a, b) => a.resetsAt.compareTo(b.resetsAt));

  ResumeEntry? operator [](String sessionId) => _entries[sessionId];

  /// Reads those kept; those whose limit has reset with nothing to do
  /// are let go.
  Future<void> load() async {
    final kept = await _store?.read() ?? const {};
    if (_disposed) return;
    final now = _clock();
    for (final json in switch (kept['entries']) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    }) {
      final entry = ResumeEntry.fromJson(json);
      if (entry == null || _entries.containsKey(entry.sessionId)) continue;
      if (!enabled && !entry.resetsAt.isAfter(now)) continue;
      _entries[entry.sessionId] = entry;
    }
    _arm();
    notifyListeners();
  }

  /// [sessionId]'s agent hit the limit, which resets [resetsAt]: it goes
  /// on then, if the setting is on by then.
  ///
  /// That with a reset said that is past (the CLI's, not taken yet), when
  /// it was continued here: it goes on again [retryAfter] on, up to
  /// [attempts] times; one not continued here has nothing to wait for.
  void hit({required String sessionId, required DateTime resetsAt}) {
    final resumed = _resumed[sessionId] ?? 0;
    final stale = !resetsAt.isAfter(_clock());
    if (stale && (resumed == 0 || resumed >= attempts)) return;
    if (_entries[sessionId]?.resetsAt == resetsAt) return;
    _entries[sessionId] = ResumeEntry(sessionId: sessionId, resetsAt: resetsAt);
    _forgetTries(sessionId);
    if (stale) _retryAt[sessionId] = _clock().add(retryAfter);
    _changed();
  }

  /// Forgets [sessionId]'s agent: deleted, say, or a turn of it went
  /// through.
  void remove(String sessionId) {
    _resumed.remove(sessionId);
    if (_entries.remove(sessionId) == null) return;
    _forgetTries(sessionId);
    _changed();
  }

  void _forgetTries(String sessionId) {
    _failed.remove(sessionId);
    _retryAt.remove(sessionId);
  }

  /// Turned on, those waiting go on as their limit resets; off, they are
  /// let go then.
  void _settingChanged() {
    if (_disposed) return;
    _arm();
    notifyListeners();
  }

  void _changed() {
    _arm();
    _save();
    notifyListeners();
  }

  void _save() {
    final store = _store;
    if (store == null) return;
    unawaited(
      store
          .write({
            'entries': [for (final entry in entries) entry.toJson()],
          })
          .catchError((Object error) {
            // Not waited for: a failure is logged here; the store still gives it to
            // whoever waits.
            debugPrint('Resume entries not kept: $error');
          }),
    );
  }

  /// When [entry] is due to go on: [margin] after its reset, or once
  /// more after it could not.
  DateTime _dueOf(ResumeEntry entry) =>
      _retryAt[entry.sessionId] ?? entry.resetsAt.add(margin);

  /// Times the next to do: one due to go on, if the workspace can continue
  /// it, or, the setting off, one whose limit resets, to be let go then.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    // Armed again once those under way are done.
    if (_disposed || _firing) return;
    final on = enabled;
    if (on && _resume == null) return;
    DateTime? next;
    for (final entry in _entries.values) {
      final at = on ? _dueOf(entry) : entry.resetsAt;
      if (next == null || at.isBefore(next)) next = at;
    }
    if (next == null) return;
    final wait = next.difference(_clock());
    // Looked at again a minute on at most: a timer does not count the time
    // the computer slept, the clock does.
    _timer = Timer(
      wait.isNegative
          ? Duration.zero
          : wait < _recheck
          ? wait
          : _recheck,
      _fire,
    );
  }

  static const _recheck = Duration(minutes: 1);

  Future<void> _fire() async {
    _timer = null;
    if (_disposed) return;
    _firing = true;
    var changed = false;
    try {
      final now = _clock();
      final resume = _resume;
      if (!enabled) {
        // Their limit reset with nothing to do: no longer listed.
        for (final entry in [..._entries.values]) {
          if (entry.resetsAt.isAfter(now)) continue;
          _entries.remove(entry.sessionId);
          _forgetTries(entry.sessionId);
          changed = true;
        }
      } else if (resume != null) {
        final due = [
          for (final entry in _entries.values)
            if (!_dueOf(entry).isAfter(now)) entry,
        ];
        for (final entry in due) {
          var done = false;
          try {
            done = await resume(entry.sessionId);
          } on Object catch (error) {
            debugPrint('Not continued after the limit reset: $error');
          }
          if (_disposed) return;
          // Changed meanwhile: as it is now.
          if (!identical(_entries[entry.sessionId], entry)) continue;
          final failed = (_failed[entry.sessionId] ?? 0) + 1;
          if (done || failed >= attempts) {
            _entries.remove(entry.sessionId);
            _forgetTries(entry.sessionId);
            if (done) {
              _resumed[entry.sessionId] = (_resumed[entry.sessionId] ?? 0) + 1;
            }
            changed = true;
          } else {
            _failed[entry.sessionId] = failed;
            _retryAt[entry.sessionId] = _clock().add(retryAfter);
          }
        }
      }
    } finally {
      _firing = false;
    }
    if (changed) {
      _save();
      notifyListeners();
    }
    _arm();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _enabledChanges?.removeListener(_settingChanged);
    _timer?.cancel();
    super.dispose();
  }
}
