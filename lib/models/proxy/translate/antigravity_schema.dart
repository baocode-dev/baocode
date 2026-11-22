// Ported from magpie's internal/gateway/codeassist.go (plainSchema and
// what it uses; MIT License; see NOTICE.md beside this file).

import 'dart:convert';

/// [schema] cut down to what Antigravity's function declarations take: an
/// OpenAPI-style subset with no references, unions, or keywords outside
/// it. Antigravity refuses a request over any keyword it does not know.
Map<String, Object?> antigravitySchema(Object? schema) {
  if (schema is! Map) {
    return {'type': 'object', 'properties': <String, Object?>{}};
  }
  final root = _deepCopy(schema) as Map<String, Object?>;
  final out = _SchemaWalk(root).walk(root, 0, '');
  return out is Map<String, Object?> ? out : {'type': 'object'};
}

Object? _deepCopy(Object? value) => switch (value) {
  final Map map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries) '$key': _deepCopy(value),
  },
  final List list => [for (final item in list) _deepCopy(item)],
  _ => value,
};

class _SchemaWalk {
  _SchemaWalk(this.root) {
    for (final key in ['\$defs', 'definitions']) {
      if (root[key] case final Map defs) {
        for (final MapEntry(:key, :value) in defs.entries) {
          this.defs['$key'] = value;
        }
      }
    }
  }

  final Map<String, Object?> root;
  final Map<String, Object?> defs = {};
  final Set<String> _expanding = {};

  /// The schema a local `$ref` names: a JSON pointer, else a `$defs` name.
  (Object?, bool) _localRef(String ref) {
    Object? byName() {
      final name = ref.substring(ref.lastIndexOf('/') + 1);
      return defs[name];
    }

    if (ref.startsWith('#/')) {
      Object? current = root;
      for (var token in ref.substring(2).split('/')) {
        token = token.replaceAll('~1', '/').replaceAll('~0', '~');
        switch (current) {
          case final Map map:
            current = map[token];
          case final List list:
            final n = int.tryParse(token);
            if (n == null || n < 0 || n >= list.length) return (null, false);
            current = list[n];
          default:
            return (null, false);
        }
        if (current == null) {
          final named = byName();
          return (named, named != null);
        }
      }
      return (current, true);
    }
    if (ref == '#') return (root, true);
    final named = byName();
    return (named, named != null);
  }

  Map<String, Object?>? _resolve(Object? value) {
    var map = value is Map<String, Object?> ? value : null;
    if (map?['\$ref'] case final String ref) {
      final (target, found) = _localRef(ref);
      map = found && target is Map<String, Object?> ? target : null;
    }
    return map;
  }

  static bool _selfRef(String ref, String path) {
    if (!ref.startsWith('#')) return false;
    final r = ref.substring(1);
    return r.isEmpty || path == r || path.startsWith('$r/');
  }

  static String _typeOf(Map map) {
    if (map['type'] case final String type) return type;
    if (map['properties'] != null) return 'object';
    if (map['items'] != null) return 'array';
    return 'object';
  }

  /// The schema every member of a tuple that says anything says alike, or
  /// null when they differ or none says anything.
  static Object? _oneSays(List members) {
    Map? one;
    for (final member in members) {
      if (member is! Map || member.isEmpty) continue;
      if (one != null && jsonEncode(one) != jsonEncode(member)) return null;
      one = member;
    }
    return one;
  }

  Object? walk(Object? value, int depth, String path) {
    switch (value) {
      case final bool any:
        // true is any value, the schema {}; false none, left out.
        return any ? <String, Object?>{} : null;
      case final List list:
        return [for (final item in list) walk(item, depth, path)];
      case final Map<String, Object?> x:
        return _walkMap(x, depth, path);
    }
    return value;
  }

