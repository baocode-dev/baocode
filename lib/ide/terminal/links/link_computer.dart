/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The editor's URL finder, which the terminal's URI link detector runs over
// a wrapped line: `http://`, `https://` and `file://` links, ended by spaces,
// quotes and brackets the way people write them in prose and code.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/common/languages/linkComputer.ts, with the `IRange` and
// `ILink` shapes of editor/common/core/range.ts and editor/common/languages.ts
// (records, so that they compare by value like the tests' object literals)
// and the ASCII table plus sparse map of core/characterClassifier.ts folded
// into [_CharacterClassifier]. Links are always strings (upstream's
// `url: URI | string`); `tooltip` is left out.

import 'dart:typed_data';

/// A one-based range of a text model.
typedef IRange = ({
  int startLineNumber,
  int startColumn,
  int endLineNumber,
  int endColumn,
});

/// A link found by [LinkComputer].
typedef ILink = ({IRange range, String url});

/// The lines [LinkComputer.computeLinks] reads; one-based line numbers.
abstract interface class ILinkComputerTarget {
  int getLineCount();
  String getLineContent(int lineNumber);
}

/// The states of the URL scheme matcher.
abstract final class State {
  static const int invalid = 0;
  static const int start = 1;
  static const int h = 2;
  static const int ht = 3;
  static const int htt = 4;
  static const int http = 5;
  static const int f = 6;
  static const int fi = 7;
  static const int fil = 8;
  static const int beforeColon = 9;
  static const int afterColon = 10;
  static const int almostThere = 11;
  static const int end = 12;
  static const int accept = 13;

  /// Marker; custom states may follow.
  static const int lastKnownState = 14;
}

/// An edge of the state machine: from state, character code, to state.
typedef Edge = (int from, int chCode, int to);

class _Uint8Matrix {
  _Uint8Matrix(this.rows, this.cols, int defaultValue)
    : _data = Uint8List(rows * cols)..fillRange(0, rows * cols, defaultValue);

  final Uint8List _data;
  final int rows;
  final int cols;

  int get(int row, int col) => _data[row * cols + col];

  void set(int row, int col, int value) {
    _data[row * cols + col] = value;
  }
}

class StateMachine {
  factory StateMachine(List<Edge> edges) {
    var maxCharCode = 0;
    var maxState = State.invalid;
    for (final (from, chCode, to) in edges) {
      if (chCode > maxCharCode) {
        maxCharCode = chCode;
      }
      if (from > maxState) {
        maxState = from;
      }
      if (to > maxState) {
        maxState = to;
      }
    }

    maxCharCode++;
    maxState++;

    final states = _Uint8Matrix(maxState, maxCharCode, State.invalid);
    for (final (from, chCode, to) in edges) {
      states.set(from, chCode, to);
    }
    return StateMachine._(states, maxCharCode);
  }

  StateMachine._(this._states, this._maxCharCode);

  final _Uint8Matrix _states;
  final int _maxCharCode;

  int nextState(int currentState, int chCode) {
    if (chCode < 0 || chCode >= _maxCharCode) {
      return State.invalid;
    }
    return _states.get(currentState, chCode);
  }
}

// State machine for http:// or https:// or file://
StateMachine? _stateMachine;
StateMachine _getStateMachine() {
  int c(String ch) => ch.codeUnitAt(0);
  return _stateMachine ??= StateMachine([
    (State.start, c('h'), State.h),
    (State.start, c('H'), State.h),
    (State.start, c('f'), State.f),
    (State.start, c('F'), State.f),

    (State.h, c('t'), State.ht),
    (State.h, c('T'), State.ht),

    (State.ht, c('t'), State.htt),
    (State.ht, c('T'), State.htt),

    (State.htt, c('p'), State.http),
    (State.htt, c('P'), State.http),

    (State.http, c('s'), State.beforeColon),
    (State.http, c('S'), State.beforeColon),
    (State.http, c(':'), State.afterColon),

    (State.f, c('i'), State.fi),
    (State.f, c('I'), State.fi),

    (State.fi, c('l'), State.fil),
    (State.fi, c('L'), State.fil),

    (State.fil, c('e'), State.beforeColon),
    (State.fil, c('E'), State.beforeColon),

    (State.beforeColon, c(':'), State.afterColon),

    (State.afterColon, c('/'), State.almostThere),

    (State.almostThere, c('/'), State.end),
  ]);
}

