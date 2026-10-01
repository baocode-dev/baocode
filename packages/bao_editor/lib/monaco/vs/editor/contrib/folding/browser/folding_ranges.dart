/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/folding/browser/foldingRanges.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// The bundled license is at lib/ide/editor/monaco/LICENSE.txt.
//
// Deviations: `SelectedLines` (declared upstream in folding.ts) is included
// here as a small interface; `toString` is `debugString`. `FoldRange` is a
// mutable class because `sanitizeAndMerge` updates its entries in place, as
// upstream does with object literals.

import 'dart:typed_data';

abstract interface class ILineRange {
  int get startLineNumber;
  int get endLineNumber;
}

enum FoldSource { provider, userDefined, recovered }

const foldSourceAbbr = <FoldSource, String>{
  FoldSource.provider: ' ',
  FoldSource.userDefined: 'u',
  FoldSource.recovered: 'r',
};

class FoldRange implements ILineRange {
  FoldRange({
    required this.startLineNumber,
    required this.endLineNumber,
    this.type,
    this.isCollapsed = false,
    this.source = FoldSource.provider,
  });

  @override
  int startLineNumber;
  @override
  int endLineNumber;
  String? type;
  bool isCollapsed;
  FoldSource source;
}

/// Upstream `SelectedLines` from folding.ts.
abstract interface class SelectedLines {
  bool startsInside(int startLine, int endLine);
}

const maxFoldingRegions = 0xFFFF;
const maxLineNumber = 0xFFFFFF;

const _maskIndent = 0xFF000000;

class _BitField {
  _BitField(int size) : _states = Uint32List((size + 31) ~/ 32);

  final Uint32List _states;

  bool get(int index) {
    final arrayIndex = index ~/ 32;
    final bit = index % 32;
    return (_states[arrayIndex] & (1 << bit)) != 0;
  }

  void set(int index, bool newState) {
    final arrayIndex = index ~/ 32;
    final bit = index % 32;
    final value = _states[arrayIndex];
    _states[arrayIndex] = newState ? value | (1 << bit) : value & ~(1 << bit);
  }
}

class FoldingRegions {
  FoldingRegions(
    Uint32List startIndexes,
    Uint32List endIndexes, [
    List<String?>? types,
  ]) : _startIndexes = startIndexes,
       _endIndexes = endIndexes,
       _collapseStates = _BitField(startIndexes.length),
       _userDefinedStates = _BitField(startIndexes.length),
       _recoveredStates = _BitField(startIndexes.length),
       _types = types {
    if (startIndexes.length != endIndexes.length ||
        startIndexes.length > maxFoldingRegions) {
      throw StateError('invalid startIndexes or endIndexes size');
    }
  }

  final Uint32List _startIndexes;
  final Uint32List _endIndexes;
  final _BitField _collapseStates;
  final _BitField _userDefinedStates;
  final _BitField _recoveredStates;
  bool _parentsComputed = false;
  final List<String?>? _types;

  void _ensureParentIndices() {
    if (_parentsComputed) return;
    _parentsComputed = true;
    final parentIndexes = <int>[];
    bool isInsideLast(int startLineNumber, int endLineNumber) {
      final index = parentIndexes.last;
      return getStartLineNumber(index) <= startLineNumber &&
          getEndLineNumber(index) >= endLineNumber;
    }

    for (var i = 0; i < _startIndexes.length; i++) {
      final startLineNumber = _startIndexes[i];
      final endLineNumber = _endIndexes[i];
      if (startLineNumber > maxLineNumber || endLineNumber > maxLineNumber) {
        throw StateError(
          'startLineNumber or endLineNumber must not exceed $maxLineNumber',
        );
      }
      while (parentIndexes.isNotEmpty &&
          !isInsideLast(startLineNumber, endLineNumber)) {
        parentIndexes.removeLast();
      }
      final parentIndex = parentIndexes.isNotEmpty ? parentIndexes.last : -1;
      parentIndexes.add(i);
      // Uint32 storage wraps -1 exactly like upstream's Uint32Array.
      _startIndexes[i] = startLineNumber + ((parentIndex & 0xFF) << 24);
      _endIndexes[i] = endLineNumber + ((parentIndex & 0xFF00) << 16);
    }
  }

  int get length => _startIndexes.length;

  int getStartLineNumber(int index) => _startIndexes[index] & maxLineNumber;

  int getEndLineNumber(int index) => _endIndexes[index] & maxLineNumber;

  String? getType(int index) => _types?[index];

