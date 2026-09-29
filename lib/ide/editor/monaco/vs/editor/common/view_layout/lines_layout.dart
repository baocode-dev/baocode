/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from src/vs/editor/common/viewLayout/linesLayout.ts at VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971.
// The bundled license is at lib/ide/editor/monaco/LICENSE.txt.

import 'dart:math' as math;

import 'line_heights.dart';
import 'view_layout_contracts.dart';

export 'view_layout_contracts.dart'
    show
        IEditorWhitespace,
        IPartialViewLinesViewportData,
        ILineHeightChangeAccessor,
        IViewWhitespaceViewportData,
        IWhitespaceChangeAccessor;

typedef _PendingChange = ({String id, int newAfterLineNumber, int newHeight});

class _PendingChanges {
  bool _hasPending = false;
  List<EditorWhitespace> _inserts = [];
  List<_PendingChange> _changes = [];
  List<String> _removes = [];

  void insert(EditorWhitespace x) {
    _hasPending = true;
    _inserts.add(x);
  }

  void change(_PendingChange x) {
    _hasPending = true;
    _changes.add(x);
  }

  void remove(String id) {
    _hasPending = true;
    _removes.add(id);
  }

  void commit(LinesLayout linesLayout) {
    if (!_hasPending) {
      return;
    }
    final inserts = _inserts;
    final changes = _changes;
    final removes = _removes;
    _hasPending = false;
    _inserts = [];
    _changes = [];
    _removes = [];
    linesLayout._commitPendingChanges(inserts, changes, removes);
  }
}

class EditorWhitespace implements IEditorWhitespace {
  EditorWhitespace(
    this.id,
    this.afterLineNumber,
    this.ordinal,
    this.height,
    this.minWidth,
  );

  @override
  String id;
  @override
  int afterLineNumber;
  int ordinal;
  @override
  num height;
  num minWidth;
  num prefixSum = 0;
}

/// Layout of text lines and whitespace/view zones that take vertical space and
/// push down subsequent objects. Whitespace prefix sums are computed lazily.
class LinesLayout {
  LinesLayout(
    this._lineCount,
    num defaultLineHeight,
    this._paddingTop,
    this._paddingBottom,
    List<CustomLineHeightData> customLineHeightData,
  ) : _instanceId = _singleLetterHash(++_instanceCount),
      _lineHeightsManager = LineHeightsManager(
        defaultLineHeight,
        customLineHeightData,
      );

  static int _instanceCount = 0;
  final String _instanceId;
  final _PendingChanges _pendingChanges = _PendingChanges();
  int _lastWhitespaceId = 0;
  List<EditorWhitespace> _arr = [];
  int _prefixSumValidIndex = -1;
  num _minWidth = -1; // Marker for not being computed.
  int _lineCount;
  num _paddingTop;
  num _paddingBottom;
  LineHeightsManager _lineHeightsManager;