abstract final class _CharacterClass {
  static const int none = 0;
  static const int forceTermination = 1;
  static const int cannotEndIn = 2;
}

/// A compact ASCII table plus a sparse map for the other characters.
class _CharacterClassifier {
  _CharacterClassifier(this._defaultValue)
    : _asciiMap = Uint8List(256)..fillRange(0, 256, _defaultValue);

  final Uint8List _asciiMap;
  final Map<int, int> _map = {};
  final int _defaultValue;

  void set(int charCode, int value) {
    if (charCode >= 0 && charCode < 256) {
      _asciiMap[charCode] = value;
    } else {
      _map[charCode] = value;
    }
  }

  int get(int charCode) {
    if (charCode >= 0 && charCode < 256) {
      return _asciiMap[charCode];
    }
    return _map[charCode] ?? _defaultValue;
  }
}

_CharacterClassifier? _classifier;
_CharacterClassifier _getClassifier() {
  var classifier = _classifier;
  if (classifier == null) {
    classifier = _classifier = _CharacterClassifier(_CharacterClass.none);

    const forceTerminationCharacters = ' \t<>\'"、。｡､，．：；‘〈「『〔（［｛｢｣｝］）〕』」〉’｀～…|';
    for (var i = 0; i < forceTerminationCharacters.length; i++) {
      classifier.set(
        forceTerminationCharacters.codeUnitAt(i),
        _CharacterClass.forceTermination,
      );
    }

    const cannotEndWithCharacters = '.,;:';
    for (var i = 0; i < cannotEndWithCharacters.length; i++) {
      classifier.set(
        cannotEndWithCharacters.codeUnitAt(i),
        _CharacterClass.cannotEndIn,
      );
    }
  }
  return classifier;
}

abstract final class _CharCode {
  static const int space = 0x20;
  static const int doubleQuote = 0x22;
  static const int singleQuote = 0x27;
  static const int openParen = 0x28;
  static const int closeParen = 0x29;
  static const int asterisk = 0x2A;
  static const int openSquareBracket = 0x5B;
  static const int closeSquareBracket = 0x5D;
  static const int backTick = 0x60;
  static const int openCurlyBrace = 0x7B;
  static const int closeCurlyBrace = 0x7D;
}

abstract final class LinkComputer {
  static ILink _createLink(
    _CharacterClassifier classifier,
    String line,
    int lineNumber,
    int linkBeginIndex,
    int linkEndIndex,
  ) {
    // Do not allow to end link in certain characters...
    var lastIncludedCharIndex = linkEndIndex - 1;
    do {
      final chCode = line.codeUnitAt(lastIncludedCharIndex);
      final chClass = classifier.get(chCode);
      if (chClass != _CharacterClass.cannotEndIn) {
        break;
      }
      lastIncludedCharIndex--;
    } while (lastIncludedCharIndex > linkBeginIndex);

    // Handle links enclosed in parens, square brackets and curlys.
    if (linkBeginIndex > 0) {
      final charCodeBeforeLink = line.codeUnitAt(linkBeginIndex - 1);
      final lastCharCodeInLink = line.codeUnitAt(lastIncludedCharIndex);

      if ((charCodeBeforeLink == _CharCode.openParen &&
              lastCharCodeInLink == _CharCode.closeParen) ||
          (charCodeBeforeLink == _CharCode.openSquareBracket &&
              lastCharCodeInLink == _CharCode.closeSquareBracket) ||
          (charCodeBeforeLink == _CharCode.openCurlyBrace &&
              lastCharCodeInLink == _CharCode.closeCurlyBrace)) {
        // Do not end in ) if ( is before the link start
        // Do not end in ] if [ is before the link start
        // Do not end in } if { is before the link start
        lastIncludedCharIndex--;
      }
    }

    return (
      range: (
        startLineNumber: lineNumber,
        startColumn: linkBeginIndex + 1,
        endLineNumber: lineNumber,
        endColumn: lastIncludedCharIndex + 2,
      ),
      url: line.substring(linkBeginIndex, lastIncludedCharIndex + 1),
    );
  }

