/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/uri.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: the `URI` class (`parse`,
// `file`, `from`, `with`, `fsPath`, `toString`), `uriToFsPath` and the
// percent encoding/decoding helpers. Not ported: `joinPath`, `revive`,
// `toJSON`, `isUri` and marshalling.
// Deviations: `with` is [URI.withComponents], where `null` keeps a component
// (upstream distinguishes `undefined` from `null`). Validation errors are
// [FormatException]s. [URI.fromUri] is a Dart adaptation: it builds the URI
// VS Code would hold for a Dart [Uri] from its decoded components, so
// `Uri.file(path)` maps to upstream `URI.file(path)` (a relative Dart file URI
// has no scheme and becomes a `file` URI with a leading slash, as upstream's
// scheme fix does). Dart's `Uri` has already removed `.`/`..` segments and
// lower-cased the scheme and host; VS Code keeps them.

import 'ecmascript_lower_case.dart';
import 'platform.dart';

final RegExp _schemePattern = RegExp(r'^\w[\w\d+.-]*$');
final RegExp _illegalSchemeCharacter = RegExp(r'[^\w\d+.-]');

void _validateUri(URI ret, bool strict) {
  // scheme, must be set
  if (ret.scheme.isEmpty && strict) {
    throw FormatException(
      '[UriError]: Scheme is missing: {scheme: "", authority: '
      '"${ret.authority}", path: "${ret.path}", query: "${ret.query}", '
      'fragment: "${ret.fragment}"}',
    );
  }

  // scheme, https://tools.ietf.org/html/rfc3986#section-3.1
  if (ret.scheme.isNotEmpty && !_schemePattern.hasMatch(ret.scheme)) {
    final matches = _illegalSchemeCharacter.allMatches(ret.scheme).toList();
    final detail = matches.isNotEmpty
        ? " Found '${matches[0][0]}' at index ${matches[0].start} "
              '(${matches.length} total)'
        : '';
    throw FormatException(
      '[UriError]: Scheme contains illegal characters.$detail '
      '(len:${ret.scheme.length})',
    );
  }

  // path, http://tools.ietf.org/html/rfc3986#section-3.3
  if (ret.path.isNotEmpty) {
    if (ret.authority.isNotEmpty) {
      if (!ret.path.startsWith('/')) {
        throw const FormatException(
          '[UriError]: If a URI contains an authority component, then the '
          'path component must either be empty or begin with a slash ("/") '
          'character',
        );
      }
    } else if (ret.path.startsWith('//')) {
      throw const FormatException(
        '[UriError]: If a URI does not contain an authority component, then '
        'the path cannot begin with two slash characters ("//")',
      );
    }
  }
}

// URIs without a scheme fall back to `file` unless strict.
String _schemeFix(String scheme, bool strict) =>
    scheme.isEmpty && !strict ? 'file' : scheme;

// Implements a bit of https://tools.ietf.org/html/rfc3986#section-5: the
// slash is the default base.
String _referenceResolution(String scheme, String path) {
  switch (scheme) {
    case 'https':
    case 'http':
    case 'file':
      if (path.isEmpty) {
        path = _slash;
      } else if (path[0] != _slash) {
        path = _slash + path;
      }
  }
  return path;
}

const String _slash = '/';
final RegExp _regexp = RegExp(
  r'^(([^:/?#]+?):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?',
);

/// Uniform Resource Identifier (RFC 3986) with decoded components.
class URI {
  URI._(
    String scheme, [
    this.authority = '',
    String path = '',
    this.query = '',
    this.fragment = '',
    bool strict = false,
  ]) : scheme = _schemeFix(scheme, strict),
       path = _referenceResolution(_schemeFix(scheme, strict), path) {
    _validateUri(this, strict);
  }

  /// The part before the first colon (`http`).
  final String scheme;

  /// The part between the double slashes and the next slash.
  final String authority;
  final String path;
  final String query;
  final String fragment;

  String? _formatted;
  String? _fsPath;

  /// Creates a URI from a string; components are percent-decoded.
  static URI parse(String value, [bool strict = false]) {
    final match = _regexp.firstMatch(value);
    if (match == null) return URI._('', '', '', '', '');
    return URI._(
      match[2] ?? '',
      percentDecode(match[4] ?? ''),
      percentDecode(match[5] ?? ''),
      percentDecode(match[7] ?? ''),
      percentDecode(match[9] ?? ''),
      strict,
    );
  }

  /// Creates a `file` URI from a file system path. On Windows backslashes
  /// become slashes; elsewhere they are file name characters.
  static URI file(String path) {
    var authority = '';
    if (isWindows) path = path.replaceAll('\\', _slash);
    // Check for authority as used in UNC shares.
    if (path.startsWith('//')) {
      final idx = path.indexOf(_slash, 2);
      if (idx == -1) {
        authority = path.substring(2);
        path = _slash;
      } else {
        authority = path.substring(2, idx);
        path = path.substring(idx);
        if (path.isEmpty) path = _slash;
      }
    }
    return URI._('file', authority, path, '', '');
  }

  static URI from({
    required String scheme,
    String? authority,
    String? path,
    String? query,
    String? fragment,
    bool strict = false,
  }) => URI._(
    scheme,
    authority ?? '',
    path ?? '',
    query ?? '',
    fragment ?? '',
    strict,
  );

  /// The VS Code URI for a Dart [uri] (see the file header).
  factory URI.fromUri(Uri uri) => URI._(
    uri.scheme,
    uri.hasAuthority ? percentDecode(uri.authority) : '',
    percentDecode(uri.path),
    uri.hasQuery ? percentDecode(uri.query) : '',
    uri.hasFragment ? percentDecode(uri.fragment) : '',
  );

  /// The platform-specific file system path; see [uriToFsPath].
  String get fsPath => _fsPath ??= uriToFsPath(this, false);

  /// Upstream `with`; `null` keeps a component.
  URI withComponents({
    String? scheme,
    String? authority,
    String? path,
    String? query,
    String? fragment,
  }) {
    scheme ??= this.scheme;
    authority ??= this.authority;
    path ??= this.path;
    query ??= this.query;
    fragment ??= this.fragment;
    if (scheme == this.scheme &&
        authority == this.authority &&
        path == this.path &&
        query == this.query &&
        fragment == this.fragment) {
      return this;
    }
    return URI._(scheme, authority, path, query, fragment);
  }

  /// The string form; with [skipEncoding] only `#` and `?` are encoded.
  @override
  String toString([bool skipEncoding = false]) {
    if (skipEncoding) return _asFormatted(this, true);
    return _formatted ??= _asFormatted(this, false);
  }
}

// Reserved characters: https://tools.ietf.org/html/rfc3986#section-2.2
const Map<int, String> _encodeTable = {
  0x3A: '%3A', // gen-delims
  0x2F: '%2F',
  0x3F: '%3F',
  0x23: '%23',
  0x5B: '%5B',
  0x5D: '%5D',
  0x40: '%40',
  0x21: '%21', // sub-delims
  0x24: '%24',
  0x26: '%26',
  0x27: '%27',
  0x28: '%28',
  0x29: '%29',
  0x2A: '%2A',
  0x2B: '%2B',
  0x2C: '%2C',
  0x3B: '%3B',
  0x3D: '%3D',
  0x20: '%20',
};

String _encodeURIComponentFast(
  String uriComponent,
  bool isPath,
  bool isAuthority,
) {
  StringBuffer? res;
  var nativeEncodePos = -1;
  for (var pos = 0; pos < uriComponent.length; pos++) {
    final code = uriComponent.codeUnitAt(pos);
    // Unreserved characters: https://tools.ietf.org/html/rfc3986#section-2.3
    if ((code >= 0x61 && code <= 0x7A) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x30 && code <= 0x39) ||
        code == 0x2D ||
        code == 0x2E ||
        code == 0x5F ||
        code == 0x7E ||
        (isPath && code == 0x2F) ||
        (isAuthority && code == 0x5B) ||
        (isAuthority && code == 0x5D) ||
        (isAuthority && code == 0x3A)) {
      // Check if we are delaying native encode.
      if (nativeEncodePos != -1) {
        res!.write(
          Uri.encodeComponent(uriComponent.substring(nativeEncodePos, pos)),
        );
        nativeEncodePos = -1;
      }
      // Only write into a new string once one is needed.
      res?.writeCharCode(code);
    } else {
      // Encoding needed: allocate a new string.
      res ??= StringBuffer(uriComponent.substring(0, pos));
      // Check with the default table first.
      final escaped = _encodeTable[code];
      if (escaped != null) {
        if (nativeEncodePos != -1) {
          res.write(
            Uri.encodeComponent(uriComponent.substring(nativeEncodePos, pos)),
          );
          nativeEncodePos = -1;
        }
        res.write(escaped);
      } else if (nativeEncodePos == -1) {
        // Use native encoding only when needed.
        nativeEncodePos = pos;
      }
    }
  }
  if (nativeEncodePos != -1) {
    res!.write(Uri.encodeComponent(uriComponent.substring(nativeEncodePos)));
  }
  return res != null ? res.toString() : uriComponent;
}

