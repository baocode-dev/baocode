/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/snippet/browser/snippetParser.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: JavaScript RegExp objects become [SnippetRegExp] (a Dart
// [RegExp] plus the `g` flag, which Dart expresses as replaceAll); flags
// outside `gimsuy` or repeated flags are invalid, as `new RegExp` rejects
// them. `Marker.parent` is nullable. Dart `toUpperCase`/`toLowerCase` stand
// in for the locale-aware variants.

const int _dollar = 0x24;
const int _colon = 0x3A;
const int _comma = 0x2C;
const int _curlyOpen = 0x7B;
const int _curlyClose = 0x7D;
const int _backslash = 0x5C;
const int _slash = 0x2F;
const int _pipe = 0x7C;
const int _plus = 0x2B;
const int _dash = 0x2D;
const int _questionMark = 0x3F;

enum TokenType {
  dollar,
  colon,
  comma,
  curlyOpen,
  curlyClose,
  backslash,
  forwardslash,
  pipe,
  int_,
  variableName,
  format,
  plus,
  dash,
  questionMark,
  eof,
}

class Token {
  const Token(this.type, this.pos, this.len);

  final TokenType type;
  final int pos;
  final int len;
}

class Scanner {
  static const Map<int, TokenType> _table = {
    _dollar: TokenType.dollar,
    _colon: TokenType.colon,
    _comma: TokenType.comma,
    _curlyOpen: TokenType.curlyOpen,
    _curlyClose: TokenType.curlyClose,
    _backslash: TokenType.backslash,
    _slash: TokenType.forwardslash,
    _pipe: TokenType.pipe,
    _plus: TokenType.plus,
    _dash: TokenType.dash,
    _questionMark: TokenType.questionMark,
  };

  static bool isDigitCharacter(int ch) => ch >= 0x30 && ch <= 0x39;

  static bool isVariableCharacter(int ch) =>
      ch == 0x5F || (ch >= 0x61 && ch <= 0x7A) || (ch >= 0x41 && ch <= 0x5A);

  String value = '';
  int pos = 0;

  void text(String value) {
    this.value = value;
    pos = 0;
  }

  String tokenText(Token token) =>
      value.substring(token.pos, token.pos + token.len);

  int _at(int index) => index < value.length ? value.codeUnitAt(index) : -1;

  Token next() {
    if (pos >= value.length) return Token(TokenType.eof, pos, 0);

    final start = pos;
    var len = 0;
    var ch = value.codeUnitAt(start);

    // static types
    final type = _table[ch];
    if (type != null) {
      pos += 1;
      return Token(type, start, 1);
    }

    // number
    if (isDigitCharacter(ch)) {
      do {
        len += 1;
        ch = _at(start + len);
      } while (isDigitCharacter(ch));
      pos += len;
      return Token(TokenType.int_, start, len);
    }

    // variable name
    if (isVariableCharacter(ch)) {
      do {
        ch = _at(start + (++len));
      } while (isVariableCharacter(ch) || isDigitCharacter(ch));
      pos += len;
      return Token(TokenType.variableName, start, len);
    }

    // format
    do {
      len += 1;
      ch = _at(start + len);
    } while (ch != -1 &&
        !_table.containsKey(ch) && // not static token
        !isDigitCharacter(ch) && // not number
        !isVariableCharacter(ch)); // not variable
    pos += len;
    return Token(TokenType.format, start, len);
  }
}

abstract class Marker {
  Marker? parent;
  List<Marker> _children = [];

  Marker appendChild(Marker child) {
    if (child is Text && _children.isNotEmpty && _children.last is Text) {
      // this and previous child are text -> merge them
      (_children.last as Text).value += child.value;
    } else {
      // normal adoption of child
      child.parent = this;
      _children.add(child);
    }
    return this;
  }

  void replace(Marker child, List<Marker> others) {
    final parent = child.parent!;
    final idx = parent.children.indexOf(child);
    final newChildren = List<Marker>.of(parent.children);
    newChildren.replaceRange(idx, idx + 1, others);
    parent._children = newChildren;

    void fixParent(List<Marker> children, Marker parent) {
      for (final child in children) {
        child.parent = parent;
        fixParent(child.children, child);
      }
    }

    fixParent(others, parent);
  }

  List<Marker> get children => _children;

  Marker get rightMostDescendant =>
      _children.isNotEmpty ? _children.last.rightMostDescendant : this;

  TextmateSnippet? get snippet {
    Marker? candidate = this;
    while (true) {
      if (candidate == null) return null;
      if (candidate is TextmateSnippet) return candidate;
      candidate = candidate.parent;
    }
  }

  @override
  String toString() => children.fold('', (prev, cur) => prev + cur.toString());

  String toTextmateString();

  int len() => 0;

  Marker clone();
}

final RegExp _textEscape = RegExp(r'\$|}|\\');

class Text extends Marker {
  Text(this.value);

  static String escape(String value) =>
      value.replaceAllMapped(_textEscape, (m) => '\\${m[0]}');

  String value;

  @override
  String toString() => value;

  @override
  String toTextmateString() => escape(value);

  @override
  int len() => value.length;

  @override
  Text clone() => Text(value);
}

abstract class TransformableMarker extends Marker {
  Transform? transform;
}

class Placeholder extends TransformableMarker {
  Placeholder(this.index);

  static int compareByIndex(Placeholder a, Placeholder b) {
    if (a.index == b.index) {
      return 0;
    } else if (a.isFinalTabstop) {
      return 1;
    } else if (b.isFinalTabstop) {
      return -1;
    } else if (a.index < b.index) {
      return -1;
    } else if (a.index > b.index) {
      return 1;
    } else {
      return 0;
    }
  }

  /// A number: merged nested snippets use fractional indices upstream.
  num index;

  bool get isFinalTabstop => index == 0;

  Choice? get choice => _children.length == 1 && _children[0] is Choice
      ? _children[0] as Choice
      : null;

  @override
  String toTextmateString() {
    var transformString = '';
    if (transform != null) transformString = transform!.toTextmateString();
    if (children.isEmpty && transform == null) {
      return '\$$index';
    } else if (children.isEmpty) {
      return '\${$index$transformString}';
    } else if (choice != null) {
      return '\${$index|${choice!.toTextmateString()}|$transformString}';
    } else {
      return '\${$index:${children.map((c) => c.toTextmateString()).join()}'
          '$transformString}';
    }
  }

  @override
  Placeholder clone() {
    final ret = Placeholder(index);
    if (transform != null) ret.transform = transform!.clone();
    ret._children = [for (final child in children) child.clone()];
    return ret;
  }
}

final RegExp _choiceEscape = RegExp(r'\||,|\\');

class Choice extends Marker {
  final List<Text> options = [];

  @override
  Choice appendChild(Marker child) {
    if (child is Text) {
      child.parent = this;
      options.add(child);
    }
    return this;
  }

  @override
  String toString() => options[0].value;

  @override
  String toTextmateString() => options
      .map(
        (option) =>
            option.value.replaceAllMapped(_choiceEscape, (m) => '\\${m[0]}'),
      )
      .join(',');

  @override
  int len() => options[0].len();

  @override
  Choice clone() {
    final ret = Choice();
    for (final option in options) {
      ret.appendChild(option.clone());
    }
    return ret;
  }
}

/// A JavaScript regular expression: [source] plus flags (`g`, `i`, `m`,
/// `s`, `u`, `y`; `y` has no Dart equivalent and is kept for printing only).
class SnippetRegExp {
  SnippetRegExp(this.source, [this.flags = ''])
    : regExp = RegExp(
        source,
        caseSensitive: !flags.contains('i'),
        multiLine: flags.contains('m'),
        dotAll: flags.contains('s'),
        unicode: flags.contains('u'),
      ) {
    final seen = <String>{};
    for (final flag in flags.split('')) {
      if (!'gimsuy'.contains(flag) || !seen.add(flag)) {
        throw FormatException('Invalid regular expression flags', flags);
      }
    }
  }

  final String source;
  final String flags;
  final RegExp regExp;

  bool get global => flags.contains('g');
  bool get ignoreCase => flags.contains('i');
}

class Transform extends Marker {
  SnippetRegExp regexp = SnippetRegExp('');

  String resolve(String value) {
    var didMatch = false;
    String replace(Match m) {
      didMatch = true;
      return _replace([for (var i = 0; i <= m.groupCount; i++) m[i]]);
    }

    var ret = regexp.global
        ? value.replaceAllMapped(regexp.regExp, replace)
        : value.replaceFirstMapped(regexp.regExp, replace);
    // when the regex didn't match and when the transform has
    // else branches, then run those
    if (!didMatch &&
        _children.any(
          (child) =>
              child is FormatString && (child.elseValue?.isNotEmpty ?? false),
        )) {
      ret = _replace(const []);
    }
    return ret;
  }

  String _replace(List<String?> groups) {
    final ret = StringBuffer();
    for (final marker in _children) {
      if (marker is FormatString) {
        var value = marker.index < groups.length
            ? groups[marker.index] ?? ''
            : '';
        value = marker.resolve(value);
        ret.write(value);
      } else {
        ret.write(marker.toString());
      }
    }
    return ret.toString();
  }

  @override
  String toString() => '';

  @override
  String toTextmateString() =>
      '/${regexp.source}/${children.map((c) => c.toTextmateString()).join()}'
      '/${(regexp.ignoreCase ? 'i' : '') + (regexp.global ? 'g' : '')}';

  @override
  Transform clone() {
    final ret = Transform();
    ret.regexp = SnippetRegExp(
      regexp.source,
      (regexp.ignoreCase ? 'i' : '') + (regexp.global ? 'g' : ''),
    );
    ret._children = [for (final child in children) child.clone()];
    return ret;
  }
}

final RegExp _letterOrDigits = RegExp(r'[\p{L}0-9]+', unicode: true);
final RegExp _letterOrDigit = RegExp(r'[\p{L}0-9]', unicode: true);
final RegExp _edgeUnderscores = RegExp(r'^_+|_+$');
final RegExp _kebabWords = RegExp(
  r'\p{Lu}{2,}(?=\p{Lu}\p{Ll}+[0-9]*|[\s_-]|$)|\p{Lu}?\p{Ll}+[0-9]*|\p{Lu}(?=\p{Lu}\p{Ll})|\p{Lu}(?=[\s_-]|$)|[0-9]+',
  unicode: true,
);

class FormatString extends Marker {
  FormatString(this.index, [this.shorthandName, this.ifValue, this.elseValue]);

  final int index;
  final String? shorthandName;
  final String? ifValue;
  final String? elseValue;

  String resolve(String? value) {
    final empty = value == null || value.isEmpty;
    if (shorthandName == 'upcase') {
      return empty ? '' : value.toUpperCase();
    } else if (shorthandName == 'downcase') {
      return empty ? '' : value.toLowerCase();
    } else if (shorthandName == 'capitalize') {
      return empty ? '' : value[0].toUpperCase() + value.substring(1);
    } else if (shorthandName == 'pascalcase') {
      return empty ? '' : _toPascalCase(value);
    } else if (shorthandName == 'camelcase') {
      return empty ? '' : _toCamelCase(value);
    } else if (shorthandName == 'kebabcase') {
      return empty ? '' : _toKebabCase(value);
    } else if (shorthandName == 'snakecase') {
      return empty ? '' : _toSnakeCase(value);
    } else if (!empty && ifValue != null) {
      return ifValue!;
    } else if (empty && elseValue != null) {
      return elseValue!;
    } else {
      return value ?? '';
    }
  }

  // Note: word-based case transforms rely on uppercase/lowercase distinctions.
  // For scripts without case, transforms are effectively no-ops.
  String _toKebabCase(String value) {
    if (!_letterOrDigits.hasMatch(value)) return value;
    if (!_letterOrDigit.hasMatch(value)) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(_edgeUnderscores, '')
          .replaceAll(RegExp(r'[\s_]+'), '-');
    }
    final cleaned = value.trim().replaceAll(_edgeUnderscores, '');
    final match2 = _kebabWords.allMatches(cleaned).map((m) => m[0]!).toList();
    if (match2.isEmpty) {
      return cleaned
          .split(RegExp(r'[\s_-]+'))
          .where((word) => word.isNotEmpty)
          .map((word) => word.toLowerCase())
          .join('-');
    }
    return match2.map((x) => x.toLowerCase()).join('-');
  }

  String _toPascalCase(String value) {
    final match = _letterOrDigits.allMatches(value).map((m) => m[0]!).toList();
    if (match.isEmpty) return value;
    return match
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join();
  }

  String _toCamelCase(String value) {
    final match = _letterOrDigits.allMatches(value).map((m) => m[0]!).toList();
    if (match.isEmpty) return value;
    return [
      for (final (index, word) in match.indexed)
        index == 0
            ? word[0].toLowerCase() + word.substring(1)
            : word[0].toUpperCase() + word.substring(1),
    ].join();
  }

  String _toSnakeCase(String value) => value
      .replaceAllMapped(
        RegExp(r'(\p{Ll})(\p{Lu})', unicode: true),
        (m) => '${m[1]}_${m[2]}',
      )
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .toLowerCase();

  @override
  String toTextmateString() {
    final value = StringBuffer('\${')..write(index);
    if (shorthandName != null) {
      value.write(':/$shorthandName');
    } else if ((ifValue?.isNotEmpty ?? false) &&
        (elseValue?.isNotEmpty ?? false)) {
      value.write(':?$ifValue:$elseValue');
    } else if (ifValue?.isNotEmpty ?? false) {
      value.write(':+$ifValue');
    } else if (elseValue?.isNotEmpty ?? false) {
      value.write(':-$elseValue');
    }
    value.write('}');
    return value.toString();
  }

  @override
  FormatString clone() =>
      FormatString(index, shorthandName, ifValue, elseValue);
}