  Object? _walkMap(Map<String, Object?> x, int depth, String path) {
    if (depth > 32) return {'type': 'object'};
    if (x['\$ref'] case final String ref) {
      final (target, found) = _localRef(ref);
      if (!found) return {'type': 'object'};
      if (_expanding.contains(ref) || _selfRef(ref, path)) {
        return {'type': target is Map ? _typeOf(target) : 'object'};
      }
      _expanding.add(ref);
      final out = walk(
        target,
        depth + 1,
        ref.startsWith('#') ? ref.substring(1) : path,
      );
      _expanding.remove(ref);
      return out;
    }
    if (x['allOf'] case final List all) {
      final merged = <String, Object?>{
        for (final MapEntry(:key, :value) in x.entries)
          if (key != 'allOf') key: value,
      };
      final required = [..._required(x['required'])];
      for (final member in all) {
        required.addAll(_required(_resolve(member)?['required']));
        final walked = walk(member, depth + 1, '$path/allOf');
        if (walked is! Map<String, Object?>) continue;
        for (final MapEntry(:key, :value) in walked.entries) {
          if (key == 'required') continue;
          if (key == 'properties' && value is Map) {
            final props = (merged['properties'] as Map<String, Object?>?) ?? {};
            props.addAll({for (final e in value.entries) '${e.key}': e.value});
            merged['properties'] = props;
          } else {
            merged.putIfAbsent(key, () => value);
          }
        }
      }
      if (required.isNotEmpty) merged['required'] = required.toSet().toList();
      return walk(merged, depth + 1, path);
    }
    if ((x['anyOf'] != null || x['oneOf'] != null) && _ownShape(x)) {
      return walk(_foldUnion(x), depth + 1, path);
    }
    for (final key in ['anyOf', 'oneOf']) {
      if (x[key] case final List alternatives) {
        Map<String, Object?>? pick;
        var nullable = false;
        for (final alternative in alternatives) {
          final map = alternative is Map<String, Object?> ? alternative : null;
          if (map?['type'] == 'null') {
            nullable = true;
          } else if (pick == null && map != null) {
            pick = map;
          }
        }
        var out = <String, Object?>{};
        if (pick != null) {
          if (walk(pick, depth + 1, '$path/$key')
              case final Map<String, Object?> m) {
            out = m;
          }
        }
        if (x['description'] case final String d
            when out['description'] == null) {
          out['description'] = d;
        }
        if (nullable) out['nullable'] = true;
        out['type'] ??= 'string';
        return out;
      }
    }
    final out = <String, Object?>{};
    for (final MapEntry(:key, :value) in x.entries) {
      switch (key) {
        case 'description' ||
            'nullable' ||
            'required' ||
            'pattern' ||
            'minimum' ||
            'maximum' ||
            'minLength' ||
            'maxLength' ||
            'minItems' ||
            'maxItems' ||
            'minProperties' ||
            'maxProperties' ||
            'propertyOrdering':
          out[key] = value;
        case 'exclusiveMinimum' || 'exclusiveMaximum':
          // Only as inclusive.
          final bound = key == 'exclusiveMinimum' ? 'minimum' : 'maximum';
          if (value is num && x[bound] == null) out[bound] = value;
        case 'type':
          if (value is List) {
            for (final type in value) {
              if (type == 'null') {
                out['nullable'] = true;
              } else {
                out['type'] ??= type;
              }
            }
            // One type a node: of a list, the one its items or properties
            // are for.
            for (final type in value) {
              if (type == 'array' && x['items'] != null ||
                  type == 'object' && x['properties'] != null) {
                out['type'] = type;
                break;
              }
            }
          } else {
            out['type'] = value;
          }
        case 'properties':
          final props = <String, Object?>{};
          if (value is Map) {
            for (final MapEntry(key: name, value: property) in value.entries) {
              if (name == '') continue;
              final at = '$name'.replaceAll('~', '~0').replaceAll('/', '~1');
              if (walk(property, depth + 1, '$path/properties/$at')
                  case final w?) {
                props['$name'] = w;
              }
            }
          }
          out[key] = props;
        case 'items':
          final walked = walk(value, depth + 1, '$path/items');
          if (walked != null) {
            out[key] = walked;
          } else if (x['maxItems'] == null) {
            out[key] = <String, Object?>{};
            out['maxItems'] = 0;
          }
        case 'enum':
          // Strings only, none blank.
          if (value is List && value.every((e) => e is String)) {
            final strings = [
              for (final e in value.cast<String>())
                if (e.trim().isNotEmpty) e,
            ];
            if (strings.isNotEmpty) out[key] = strings;
          }
        default:
          // Outside the subset (format, default, title,
          // additionalProperties, const…).
          break;
      }
    }
    if (x['const'] case final String c when c.trim().isNotEmpty) {
      out['enum'] = [c];
    }
    if (out['enum'] case final Object values? when out['type'] == 'array') {
      out.remove('enum');
      if (out['items'] case final Map<String, Object?> items
          when items['enum'] == null &&
              (items['type'] == null || items['type'] == 'string')) {
        items['type'] = 'string';
        items['enum'] = values;
      }
    }
    if (out['type'] == null) {
      if (out['properties'] != null) {
        out['type'] = 'object';
      } else if (out['items'] != null) {
        out['type'] = 'array';
      }
    }
    if (out['type'] == 'array') {
      if (out['items'] case final List tuple) out['items'] = _oneSays(tuple);
      if (out['items'] == null) {
        if (x['prefixItems'] case final List prefix when prefix.isNotEmpty) {
          if (_oneSays(prefix) case final one?) {
            out['items'] = walk(one, depth + 1, '$path/items');
          }
        }
        out['items'] ??= <String, Object?>{};
      }
    }
    if (out['type'] case final String type) {
      if (type != 'array') {
        out
          ..remove('items')
          ..remove('minItems')
          ..remove('maxItems');
      }
      if (type != 'object') {
        out
          ..remove('properties')
          ..remove('required')
          ..remove('minProperties')
          ..remove('maxProperties')
          ..remove('propertyOrdering');
      }
    }
    if (out['required'] case final List required) {
      final props = out['properties'] is Map
          ? out['properties'] as Map
          : const {};
      final kept = [
        for (final name in required)
          if (name is String && props[name] != null) name,
      ];
      if (kept.isEmpty) {
        out.remove('required');
      } else {
        out['required'] = kept;
      }
    }
    return out;
  }