String _encodeURIComponentMinimal(String path) {
  var pos = path.indexOf('?');
  final hashPos = path.indexOf('#');
  if (pos == -1 || (hashPos != -1 && hashPos < pos)) pos = hashPos;
  if (pos == -1) return path;
  final res = StringBuffer(path.substring(0, pos));
  var copyStart = pos;
  for (; pos < path.length; pos++) {
    final code = path.codeUnitAt(pos);
    if (code == 0x23 || code == 0x3F) {
      if (copyStart < pos) res.write(path.substring(copyStart, pos));
      res.write(_encodeTable[code]);
      copyStart = pos + 1;
    }
  }
  if (copyStart < path.length) res.write(path.substring(copyStart));
  return res.toString();
}

/// Computes `fsPath` for [uri]; without [keepDriveLetterCasing] a Windows
/// drive letter is lower-cased. On Windows, slashes become backslashes.
String uriToFsPath(URI uri, bool keepDriveLetterCasing) {
  String value;
  final path = uri.path;
  if (uri.authority.isNotEmpty && path.length > 1 && uri.scheme == 'file') {
    // UNC path: file://shares/c$/far/boo
    value = '//${uri.authority}$path';
  } else if (path.length >= 3 &&
      path.codeUnitAt(0) == 0x2F &&
      _isAsciiLetter(path.codeUnitAt(1)) &&
      path.codeUnitAt(2) == 0x3A) {
    // Windows drive letter: file:///c:/far/boo
    value = keepDriveLetterCasing
        ? path.substring(1)
        : jsToLowerCase(path[1]) + path.substring(2);
  } else {
    // Other path.
    value = path;
  }
  if (isWindows) value = value.replaceAll('/', '\\');
  return value;
}

