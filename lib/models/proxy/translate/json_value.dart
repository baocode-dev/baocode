// Part of the port of CLIProxyAPI's translators (MIT License; see NOTICE.md
// beside this file). They were written against tidwall/gjson: this is the
// part of it they read with, over a decoded JSON value.

import 'dart:convert';

/// What kind of JSON value a [JsonValue] holds, as gjson's `Type` (an
/// object or an array is [json]).
enum JsonType { none, nil, falsy, truthy, number, string, json }

/// A JSON value read by path, as a gjson `Result`: missing values read as
/// empty, numbers and booleans read as text and the other way round.
class JsonValue {
  const JsonValue(this.value) : exists = true;
  const JsonValue._missing() : value = null, exists = false;

  static const missing = JsonValue._missing();

  /// [raw] decoded; missing when it is not JSON.
  factory JsonValue.parse(String raw) {
    try {
      return JsonValue(jsonDecode(raw));
    } on FormatException {
      return missing;
    }
  }

  /// [value] if it is a JSON text, else the value itself.
  factory JsonValue.of(Object? value) =>
      value is String ? JsonValue.parse(value) : JsonValue(value);

  /// The decoded value: a map, list, string, number, bool or null.
  final Object? value;
  final bool exists;

  JsonType get type {
    if (!exists) return JsonType.none;
    return switch (value) {
      null => JsonType.nil,
      false => JsonType.falsy,
      true => JsonType.truthy,
      num() => JsonType.number,
      String() => JsonType.string,
      _ => JsonType.json,
    };
  }

  bool get isObject => exists && value is Map;
  bool get isArray => exists && value is List;
  bool get isString => exists && value is String;
  bool get isNull => exists && value == null;

  /// The value at [path]: keys and indexes joined by dots (a dot in a key
  /// escaped as `\.`); `#` is an array's length, or with more after it,
  /// that path in each of its items.
  JsonValue get(String path) {
    if (path.isEmpty) return this;
    return _get(this, _segments(path));
  }

  static List<String> _segments(String path) {
    final segments = <String>[];
    final current = StringBuffer();
    for (var i = 0; i < path.length; i++) {
      final char = path[i];
      if (char == r'\' && i + 1 < path.length) {
        current.write(path[++i]);
      } else if (char == '.') {
        segments.add('$current');
        current.clear();
      } else {
        current.write(char);
      }
    }
    segments.add('$current');
    return segments;
  }

  static JsonValue _get(JsonValue from, List<String> segments) {
    var node = from;
    for (var i = 0; i < segments.length; i++) {
      if (!node.exists) return missing;
      final segment = segments[i];
      final value = node.value;
      if (segment == '#' && value is List) {
        if (i == segments.length - 1) return JsonValue(value.length);
        final rest = segments.sublist(i + 1);
        return JsonValue([
          for (final item in value)
            if (_get(JsonValue(item), rest) case final found when found.exists)
              found.value,
        ]);
      }
      if (value is Map) {
        if (!value.containsKey(segment)) return missing;
        node = JsonValue(value[segment]);
      } else if (value is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= value.length) return missing;
        node = JsonValue(value[index]);
      } else {
        return missing;
      }
    }
    return node;
  }

  /// As gjson's `String()`: a string as it is, anything else as its JSON
  /// text; empty when missing or null.
  String get string => switch (value) {
    _ when !exists => '',
    null => '',
    final String text => text,
    final bool flag => '$flag',
    final num number => _number(number),
    _ => raw,
  };

  /// As gjson's `Int()`: numbers truncated, numeric text parsed, true as 1.
  int get integer => switch (value) {
    final int number => number,
    final double number when number.isFinite => number.truncate(),
    final String text =>
      int.tryParse(text.trim()) ??
          double.tryParse(text.trim())?.truncate() ??
          0,
    true => 1,
    _ => 0,
  };

  /// As gjson's `Float()`.
  double get number => switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text.trim()) ?? 0,
    true => 1,
    _ => 0,
  };

  /// As gjson's `Bool()`.
  bool get boolean => switch (value) {
    final bool flag => flag,
    final num number => number != 0,
    final String text => const {
      '1',
      't',
      'T',
      'TRUE',
      'true',
      'True',
    }.contains(text),
    _ => false,
  };

  /// The value's JSON text; empty when missing.
  String get raw => exists ? jsonEncode(value) : '';

  List<JsonValue> get array => switch (value) {
    final List<Object?> items when exists => [
      for (final item in items) JsonValue(item),
    ],
    _ => const [],
  };

  /// An object's entries, in order.
  Map<String, JsonValue> get map => switch (value) {
    final Map<Object?, Object?> entries when exists => {
      for (final MapEntry(:key, :value) in entries.entries)
        '$key': JsonValue(value),
    },
    _ => const {},
  };

  static String _number(num number) {
    if (number is int) return '$number';
    if (number == number.truncateToDouble() && number.abs() < 1e15) {
      return number.truncate().toString();
    }
    return '$number';
  }

  @override
  String toString() => raw;
}

/// A deep copy of decoded JSON, for values set into an output that the
/// output's later changes must not reach back into.
Object? jsonCopy(Object? value) => switch (value) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries) '$key': jsonCopy(value),
  },
  final List<Object?> list => [for (final item in list) jsonCopy(item)],
  _ => value,
};
