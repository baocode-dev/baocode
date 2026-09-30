// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/json.ts (MIT, see LICENSE.md).

import 'js_semantics.dart';

Never _doFail(_JSONStreamState streamState, String msg) {
  // console.log('Near offset ' + streamState.pos + ': ' + msg + ' ~~~' + streamState.source.substr(streamState.pos, 50) + '~~~');
  throw FormatException(
    'Near offset ${streamState.pos}: $msg ~~~${jsSubstr(streamState.source, streamState.pos, 50)}~~~',
  );
}

/// Upstream's `ILocation` of this file; the parser returns it as a map with
/// the keys `filename`, `line` and `char`.
Map<String, Object?> _toLocation(String? filename, int line, int char) {
  return <String, Object?>{'filename': filename, 'line': line, 'char': char};
}

/// A JSON parser that can record where each object starts, under the key
/// `$vscodeTextmateLocation`. Numbers are doubles, as in JavaScript.
Object? parseJSON(String source, String? filename, bool withMetadata) {
  final streamState = _JSONStreamState(source);
  final token = _JSONToken();
  var state = _JSONState.rootState;
  Object? cur;
  final stateStack = <int>[];
  final objStack = <Object?>[];

  void pushState() {
    stateStack.add(state);
    objStack.add(cur);
  }

  void popState() {
    state = stateStack.removeLast();
    cur = objStack.removeLast();
  }

  Never fail(String msg) {
    _doFail(streamState, msg);
  }

  while (_nextJSONToken(streamState, token)) {
    if (state == _JSONState.rootState) {
      if (cur != null) {
        fail('too many constructs in root');
      }

      if (token.type == _JSONTokenType.leftCurlyBracket) {
        final dict = <String, Object?>{};
        if (withMetadata) {
          dict[r'$vscodeTextmateLocation'] = token.toLocation(filename);
        }
        cur = dict;
        pushState();
        state = _JSONState.dictState;
        continue;
      }

      if (token.type == _JSONTokenType.leftSquareBracket) {
        cur = <Object?>[];
        pushState();
        state = _JSONState.arrState;
        continue;
      }

      fail('unexpected token in root');
    }

    if (state == _JSONState.dictStateComma) {
      if (token.type == _JSONTokenType.rightCurlyBracket) {
        popState();
        continue;
      }

      if (token.type == _JSONTokenType.comma) {
        state = _JSONState.dictStateNoClose;
        continue;
      }

      fail('expected , or }');
    }

    if (state == _JSONState.dictState || state == _JSONState.dictStateNoClose) {
      if (state == _JSONState.dictState &&
          token.type == _JSONTokenType.rightCurlyBracket) {
        popState();
        continue;
      }

      if (token.type == _JSONTokenType.string) {
        final keyValue = token.value!;
        final dict = cur as Map<String, Object?>;

        if (!_nextJSONToken(streamState, token) ||
            token.type != _JSONTokenType.colon) {
          fail('expected colon');
        }
        if (!_nextJSONToken(streamState, token)) {
          fail('expected value');
        }

        state = _JSONState.dictStateComma;

        if (token.type == _JSONTokenType.string) {
          dict[keyValue] = token.value;
          continue;
        }
        if (token.type == _JSONTokenType.nullToken) {
          dict[keyValue] = null;
          continue;
        }
        if (token.type == _JSONTokenType.trueToken) {
          dict[keyValue] = true;
          continue;
        }
        if (token.type == _JSONTokenType.falseToken) {
          dict[keyValue] = false;
          continue;
        }
        if (token.type == _JSONTokenType.number) {
          dict[keyValue] = jsParseFloat(token.value!);
          continue;
        }
        if (token.type == _JSONTokenType.leftSquareBracket) {
          final newArr = <Object?>[];
          dict[keyValue] = newArr;
          pushState();
          state = _JSONState.arrState;
          cur = newArr;
          continue;
        }
        if (token.type == _JSONTokenType.leftCurlyBracket) {
          final newDict = <String, Object?>{};
          if (withMetadata) {
            newDict[r'$vscodeTextmateLocation'] = token.toLocation(filename);
          }
          dict[keyValue] = newDict;
          pushState();
          state = _JSONState.dictState;
          cur = newDict;
          continue;
        }
      }

      fail('unexpected token in dict');
    }

    if (state == _JSONState.arrStateComma) {
      if (token.type == _JSONTokenType.rightSquareBracket) {
        popState();
        continue;
      }

      if (token.type == _JSONTokenType.comma) {
        state = _JSONState.arrStateNoClose;
        continue;
      }

      fail('expected , or ]');
    }

    if (state == _JSONState.arrState || state == _JSONState.arrStateNoClose) {
      if (state == _JSONState.arrState &&
          token.type == _JSONTokenType.rightSquareBracket) {
        popState();
        continue;
      }

      state = _JSONState.arrStateComma;
      final arr = cur as List<Object?>;

      if (token.type == _JSONTokenType.string) {
        arr.add(token.value);
        continue;
      }
      if (token.type == _JSONTokenType.nullToken) {
        arr.add(null);
        continue;
      }
      if (token.type == _JSONTokenType.trueToken) {
        arr.add(true);
        continue;
      }
      if (token.type == _JSONTokenType.falseToken) {
        arr.add(false);
        continue;
      }
      if (token.type == _JSONTokenType.number) {
        arr.add(jsParseFloat(token.value!));
        continue;
      }

      if (token.type == _JSONTokenType.leftSquareBracket) {
        final newArr = <Object?>[];
        arr.add(newArr);
        pushState();
        state = _JSONState.arrState;
        cur = newArr;
        continue;
      }
      if (token.type == _JSONTokenType.leftCurlyBracket) {
        final newDict = <String, Object?>{};
        if (withMetadata) {
          newDict[r'$vscodeTextmateLocation'] = token.toLocation(filename);
        }
        arr.add(newDict);
        pushState();
        state = _JSONState.dictState;
        cur = newDict;
        continue;
      }

      fail('unexpected token in array');
    }

    fail('unknown state');
  }

  if (objStack.isNotEmpty) {
    fail('unclosed constructs');
  }

  return cur;
}

