// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
// Ported from VS Code src/vs/editor/common/core/editOperation.ts.

import 'position.dart';
import 'range.dart';

abstract interface class ISingleEditOperation {
  IRange get range;
  String? get text;
  bool? get forceMoveMarkers;
}

class SingleEditOperation implements ISingleEditOperation {
  const SingleEditOperation(this.range, this.text, {this.forceMoveMarkers});

  @override
  final IRange range;
  @override
  final String? text;
  @override
  final bool? forceMoveMarkers;
}

class EditOperation {
  const EditOperation._();

  static ISingleEditOperation insert(Position position, String text) =>
      SingleEditOperation(
        Range(
          position.lineNumber,
          position.column,
          position.lineNumber,
          position.column,
        ),
        text,
        forceMoveMarkers: true,
      );

  static ISingleEditOperation delete(Range range) =>
      SingleEditOperation(range, null);

  static ISingleEditOperation replace(Range range, String? text) =>
      SingleEditOperation(range, text);

  static ISingleEditOperation replaceMove(Range range, String? text) =>
      SingleEditOperation(range, text, forceMoveMarkers: true);
}
