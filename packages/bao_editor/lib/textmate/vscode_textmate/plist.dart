// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/plist.ts (MIT, see LICENSE.md).

import 'js_semantics.dart';

abstract final class _ChCode {
  static const int bom = 65279;

  static const int space = 32;
  static const int tab = 9;
  static const int carriageReturn = 13;
  static const int lineFeed = 10;

  static const int slash = 47;

  static const int lessThan = 60;
  static const int questionMark = 63;
  static const int exclamationMark = 33;
}

abstract final class _State {
  static const int rootState = 0;
  static const int dictState = 1;
  static const int arrState = 2;
}

/// The value of a `<date>` that JavaScript's `Date` constructor would turn
/// into an invalid date. Like a `Date`, it is a non-null object.
final class InvalidPlistDate {
  const InvalidPlistDate(this.source);

  /// The text of the `<date>` element.
  final String source;

  @override
  String toString() => 'Invalid Date';
}

Object? parseWithLocation(
  String content,
  String? filename,
  String? locationKeyName,
) {
  return _parse(content, filename, locationKeyName);
}

/// A very fast plist parser
Object? parsePLIST(String content) {
  return _parse(content, null, null);
}

/// `String.fromCodePoint(parseInt(digits, radix))`.
String _fromCodePoint(String digits, int radix) {
  final value = BigInt.parse(digits, radix: radix);
  if (value > BigInt.from(0x10FFFF)) {
    throw RangeError('Invalid code point $value');
  }
  return String.fromCharCode(value.toInt());
}

final RegExp _decimalEntity = RegExp(r'&#([0-9]+);');
final RegExp _hexEntity = RegExp(r'&#x([0-9a-f]+);');
final RegExp _namedEntity = RegExp(r'&amp;|&lt;|&gt;|&quot;|&apos;');

String _escapeVal(String str) {
  return str
      .replaceAllMapped(_decimalEntity, (m) => _fromCodePoint(m[1]!, 10))
      .replaceAllMapped(_hexEntity, (m) => _fromCodePoint(m[1]!, 16))
      .replaceAllMapped(_namedEntity, (m) {
        final all = m[0]!;
        switch (all) {
          case '&amp;':
            return '&';
          case '&lt;':
            return '<';
          case '&gt;':
            return '>';
          case '&quot;':
            return '"';
          case '&apos;':
            return '\'';
        }
        return all;
      });
}

class _ParsedTag {
  _ParsedTag(this.name, this.isClosed);

  final String name;
  final bool isClosed;
}

