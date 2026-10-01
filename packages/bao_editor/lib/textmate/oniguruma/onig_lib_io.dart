// vscode-oniguruma's OnigScanner and OnigString over native/oniguruma
// (onig_native.dart). Strings are UTF-16 here and UTF-8 to Oniguruma: an
// OnigString keeps its UTF-8 in native memory for its lifetime, with the
// offset maps both ways when the two differ, and the scanner converts the
// start position in and the capture offsets out.
//
// Adapted from vscode-oniguruma 1.7.0
// (716aeaa229e4ae2e3b0057377b55743e9a3e995b): src/index.ts (MIT, see
// native/oniguruma/LICENSE.txt).

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import '../vscode_textmate/onig_lib.dart';
import 'onig_lib.dart' show OnigError;
import 'onig_native.dart';

final IOnigLib? _loaded = () {
  try {
    onigVersion();
    return const NativeOnigLib();
  } on ArgumentError {
    // The native asset is missing: not built for this platform.
    return null;
  }
}();

IOnigLib? loadNativeOnigLib() => _loaded;

/// Oniguruma through dart:ffi, as vscode-oniguruma's `createOnigScanner` and
/// `createOnigString` give it.
final class NativeOnigLib implements IOnigLib {
  const NativeOnigLib({this.strict = false});

  /// Whether an invalid pattern throws an [OnigError], as vscode-oniguruma's
  /// source means it to. VS Code's vscode-oniguruma makes a scanner all the
  /// same (see [NativeOnigScanner.error]), and so does this by default.
  final bool strict;

  @override
  NativeOnigScanner createOnigScanner(List<String> sources) =>
      NativeOnigScanner(sources, strict: strict);

  @override
  NativeOnigString createOnigString(String str) => NativeOnigString(str);
}

final _free = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(onigFree),
);

final _freeScanner = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
    onigScannerFree,
  ),
);

Pointer<Uint8> _allocate(int bytes) {
  final pointer = onigMalloc(bytes);
  if (pointer == nullptr) throw OutOfMemoryError();
  return pointer.cast();
}

/// A string to search, in UTF-8 in native memory until [dispose] (or, as a
/// safety net, until it is garbage collected).
final class NativeOnigString implements OnigString, Finalizable {
  factory NativeOnigString(String content) {
    final utf16Length = content.length;
    final utf8Length = _utf8ByteLength(content);
    final data = _allocate(utf8Length);
    final bytes = data.asTypedList(utf8Length);
    if (utf8Length == utf16Length) {
      // ASCII: the offsets are the same both ways.
      for (var i = 0; i < utf16Length; i++) {
        bytes[i] = content.codeUnitAt(i);
      }
      return NativeOnigString._(content, data, utf8Length, null, null);
    }
    final utf16OffsetToUtf8 = Uint32List(utf16Length + 1)
      ..[utf16Length] = utf8Length;
    final utf8OffsetToUtf16 = Uint32List(utf8Length + 1)
      ..[utf8Length] = utf16Length;
    _encode(content, bytes, 0, utf16OffsetToUtf8, utf8OffsetToUtf16);
    return NativeOnigString._(
      content,
      data,
      utf8Length,
      utf16OffsetToUtf8,
      utf8OffsetToUtf16,
    );
  }

  NativeOnigString._(
    this.content,
    this._data,
    this._utf8Length,
    this._utf16OffsetToUtf8,
    this._utf8OffsetToUtf16,
  ) {
    _free.attach(this, _data.cast(), detach: this, externalSize: _utf8Length);
  }

  @override
  final String content;

  /// Names this string to the scanners' per-regex search caches.
  final int _id = onigNextStringId();

  Pointer<Uint8> _data;
  final int _utf8Length;
  final Uint32List? _utf16OffsetToUtf8;
  final Uint32List? _utf8OffsetToUtf16;

  bool get disposed => _data == nullptr;

  int _convertUtf16OffsetToUtf8(int utf16Offset) {
    final map = _utf16OffsetToUtf8;
    if (map == null) return utf16Offset;
    if (utf16Offset < 0) return 0;
    if (utf16Offset > content.length) return _utf8Length;
    return map[utf16Offset];
  }