abstract interface class VariableResolver {
  String? resolve(Variable variable);
}

class Variable extends TransformableMarker {
  Variable(this.name);

  String name;

  bool resolve(VariableResolver resolver) {
    var value = resolver.resolve(this);
    if (transform != null) value = transform!.resolve(value ?? '');
    if (value != null) {
      _children = [Text(value)..parent = this];
      return true;
    }
    return false;
  }

  @override
  String toTextmateString() {
    var transformString = '';
    if (transform != null) transformString = transform!.toTextmateString();
    if (children.isEmpty) {
      return '\${$name$transformString}';
    } else {
      return '\${$name:${children.map((c) => c.toTextmateString()).join()}'
          '$transformString}';
    }
  }

  @override
  Variable clone() {
    final ret = Variable(name);
    if (transform != null) ret.transform = transform!.clone();
    ret._children = [for (final child in children) child.clone()];
    return ret;
  }
}

void _walk(List<Marker> marker, bool Function(Marker marker) visitor) {
  final stack = List<Marker>.of(marker);
  while (stack.isNotEmpty) {
    final marker = stack.removeAt(0);
    final recurse = visitor(marker);
    if (!recurse) break;
    stack.insertAll(0, marker.children);
  }
}

class TextmateSnippet extends Marker {
  ({List<Placeholder> all, Placeholder? last})? _placeholders;

