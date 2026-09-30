/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/base/common/mime.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. `Mimes` is a class of constants;
// `extname` is platform-selected as upstream. Lower-casing uses
// [jsToLowerCase].

import 'ecmascript_lower_case.dart';
import 'path.dart';

/// Upstream `Mimes`.
abstract final class Mimes {
  static const String text = 'text/plain';
  static const String binary = 'application/octet-stream';
  static const String unknown = 'application/unknown';
  static const String markdown = 'text/markdown';
  static const String latex = 'text/latex';
  static const String uriList = 'text/uri-list';
  static const String html = 'text/html';
}

const Map<String, String> _mapExtToTextMimes = {
  '.css': 'text/css',
  '.csv': 'text/csv',
  '.htm': 'text/html',
  '.html': 'text/html',
  '.ics': 'text/calendar',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.txt': 'text/plain',
  '.xml': 'text/xml',
};

// Known media mimes that we can handle (a `String` or a `List<String>`).
const Map<String, Object> _mapExtToMediaMimes = {
  '.aac': 'audio/x-aac',
  '.avi': 'video/x-msvideo',
  '.avif': 'image/avif',
  '.bmp': 'image/bmp',
  '.flv': 'video/x-flv',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.jpe': ['image/jpg', 'image/jpeg'],
  '.jpeg': ['image/jpg', 'image/jpeg'],
  '.jpg': ['image/jpg', 'image/jpeg'],
  '.m1v': 'video/mpeg',
  '.m2a': 'audio/mpeg',
  '.m2v': 'video/mpeg',
  '.m3a': 'audio/mpeg',
  '.mid': 'audio/midi',
  '.midi': 'audio/midi',
  '.mk3d': 'video/x-matroska',
  '.mks': 'video/x-matroska',
  '.mkv': 'video/x-matroska',
  '.mov': 'video/quicktime',
  '.movie': 'video/x-sgi-movie',
  '.mp2': 'audio/mpeg',
  '.mp2a': 'audio/mpeg',
  '.mp3': 'audio/mpeg',
  '.mp4': 'video/mp4',
  '.mp4a': 'audio/mp4',
  '.mp4v': 'video/mp4',
  '.mpe': 'video/mpeg',
  '.mpeg': 'video/mpeg',
  '.mpg': 'video/mpeg',
  '.mpg4': 'video/mp4',
  '.mpga': 'audio/mpeg',
  '.oga': 'audio/ogg',
  '.ogg': 'audio/ogg',
  '.opus': 'audio/opus',
  '.ogv': 'video/ogg',
  '.png': 'image/png',
  '.psd': 'image/vnd.adobe.photoshop',
  '.qt': 'video/quicktime',
  '.spx': 'audio/ogg',
  '.svg': 'image/svg+xml',
  '.tga': 'image/x-tga',
  '.tif': 'image/tiff',
  '.tiff': 'image/tiff',
  '.wav': 'audio/x-wav',
  '.webm': 'video/webm',
  '.webp': 'image/webp',
  '.wma': 'audio/x-ms-wma',
  '.wmv': 'video/x-ms-wmv',
  '.woff': 'application/font-woff',
};

String? getMediaOrTextMime(String path) {
  final ext = extname(path);
  final textMime = _mapExtToTextMimes[jsToLowerCase(ext)];
  if (textMime != null) return textMime;
  return getMediaMime(path);
}

String? getMediaMime(String path) {
  final ext = extname(path);
  final mimeType = _mapExtToMediaMimes[jsToLowerCase(ext)];
  return mimeType is List<String> ? mimeType.first : mimeType as String?;
}

String? getExtensionForMimeType(String mimeType) {
  for (final mapping in <Map<String, Object>>[
    _mapExtToTextMimes,
    _mapExtToMediaMimes,
  ]) {
    for (final MapEntry(key: extension, :value) in mapping.entries) {
      if (value is List<String>
          ? value.contains(mimeType)
          : value == mimeType) {
        return extension;
      }
    }
  }
  return null;
}

final RegExp _simplePattern = RegExp(r'^(.+)\/(.+?)(;.+)?$');

/// Lower-cases the media type and subtype (RFC 2045 section 5.1). Without
/// [strict], a string that is not a mime type is returned unchanged; with it,
/// `null` is returned.
String? normalizeMimeType(String mimeType, {bool strict = false}) {
  final match = _simplePattern.firstMatch(mimeType);
  if (match == null) return strict ? null : mimeType;
  return '${jsToLowerCase(match[1]!)}/${jsToLowerCase(match[2]!)}'
      '${match[3] ?? ''}';
}

/// Whether [mimeType] is a text stream like `stdout` or `stderr`.
bool isTextStreamMime(String mimeType) => const [
  'application/vnd.code.notebook.stdout',
  'application/vnd.code.notebook.stderr',
].contains(mimeType);
