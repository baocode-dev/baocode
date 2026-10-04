import 'mason_platform.dart';

/// Expands mason-registry `{{ … }}` templates, as package fields use them:
/// `{{version}}`, `{{ version | strip_prefix "v" }}`,
/// `{{source.asset.bin}}`, `{{ take_if_not(is_platform("win"), ".py") }}`.
///
/// An expression is a string literal, a dotted path into [context], or a
/// call; `value | f args` calls `f(args…, value)`. Functions:
/// `strip_prefix`, `strip_suffix`, `is_platform`, `take_if`, `take_if_not`.
/// Anything else throws a [FormatException].
String expandMasonTemplate(
  String template,
  Map<String, Object?> context,
  MasonPlatform platform,
) => template.replaceAllMapped(RegExp(r'\{\{(.*?)\}\}'), (match) {
  final value = _Expression(match[1]!, context, platform).evaluate();
  return switch (value) {
    null => '',
    final String text => text,
    final bool flag => flag ? 'true' : '',
    _ => throw FormatException('Template value is not text: $value', match[0]),
  };
});

class _Expression {
  _Expression(this.source, this.context, this.platform)
    : tokens = _tokenize(source);

  final String source;
  final Map<String, Object?> context;
  final MasonPlatform platform;
  final List<String> tokens;
  var _next = 0;

  static final _token = RegExp(
    r'''\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[A-Za-z_][\w.]*|[(),|])''',
  );

  static List<String> _tokenize(String source) {
    final tokens = <String>[];
    var index = 0;
    while (index < source.length) {
      if (source.substring(index).trim().isEmpty) break;
      final match = _token.matchAsPrefix(source, index);
      if (match == null) {
        throw FormatException('Bad template expression', source, index);
      }
      tokens.add(match[1]!);
      index = match.end;
    }
    return tokens;
  }

  String? get _peek => _next < tokens.length ? tokens[_next] : null;

  String _take() {
    if (_next >= tokens.length) {
      throw FormatException('Unfinished template expression', source);
    }
    return tokens[_next++];
  }

  void _expect(String token) {
    if (_take() != token) {
      throw FormatException('Expected "$token" in template', source);
    }
  }

  Object? evaluate() {
    var value = _term();
    while (_peek == '|') {
      _take();
      final name = _take();
      final args = <Object?>[];
      if (_peek == '(') {
        args.addAll(_arguments());
      } else {
        while (_peek != null && _peek != '|') {
          args.add(_term());
        }
      }
      value = _call(name, [...args, value]);
    }
    if (_peek != null) {
      throw FormatException('Unexpected "$_peek" in template', source);
    }
    return value;
  }

  List<Object?> _arguments() {
    _expect('(');
    final args = <Object?>[];
    while (_peek != ')') {
      args.add(_term());
      if (_peek == ',') _take();
    }
    _expect(')');
    return args;
  }

  Object? _term() {
    final token = _take();
    if (token.startsWith('"') || token.startsWith("'")) {
      return token
          .substring(1, token.length - 1)
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    }
    if (!RegExp(r'^[A-Za-z_]').hasMatch(token)) {
      throw FormatException('Unexpected "$token" in template', source);
    }
    if (_peek == '(') return _call(token, _arguments());
    Object? value = context;
    for (final part in token.split('.')) {
      if (value is Map && value.containsKey(part)) {
        value = value[part];
      } else {
        throw FormatException('Unknown template value "$token"', source);
      }
    }
    return value;
  }

  Object? _call(String name, List<Object?> args) {
    String text(Object? value) => switch (value) {
      final String text => text,
      null => '',
      _ => '$value',
    };
    void arity(int count) {
      if (args.length != count) {
        throw FormatException('$name takes $count arguments', source);
      }
    }

    switch (name) {
      case 'strip_prefix':
        arity(2);
        final (prefix, value) = (text(args[0]), text(args[1]));
        return value.startsWith(prefix)
            ? value.substring(prefix.length)
            : value;
      case 'strip_suffix':
        arity(2);
        final (suffix, value) = (text(args[0]), text(args[1]));
        return value.endsWith(suffix)
            ? value.substring(0, value.length - suffix.length)
            : value;
      case 'is_platform':
        arity(1);
        return platform.matches(text(args[0]));
      case 'take_if':
        arity(2);
        return args[0] == true ? args[1] : '';
      case 'take_if_not':
        arity(2);
        return args[0] == true ? '' : args[1];
    }
    throw FormatException('Unknown template function "$name"', source);
  }
}