  /// Equal (line, ordinal) keys are inserted after existing entries.
  static int findInsertionIndex(
    List<EditorWhitespace> arr,
    int afterLineNumber,
    int ordinal,
  ) {
    var low = 0;
    var high = arr.length;
    while (low < high) {
      final mid = (low + high) >>> 1;
      if (afterLineNumber == arr[mid].afterLineNumber) {
        if (ordinal < arr[mid].ordinal) {
          high = mid;
        } else {
          low = mid + 1;
        }
      } else if (afterLineNumber < arr[mid].afterLineNumber) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  void setDefaultLineHeight(num lineHeight) {
    _lineHeightsManager.defaultLineHeight = lineHeight;
  }

  void setPadding(num paddingTop, num paddingBottom) {
    _paddingTop = paddingTop;
    _paddingBottom = paddingBottom;
  }

  void onFlushed(
    int lineCount,
    List<CustomLineHeightData> customLineHeightData,
  ) {
    _lineCount = lineCount;
    _lineHeightsManager = LineHeightsManager(
      _lineHeightsManager.defaultLineHeight,
      customLineHeightData,
    );
  }

  bool changeLineHeights(void Function(ILineHeightChangeAccessor) callback) {
    var hadAChange = false;
    // Resolve the manager at call time, just as the upstream accessor does.
    final accessor = _LineHeightChangeAccessor(() => _lineHeightsManager, () {
      hadAChange = true;
    });
    callback(accessor);
    return hadAChange;
  }

  bool changeWhitespace(void Function(IWhitespaceChangeAccessor) callback) {
    var hadAChange = false;
    try {
      final accessor = _WhitespaceChangeAccessor(
        _pendingChanges,
        () => '$_instanceId${++_lastWhitespaceId}',
        () {
          hadAChange = true;
        },
      );
      callback(accessor);
    } finally {
      _pendingChanges.commit(this);
    }
    return hadAChange;
  }

  void _commitPendingChanges(
    List<EditorWhitespace> inserts,
    List<_PendingChange> changes,
    List<String> removes,
  ) {
    if (inserts.isNotEmpty || removes.isNotEmpty) {
      _minWidth = -1;
    }
    if (inserts.length + changes.length + removes.length <= 1) {
      // When only one thing happened, handle it "delicately".
      for (final insert in inserts) {
        _insertWhitespace(insert);
      }
      for (final change in changes) {
        _changeOneWhitespace(
          change.id,
          change.newAfterLineNumber,
          change.newHeight,
        );
      }
      for (final remove in removes) {
        final index = _findWhitespaceIndex(remove);
        if (index == -1) {
          continue;
        }
        _removeWhitespace(index);
      }
      return;
    }

    // Otherwise rebuild the data structure. Removes win; last change wins.
    final toRemove = removes.toSet();
    final toChange = <String, _PendingChange>{};
    for (final change in changes) {
      toChange[change.id] = change;
    }
    List<EditorWhitespace> applyRemoveAndChange(
      List<EditorWhitespace> whitespaces,
    ) {
      final result = <EditorWhitespace>[];
      for (final whitespace in whitespaces) {
        if (toRemove.contains(whitespace.id)) {
          continue;
        }
        final change = toChange[whitespace.id];
        if (change != null) {
          whitespace.afterLineNumber = change.newAfterLineNumber;
          whitespace.height = change.newHeight;
        }
        result.add(whitespace);
      }
      return result;
    }

    final result = [
      ...applyRemoveAndChange(_arr),
      ...applyRemoveAndChange(inserts),
    ];
    // JS Array.sort is stable; Dart List.sort is not. Preserve original order
    // for equal keys explicitly (including existing entries before new ones).
    final originalOrder = <EditorWhitespace, int>{
      for (var i = 0; i < result.length; i++) result[i]: i,
    };
    result.sort((a, b) {
      final comparison = a.afterLineNumber == b.afterLineNumber
          ? a.ordinal.compareTo(b.ordinal)
          : a.afterLineNumber.compareTo(b.afterLineNumber);
      return comparison != 0
          ? comparison
          : originalOrder[a]!.compareTo(originalOrder[b]!);
    });
    _arr = result;
    _prefixSumValidIndex = -1;
  }

  void _insertWhitespace(EditorWhitespace whitespace) {
    final insertIndex = findInsertionIndex(
      _arr,
      whitespace.afterLineNumber,
      whitespace.ordinal,
    );
    _arr.insert(insertIndex, whitespace);
    _prefixSumValidIndex = math.min(_prefixSumValidIndex, insertIndex - 1);
  }

  int _findWhitespaceIndex(String id) {
    final arr = _arr;
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id == id) {
        return i;
      }
    }
    return -1;
  }

  void _changeOneWhitespace(String id, int newAfterLineNumber, int newHeight) {
    final index = _findWhitespaceIndex(id);
    if (index == -1) {
      return;
    }
    if (_arr[index].height != newHeight) {
      _arr[index].height = newHeight;
      _prefixSumValidIndex = math.min(_prefixSumValidIndex, index - 1);
    }
    if (_arr[index].afterLineNumber != newAfterLineNumber) {
      // Moving may reorder the entry, so remove and reinsert it.
      final whitespace = _arr[index];
      _removeWhitespace(index);
      whitespace.afterLineNumber = newAfterLineNumber;
      _insertWhitespace(whitespace);
    }
  }

