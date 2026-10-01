/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/themes/common/plistParser.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971: `parse`, the XML plist reader
// color themes use for a `.tmTheme` file. The location-tracking variant
// (`locationKeyName`) is not ported.
// Deviations: dictionaries are insertion-ordered `Map<String, Object?>`,
// arrays `List<Object?>`; `<real>`/`<integer>` follow JavaScript's
// `parseFloat`/`parseInt` prefix parsing; `<date>` becomes a `DateTime`
// (null where JavaScript's `Date` would be invalid). Errors are
// [FormatException]s with upstream's messages.

/// Parses an XML property list.
Object? parse(String content) => _PlistParser(content).parse();

const int _bom = 65279;
const int _space = 32;
const int _tab = 9;
const int _carriageReturn = 13;
const int _lineFeed = 10;
const int _slash = 47;
const int _lessThan = 60;
const int _questionMark = 63;
const int _exclamationMark = 33;

const int _rootState = 0;
const int _dictState = 1;
const int _arrState = 2;

class _ParsedTag {
  const _ParsedTag(this.name, this.isClosed);

  final String name;
  final bool isClosed;
}

class _PlistParser {
  _PlistParser(this.content) : len = content.length;

  final String content;
  final int len;
  int pos = 0;

  int state = _rootState;
  Object? cur;
  final List<int> stateStack = [];
  final List<Object?> objStack = [];
  String? curKey;

  int _charCodeAt(int index) =>
      index >= 0 && index < len ? content.codeUnitAt(index) : -1;

  String _substr(int start, int length) =>
      content.substring(start, (start + length).clamp(start, len));

  void skipWhitespace() {
    while (pos < len) {
      final chCode = content.codeUnitAt(pos);
      if (chCode != _space &&
          chCode != _tab &&
          chCode != _carriageReturn &&
          chCode != _lineFeed) {
        break;
      }
      pos++;
    }
  }

  bool advanceIfStartsWith(String str) {
    if (_substr(pos, str.length) == str) {
      pos += str.length;
      return true;
    }
    return false;
  }

  void advanceUntil(String str) {
    final nextOccurence = content.indexOf(str, pos);
    if (nextOccurence != -1) {
      pos = nextOccurence + str.length;
    } else {
      // EOF
      pos = len;
    }
  }

  String captureUntil(String str) {
    final nextOccurence = content.indexOf(str, pos);
    if (nextOccurence != -1) {
      final r = content.substring(pos, nextOccurence);
      pos = nextOccurence + str.length;
      return r;
    } else {
      // EOF
      final r = content.substring(pos);
      pos = len;
      return r;
    }
  }

  void pushState(int newState, Object? newCur) {
    stateStack.add(state);
    objStack.add(cur);
    state = newState;
    cur = newCur;
  }

  void popState() {
    if (stateStack.isEmpty) {
      fail('illegal state stack');
    }
    state = stateStack.removeLast();
    cur = objStack.removeLast();
  }

  Never fail(String msg) {
    throw FormatException('Near offset $pos: $msg ~~~${_substr(pos, 50)}~~~');
  }

  Map<String, Object?> get _dict => cur as Map<String, Object?>;
  List<Object?> get _array => cur as List<Object?>;

  void enterDict() {
    if (state == _dictState) {
      if (curKey == null) {
        fail('missing <key>');
      }
      final newDict = <String, Object?>{};
      _dict[curKey!] = newDict;
      curKey = null;
      pushState(_dictState, newDict);
    } else if (state == _arrState) {
      final newDict = <String, Object?>{};
      _array.add(newDict);
      pushState(_dictState, newDict);
    } else {
      // ROOT_STATE
      cur = <String, Object?>{};
      pushState(_dictState, cur);
    }
  }

  void leaveDict() {
    if (state == _dictState) {
      popState();
    } else {
      // ARR_STATE, ROOT_STATE
      fail('unexpected </dict>');
    }
  }

  void enterArray() {
    if (state == _dictState) {
      if (curKey == null) {
        fail('missing <key>');
      }
      final newArr = <Object?>[];
      _dict[curKey!] = newArr;
      curKey = null;
      pushState(_arrState, newArr);
    } else if (state == _arrState) {
      final newArr = <Object?>[];
      _array.add(newArr);
      pushState(_arrState, newArr);
    } else {
      // ROOT_STATE
      cur = <Object?>[];
      pushState(_arrState, cur);
    }
  }

  void leaveArray() {
    if (state == _arrState) {
      popState();
    } else {
      // DICT_STATE, ROOT_STATE
      fail('unexpected </array>');
    }
  }

  void acceptKey(String val) {
    if (state == _dictState) {
      if (curKey != null) {
        fail('too many <key>');
      }
      curKey = val;
    } else {
      // ARR_STATE, ROOT_STATE
      fail('unexpected <key>');
    }
  }

