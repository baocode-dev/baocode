/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The document data the main thread sends the extension host.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/model/mirrorTextModel.ts (`IModelContentChange`,
// `IModelChangedEvent`), src/vs/editor/common/textModelEvents.ts
// (`ISerializedModelContentChangedEvent`),
// src/vs/workbench/api/common/extHost.protocol.ts (`IModelAddedData`).
//
// Deviations:
// - `detailedReason` is never sent (BaoCode has no edit-source telemetry).

import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

/// `IModelContentChange`: [text] replaced [range] (one-based lines and
/// UTF-16 columns of the model as the previous changes of the event left it).
class ModelContentChange {
  const ModelContentChange({
    required this.range,
    required this.rangeOffset,
    required this.rangeLength,
    required this.text,
  });

  factory ModelContentChange.fromJson(Map<String, Object?> json) {
    final range = (json['range']! as Map).cast<String, Object?>();
    return ModelContentChange(
      range: Range(
        range['startLineNumber']! as int,
        range['startColumn']! as int,
        range['endLineNumber']! as int,
        range['endColumn']! as int,
      ),
      rangeOffset: json['rangeOffset']! as int,
      rangeLength: json['rangeLength']! as int,
      text: json['text']! as String,
    );
  }

  /// The old range that got replaced.
  final Range range;

  /// The offset of the range that got replaced.
  final int rangeOffset;

  /// The length of the range that got replaced.
  final int rangeLength;

  /// The new text for the range.
  final String text;

  Map<String, Object?> toJson() => {
    'range': range.toJson(),
    'rangeOffset': rangeOffset,
    'rangeLength': rangeLength,
    'text': text,
  };

  @override
  String toString() =>
      'ModelContentChange($range, $rangeOffset+$rangeLength, '
      '${text.replaceAll('\r', r'\r').replaceAll('\n', r'\n')})';
}

/// `ISerializedModelContentChangedEvent` (an `IModelChangedEvent` plus the
/// flush/EOL flags): the argument of `ExtHostDocuments.$acceptModelChanged`.
/// Changes apply in order, each to the text the previous one left.
class ModelChangedEvent {
  const ModelChangedEvent({
    required this.changes,
    required this.eol,
    required this.versionId,
    this.isUndoing = false,
    this.isRedoing = false,
    this.isFlush = false,
    this.isEolChange = false,
  });

  factory ModelChangedEvent.fromJson(Map<String, Object?> json) =>
      ModelChangedEvent(
        changes: [
          for (final change in json['changes']! as List)
            ModelContentChange.fromJson((change as Map).cast()),
        ],
        eol: json['eol']! as String,
        versionId: json['versionId']! as int,
        isUndoing: json['isUndoing'] == true,
        isRedoing: json['isRedoing'] == true,
        isFlush: json['isFlush'] == true,
        isEolChange: json['isEolChange'] == true,
      );

  final List<ModelContentChange> changes;

  /// The (new) end-of-line sequence of the model.
  final String eol;

  /// The version the model has transitioned to.
  final int versionId;
  final bool isUndoing;
  final bool isRedoing;

  /// The whole text was replaced (`TextModel.setValue`).
  final bool isFlush;

  /// Only the EOL changed (`TextModel.setEOL`).
  final bool isEolChange;

  Map<String, Object?> toJson() => {
    'changes': [for (final change in changes) change.toJson()],
    'eol': eol,
    'versionId': versionId,
    'isUndoing': isUndoing,
    'isRedoing': isRedoing,
    'isFlush': isFlush,
    'isEolChange': isEolChange,
  };
}

/// `IModelAddedData`: a document as `$acceptDocumentsAndEditorsDelta`
/// announces it.
class ModelAddedData {
  const ModelAddedData({
    required this.uri,
    required this.versionId,
    required this.lines,
    required this.eol,
    required this.languageId,
    this.isDirty = false,
    this.encoding = 'utf8',
  });

  final VsUri uri;
  final int versionId;
  final List<String> lines;
  final String eol;
  final String languageId;
  final bool isDirty;

  /// The encoding id (`utf8`, `utf8bom`, `utf16le`, …).
  final String encoding;

  Map<String, Object?> toJson() => {
    'uri': uri.toJson(),
    'versionId': versionId,
    'lines': lines,
    'EOL': eol,
    'languageId': languageId,
    'isDirty': isDirty,
    'encoding': encoding,
  };
}