bool _isAsciiLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

String _asFormatted(URI uri, bool skipEncoding) {
  final encoder = !skipEncoding
      ? _encodeURIComponentFast
      : (String s, bool isPath, bool isAuthority) =>
            _encodeURIComponentMinimal(s);
  final res = StringBuffer();
  final scheme = uri.scheme;
  var authority = uri.authority;
  var path = uri.path;
  final query = uri.query, fragment = uri.fragment;
  if (scheme.isNotEmpty) {
    res
      ..write(scheme)
      ..write(':');
  }
  if (authority.isNotEmpty || scheme == 'file') {
    res
      ..write(_slash)
      ..write(_slash);
  }
  if (authority.isNotEmpty) {
    var idx = authority.indexOf('@');
    if (idx != -1) {
      // <user>@<auth>
      final userinfo = authority.substring(0, idx);
      authority = authority.substring(idx + 1);
      idx = userinfo.lastIndexOf(':');
      if (idx == -1) {
        res.write(encoder(userinfo, false, false));
      } else {
        // <user>:<pass>@<auth>
        res
          ..write(encoder(userinfo.substring(0, idx), false, false))
          ..write(':')
          ..write(encoder(userinfo.substring(idx + 1), false, true));
      }
      res.write('@');
    }
    authority = jsToLowerCase(authority);
    idx = authority.lastIndexOf(':');
    if (idx == -1) {
      res.write(encoder(authority, false, true));
    } else {
      // <auth>:<port>
      res
        ..write(encoder(authority.substring(0, idx), false, true))
        ..write(authority.substring(idx));
    }
  }
  if (path.isNotEmpty) {
    // HTTP paths are case-sensitive, even when their first segment resembles
    // a drive letter.
    final lowerScheme = jsToLowerCase(scheme);
    final isHttp = lowerScheme == 'http' || lowerScheme == 'https';
    if (path.length >= 3 &&
        path.codeUnitAt(0) == 0x2F &&
        path.codeUnitAt(2) == 0x3A) {
      final code = path.codeUnitAt(1);
      if (code >= 0x41 && code <= 0x5A && !isHttp) {
        path = '/${String.fromCharCode(code + 32)}:${path.substring(3)}';
      }
    } else if (path.length >= 2 && path.codeUnitAt(1) == 0x3A) {
      final code = path.codeUnitAt(0);
      if (code >= 0x41 && code <= 0x5A && !isHttp) {
        path = '${String.fromCharCode(code + 32)}:${path.substring(2)}';
      }
    }
    // Encode the rest of the path.
    res.write(encoder(path, true, false));
  }
  if (query.isNotEmpty) {
    res
      ..write('?')
      ..write(encoder(query, false, false));
  }
  if (fragment.isNotEmpty) {
    res
      ..write('#')
      ..write(
        !skipEncoding
            ? _encodeURIComponentFast(fragment, false, false)
            : fragment,
      );
  }
  return res.toString();
}