class _JSONStreamState {
  _JSONStreamState(this.source) : len = source.length;

  final String source;

  int pos = 0;
  final int len;

  int line = 1;
  int char = 0;
}

abstract final class _JSONTokenType {
  static const int unknown = 0;
  static const int string = 1;
  static const int leftSquareBracket = 2; // [
  static const int leftCurlyBracket = 3; // {
  static const int rightSquareBracket = 4; // ]
  static const int rightCurlyBracket = 5; // }
  static const int colon = 6; // :
  static const int comma = 7; // ,
  static const int nullToken = 8;
  static const int trueToken = 9;
  static const int falseToken = 10;
  static const int number = 11;
}

abstract final class _JSONState {
  static const int rootState = 0;
  static const int dictState = 1;
  static const int dictStateComma = 2;
  static const int dictStateNoClose = 3;
  static const int arrState = 4;
  static const int arrStateComma = 5;
  static const int arrStateNoClose = 6;
}

abstract final class _ChCode {
  static const int space = 0x20;
  static const int horizontalTab = 0x09;
  static const int carriageReturn = 0x0D;
  static const int lineFeed = 0x0A;
  static const int quotationMark = 0x22;
  static const int backslash = 0x5C;

  static const int leftSquareBracket = 0x5B;
  static const int leftCurlyBracket = 0x7B;
  static const int rightSquareBracket = 0x5D;
  static const int rightCurlyBracket = 0x7D;
  static const int colon = 0x3A;
  static const int comma = 0x2C;
  static const int dot = 0x2E;

  static const int d0 = 0x30;
  static const int d9 = 0x39;

  static const int minus = 0x2D;
  static const int plus = 0x2B;

  static const int upperE = 0x45;

  static const int a = 0x61;
  static const int e = 0x65;
  static const int f = 0x66;
  static const int l = 0x6C;
  static const int n = 0x6E;
  static const int r = 0x72;
  static const int s = 0x73;
  static const int t = 0x74;
  static const int u = 0x75;
}

class _JSONToken {
  String? value;
  int type = _JSONTokenType.unknown;

  int offset = -1;
  int len = -1;

  /// 1 based line number
  int line = -1;
  int char = -1;

  Map<String, Object?> toLocation(String? filename) {
    return _toLocation(filename, line, char);
  }
}

final RegExp _unicodeEscape = RegExp(r'\\u([0-9A-Fa-f]{4})');
final RegExp _charEscape = RegExp(r'\\(.)');

/// `charCodeAt` returns NaN past the end, which equals no character.
int _charCodeAt(String s, int pos) =>
    pos >= 0 && pos < s.length ? s.codeUnitAt(pos) : -1;

