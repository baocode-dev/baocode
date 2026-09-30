// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/rawGrammar.ts (MIT, see LICENSE.md).
//
// Upstream declares TypeScript interfaces over plain JSON objects and relies
// on JavaScript's looseness (missing keys, `$self`/`$base`, rule ids written
// onto the objects). These extension types are zero-cost views of the decoded
// `Map`s, so the port keeps that shape: the grammar code reads the maps with
// JavaScript semantics (see `js_semantics.dart`) and only ever mutates its
// own deep copy (`initGrammar`).

/// A TextMate grammar: the object decoded from its JSON or plist file.
extension type IRawGrammar(Map<String, Object?> map) {
  /// Normally a map of rule name to rule.
  Object? get repository => map['repository'];

  /// The grammar's scope name, e.g. `source.ts`.
  String get scopeName {
    final value = map['scopeName'];
    if (value is String) return value;
    throw ArgumentError.value(value, 'scopeName', 'Not a string');
  }

  /// Normally a list of rules.
  Object? get patterns => map['patterns'];

  /// Normally a map of injection selector to rule.
  Object? get injections => map['injections'];

  Object? get injectionSelector => map['injectionSelector'];
  Object? get fileTypes => map['fileTypes'];
  Object? get name => map['name'];
  Object? get firstLineMatch => map['firstLineMatch'];

  /// Present when the grammar was parsed in debug mode.
  ILocation? get $vscodeTextmateLocation => _location(map);
}

/// Allowed values:
/// * Scope Name, e.g. `source.ts`
/// * Top level scope reference, e.g. `source.ts#entity.name.class`
/// * Relative scope reference, e.g. `#entity.name.class`
/// * self, e.g. `$self`
/// * base, e.g. `$base`
typedef IncludeString = String;
typedef RegExpString = String;

/// A map of rule name to rule, plus `$self` and `$base` once the grammar is
/// initialized.
extension type IRawRepository(Map<String, Object?> map) {
  Object? operator [](String name) => map[name];
}

/// A grammar rule. Every field is optional; `id` is not part of the spec and
/// is written by the rule factory.
extension type IRawRule(Map<String, Object?> map) {
  Object? get id => map['id'];
  Object? get include => map['include'];
  Object? get name => map['name'];
  Object? get contentName => map['contentName'];
  Object? get match => map['match'];
  Object? get captures => map['captures'];
  Object? get begin => map['begin'];
  Object? get beginCaptures => map['beginCaptures'];
  Object? get end => map['end'];
  Object? get endCaptures => map['endCaptures'];
  Object? get $while => map['while'];
  Object? get whileCaptures => map['whileCaptures'];
  Object? get patterns => map['patterns'];
  Object? get repository => map['repository'];

  /// A boolean, or a number used as one.
  Object? get applyEndPatternLast => map['applyEndPatternLast'];

  ILocation? get $vscodeTextmateLocation => _location(map);
}

/// A map of capture number (as a string) to rule.
extension type IRawCaptures(Map<String, Object?> map) {
  Object? operator [](String captureId) => map[captureId];
}

/// Where a rule was defined; recorded by the debug-mode parsers.
extension type ILocation(Map<String, Object?> map) {
  String? get filename => map['filename'] as String?;
  int get line => (map['line'] as num).toInt();
  int get char => (map['char'] as num).toInt();
}

ILocation? _location(Map<String, Object?> map) {
  final value = map[r'$vscodeTextmateLocation'];
  return value is Map<String, Object?> ? ILocation(value) : null;
}

/// The `$vscodeTextmateLocation` of a raw value, when it has one.
ILocation? locationOf(Object? raw) {
  if (raw is! Map) return null;
  final value = raw[r'$vscodeTextmateLocation'];
  return value is Map<String, Object?> ? ILocation(value) : null;
}
