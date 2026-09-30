// Not an upstream file. JavaScript behaviors that vscode-textmate 9.3.2
// (25b68dad…) relies on implicitly, reproduced for the Dart port (MIT, see
// LICENSE.md). The V8 sort below follows V8's `third_party/v8/builtins/
// array-sort.tq` (TimSort), which is what `Array.prototype.sort` runs in
// VS Code.

/// JavaScript truthiness (`!!value`).
bool jsTruthy(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0 && !value.isNaN;
  if (value is String) return value.isNotEmpty;
  return true;
}

/// Throws what JavaScript would report as a `TypeError`.
Never jsTypeError(String message) => throw ArgumentError(message);

/// `String.prototype.substring`: clamps both ends and swaps them if needed.
String jsSubstring(String s, int start, [int? end]) {
  final len = s.length;
  final a = start < 0 ? 0 : (start > len ? len : start);
  final b = end == null ? len : (end < 0 ? 0 : (end > len ? len : end));
  return a <= b ? s.substring(a, b) : s.substring(b, a);
}

/// `String.prototype.substr`.
String jsSubstr(String s, int start, [int? length]) {
  final len = s.length;
  var from = start < 0 ? len + start : start;
  if (from < 0) from = 0;
  if (from > len) from = len;
  var count = length ?? (len - from);
  if (count < 0) count = 0;
  if (count > len - from) count = len - from;
  return s.substring(from, from + count);
}

/// `String.prototype.split` with a non-empty string separator. Unlike Dart,
/// JavaScript splits the empty string into `['']`.
List<String> jsSplit(String s, String separator) {
  if (s.isEmpty) return [''];
  return s.split(separator);
}

/// Whether [c] is JavaScript `WhiteSpace` or `LineTerminator`.
bool isJsWhitespace(int c) {
  if (c <= 0x20) {
    return c == 0x20 || (c >= 0x09 && c <= 0x0D);
  }
  if (c < 0xA0) return false;
  return c == 0xA0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000 ||
      c == 0xFEFF;
}

/// `String.prototype.trim`. Dart's `trim` also strips U+0085.
String jsTrim(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && isJsWhitespace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isJsWhitespace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return (start == 0 && end == s.length) ? s : s.substring(start, end);
}

/// `parseInt(s, 10)`: an `int`, a `double` when the digits overflow 2^53, or
/// `double.nan` when there are no digits.
num jsParseInt(String s) {
  var i = 0;
  final len = s.length;
  while (i < len && isJsWhitespace(s.codeUnitAt(i))) {
    i++;
  }
  var negative = false;
  if (i < len) {
    final c = s.codeUnitAt(i);
    if (c == 0x2B /* + */ || c == 0x2D /* - */ ) {
      negative = c == 0x2D;
      i++;
    }
  }
  final digitsStart = i;
  while (i < len) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) break;
    i++;
  }
  if (i == digitsStart) return double.nan;
  final digits = s.substring(digitsStart, i);
  num value;
  if (digits.length <= 15) {
    value = int.parse(digits);
  } else {
    final big = BigInt.parse(digits);
    value = big <= BigInt.from(9007199254740992) ? big.toInt() : big.toDouble();
  }
  if (negative) {
    // parseInt('-0') is -0.
    return value == 0 ? -0.0 : -value;
  }
  return value;
}

final RegExp _jsFloatPrefix = RegExp(
  r'^[+-]?(?:Infinity|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)',
);

/// `parseFloat(s)`.
double jsParseFloat(String s) {
  var i = 0;
  while (i < s.length && isJsWhitespace(s.codeUnitAt(i))) {
    i++;
  }
  final match = _jsFloatPrefix.matchAsPrefix(s, i);
  if (match == null) return double.nan;
  var text = match[0]!;
  var negative = false;
  if (text.startsWith('+') || text.startsWith('-')) {
    negative = text.startsWith('-');
    text = text.substring(1);
  }
  double value;
  if (text == 'Infinity') {
    value = double.infinity;
  } else {
    // Dart rejects a trailing or leading bare dot ("1." / ".5" is fine).
    if (text.endsWith('.')) text = '${text}0';
    final ePos = text.indexOf(RegExp('[eE]'));
    if (ePos > 0 && text[ePos - 1] == '.') {
      text = '${text.substring(0, ePos)}0${text.substring(ePos)}';
    }
    value = double.parse(text);
  }
  return negative ? -value : value;
}

