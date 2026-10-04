import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter/foundation.dart';

/// An edit in progress of one block of a markdown document, made in a
/// field of its own and put in the document at once when done: the
/// block's text replaced, as one undo step, and the rest of the document
/// left as it is, byte for byte.
///
/// The block follows the document's changes made meanwhile elsewhere
/// (another tab's, an agent's, the file reloaded); one changing the block
/// itself, or touching it, ends the edit ([onConflict]): it then puts
/// nothing in.
class MarkdownBlockEdit {
  /// The block at [start, end) of [model]'s text. One [start]ing at the
  /// end of the text with nothing in it is a new block, [prefix] (the line
  /// breaks keeping it apart from the last) put before what it gets.
  MarkdownBlockEdit(
    this.model, {
    required int start,
    required int end,
    this.prefix = '',
    this.onConflict,
  }) : _start = start,
       _end = end,
       original = model.text.substring(start, end) {
    _lineBreak = _lineBreakOf(original) ?? _lineBreakOf(model.text) ?? '\n';
    _changes = model.changes.listen(_changed);
  }

  final EditorDocumentModel model;
  final String prefix;

  /// Called once, when another change touched the block.
  final VoidCallback? onConflict;

  /// The block's text when the edit began.
  final String original;

  int _start;
  int _end;
  late final String _lineBreak;
  late final StreamSubscription<EditorContentChangeEvent> _changes;
  bool _applying = false;
  bool _conflicted = false;
  bool _done = false;

  /// Where the block now is in the text.
  int get start => _start;
  int get end => _end;

  /// Whether another change touched the block: it cannot be put in.
  bool get conflicted => _conflicted;

  /// The block's text as its field edits it, with LF line breaks.
  String get text => original.replaceAll(_lineBreaks, '\n');

  void _changed(EditorContentChangeEvent event) {
    if (_applying || _conflicted || _done) return;
    // Each change is in the text the previous ones left.
    for (final change in event.changes) {
      final from = change.rangeOffset;
      final to = from + change.rangeLength;
      if (to < _start) {
        final delta = change.text.length - change.rangeLength;
        _start += delta;
        _end += delta;
      } else if (from > _end) {
        continue;
      } else {
        _conflicted = true;
        onConflict?.call();
        return;
      }
    }
  }

  /// Puts [edited] (the field's text) in place of the block, its line
  /// breaks the document's, and ends the edit. Whether the document
  /// changed: not when the text is the same, nor after a conflict.
  bool commit(String edited) {
    if (_done) return false;
    _done = true;
    unawaited(_changes.cancel());
    if (_conflicted) return false;
    final replacement = edited
        .replaceAll(_lineBreaks, '\n')
        .replaceAll('\n', _lineBreak);
    final isNew = _start == _end && original.isEmpty;
    if (isNew && replacement.trim().isEmpty) return false;
    if (replacement == model.text.substring(_start, _end)) return false;
    var start = _start;
    var end = _end;
    if (replacement.isEmpty) {
      // The block deleted takes its line with it.
      final text = model.text;
      if (text.startsWith(_lineBreak, end)) {
        end += _lineBreak.length;
      } else if (start >= _lineBreak.length &&
          text.startsWith(_lineBreak, start - _lineBreak.length)) {
        start -= _lineBreak.length;
      }
    }
    _applying = true;
    try {
      model.closeUndoGroup();
      model.applyOffsetEdits([
        EditorOffsetEdit(
          start,
          end,
          isNew ? '$prefix$replacement' : replacement,
        ),
      ]);
      model.closeUndoGroup();
    } finally {
      _applying = false;
    }
    return true;
  }

  /// Ends the edit without putting anything in.
  void cancel() {
    if (_done) return;
    _done = true;
    unawaited(_changes.cancel());
  }

  /// What goes before a new block at the end of [text]: line breaks to
  /// leave an empty line after the last block.
  static String newBlockPrefix(String text) {
    if (text.trim().isEmpty) return '';
    final lineBreak = _lineBreakOf(text) ?? '\n';
    if (text.endsWith('$lineBreak$lineBreak')) return '';
    return text.endsWith(lineBreak) ? lineBreak : '$lineBreak$lineBreak';
  }

  static String? _lineBreakOf(String text) =>
      _lineBreaks.firstMatch(text)?.group(0);
}

final _lineBreaks = RegExp('\r\n|\r|\n');

/// Ticks or unticks the task box whose mark (the space or `x` between its
/// brackets) is at [offset] of [model]'s text, as one undo step.
void toggleMarkdownTask(EditorDocumentModel model, int offset) {
  final text = model.text;
  if (offset < 0 || offset >= text.length) return;
  final mark = text[offset];
  if (mark != ' ' && mark != 'x' && mark != 'X') return;
  model.closeUndoGroup();
  model.applyOffsetEdits([
    EditorOffsetEdit(offset, offset + 1, mark == ' ' ? 'x' : ' '),
  ]);
  model.closeUndoGroup();
}