Object? _parse(String content, String? filename, String? locationKeyName) {
  final len = content.length;

  var pos = 0;
  var line = 1;
  var char = 0;

  // Skip UTF8 BOM
  if (len > 0 && content.codeUnitAt(0) == _ChCode.bom) {
    pos = 1;
  }

  void advancePosBy(int by) {
    if (locationKeyName == null) {
      pos = pos + by;
    } else {
      while (by > 0) {
        final chCode = pos < len ? content.codeUnitAt(pos) : -1;
        if (chCode == _ChCode.lineFeed) {
          pos++;
          line++;
          char = 0;
        } else {
          pos++;
          char++;
        }
        by--;
      }
    }
  }

  void advancePosTo(int to) {
    if (locationKeyName == null) {
      pos = to;
    } else {
      advancePosBy(to - pos);
    }
  }

  void skipWhitespace() {
    while (pos < len) {
      final chCode = content.codeUnitAt(pos);
      if (chCode != _ChCode.space &&
          chCode != _ChCode.tab &&
          chCode != _ChCode.carriageReturn &&
          chCode != _ChCode.lineFeed) {
        break;
      }
      advancePosBy(1);
    }
  }

  bool advanceIfStartsWith(String str) {
    if (jsSubstr(content, pos, str.length) == str) {
      advancePosBy(str.length);
      return true;
    }
    return false;
  }

  /// `content.indexOf(str, pos)`, which clamps `pos` instead of throwing.
  int indexOfFromPos(String str) {
    return content.indexOf(str, pos < 0 ? 0 : (pos > len ? len : pos));
  }

  void advanceUntil(String str) {
    final nextOccurence = indexOfFromPos(str);
    if (nextOccurence != -1) {
      advancePosTo(nextOccurence + str.length);
    } else {
      // EOF
      advancePosTo(len);
    }
  }

  String captureUntil(String str) {
    final nextOccurence = indexOfFromPos(str);
    if (nextOccurence != -1) {
      final r = jsSubstring(content, pos, nextOccurence);
      advancePosTo(nextOccurence + str.length);
      return r;
    } else {
      // EOF
      final r = jsSubstr(content, pos);
      advancePosTo(len);
      return r;
    }
  }

  var state = _State.rootState;

  Object? cur;
  final stateStack = <int>[];
  final objStack = <Object?>[];
  String? curKey;

  void pushState(int newState, Object? newCur) {
    stateStack.add(state);
    objStack.add(cur);
    state = newState;
    cur = newCur;
  }

  Never fail(String msg) {
    throw FormatException(
      'Near offset $pos: $msg ~~~${jsSubstr(content, pos, 50)}~~~',
    );
  }

  void popState() {
    if (stateStack.isEmpty) {
      fail('illegal state stack');
    }
    state = stateStack.removeLast();
    cur = objStack.removeLast();
  }

  Map<String, Object?> newDictWithLocation() {
    final newDict = <String, Object?>{};
    if (locationKeyName != null) {
      newDict[locationKeyName] = <String, Object?>{
        'filename': filename,
        'line': line,
        'char': char,
      };
    }
    return newDict;
  }

  void dictStateEnterDict() {
    final key = curKey;
    if (key == null) {
      fail('missing <key>');
    }
    final newDict = newDictWithLocation();
    (cur as Map<String, Object?>)[key] = newDict;
    curKey = null;
    pushState(_State.dictState, newDict);
  }

  void dictStateEnterArray() {
    final key = curKey;
    if (key == null) {
      fail('missing <key>');
    }
    final newArr = <Object?>[];
    (cur as Map<String, Object?>)[key] = newArr;
    curKey = null;
    pushState(_State.arrState, newArr);
  }

  void arrStateEnterDict() {
    final newDict = newDictWithLocation();
    (cur as List<Object?>).add(newDict);
    pushState(_State.dictState, newDict);
  }

  void arrStateEnterArray() {
    final newArr = <Object?>[];
    (cur as List<Object?>).add(newArr);
    pushState(_State.arrState, newArr);
  }

  void enterDict() {
    if (state == _State.dictState) {
      dictStateEnterDict();
    } else if (state == _State.arrState) {
      arrStateEnterDict();
    } else {
      // ROOT_STATE
      cur = newDictWithLocation();
      pushState(_State.dictState, cur);
    }
  }

  void leaveDict() {
    if (state == _State.dictState) {
      popState();
    } else if (state == _State.arrState) {
      fail('unexpected </dict>');
    } else {
      // ROOT_STATE
      fail('unexpected </dict>');
    }
  }

  void enterArray() {
    if (state == _State.dictState) {
      dictStateEnterArray();
    } else if (state == _State.arrState) {
      arrStateEnterArray();
    } else {
      // ROOT_STATE
      cur = <Object?>[];
      pushState(_State.arrState, cur);
    }
  }

  void leaveArray() {
    if (state == _State.dictState) {
      fail('unexpected </array>');
    } else if (state == _State.arrState) {
      popState();
    } else {
      // ROOT_STATE
      fail('unexpected </array>');
    }
  }

  void acceptKey(String val) {
    if (state == _State.dictState) {
      if (curKey != null) {
        fail('too many <key>');
      }
      curKey = val;
    } else if (state == _State.arrState) {
      fail('unexpected <key>');
    } else {
      // ROOT_STATE
      fail('unexpected <key>');
    }
  }

  /// The shared body of upstream's `acceptString`, `acceptReal`,
  /// `acceptInteger`, `acceptDate`, `acceptData` and `acceptBool`.
  void acceptValue(Object? val) {
    if (state == _State.dictState) {
      final key = curKey;
      if (key == null) {
        fail('missing <key>');
      }
      (cur as Map<String, Object?>)[key] = val;
      curKey = null;
    } else if (state == _State.arrState) {
      (cur as List<Object?>).add(val);
    } else {
      // ROOT_STATE
      cur = val;
    }
  }

  void acceptReal(double val) {
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

  _ParsedTag parseOpenTag() {
    var r = captureUntil('>');
    var isClosed = false;
    if (r.isNotEmpty && r.codeUnitAt(r.length - 1) == _ChCode.slash) {
      isClosed = true;
      r = r.substring(0, r.length - 1);
    }

    return _ParsedTag(jsTrim(r), isClosed);
  }

  String parseTagValue(_ParsedTag tag) {
    if (tag.isClosed) {
      return '';
    }
    final val = captureUntil('</');
    advanceUntil('>');
    return _escapeVal(val);
  }

  while (pos < len) {
    skipWhitespace();
    if (pos >= len) {
      break;
    }

    final chCode = content.codeUnitAt(pos);
    advancePosBy(1);
    if (chCode != _ChCode.lessThan) {
      fail('expected <');
    }

    if (pos >= len) {
      fail('unexpected end of input');
    }

    final peekChCode = content.codeUnitAt(pos);

    if (peekChCode == _ChCode.questionMark) {
      advancePosBy(1);
      advanceUntil('?>');
      continue;
    }

    if (peekChCode == _ChCode.exclamationMark) {
      advancePosBy(1);

      if (advanceIfStartsWith('--')) {
        advanceUntil('-->');
        continue;
      }

      advanceUntil('>');
      continue;
    }

    if (peekChCode == _ChCode.slash) {
      advancePosBy(1);
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
        acceptReal(jsParseFloat(parseTagValue(tag)));
        continue;

      case 'integer':
        acceptInteger(jsParseInt(parseTagValue(tag)));
        continue;

      case 'date':
        final text = parseTagValue(tag);
        acceptValue(DateTime.tryParse(text) ?? InvalidPlistDate(text));
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
