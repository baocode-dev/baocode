/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/folding/browser/indentRangeProvider.ts
// (and `computeIndentLevel` from src/vs/editor/common/model/utils.ts) at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// The bundled license is at lib/ide/editor/monaco/LICENSE.txt.
//
// Deviations: [computeRanges] reads lines through [FoldingLineSource] instead
// of an ITextModel, and takes the tab size directly; the async
// `IndentRangeProvider`/language-configuration-service wrapper is omitted.
// JavaScript RegExp flags are compared through Dart's RegExp properties when
// deciding whether markers can be combined into one pattern.

import 'dart:typed_data';

import '../../../common/languages/language_configuration.dart';
import 'folding_ranges.dart';

const maxFoldingRegionsForIndentDefault = 5000;

/// Upstream `FoldingLimitReporter` (folding.ts).
abstract interface class FoldingLimitReporter {
  int get limit;
  void update(int computed, Object limited);
}

class _DefaultLimitReporter implements FoldingLimitReporter {
  const _DefaultLimitReporter();

  @override
  int get limit => maxFoldingRegionsForIndentDefault;

  @override
  void update(int computed, Object limited) {}
}

/// Line access used by [computeRanges]: one-based [getLineContent].
abstract interface class FoldingLineSource {
  int get lineCount;
  String getLineContent(int lineNumber);
}

/// Returns the visible indentation of [line] in columns, or -1 when the line
/// consists only of whitespace.
int computeIndentLevel(String line, int tabSize) {
  var indent = 0;
  var i = 0;
  final len = line.length;
  while (i < len) {
    final chCode = line.codeUnitAt(i);
    if (chCode == 0x20) {
      indent++;
    } else if (chCode == 0x09) {
      indent = indent - indent % tabSize + tabSize;
    } else {
      break;
    }
    i++;
  }
  if (i == len) return -1; // line only consists of whitespace
  return indent;
}

// public only for testing
class RangesCollector {
  RangesCollector(this._foldingRangesLimit);

  final List<int> _startIndexes = [];
  final List<int> _endIndexes = [];
  final List<int> _indentOccurrences = [];
  int _length = 0;
  final FoldingLimitReporter _foldingRangesLimit;

  void insertFirst(int startLineNumber, int endLineNumber, int indent) {
    if (startLineNumber > maxLineNumber || endLineNumber > maxLineNumber) {
      return;
    }
    _startIndexes.add(startLineNumber);
    _endIndexes.add(endLineNumber);
    _length++;
    if (indent < 1000) {
      while (_indentOccurrences.length <= indent) {
        _indentOccurrences.add(0);
      }
      _indentOccurrences[indent]++;
    }
  }

  FoldingRegions toIndentRanges(FoldingLineSource model, int tabSize) {
    final limit = _foldingRangesLimit.limit;
    if (_length <= limit) {
      _foldingRangesLimit.update(_length, false);
      // reverse and create arrays of the exact length
      final startIndexes = Uint32List(_length);
      final endIndexes = Uint32List(_length);
      for (var i = _length - 1, k = 0; i >= 0; i--, k++) {
        startIndexes[k] = _startIndexes[i];
        endIndexes[k] = _endIndexes[i];
      }
      return FoldingRegions(startIndexes, endIndexes);
    }
    _foldingRangesLimit.update(_length, limit);
    var entries = 0;
    var maxIndent = _indentOccurrences.length;
    for (var i = 0; i < _indentOccurrences.length; i++) {
      final n = _indentOccurrences[i];
      if (n != 0) {
        if (n + entries > limit) {
          maxIndent = i;
          break;
        }
        entries += n;
      }
    }
    // reverse and create arrays of the exact length
    final startIndexes = Uint32List(limit);
    final endIndexes = Uint32List(limit);
    for (var i = _length - 1, k = 0; i >= 0; i--) {
      final startIndex = _startIndexes[i];
      final lineContent = model.getLineContent(startIndex);
      final indent = computeIndentLevel(lineContent, tabSize);
      if (indent < maxIndent || (indent == maxIndent && entries++ < limit)) {
        startIndexes[k] = startIndex;
        endIndexes[k] = _endIndexes[i];
        k++;
      }
    }
    return FoldingRegions(startIndexes, endIndexes);
  }
}