/// Whether [key] is a canonical array index ("0", "1", … "4294967294"),
/// which JavaScript objects enumerate first, in ascending order.
bool _isArrayIndexKey(String key) {
  final len = key.length;
  if (len == 0 || len > 10) return false;
  final first = key.codeUnitAt(0);
  if (first < 0x30 || first > 0x39) return false;
  if (first == 0x30) return len == 1;
  for (var i = 1; i < len; i++) {
    final c = key.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return len < 10 || int.parse(key) <= 4294967294;
}

/// The keys of [map] in JavaScript property order (`Object.keys`, `for…in`):
/// array-index keys ascending, then the other keys in insertion order.
List<String> jsObjectKeys(Map<Object?, Object?> map) {
  List<String>? indexKeys;
  final otherKeys = <String>[];
  for (final key in map.keys) {
    final k = key is String ? key : '$key';
    if (_isArrayIndexKey(k)) {
      (indexKeys ??= <String>[]).add(k);
    } else {
      otherKeys.add(k);
    }
  }
  if (indexKeys == null) return otherKeys;
  indexKeys.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return indexKeys..addAll(otherKeys);
}

/// The key/value pairs a JavaScript `for…in` loop visits on [value]: the
/// properties of an object, the indices of an array or string, and nothing
/// for other values (including null and undefined).
Iterable<MapEntry<String, Object?>> jsForInEntries(Object? value) sync* {
  if (value is Map) {
    for (final key in jsObjectKeys(value)) {
      yield MapEntry(
        key,
        value.containsKey(key) ? value[key] : _mapGet(value, key),
      );
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      yield MapEntry('$i', value[i]);
    }
  } else if (value is String) {
    for (var i = 0; i < value.length; i++) {
      yield MapEntry('$i', value[i]);
    }
  }
}

Object? _mapGet(Map<Object?, Object?> map, String key) {
  for (final entry in map.entries) {
    if ('${entry.key}' == key) return entry.value;
  }
  return null;
}

/// A JavaScript property read (`value[key]`) on JSON-shaped data. Reading a
/// property of null throws, as in JavaScript; primitives other than strings
/// have no properties here. Object.prototype members are not modeled.
Object? jsGet(Object? value, String key) {
  if (value is Map) return value[key];
  if (value == null) {
    jsTypeError("Cannot read properties of null (reading '$key')");
  }
  if (value is List) {
    if (key == 'length') return value.length;
    if (_isArrayIndexKey(key)) {
      final i = int.parse(key);
      return i < value.length ? value[i] : null;
    }
    return null;
  }
  if (value is String) {
    if (key == 'length') return value.length;
    if (_isArrayIndexKey(key)) {
      final i = int.parse(key);
      return i < value.length ? value[i] : null;
    }
    return null;
  }
  return null;
}

/// `String(value)` for JSON-shaped values.
String jsToString(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return '$value';
  if (value is double) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
    if (value == value.truncateToDouble() && value.abs() < 1e21) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  if (value is List) {
    return value.map((e) => e == null ? '' : jsToString(e)).join(',');
  }
  if (value is Map) return '[object Object]';
  return value.toString();
}

// ---------------------------------------------------------------------------
// Array.prototype.sort (V8 TimSort)
// ---------------------------------------------------------------------------

/// Sorts [list] in place exactly as V8's `Array.prototype.sort(compare)`
/// does: the same comparisons in the same order, so inconsistent
/// comparators give the same result as in VS Code.
void jsArraySort<T>(List<T> list, num Function(T a, T b) compare) {
  final length = list.length;
  if (length < 2) return;
  _TimSort<T>(list, compare).sort();
}

class _TimSort<T> {
  _TimSort(this.work, this.compareFn);

  static const int _minGallopWins = 7;

  final List<T> work;
  final num Function(T a, T b) compareFn;
  int minGallop = _minGallopWins;
  final List<int> runBase = <int>[];
  final List<int> runLength = <int>[];

  num _compare(T a, T b) => compareFn(a, b);

  void sort() {
    final length = work.length;
    var remaining = length;
    var low = 0;
    final minRunLength = _computeMinRunLength(remaining);
    while (remaining != 0) {
      var currentRunLength = _countAndMakeRun(low, low + remaining);
      if (currentRunLength < minRunLength) {
        final forced = minRunLength < remaining ? minRunLength : remaining;
        _binaryInsertionSort(low, low + currentRunLength, low + forced);
        currentRunLength = forced;
      }
      runBase.add(low);
      runLength.add(currentRunLength);
      _mergeCollapse();
      low += currentRunLength;
      remaining -= currentRunLength;
    }
    _mergeForceCollapse();
  }

  static int _computeMinRunLength(int nArg) {
    var n = nArg;
    var r = 0;
    while (n >= 64) {
      r |= n & 1;
      n >>= 1;
    }
    return n + r;
  }

  int _countAndMakeRun(int lowArg, int high) {
    final low = lowArg + 1;
    if (low == high) return 1;
    var runLength = 2;
    final elementLow = work[low];
    final elementLowPre = work[low - 1];
    var order = _compare(elementLow, elementLowPre);
    final isDescending = order < 0;
    var previousElement = elementLow;
    for (var idx = low + 1; idx < high; ++idx) {
      final currentElement = work[idx];
      order = _compare(currentElement, previousElement);
      if (isDescending) {
        if (order >= 0) break;
      } else {
        if (order < 0) break;
      }
      previousElement = currentElement;
      ++runLength;
    }
    if (isDescending) {
      var lo = lowArg;
      var hi = lowArg + runLength - 1;
      while (lo < hi) {
        final tmp = work[lo];
        work[lo] = work[hi];
        work[hi] = tmp;
        lo++;
        hi--;
      }
    }
    return runLength;
  }

  void _binaryInsertionSort(int low, int startArg, int high) {
    var start = low == startArg ? (startArg + 1) : startArg;
    for (; start < high; ++start) {
      var left = low;
      var right = start;
      final pivot = work[start];
      while (left < right) {
        final mid = left + ((right - left) >> 1);
        final order = _compare(pivot, work[mid]);
        if (order < 0) {
          right = mid;
        } else {
          left = mid + 1;
        }
      }
      for (var p = start; p > left; --p) {
        work[p] = work[p - 1];
      }
      work[left] = pivot;
    }
  }

  bool _runInvariantEstablished(int n) {
    if (n < 2) return true;
    return runLength[n - 2] > runLength[n - 1] + runLength[n];
  }

  void _mergeCollapse() {
    while (runLength.length > 1) {
      var n = runLength.length - 2;
      if (!_runInvariantEstablished(n + 1) || !_runInvariantEstablished(n)) {
        if (runLength[n - 1] < runLength[n + 1]) --n;
        _mergeAt(n);
      } else if (runLength[n] <= runLength[n + 1]) {
        _mergeAt(n);
      } else {
        break;
      }
    }
  }

  void _mergeForceCollapse() {
    while (runLength.length > 1) {
      var n = runLength.length - 2;
      if (n > 0 && runLength[n - 1] < runLength[n + 1]) --n;
      _mergeAt(n);
    }
  }

  void _mergeAt(int i) {
    final stackSize = runLength.length;
    var baseA = runBase[i];
    var lengthA = runLength[i];
    final baseB = runBase[i + 1];
    var lengthB = runLength[i + 1];

    runLength[i] = lengthA + lengthB;
    if (i == stackSize - 3) {
      runBase[i + 1] = runBase[i + 2];
      runLength[i + 1] = runLength[i + 2];
    }
    runBase.removeLast();
    runLength.removeLast();

    final keyRight = work[baseB];
    final k = _gallopRight(work, keyRight, baseA, lengthA, 0);
    baseA += k;
    lengthA -= k;
    if (lengthA == 0) return;

    final keyLeft = work[baseA + lengthA - 1];
    lengthB = _gallopLeft(work, keyLeft, baseB, lengthB, lengthB - 1);
    if (lengthB == 0) return;

    if (lengthA <= lengthB) {
      _mergeLow(baseA, lengthA, baseB, lengthB);
    } else {
      _mergeHigh(baseA, lengthA, baseB, lengthB);
    }
  }

  int _gallopLeft(List<T> array, T key, int base, int length, int hint) {
    var lastOfs = 0;
    var offset = 1;
    final baseHintElement = array[base + hint];
    var order = _compare(baseHintElement, key);
    if (order < 0) {
      final maxOfs = length - hint;
      while (offset < maxOfs) {
        order = _compare(array[base + hint + offset], key);
        if (order >= 0) break;
        lastOfs = offset;
        offset = (offset << 1) + 1;
        if (offset <= 0) offset = maxOfs;
      }
      if (offset > maxOfs) offset = maxOfs;
      lastOfs = lastOfs + hint;
      offset = offset + hint;
    } else {
      final maxOfs = hint + 1;
      while (offset < maxOfs) {
        order = _compare(array[base + hint - offset], key);
        if (order < 0) break;
        lastOfs = offset;
        offset = (offset << 1) + 1;
        if (offset <= 0) offset = maxOfs;
      }
      if (offset > maxOfs) offset = maxOfs;
      final tmp = lastOfs;
      lastOfs = hint - offset;
      offset = hint - tmp;
    }
    lastOfs++;
    while (lastOfs < offset) {
      final m = lastOfs + ((offset - lastOfs) >> 1);
      order = _compare(array[base + m], key);
      if (order < 0) {
        lastOfs = m + 1;
      } else {
        offset = m;
      }
    }
    return offset;
  }

  int _gallopRight(List<T> array, T key, int base, int length, int hint) {
    var lastOfs = 0;
    var offset = 1;
    final baseHintElement = array[base + hint];
    var order = _compare(key, baseHintElement);
    if (order < 0) {
      final maxOfs = hint + 1;
      while (offset < maxOfs) {
        order = _compare(key, array[base + hint - offset]);
        if (order >= 0) break;
        lastOfs = offset;
        offset = (offset << 1) + 1;
        if (offset <= 0) offset = maxOfs;
      }
      if (offset > maxOfs) offset = maxOfs;
      final tmp = lastOfs;
      lastOfs = hint - offset;
      offset = hint - tmp;
    } else {
      final maxOfs = length - hint;
      while (offset < maxOfs) {
        order = _compare(key, array[base + hint + offset]);
        if (order < 0) break;
        lastOfs = offset;
        offset = (offset << 1) + 1;
        if (offset <= 0) offset = maxOfs;
      }
      if (offset > maxOfs) offset = maxOfs;
      lastOfs = lastOfs + hint;
      offset = offset + hint;
    }
    lastOfs++;
    while (lastOfs < offset) {
      final m = lastOfs + ((offset - lastOfs) >> 1);
      order = _compare(key, array[base + m]);
      if (order < 0) {
        offset = m;
      } else {
        lastOfs = m + 1;
      }
    }
    return offset;
  }

  static void _copy<E>(
    List<E> source,
    int srcPos,
    List<E> target,
    int dstPos,
    int length,
  ) {
    if (srcPos < dstPos) {
      var srcIdx = srcPos + length - 1;
      var dstIdx = dstPos + length - 1;
      while (srcIdx >= srcPos) {
        target[dstIdx--] = source[srcIdx--];
      }
    } else {
      var srcIdx = srcPos;
      var dstIdx = dstPos;
      final to = srcPos + length;
      while (srcIdx < to) {
        target[dstIdx++] = source[srcIdx++];
      }
    }
  }

  void _mergeLow(int baseA, int lengthAArg, int baseB, int lengthBArg) {
    var lengthA = lengthAArg;
    var lengthB = lengthBArg;
    final temp = work.sublist(baseA, baseA + lengthA);

    var dest = baseA;
    var cursorTemp = 0;
    var cursorB = baseB;

    work[dest++] = work[cursorB++];

    // 0: Succeed, 1: CopyB.
    var exit = 0;
    outer:
    {
      if (--lengthB == 0) {
        exit = 0;
        break outer;
      }
      if (lengthA == 1) {
        exit = 1;
        break outer;
      }
      var minGallop = this.minGallop;
      while (true) {
        var nofWinsA = 0;
        var nofWinsB = 0;
        while (true) {
          final order = _compare(work[cursorB], temp[cursorTemp]);
          if (order < 0) {
            work[dest++] = work[cursorB++];
            ++nofWinsB;
            --lengthB;
            nofWinsA = 0;
            if (lengthB == 0) {
              exit = 0;
              break outer;
            }
            if (nofWinsB >= minGallop) break;
          } else {
            work[dest++] = temp[cursorTemp++];
            ++nofWinsA;
            --lengthA;
            nofWinsB = 0;
            if (lengthA == 1) {
              exit = 1;
              break outer;
            }
            if (nofWinsA >= minGallop) break;
          }
        }
        ++minGallop;
        var firstIteration = true;
        while (nofWinsA >= _minGallopWins ||
            nofWinsB >= _minGallopWins ||
            firstIteration) {
          firstIteration = false;
          minGallop = minGallop - 1 > 1 ? minGallop - 1 : 1;
          this.minGallop = minGallop;

          nofWinsA = _gallopRight(temp, work[cursorB], cursorTemp, lengthA, 0);
          if (nofWinsA > 0) {
            _copy(temp, cursorTemp, work, dest, nofWinsA);
            dest += nofWinsA;
            cursorTemp += nofWinsA;
            lengthA -= nofWinsA;
            if (lengthA == 1) {
              exit = 1;
              break outer;
            }
            if (lengthA == 0) {
              exit = 0;
              break outer;
            }
          }
          work[dest++] = work[cursorB++];
          if (--lengthB == 0) {
            exit = 0;
            break outer;
          }

          nofWinsB = _gallopLeft(work, temp[cursorTemp], cursorB, lengthB, 0);
          if (nofWinsB > 0) {
            _copy(work, cursorB, work, dest, nofWinsB);
            dest += nofWinsB;
            cursorB += nofWinsB;
            lengthB -= nofWinsB;
            if (lengthB == 0) {
              exit = 0;
              break outer;
            }
          }
          work[dest++] = temp[cursorTemp++];
          if (--lengthA == 1) {
            exit = 1;
            break outer;
          }
        }
        ++minGallop;
        this.minGallop = minGallop;
      }
    }

    if (exit == 0) {
      if (lengthA > 0) {
        _copy(temp, cursorTemp, work, dest, lengthA);
      }
    } else {
      _copy(work, cursorB, work, dest, lengthB);
      work[dest + lengthB] = temp[cursorTemp];
    }
  }

  void _mergeHigh(int baseA, int lengthAArg, int baseB, int lengthBArg) {
    var lengthA = lengthAArg;
    var lengthB = lengthBArg;
    final temp = work.sublist(baseB, baseB + lengthB);

    var dest = baseB + lengthB - 1;
    var cursorTemp = lengthB - 1;
    var cursorA = baseA + lengthA - 1;

    work[dest--] = work[cursorA--];

    // 0: Succeed, 1: CopyA.
    var exit = 0;
    outer:
    {
      if (--lengthA == 0) {
        exit = 0;
        break outer;
      }
      if (lengthB == 1) {
        exit = 1;
        break outer;
      }
      var minGallop = this.minGallop;
      while (true) {
        var nofWinsA = 0;
        var nofWinsB = 0;
        while (true) {
          final order = _compare(temp[cursorTemp], work[cursorA]);
          if (order < 0) {
            work[dest--] = work[cursorA--];
            ++nofWinsA;
            --lengthA;
            nofWinsB = 0;
            if (lengthA == 0) {
              exit = 0;
              break outer;
            }
            if (nofWinsA >= minGallop) break;
          } else {
            work[dest--] = temp[cursorTemp--];
            ++nofWinsB;
            --lengthB;
            nofWinsA = 0;
            if (lengthB == 1) {
              exit = 1;
              break outer;
            }
            if (nofWinsB >= minGallop) break;
          }
        }
        ++minGallop;
        var firstIteration = true;
        while (nofWinsA >= _minGallopWins ||
            nofWinsB >= _minGallopWins ||
            firstIteration) {
          firstIteration = false;
          minGallop = minGallop - 1 > 1 ? minGallop - 1 : 1;
          this.minGallop = minGallop;

          var k = _gallopRight(
            work,
            temp[cursorTemp],
            baseA,
            lengthA,
            lengthA - 1,
          );
          nofWinsA = lengthA - k;
          if (nofWinsA > 0) {
            dest -= nofWinsA;
            cursorA -= nofWinsA;
            _copy(work, cursorA + 1, work, dest + 1, nofWinsA);
            lengthA -= nofWinsA;
            if (lengthA == 0) {
              exit = 0;
              break outer;
            }
          }
          work[dest--] = temp[cursorTemp--];
          if (--lengthB == 1) {
            exit = 1;
            break outer;
          }

          k = _gallopLeft(temp, work[cursorA], 0, lengthB, lengthB - 1);
          nofWinsB = lengthB - k;
          if (nofWinsB > 0) {
            dest -= nofWinsB;
            cursorTemp -= nofWinsB;
            _copy(temp, cursorTemp + 1, work, dest + 1, nofWinsB);
            lengthB -= nofWinsB;
            if (lengthB == 1) {
              exit = 1;
              break outer;
            }
            if (lengthB == 0) {
              exit = 0;
              break outer;
            }
          }
          work[dest--] = work[cursorA--];
          if (--lengthA == 0) {
            exit = 0;
            break outer;
          }
        }
        ++minGallop;
        this.minGallop = minGallop;
      }
    }

    if (exit == 0) {
      if (lengthB > 0) {
        _copy(temp, 0, work, dest - (lengthB - 1), lengthB);
      }
    } else {
      dest -= lengthA;
      cursorA -= lengthA;
      _copy(work, cursorA + 1, work, dest + 1, lengthA);
      work[dest] = temp[cursorTemp];
    }
  }
}
