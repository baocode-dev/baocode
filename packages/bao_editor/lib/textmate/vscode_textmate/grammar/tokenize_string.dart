// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/grammar/tokenizeString.ts (MIT, see LICENSE.md).

import '../debug.dart';
import '../js_semantics.dart';
import '../onig_lib.dart';
import '../rule.dart';
import 'grammar.dart';

class TokenizeStringResult {
  const TokenizeStringResult(this.stack, this.stoppedEarly);

  final StateStackImpl stack;
  final bool stoppedEarly;
}

/// Tokenize a string
///
/// Upstream's `_tokenizeString`. [timeLimit] is in milliseconds; use `0` to
/// indicate no time limit. The result's `stoppedEarly` is set when the time
/// limit has been reached.
TokenizeStringResult tokenizeStringImpl(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  LineTokens lineTokens,
  LineFonts lineFonts,
  bool checkWhileConditions,
  int timeLimit,
) {
  final lineLength = lineText.content.length;

  var anchorPosition = -1;

  if (checkWhileConditions) {
    final whileCheckResult = _checkWhileConditions(
      grammar,
      lineText,
      isFirstLine,
      linePos,
      stack,
      lineTokens,
      lineFonts,
    );
    stack = whileCheckResult.stack;
    linePos = whileCheckResult.linePos;
    isFirstLine = whileCheckResult.isFirstLine;
    anchorPosition = whileCheckResult.anchorPosition;
  }

  final stopwatch = timeLimit != 0 ? (Stopwatch()..start()) : null;
  while (true) {
    if (stopwatch != null) {
      final elapsedTime = stopwatch.elapsedMilliseconds;
      if (elapsedTime > timeLimit) {
        return TokenizeStringResult(stack, true);
      }
    }

    // scanNext(): potentially modifies linePos && anchorPosition
    final r = _matchRuleOrInjections(
      grammar,
      lineText,
      isFirstLine,
      linePos,
      stack,
      anchorPosition,
    );

    if (r == null) {
      // No match
      lineTokens.produce(stack, lineLength);
      lineFonts.produce(stack, lineLength);
      break;
    }

    final captureIndices = r.captureIndices;
    final matchedRuleId = r.ruleId;

    final hasAdvanced = captureIndices.isNotEmpty
        ? captureIndices[0].end > linePos
        : false;

    if (matchedRuleId == endRuleId) {
      // We matched the `end` for this rule => pop it
      final poppedRule = stack.getRule(grammar) as BeginEndRule;

      lineTokens.produce(stack, captureIndices[0].start);
      lineFonts.produce(stack, captureIndices[0].start);
      stack = stack.withContentNameScopesList(stack.nameScopesList!);
      _handleCaptures(
        grammar,
        lineText,
        isFirstLine,
        stack,
        lineTokens,
        lineFonts,
        poppedRule.endCaptures,
        captureIndices,
      );
      lineTokens.produce(stack, captureIndices[0].end);
      lineFonts.produce(stack, captureIndices[0].end);

      // pop
      final popped = stack;
      stack = stack.parent!;
      anchorPosition = popped.getAnchorPos();

      if (!hasAdvanced && popped.getEnterPos() == linePos) {
        // Grammar pushed & popped a rule without advancing
        // "[1] - Grammar is in an endless loop - Grammar pushed & popped a rule without advancing"

        // See https://github.com/Microsoft/vscode-textmate/issues/12
        // Let's assume this was a mistake by the grammar author and the intent was to continue in this state
        stack = popped;

        lineTokens.produce(stack, lineLength);
        lineFonts.produce(stack, lineLength);
        break;
      }
    } else {
      // We matched a rule!
      final rule = grammar.getRule(matchedRuleId)!;

      lineTokens.produce(stack, captureIndices[0].start);
      lineFonts.produce(stack, captureIndices[0].start);

      final beforePush = stack;
      // push it on the stack rule
      final scopeName = rule.getName(lineText.content, captureIndices);
      final nameScopesList = stack.contentNameScopesList!.pushAttributed(
        scopeName,
        grammar,
      );
      stack = stack.push(
        matchedRuleId,
        linePos,
        anchorPosition,
        captureIndices[0].end == lineLength,
        null,
        nameScopesList,
        nameScopesList,
      );

      if (rule is BeginEndRule) {
        final pushedRule = rule;

        _handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          lineFonts,
          pushedRule.beginCaptures,
          captureIndices,
        );
        lineTokens.produce(stack, captureIndices[0].end);
        lineFonts.produce(stack, captureIndices[0].end);
        anchorPosition = captureIndices[0].end;

        final contentName = pushedRule.getContentName(
          lineText.content,
          captureIndices,
        );
        final contentNameScopesList = nameScopesList.pushAttributed(
          contentName,
          grammar,
        );
        stack = stack.withContentNameScopesList(contentNameScopesList);

        if (pushedRule.endHasBackReferences) {
          stack = stack.withEndRule(
            pushedRule.getEndWithResolvedBackReferences(
              lineText.content,
              captureIndices,
            ),
          );
        }

        if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
          // Grammar pushed the same rule without advancing
          // "[2] - Grammar is in an endless loop - Grammar pushed the same rule without advancing"
          stack = stack.pop()!;
          lineTokens.produce(stack, lineLength);
          lineFonts.produce(stack, lineLength);
          break;
        }
      } else if (rule is BeginWhileRule) {
        final pushedRule = rule;

        _handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          lineFonts,
          pushedRule.beginCaptures,
          captureIndices,
        );
        lineTokens.produce(stack, captureIndices[0].end);
        lineFonts.produce(stack, captureIndices[0].end);
        anchorPosition = captureIndices[0].end;
        final contentName = pushedRule.getContentName(
          lineText.content,
          captureIndices,
        );
        final contentNameScopesList = nameScopesList.pushAttributed(
          contentName,
          grammar,
        );
        stack = stack.withContentNameScopesList(contentNameScopesList);

        if (pushedRule.whileHasBackReferences) {
          stack = stack.withEndRule(
            pushedRule.getWhileWithResolvedBackReferences(
              lineText.content,
              captureIndices,
            ),
          );
        }

        if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
          // Grammar pushed the same rule without advancing
          // "[3] - Grammar is in an endless loop - Grammar pushed the same rule without advancing"
          stack = stack.pop()!;
          lineTokens.produce(stack, lineLength);
          lineFonts.produce(stack, lineLength);
          break;
        }
      } else {
        final matchingRule = rule as MatchRule;

        _handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          lineFonts,
          matchingRule.captures,
          captureIndices,
        );
        lineTokens.produce(stack, captureIndices[0].end);
        lineFonts.produce(stack, captureIndices[0].end);

        // pop rule immediately since it is a MatchRule
        stack = stack.pop()!;

        if (!hasAdvanced) {
          // Grammar is not advancing, nor is it pushing/popping
          // "[4] - Grammar is in an endless loop - Grammar is not advancing, nor is it pushing/popping"
          stack = stack.safePop();
          lineTokens.produce(stack, lineLength);
          lineFonts.produce(stack, lineLength);
          break;
        }
      }
    }

    if (captureIndices[0].end > linePos) {
      // Advance stream
      linePos = captureIndices[0].end;
      isFirstLine = false;
    }
  }

  return TokenizeStringResult(stack, false);
}