class _PreviousRegion {
  _PreviousRegion(this.indent, this.endAbove, this.line);

  int indent; // indent or -2 if a marker
  int endAbove; // end line number for the region above
  int line; // start line of the region. Only used for marker regions.
}

bool _sameFlags(RegExp a, RegExp b) =>
    a.isMultiLine == b.isMultiLine &&
    a.isCaseSensitive == b.isCaseSensitive &&
    a.isUnicode == b.isUnicode &&
    a.isDotAll == b.isDotAll;

FoldingRegions computeRanges(
  FoldingLineSource model,
  bool offSide, {
  FoldingMarkers? markers,
  int tabSize = 4,
  FoldingLimitReporter foldingRangesLimit = const _DefaultLimitReporter(),
}) {
  final result = RangesCollector(foldingRangesLimit);

  RegExp? pattern;
  RegExp? startPattern;
  RegExp? endPattern;
  if (markers != null) {
    if (_sameFlags(markers.start, markers.end)) {
      pattern = RegExp(
        '(${markers.start.pattern})|(?:${markers.end.pattern})',
        multiLine: markers.start.isMultiLine,
        caseSensitive: markers.start.isCaseSensitive,
        unicode: markers.start.isUnicode,
        dotAll: markers.start.isDotAll,
      );
    } else {
      startPattern = markers.start;
      endPattern = markers.end;
    }
  }

  final previousRegions = <_PreviousRegion>[];
  final sentinel = model.lineCount + 1;
  // sentinel, to make sure there's at least one entry
  previousRegions.add(_PreviousRegion(-1, sentinel, sentinel));

  for (var line = model.lineCount; line > 0; line--) {
    final lineContent = model.getLineContent(line);
    final indent = computeIndentLevel(lineContent, tabSize);
    var previous = previousRegions.last;
    if (indent == -1) {
      if (offSide) {
        // for offSide languages, empty lines are associated to the previous
        // block. note: the next block is already written to the results, so
        // this only impacts the end position of the block before
        previous.endAbove = line;
      }
      continue; // only whitespace
    }
    var isStartMatch = false;
    var isEndMatch = false;
    if (pattern != null) {
      final m = pattern.firstMatch(lineContent);
      if (m != null) {
        isStartMatch = m.group(1) != null && m.group(1)!.isNotEmpty;
        isEndMatch = !isStartMatch;
      }
    } else {
      if (startPattern != null) {
        isStartMatch = startPattern.hasMatch(lineContent);
      }
      if (!isStartMatch && endPattern != null) {
        isEndMatch = endPattern.hasMatch(lineContent);
      }
    }
    if (isStartMatch || isEndMatch) {
      // folding pattern match
      if (isStartMatch) {
        // start pattern match: discard all regions until the folding pattern
        var i = previousRegions.length - 1;
        while (i > 0 && previousRegions[i].indent != -2) {
          i--;
        }
        if (i > 0) {
          previousRegions.length = i + 1;
          previous = previousRegions[i];
          // new folding range from pattern, includes the end line
          result.insertFirst(line, previous.line, indent);
          previous.line = line;
          previous.indent = indent;
          previous.endAbove = line;
          continue;
        } else {
          // no end marker found, treat line as a regular line
        }
      } else {
        // end pattern match
        previousRegions.add(_PreviousRegion(-2, line, line));
        continue;
      }
    }
    if (previous.indent > indent) {
      // discard all regions with larger indent
      do {
        previousRegions.removeLast();
        previous = previousRegions.last;
      } while (previous.indent > indent);

      // new folding range
      final endLineNumber = previous.endAbove - 1;
      if (endLineNumber - line >= 1) {
        // needs at east size 1
        result.insertFirst(line, endLineNumber, indent);
      }
    }
    if (previous.indent == indent) {
      previous.endAbove = line;
    } else {
      // previous.indent < indent: new region with a bigger indent
      previousRegions.add(_PreviousRegion(indent, line, line));
    }
  }
  return result.toIndentRanges(model, tabSize);
}
