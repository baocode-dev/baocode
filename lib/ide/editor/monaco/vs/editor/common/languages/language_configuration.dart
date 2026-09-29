/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/languageConfiguration.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// Dart RegExp replaces JS RegExp; `StandardAutoClosingPairConditional
// .shouldAutoClose` takes a token-type lookup instead of ScopedLineTokens.

import '../encoded_token_attributes.dart';

/// Configuration for line comments.
class LineCommentConfig {
  const LineCommentConfig(this.comment, {this.noIndent = false});

  /// The line comment token, like `//`.
  final String comment;

  /// Whether the token is placed at the first column instead of indented.
  final bool noIndent;
}

/// Describes how comments for a language work.
class CommentRule {
  const CommentRule({this.lineComment, this.blockComment});

  final LineCommentConfig? lineComment;
  final CharacterPair? blockComment;
}

/// A tuple of two characters, like a pair of opening and closing brackets.
typedef CharacterPair = (String, String);

class AutoClosingPair {
  const AutoClosingPair(this.open, this.close);

  final String open;
  final String close;
}

class AutoClosingPairConditional extends AutoClosingPair {
  const AutoClosingPairConditional(super.open, super.close, {this.notIn});

  final List<String>? notIn;
}

/// Describes indentation rules for a language.
class IndentationRule {
  const IndentationRule({
    required this.decreaseIndentPattern,
    required this.increaseIndentPattern,
    this.indentNextLinePattern,
    this.unIndentedLinePattern,
  });

  final RegExp decreaseIndentPattern;
  final RegExp increaseIndentPattern;
  final RegExp? indentNextLinePattern;
  final RegExp? unIndentedLinePattern;
}

class FoldingMarkers {
  const FoldingMarkers(this.start, this.end);

  final RegExp start;
  final RegExp end;
}

class FoldingRules {
  const FoldingRules({this.offSide = false, this.markers});

  final bool offSide;
  final FoldingMarkers? markers;
}

/// Describes what to do with the indentation when pressing Enter.
enum IndentAction {
  /// Insert new line and copy the previous line's indentation.
  none,

  /// Insert new line and indent once.
  indent,

  /// Insert two new lines: the first indented, the second at the same level.
  indentOutdent,

  /// Insert new line and outdent once.
  outdent,
}

/// Describes what to do when pressing Enter.
class EnterAction {
  const EnterAction(this.indentAction, {this.appendText, this.removeText});

  final IndentAction indentAction;
  final String? appendText;
  final int? removeText;
}

class CompleteEnterAction {
  const CompleteEnterAction({
    required this.indentAction,
    required this.appendText,
    required this.removeText,
    required this.indentation,
  });

  final IndentAction indentAction;
  final String appendText;
  final int removeText;

  /// The line's indentation minus removeText.
  final String indentation;
}

/// Describes a rule to be evaluated when pressing Enter.
class OnEnterRule {
  const OnEnterRule({
    required this.beforeText,
    this.afterText,
    this.previousLineText,
    required this.action,
  });

  final RegExp beforeText;
  final RegExp? afterText;
  final RegExp? previousLineText;
  final EnterAction action;
}

/// Definition of documentation comments (e.g. Javadoc/JSdoc).
class DocComment {
  const DocComment(this.open, {this.close});

  final String open;
  final String? close;
}

/// The contract between languages and editor features such as automatic
/// bracket insertion and indentation.
class LanguageConfiguration {
  const LanguageConfiguration({
    this.comments,
    this.brackets,
    this.wordPattern,
    this.indentationRules,
    this.onEnterRules,
    this.autoClosingPairs,
    this.surroundingPairs,
    this.colorizedBracketPairs,
    this.autoCloseBefore,
    this.folding,
    this.docComment,
  });

