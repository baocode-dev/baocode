import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Whether a model's API runs Anthropic's `web_search` tool itself, as
/// last seen, by provider, protocol and model: kept [ttl] (5 hours), in a
/// file at [path] when given, so that it is found out once, not on each
/// search.
///
/// Only what is known is kept (see `nativeSearchOutcome`): a search that
/// failed for another reason (a limit, the network) says nothing either
/// way.
class NativeSearchSupport {
  NativeSearchSupport({
    this._path,
    this.ttl = const Duration(hours: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String Function()? _path;
  final DateTime Function() _now;
  final Duration ttl;

  Map<String, ({bool native, DateTime at})>? _entries;
  Future<void>? _writing;
  var _dirty = false;

  static String _key(String provider, String protocol, String model) =>
      '$provider\n$protocol\n$model';

  /// What was last seen of [model], unless it is older than [ttl]: null
  /// when not known.
  bool? lookup(String provider, String protocol, String model) {
    final entry = _load()[_key(provider, protocol, model)];
    if (entry == null) return null;
    if (_now().difference(entry.at) >= ttl) return null;
    return entry.native;
  }

  /// That [model] does ([native]) or does not run the tool itself.
  void record(String provider, String protocol, String model, bool native) {
    final entries = _load();
    final key = _key(provider, protocol, model);
    final now = _now();
    entries.removeWhere((_, entry) => now.difference(entry.at) >= ttl);
    entries[key] = (native: native, at: now);
    _save();
  }

  /// Forgets what was seen of [model], or of all.
  void forget([String? provider, String? protocol, String? model]) {
    final entries = _load();
    if (provider == null) {
      entries.clear();
    } else {
      entries.remove(_key(provider, protocol ?? '', model ?? ''));
    }
    _save();
  }

  Map<String, ({bool native, DateTime at})> _load() {
    if (_entries case final entries?) return entries;
    final entries = _entries = {};
    final path = _path?.call();
    if (path == null) return entries;
    try {
      final file = File(path);
      if (!file.existsSync()) return entries;
      final json = jsonDecode(file.readAsStringSync());
      if (json case {'entries': final Map<String, Object?> saved}) {
        for (final MapEntry(:key, :value) in saved.entries) {
          if (value case {'native': final bool native, 'at': final int at}) {
            entries[key] = (
              native: native,
              at: DateTime.fromMillisecondsSinceEpoch(at),
            );
          }
        }
      }
    } on Object {
      // Unreadable: found out again.
    }
    return entries;
  }

  void _save() {
    if (_path == null) return;
    _dirty = true;
    _writing ??= Future(() async {
      try {
        while (_dirty) {
          _dirty = false;
          final path = _path();
          final json = jsonEncode({
            'entries': {
              for (final MapEntry(:key, :value) in _entries!.entries)
                key: {
                  'native': value.native,
                  'at': value.at.millisecondsSinceEpoch,
                },
            },
          });
          final file = File(path);
          await file.parent.create(recursive: true);
          final temporary = File('$path.tmp');
          await temporary.writeAsString(json, flush: true);
          await temporary.rename(path);
        }
      } on Object {
        // Not kept: found out again next time.
      } finally {
        _writing = null;
      }
    });
  }

  /// Done when what was recorded is written.
  Future<void> flush() async {
    for (var writing = _writing; writing != null; writing = _writing) {
      await writing;
    }
  }
}