  void _removeWhitespace(int removeIndex) {
    _arr.removeAt(removeIndex);
    _prefixSumValidIndex = math.min(_prefixSumValidIndex, removeIndex - 1);
  }

  /// Notify the layouter that a continuous inclusive range was deleted.
  void onLinesDeleted(num fromLineNumber, num toLineNumber) {
    final from = _toInt32(fromLineNumber);
    final to = _toInt32(toLineNumber);
    _lineCount -= to - from + 1;
    for (var i = 0; i < _arr.length; i++) {
      final afterLineNumber = _arr[i].afterLineNumber;
      if (from <= afterLineNumber && afterLineNumber <= to) {
        // The anchor was deleted; move to before the first deleted line.
        _arr[i].afterLineNumber = from - 1;
      } else if (afterLineNumber > to) {
        _arr[i].afterLineNumber -= to - from + 1;
      }
    }
    _lineHeightsManager.onLinesDeleted(from, to);
  }

  /// Notify the layouter that a continuous inclusive range was inserted.
  void onLinesInserted(num fromLineNumber, num toLineNumber) {
    final from = _toInt32(fromLineNumber);
    final to = _toInt32(toLineNumber);
    _lineCount += to - from + 1;
    for (var i = 0; i < _arr.length; i++) {
      final afterLineNumber = _arr[i].afterLineNumber;
      if (from <= afterLineNumber) {
        _arr[i].afterLineNumber += to - from + 1;
      }
    }
    _lineHeightsManager.onLinesInserted(from, to);
  }

  num getWhitespacesTotalHeight() {
    if (_arr.isEmpty) {
      return 0;
    }
    return getWhitespacesAccumulatedHeight(_arr.length - 1);
  }

  /// Sum of whitespace heights at [0..index], including index.
  num getWhitespacesAccumulatedHeight(num index) {
    final target = _toInt32(index);
    var startIndex = math.max(0, _prefixSumValidIndex + 1);
    if (startIndex == 0) {
      _arr[0].prefixSum = _arr[0].height;
      startIndex++;
    }
    for (var i = startIndex; i <= target; i++) {
      _arr[i].prefixSum = _arr[i - 1].prefixSum + _arr[i].height;
    }
    _prefixSumValidIndex = math.max(_prefixSumValidIndex, target);
    return _arr[target].prefixSum;
  }

  num getLinesTotalHeight() {
    final linesHeight = _lineHeightsManager
        .getAccumulatedLineHeightsIncludingLineNumber(_lineCount);
    final whitespacesHeight = getWhitespacesTotalHeight();
    return linesHeight + whitespacesHeight + _paddingTop + _paddingBottom;
  }

  num getWhitespaceAccumulatedHeightBeforeLineNumber(num lineNumber) {
    final line = _toInt32(lineNumber);
    final lastWhitespaceBeforeLineNumber = _findLastWhitespaceBeforeLineNumber(
      line,
    );
    if (lastWhitespaceBeforeLineNumber == -1) {
      return 0;
    }
    return getWhitespacesAccumulatedHeight(lastWhitespaceBeforeLineNumber);
  }

  int _findLastWhitespaceBeforeLineNumber(int lineNumber) {
    lineNumber = _toInt32(lineNumber);
    final arr = _arr;
    var low = 0;
    var high = arr.length - 1;
    while (low <= high) {
      final delta = _toInt32(high - low);
      final halfDelta = _toInt32(delta / 2);
      final mid = _toInt32(low + halfDelta);
      if (arr[mid].afterLineNumber < lineNumber) {
        if (mid + 1 >= arr.length ||
            arr[mid + 1].afterLineNumber >= lineNumber) {
          return mid;
        } else {
          low = _toInt32(mid + 1);
        }
      } else {
        high = _toInt32(mid - 1);
      }
    }
    return -1;
  }