// --- decode

/// JavaScript `decodeURIComponent` for a run of `%XX` escapes; `null` where
/// JavaScript throws a URIError.
String? _decodeEscapes(String str) {
  final bytes = <int>[];
  for (var i = 0; i < str.length; i += 3) {
    final byte = int.tryParse(str.substring(i + 1, i + 3), radix: 16);
    if (byte == null) return null;
    bytes.add(byte);
  }
  final out = StringBuffer();
  for (var i = 0; i < bytes.length;) {
    final b = bytes[i];
    if (b < 0x80) {
      out.writeCharCode(b);
      i++;
      continue;
    }
    final n = b >= 0xF0 && b < 0xF8
        ? 4
        : b >= 0xE0 && b < 0xF0
        ? 3
        : b >= 0xC0 && b < 0xE0
        ? 2
        : 0;
    if (n == 0 || i + n > bytes.length) return null;
    var value = b & (0xFF >> (n + 1));
    for (var k = 1; k < n; k++) {
      final c = bytes[i + k];
      if (c & 0xC0 != 0x80) return null;
      value = (value << 6) | (c & 0x3F);
    }
    const minimum = [0, 0, 0x80, 0x800, 0x10000];
    if (value < minimum[n] ||
        value > 0x10FFFF ||
        (value >= 0xD800 && value <= 0xDFFF)) {
      return null;
    }
    out.writeCharCode(value);
    i += n;
  }
  return out.toString();
}

String _decodeURIComponentGraceful(String str) {
  final decoded = _decodeEscapes(str);
  if (decoded != null) return decoded;
  if (str.length > 3) {
    return str.substring(0, 3) + _decodeURIComponentGraceful(str.substring(3));
  }
  return str;
}

final RegExp _rEncodedAsHex = RegExp(r'(%[0-9A-Za-z][0-9A-Za-z])+');

/// Decodes `%XX` sequences, keeping those that are not valid UTF-8.
String percentDecode(String str) {
  if (!_rEncodedAsHex.hasMatch(str)) return str;
  return str.replaceAllMapped(
    _rEncodedAsHex,
    (match) => _decodeURIComponentGraceful(match[0]!),
  );
}
