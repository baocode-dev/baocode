/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A DAP source and the URI it is opened by: a file, or a `debug:` URI
// whose content the adapter gives (`source` request).
//
//       debug:arbitrary_path?session=123e4567-e89b-12d3-a456-426655440000&ref=1016
//       \___/ \____________/ \__________________________________________/ \______/
//         |          |                             |                          |
//      scheme   source.path                    session id            source.reference
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debugSource.ts.
//
// Deviations: URIs are not made canonical (no `IUriIdentityService`);
// opening one in an editor is the host's (`DebugServiceHost.openSource`).

import '../../base/uri.dart' show VsUri;

import 'debug_types.dart';
import 'debug_utils.dart';

/// `DEBUG_SCHEME`.
const debugScheme = 'debug';

/// `UNKNOWN_SOURCE_LABEL`.
const unknownSourceLabel = 'Unknown Source';

class Source {
  Source(Json? raw, String sessionId) {
    String path;
    if (raw != null) {
      this.raw = raw;
      path = raw.str('path') ?? raw.str('name') ?? '';
      available = true;
    } else {
      this.raw = {'name': unknownSourceLabel};
      available = false;
      path = '$debugScheme:$unknownSourceLabel';
    }
    uri = getUriFromSource(this.raw, path, sessionId);
  }

  late final VsUri uri;
  late bool available;
  late Json raw;

  String get name => raw.str('name') ?? basenameOrAuthority(uri);
  String? get origin => raw.str('origin');
  String? get presentationHint => raw.str('presentationHint');
  int? get reference => raw.integer('sourceReference');
  bool get inMemory => uri.scheme == debugScheme;

  /// `Source.getEncodedDebugData`: what a URI says of the source it is.
  static ({String name, String path, String? sessionId, int? sourceReference})
  getEncodedDebugData(VsUri modelUri, {bool windows = false}) {
    String path;
    int? sourceReference;
    String? sessionId;
    switch (modelUri.scheme) {
      case 'file':
        path = modelUri.fsPath(windows: windows);
      case debugScheme:
        path = modelUri.path;
        if (modelUri.query.isNotEmpty) {
          for (final keyValue in modelUri.query.split('&')) {
            final pair = keyValue.split('=');
            if (pair.length == 2) {
              switch (pair[0]) {
                case 'session':
                  sessionId = pair[1];
                case 'ref':
                  sourceReference = int.tryParse(pair[1]);
              }
            }
          }
        }
      default:
        path = modelUri.toString();
    }
    return (
      name: basenameOrAuthority(modelUri),
      path: path,
      sourceReference: sourceReference,
      sessionId: sessionId,
    );
  }
}

/// `getUriFromSource`.
VsUri getUriFromSource(Json raw, String? path, String sessionId) {
  VsUri fromSource(String? path) {
    final ref = raw.integer('sourceReference');
    if (ref != null && ref > 0) {
      return VsUri(
        debugScheme,
        path: path?.replaceAll(RegExp(r'^/+'), '/') ?? '',
        query: 'session=$sessionId&ref=$ref',
      );
    }
    if (path != null && isUriString(path)) return VsUri.parse(path);
    if (path != null && isAbsolutePath(path)) {
      return VsUri.file(
        path,
        windows: !path.startsWith('/'),
      );
    }
    // A relative path: a `debug:` URI, whose content the adapter is asked
    // for.
    return VsUri(debugScheme, path: path ?? '', query: 'session=$sessionId');
  }

  try {
    return fromSource(path);
  } on Object {
    return fromSource('/invalidDebugSource');
  }
}