  ({List<Placeholder> all, Placeholder? last}) get placeholderInfo {
    if (_placeholders == null) {
      // fill in placeholders
      final all = <Placeholder>[];
      Placeholder? last;
      walk((candidate) {
        if (candidate is Placeholder) {
          all.add(candidate);
          last = last == null || last!.index < candidate.index
              ? candidate
              : last;
        }
        return true;
      });
      _placeholders = (all: all, last: last);
    }
    return _placeholders!;
  }

  List<Placeholder> get placeholders => placeholderInfo.all;

  int offset(Marker marker) {
    var pos = 0;
    var found = false;
    walk((candidate) {
      if (identical(candidate, marker)) {
        found = true;
        return false;
      }
      pos += candidate.len();
      return true;
    });
    return found ? pos : -1;
  }

  int fullLen(Marker marker) {
    var ret = 0;
    _walk([marker], (marker) {
      ret += marker.len();
      return true;
    });
    return ret;
  }

  List<Placeholder> enclosingPlaceholders(Placeholder placeholder) {
    final ret = <Placeholder>[];
    var parent = placeholder.parent;
    while (parent != null) {
      if (parent is Placeholder) ret.add(parent);
      parent = parent.parent;
    }
    return ret;
  }

  TextmateSnippet resolveVariables(VariableResolver resolver) {
    walk((candidate) {
      if (candidate is Variable) {
        if (candidate.resolve(resolver)) _placeholders = null;
      }
      return true;
    });
    return this;
  }