  int _findFirstWhitespaceAfterLineNumber(int lineNumber) {
    lineNumber = _toInt32(lineNumber);
    final lastWhitespaceBeforeLineNumber = _findLastWhitespaceBeforeLineNumber(
      lineNumber,
    );
    final firstWhitespaceAfterLineNumber = lastWhitespaceBeforeLineNumber + 1;
    if (firstWhitespaceAfterLineNumber < _arr.length) {
      return firstWhitespaceAfterLineNumber;
    }
    return -1;
  }

  /// First whitespace with afterLineNumber >= lineNumber, or -1.
  int getFirstWhitespaceIndexAfterLineNumber(num lineNumber) {
    return _findFirstWhitespaceAfterLineNumber(_toInt32(lineNumber));
  }

  num getVerticalOffsetForLineNumber(
    num lineNumber, [
    bool includeViewZones = false,
  ]) {
    final line = _toInt32(lineNumber);
    final previousLinesHeight = line > 1
        ? _lineHeightsManager.getAccumulatedLineHeightsIncludingLineNumber(
            line - 1,
          )
        : 0;
    final previousWhitespacesHeight =
        getWhitespaceAccumulatedHeightBeforeLineNumber(
          line - (includeViewZones ? 1 : 0),
        );
    return previousLinesHeight + previousWhitespacesHeight + _paddingTop;
  }

  num getLineHeightForLineNumber(int lineNumber) {
    return _lineHeightsManager.heightForLineNumber(lineNumber);
  }

  num getVerticalOffsetAfterLineNumber(
    num lineNumber, [
    bool includeViewZones = false,
  ]) {
    final line = _toInt32(lineNumber);
    final previousLinesHeight = _lineHeightsManager
        .getAccumulatedLineHeightsIncludingLineNumber(line);
    final previousWhitespacesHeight =
        getWhitespaceAccumulatedHeightBeforeLineNumber(
          line + (includeViewZones ? 1 : 0),
        );
    return previousLinesHeight + previousWhitespacesHeight + _paddingTop;
  }

  bool hasWhitespace() => getWhitespacesCount() > 0;

  /// Maximum minWidth over all whitespace entries.
  num getWhitespaceMinWidth() {
    if (_minWidth == -1) {
      num minWidth = 0;
      for (var i = 0; i < _arr.length; i++) {
        minWidth = math.max(minWidth, _arr[i].minWidth);
      }
      _minWidth = minWidth;
    }
    return _minWidth;
  }

  bool isAfterLines(num verticalOffset) {
    final totalHeight = getLinesTotalHeight();
    return verticalOffset > totalHeight;
  }

  bool isInTopPadding(num verticalOffset) {
    if (_paddingTop == 0) {
      return false;
    }
    return verticalOffset < _paddingTop;
  }

  bool isInBottomPadding(num verticalOffset) {
    if (_paddingBottom == 0) {
      return false;
    }
    final totalHeight = getLinesTotalHeight();
    return verticalOffset >= totalHeight - _paddingBottom;
  }

  /// A hit within a view zone resolves to the following line, clamped to the
  /// document. This is not simply a division by the default line height.
  int getLineNumberAtOrAfterVerticalOffset(num verticalOffset) {
    final offset = _toInt32(verticalOffset);
    if (offset < 0) {
      return 1;
    }
    final linesCount = _toInt32(_lineCount);
    var minLineNumber = 1;
    var maxLineNumber = linesCount;
    while (minLineNumber < maxLineNumber) {
      final midLineNumber = _toInt32((minLineNumber + maxLineNumber) / 2);
      final lineHeight = getLineHeightForLineNumber(midLineNumber);
      final midLineNumberVerticalOffset = _toInt32(
        getVerticalOffsetForLineNumber(midLineNumber),
      );
      if (offset >= midLineNumberVerticalOffset + lineHeight) {
        minLineNumber = midLineNumber + 1;
      } else if (offset >= midLineNumberVerticalOffset) {
        return midLineNumber;
      } else {
        maxLineNumber = midLineNumber;
      }
    }
    if (minLineNumber > linesCount) {
      return linesCount;
    }
    return minLineNumber;
  }