class _WhileStack {
  const _WhileStack(this.stack, this.rule);

  final StateStackImpl stack;
  final BeginWhileRule rule;
}

class _WhileCheckResult {
  const _WhileCheckResult(
    this.stack,
    this.linePos,
    this.anchorPosition,
    this.isFirstLine,
  );

  final StateStackImpl stack;
  final int linePos;
  final int anchorPosition;
  final bool isFirstLine;
}

/// Walk the stack from bottom to top, and check each while condition in this order.
/// If any fails, cut off the entire stack above the failed while condition. While conditions
/// may also advance the linePosition.
_WhileCheckResult _checkWhileConditions(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  LineTokens lineTokens,
  LineFonts lineFonts,
) {
  var anchorPosition = (stack.beginRuleCapturedEOL ? 0 : -1);

  final whileRules = <_WhileStack>[];
  for (StateStackImpl? node = stack; node != null; node = node.pop()) {
    final nodeRule = node.getRule(grammar);
    if (nodeRule is BeginWhileRule) {
      whileRules.add(_WhileStack(node, nodeRule));
    }
  }

  while (whileRules.isNotEmpty) {
    final whileRule = whileRules.removeLast();
    final ruleScanner = _prepareRuleWhileSearch(
      whileRule.rule,
      grammar,
      whileRule.stack.endRule,
      isFirstLine,
      linePos == anchorPosition,
    );
    final r = ruleScanner.findNextMatchSync(
      lineText,
      linePos,
      _findOptions(isFirstLine, linePos == anchorPosition),
    );

    if (r != null) {
      final matchedRuleId = r.ruleId;
      if (matchedRuleId != whileRuleId) {
        // we shouldn't end up here
        stack = whileRule.stack.pop()!;
        break;
      }
      if (r.captureIndices.isNotEmpty) {
        lineTokens.produce(whileRule.stack, r.captureIndices[0].start);
        lineFonts.produce(whileRule.stack, r.captureIndices[0].start);
        _handleCaptures(
          grammar,
          lineText,
          isFirstLine,
          whileRule.stack,
          lineTokens,
          lineFonts,
          whileRule.rule.whileCaptures,
          r.captureIndices,
        );
        lineTokens.produce(whileRule.stack, r.captureIndices[0].end);
        lineFonts.produce(whileRule.stack, r.captureIndices[0].end);
        anchorPosition = r.captureIndices[0].end;
        if (r.captureIndices[0].end > linePos) {
          linePos = r.captureIndices[0].end;
          isFirstLine = false;
        }
      }
    } else {
      stack = whileRule.stack.pop()!;
      break;
    }
  }

  return _WhileCheckResult(stack, linePos, anchorPosition, isFirstLine);
}

