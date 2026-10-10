/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The part of `ITextModel` language features use.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/model.ts (`ITextModel.uri`, `getLanguageId`,
// `getVersionId`, `getLineCount`, `getLineContent`, `shouldSynchronizeModel`).
//
// Deviations:
// - Adds the mapping between editor coordinates (one-based over BaoCode's
//   raw text, which keeps a BOM) and model coordinates (one-based over the
//   model text, which providers and the extension host use).

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

/// A document as language feature providers see it: the model of an open
/// editor document (see `ExtHostDocumentMirror`).
abstract interface class LanguageFeatureDocument {
  VsUri get uri;

  /// The VS Code language id.
  String get languageId;

  int get versionId;

  /// `shouldSynchronizeModel`: false for documents too large to sync, which
  /// only `hasAccessToAllModels` selectors match.
  bool get isSynchronized;

  int get lineCount;

  /// The model text of one-based [lineNumber] (no line break, no BOM).
  String getLineContent(int lineNumber);

  /// Editor coordinates to model coordinates.
  Position toModelPosition(IPosition editorPosition);

  /// Model coordinates to editor coordinates.
  Position toEditorPosition(IPosition modelPosition);
}