  /// `acceptString`, `acceptDate`, `acceptData`, `acceptBool` and, once
  /// checked for NaN, `acceptReal` and `acceptInteger`.
  void acceptValue(Object? val) {
    if (state == _dictState) {
      if (curKey == null) {
        fail('missing <key>');
      }
      _dict[curKey!] = val;
      curKey = null;
    } else if (state == _arrState) {
      _array.add(val);
    } else {
      // ROOT_STATE
      cur = val;
    }
  }

  void acceptReal(num val) {
    if (val.isNaN) {
      fail('cannot parse float');
    }
    acceptValue(val);
  }

  void acceptInteger(num val) {
    if (val.isNaN) {
      fail('cannot parse integer');
    }
    acceptValue(val);
  }

  static String escapeVal(String str) => str
      .replaceAllMapped(
        RegExp(r'&#([0-9]+);'),
        (m) => String.fromCharCode(int.parse(m[1]!)),
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-f]+);'),
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
      )
      .replaceAllMapped(RegExp(r'&amp;|&lt;|&gt;|&quot;|&apos;'), (m) {
        switch (m[0]) {
          case '&amp;':
            return '&';
          case '&lt;':
            return '<';
          case '&gt;':
            return '>';
          case '&quot;':
            return '"';
          case '&apos;':
            return "'";
        }
        return m[0]!;
      });

  _ParsedTag parseOpenTag() {
    var r = captureUntil('>');
    var isClosed = false;
    if (r.isNotEmpty && r.codeUnitAt(r.length - 1) == _slash) {
      isClosed = true;
      r = r.substring(0, r.length - 1);
    }
    return _ParsedTag(r.trim(), isClosed);
  }

  String parseTagValue(_ParsedTag tag) {
    if (tag.isClosed) {
      return '';
    }
    final val = captureUntil('</');
    advanceUntil('>');
    return escapeVal(val);
  }

  Object? parse() {
    // Skip UTF8 BOM
    if (len > 0 && content.codeUnitAt(0) == _bom) {
      pos = 1;
    }

    while (pos < len) {
      skipWhitespace();
      if (pos >= len) {
        break;
      }

      final chCode = content.codeUnitAt(pos);
      pos++;
      if (chCode != _lessThan) {
        fail('expected <');
      }

      if (pos >= len) {
        fail('unexpected end of input');
      }

      final peekChCode = _charCodeAt(pos);

      if (peekChCode == _questionMark) {
        pos++;
        advanceUntil('?>');
        continue;
      }

      if (peekChCode == _exclamationMark) {
        pos++;

        if (advanceIfStartsWith('--')) {
          advanceUntil('-->');
          continue;
        }

        advanceUntil('>');
        continue;
      }

      if (peekChCode == _slash) {
        pos++;
        skipWhitespace();

        if (advanceIfStartsWith('plist')) {
          advanceUntil('>');
          continue;
        }

        if (advanceIfStartsWith('dict')) {
          advanceUntil('>');
          leaveDict();
          continue;
        }

        if (advanceIfStartsWith('array')) {
          advanceUntil('>');
          leaveArray();
          continue;
        }

        fail('unexpected closed tag');
      }

      final tag = parseOpenTag();

      switch (tag.name) {
        case 'dict':
          enterDict();
          if (tag.isClosed) {
            leaveDict();
          }
          continue;

        case 'array':
          enterArray();
          if (tag.isClosed) {
            leaveArray();
          }
          continue;

        case 'key':
          acceptKey(parseTagValue(tag));
          continue;

        case 'string':
          acceptValue(parseTagValue(tag));
          continue;

        case 'real':
          acceptReal(_parseFloat(parseTagValue(tag)));
          continue;

        case 'integer':
          acceptInteger(_parseInt(parseTagValue(tag)));
          continue;

        case 'date':
          acceptValue(DateTime.tryParse(parseTagValue(tag)));
          continue;

        case 'data':
          acceptValue(parseTagValue(tag));
          continue;

        case 'true':
          parseTagValue(tag);
          acceptValue(true);
          continue;

        case 'false':
          parseTagValue(tag);
          acceptValue(false);
          continue;
      }

      if (tag.name.startsWith('plist')) {
        continue;
      }

      fail('unexpected opened tag ${tag.name}');
    }

    return cur;
  }
}

/// JavaScript's `parseFloat`: the longest numeric prefix, else NaN.
num _parseFloat(String value) {
  final match = RegExp(r'^[+-]?(Infinity|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)')
      .firstMatch(value.trimLeft());
  if (match == null) return double.nan;
  final text = match[0]!;
  if (text.endsWith('Infinity')) {
    return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  return double.parse(text);
}

/// JavaScript's `parseInt(value, 10)`: the longest integer prefix, else NaN.
num _parseInt(String value) {
  final match = RegExp(r'^[+-]?\d+').firstMatch(value.trimLeft());
  if (match == null) return double.nan;
  return int.tryParse(match[0]!) ?? double.parse(match[0]!);
}
