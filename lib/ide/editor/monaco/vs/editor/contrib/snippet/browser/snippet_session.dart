/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Adapted from VS Code src/vs/editor/contrib/snippet/browser/snippetSession.ts
// (OneSnippet, SnippetSession.adjustWhitespace/adjustSelection/
// createEditsAndSnippetsFromSelections, next/prev/_move) and a subset of
// snippetVariables.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: placeholder ranges are UTF-16 offset pairs tracked by
// [SnippetSession.acceptEdits] (the interval-tree `nodeAcceptEdit` rule with
// AlwaysGrows stickiness for the active group, NeverGrows otherwise) instead
// of model decorations; the caller applies the returned edits. Nested
// snippets are not merged: inserting a snippet during a session replaces it.
// Variables resolve through a caller callback (see [SnippetVariableValues]);
// unknown variables keep their default text as upstream does.

import 'dart:math' as math;

import 'snippet_parser.dart';

/// A replacement of `[start, end)` (pre-edit UTF-16 offsets) by [text].
class SnippetEdit {
  const SnippetEdit(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

/// A tracked placeholder range.
class _TrackedRange {
  _TrackedRange(this.start, this.end);

  int start;
  int end;
}

/// Upstream `nodeAcceptEdit` for one marker (forceMoveMarkers false).
int _acceptEdit(
  int marker,
  bool stickToPrevious,
  int start,
  int end,
  int length,
) {
  final deleting = end - start;
  final common = math.min(deleting, length);
  bool before(int check, {required bool forceStay}) {
    if (marker != check) return marker < check;
    return forceStay || stickToPrevious;
  }

  if (before(start, forceStay: deleting > 0)) return marker;
  if (common > 0 && before(start + common, forceStay: deleting > length)) {
    return marker;
  }
  if (before(end, forceStay: false)) return start + length;
  return marker + length - deleting;
}

List<List<Placeholder>> _groupBy(List<Placeholder> placeholders) {
  final sorted = List.of(placeholders)..sort(Placeholder.compareByIndex);
  final groups = <List<Placeholder>>[];
  for (final placeholder in sorted) {
    if (groups.isEmpty ||
        Placeholder.compareByIndex(groups.last.first, placeholder) != 0) {
      groups.add([placeholder]);
    } else {
      groups.last.add(placeholder);
    }
  }
  return groups;
}

/// A selection to make: `[base, extent]` offsets.
typedef SnippetSelection = ({int base, int extent});

/// A choice placeholder that is active, with its current range.
typedef SnippetActiveChoice = ({Choice choice, int start, int end});

/// One inserted snippet (upstream `OneSnippet`).
class OneSnippet {
  OneSnippet(this.snippet, this.snippetLineLeadingWhitespace)
    : _placeholderGroups = _groupBy(snippet.placeholders);

  final TextmateSnippet snippet;
  final String snippetLineLeadingWhitespace;
  final List<List<Placeholder>> _placeholderGroups;
  int _placeholderGroupsIdx = -1;
  int _offset = -1;
  Map<Placeholder, _TrackedRange>? _ranges;
  final Set<Placeholder> _active = {};

  void initialize(int offset) => _offset = offset;

  void _initRanges() {
    if (_offset == -1) throw StateError('Snippet not initialized!');
    if (_ranges != null) return;
    _ranges = {
      for (final placeholder in snippet.placeholders)
        placeholder: _TrackedRange(
          _offset + snippet.offset(placeholder),
          _offset + snippet.offset(placeholder) + snippet.fullLen(placeholder),
        ),
    };
  }

  /// Maps the tracked ranges through sorted, disjoint pre-edit [edits]
  /// (`(start, end, insertedLength)`).
  void acceptEdits(List<(int, int, int)> edits) {
    final ranges = _ranges;
    if (ranges == null) return;
    for (final MapEntry(key: placeholder, value: range) in ranges.entries) {
      final grows = _active.contains(placeholder);
      for (final (start, end, length) in edits.reversed) {
        final newStart = _acceptEdit(range.start, grows, start, end, length);
        final newEnd = _acceptEdit(range.end, !grows, start, end, length);
        range.start = newStart;
        range.end = math.max(newStart, newEnd);
      }
    }
  }

  /// Moves to the next (`true`), previous (`false`) or current (`null`)
  /// placeholder group. [transform] applies placeholder transformations of
  /// the group being left and must call [acceptEdits] with what it applied.
  List<SnippetSelection> move(
    bool? fwd, {
    required String Function(int start, int end) textIn,
    required void Function(List<SnippetEdit> edits) transform,
    required String Function(String text) normalizeIndentation,
    required String eol,
  }) {
    _initRanges();
    final ranges = _ranges!;

    // Transform placeholder text if necessary
    if (_placeholderGroupsIdx >= 0) {
      final operations = <SnippetEdit>[];
      for (final placeholder in _placeholderGroups[_placeholderGroupsIdx]) {
        final range = ranges[placeholder];
        if (placeholder.transform != null && range != null) {
          final currentValue = textIn(range.start, range.end);
          final lines = placeholder.transform!
              .resolve(currentValue)
              .split(RegExp(r'\r\n|\r|\n'));
          // fix indentation for transformed lines
          for (var i = 1; i < lines.length; i++) {
            lines[i] = normalizeIndentation(
              snippetLineLeadingWhitespace + lines[i],
            );
          }
          operations.add(SnippetEdit(range.start, range.end, lines.join(eol)));
        }
      }
      if (operations.isNotEmpty) {
        operations.sort((a, b) => a.start.compareTo(b.start));
        transform(operations);
      }
    }

    var couldSkipThisPlaceholder = false;
    if (fwd == true && _placeholderGroupsIdx < _placeholderGroups.length - 1) {
      _placeholderGroupsIdx += 1;
      couldSkipThisPlaceholder = true;
    } else if (fwd == false && _placeholderGroupsIdx > 0) {
      _placeholderGroupsIdx -= 1;
      couldSkipThisPlaceholder = true;
    } else {
      // the selection of the current placeholder might
      // not acurate any more -> simply restore it
    }

    // Active placeholders (and those enclosing them) grow when typing at
    // their edges; all others never grow.
    _active.clear();
    final selections = <SnippetSelection>[];
    for (final placeholder in _placeholderGroups[_placeholderGroupsIdx]) {
      final range = ranges[placeholder];
      // consider to skip this placeholder index when the decoration
      // range is empty but when the placeholder wasn't. that's a strong
      // hint that the placeholder has been deleted. (all placeholder must
      // match this)
      couldSkipThisPlaceholder =
          couldSkipThisPlaceholder && _hasPlaceholderBeenCollapsed(placeholder);
      if (range == null) continue;
      selections.add((base: range.start, extent: range.end));
      _active.add(placeholder);
      _active.addAll(snippet.enclosingPlaceholders(placeholder));
    }

    return !couldSkipThisPlaceholder
        ? selections
        : move(
            fwd,
            textIn: textIn,
            transform: transform,
            normalizeIndentation: normalizeIndentation,
            eol: eol,
          );
  }

  bool _hasPlaceholderBeenCollapsed(Placeholder placeholder) {
    // A placeholder is empty when it wasn't empty when authored but
    // when its tracking decoration is empty. This also applies to all
    // potential parent placeholders
    Marker? marker = placeholder;
    while (marker != null) {
      if (marker is Placeholder) {
        final range = _ranges![marker];
        if ((range == null || range.start == range.end) &&
            marker.toString().isNotEmpty) {
          return true;
        }
      }
      marker = marker.parent;
    }
    return false;
  }

  bool get isAtFirstPlaceholder =>
      _placeholderGroupsIdx <= 0 || _placeholderGroups.isEmpty;

  bool get isAtLastPlaceholder =>
      _placeholderGroupsIdx == _placeholderGroups.length - 1;

  bool get hasPlaceholder => snippet.placeholders.isNotEmpty;

  /// A snippet is trivial when it has no placeholder or only a final
  /// placeholder at its very end
  bool get isTrivialSnippet {
    if (snippet.placeholders.isEmpty) return true;
    if (snippet.placeholders.length == 1) {
      final placeholder = snippet.placeholders.first;
      if (placeholder.isFinalTabstop &&
          identical(snippet.rightMostDescendant, placeholder)) {
        return true;
      }
    }
    return false;
  }

  /// Ranges each non-final placeholder index may select (upstream
  /// `computePossibleSelections`).
  Map<num, List<(int, int)>> computePossibleSelections() {
    final result = <num, List<(int, int)>>{};
    for (final group in _placeholderGroups) {
      List<(int, int)>? ranges;
      for (final placeholder in group) {
        if (placeholder.isFinalTabstop) break;
        ranges ??= result[placeholder.index] = [];
        final range = _ranges?[placeholder];
        if (range == null) {
          result.remove(placeholder.index);
          break;
        }
        ranges.add((range.start, range.end));
      }
    }
    return result;
  }

  SnippetActiveChoice? get activeChoice {
    if (_ranges == null || _placeholderGroupsIdx < 0) return null;
    final placeholder = _placeholderGroups[_placeholderGroupsIdx].firstOrNull;
    final choice = placeholder?.choice;
    if (choice == null) return null;
    final range = _ranges![placeholder];
    if (range == null) return null;
    return (choice: choice, start: range.start, end: range.end);
  }

  /// Every placeholder range, for painting: `(start, end, active, final)`.
  Iterable<(int, int, bool, bool)> get placeholderRanges sync* {
    final ranges = _ranges;
    if (ranges == null) return;
    for (final MapEntry(key: placeholder, value: range) in ranges.entries) {
      yield (
        range.start,
        range.end,
        _active.contains(placeholder),
        placeholder.isFinalTabstop,
      );
    }
  }

  (int, int)? get enclosingRange {
    int? start;
    int? end;
    for (final range in _ranges?.values ?? const <_TrackedRange>[]) {
      start = start == null ? range.start : math.min(start, range.start);
      end = end == null ? range.end : math.max(end, range.end);
    }
    return start == null ? null : (start, end!);
  }
}

/// Values for snippet variables at one cursor: [name] is the variable name,
/// [cursorIndex] the cursor's index. Return null for unknown variables.
typedef SnippetVariableValues = String? Function(String name, int cursorIndex);

class _Resolver implements VariableResolver {
  _Resolver(this._values, this._index);

  final SnippetVariableValues _values;
  final int _index;

  @override
  String? resolve(Variable variable) => _values(variable.name, _index);
}

/// What inserting a snippet at every cursor does: the edits (sorted,
/// pre-edit offsets) and the session that tracks the result.
class SnippetInsertion {
  SnippetInsertion(this.edits, this.session);

  final List<SnippetEdit> edits;
  final SnippetSession session;
}

/// A cursor to insert at: `[start, end)` is what the snippet replaces (the
/// selection extended by overwriteBefore/After) and [lineText]/[column] its
/// start line's content and zero-based start column within it.
typedef SnippetTarget = ({
  int start,
  int end,
  String lineText,
  int column,
  int cursorIndex,
});

class SnippetSession {
  SnippetSession._(this._snippets);

  final List<OneSnippet> _snippets;

  /// Upstream `SnippetSession.adjustWhitespace`: indents every line after
  /// the first by the insertion line's leading whitespace, normalizing
  /// indentation, and uses [eol] for line breaks. Returns that whitespace.
  static String adjustWhitespace(
    String lineText,
    int column,
    bool adjustIndentation,
    TextmateSnippet snippet,
    String Function(String text) normalizeIndentation,
    String eol,
  ) {
    var end = 0;
    while (end < column && end < lineText.length) {
      final c = lineText.codeUnitAt(end);
      if (c != 0x20 && c != 0x09) break;
      end++;
    }
    final lineLeadingWhitespace = lineText.substring(0, end);

    // the snippet as inserted
    String? snippetTextString;

    snippet.walk((marker) {
      // all text elements that are not inside choice
      if (marker is! Text || marker.parent is Choice) return true;

      final lines = marker.value.split(RegExp(r'\r\n|\r|\n'));

      if (adjustIndentation) {
        // adjust indentation of snippet test
        // -the snippet-start doesn't get extra-indented (lineLeadingWhitespace), only normalized
        // -all N+1 lines get extra-indented and normalized
        // -the text start get extra-indented and normalized when following a linebreak
        final offset = snippet.offset(marker);
        if (offset == 0) {
          // snippet start
          lines[0] = normalizeIndentation(lines[0]);
        } else {
          // check if text start is after a linebreak
          snippetTextString ??= snippet.toString();
          final prevChar = snippetTextString!.codeUnitAt(offset - 1);
          if (prevChar == 0x0A || prevChar == 0x0D) {
            lines[0] = normalizeIndentation(lineLeadingWhitespace + lines[0]);
          }
        }
        for (var i = 1; i < lines.length; i++) {
          lines[i] = normalizeIndentation(lineLeadingWhitespace + lines[i]);
        }
      }

      final newValue = lines.join(eol);
      if (newValue != marker.value) {
        marker.parent!.replace(marker, [Text(newValue)]);
        snippetTextString = null;
      }
      return true;
    });

    return lineLeadingWhitespace;
  }

  /// Parses [template] once per target and returns the edits to apply and
  /// the session; call [initialize] after applying the edits.
  static SnippetInsertion create(
    String template,
    List<SnippetTarget> targets, {
    required String Function(String text) normalizeIndentation,
    required String eol,
    SnippetVariableValues? variables,
    bool adjustWhitespace = true,
    bool enforceFinalTabstop = false,
  }) {
    final sorted = List.of(targets)..sort((a, b) => a.start.compareTo(b.start));
    final edits = <SnippetEdit>[];
    final snippets = <OneSnippet>[];
    for (final target in sorted) {
      final snippet = SnippetParser().parse(
        template,
        true,
        enforceFinalTabstop,
      );
      final leading = SnippetSession.adjustWhitespace(
        target.lineText,
        target.column,
        adjustWhitespace,
        snippet,
        normalizeIndentation,
        eol,
      );
      if (variables != null) {
        snippet.resolveVariables(_Resolver(variables, target.cursorIndex));
      }
      edits.add(SnippetEdit(target.start, target.end, snippet.toString()));
      snippets.add(OneSnippet(snippet, leading));
    }
    // Where each insertion starts once all edits are applied.
    var delta = 0;
    for (var i = 0; i < edits.length; i++) {
      snippets[i].initialize(edits[i].start + delta);
      delta += edits[i].text.length - (edits[i].end - edits[i].start);
    }
    return SnippetInsertion(edits, SnippetSession._(snippets));
  }

  bool get hasPlaceholder => _snippets.firstOrNull?.hasPlaceholder ?? false;

  /// Moves each snippet's start (before its ranges are first computed) by
  /// [shifts], one per snippet in document order, for edits the caller
  /// applied together with the insertion (e.g. a completion's imports).
  void shiftStarts(List<int> shifts) {
    for (var i = 0; i < _snippets.length && i < shifts.length; i++) {
      final snippet = _snippets[i];
      if (snippet._ranges != null) throw StateError('Snippet already moved');
      snippet._offset += shifts[i];
    }
  }

  bool get isAtFirstPlaceholder => _snippets.first.isAtFirstPlaceholder;

  bool get isAtLastPlaceholder => _snippets.first.isAtLastPlaceholder;

  bool get isTrivial => _snippets.every((s) => s.isTrivialSnippet);

  SnippetActiveChoice? get activeChoice => _snippets.first.activeChoice;

  /// Maps every tracked range through sorted pre-edit `(start, end,
  /// insertedLength)` [edits].
  void acceptEdits(List<(int, int, int)> edits) {
    if (edits.isEmpty) return;
    for (final snippet in _snippets) {
      snippet.acceptEdits(edits);
    }
  }

  /// Selections for the next (`true`), previous (`false`) or current
  /// (`null`) placeholder group across all snippets.
  List<SnippetSelection> move(
    bool? fwd, {
    required String Function(int start, int end) textIn,
    required void Function(List<SnippetEdit> edits) transform,
    required String Function(String text) normalizeIndentation,
    required String eol,
  }) => [
    for (final snippet in _snippets)
      ...snippet.move(
        fwd,
        textIn: textIn,
        transform: transform,
        normalizeIndentation: normalizeIndentation,
        eol: eol,
      ),
  ];

  /// Upstream `isSelectionWithinPlaceholders`: every selection must lie in
  /// a range of one placeholder index.
  bool isSelectionWithinPlaceholders(List<(int, int)> selections) {
    if (!hasPlaceholder) return false;
    final all = <num, List<(int, int)>>{};
    for (final snippet in _snippets) {
      for (final MapEntry(:key, :value)
          in snippet.computePossibleSelections().entries) {
        all.putIfAbsent(key, () => []).addAll(value);
      }
    }
    for (final ranges in all.values) {
      final sorted = List.of(selections)..sort((a, b) => a.$1.compareTo(b.$1));
      if (sorted.length != ranges.length) continue;
      final sortedRanges = List.of(ranges)
        ..sort((a, b) => a.$1.compareTo(b.$1));
      var ok = true;
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].$1 < sortedRanges[i].$1 ||
            sorted[i].$2 > sortedRanges[i].$2) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  /// Whether [offset] is inside the snippets' enclosing ranges.
  bool containsOffset(int offset) {
    for (final snippet in _snippets) {
      final range = snippet.enclosingRange;
      if (range != null && range.$1 <= offset && offset <= range.$2) {
        return true;
      }
    }
    return false;
  }

  /// Every placeholder range: `(start, end, active, final)`.
  List<(int, int, bool, bool)> get placeholderRanges => [
    for (final snippet in _snippets) ...snippet.placeholderRanges,
  ];
}
