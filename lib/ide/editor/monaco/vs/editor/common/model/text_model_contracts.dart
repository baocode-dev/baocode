/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Source: VS Code model.ts, pinned at 6a598d4a13031703d483d103c1d934a36ad27971.
// Only the text, edit, option and plain-range decoration contracts are exposed.
// Omitted: tokenization, bracket pairs, guides, search, injected text, rendering,
// attached views, large-file limits, language services and external undo services.

import '../core/range.dart';
import 'interval_tree.dart';
import 'piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'piece_tree_text_buffer/piece_tree_text_buffer_builder.dart';

export 'interval_tree.dart' show TrackedRangeStickiness;
export 'piece_tree_text_buffer/piece_tree_text_buffer.dart'
    show EndOfLinePreference, SingleEditOperationIdentifier, ValidEditOperation;
export 'piece_tree_text_buffer/piece_tree_text_buffer_builder.dart'
    show DefaultEndOfLine;

enum EndOfLineSequence { lf, crlf }

abstract interface class TextSnapshot {
  String? read();
}

class TextModelEditOperation {
  const TextModelEditOperation(
    this.range,
    this.text, {
    this.identifier,
    this.forceMoveMarkers = false,
    this.isAutoWhitespaceEdit = false,
    this.isTracked = false,
  });

  final Range range;
  final String? text;
  final SingleEditOperationIdentifier? identifier;
  final bool forceMoveMarkers;
  final bool isAutoWhitespaceEdit;
  final bool isTracked;
}

class TextModelOptions {
  const TextModelOptions({
    this.tabSize = 4,
    this.indentSize,
    this.insertSpaces = true,
    this.trimAutoWhitespace = true,
    this.defaultEOL = DefaultEndOfLine.lf,
  });

  final int tabSize;

  /// Null means track tabSize, as upstream's 'tabSize' option does.
  final int? indentSize;
  final bool insertSpaces;
  final bool trimAutoWhitespace;
  final DefaultEndOfLine defaultEOL;
}

class TextModelResolvedOptions {
  const TextModelResolvedOptions({
    required this.tabSize,
    required this.indentSize,
    required this.originalIndentSize,
    required this.insertSpaces,
    required this.trimAutoWhitespace,
    required this.defaultEOL,
  });

  final int tabSize;
  final int indentSize;
  final int? originalIndentSize;
  final bool insertSpaces;
  final bool trimAutoWhitespace;
  final DefaultEndOfLine defaultEOL;
}

class ModelDeltaDecoration {
  const ModelDeltaDecoration(
    this.range, {
    this.options = const IntervalNodeOptions(),
  });
  final Range range;

  /// Only IntervalNodeOptions are supported. Rendering/injected-text options are omitted.
  final IntervalNodeOptions options;
}

class ModelDecoration {
  const ModelDecoration(this.id, this.range, this.options, this.ownerId);
  final String id;
  final Range range;
  final IntervalNodeOptions options;
  final int ownerId;
}

// Keep the imported source types part of this small model's public vocabulary.
typedef ModelEOLPreference = EndOfLinePreference;
typedef ModelDefaultEOL = DefaultEndOfLine;
typedef ModelStickiness = TrackedRangeStickiness;
