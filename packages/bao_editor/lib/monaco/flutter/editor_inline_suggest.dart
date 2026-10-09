// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// Inline completions shown as ghost text, adapted from VS Code 1.135.0
// (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5)
// src/vs/editor/contrib/inlineCompletions/browser:
// - model/computeGhostText.ts `computeGhostText` (with
//   singleTextEditHelpers.ts `singleTextRemoveCommonPrefix`) and
//   model/ghostText.ts `GhostText`/`GhostTextPart` ([computeGhostText]);
// - view/ghostText/ghostTextView.ts `computeGhostTextViewData` and
//   ghostTextView.css: each part's first line is injected after its column
//   (`ghost-text-decoration`: italic, `editorGhostText.foreground`/
//   `background`/`border`, cursor stop on the left), the other lines go in a
//   view zone below, and when they break the line, the rest of it is hidden
//   (`ghost-text-hidden`) and shown at the end of the last one;
// - model/inlineCompletionsModel.ts `accept`/`acceptNextWord`, and
//   controller/commands.ts: Tab commits and Escape hides while ghost text
//   shows (the surface's keys).
//
// Deviations: one suggestion at a time, given by the caller (no providers,
// cycling, debounce, telemetry or inline edits); the diff that places the
// parts is a greedy subsequence match rather than `LcsDiff` with smart
// bracket matching, so `subword` parts may split differently; no syntax
// highlighting of the ghost text (upstream's
// `inlineSuggest.syntaxHighlightingEnabled`).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';
import 'editor_surface.dart' show EditorViewZone;
import 'editor_surface_controller.dart';

/// `GhostTextPart`: [lines] (the first goes after [column] of the line).
@immutable
class EditorGhostTextPart {
  EditorGhostTextPart(this.column, this.text, {this.preview = false})
    : lines = text.split(RegExp(r'\r\n|\r|\n'));

  /// One-based column.
  final int column;
  final String text;
  final bool preview;
  final List<String> lines;

  @override
  bool operator ==(Object other) =>
      other is EditorGhostTextPart &&
      other.column == column &&
      other.text == text &&
      other.preview == preview;

  @override
  int get hashCode => Object.hash(column, text, preview);

  @override
  String toString() => 'EditorGhostTextPart($column, ${text.length})';
}

/// `GhostText`: the [parts] shown on one-based [lineNumber].
@immutable
class EditorGhostText {
  const EditorGhostText(this.lineNumber, this.parts);

  final int lineNumber;
  final List<EditorGhostTextPart> parts;

  bool get isEmpty => parts.every((p) => p.text.isEmpty);

  /// `GhostText.render`: [lineText] with the parts inserted.
  String render(String lineText) {
    final buffer = StringBuffer();
    var last = 0;
    for (final part in parts) {
      buffer
        ..write(lineText.substring(last, part.column - 1))
        ..write(part.text);
      last = part.column - 1;
    }
    buffer.write(lineText.substring(last));
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is EditorGhostText &&
      other.lineNumber == lineNumber &&
      listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(lineNumber, Object.hashAll(parts));
}

/// `computeGhostText`: how replacing `[start, end)` of [snapshot] with
/// [text] shows as ghost text, or null when it cannot (it removes text, or
/// spans lines). [mode] is `prefix` (one insertion at the end of the
/// replaced text), `subword` (insertions anywhere in it) or `subwordSmart`
/// (`subword`, none before [cursorOffset]).
EditorGhostText? computeGhostText(
  DocumentSnapshot snapshot,
  int start,
  int end,
  String text, {
  String mode = 'subword',
  int? cursorOffset,
}) {
  final source = snapshot.text;
  if (start < 0 || end > source.length || start > end) return null;
  // singleTextRemoveCommonPrefix.
  var normalized = text.replaceAll('\r\n', '\n');
  var replaced = source.substring(start, end).replaceAll('\r\n', '\n');
  var common = 0;
  while (common < replaced.length &&
      common < normalized.length &&
      replaced.codeUnitAt(common) == normalized.codeUnitAt(common)) {
    common++;
  }
  // The common prefix may hold line breaks: move the start past them.
  var from = start;
  for (var i = 0; i < common; i++) {
    if (source.startsWith('\r\n', from)) {
      from += 2;
    } else {
      from++;
    }
  }
  normalized = normalized.substring(common);
  final startPosition = snapshot.positionAtOffset(from);
  final endPosition = snapshot.positionAtOffset(end);
  if (startPosition.lineNumber != endPosition.lineNumber) return null;
  final lineNumber = startPosition.lineNumber;
  final lineStart = snapshot.lineStarts[lineNumber - 1];
  final lineText = source.substring(
    lineStart,
    snapshot.contentEnds[lineNumber - 1],
  );
  var startColumn = startPosition.column;
  // A suggestion that touches the indentation only adds to it.
  final indentation = lineText.length - lineText.trimLeft().length;
  if (startColumn - 1 <= indentation) {
    final replacedIndentation = lineText.substring(
      startColumn - 1,
      indentation.clamp(startColumn - 1, lineText.length),
    );
    final addedIndentation = normalized.length - normalized.trimLeft().length;
    startColumn = startColumn + replacedIndentation.length <= endPosition.column
        ? startColumn + replacedIndentation.length
        : endPosition.column;
    normalized = normalized.startsWith(replacedIndentation)
        ? normalized.substring(replacedIndentation.length)
        : normalized.substring(addedIndentation);
  }
  replaced = lineText.substring(startColumn - 1, endPosition.column - 1);
  // Insert-only alignment of `replaced` in `normalized`.
  final insertions = <(int, int, int)>[]; // original index, start, end
  var j = 0;
  for (var i = 0; i < replaced.length; i++) {
    final at = normalized.indexOf(replaced[i], j);
    if (at < 0) return null;
    if (at > j) insertions.add((i, j, at));
    j = at + 1;
  }
  if (j < normalized.length) {
    insertions.add((replaced.length, j, normalized.length));
  }
  if (mode == 'prefix' &&
      (insertions.length > 1 ||
          (insertions.length == 1 && insertions.first.$1 != replaced.length))) {
    return null;
  }
  final cursor = cursorOffset == null
      ? null
      : snapshot.positionAtOffset(cursorOffset);
  final parts = <EditorGhostTextPart>[];
  for (final (originalIndex, a, b) in insertions) {
    final column = startColumn + originalIndex;
    if (mode == 'subwordSmart' &&
        cursor != null &&
        cursor.lineNumber == lineNumber &&
        column < cursor.column) {
      return null;
    }
    parts.add(EditorGhostTextPart(column, normalized.substring(a, b)));
  }
  return EditorGhostText(lineNumber, parts);
}

/// An inline completion: replace `[start, end)` of the text it was given
/// for with [text]. [data] is the caller's (e.g. the provider's item).
@immutable
class EditorInlineSuggestion {
  const EditorInlineSuggestion({
    required this.start,
    required this.end,
    required this.text,
    this.data,
  });

