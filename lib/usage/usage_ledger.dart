import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'usage_record.dart';

/// Where the calls are kept: a file of lines a day (`yyyy-MM-dd`), and an
/// index of the days each conversation has calls on.
abstract class UsageStorage {
  /// Adds [lines] to [day]'s.
  void append(String day, List<String> lines);

  /// The calls of [days], each day's in order.
  Future<List<UsageCall>> read(List<String> days);

  /// The days kept, oldest first.
  Future<List<String>> days();

  /// The bytes each day takes.
  Future<Map<String, int>> sizes();

  Future<void> delete(String day);

  /// [day]'s calls but those [drop] picks; how many were dropped.
  Future<int> rewrite(String day, bool Function(UsageCall call) drop);

  Future<Map<String, Object?>?> readIndex();
  void writeIndex(Map<String, Object?> index);
}

/// Kept in memory only: under test, and where there are no files.
class MemoryUsageStorage implements UsageStorage {
  final Map<String, List<String>> lines = {};
  Map<String, Object?>? index;

  @override
  void append(String day, List<String> lines) =>
      (this.lines[day] ??= []).addAll(lines);

  @override
  Future<List<UsageCall>> read(List<String> days) async => [
    for (final day in days)
      for (final line in lines[day] ?? const <String>[])
        ?UsageCall.decode(line),
  ];

  @override
  Future<List<String>> days() async => lines.keys.toList()..sort();

  @override
  Future<Map<String, int>> sizes() async => {
    for (final MapEntry(:key, :value) in lines.entries)
      key: value.fold(0, (sum, line) => sum + utf8.encode(line).length + 1),
  };

  @override
  Future<void> delete(String day) async => lines.remove(day);

  @override
  Future<int> rewrite(String day, bool Function(UsageCall call) drop) async {
    final kept = <String>[];
    var dropped = 0;
    for (final line in lines[day] ?? const <String>[]) {
      final call = UsageCall.decode(line);
      if (call != null && drop(call)) {
        dropped++;
      } else {
        kept.add(line);
      }
    }
    if (kept.isEmpty) {
      lines.remove(day);
    } else {
      lines[day] = kept;
    }
    return dropped;
  }

  @override
  Future<Map<String, Object?>?> readIndex() async => index;

  @override
  void writeIndex(Map<String, Object?> index) => this.index = index;
}

/// Which calls to delete: those in a time ([from] to [until]), of the
/// upstreams, models and conversation given; all where none is.
class UsageClearSpec {
  const UsageClearSpec({
    this.from,
    this.until,
    this.providers = const {},
    this.models = const {},
    this.session,
  });

  final DateTime? from;
  final DateTime? until;
  final Set<String> providers;
  final Set<String> models;
  final String? session;

  /// Whether it deletes whole days: no filter but the time.
  bool get byDay => providers.isEmpty && models.isEmpty && session == null;

  bool matches(UsageCall call) =>
      (from == null || !call.at.isBefore(from!)) &&
      (until == null || call.at.isBefore(until!)) &&
      (providers.isEmpty || providers.contains(call.provider)) &&
      (models.isEmpty || models.contains(call.model)) &&
      (session == null || call.session == session);
}

/// How much is kept.
typedef UsageSpace = ({int bytes, int days, String? oldest});