IFindNextMatchResult? _matchRuleOrInjections(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  int anchorPosition,
) {
  // Look for normal grammar rule
  final matchResult = _matchRule(
    grammar,
    lineText,
    isFirstLine,
    linePos,
    stack,
    anchorPosition,
  );

  // Look for injected rules
  final injections = grammar.getInjections();
  if (injections.isEmpty) {
    // No injections whatsoever => early return
    return matchResult;
  }

  final injectionResult = _matchInjections(
    injections,
    grammar,
    lineText,
    isFirstLine,
    linePos,
    stack,
    anchorPosition,
  );
  if (injectionResult == null) {
    // No injections matched => early return
    return matchResult;
  }

  if (matchResult == null) {
    // Only injections matched => early return
    return injectionResult.match;
  }

  // Decide if `matchResult` or `injectionResult` should win
  final matchResultScore = matchResult.captureIndices[0].start;
  final injectionResultScore = injectionResult.match.captureIndices[0].start;

  if (injectionResultScore < matchResultScore ||
      (injectionResult.priorityMatch &&
          injectionResultScore == matchResultScore)) {
    // injection won!
    return injectionResult.match;
  }
  return matchResult;
}

IFindNextMatchResult? _matchRule(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  int anchorPosition,
) {
  final rule = stack.getRule(grammar)!;
  final ruleScanner = _prepareRuleSearch(
    rule,
    grammar,
    stack.endRule,
    isFirstLine,
    linePos == anchorPosition,
  );

  return ruleScanner.findNextMatchSync(
    lineText,
    linePos,
    _findOptions(isFirstLine, linePos == anchorPosition),
  );
}

class _MatchInjectionsResult {
  const _MatchInjectionsResult(this.priorityMatch, this.match);

  final bool priorityMatch;
  final IFindNextMatchResult match;
}

_MatchInjectionsResult? _matchInjections(
  List<Injection> injections,
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  int linePos,
  StateStackImpl stack,
  int anchorPosition,
) {
  // The lower the better
  num bestMatchRating = double.maxFinite;
  IFindNextMatchResult? bestMatch;
  var bestMatchResultPriority = 0;

  final scopes = stack.contentNameScopesList!.getScopeNames();

  for (var i = 0, len = injections.length; i < len; i++) {
    final injection = injections[i];
    if (!injection.matcher(scopes)) {
      // injection selector doesn't match stack
      continue;
    }
    final rule = grammar.getRule(injection.ruleId)!;
    final ruleScanner = _prepareRuleSearch(
      rule,
      grammar,
      null,
      isFirstLine,
      linePos == anchorPosition,
    );
    final matchResult = ruleScanner.findNextMatchSync(
      lineText,
      linePos,
      _findOptions(isFirstLine, linePos == anchorPosition),
    );
    if (matchResult == null) {
      continue;
    }

    final matchRating = matchResult.captureIndices[0].start;
    if (matchRating >= bestMatchRating) {
      // Injections are sorted by priority, so the previous injection had a better or equal priority
      continue;
    }

    bestMatchRating = matchRating;
    bestMatch = matchResult;
    bestMatchResultPriority = injection.priority;

    if (bestMatchRating == linePos) {
      // No more need to look at the rest of the injections.
      break;
    }
  }

  if (bestMatch != null) {
    return _MatchInjectionsResult(bestMatchResultPriority == -1, bestMatch);
  }

  return null;
}

/// Upstream returns `{ ruleScanner, findOptions }`; the options come from
/// [_findOptions] here, which avoids an allocation per scan.
CompiledRule _prepareRuleSearch(
  Rule rule,
  Grammar grammar,
  String? endRegexSource,
  bool allowA,
  bool allowG,
) {
  if (useOnigurumaFindOptions) {
    return rule.compile(grammar, endRegexSource);
  }
  return rule.compileAG(grammar, endRegexSource, allowA, allowG);
}