  /// Lines and relative offsets positioned between the viewport boundaries.
  IPartialViewLinesViewportData getLinesViewportData(
    num verticalOffset1,
    num verticalOffset2,
  ) {
    final offset1 = _toInt32(verticalOffset1);
    final offset2 = _toInt32(verticalOffset2);
    final startLineNumber = _toInt32(
      getLineNumberAtOrAfterVerticalOffset(offset1),
    );
    final startLineNumberVerticalOffset = _toInt32(
      getVerticalOffsetForLineNumber(startLineNumber),
    );
    var endLineNumber = _toInt32(_lineCount);
    var whitespaceIndex = _toInt32(
      getFirstWhitespaceIndexAfterLineNumber(startLineNumber),
    );
    final whitespaceCount = _toInt32(getWhitespacesCount());
    int currentWhitespaceHeight;
    int currentWhitespaceAfterLineNumber;
    if (whitespaceIndex == -1) {
      whitespaceIndex = whitespaceCount;
      currentWhitespaceAfterLineNumber = endLineNumber + 1;
      currentWhitespaceHeight = 0;
    } else {
      currentWhitespaceAfterLineNumber = _toInt32(
        getAfterLineNumberForWhitespaceIndex(whitespaceIndex),
      );
      currentWhitespaceHeight = _toInt32(
        getHeightForWhitespaceIndex(whitespaceIndex),
      );
    }
    num currentVerticalOffset = startLineNumberVerticalOffset;
    num currentLineRelativeOffset = currentVerticalOffset;

    // Upstream's large-coordinate rebasing, aligned to default line increments.
    const stepSize = 500000;
    num bigNumbersDelta = 0;
    if (startLineNumberVerticalOffset >= stepSize) {
      bigNumbersDelta =
          (startLineNumberVerticalOffset / stepSize).floor() * stepSize;
      bigNumbersDelta =
          (bigNumbersDelta / _lineHeightsManager.defaultLineHeight).floor() *
          _lineHeightsManager.defaultLineHeight;
      currentLineRelativeOffset -= bigNumbersDelta;
    }
    final linesOffsets = <num>[];
    final verticalCenter = offset1 + (offset2 - offset1) / 2;
    var centeredLineNumber = -1;
    for (
      var lineNumber = startLineNumber;
      lineNumber <= endLineNumber;
      lineNumber++
    ) {
      final lineHeight = getLineHeightForLineNumber(lineNumber);
      if (centeredLineNumber == -1) {
        final currentLineTop = currentVerticalOffset;
        final currentLineBottom = currentVerticalOffset + lineHeight;
        if ((currentLineTop <= verticalCenter &&
                verticalCenter < currentLineBottom) ||
            currentLineTop > verticalCenter) {
          centeredLineNumber = lineNumber;
        }
      }
      currentVerticalOffset += lineHeight;
      linesOffsets.add(currentLineRelativeOffset);
      currentLineRelativeOffset += lineHeight;
      while (currentWhitespaceAfterLineNumber == lineNumber) {
        currentLineRelativeOffset += currentWhitespaceHeight;
        currentVerticalOffset += currentWhitespaceHeight;
        whitespaceIndex++;
        if (whitespaceIndex >= whitespaceCount) {
          currentWhitespaceAfterLineNumber = endLineNumber + 1;
        } else {
          currentWhitespaceAfterLineNumber = _toInt32(
            getAfterLineNumberForWhitespaceIndex(whitespaceIndex),
          );
          currentWhitespaceHeight = _toInt32(
            getHeightForWhitespaceIndex(whitespaceIndex),
          );
        }
      }
      if (currentVerticalOffset >= offset2) {
        endLineNumber = lineNumber;
        break;
      }
    }
    if (centeredLineNumber == -1) {
      centeredLineNumber = endLineNumber;
    }
    final endLineNumberVerticalOffset = _toInt32(
      getVerticalOffsetForLineNumber(endLineNumber),
    );
    var completelyVisibleStartLineNumber = startLineNumber;
    var completelyVisibleEndLineNumber = endLineNumber;
    if (completelyVisibleStartLineNumber < completelyVisibleEndLineNumber) {
      if (startLineNumberVerticalOffset < offset1) {
        completelyVisibleStartLineNumber++;
      }
    }
    if (completelyVisibleStartLineNumber < completelyVisibleEndLineNumber) {
      final endLineHeight = getLineHeightForLineNumber(endLineNumber);
      if (endLineNumberVerticalOffset + endLineHeight > offset2) {
        completelyVisibleEndLineNumber--;
      }
    }
    return IPartialViewLinesViewportData(
      bigNumbersDelta: bigNumbersDelta,
      startLineNumber: startLineNumber,
      endLineNumber: endLineNumber,
      relativeVerticalOffset: linesOffsets,
      centeredLineNumber: centeredLineNumber,
      completelyVisibleStartLineNumber: completelyVisibleStartLineNumber,
      completelyVisibleEndLineNumber: completelyVisibleEndLineNumber,
      lineHeight: _lineHeightsManager.defaultLineHeight,
    );
  }

