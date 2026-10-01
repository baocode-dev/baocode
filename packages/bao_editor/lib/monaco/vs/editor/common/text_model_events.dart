/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Source: textModelEvents.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Public content/options/language/plain-decoration events only. Raw view events,
// injected text, line height, font and token events are intentionally omitted.

import 'model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'text_model_edit_source.dart';

class ModelContentChangedEvent {
  const ModelContentChangedEvent({
    required this.changes,
    required this.eol,
    required this.versionId,
    required this.isUndoing,
    required this.isRedoing,
    required this.isFlush,
    required this.isEolChange,
    required this.detailedReasons,
  });

  /// Descending document order; can be applied sequentially to an old value.
  final List<InternalModelContentChange> changes;
  final String eol;
  final int versionId;
  final bool isUndoing;
  final bool isRedoing;
  final bool isFlush;
  final bool isEolChange;
  final List<TextModelEditSource> detailedReasons;

  /// One change-count for each detailed reason (one reason in this subset).
  List<int> get detailedReasonsChangeLengths => [changes.length];
}

class ModelOptionsChangedEvent {
  const ModelOptionsChangedEvent({
    required this.tabSize,
    required this.indentSize,
    required this.insertSpaces,
    required this.trimAutoWhitespace,
  });
  final bool tabSize;
  final bool indentSize;
  final bool insertSpaces;
  final bool trimAutoWhitespace;
}

class ModelLanguageChangedEvent {
  const ModelLanguageChangedEvent(
    this.oldLanguage,
    this.newLanguage,
    this.source,
  );
  final String oldLanguage;
  final String newLanguage;
  final String source;
}