  static List<ILink> computeLinks(
    ILinkComputerTarget model, [
    StateMachine? stateMachine,
  ]) {
    stateMachine ??= _getStateMachine();
    final classifier = _getClassifier();

    final result = <ILink>[];
    for (var i = 1, lineCount = model.getLineCount(); i <= lineCount; i++) {
      final line = model.getLineContent(i);
      final len = line.length;

      var j = 0;
      var linkBeginIndex = 0;
      var linkBeginChCode = 0;
      var state = State.start;
      var hasOpenParens = false;
      var hasOpenSquareBracket = false;
      var inSquareBrackets = false;
      var hasOpenCurlyBracket = false;

      while (j < len) {
        var resetStateMachine = false;
        final chCode = line.codeUnitAt(j);

        if (state == State.accept) {
          int chClass;
          switch (chCode) {
            case _CharCode.openParen:
              hasOpenParens = true;
              chClass = _CharacterClass.none;
            case _CharCode.closeParen:
              chClass = hasOpenParens
                  ? _CharacterClass.none
                  : _CharacterClass.forceTermination;
            case _CharCode.openSquareBracket:
              inSquareBrackets = true;
              hasOpenSquareBracket = true;
              chClass = _CharacterClass.none;
            case _CharCode.closeSquareBracket:
              inSquareBrackets = false;
              chClass = hasOpenSquareBracket
                  ? _CharacterClass.none
                  : _CharacterClass.forceTermination;
            case _CharCode.openCurlyBrace:
              hasOpenCurlyBracket = true;
              chClass = _CharacterClass.none;
            case _CharCode.closeCurlyBrace:
              chClass = hasOpenCurlyBracket
                  ? _CharacterClass.none
                  : _CharacterClass.forceTermination;

            // The following three rules make it that ' or " or ` are allowed
            // inside links only if the link is wrapped by some other quote
            // character
            case _CharCode.singleQuote:
            case _CharCode.doubleQuote:
            case _CharCode.backTick:
              if (linkBeginChCode == chCode) {
                chClass = _CharacterClass.forceTermination;
              } else if (linkBeginChCode == _CharCode.singleQuote ||
                  linkBeginChCode == _CharCode.doubleQuote ||
                  linkBeginChCode == _CharCode.backTick) {
                chClass = _CharacterClass.none;
              } else {
                chClass = _CharacterClass.forceTermination;
              }
            case _CharCode.asterisk:
              // `*` terminates a link if the link began with `*`
              chClass = linkBeginChCode == _CharCode.asterisk
                  ? _CharacterClass.forceTermination
                  : _CharacterClass.none;
            case _CharCode.space:
              // ` ` allow space in between [ and ]
              chClass = inSquareBrackets
                  ? _CharacterClass.none
                  : _CharacterClass.forceTermination;
            default:
              chClass = classifier.get(chCode);
          }

          // Check if character terminates link
          if (chClass == _CharacterClass.forceTermination) {
            result.add(_createLink(classifier, line, i, linkBeginIndex, j));
            resetStateMachine = true;
          }
        } else if (state == State.end) {
          int chClass;
          if (chCode == _CharCode.openSquareBracket) {
            // Allow for the authority part to contain ipv6 addresses which
            // contain [ and ]
            hasOpenSquareBracket = true;
            chClass = _CharacterClass.none;
          } else {
            chClass = classifier.get(chCode);
          }

          // Check if character terminates link
          if (chClass == _CharacterClass.forceTermination) {
            resetStateMachine = true;
          } else {
            state = State.accept;
          }
        } else {
          state = stateMachine.nextState(state, chCode);
          if (state == State.invalid) {
            resetStateMachine = true;
          }
        }

        if (resetStateMachine) {
          state = State.start;
          hasOpenParens = false;
          hasOpenSquareBracket = false;
          hasOpenCurlyBracket = false;

          // Record where the link started
          linkBeginIndex = j + 1;
          linkBeginChCode = chCode;
        }

        j++;
      }

      if (state == State.accept) {
        result.add(_createLink(classifier, line, i, linkBeginIndex, len));
      }
    }

    return result;
  }
}

/// Returns an array of all links contains in the provided document. *Note*
/// that this operation is computational expensive and should not run in the
/// UI thread.
List<ILink> computeLinks(ILinkComputerTarget? model) {
  if (model == null) {
    // Unknown caller!
    return [];
  }
  return LinkComputer.computeLinks(model);
}