  @override
  Marker appendChild(Marker child) {
    _placeholders = null;
    return super.appendChild(child);
  }

  @override
  void replace(Marker child, List<Marker> others) {
    _placeholders = null;
    super.replace(child, others);
  }

  @override
  String toTextmateString() =>
      children.fold('', (prev, cur) => prev + cur.toTextmateString());

  @override
  TextmateSnippet clone() {
    final ret = TextmateSnippet();
    ret._children = [for (final child in children) child.clone()];
    return ret;
  }

  void walk(bool Function(Marker marker) visitor) => _walk(children, visitor);
}

final RegExp _unescapeUntil = RegExp(r'\\(\$|}|\\)');

class SnippetParser {
  static String escape(String value) =>
      value.replaceAllMapped(_textEscape, (m) => '\\${m[0]}');

  /// Takes a snippet and returns the insertable string, e.g return the
  /// snippet-string without any placeholder, tabstop, variables etc...
  static String asInsertText(String value) =>
      SnippetParser().parse(value).toString();

  static bool guessNeedsClipboard(String template) =>
      RegExp(r'\${?CLIPBOARD').hasMatch(template);

  final Scanner _scanner = Scanner();
  Token _token = const Token(TokenType.eof, 0, 0);

  TextmateSnippet parse(
    String value, [
    bool insertFinalTabstop = false,
    bool enforceFinalTabstop = false,
  ]) {
    final snippet = TextmateSnippet();
    parseFragment(value, snippet);
    ensureFinalTabstop(snippet, enforceFinalTabstop, insertFinalTabstop);
    return snippet;
  }