  bool hasTypes() => _types != null;

  bool isCollapsed(int index) => _collapseStates.get(index);

  void setCollapsed(int index, bool newState) =>
      _collapseStates.set(index, newState);

  bool _isUserDefined(int index) => _userDefinedStates.get(index);

  void _setUserDefined(int index, bool newState) =>
      _userDefinedStates.set(index, newState);

  bool _isRecovered(int index) => _recoveredStates.get(index);

  void _setRecovered(int index, bool newState) =>
      _recoveredStates.set(index, newState);

  FoldSource getSource(int index) {
    if (_isUserDefined(index)) return FoldSource.userDefined;
    if (_isRecovered(index)) return FoldSource.recovered;
    return FoldSource.provider;
  }

  void setSource(int index, FoldSource source) {
    _setUserDefined(index, source == FoldSource.userDefined);
    _setRecovered(index, source == FoldSource.recovered);
  }

  bool setCollapsedAllOfType(String type, bool newState) {
    var hasChanged = false;
    final types = _types;
    if (types != null) {
      for (var i = 0; i < types.length; i++) {
        if (types[i] == type) {
          setCollapsed(i, newState);
          hasChanged = true;
        }
      }
    }
    return hasChanged;
  }

  FoldingRegion toRegion(int index) => FoldingRegion(this, index);

  int getParentIndex(int index) {
    _ensureParentIndices();
    final parent =
        ((_startIndexes[index] & _maskIndent) >> 24) +
        ((_endIndexes[index] & _maskIndent) >> 16);
    if (parent == maxFoldingRegions) return -1;
    return parent;
  }

  bool contains(int index, int line) =>
      getStartLineNumber(index) <= line && getEndLineNumber(index) >= line;

  int _findIndex(int line) {
    var low = 0;
    var high = _startIndexes.length;
    if (high == 0) return -1; // no children
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (line < getStartLineNumber(mid)) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low - 1;
  }

  int findRange(int line) {
    var index = _findIndex(line);
    if (index >= 0) {
      final endLineNumber = getEndLineNumber(index);
      if (endLineNumber >= line) return index;
      index = getParentIndex(index);
      while (index != -1) {
        if (contains(index, line)) return index;
        index = getParentIndex(index);
      }
    }
    return -1;
  }

  /// Upstream `toString`.
  String debugString() => [
    for (var i = 0; i < length; i++)
      '[${foldSourceAbbr[getSource(i)]}${isCollapsed(i) ? '+' : '-'}] '
          '${getStartLineNumber(i)}/${getEndLineNumber(i)}',
  ].join(', ');

  FoldRange toFoldRange(int index) => FoldRange(
    startLineNumber: _startIndexes[index] & maxLineNumber,
    endLineNumber: _endIndexes[index] & maxLineNumber,
    type: _types?[index],
    isCollapsed: isCollapsed(index),
    source: getSource(index),
  );

  static FoldingRegions fromFoldRanges(List<FoldRange> ranges) {
    final rangesLength = ranges.length;
    final startIndexes = Uint32List(rangesLength);
    final endIndexes = Uint32List(rangesLength);
    List<String?>? types = [];
    var gotTypes = false;
    for (var i = 0; i < rangesLength; i++) {
      final range = ranges[i];
      startIndexes[i] = range.startLineNumber;
      endIndexes[i] = range.endLineNumber;
      types.add(range.type);
      if (range.type != null && range.type!.isNotEmpty) gotTypes = true;
    }
    if (!gotTypes) types = null;
    final regions = FoldingRegions(startIndexes, endIndexes, types);
    for (var i = 0; i < rangesLength; i++) {
      if (ranges[i].isCollapsed) regions.setCollapsed(i, true);
      regions.setSource(i, ranges[i].source);
    }
    return regions;
  }

