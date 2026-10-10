/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Command arguments as the extension host marshals them, and the shapes
// the built-in commands read.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/marshalling.ts (`revive`), src/vs/editor/common/core/
// position.ts and range.ts (`isIPosition`, `isIRange`, `lift`),
// src/vs/workbench/api/common/extHostTypeConverters.ts (`ViewColumn.from`,
// `TextEditorOpenOptions.from`: what `vscode.open`'s options arrive as).
//
// Deviations: a revived regular expression is a [JsRegExp]; dates are
// [DateTime]s.

import 'package:bao_exthost/bao_exthost.dart';

import '../contextkey/js_values.dart';

/// `MarshalledId.Regexp`, `MarshalledId.Date`.
const _regexpMarshalledId = 2;
const _dateMarshalledId = 3;

/// `revive`: marshalled URIs (`$mid: 1`) as [VsUri]s, regular expressions
/// and dates, anywhere in [value] (up to 200 levels deep).
Object? reviveMarshalled(Object? value, [int depth = 0]) {
  if (value == null || depth > 200) return value;
  if (value is Map) {
    switch (value[r'$mid']) {
      case uriMarshalledId:
        return VsUri.revive(value.cast<String, Object?>());
      case _regexpMarshalledId:
        try {
          return JsRegExp('${value['source']}', '${value['flags'] ?? ''}');
        } on FormatException {
          return value;
        }
      case _dateMarshalledId:
        return DateTime.tryParse('${value['source']}') ?? value;
    }
    return {
      for (final MapEntry(:key, value: v) in value.entries)
        '$key': reviveMarshalled(v, depth + 1),
    };
  }
  if (value is List) {
    return [for (final v in value) reviveMarshalled(v, depth + 1)];
  }
  return value;
}

/// `IPosition`: 1-based line and column.
typedef CommandPosition = ({int lineNumber, int column});

/// `IRange`: 1-based, end exclusive of nothing (as Monaco's).
typedef CommandRange = ({
  int startLineNumber,
  int startColumn,
  int endLineNumber,
  int endColumn,
});

/// `Location`: a range in a resource.
typedef CommandLocation = ({VsUri uri, CommandRange range});

int? _int(Object? v) => v is num ? v.toInt() : null;

/// `Position.isIPosition` / `Position.lift`; null when [value] is none.
CommandPosition? positionArg(Object? value) {
  if (value is! Map) return null;
  final line = _int(value['lineNumber']);
  final column = _int(value['column']);
  if (line == null || column == null) return null;
  return (lineNumber: line, column: column);
}

/// `Range.isIRange` / `Range.lift`; null when [value] is none.
CommandRange? rangeArg(Object? value) {
  if (value is! Map) return null;
  final sl = _int(value['startLineNumber']);
  final sc = _int(value['startColumn']);
  final el = _int(value['endLineNumber']);
  final ec = _int(value['endColumn']);
  if (sl == null || sc == null || el == null || ec == null) return null;
  return (startLineNumber: sl, startColumn: sc, endLineNumber: el, endColumn: ec);
}

/// A URI argument: revived, or its components.
VsUri? uriArg(Object? value) => switch (value) {
  final VsUri uri => uri,
  final Map<Object?, Object?> map => VsUri.tryRevive(map),
  _ => null,
};

/// `languages.Location` (`{uri, range}`); null when [value] is none.
CommandLocation? locationArg(Object? value) {
  if (value is! Map) return null;
  final uri = uriArg(value['uri']);
  final range = rangeArg(value['range']);
  if (uri == null || range == null) return null;
  return (uri: uri, range: range);
}

/// Where an editor opens (`EditorGroupColumn`): a 0-based group, or
/// [activeGroup] / [sideGroup].
abstract final class EditorGroupColumn {
  static const activeGroup = -1;
  static const sideGroup = -2;
}

/// `ITextEditorOptions`, as `TextEditorOpenOptions.from` sends them.
typedef EditorOpenOptions = ({
  bool? pinned,
  bool? inactive,
  bool? preserveFocus,
  CommandRange? selection,
});

/// `[column, options]` of `_workbench.open` / `_workbench.diff`.
({int? column, EditorOpenOptions? options}) columnAndOptionsArg(
  Object? value,
) {
  if (value is! List) return (column: null, options: null);
  final column = value.isNotEmpty ? _int(value[0]) : null;
  final raw = value.length > 1 ? value[1] : null;
  EditorOpenOptions? options;
  if (raw is Map) {
    options = (
      pinned: raw['pinned'] as bool?,
      inactive: raw['inactive'] as bool?,
      preserveFocus: raw['preserveFocus'] as bool?,
      selection: rangeArg(raw['selection']),
    );
  }
  return (column: column, options: options);
}
