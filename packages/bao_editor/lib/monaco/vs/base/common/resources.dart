/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/resources.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: the `DataUri` namespace.

import 'uri.dart';

/// Upstream `DataUri`.
abstract final class DataUri {
  static const String metaDataLabel = 'label';
  static const String metaDataDescription = 'description';
  static const String metaDataSize = 'size';
  static const String metaDataMime = 'mime';

  /// For `data:image/png;size:2313;label:SomeLabel;description:Desc;base64,…`
  /// returns `size`, `label` and `description`, plus `mime` (`image/png`).
  static Map<String, String> parseMetaData(URI dataUri) {
    final metadata = <String, String>{};
    final path = dataUri.path;
    final meta = _substring(path, path.indexOf(';') + 1, path.lastIndexOf(';'));
    for (final property in meta.split(';')) {
      final parts = property.split(':');
      final key = parts[0];
      final value = parts.length > 1 ? parts[1] : '';
      if (key.isNotEmpty && value.isNotEmpty) metadata[key] = value;
    }
    final mime = _substring(path, 0, path.indexOf(';'));
    if (mime.isNotEmpty) metadata[metaDataMime] = mime;
    return metadata;
  }
}

/// JavaScript `String.prototype.substring`: clamps both indices to the
/// string and swaps them when the start is after the end.
String _substring(String s, int start, int end) {
  start = start.clamp(0, s.length);
  end = end.clamp(0, s.length);
  return start <= end ? s.substring(start, end) : s.substring(end, start);
}