  List<Marker> parseFragment(String value, TextmateSnippet snippet) {
    final offset = snippet.children.length;
    _scanner.text(value);
    _token = _scanner.next();
    while (_parse(snippet)) {
      // nothing
    }

    // fill in values for placeholders. the first placeholder of an index
    // that has a value defines the value for all placeholders with that index
    final placeholderDefaultValues = <num, List<Marker>?>{};
    final incompletePlaceholders = <Placeholder>[];
    snippet.walk((marker) {
      if (marker is Placeholder) {
        if (marker.isFinalTabstop) {
          placeholderDefaultValues[0] = null;
        } else if (!placeholderDefaultValues.containsKey(marker.index) &&
            marker.children.isNotEmpty) {
          placeholderDefaultValues[marker.index] = marker.children;
        } else {
          incompletePlaceholders.add(marker);
        }
      }
      return true;
    });

    void fillInIncompletePlaceholder(Placeholder placeholder, Set<num> stack) {
      final defaultValues = placeholderDefaultValues[placeholder.index];
      if (defaultValues == null) return;
      final clone = Placeholder(placeholder.index);
      clone.transform = placeholder.transform;
      for (final child in defaultValues) {
        final newChild = child.clone();
        clone.appendChild(newChild);

        // "recurse" on children that are again placeholders
        if (newChild is Placeholder &&
            placeholderDefaultValues.containsKey(newChild.index) &&
            !stack.contains(newChild.index)) {
          stack.add(newChild.index);
          fillInIncompletePlaceholder(newChild, stack);
          stack.remove(newChild.index);
        }
      }
      snippet.replace(placeholder, [clone]);
    }

    final stack = <num>{};
    for (final placeholder in incompletePlaceholders) {
      fillInIncompletePlaceholder(placeholder, stack);
    }

    return snippet.children.sublist(offset);
  }