  final CommentRule? comments;
  final List<CharacterPair>? brackets;
  final RegExp? wordPattern;
  final IndentationRule? indentationRules;
  final List<OnEnterRule>? onEnterRules;
  final List<AutoClosingPairConditional>? autoClosingPairs;
  final List<AutoClosingPair>? surroundingPairs;
  final List<CharacterPair>? colorizedBracketPairs;
  final String? autoCloseBefore;
  final FoldingRules? folding;

  /// Upstream `__electricCharacterSupport.docComment`.
  final DocComment? docComment;
}

class StandardAutoClosingPairConditional {
  StandardAutoClosingPairConditional(AutoClosingPairConditional source)
    : open = source.open,
      close = source.close,
      _inString = !(source.notIn?.contains('string') ?? false),
      _inComment = !(source.notIn?.contains('comment') ?? false),
      _inRegEx = !(source.notIn?.contains('regex') ?? false);

  final String open;
  final String close;
  final bool _inString;
  final bool _inComment;
  final bool _inRegEx;
  String? _neutralCharacter;
  bool _neutralCharacterSearched = false;

  bool isOK(int standardToken) => switch (standardToken) {
    StandardTokenType.comment => _inComment,
    StandardTokenType.string => _inString,
    StandardTokenType.regEx => _inRegEx,
    _ => true,
  };

  /// [standardTokenTypeBefore] is the standard token type at offset
  /// `column - 2` of the line, or null for a line with no tokens (upstream
  /// always auto-closes on an empty line).
  bool shouldAutoClose(int? standardTokenTypeBefore) =>
      standardTokenTypeBefore == null || isOK(standardTokenTypeBefore);

  String? _findNeutralCharacterInRange(int from, int to) {
    for (var code = from; code <= to; code++) {
      final character = String.fromCharCode(code);
      if (!open.contains(character) && !close.contains(character)) {
        return character;
      }
    }
    return null;
  }

  /// Find a character in [0-9a-zA-Z] that does not appear in open or close.
  String? findNeutralCharacter() {
    if (!_neutralCharacterSearched) {
      _neutralCharacterSearched = true;
      _neutralCharacter ??= _findNeutralCharacterInRange(0x30, 0x39);
      _neutralCharacter ??= _findNeutralCharacterInRange(0x61, 0x7a);
      _neutralCharacter ??= _findNeutralCharacterInRange(0x41, 0x5a);
    }
    return _neutralCharacter;
  }
}

class AutoClosingPairs {
  AutoClosingPairs(List<StandardAutoClosingPairConditional> autoClosingPairs) {
    for (final pair in autoClosingPairs) {
      _append(autoClosingPairsOpenByStart, pair.open[0], pair);
      _append(autoClosingPairsOpenByEnd, pair.open[pair.open.length - 1], pair);
      _append(autoClosingPairsCloseByStart, pair.close[0], pair);
      _append(
        autoClosingPairsCloseByEnd,
        pair.close[pair.close.length - 1],
        pair,
      );
      if (pair.close.length == 1 && pair.open.length == 1) {
        _append(autoClosingPairsCloseSingleChar, pair.close, pair);
      }
    }
  }

  /// Key is first character of open.
  final Map<String, List<StandardAutoClosingPairConditional>>
  autoClosingPairsOpenByStart = {};

  /// Key is last character of open.
  final Map<String, List<StandardAutoClosingPairConditional>>
  autoClosingPairsOpenByEnd = {};

  /// Key is first character of close.
  final Map<String, List<StandardAutoClosingPairConditional>>
  autoClosingPairsCloseByStart = {};

  /// Key is last character of close.
  final Map<String, List<StandardAutoClosingPairConditional>>
  autoClosingPairsCloseByEnd = {};

  /// Key is close. Only has pairs that are a single character.
  final Map<String, List<StandardAutoClosingPairConditional>>
  autoClosingPairsCloseSingleChar = {};

  static void _append(
    Map<String, List<StandardAutoClosingPairConditional>> target,
    String key,
    StandardAutoClosingPairConditional value,
  ) => target.putIfAbsent(key, () => []).add(value);
}