/// The calls to custom upstreams, kept as they come from the model proxy:
/// for the dashboard (Settings → Usage) and a conversation's own (its side
/// panel). Written a few at a time, a file a day, so a day, or all before
/// one, goes at once; kept as long as [retentionDays] says.
class UsageLedger extends ChangeNotifier {
  UsageLedger(this.storage, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The app's: in memory until main() gives it its folder.
  static UsageLedger current = UsageLedger(MemoryUsageStorage());

  /// The conversation's title and project, for a session's id: the
  /// window's agents. Kept with its calls, so they show by it after it is
  /// gone.
  static String? Function(String session)? titleOf;
  static String? Function(String session)? projectOf;

  final UsageStorage storage;
  final DateTime Function() _clock;

  static const enabledKey = 'usage.enabled';
  static const detailedKey = 'usage.detailed';
  static const retentionKey = 'usage.retentionDays';

  /// The choices of how long to keep them, in days (0: always).
  static const retentionChoices = [7, 30, 90, 180, 365, 0];
  static const defaultRetention = 90;

  /// Whether calls are kept: the sessions on a custom upstream go through
  /// the proxy for it.
  bool enabled = true;

  /// Whether what filled each request's context, and the tools', is kept.
  bool detailed = true;

  /// Days kept; 0 for always.
  int retentionDays = defaultRetention;

  UserSettings? _settings;

  /// Takes its choices from [settings], as they change.
  void follow(UserSettings settings) {
    _settings?.removeListener(_read);
    _settings = settings;
    settings.addListener(_read);
    _read();
  }

  void _read() {
    final settings = _settings;
    if (settings == null) return;
    final on = settings[enabledKey] != false;
    final detail = settings[detailedKey] != false;
    final days = switch (settings[retentionKey]) {
      final num days when days >= 0 => days.toInt(),
      _ => defaultRetention,
    };
    if (on == enabled && detail == detailed && days == retentionDays) return;
    final shorter = retentionDays == 0 || (days != 0 && days < retentionDays);
    enabled = on;
    detailed = detail;
    retentionDays = days;
    if (shorter) unawaited(prune());
    notifyListeners();
  }

  /// Keeps [key]'s [value] in settings.json (null: its default).
  Future<void> save(String key, Object? value) async {
    final settings = _settings;
    if (settings == null) {
      switch (key) {
        case enabledKey:
          enabled = value != false;
        case detailedKey:
          detailed = value != false;
        case retentionKey:
          retentionDays = (value as int?) ?? defaultRetention;
      }
      notifyListeners();
      return;
    }
    try {
      await settings.update(key, value);
    } on Object catch (error) {
      debugPrint('$key not kept: $error');
    }
  }

  // --- Recording ------------------------------------------------------------

  static String dayOf(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  static DateTime? parseDay(String day) => DateTime.tryParse(day);

  /// Grows each time a call is kept or some are deleted: what is shown of
  /// them is out of date.
  int get version => _version;
  int _version = 0;

  final Map<String, List<String>> _unwritten = {};
  Timer? _flush;
  Timer? _notify;

  /// The sessions and agents labeled already in each day's file.
  final Set<String> _labeled = {};

  /// Each session's days, as the index has them.
  Map<String, Set<String>>? _index;
  bool _indexChanged = false;

  /// Decoded days, those before today: they no longer change.
  final Map<String, List<UsageCall>> _decoded = {};

  /// Today's, as kept this run (and read).
  final Map<String, List<UsageCall>> _live = {};

  /// Keeps [call], unless calls are not kept.
  void record(UsageCall call) {
    if (!enabled) return;
    final day = dayOf(call.at);
    var kept = detailed ? call : call.brief;
    final session = call.session;
    String? title, project, task;
    if (session != null && _labeled.add('$day/$session')) {
      title = titleOf?.call(session);
      project = projectOf?.call(session);
    }
    if (call.agentId case final agent? when call.task != null) {
      if (_labeled.add('$day/agent/$agent')) task = call.task;
    }
    kept = kept.labeled(
      sessionTitle: title ?? kept.sessionTitle,
      project: project ?? kept.project,
      task: task,
    );
    (_unwritten[day] ??= []).add(kept.encode());
    (_live[day] ??= []).add(kept);
    _decoded.remove(day);
    if (session != null) {
      final days = (_index ??= {})[session] ??= {};
      if (days.add(day)) _indexChanged = true;
    }
    _flush ??= Timer(const Duration(milliseconds: 600), flush);
    _changed();
  }

  void _changed() {
    _version++;
    _notify ??= Timer(const Duration(milliseconds: 250), () {
      _notify = null;
      notifyListeners();
    });
  }

  /// Writes what is kept but not yet written.
  void flush() {
    _flush?.cancel();
    _flush = null;
    final unwritten = Map.of(_unwritten);
    _unwritten.clear();
    for (final MapEntry(:key, :value) in unwritten.entries) {
      storage.append(key, value);
    }
    if (_indexChanged && _index != null) {
      _indexChanged = false;
      storage.writeIndex({
        'v': 1,
        's': {
          for (final MapEntry(:key, :value) in _index!.entries)
            key: value.toList()..sort(),
        },
      });
    }
  }

  @override
  void dispose() {
    flush();
    _notify?.cancel();
    _settings?.removeListener(_read);
    super.dispose();
  }

  // --- Reading --------------------------------------------------------------

  Future<Map<String, Set<String>>> _sessions() async {
    if (_index case final index?) {
      if (!_indexRead) await _mergeIndex(index);
      return index;
    }
    final index = _index = {};
    await _mergeIndex(index);
    return index;
  }

  bool _indexRead = false;

  Future<void> _mergeIndex(Map<String, Set<String>> into) async {
    _indexRead = true;
    final json = await storage.readIndex();
    if (json?['s'] case final Map<Object?, Object?> sessions) {
      for (final MapEntry(:key, :value) in sessions.entries) {
        if (value is List) {
          (into['$key'] ??= {}).addAll(value.whereType<String>());
        }
      }
    }
  }

  Future<List<UsageCall>> _readDays(List<String> days) async {
    final today = dayOf(_clock());
    final missing = [
      for (final day in days)
        if (!_decoded.containsKey(day)) day,
    ];
    if (missing.isNotEmpty) {
      flush();
      final read = await storage.read(missing);
      final byDay = <String, List<UsageCall>>{};
      for (final call in read) {
        (byDay[dayOf(call.at)] ??= []).add(call);
      }
      for (final day in missing) {
        final calls = byDay[day] ?? <UsageCall>[];
        // Today's grows: read again each time it is asked for, but as
        // kept this run meanwhile.
        if (day == today) {
          _live[day] = calls;
        } else {
          _decoded[day] = calls;
        }
      }
      while (_decoded.length > 120) {
        _decoded.remove(_decoded.keys.first);
      }
    }
    return [for (final day in days) ...?(_decoded[day] ?? _live[day])];
  }

  /// The calls from [from] till [until] (all kept, without them).
  Future<List<UsageCall>> range({DateTime? from, DateTime? until}) async {
    final kept = await storage.days();
    final pending = _unwritten.keys.where((day) => !kept.contains(day));
    final first = from == null ? null : dayOf(from);
    final last = until == null ? null : dayOf(until);
    final days =
        {...kept, ...pending}
            .where(
              (day) =>
                  (first == null || day.compareTo(first) >= 0) &&
                  (last == null || day.compareTo(last) <= 0),
            )
            .toList()
          ..sort();
    final calls = await _readDays(days);
    return [
      for (final call in calls)
        if ((from == null || !call.at.isBefore(from)) &&
            (until == null || call.at.isBefore(until)))
          call,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  /// [session]'s calls.
  Future<List<UsageCall>> ofSession(String session) async {
    final days = (await _sessions())[session]?.toList() ?? const <String>[];
    final calls = await _readDays(days..sort());
    return [
      for (final call in calls)
        if (call.session == session) call,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<UsageSpace> space() async {
    flush();
    final sizes = await storage.sizes();
    final days = sizes.keys.toList()..sort();
    return (
      bytes: sizes.values.fold(0, (sum, size) => sum + size),
      days: days.length,
      oldest: days.firstOrNull,
    );
  }

  // --- Deleting -------------------------------------------------------------

  /// Deletes the calls [spec] picks; how many days' files changed.
  Future<int> clear(UsageClearSpec spec) async {
    flush();
    final first = spec.from == null ? null : dayOf(spec.from!);
    final last = spec.until == null ? null : dayOf(spec.until!);
    var changed = 0;
    for (final day in await storage.days()) {
      if (first != null && day.compareTo(first) < 0) continue;
      if (last != null && day.compareTo(last) > 0) continue;
      final start = parseDay(day);
      final whole =
          spec.byDay &&
          start != null &&
          (spec.from == null || !start.isBefore(spec.from!)) &&
          (spec.until == null ||
              !start.add(const Duration(days: 1)).isAfter(spec.until!));
      if (whole) {
        await storage.delete(day);
        changed++;
      } else if (await storage.rewrite(day, spec.matches) > 0) {
        changed++;
      }
      _decoded.remove(day);
      _live.remove(day);
    }
    _labeled.clear();
    _changed();
    notifyListeners();
    return changed;
  }

  /// Deletes the days kept longer than [retentionDays].
  Future<void> prune() async {
    if (retentionDays <= 0) return;
    final now = _clock();
    final before = DateTime(now.year, now.month, now.day - retentionDays + 1);
    final days = await storage.days();
    if (days.isEmpty || days.first.compareTo(dayOf(before)) >= 0) return;
    await clear(UsageClearSpec(until: before));
  }
}