  void ensureFinalTabstop(
    TextmateSnippet snippet,
    bool enforceFinalTabstop,
    bool insertFinalTabstop,
  ) {
    if (enforceFinalTabstop ||
        insertFinalTabstop && snippet.placeholders.isNotEmpty) {
      final finalTabstop = snippet.placeholders
          .where((p) => p.index == 0)
          .firstOrNull;
      if (finalTabstop == null) {
        // the snippet uses placeholders but has no
        // final tabstop defined -> insert at the end
        snippet.appendChild(Placeholder(0));
      }
    }
  }

  bool _accept([TokenType? type]) {
    if (type == null || _token.type == type) {
      _token = _scanner.next();
      return true;
    }
    return false;
  }

  /// `_accept(type, true)`: the token's text, or null.
  String? _acceptText([TokenType? type]) {
    if (type == null || _token.type == type) {
      final ret = _scanner.tokenText(_token);
      _token = _scanner.next();
      return ret;
    }
    return null;
  }

  bool _backTo(Token token) {
    _scanner.pos = token.pos + token.len;
    _token = token;
    return false;
  }

  String? _until(TokenType type) {
    final start = _token;
    while (_token.type != type) {
      if (_token.type == TokenType.eof) {
        return null;
      } else if (_token.type == TokenType.backslash) {
        final nextToken = _scanner.next();
        if (nextToken.type != TokenType.dollar &&
            nextToken.type != TokenType.curlyClose &&
            nextToken.type != TokenType.backslash) {
          return null;
        }
      }
      _token = _scanner.next();
    }
    final value = _scanner.value
        .substring(start.pos, _token.pos)
        .replaceAllMapped(_unescapeUntil, (m) => m[1]!);
    _token = _scanner.next();
    return value;
  }

  bool _parse(Marker marker) =>
      _parseEscaped(marker) ||
      _parseTabstopOrVariableName(marker) ||
      _parseComplexPlaceholder(marker) ||
      _parseComplexVariable(marker) ||
      _parseAnything(marker);

  // \$, \\, \} -> just text
  bool _parseEscaped(Marker marker) {
    final value = _acceptText(TokenType.backslash);
    if (value != null) {
      // saw a backslash, append escaped token or that backslash
      final escaped =
          _acceptText(TokenType.dollar) ??
          _acceptText(TokenType.curlyClose) ??
          _acceptText(TokenType.backslash) ??
          value;
      marker.appendChild(Text(escaped));
      return true;
    }
    return false;
  }

  // $foo -> variable, $1 -> tabstop
  bool _parseTabstopOrVariableName(Marker parent) {
    final token = _token;
    String? value;
    final match =
        _accept(TokenType.dollar) &&
        (value =
                _acceptText(TokenType.variableName) ??
                _acceptText(TokenType.int_)) !=
            null;
    if (!match) return _backTo(token);
    parent.appendChild(
      RegExp(r'^\d+$').hasMatch(value!)
          ? Placeholder(int.parse(value))
          : Variable(value),
    );
    return true;
  }