  final int start;
  final int end;
  final String text;
  final Object? data;
}

/// Colors of the ghost text (`editorGhostText.*`).
@immutable
class EditorGhostTextColors {
  const EditorGhostTextColors({
    this.foreground = const Color(0x56ffffff),
    this.background,
    this.border,
  });

  factory EditorGhostTextColors.from(Color? Function(String id) colors) =>
      EditorGhostTextColors(
        foreground:
            colors('editorGhostText.foreground') ?? const Color(0x56ffffff),
        background: colors('editorGhostText.background'),
        border: colors('editorGhostText.border'),
      );

  final Color foreground;
  final Color? background;
  final Color? border;

  @override
  bool operator ==(Object other) =>
      other is EditorGhostTextColors &&
      other.foreground == foreground &&
      other.background == background &&
      other.border == border;

  @override
  int get hashCode => Object.hash(foreground, background, border);
}

/// The ghost text of one inline suggestion in one editor
/// (`InlineCompletionsModel` + `GhostTextView`, reduced). [show] it; it
/// follows typing that agrees with it and goes away otherwise, when the
/// cursor leaves it, or on [dismiss]; [accept] inserts it. Give it to the
/// surface's `inlineSuggest`.
class EditorInlineSuggestController extends ChangeNotifier
    implements EditorDecorationProvider {
  EditorInlineSuggestController(
    this.controller, {
    EditorGhostTextColors colors = const EditorGhostTextColors(),
    this.mode = 'subwordSmart',
  })
    // ignore: prefer_initializing_formals
    : _colors = colors {
    controller.addListener(_update);
    _subscription = controller.document.changes.listen(_onChanges);
  }

  final EditorSurfaceController controller;

  /// `inlineSuggest.mode`.
  final String mode;
  late final StreamSubscription<EditorContentChangeEvent> _subscription;
  EditorGhostTextColors _colors;
  EditorInlineSuggestion? _suggestion;
  EditorGhostText? _ghost;
  EditorDecorationSet _decorations = SortedDecorations.empty;
  bool _disposed = false;

  /// Told when a suggestion is inserted ([accept], or partly with
  /// [acceptNextWord]: the accepted length) or hidden without it.
  void Function(EditorInlineSuggestion suggestion, int acceptedLength)?
  onAccepted;
  void Function(EditorInlineSuggestion suggestion)? onDismissed;

  EditorGhostTextColors get colors => _colors;

  set colors(EditorGhostTextColors value) {
    if (value == _colors) return;
    _colors = value;
    _rebuild();
  }

  /// The suggestion shown, with its range as edits moved it.
  EditorInlineSuggestion? get suggestion => _suggestion;

  /// What shows (null when nothing does).
  EditorGhostText? get ghostText => _ghost;

  bool get isVisible => _ghost != null && !_ghost!.isEmpty;

  @override
  EditorDecorationSet get decorations => _decorations;

  @override
  bool get affectsLayout => isVisible;

  /// Shows [suggestion] (over the current text), replacing any other.
  void show(EditorInlineSuggestion suggestion) {
    _suggestion = suggestion;
    _update();
  }

  /// Hides the suggestion (`hideInlineCompletion`, Escape).
  void dismiss() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    _suggestion = null;
    _update();
    onDismissed?.call(suggestion);
  }