  /// Two inputs, each a [FoldingRegions] or a `List<FoldRange>`, are merged.
  /// Each input must be pre-sorted on startLineNumber. The first list is
  /// assumed to always include all regions currently defined by range
  /// providers. The second list only contains the previously collapsed and
  /// all manual ranges. If the line position matches, the range of the new
  /// range is taken, and the range is no longer manual. When an entry in one
  /// list overlaps an entry in the other, the second list's entry "wins" and
  /// overlapping entries in the first list are discarded. Invalid entries are
  /// discarded: the start and end line numbers aren't a valid range of line
  /// numbers, it is out of sequence or has the same start line as a preceding
  /// entry, or it overlaps a preceding entry and is not fully contained by it.
  static List<FoldRange> sanitizeAndMerge(
    Object rangesA,
    Object rangesB,
    int? maxLineNumber, [
    SelectedLines? selection,
  ]) {
    final maxLine = maxLineNumber ?? (1 << 53);

    FoldRange? Function(int) indexed(Object r) {
      if (r is List<FoldRange>) {
        return (i) => i < r.length ? r[i] : null;
      }
      final regions = r as FoldingRegions;
      return (i) => i < regions.length ? regions.toFoldRange(i) : null;
    }

    final getA = indexed(rangesA);
    final getB = indexed(rangesB);
    var indexA = 0;
    var indexB = 0;
    var nextA = getA(0);
    var nextB = getB(0);

    final stackedRanges = <FoldRange>[];
    FoldRange? topStackedRange;
    var prevLineNumber = 0;
    final resultRanges = <FoldRange>[];

    while (nextA != null || nextB != null) {
      FoldRange? useRange;
      if (nextB != null &&
          (nextA == null || nextA.startLineNumber >= nextB.startLineNumber)) {
        if (nextA != null && nextA.startLineNumber == nextB.startLineNumber) {
          if (nextB.source == FoldSource.userDefined) {
            // a user defined range (possibly unfolded)
            useRange = nextB;
          } else {
            // a previously folded range or a (possibly unfolded) recovered range
            useRange = nextA;
            // stays collapsed if the range still has the same number of lines
            // or the selection is not in the range or after it
            useRange.isCollapsed =
                nextB.isCollapsed &&
                (nextA.endLineNumber == nextB.endLineNumber ||
                    !(selection?.startsInside(
                          nextA.startLineNumber + 1,
                          nextA.endLineNumber + 1,
                        ) ??
                        false));
            useRange.source = FoldSource.provider;
          }
          nextA = getA(++indexA); // not necessary, just for speed
        } else {
          useRange = nextB;
          if (nextB.isCollapsed && nextB.source == FoldSource.provider) {
            // a previously collapsed range
            useRange.source = FoldSource.recovered;
          }
        }
        nextB = getB(++indexB);
      } else {
        // nextA is next. The user folded B set takes precedence and we
        // sometimes need to look ahead in it to check for an upcoming conflict.
        var scanIndex = indexB;
        var prescanB = nextB;
        while (true) {
          if (prescanB == null ||
              prescanB.startLineNumber > nextA!.endLineNumber) {
            useRange = nextA;
            break; // no conflict, use this nextA
          }
          if (prescanB.source == FoldSource.userDefined &&
              prescanB.endLineNumber > nextA.endLineNumber) {
            // we found a user folded range, it wins
            break; // without setting nextResult, so this nextA gets skipped
          }
          prescanB = getB(++scanIndex);
        }
        nextA = getA(++indexA);
      }

      if (useRange != null) {
        while (topStackedRange != null &&
            topStackedRange.endLineNumber < useRange.startLineNumber) {
          topStackedRange = stackedRanges.isEmpty
              ? null
              : stackedRanges.removeLast();
        }
        if (useRange.endLineNumber > useRange.startLineNumber &&
            useRange.startLineNumber > prevLineNumber &&
            useRange.endLineNumber <= maxLine &&
            (topStackedRange == null ||
                topStackedRange.endLineNumber >= useRange.endLineNumber)) {
          resultRanges.add(useRange);
          prevLineNumber = useRange.startLineNumber;
          if (topStackedRange != null) stackedRanges.add(topStackedRange);
          topStackedRange = useRange;
        }
      }
    }
    return resultRanges;
  }
}

class FoldingRegion implements ILineRange {
  FoldingRegion(this._ranges, this._index);

  final FoldingRegions _ranges;
  final int _index;

  @override
  int get startLineNumber => _ranges.getStartLineNumber(_index);
  @override
  int get endLineNumber => _ranges.getEndLineNumber(_index);
  int get regionIndex => _index;
  int get parentIndex => _ranges.getParentIndex(_index);
  bool get isCollapsed => _ranges.isCollapsed(_index);

  bool containedBy(ILineRange range) =>
      range.startLineNumber <= startLineNumber &&
      range.endLineNumber >= endLineNumber;

  bool containsLine(int lineNumber) =>
      startLineNumber <= lineNumber && lineNumber <= endLineNumber;

  bool hidesLine(int lineNumber) =>
      startLineNumber < lineNumber && lineNumber <= endLineNumber;
}