  // ${1:<children>}, ${1} -> placeholder
  bool _parseComplexPlaceholder(Marker parent) {
    final token = _token;
    String? index;
    final match =
        _accept(TokenType.dollar) &&
        _accept(TokenType.curlyOpen) &&
        (index = _acceptText(TokenType.int_)) != null;
    if (!match) return _backTo(token);

    final placeholder = Placeholder(int.parse(index!));

    if (_accept(TokenType.colon)) {
      // ${1:<children>}
      while (true) {
        // ...} -> done
        if (_accept(TokenType.curlyClose)) {
          parent.appendChild(placeholder);
          return true;
        }
        if (_parse(placeholder)) continue;

        // fallback
        parent.appendChild(Text('\${$index:'));
        for (final child in List.of(placeholder.children)) {
          parent.appendChild(child);
        }
        return true;
      }
    } else if (placeholder.index > 0 && _accept(TokenType.pipe)) {
      // ${1|one,two,three|}
      final choice = Choice();
      while (true) {
        if (_parseChoiceElement(choice)) {
          if (_accept(TokenType.comma)) {
            // opt, -> more
            continue;
          }
          if (_accept(TokenType.pipe)) {
            placeholder.appendChild(choice);
            if (_accept(TokenType.curlyClose)) {
              // ..|} -> done
              parent.appendChild(placeholder);
              return true;
            }
          }
        }
        _backTo(token);
        return false;
      }
    } else if (_accept(TokenType.forwardslash)) {
      // ${1/<regex>/<format>/<options>}
      if (_parseTransform(placeholder)) {
        parent.appendChild(placeholder);
        return true;
      }
      _backTo(token);
      return false;
    } else if (_accept(TokenType.curlyClose)) {
      // ${1}
      parent.appendChild(placeholder);
      return true;
    } else {
      // ${1 <- missing curly or colon
      return _backTo(token);
    }
  }

  bool _parseChoiceElement(Choice parent) {
    final token = _token;
    final values = <String>[];

    while (true) {
      if (_token.type == TokenType.comma || _token.type == TokenType.pipe) {
        break;
      }
      String? value = _acceptText(TokenType.backslash);
      if (value != null) {
        // \, \|, or \\
        value =
            _acceptText(TokenType.comma) ??
            _acceptText(TokenType.pipe) ??
            _acceptText(TokenType.backslash) ??
            value;
      } else {
        value = _token.type == TokenType.eof ? null : _acceptText();
      }
      if (value == null || value.isEmpty) {
        // EOF
        _backTo(token);
        return false;
      }
      values.add(value);
    }

    if (values.isEmpty) {
      _backTo(token);
      return false;
    }

    parent.appendChild(Text(values.join()));
    return true;
  }

  // ${foo:<children>}, ${foo} -> variable
  bool _parseComplexVariable(Marker parent) {
    final token = _token;
    String? name;
    final match =
        _accept(TokenType.dollar) &&
        _accept(TokenType.curlyOpen) &&
        (name = _acceptText(TokenType.variableName)) != null;
    if (!match) return _backTo(token);

    final variable = Variable(name!);

    if (_accept(TokenType.colon)) {
      // ${foo:<children>}
      while (true) {
        // ...} -> done
        if (_accept(TokenType.curlyClose)) {
          parent.appendChild(variable);
          return true;
        }
        if (_parse(variable)) continue;

        // fallback
        parent.appendChild(Text('\${$name:'));
        for (final child in List.of(variable.children)) {
          parent.appendChild(child);
        }
        return true;
      }
    } else if (_accept(TokenType.forwardslash)) {
      // ${foo/<regex>/<format>/<options>}
      if (_parseTransform(variable)) {
        parent.appendChild(variable);
        return true;
      }
      _backTo(token);
      return false;
    } else if (_accept(TokenType.curlyClose)) {
      // ${foo}
      parent.appendChild(variable);
      return true;
    } else {
      // ${foo <- missing curly or colon
      return _backTo(token);
    }
  }

