// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/utils.ts (MIT, see LICENSE.md).

import 'js_semantics.dart';
import 'onig_lib.dart';

/// A deep copy of JSON-shaped data, as upstream's `clone`.
///
/// Like upstream (where `typeof null === 'object'`), null and non-JSON
/// objects become empty objects; strings, numbers and booleans are kept.
T clone<T>(T something) => _doClone(something) as T;

Object? _doClone(Object? something) {
  if (something is List) {
    return _cloneArray(something);
  }
  if (something is String || something is num || something is bool) {
    return something;
  }
  return _cloneObj(something);
}

List<Object?> _cloneArray(List<Object?> arr) {
  final r = List<Object?>.filled(arr.length, null, growable: true);
  for (var i = 0, len = arr.length; i < len; i++) {
    r[i] = _doClone(arr[i]);
  }
  return r;
}

Map<String, Object?> _cloneObj(Object? obj) {
  final r = <String, Object?>{};
  if (obj is Map) {
    for (final entry in obj.entries) {
      r['${entry.key}'] = _doClone(entry.value);
    }
  }
  return r;
}

/// Copies every enumerable property of [sources] into [target].
Map<String, Object?> mergeObjects(
  Map<String, Object?> target,
  List<Object?> sources,
) {
  for (final source in sources) {
    for (final entry in jsForInEntries(source)) {
      target[entry.key] = entry.value;
    }
  }
  return target;
}

String basename(String path) {
  var idx = ~path.lastIndexOf('/');
  if (idx == 0) idx = ~path.lastIndexOf('\\');
  if (idx == 0) {
    return path;
  } else if (~idx == path.length - 1) {
    return basename(path.substring(0, path.length - 1));
  } else {
    return jsSubstr(path, ~idx + 1);
  }
}

final RegExp _capturingRegexSource = RegExp(
  r'\$(\d+)|\$\{(\d+):\/(downcase|upcase)\}',
);

abstract final class RegexSource {
  static bool hasCaptures(String? regexSource) {
    if (regexSource == null) {
      return false;
    }
    return _capturingRegexSource.hasMatch(regexSource);
  }

  static String replaceCaptures(
    String regexSource,
    String captureSource,
    List<IOnigCaptureIndex> captureIndices,
  ) {
    return regexSource.replaceAllMapped(_capturingRegexSource, (match) {
      final index = match[1];
      final commandIndex = match[2];
      final command = match[3];
      final capture = _captureAt(captureIndices, index ?? commandIndex!);
      if (capture != null) {
        var result = jsSubstring(captureSource, capture.start, capture.end);
        // Remove leading dots that would make the selector invalid
        while (result.startsWith('.')) {
          result = result.substring(1);
        }
        switch (command) {
          case 'downcase':
            return result.toLowerCase();
          case 'upcase':
            return result.toUpperCase();
          default:
            return result;
        }
      } else {
        return match[0]!;
      }
    });
  }

  static IOnigCaptureIndex? _captureAt(
    List<IOnigCaptureIndex> captureIndices,
    String digits,
  ) {
    final i = int.tryParse(digits);
    if (i == null || i >= captureIndices.length) return null;
    return captureIndices[i];
  }
}

/// `a < b` on JavaScript strings: UTF-16 code unit order.
int strcmp(String a, String b) {
  final r = a.compareTo(b);
  return r < 0 ? -1 : (r > 0 ? 1 : 0);
}

int strArrCmp(List<String>? a, List<String>? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return -1;
  }
  if (b == null) {
    return 1;
  }
  final len1 = a.length;
  final len2 = b.length;
  if (len1 == len2) {
    for (var i = 0; i < len1; i++) {
      final res = strcmp(a[i], b[i]);
      if (res != 0) {
        return res;
      }
    }
    return 0;
  }
  return len1 - len2;
}

final RegExp _hex6 = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
final RegExp _hex8 = RegExp(r'^#[0-9a-f]{8}$', caseSensitive: false);
final RegExp _hex3 = RegExp(r'^#[0-9a-f]{3}$', caseSensitive: false);
final RegExp _hex4 = RegExp(r'^#[0-9a-f]{4}$', caseSensitive: false);

bool isValidHexColor(String hex) {
  if (_hex6.hasMatch(hex)) {
    // #rrggbb
    return true;
  }

  if (_hex8.hasMatch(hex)) {
    // #rrggbbaa
    return true;
  }

  if (_hex3.hasMatch(hex)) {
    // #rgb
    return true;
  }

  if (_hex4.hasMatch(hex)) {
    // #rgba
    return true;
  }

  return false;
}

final RegExp _regExpCharacters = RegExp(
  r'[\-\\\{\}\*\+\?\|\^\$\.\,\[\]\(\)\#\s]',
);

/// Escapes regular expression characters in a given string
String escapeRegExpCharacters(String value) {
  return value.replaceAllMapped(_regExpCharacters, (m) => '\\${m[0]}');
}

class CachedFn<TKey, TValue> {
  CachedFn(this._fn);

  final Map<TKey, TValue> _cache = <TKey, TValue>{};
  final TValue Function(TKey key) _fn;

  TValue get(TKey key) {
    final cached = _cache[key];
    if (cached != null || _cache.containsKey(key)) {
      return cached as TValue;
    }
    final value = _fn(key);
    _cache[key] = value;
    return value;
  }
}

final Stopwatch _clock = Stopwatch()..start();

/// `performance.now()`: milliseconds on a monotonic clock.
double performanceNow() => _clock.elapsedMicroseconds / 1000.0;

RegExp? _containsRtl;

RegExp _makeContainsRtl() {
  // Generated using https://github.com/alexdima/unicode-utils/blob/main/rtl-test.js
  return RegExp(
    r'(?:[\u05BE\u05C0\u05C3\u05C6\u05D0-\u05F4\u0608\u060B\u060D\u061B-\u064A\u066D-\u066F\u0671-\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u0710\u0712-\u072F\u074D-\u07A5\u07B1-\u07EA\u07F4\u07F5\u07FA\u07FE-\u0815\u081A\u0824\u0828\u0830-\u0858\u085E-\u088E\u08A0-\u08C9\u200F\uFB1D\uFB1F-\uFB28\uFB2A-\uFD3D\uFD50-\uFDC7\uFDF0-\uFDFC\uFE70-\uFEFC]|\uD802[\uDC00-\uDD1B\uDD20-\uDE00\uDE10-\uDE35\uDE40-\uDEE4\uDEEB-\uDF35\uDF40-\uDFFF]|\uD803[\uDC00-\uDD23\uDE80-\uDEA9\uDEAD-\uDF45\uDF51-\uDF81\uDF86-\uDFF6]|\uD83A[\uDC00-\uDCCF\uDD00-\uDD43\uDD4B-\uDFFF]|\uD83B[\uDC00-\uDEBB])',
  );
}

/// Returns true if `str` contains any Unicode character that is classified as "R" or "AL".
bool containsRTL(String str) {
  return (_containsRtl ??= _makeContainsRtl()).hasMatch(str);
}
