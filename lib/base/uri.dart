/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's URI, as the extension host marshals it.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/uri.ts.
//
// Deviations:
// - Whether paths are Windows paths is a parameter (`windows`), not the
//   platform this runs on: a project's host may be another machine.
// - No `_formatted`/`_fsPath` caches beyond what `toJson` round-trips.

import 'dart:convert';

const _empty = '';
const _slash = '/';
final _schemePattern = RegExp(r'^\w[\w\d+.-]*$');
final _regexp = RegExp(r'^(([^:/?#]+?):)?(\/\/([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?');

/// `MarshalledId.Uri`: how a URI is told apart in a JSON message.
const int uriMarshalledId = 1;

/// A VS Code URI: scheme, authority, path, query and fragment.
final class VsUri {
  VsUri._(this.scheme, this.authority, this.path, this.query, this.fragment);

  /// `new Uri(scheme, authority, path, query, fragment, strict)`.
  factory VsUri(
    String scheme, {
    String authority = _empty,
    String path = _empty,
    String query = _empty,
    String fragment = _empty,
    bool strict = false,
  }) {
    final fixedScheme = scheme.isEmpty && !strict ? 'file' : scheme;
    final uri = VsUri._(
      fixedScheme,
      authority,
      _referenceResolution(fixedScheme, path),
      query,
      fragment,
    );
    _validate(uri, strict);
    return uri;
  }

  final String scheme;
  final String authority;
  final String path;
  final String query;
  final String fragment;

  /// `URI.parse`.
  static VsUri parse(String value, {bool strict = false}) {
    final match = _regexp.firstMatch(value);
    if (match == null) return VsUri._(_empty, _empty, _empty, _empty, _empty);
    return VsUri(
      match.group(2) ?? _empty,
      authority: _percentDecode(match.group(4) ?? _empty),
      path: _percentDecode(match.group(5) ?? _empty),
      query: _percentDecode(match.group(7) ?? _empty),
      fragment: _percentDecode(match.group(9) ?? _empty),
      strict: strict,
    );
  }

