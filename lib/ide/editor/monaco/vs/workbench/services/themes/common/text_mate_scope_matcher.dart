/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/themes/common/
// textMateScopeMatcher.ts at 6a598d4a13031703d483d103c1d934a36ad27971: the
// scope selector parser color themes match their TextMate rules with
// (`createMatchers`). Upstream's nested functions sharing `token` become the
// methods of a private parser. The `console.log` for an unknown priority is
// dropped: the tokenizer only produces `L:` and `R:`.

class MatcherWithPriority<T> {
  const MatcherWithPriority(this.matcher, this.priority);

  final Matcher<T> matcher;

  /// -1, 0 or 1.
  final int priority;
}

typedef Matcher<T> = int Function(T matcherInput);

void createMatchers<T>(
  String selector,
  int Function(List<String> names, T matcherInput) matchesName,
  List<MatcherWithPriority<T>> results,
) {
  final parser = _Parser<T>(selector, matchesName);
  while (parser.token != null) {
    var priority = 0;
    final token = parser.token!;
    if (token.length == 2 && token[1] == ':') {
      switch (token[0]) {
        case 'R':
          priority = 1;
        case 'L':
          priority = -1;
      }
      parser.token = parser.next();
    }
    final matcher = parser.parseConjunction();
    if (matcher != null) {
      results.add(MatcherWithPriority(matcher, priority));
    }
    if (parser.token != ',') {
      break;
    }
    parser.token = parser.next();
  }
}

class _Parser<T> {
  _Parser(String input, this.matchesName)
    : _matches = _tokenPattern.allMatches(input).iterator {
    token = next();
  }

  static final RegExp _tokenPattern = RegExp(
    r'([LR]:|[\w\.:][\w\.:\-]*|[\,\|\-\(\)])',
  );

  final int Function(List<String> names, T matcherInput) matchesName;
  final Iterator<RegExpMatch> _matches;
  String? token;

  String? next() => _matches.moveNext() ? _matches.current[0] : null;

  Matcher<T>? parseOperand() {
    if (token == '-') {
      token = next();
      final expressionToNegate = parseOperand();
      if (expressionToNegate == null) {
        return null;
      }
      return (matcherInput) {
        final score = expressionToNegate(matcherInput);
        return score < 0 ? 0 : -1;
      };
    }
    if (token == '(') {
      token = next();
      final expressionInParents = parseInnerExpression();
      if (token == ')') {
        token = next();
      }
      return expressionInParents;
    }
    if (_isIdentifier(token)) {
      final identifiers = <String>[];
      do {
        identifiers.add(token!);
        token = next();
      } while (_isIdentifier(token));
      return (matcherInput) => matchesName(identifiers, matcherInput);
    }
    return null;
  }

  Matcher<T>? parseConjunction() {
    var matcher = parseOperand();
    if (matcher == null) {
      return null;
    }

    final matchers = <Matcher<T>>[];
    while (matcher != null) {
      matchers.add(matcher);
      matcher = parseOperand();
    }
    return (matcherInput) {
      // and
      var min = matchers[0](matcherInput);
      for (var i = 1; min >= 0 && i < matchers.length; i++) {
        final score = matchers[i](matcherInput);
        if (score < min) min = score;
      }
      return min;
    };
  }

  Matcher<T>? parseInnerExpression() {
    var matcher = parseConjunction();
    if (matcher == null) {
      return null;
    }
    final matchers = <Matcher<T>>[];
    while (matcher != null) {
      matchers.add(matcher);
      if (token == '|' || token == ',') {
        do {
          token = next();
        } while (token == '|' || token == ','); // ignore subsequent commas
      } else {
        break;
      }
      matcher = parseConjunction();
    }
    return (matcherInput) {
      // or
      var max = matchers[0](matcherInput);
      for (var i = 1; i < matchers.length; i++) {
        final score = matchers[i](matcherInput);
        if (score > max) max = score;
      }
      return max;
    };
  }
}

final RegExp _identifierPattern = RegExp(r'[\w\.:]+');

bool _isIdentifier(String? token) =>
    token != null && token.isNotEmpty && _identifierPattern.hasMatch(token);