  static bool _ownShape(Map x) {
    if (x['properties'] != null || x['items'] != null) return true;
    return switch (x['type']) {
      final String type => type != 'null',
      final List types => types.any((t) => t != 'null'),
      _ => false,
    };
  }

  /// [x], of a shape of its own, with its unions folded in: a null branch
  /// makes it nullable; an object's branches' fields join its properties,
  /// and a field every branch requires is required.
  Map<String, Object?> _foldUnion(Map<String, Object?> x) {
    final out = <String, Object?>{
      for (final MapEntry(:key, :value) in x.entries)
        if (key != 'anyOf' && key != 'oneOf') key: value,
    };
    var object = x['type'] == 'object' || x['properties'] != null;
    if (x['type'] case final List types) {
      object = object || types.contains('object');
    }
    final props = <String, Object?>{
      if (x['properties'] case final Map own)
        for (final e in own.entries) '${e.key}': e.value,
    };
    List<Object?>? common;
    for (final key in ['anyOf', 'oneOf']) {
      for (final alternative in (x[key] as List?) ?? const []) {
        final map = _resolve(alternative);
        if (map == null) continue;
        if (map['type'] == 'null') {
          out['nullable'] = true;
          continue;
        }
        if (!object) continue;
        if (map['properties'] case final Map branch) {
          final names = branch.keys.map((k) => '$k').toList()..sort();
          for (final name in names) {
            props.putIfAbsent(name, () => branch[name]);
          }
        }
        final required = _required(map['required']);
        common = common == null
            ? [...required]
            : [
                for (final name in common)
                  if (required.contains(name)) name,
              ];
      }
    }
    if (object) {
      if (props.isNotEmpty) out['properties'] = props;
      final required = [..._required(x['required']), ...?common];
      if (required.isNotEmpty) out['required'] = required.toSet().toList();
    }
    return out;
  }

  static List<Object?> _required(Object? value) => [
    if (value is List)
      for (final name in value)
        if (name is String) name,
  ];
}