  /// Inserts the whole suggestion; the caret goes after it. False when
  /// none shows.
  bool accept() {
    final suggestion = _suggestion;
    if (suggestion == null || !isVisible) return false;
    _suggestion = null;
    final text = _withDocumentEol(suggestion.text);
    controller.applyEdits([
      EditorOffsetEdit(suggestion.start, suggestion.end, text),
    ]);
    final end = suggestion.start + text.length;
    controller.setSelections([TextSelection.collapsed(offset: end)]);
    _update();
    onAccepted?.call(suggestion, suggestion.text.length);
    return true;
  }

  /// `acceptNextWord`: inserts the first part's text up to the end of its
  /// next word (or whitespace run); the rest keeps showing.
  bool acceptNextWord() {
    final ghost = _ghost;
    final suggestion = _suggestion;
    if (ghost == null || suggestion == null || ghost.parts.isEmpty) {
      return false;
    }
    final part = ghost.parts.first;
    final text = part.text;
    final word = RegExp(
      r'(-?\d*\.\d\w*)|([^\`\~\!\@\#\$\%\^\&\*\(\)\-\=\+\[\{\]\}\\\|\;\:\x27\"\,\.\<\>\/\?\s]+)',
    ).firstMatch(text);
    var until = word == null
        ? text.length
        : (word.start == 0 ? word.end : word.start);
    final space = RegExp(r'\s+').firstMatch(text);
    if (space != null && space.end < until) until = space.end;
    if (until <= 0) until = text.length;
    final snapshot = controller.document.snapshot;
    final offset = snapshot.lineStarts[ghost.lineNumber - 1] + part.column - 1;
    final inserted = _withDocumentEol(text.substring(0, until));
    controller.applyEdits([EditorOffsetEdit(offset, offset, inserted)]);
    controller.setSelections([
      TextSelection.collapsed(offset: offset + inserted.length),
    ]);
    onAccepted?.call(suggestion, until);
    _update();
    return true;
  }

  String _withDocumentEol(String text) {
    final snapshot = controller.document.snapshot;
    final crlf = snapshot.text.contains('\r\n');
    final normalized = text.replaceAll('\r\n', '\n');
    return crlf ? normalized.replaceAll('\n', '\r\n') : normalized;
  }

  /// Edits move the range: its start stays before text typed there, its
  /// end goes after it.
  void _onChanges(EditorContentChangeEvent event) {
    var suggestion = _suggestion;
    if (suggestion == null) return;
    var start = suggestion.start;
    var end = suggestion.end;
    for (final change in event.changes) {
      final from = change.rangeOffset;
      final to = from + change.rangeLength;
      final delta = change.text.length - change.rangeLength;
      if (to < start || (to == start && from < start)) {
        start += delta;
        end += delta;
      } else if (from > end) {
        continue;
      } else if (from >= start && to <= end) {
        end += delta;
      } else {
        _suggestion = null;
        return;
      }
    }
    _suggestion = EditorInlineSuggestion(
      start: start,
      end: end,
      text: suggestion.text,
      data: suggestion.data,
    );
  }

  /// Recomputes what shows; hides the suggestion when it no longer can.
  void _update() {
    if (_disposed) return;
    final suggestion = _suggestion;
    EditorGhostText? ghost;
    if (suggestion != null) {
      final selections = controller.selections;
      final primary = selections.first;
      final snapshot = controller.document.snapshot;
      if (selections.length == 1 &&
          primary.isValid &&
          primary.isCollapsed &&
          primary.extentOffset >= suggestion.start &&
          primary.extentOffset <= suggestion.end &&
          suggestion.end <= snapshot.text.length) {
        ghost = computeGhostText(
          snapshot,
          suggestion.start,
          suggestion.end,
          suggestion.text,
          mode: mode,
          cursorOffset: primary.extentOffset,
        );
      }
      if (ghost == null || ghost.isEmpty) {
        _suggestion = null;
        ghost = null;
        scheduleMicrotask(() => onDismissed?.call(suggestion));
      }
    }
    if (ghost == _ghost) return;
    _ghost = ghost;
    _rebuild();
  }

