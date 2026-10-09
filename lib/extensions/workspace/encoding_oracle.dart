/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Which encoding a file is read and written with (`workspace.decode`,
// `workspace.encode`, `openTextDocument(uri, {encoding})`): an override
// for settings files, the encoding asked for or detected, else
// `files.encoding`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/textfile/browser/textFileService.ts
// (`resolveDecoding`, `validateDetectedEncoding`, `resolveEncoding`,
// `EncodingOracle`), src/vs/workbench/services/textfile/common/
// encoding.ts (`SUPPORTED_ENCODINGS`' keys, `UTF8`, `UTF8_with_bom`,
// `UTF16be`, `UTF16le`).
//
// Deviations: an encoding exists when it is one of VS Code's supported
// encodings (iconv-lite knows more aliases); no override for the untitled
// workspaces folder.

import 'package:bao_exthost/bao_exthost.dart';

import '../configuration/configuration_service.dart';
import '../files/file_service.dart' show uriIsEqualOrParent;
import 'workspace_context.dart';

const utf8Encoding = 'utf8';
const utf8WithBom = 'utf8bom';
const utf16be = 'utf16be';
const utf16le = 'utf16le';

/// `SUPPORTED_ENCODINGS`' keys.
const supportedEncodings = {
  'utf8', 'utf8bom', 'utf16le', 'utf16be', 'windows1252', 'iso88591', //
  'iso88593', 'iso885915', 'macroman', 'cp437', 'windows1256', 'iso88596',
  'windows1257', 'iso88594', 'iso885914', 'windows1250', 'iso88592', 'cp852',
  'windows1251', 'cp866', 'cp1125', 'iso88595', 'koi8r', 'koi8u', 'iso885913',
  'windows1253', 'iso88597', 'windows1255', 'iso88598', 'iso885910',
  'iso885916', 'windows1254', 'iso88599', 'cp857', 'windows1258', 'gbk',
  'gb18030', 'cp950', 'big5hkscs', 'shiftjis', 'eucjp', 'euckr', 'windows874',
  'iso885911', 'koi8ru', 'koi8t', 'gb2312', 'cp865', 'cp850',
};

/// `encodingExists`, by VS Code's names (`-` and `_` ignored).
bool encodingExists(String encoding) => supportedEncodings.contains(
  encoding.toLowerCase().replaceAll(RegExp('[-_ ]'), ''),
);

final class EncodingOracle {
  EncodingOracle({
    required this.configuration,
    required this.workspace,
    this.userSettingsHome,
  });

  final ConfigurationService configuration;
  final WorkspaceContextService workspace;

  /// The user's settings folder (always UTF-8).
  final VsUri? userSettingsHome;

  Object? _get(VsUri? resource, String key) =>
      configuration.getValue(key, resource: resource);

  /// `resolveDecoding`.
  Map<String, Object?> resolveDecoding(
    VsUri? resource,
    Map<String, Object?>? options,
  ) => {
    'preferredEncoding': preferredReadEncoding(resource, options, null).encoding,
    'guessEncoding':
        options?['autoGuessEncoding'] == true ||
        _get(resource, 'files.autoGuessEncoding') == true,
    'candidateGuessEncodings':
        options?['candidateGuessEncodings'] ??
        _get(resource, 'files.candidateGuessEncodings') ??
        const <String>[],
  };

  /// `validateDetectedEncoding`.
  String validateDetectedEncoding(
    VsUri? resource,
    String detectedEncoding,
    Map<String, Object?>? options,
  ) => preferredReadEncoding(resource, options, detectedEncoding).encoding;

  /// `resolveEncoding`: the write encoding and whether to add a BOM.
  Map<String, Object?> resolveEncoding(
    VsUri? resource,
    Map<String, Object?>? options,
  ) {
    final encoding = _validated(resource, options?['encoding'] as String?);
    return {'encoding': encoding, 'addBOM': _hasBom(encoding)};
  }

  /// `getPreferredReadEncoding`.
  ({String encoding, bool hasBom}) preferredReadEncoding(
    VsUri? resource,
    Map<String, Object?>? options,
    String? detectedEncoding,
  ) {
    String? preferred;
    final asked = options?['encoding'] as String?;
    if (asked != null && asked.isNotEmpty) {
      preferred = detectedEncoding == utf8WithBom && asked == utf8Encoding
          ? utf8WithBom
          : asked;
    } else if (detectedEncoding != null) {
      preferred = detectedEncoding;
    } else if (_get(resource, 'files.encoding') == utf8WithBom) {
      preferred = utf8Encoding;
    }
    final encoding = _validated(resource, preferred);
    return (encoding: encoding, hasBom: _hasBom(encoding));
  }

  static bool _hasBom(String encoding) =>
      encoding == utf16be || encoding == utf16le || encoding == utf8WithBom;

  String _validated(VsUri? resource, String? preferred) {
    var encoding = _override(resource) ??
        preferred ??
        (_get(resource, 'files.encoding') as String?) ??
        utf8Encoding;
    if (encoding.isEmpty) encoding = utf8Encoding;
    if (encoding != utf8Encoding && !encodingExists(encoding)) {
      encoding = utf8Encoding;
    }
    return encoding;
  }

  /// `getEncodingOverride`: settings files are UTF-8.
  String? _override(VsUri? resource) {
    if (resource == null) return null;
    final home = userSettingsHome;
    if (home != null && uriIsEqualOrParent(resource, home)) return utf8Encoding;
    if (resource.path.endsWith('.code-workspace')) return utf8Encoding;
    for (final folder in workspace.workspaceFolders) {
      if (uriIsEqualOrParent(resource, folder.uri.joinPath(['.vscode']))) {
        return utf8Encoding;
      }
    }
    return null;
  }
}