CompiledRule _prepareRuleWhileSearch(
  BeginWhileRule rule,
  Grammar grammar,
  String? endRegexSource,
  bool allowA,
  bool allowG,
) {
  if (useOnigurumaFindOptions) {
    return rule.compileWhile(grammar, endRegexSource);
  }
  return rule.compileWhileAG(grammar, endRegexSource, allowA, allowG);
}

int _findOptions(bool allowA, bool allowG) {
  if (useOnigurumaFindOptions) {
    return _getFindOptions(allowA, allowG);
  }
  return FindOption.none;
}

int _getFindOptions(bool allowA, bool allowG) {
  var options = FindOption.none;
  if (!allowA) {
    options |= FindOption.notBeginString;
  }
  if (!allowG) {
    options |= FindOption.notBeginPosition;
  }
  return options;
}

void _handleCaptures(
  Grammar grammar,
  OnigString lineText,
  bool isFirstLine,
  StateStackImpl stack,
  LineTokens lineTokens,
  LineFonts lineFonts,
  List<CaptureRule?> captures,
  List<IOnigCaptureIndex> captureIndices,
) {
  if (captures.isEmpty) {
    return;
  }

  final lineTextContent = lineText.content;

  final len = captures.length < captureIndices.length
      ? captures.length
      : captureIndices.length;
  final localStack = <LocalStackElement>[];
  final maxEnd = captureIndices[0].end;

  for (var i = 0; i < len; i++) {
    final captureRule = captures[i];
    if (captureRule == null) {
      // Not interested
      continue;
    }

    final captureIndex = captureIndices[i];

    if (captureIndex.length == 0) {
      // Nothing really captured
      continue;
    }

    if (captureIndex.start > maxEnd) {
      // Capture going beyond consumed string
      break;
    }

    // pop captures while needed
    while (localStack.isNotEmpty &&
        localStack[localStack.length - 1].endPos <= captureIndex.start) {
      // pop!
      lineTokens.produceFromScopes(
        localStack[localStack.length - 1].scopes,
        localStack[localStack.length - 1].endPos,
      );
      lineFonts.produceFromScopes(
        localStack[localStack.length - 1].scopes,
        localStack[localStack.length - 1].endPos,
      );
      localStack.removeLast();
    }

    if (localStack.isNotEmpty) {
      lineTokens.produceFromScopes(
        localStack[localStack.length - 1].scopes,
        captureIndex.start,
      );
      lineFonts.produceFromScopes(
        localStack[localStack.length - 1].scopes,
        captureIndex.start,
      );
    } else {
      lineTokens.produce(stack, captureIndex.start);
      lineFonts.produce(stack, captureIndex.start);
    }

    if (captureRule.retokenizeCapturedWithRuleId != 0) {
      // the capture requires additional matching
      final scopeName = captureRule.getName(lineTextContent, captureIndices);
      final nameScopesList = stack.contentNameScopesList!.pushAttributed(
        scopeName,
        grammar,
      );
      final contentName = captureRule.getContentName(
        lineTextContent,
        captureIndices,
      );
      final contentNameScopesList = nameScopesList.pushAttributed(
        contentName,
        grammar,
      );

      final stackClone = stack.push(
        captureRule.retokenizeCapturedWithRuleId,
        captureIndex.start,
        -1,
        false,
        null,
        nameScopesList,
        contentNameScopesList,
      );
      final onigSubStr = grammar.createOnigString(
        jsSubstring(lineTextContent, 0, captureIndex.end),
      );
      tokenizeStringImpl(
        grammar,
        onigSubStr,
        (isFirstLine && captureIndex.start == 0),
        captureIndex.start,
        stackClone,
        lineTokens,
        lineFonts,
        false,
        /* no time limit */ 0,
      );
      disposeOnigString(onigSubStr);
      continue;
    }

    final captureRuleScopeName = captureRule.getName(
      lineTextContent,
      captureIndices,
    );
    if (captureRuleScopeName != null) {
      // push
      final base = localStack.isNotEmpty
          ? localStack[localStack.length - 1].scopes
          : stack.contentNameScopesList;
      final captureRuleScopesList = base!.pushAttributed(
        captureRuleScopeName,
        grammar,
      );
      localStack.add(
        LocalStackElement(captureRuleScopesList, captureIndex.end),
      );
    }
  }

  while (localStack.isNotEmpty) {
    // pop!
    lineTokens.produceFromScopes(
      localStack[localStack.length - 1].scopes,
      localStack[localStack.length - 1].endPos,
    );
    lineFonts.produceFromScopes(
      localStack[localStack.length - 1].scopes,
      localStack[localStack.length - 1].endPos,
    );
    localStack.removeLast();
  }
}

class LocalStackElement {
  const LocalStackElement(this.scopes, this.endPos);

  final AttributedScopeStack scopes;
  final int endPos;
}