  void _rebuild() {
    final ghost = _ghost;
    if (ghost == null) {
      _decorations = SortedDecorations.empty;
    } else {
      final snapshot = controller.document.snapshot;
      final lineStart = snapshot.lineStarts[ghost.lineNumber - 1];
      final lineEnd = snapshot.contentEnds[ghost.lineNumber - 1];
      final decorations = <EditorDecoration>[];
      final data = _viewData(ghost);
      final hidden = data.hiddenColumn;
      for (final (column, text) in data.inline) {
        if (text.isEmpty) continue;
        final offset = lineStart + column - 1;
        decorations.add(
          EditorDecoration(
            start: offset,
            end: offset,
            showIfCollapsed: true,
            after: _injected(text),
          ),
        );
      }
      if (hidden != null && lineStart + hidden - 1 < lineEnd) {
        decorations.add(
          EditorDecoration(
            start: lineStart + hidden - 1,
            end: lineEnd,
            // `ghost-text-hidden`: opacity 0, font size 0.
            textStyle: const TextStyle(fontSize: 0.001, letterSpacing: 0),
            opacity: 0,
          ),
        );
      }
      _decorations = SortedDecorations(decorations);
    }
    notifyListeners();
  }

  EditorInjectedText _injected(String text) => EditorInjectedText(
    text,
    style: TextStyle(color: _colors.foreground, fontStyle: FontStyle.italic),
    backgroundColor: _colors.background,
    borderColor: _colors.border,
    borderWidth: _colors.border == null
        ? EditorCssLength.zero
        : const EditorCssLength(1),
    cursorStops: InjectedTextCursorStops.left,
  );

  /// `computeGhostTextViewData`: the first lines shown in the line (column,
  /// text), the lines below it as segments (text, isGhost), and the column
  /// from which the line's own text moves to the last of those.
  ({
    List<(int, String)> inline,
    List<List<(String, bool)>> lines,
    int? hiddenColumn,
  })
  _viewData(EditorGhostText ghost) {
    final snapshot = controller.document.snapshot;
    final lineText = snapshot.text.substring(
      snapshot.lineStarts[ghost.lineNumber - 1],
      snapshot.contentEnds[ghost.lineNumber - 1],
    );
    final inline = <(int, String)>[];
    final lines = <List<(String, bool)>>[];
    int? hiddenColumn;
    var last = 0;
    void addLines(List<String> added, bool isGhost) {
      var rest = added;
      if (lines.isNotEmpty) {
        lines.last.add((rest.first, isGhost));
        rest = rest.sublist(1);
      }
      for (final line in rest) {
        lines.add([(line, isGhost)]);
      }
    }

    for (final part in ghost.parts) {
      var ghostLines = part.lines;
      if (hiddenColumn == null) {
        inline.add((part.column, ghostLines.first));
        ghostLines = ghostLines.sublist(1);
      } else {
        addLines([lineText.substring(last, part.column - 1)], false);
      }
      if (ghostLines.isNotEmpty) {
        addLines(ghostLines, true);
        if (hiddenColumn == null && part.column <= lineText.length) {
          hiddenColumn = part.column;
        }
      }
      last = part.column - 1;
    }
    if (hiddenColumn != null) addLines([lineText.substring(last)], false);
    return (inline: inline, lines: lines, hiddenColumn: hiddenColumn);
  }

  /// The view zone with the ghost text's other lines (none when it has
  /// one line), in the editor's [style].
  List<EditorViewZone> zones(TextStyle style) {
    final ghost = _ghost;
    if (ghost == null) return const [];
    final lines = _viewData(ghost).lines;
    if (lines.isEmpty) return const [];
    return [
      EditorViewZone(
        afterLineNumber: ghost.lineNumber,
        heightInLines: lines.length.toDouble(),
        content: _GhostLines(lines: lines, style: style, colors: _colors),
      ),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_update);
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// The ghost text's lines below its line (`AdditionalLinesWidget`): ghost
/// segments in the ghost color, the line's moved rest in the text's.
class _GhostLines extends StatelessWidget {
  const _GhostLines({
    required this.lines,
    required this.style,
    required this.colors,
  });

  final List<List<(String, bool)>> lines;
  final TextStyle style;
  final EditorGhostTextColors colors;

  @override
  Widget build(BuildContext context) {
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segments in lines)
          Text.rich(
            TextSpan(
              style: style,
              children: [
                for (final (text, isGhost) in segments)
                  TextSpan(
                    text: text,
                    style: isGhost
                        ? TextStyle(
                            color: colors.foreground,
                            fontStyle: FontStyle.italic,
                            backgroundColor: colors.background,
                          )
                        : null,
                  ),
              ],
            ),
            strutStyle: strut,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            textScaler: TextScaler.noScaling,
          ),
      ],
    );
  }
}
