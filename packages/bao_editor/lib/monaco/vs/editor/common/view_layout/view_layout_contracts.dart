/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Narrow contracts referenced by lineHeights.ts and linesLayout.ts, from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971. The bundled license is at
// lib/ide/editor/monaco/LICENSE.txt. These are not full editor service ports.

import '../core/range.dart';

abstract interface class IEditorWhitespace {
  String get id;
  int get afterLineNumber;
  num get height;
}

/// An accessor that allows whitespace to be added, removed or changed in bulk.
abstract interface class IWhitespaceChangeAccessor {
  String insertWhitespace(
    num afterLineNumber,
    num ordinal,
    num heightInPx,
    num minWidth,
  );
  void changeOneWhitespace(String id, num newAfterLineNumber, num newHeight);
  void removeWhitespace(String id);
}

abstract interface class ILineHeightChangeAccessor {
  void insertOrChangeCustomLineHeight(
    String decorationId,
    int startLineNumber,
    int endLineNumber,
    num lineHeight,
  );
  void removeCustomLineHeight(String decorationId);
}

/// The subset of viewModel.ts needed by the vertical layouter.
class IPartialViewLinesViewportData {
  const IPartialViewLinesViewportData({
    required this.bigNumbersDelta,
    required this.startLineNumber,
    required this.endLineNumber,
    required this.relativeVerticalOffset,
    required this.centeredLineNumber,
    required this.completelyVisibleStartLineNumber,
    required this.completelyVisibleEndLineNumber,
    required this.lineHeight,
  });

  /// Subtract this from scrollTop to keep relative offsets small.
  final num bigNumbersDelta;
  final int startLineNumber;
  final int endLineNumber;

  /// Top of line i + startLineNumber, relative to bigNumbersDelta.
  final List<num> relativeVerticalOffset;
  final int centeredLineNumber;
  final int completelyVisibleStartLineNumber;
  final int completelyVisibleEndLineNumber;
  final num lineHeight;
}

// A record retains the structural equality of upstream viewport data objects.
typedef IViewWhitespaceViewportData = ({
  String id,
  int afterLineNumber,
  num verticalOffset,
  num height,
});

/// Only the decoration properties consumed by CustomLineHeightData.
abstract interface class IModelDecoration {
  String get id;
  IRange get range;
  IModelDecorationOptions get options;
}

abstract interface class IModelDecorationOptions {
  /// A multiplier of the configured default line height.
  num? get lineHeight;
}

abstract interface class ICoordinatesConverter {
  IRange convertModelRangeToViewRange(IRange modelRange);
}

/// Only the configuration option consumed by CustomLineHeightData.
enum EditorOption { lineHeight }

abstract interface class IEditorOptions {
  num get(EditorOption option);
}

abstract interface class IEditorConfiguration {
  IEditorOptions get options;
}