  int _convertUtf8OffsetToUtf16(int utf8Offset) {
    final map = _utf8OffsetToUtf16;
    if (map == null) return utf8Offset;
    if (utf8Offset < 0) return 0;
    if (utf8Offset > _utf8Length) return content.length;
    return map[utf8Offset];
  }

  @override
  void dispose() {
    final data = _data;
    if (data == nullptr) return;
    _data = nullptr;
    _free.detach(this);
    onigFree(data.cast());
  }
}

/// Finds the earliest match of any of its patterns, as vscode-oniguruma's
/// `OnigScanner` does; its compiled patterns live in native memory until
/// [dispose] (or, as a safety net, until it is garbage collected).
final class NativeOnigScanner implements OnigScanner, Finalizable {
  /// With [strict], throws an [OnigError] for the first invalid pattern.
  /// Otherwise the scanner is made all the same, as VS Code's
  /// vscode-oniguruma makes it (native/oniguruma/bao_onig.c has the
  /// details): an invalid pattern never matches, and with valid ones beside
  /// it, nothing matches in a string under 1000 UTF-8 bytes.
  factory NativeOnigScanner(List<String> sources, {bool strict = false}) {
    final count = sources.length;
    final lengths = Int32List(count);
    var total = 0;
    for (var i = 0; i < count; i++) {
      total += lengths[i] = _utf8ByteLength(sources[i]);
    }
    final patterns = _allocate(total);
    final patternLengths = _allocate(count * sizeOf<Int32>()).cast<Int32>();
    final invalid = _allocate(sizeOf<Int32>()).cast<Int32>();
    final error = _allocate(onigErrorLength)..value = 0;
    try {
      final bytes = patterns.asTypedList(total);
      var offset = 0;
      for (var i = 0; i < count; i++) {
        _encode(sources[i], bytes, offset, null, null);
        offset += lengths[i];
      }
      patternLengths.asTypedList(count).setAll(0, lengths);
      final scanner = onigScannerNew(
        patterns,
        patternLengths,
        count,
        invalid,
        error,
      );
      if (scanner == nullptr) throw OutOfMemoryError();
      OnigError? onigError;
      if (invalid.value >= 0) {
        final message = error.asTypedList(onigErrorLength);
        final end = message.indexOf(0);
        onigError = OnigError(
          utf8.decode(
            message.sublist(0, end < 0 ? onigErrorLength : end),
            allowMalformed: true,
          ),
          pattern: sources[invalid.value],
        );
        if (strict) {
          onigScannerFree(scanner.cast());
          throw onigError;
        }
      }
      // A guess at the compiled patterns' size, for the garbage collector.
      return NativeOnigScanner._(
        scanner,
        onigError,
        externalSize: 512 * count + total,
      );
    } finally {
      onigFree(patterns.cast());
      onigFree(patternLengths.cast());
      onigFree(invalid.cast());
      onigFree(error.cast());
    }
  }

  NativeOnigScanner._(this._scanner, this.error, {required int externalSize})
    : _result = onigScannerResult(_scanner)
          .asTypedList(1 + 2 * onigScannerCapacity(_scanner)) {
    _freeScanner.attach(
      this,
      _scanner.cast(),
      detach: this,
      externalSize: externalSize,
    );
  }

  Pointer<OnigScannerHandle> _scanner;

  /// Oniguruma's error for the first invalid pattern, if any.
  final OnigError? error;

  /// The native result the scanner writes each match to: the register count,
  /// then each register's UTF-8 start and end.
  Uint32List _result;

  bool get disposed => _scanner == nullptr;

  @override
  IOnigMatch? findNextMatchSync(
    OnigString string,
    int startPosition,
    int options,
  ) {
    final scanner = _scanner;
    if (scanner == nullptr) {
      throw StateError('The OnigScanner has been disposed');
    }
    if (string is! NativeOnigString) {
      // vscode-oniguruma's findNextMatchSync on a plain string.
      final native = NativeOnigString(string.content);
      try {
        return findNextMatchSync(native, startPosition, options);
      } finally {
        native.dispose();
      }
    }
    final data = string._data;
    if (data == nullptr) {
      throw StateError('The OnigString has been disposed');
    }
    final index = onigFindNext(
      scanner,
      string._id,
      data,
      string._utf8Length,
      string._convertUtf16OffsetToUtf8(startPosition),
      options,
    );
    if (index < 0) return null;
    final result = _result;
    return IOnigMatch(
      index,
      List.generate(result[0], (i) {
        final start = string._convertUtf8OffsetToUtf16(result[2 * i + 1]);
        final end = string._convertUtf8OffsetToUtf16(result[2 * i + 2]);
        return IOnigCaptureIndex(start, end, end - start);
      }, growable: false),
    );
  }