  num getVerticalOffsetForWhitespaceIndex(num whitespaceIndex) {
    final index = _toInt32(whitespaceIndex);
    final afterLineNumber = getAfterLineNumberForWhitespaceIndex(index);
    final previousLinesHeight = afterLineNumber >= 1
        ? _lineHeightsManager.getAccumulatedLineHeightsIncludingLineNumber(
            afterLineNumber,
          )
        : 0;
    final previousWhitespacesHeight = index > 0
        ? getWhitespacesAccumulatedHeight(index - 1)
        : 0;
    return previousLinesHeight + previousWhitespacesHeight + _paddingTop;
  }

  // The spelling "Verticall" is part of the upstream API.
  int getWhitespaceIndexAtOrAfterVerticallOffset(num verticalOffset) {
    final offset = _toInt32(verticalOffset);
    var minWhitespaceIndex = 0;
    var maxWhitespaceIndex = getWhitespacesCount() - 1;
    if (maxWhitespaceIndex < 0) {
      return -1;
    }
    final maxWhitespaceVerticalOffset = getVerticalOffsetForWhitespaceIndex(
      maxWhitespaceIndex,
    );
    final maxWhitespaceHeight = getHeightForWhitespaceIndex(maxWhitespaceIndex);
    if (offset >= maxWhitespaceVerticalOffset + maxWhitespaceHeight) {
      return -1;
    }
    while (minWhitespaceIndex < maxWhitespaceIndex) {
      final midWhitespaceIndex = ((minWhitespaceIndex + maxWhitespaceIndex) / 2)
          .floor();
      final midWhitespaceVerticalOffset = getVerticalOffsetForWhitespaceIndex(
        midWhitespaceIndex,
      );
      final midWhitespaceHeight = getHeightForWhitespaceIndex(
        midWhitespaceIndex,
      );
      if (offset >= midWhitespaceVerticalOffset + midWhitespaceHeight) {
        minWhitespaceIndex = midWhitespaceIndex + 1;
      } else if (offset >= midWhitespaceVerticalOffset) {
        return midWhitespaceIndex;
      } else {
        maxWhitespaceIndex = midWhitespaceIndex;
      }
    }
    return minWhitespaceIndex;
  }

  /// Exactly the whitespace containing the offset, or null.
  IViewWhitespaceViewportData? getWhitespaceAtVerticalOffset(
    num verticalOffset,
  ) {
    final offset = _toInt32(verticalOffset);
    final candidateIndex = getWhitespaceIndexAtOrAfterVerticallOffset(offset);
    if (candidateIndex < 0) {
      return null;
    }
    if (candidateIndex >= getWhitespacesCount()) {
      return null;
    }
    final candidateTop = getVerticalOffsetForWhitespaceIndex(candidateIndex);
    if (candidateTop > offset) {
      return null;
    }
    final candidateHeight = getHeightForWhitespaceIndex(candidateIndex);
    final candidateId = getIdForWhitespaceIndex(candidateIndex);
    final candidateAfterLineNumber = getAfterLineNumberForWhitespaceIndex(
      candidateIndex,
    );
    return (
      id: candidateId,
      afterLineNumber: candidateAfterLineNumber,
      verticalOffset: candidateTop,
      height: candidateHeight,
    );
  }