  bool _parseTransform(TransformableMarker parent) {
    // ...<regex>/<format>/<options>}

    final transform = Transform();
    var regexValue = '';
    var regexOptions = '';

    // (1) /regex
    while (true) {
      if (_accept(TokenType.forwardslash)) break;

      final escaped = _acceptText(TokenType.backslash);
      if (escaped != null) {
        regexValue += _acceptText(TokenType.forwardslash) ?? escaped;
        continue;
      }

      if (_token.type != TokenType.eof) {
        regexValue += _acceptText()!;
        continue;
      }
      return false;
    }

    // (2) /format
    while (true) {
      if (_accept(TokenType.forwardslash)) break;

      final escaped = _acceptText(TokenType.backslash);
      if (escaped != null) {
        transform.appendChild(
          Text(
            _acceptText(TokenType.backslash) ??
                _acceptText(TokenType.forwardslash) ??
                escaped,
          ),
        );
        continue;
      }

      if (_parseFormatString(transform) || _parseAnything(transform)) {
        continue;
      }
      return false;
    }

    // (3) /option
    while (true) {
      if (_accept(TokenType.curlyClose)) break;
      if (_token.type != TokenType.eof) {
        regexOptions += _acceptText()!;
        continue;
      }
      return false;
    }

    try {
      transform.regexp = SnippetRegExp(regexValue, regexOptions);
    } on FormatException {
      // invalid regexp
      return false;
    }

    parent.transform = transform;
    return true;
  }

  bool _parseFormatString(Transform parent) {
    final token = _token;
    if (!_accept(TokenType.dollar)) return false;

    var complex = false;
    if (_accept(TokenType.curlyOpen)) complex = true;

    final index = _acceptText(TokenType.int_);

    if (index == null) {
      _backTo(token);
      return false;
    } else if (!complex) {
      // $1
      parent.appendChild(FormatString(int.parse(index)));
      return true;
    } else if (_accept(TokenType.curlyClose)) {
      // ${1}
      parent.appendChild(FormatString(int.parse(index)));
      return true;
    } else if (!_accept(TokenType.colon)) {
      _backTo(token);
      return false;
    }

    if (_accept(TokenType.forwardslash)) {
      // ${1:/upcase}
      final shorthand = _acceptText(TokenType.variableName);
      if (shorthand == null || !_accept(TokenType.curlyClose)) {
        _backTo(token);
        return false;
      } else {
        parent.appendChild(FormatString(int.parse(index), shorthand));
        return true;
      }
    } else if (_accept(TokenType.plus)) {
      // ${1:+<if>}
      final ifValue = _until(TokenType.curlyClose);
      if (ifValue != null && ifValue.isNotEmpty) {
        parent.appendChild(FormatString(int.parse(index), null, ifValue));
        return true;
      }
    } else if (_accept(TokenType.dash)) {
      // ${2:-<else>}
      final elseValue = _until(TokenType.curlyClose);
      if (elseValue != null && elseValue.isNotEmpty) {
        parent.appendChild(
          FormatString(int.parse(index), null, null, elseValue),
        );
        return true;
      }
    } else if (_accept(TokenType.questionMark)) {
      // ${2:?<if>:<else>}
      final ifValue = _until(TokenType.colon);
      if (ifValue != null && ifValue.isNotEmpty) {
        final elseValue = _until(TokenType.curlyClose);
        if (elseValue != null && elseValue.isNotEmpty) {
          parent.appendChild(
            FormatString(int.parse(index), null, ifValue, elseValue),
          );
          return true;
        }
      }
    } else {
      // ${1:<else>}
      final elseValue = _until(TokenType.curlyClose);
      if (elseValue != null && elseValue.isNotEmpty) {
        parent.appendChild(
          FormatString(int.parse(index), null, null, elseValue),
        );
        return true;
      }
    }

    _backTo(token);
    return false;
  }

  bool _parseAnything(Marker marker) {
    if (_token.type != TokenType.eof) {
      marker.appendChild(Text(_scanner.tokenText(_token)));
      _accept();
      return true;
    }
    return false;
  }
}