  @override
  void dispose() {
    final scanner = _scanner;
    if (scanner == nullptr) return;
    _scanner = nullptr;
    _result = Uint32List(0);
    _freeScanner.detach(this);
    onigScannerFree(scanner.cast());
  }
}

/// vscode-oniguruma's `UtfString._utf8ByteLength`: a surrogate pair takes
/// four bytes, and a lone surrogate three, as if it were a character.
int _utf8ByteLength(String str) {
  var result = 0;
  final length = str.length;
  for (var i = 0; i < length; i++) {
    final charCode = str.codeUnitAt(i);
    if (charCode <= 0x7f) {
      result += 1;
    } else if (charCode <= 0x7ff) {
      result += 2;
    } else if (charCode >= 0xd800 &&
        charCode <= 0xdbff &&
        i + 1 < length &&
        _isLowSurrogate(str.codeUnitAt(i + 1))) {
      result += 4;
      i++;
    } else {
      result += 3;
    }
  }
  return result;
}

bool _isLowSurrogate(int charCode) => charCode >= 0xdc00 && charCode <= 0xdfff;

/// vscode-oniguruma's `UtfString`: [str] in UTF-8 into [out] from [offset],
/// a lone surrogate encoded as if it were a character; and, when given, the
/// offset maps. Both halves of a surrogate pair map to its first byte, and
/// every byte of a character to its first code unit.
void _encode(
  String str,
  Uint8List out,
  int offset,
  Uint32List? utf16OffsetToUtf8,
  Uint32List? utf8OffsetToUtf16,
) {
  final utf16Length = str.length;
  var i8 = offset;
  for (var i16 = 0; i16 < utf16Length; i16++) {
    final charCode = str.codeUnitAt(i16);

    var codePoint = charCode;
    var wasSurrogatePair = false;

    if (charCode >= 0xd800 && charCode <= 0xdbff) {
      // Hit a high surrogate, try to look for a matching low surrogate
      if (i16 + 1 < utf16Length) {
        final nextCharCode = str.codeUnitAt(i16 + 1);
        if (_isLowSurrogate(nextCharCode)) {
          // Found the matching low surrogate
          codePoint =
              (((charCode - 0xd800) << 10) + 0x10000) | (nextCharCode - 0xdc00);
          wasSurrogatePair = true;
        }
      }
    }

    if (utf16OffsetToUtf8 != null && utf8OffsetToUtf16 != null) {
      utf16OffsetToUtf8[i16] = i8;
      if (wasSurrogatePair) {
        utf16OffsetToUtf8[i16 + 1] = i8;
      }

      utf8OffsetToUtf16[i8] = i16;
      if (codePoint > 0x7f) {
        utf8OffsetToUtf16[i8 + 1] = i16;
        if (codePoint > 0x7ff) {
          utf8OffsetToUtf16[i8 + 2] = i16;
          if (codePoint > 0xffff) {
            utf8OffsetToUtf16[i8 + 3] = i16;
          }
        }
      }
    }

    if (codePoint <= 0x7f) {
      out[i8++] = codePoint;
    } else if (codePoint <= 0x7ff) {
      out[i8++] = 0xc0 | (codePoint >> 6);
      out[i8++] = 0x80 | (codePoint & 0x3f);
    } else if (codePoint <= 0xffff) {
      out[i8++] = 0xe0 | (codePoint >> 12);
      out[i8++] = 0x80 | ((codePoint >> 6) & 0x3f);
      out[i8++] = 0x80 | (codePoint & 0x3f);
    } else {
      out[i8++] = 0xf0 | (codePoint >> 18);
      out[i8++] = 0x80 | ((codePoint >> 12) & 0x3f);
      out[i8++] = 0x80 | ((codePoint >> 6) & 0x3f);
      out[i8++] = 0x80 | (codePoint & 0x3f);
    }

    if (wasSurrogatePair) {
      i16++;
    }
  }
}