/// precondition: the string is known to be valid JSON (https://www.ietf.org/rfc/rfc4627.txt)
bool _nextJSONToken(_JSONStreamState state, _JSONToken out) {
  out.value = null;
  out.type = _JSONTokenType.unknown;
  out.offset = -1;
  out.len = -1;
  out.line = -1;
  out.char = -1;

  final source = state.source;
  var pos = state.pos;
  final len = state.len;
  var line = state.line;
  var char = state.char;

  //------------------------ skip whitespace
  int chCode;
  do {
    if (pos >= len) {
      return false; /*EOS*/
    }

    chCode = source.codeUnitAt(pos);
    if (chCode == _ChCode.space ||
        chCode == _ChCode.horizontalTab ||
        chCode == _ChCode.carriageReturn) {
      // regular whitespace
      pos++;
      char++;
      continue;
    }

    if (chCode == _ChCode.lineFeed) {
      // newline
      pos++;
      line++;
      char = 0;
      continue;
    }

    // not whitespace
    break;
  } while (true);

  out.offset = pos;
  out.line = line;
  out.char = char;

  if (chCode == _ChCode.quotationMark) {
    //------------------------ strings
    out.type = _JSONTokenType.string;

    pos++;
    char++;

    do {
      if (pos >= len) {
        return false; /*EOS*/
      }

      chCode = source.codeUnitAt(pos);
      pos++;
      char++;

      if (chCode == _ChCode.backslash) {
        // skip next char
        pos++;
        char++;
        continue;
      }

      if (chCode == _ChCode.quotationMark) {
        // end of the string
        break;
      }
    } while (true);

    out.value = jsSubstring(source, out.offset + 1, pos - 1)
        .replaceAllMapped(_unicodeEscape, (m) {
          return String.fromCharCode(int.parse(m[1]!, radix: 16));
        })
        .replaceAllMapped(_charEscape, (m) {
          switch (m[1]) {
            case '"':
              return '"';
            case '\\':
              return '\\';
            case '/':
              return '/';
            case 'b':
              return '\b';
            case 'f':
              return '\f';
            case 'n':
              return '\n';
            case 'r':
              return '\r';
            case 't':
              return '\t';
            default:
              _doFail(state, 'invalid escape sequence');
          }
        });
  } else if (chCode == _ChCode.leftSquareBracket) {
    out.type = _JSONTokenType.leftSquareBracket;
    pos++;
    char++;
  } else if (chCode == _ChCode.leftCurlyBracket) {
    out.type = _JSONTokenType.leftCurlyBracket;
    pos++;
    char++;
  } else if (chCode == _ChCode.rightSquareBracket) {
    out.type = _JSONTokenType.rightSquareBracket;
    pos++;
    char++;
  } else if (chCode == _ChCode.rightCurlyBracket) {
    out.type = _JSONTokenType.rightCurlyBracket;
    pos++;
    char++;
  } else if (chCode == _ChCode.colon) {
    out.type = _JSONTokenType.colon;
    pos++;
    char++;
  } else if (chCode == _ChCode.comma) {
    out.type = _JSONTokenType.comma;
    pos++;
    char++;
  } else if (chCode == _ChCode.n) {
    //------------------------ null

    out.type = _JSONTokenType.nullToken;
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.u) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.l) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.l) {
      return false; /* INVALID */
    }
    pos++;
    char++;
  } else if (chCode == _ChCode.t) {
    //------------------------ true

    out.type = _JSONTokenType.trueToken;
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.r) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.u) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.e) {
      return false; /* INVALID */
    }
    pos++;
    char++;
  } else if (chCode == _ChCode.f) {
    //------------------------ false

    out.type = _JSONTokenType.falseToken;
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.a) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.l) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.s) {
      return false; /* INVALID */
    }
    pos++;
    char++;
    chCode = _charCodeAt(source, pos);
    if (chCode != _ChCode.e) {
      return false; /* INVALID */
    }
    pos++;
    char++;
  } else {
    //------------------------ numbers

    out.type = _JSONTokenType.number;
    do {
      if (pos >= len) {
        return false; /*EOS*/
      }

      chCode = source.codeUnitAt(pos);
      if (chCode == _ChCode.dot ||
          (chCode >= _ChCode.d0 && chCode <= _ChCode.d9) ||
          (chCode == _ChCode.e || chCode == _ChCode.upperE) ||
          (chCode == _ChCode.minus || chCode == _ChCode.plus)) {
        // looks like a piece of a number
        pos++;
        char++;
        continue;
      }

      // pos--; char--;
      break;
    } while (true);
  }

  out.len = pos - out.offset;
  out.value ??= jsSubstr(source, out.offset, out.len);

  state.pos = pos;
  state.line = line;
  state.char = char;

  // console.log('PRODUCING TOKEN: ', _out.value, JSONTokenType[_out.type]);

  return true;
}
