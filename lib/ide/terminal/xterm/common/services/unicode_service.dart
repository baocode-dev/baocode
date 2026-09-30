// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/services/UnicodeService.ts (c58ea36).

import '../event.dart';
import '../lifecycle.dart';
import 'services.dart';

class UnicodeService implements IUnicodeService, IDisposable {
  final Map<String, IUnicodeVersionProvider> _providers =
      <String, IUnicodeVersionProvider>{};
  String _active = '';
  late IUnicodeVersionProvider _activeProvider;

  final Emitter<String> _onChange = Emitter<String>();
  @override
  late final IEvent<String> onChange = _onChange.event;

  static bool extractShouldJoin(UnicodeCharProperties value) {
    return (value & 1) != 0;
  }

  static UnicodeCharWidth extractWidth(UnicodeCharProperties value) {
    return (value >> 1) & 0x3;
  }

  static int extractCharKind(UnicodeCharProperties value) {
    return value >> 3;
  }

  static UnicodeCharProperties createPropertyValue(
    int state,
    int width, [
    bool shouldJoin = false,
  ]) {
    return ((state & 0xffffff) << 3) |
        ((width & 3) << 1) |
        (shouldJoin ? 1 : 0);
  }

  @override
  void dispose() {
    _onChange.dispose();
  }

  @override
  List<String> get versions => _providers.keys.toList();

  @override
  String get activeVersion => _active;

  @override
  set activeVersion(String version) {
    final provider = _providers[version];
    if (provider == null) {
      throw ArgumentError('unknown Unicode version "$version"');
    }
    _active = version;
    _activeProvider = provider;
    _onChange.fire(version);
  }

  @override
  void register(IUnicodeVersionProvider provider) {
    _providers[provider.version] = provider;
    if (_active.isEmpty) {
      activeVersion = provider.version;
    }
  }

  /// Unicode version dependent interface.
  @override
  UnicodeCharWidth wcwidth(int codepoint) {
    return _activeProvider.wcwidth(codepoint);
  }

  @override
  int getStringCellWidth(String s) {
    var result = 0;
    var precedingInfo = 0;
    final length = s.length;
    for (var i = 0; i < length; ++i) {
      var code = s.codeUnitAt(i);
      // surrogate pair first
      if (0xD800 <= code && code <= 0xDBFF) {
        if (++i >= length) {
          // this should not happen with strings retrieved from
          // Buffer.translateToString as it converts from UTF-32
          // and therefore always should contain the second part
          // for any other string we still have to handle it somehow:
          // simply treat the lonely surrogate first as a single char (UCS-2
          // behavior)
          return result + wcwidth(code);
        }
        final second = s.codeUnitAt(i);
        // convert surrogate pair to high codepoint only for valid second part
        // (UTF-16) otherwise treat them independently (UCS-2 behavior)
        if (0xDC00 <= second && second <= 0xDFFF) {
          code = (code - 0xD800) * 0x400 + second - 0xDC00 + 0x10000;
        } else {
          result += wcwidth(second);
        }
      }
      final currentInfo = charProperties(code, precedingInfo);
      var chWidth = UnicodeService.extractWidth(currentInfo);
      if (UnicodeService.extractShouldJoin(currentInfo)) {
        chWidth -= UnicodeService.extractWidth(precedingInfo);
      }
      result += chWidth;
      precedingInfo = currentInfo;
    }
    return result;
  }

  @override
  UnicodeCharProperties charProperties(
    int codepoint,
    UnicodeCharProperties preceding,
  ) {
    return _activeProvider.charProperties(codepoint, preceding);
  }
}