  List<IViewWhitespaceViewportData> getWhitespaceViewportData(
    num verticalOffset1,
    num verticalOffset2,
  ) {
    final offset1 = _toInt32(verticalOffset1);
    final offset2 = _toInt32(verticalOffset2);
    final startIndex = getWhitespaceIndexAtOrAfterVerticallOffset(offset1);
    final endIndex = getWhitespacesCount() - 1;
    if (startIndex < 0) {
      return [];
    }
    final result = <IViewWhitespaceViewportData>[];
    for (var i = startIndex; i <= endIndex; i++) {
      final top = getVerticalOffsetForWhitespaceIndex(i);
      final height = getHeightForWhitespaceIndex(i);
      if (top >= offset2) {
        break;
      }
      result.add((
        id: getIdForWhitespaceIndex(i),
        afterLineNumber: getAfterLineNumberForWhitespaceIndex(i),
        verticalOffset: top,
        height: height,
      ));
    }
    return result;
  }

  /// A shallow copy, matching the upstream slice(0).
  List<IEditorWhitespace> getWhitespaces() => List<IEditorWhitespace>.of(_arr);
  int getWhitespacesCount() => _arr.length;
  String getIdForWhitespaceIndex(num index) => _arr[_toInt32(index)].id;
  int getAfterLineNumberForWhitespaceIndex(num index) =>
      _arr[_toInt32(index)].afterLineNumber;
  num getHeightForWhitespaceIndex(num index) => _arr[_toInt32(index)].height;
}

class _LineHeightChangeAccessor implements ILineHeightChangeAccessor {
  _LineHeightChangeAccessor(this._manager, this._onChange);
  final LineHeightsManager Function() _manager;
  final void Function() _onChange;

  @override
  void insertOrChangeCustomLineHeight(
    String decorationId,
    int startLineNumber,
    int endLineNumber,
    num lineHeight,
  ) {
    _onChange();
    _manager().insertOrChangeCustomLineHeight(
      decorationId,
      startLineNumber,
      endLineNumber,
      lineHeight,
    );
  }

  @override
  void removeCustomLineHeight(String decorationId) {
    _onChange();
    _manager().removeCustomLineHeight(decorationId);
  }
}

class _WhitespaceChangeAccessor implements IWhitespaceChangeAccessor {
  _WhitespaceChangeAccessor(this._pendingChanges, this._newId, this._onChange);
  final _PendingChanges _pendingChanges;
  final String Function() _newId;
  final void Function() _onChange;

  @override
  String insertWhitespace(
    num afterLineNumber,
    num ordinal,
    num heightInPx,
    num minWidth,
  ) {
    _onChange();
    final id = _newId();
    _pendingChanges.insert(
      EditorWhitespace(
        id,
        _toInt32(afterLineNumber),
        _toInt32(ordinal),
        _toInt32(heightInPx),
        _toInt32(minWidth),
      ),
    );
    return id;
  }

  @override
  void changeOneWhitespace(String id, num newAfterLineNumber, num newHeight) {
    _onChange();
    _pendingChanges.change((
      id: id,
      newAfterLineNumber: _toInt32(newAfterLineNumber),
      newHeight: _toInt32(newHeight),
    ));
  }

  @override
  void removeWhitespace(String id) {
    _onChange();
    _pendingChanges.remove(id);
  }
}

// JavaScript's `number | 0`: truncate, wrap to signed 32 bits, nonfinite -> 0.
int _toInt32(num value) {
  if (value is int) {
    return value.toSigned(32);
  }
  if (!value.isFinite || value == 0) {
    return 0;
  }
  return (value.truncateToDouble() % 0x100000000).toInt().toSigned(32);
}

// Inlined base/common/strings.ts singleLetterHash.
String _singleLetterHash(int n) {
  const lettersCount = 26;
  n %= 2 * lettersCount;
  return String.fromCharCode(n < lettersCount ? 97 + n : 65 + n - lettersCount);
}
