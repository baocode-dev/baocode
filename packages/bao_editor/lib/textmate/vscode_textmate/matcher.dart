// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/matcher.ts (MIT, see LICENSE.md).

class MatcherWithPriority<T> {
  MatcherWithPriority(this.matcher, this.priority);

  final Matcher<T> matcher;

  /// -1 (`L:`), 0 or 1 (`R:`).
  final int priority;
}

typedef Matcher<T> = bool Function(T matcherInput);

List<MatcherWithPriority<T>> createMatchers<T>(
  String selector,
  bool Function(List<String> names, T matcherInput) matchesName,
) {
  return _MatcherParser<T>(selector, matchesName).parse();
}

class _MatcherParser<T> {
  _MatcherParser(String selector, this.matchesName)
    : tokenizer = _Tokenizer(selector);

  final bool Function(List<String> names, T matcherInput) matchesName;
  final _Tokenizer tokenizer;
  String? token;

  List<MatcherWithPriority<T>> parse() {
    final results = <MatcherWithPriority<T>>[];
    token = tokenizer.next();
    while (token != null) {
      var priority = 0;
      final current = token!;
      if (current.length == 2 && current[1] == ':') {
        switch (current[0]) {
          case 'R':
            priority = 1;
            break;
          case 'L':
            priority = -1;
            break;
          default:
            // Upstream logs `Unknown priority ${token} in scope selector`.
            break;
        }
        token = tokenizer.next();
      }
      final matcher = parseConjunction();
      results.add(MatcherWithPriority<T>(matcher, priority));
      if (token != ',') {
        break;
      }
      token = tokenizer.next();
    }
    return results;
  }

  Matcher<T>? parseOperand() {
    if (token == '-') {
      token = tokenizer.next();
      final expressionToNegate = parseOperand();
      return (matcherInput) =>
          expressionToNegate != null && !expressionToNegate(matcherInput);
    }
    if (token == '(') {
      token = tokenizer.next();
      final expressionInParents = parseInnerExpression();
      if (token == ')') {
        token = tokenizer.next();
      }
      return expressionInParents;
    }
    if (_isIdentifier(token)) {
      final identifiers = <String>[];
      do {
        identifiers.add(token!);
        token = tokenizer.next();
      } while (_isIdentifier(token));
      return (matcherInput) => matchesName(identifiers, matcherInput);
    }
    return null;
  }

  Matcher<T> parseConjunction() {
    final matchers = <Matcher<T>>[];
    var matcher = parseOperand();
    while (matcher != null) {
      matchers.add(matcher);
      matcher = parseOperand();
    }
    // and
    return (matcherInput) => matchers.every((m) => m(matcherInput));
  }

  Matcher<T> parseInnerExpression() {
    final matchers = <Matcher<T>>[];
    Matcher<T>? matcher = parseConjunction();
    while (matcher != null) {
      matchers.add(matcher);
      if (token == '|' || token == ',') {
        do {
          token = tokenizer.next();
        } while (token == '|' || token == ','); // ignore subsequent commas
      } else {
        break;
      }
      matcher = parseConjunction();
    }
    // or
    return (matcherInput) => matchers.any((m) => m(matcherInput));
  }
}

final RegExp _identifierRegExp = RegExp(r'[\w\.:]+');

bool _isIdentifier(String? token) {
  return token != null && token.isNotEmpty && _identifierRegExp.hasMatch(token);
}

final RegExp _tokenRegExp = RegExp(r'([LR]:|[\w\.:][\w\.:\-]*|[\,\|\-\(\)])');

class _Tokenizer {
  _Tokenizer(String input) : _matches = _tokenRegExp.allMatches(input).iterator;

  final Iterator<RegExpMatch> _matches;

  String? next() {
    if (!_matches.moveNext()) {
      return null;
    }
    return _matches.current[0];
  }
}