  /// `URI.file`: [path] is a file system path, Windows' when [windows].
  static VsUri file(String path, {bool windows = false}) {
    var authority = _empty;
    if (windows) path = path.replaceAll(r'\', _slash);
    if (path.length > 1 && path[0] == _slash && path[1] == _slash) {
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
    return VsUri('file', authority: authority, path: path);
  }

  /// `URI.from`.
  static VsUri from(Map<String, Object?> components, {bool strict = false}) =>
      VsUri(
        components['scheme'] as String? ?? _empty,
        authority: components['authority'] as String? ?? _empty,
        path: components['path'] as String? ?? _empty,
        query: components['query'] as String? ?? _empty,
        fragment: components['fragment'] as String? ?? _empty,
        strict: strict,
      );

  /// `URI.revive`: the components as they are, unvalidated.
  static VsUri revive(Map<String, Object?> data) => VsUri._(
    data['scheme'] as String? ?? _empty,
    data['authority'] as String? ?? _empty,
    data['path'] as String? ?? _empty,
    data['query'] as String? ?? _empty,
    data['fragment'] as String? ?? _empty,
  );

  /// [revive] when [data] is URI components, else null.
  static VsUri? tryRevive(Object? data) {
    if (data is VsUri) return data;
    if (data is Map && data['scheme'] is String) {
      return revive(data.cast<String, Object?>());
    }
    return null;
  }

  /// `uri.with(...)`; pass [clear] names to set those parts to ''.
  VsUri replace({
    String? scheme,
    String? authority,
    String? path,
    String? query,
    String? fragment,
  }) {
    final s = scheme ?? this.scheme;
    final a = authority ?? this.authority;
    final p = path ?? this.path;
    final q = query ?? this.query;
    final f = fragment ?? this.fragment;
    if (s == this.scheme &&
        a == this.authority &&
        p == this.path &&
        q == this.query &&
        f == this.fragment) {
      return this;
    }
    return VsUri(s, authority: a, path: p, query: q, fragment: f);
  }

  /// `URI.joinPath` for posix paths.
  VsUri joinPath(List<String> fragments) {
    if (path.isEmpty) {
      throw StateError('[UriError]: cannot call joinPath on URI without path');
    }
    final parts = [path, ...fragments].join(_slash);
    return replace(path: _normalizePosix(parts));
  }

  /// `uri.fsPath`; Windows separators when [windows].
  String fsPath({bool windows = false, bool keepDriveLetterCasing = false}) {
    String value;
    if (authority.isNotEmpty && path.length > 1 && scheme == 'file') {
      value = '//$authority$path';
    } else if (path.length >= 3 &&
        path.codeUnitAt(0) == 0x2F &&
        _isAsciiLetter(path.codeUnitAt(1)) &&
        path.codeUnitAt(2) == 0x3A) {
      value = keepDriveLetterCasing
          ? path.substring(1)
          : path[1].toLowerCase() + path.substring(2);
    } else {
      value = path;
    }
    if (windows) value = value.replaceAll('/', r'\');
    return value;
  }

  /// `uri.toString(skipEncoding)`.
  @override
  String toString({bool skipEncoding = false}) => _asFormatted(skipEncoding);

  /// `Uri.toJSON()`: the marshalled form (`$mid: 1`).
  Map<String, Object?> toJson() => {
    r'$mid': uriMarshalledId,
    if (path.isNotEmpty) 'path': path,
    if (scheme.isNotEmpty) 'scheme': scheme,
    if (authority.isNotEmpty) 'authority': authority,
    if (query.isNotEmpty) 'query': query,
    if (fragment.isNotEmpty) 'fragment': fragment,
  };

  @override
  bool operator ==(Object other) =>
      other is VsUri &&
      other.scheme == scheme &&
      other.authority == authority &&
      other.path == path &&
      other.query == query &&
      other.fragment == fragment;

  @override
  int get hashCode => Object.hash(scheme, authority, path, query, fragment);

  String _asFormatted(bool skipEncoding) {
    String encoder(String s, bool isPath, bool isAuthority) => skipEncoding
        ? _encodeMinimal(s)
        : _encodeFast(s, isPath, isAuthority);
    final res = StringBuffer();
    var authority = this.authority;
    var path = this.path;
    if (scheme.isNotEmpty) {
      res
        ..write(scheme)
        ..write(':');
    }
    if (authority.isNotEmpty || scheme == 'file') {
      res.write('//');
    }
    if (authority.isNotEmpty) {
      var idx = authority.indexOf('@');
      if (idx != -1) {
        final userinfo = authority.substring(0, idx);
        authority = authority.substring(idx + 1);
        idx = userinfo.lastIndexOf(':');
        if (idx == -1) {
          res.write(encoder(userinfo, false, false));
        } else {
          res
            ..write(encoder(userinfo.substring(0, idx), false, false))
            ..write(':')
            ..write(encoder(userinfo.substring(idx + 1), false, true));
        }
        res.write('@');
      }
      authority = authority.toLowerCase();
      idx = authority.lastIndexOf(':');
      if (idx == -1) {
        res.write(encoder(authority, false, true));
      } else {
        res
          ..write(encoder(authority.substring(0, idx), false, true))
          ..write(authority.substring(idx));
      }
    }
    if (path.isNotEmpty) {
      if (path.length >= 3 &&
          path.codeUnitAt(0) == 0x2F &&
          path.codeUnitAt(2) == 0x3A) {
        final code = path.codeUnitAt(1);
        if (code >= 0x41 && code <= 0x5A) {
          path = '/${String.fromCharCode(code + 32)}:${path.substring(3)}';
        }
      } else if (path.length >= 2 && path.codeUnitAt(1) == 0x3A) {
        final code = path.codeUnitAt(0);
        if (code >= 0x41 && code <= 0x5A) {
          path = '${String.fromCharCode(code + 32)}:${path.substring(2)}';
        }
      }
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
        ..write(skipEncoding ? fragment : _encodeFast(fragment, false, false));
    }
    return res.toString();
  }
}

bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

void _validate(VsUri ret, bool strict) {
  if (ret.scheme.isEmpty && strict) {
    throw FormatException('[UriError]: Scheme is missing');
  }
  if (ret.scheme.isNotEmpty && !_schemePattern.hasMatch(ret.scheme)) {
    throw FormatException('[UriError]: Scheme contains illegal characters.');
  }
  if (ret.path.isNotEmpty) {
    if (ret.authority.isNotEmpty) {
      if (!ret.path.startsWith('/')) {
        throw const FormatException(
          '[UriError]: If a URI contains an authority component, then the path component must either be empty or begin with a slash ("/") character',
        );
      }
    } else if (ret.path.startsWith('//')) {
      throw const FormatException(
        '[UriError]: If a URI does not contain an authority component, then the path cannot begin with two slash characters ("//")',
      );
    }
  }
}

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

const _encodeTable = <int, String>{
  0x3A: '%3A', // :
  0x2F: '%2F', // /
  0x3F: '%3F', // ?
  0x23: '%23', // #
  0x5B: '%5B', // [
  0x5D: '%5D', // ]
  0x40: '%40', // @
  0x21: '%21', // !
  0x24: '%24', // $
  0x26: '%26', // &
  0x27: '%27', // '
  0x28: '%28', // (
  0x29: '%29', // )
  0x2A: '%2A', // *
  0x2B: '%2B', // +
  0x2C: '%2C', // ,
  0x3B: '%3B', // ;
  0x3D: '%3D', // =
  0x20: '%20', // space
};

/// JavaScript's `encodeURIComponent`.
String _encodeURIComponent(String s) => Uri.encodeComponent(s);

String _encodeFast(String uriComponent, bool isPath, bool isAuthority) {
  StringBuffer? res;
  var nativeEncodePos = -1;
  for (var pos = 0; pos < uriComponent.length; pos++) {
    final code = uriComponent.codeUnitAt(pos);
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
      if (nativeEncodePos != -1) {
        res!.write(
          _encodeURIComponent(uriComponent.substring(nativeEncodePos, pos)),
        );
        nativeEncodePos = -1;
      }
      res?.write(uriComponent[pos]);
    } else {
      res ??= StringBuffer(uriComponent.substring(0, pos));
      final escaped = _encodeTable[code];
      if (escaped != null) {
        if (nativeEncodePos != -1) {
          res.write(
            _encodeURIComponent(uriComponent.substring(nativeEncodePos, pos)),
          );
          nativeEncodePos = -1;
        }
        res.write(escaped);
      } else if (nativeEncodePos == -1) {
        nativeEncodePos = pos;
      }
    }
  }
  if (nativeEncodePos != -1) {
    res!.write(_encodeURIComponent(uriComponent.substring(nativeEncodePos)));
  }
  return res?.toString() ?? uriComponent;
}

String _encodeMinimal(String path) {
  StringBuffer? res;
  for (var pos = 0; pos < path.length; pos++) {
    final code = path.codeUnitAt(pos);
    if (code == 0x23 || code == 0x3F) {
      res ??= StringBuffer(path.substring(0, pos));
      res.write(_encodeTable[code]);
    } else {
      res?.write(path[pos]);
    }
  }
  return res?.toString() ?? path;
}

final _encodedAsHex = RegExp(r'(%[0-9A-Za-z][0-9A-Za-z])+');

String _decodeGraceful(String str) {
  try {
    return utf8.decode(
      [
        for (var i = 0; i < str.length; i += 3)
          int.parse(str.substring(i + 1, i + 3), radix: 16),
      ],
    );
  } on FormatException {
    if (str.length > 3) {
      return str.substring(0, 3) + _decodeGraceful(str.substring(3));
    }
    return str;
  }
}

String _percentDecode(String str) {
  if (!_encodedAsHex.hasMatch(str)) return str;
  return str.replaceAllMapped(_encodedAsHex, (m) => _decodeGraceful(m[0]!));
}

/// `paths.posix.join`'s normalization: `.`/`..` segments and duplicate
/// slashes resolved, a leading slash kept.
String _normalizePosix(String path) {
  if (path.isEmpty) return '.';
  final isAbsolute = path.startsWith('/');
  final trailingSlash = path.endsWith('/');
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else if (!isAbsolute) {
        out.add('..');
      }
    } else {
      out.add(segment);
    }
  }
  var result = out.join('/');
  if (result.isEmpty && !isAbsolute) result = '.';
  if (trailingSlash && result.isNotEmpty && result != '.') result += '/';
  return isAbsolute ? '/$result' : result;
}
