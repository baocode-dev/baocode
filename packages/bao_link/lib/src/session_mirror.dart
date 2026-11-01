import 'dart:convert';

import 'protocol.dart';

/// A session update as the desktop sends it after the first, slimmed
/// against what it sent before:
///
/// - `"partial": true`: of `live`, `interaction`, `choices`, `changes`,
///   `tasks`, `earlier`, `goal`, only those that changed are there (null:
///   gone);
/// - `"append": {"index", "path", "text"}`: the item at `index` (the one
///   before `start`) is as before but for `text` added at the end of the
///   string at `path` in it (keys and list indices); the items from `start`
///   follow whole as ever: the message streaming in (with the live line
///   after it), without sending all of it again each time.
///
/// [LinkSessionMirror] makes whole updates of these again on the phone.
abstract final class LinkSessionWire {
  static const rest = [
    'live',
    'interaction',
    'choices',
    'changes',
    'tasks',
    'earlier',
    'goal',
  ];
}

/// The desktop's end of [LinkSessionWire]: slims a session's updates
/// against what it sent before.
class LinkSessionSlimmer {
  /// The rest as last sent, each field as JSON text.
  Map<String, String> _rest = const {};

  /// [update] for the wire: whole when [full]; else with only the rest
  /// that changed, and, when its first item is [before] (that item's JSON
  /// as sent last) with text added to one string of it, that text alone.
  Map<String, Object?> encode(
    LinkSessionUpdate update, {
    bool full = false,
    Object? before,
  }) {
    final json = update.toJson();
    final rest = {
      for (final key in LinkSessionWire.rest) key: jsonEncode(json[key]),
    };
    final previous = _rest;
    _rest = rest;
    if (full) return json;
    final slim = <String, Object?>{
      'session': update.session,
      'start': update.start,
      'count': update.count,
      'items': update.items,
      'partial': true,
      for (final key in LinkSessionWire.rest)
        if (rest[key] != previous[key]) key: json[key],
    };
    if (before != null && update.items.isNotEmpty) {
      if (jsonAppendPatch(before, update.items.first) case (
        final path,
        final text,
      )) {
        slim
          ..['start'] = update.start + 1
          ..['items'] = update.items.sublist(1)
          ..['append'] = {'index': update.start, 'path': path, 'text': text};
      }
    }
    return slim;
  }
}

/// The phone's copy of each session it follows, as the desktop told it, to
/// make whole updates of slim ones (see [LinkSessionWire]).
class LinkSessionMirror {
  final Map<String, _Mirrored> _sessions = {};

  /// The whole update an `open` answered with.
  void opened(Map<String, Object?> update) {
    final session = update['session'];
    if (session is! String) return;
    _sessions[session] = _Mirrored(
      [...?(update['items'] as List?)],
      {for (final key in LinkSessionWire.rest) key: update[key]},
    );
  }

  /// [items] put before the first (an `earlier` answer).
  void earlier(String session, List<Object?> items) {
    final mirrored = _sessions[session];
    if (mirrored != null) mirrored.items.insertAll(0, items);
  }

  void closed(String session) => _sessions.remove(session);

  /// The whole update [update] makes: what the phone used to be sent, its
  /// items from the first that changed. Null when it does not fit the
  /// copy kept (some update was missed): the session should be opened
  /// again.
  Map<String, Object?>? apply(Map<String, Object?> update) {
    final session = update['session'];
    if (session is! String) return null;
    final partial = update['partial'] == true;
    var mirrored = _sessions[session];
    if (mirrored == null) {
      if (partial || update['append'] != null || update['start'] != 0) {
        return null;
      }
      mirrored = _sessions[session] = _Mirrored([], {});
    }
    final start = update['start'];
    final count = update['count'];
    final items = update['items'];
    if (start is! int || count is! int || items is! List) return null;
    if (start < 0 || start > mirrored.items.length) return null;
    final next = [...mirrored.items.take(start), ...items];
    var from = start;
    if (update['append'] case final Object append) {
      if (append
          case {
            'index': final int index,
            'path': final List<Object?> path,
            'text': final String text,
          }
          when index >= 0 && index < next.length) {
        final patched = applyAppend(next[index], path, text);
        if (patched == null) return null;
        next[index] = patched;
        if (index < from) from = index;
      } else {
        return null;
      }
    }
    if (next.length != count) return null;
    mirrored.items
      ..clear()
      ..addAll(next);
    if (partial) {
      for (final key in LinkSessionWire.rest) {
        if (update.containsKey(key)) mirrored.rest[key] = update[key];
      }
    } else {
      mirrored.rest = {
        for (final key in LinkSessionWire.rest) key: update[key],
      };
    }
    return {
      'session': session,
      'start': from,
      'count': count,
      'items': next.sublist(from),
      for (final MapEntry(:key, :value) in mirrored.rest.entries) key: ?value,
    };
  }
}

class _Mirrored {
  _Mirrored(this.items, this.rest);

  final List<Object?> items;
  Map<String, Object?> rest;
}

/// Where [after] differs from [before] by text added at the end of one
/// string in it: that string's path (keys, list indices) and the text.
/// Null when it differs otherwise, or not at all.
(List<Object>, String)? jsonAppendPatch(Object? before, Object? after) {
  if (before is String && after is String) {
    if (after.length > before.length && after.startsWith(before)) {
      return (const [], after.substring(before.length));
    }
    return null;
  }
  if (before is Map && after is Map) {
    if (before.length != after.length) return null;
    Object? differing;
    for (final key in after.keys) {
      if (!before.containsKey(key)) return null;
      if (!_same(before[key], after[key])) {
        if (differing != null) return null;
        differing = key;
      }
    }
    if (differing is! String) return null;
    final inner = jsonAppendPatch(before[differing], after[differing]);
    if (inner == null) return null;
    return ([differing, ...inner.$1], inner.$2);
  }
  if (before is List && after is List) {
    if (before.length != after.length) return null;
    int? differing;
    for (var i = 0; i < after.length; i++) {
      if (!_same(before[i], after[i])) {
        if (differing != null) return null;
        differing = i;
      }
    }
    if (differing == null) return null;
    final inner = jsonAppendPatch(before[differing], after[differing]);
    if (inner == null) return null;
    return ([differing, ...inner.$1], inner.$2);
  }
  return null;
}

/// [json] with [text] added to the string at [path]; null when there is
/// no string there. What is not on the path is shared, not copied.
Object? applyAppend(Object? json, List<Object?> path, String text) {
  if (path.isEmpty) return json is String ? json + text : null;
  final [step, ...rest] = path;
  switch ((json, step)) {
    case (final Map<String, Object?> map, final String key)
        when map.containsKey(key):
      final inner = applyAppend(map[key], rest, text);
      if (inner == null) return null;
      return {...map, key: inner};
    case (final List<Object?> list, final int index)
        when index >= 0 && index < list.length:
      final inner = applyAppend(list[index], rest, text);
      if (inner == null) return null;
      return [...list]..[index] = inner;
  }
  return null;
}

bool _same(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_same(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
