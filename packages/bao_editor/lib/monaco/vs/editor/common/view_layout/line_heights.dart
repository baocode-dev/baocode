/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from src/vs/editor/common/viewLayout/lineHeights.ts at VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971.
// The bundled license is at lib/monaco/LICENSE.txt.

import 'dart:math' as math;

import 'view_layout_contracts.dart';

sealed class _PendingChange {
  const _PendingChange();
}

final class _InsertOrChange extends _PendingChange {
  const _InsertOrChange(
    this.decorationId,
    this.startLineNumber,
    this.endLineNumber,
    this.lineHeight,
  );

  final String decorationId;
  final int startLineNumber;
  final int endLineNumber;
  final num lineHeight;
}

final class _Remove extends _PendingChange {
  const _Remove(this.decorationId);
  final String decorationId;
}

final class _LinesDeleted extends _PendingChange {
  const _LinesDeleted(this.fromLineNumber, this.toLineNumber);
  final int fromLineNumber;
  final int toLineNumber;
}

final class _LinesInserted extends _PendingChange {
  const _LinesInserted(this.fromLineNumber, this.toLineNumber);
  final int fromLineNumber;
  final int toLineNumber;
}

class CustomLine {
  CustomLine(
    this.decorationId,
    this.index,
    this.lineNumber,
    num specialHeight,
    this.prefixSum,
  ) : specialHeight = _round(specialHeight),
      maximumSpecialHeight = _round(specialHeight);

  int index;
  int lineNumber;
  num specialHeight;
  num prefixSum;
  num maximumSpecialHeight;
  String decorationId;
  bool deleted = false;

  // Math.round ties towards positive infinity, unlike Dart's num.round.
  static num _round(num value) {
    if (value is int || !value.isFinite || value == 0) {
      return value;
    }
    final floor = value.floorToDouble();
    final result = value - floor < 0.5 ? floor : floor + 1;
    return result == 0 && value < 0 ? -0.0 : result;
  }
}

/// Manages default and decoration-specific line heights using an ordered array,
/// binary searches and prefix sums. Reads commit queued changes. Each decorated
/// line retains its decoration ID; overlapping decorations use the maximum.
/// Structural changes flush staged decorations before moving/collapsing them.
class LineHeightsManager {
  LineHeightsManager(
    this._defaultLineHeight,
    List<CustomLineHeightData> customLineHeightData,
  ) {
    for (final data in customLineHeightData) {
      insertOrChangeCustomLineHeight(
        data.decorationId,
        data.startLineNumber,
        data.endLineNumber,
        data.lineHeight,
      );
    }
  }

  _ArrayMap<String, CustomLine> _decorationIDToCustomLine = _ArrayMap();
  List<CustomLine> _orderedCustomLines = [];
  List<_PendingChange> _pendingChanges = [];
  // null is the upstream Infinity sentinel (no invalid entries).
  int? _invalidIndex;
  num _defaultLineHeight;
  bool _hasPending = false;

  set defaultLineHeight(num defaultLineHeight) {
    // Deliberately matches the pinned setter, including its cache behavior.
    _defaultLineHeight = defaultLineHeight;
  }

  // Keep the upstream accessor boundary without adding cache invalidation.
  // ignore: unnecessary_getters_setters
  num get defaultLineHeight => _defaultLineHeight;

  void removeCustomLineHeight(String decorationID) {
    _pendingChanges.add(_Remove(decorationID));
    _hasPending = true;
  }

  void insertOrChangeCustomLineHeight(
    String decorationId,
    int startLineNumber,
    int endLineNumber,
    num lineHeight,
  ) {
    _pendingChanges.add(
      _InsertOrChange(decorationId, startLineNumber, endLineNumber, lineHeight),
    );
    _hasPending = true;
  }

  num heightForLineNumber(int lineNumber) {
    _commit();
    final searchIndex = _binarySearchOverOrderedCustomLinesArray(lineNumber);
    if (searchIndex >= 0) {
      return _orderedCustomLines[searchIndex].maximumSpecialHeight;
    }
    return _defaultLineHeight;
  }

  num getAccumulatedLineHeightsIncludingLineNumber(int lineNumber) {
    _commit();
    final searchIndex = _binarySearchOverOrderedCustomLinesArray(lineNumber);
    if (searchIndex >= 0) {
      return _orderedCustomLines[searchIndex].prefixSum +
          _orderedCustomLines[searchIndex].maximumSpecialHeight;
    }
    if (searchIndex == -1) {
      return _defaultLineHeight * lineNumber;
    }
    final modifiedIndex = -(searchIndex + 1);
    final previousSpecialLine = _orderedCustomLines[modifiedIndex - 1];
    return previousSpecialLine.prefixSum +
        previousSpecialLine.maximumSpecialHeight +
        _defaultLineHeight * (lineNumber - previousSpecialLine.lineNumber);
  }

  void onLinesDeleted(int fromLineNumber, int toLineNumber) {
    _pendingChanges.add(_LinesDeleted(fromLineNumber, toLineNumber));
    _hasPending = true;
  }

  void onLinesInserted(int fromLineNumber, int toLineNumber) {
    _pendingChanges.add(_LinesInserted(fromLineNumber, toLineNumber));
    _hasPending = true;
  }

  void _commit() {
    if (!_hasPending) {
      return;
    }
    final changes = _pendingChanges;
    _pendingChanges = [];
    _hasPending = false;

    final stagedInserts = <CustomLine>[];
    final stagedIdMap = _ArrayMap<String, CustomLine>();
    for (final change in changes) {
      switch (change) {
        case _Remove():
          _doRemoveCustomLineHeight(change.decorationId, stagedIdMap);
        case _InsertOrChange():
          _doInsertOrChangeCustomLineHeight(
            change.decorationId,
            change.startLineNumber,
            change.endLineNumber,
            change.lineHeight,
            stagedInserts,
            stagedIdMap,
          );
        case _LinesDeleted():
          _flushStagedDecorationChanges(stagedInserts, stagedIdMap);
          _doLinesDeleted(change.fromLineNumber, change.toLineNumber);
        case _LinesInserted():
          _flushStagedDecorationChanges(stagedInserts, stagedIdMap);
          _doLinesInserted(
            change.fromLineNumber,
            change.toLineNumber,
            stagedInserts,
            stagedIdMap,
          );
      }
    }
    _flushStagedDecorationChanges(stagedInserts, stagedIdMap);
  }

  void _doRemoveCustomLineHeight(
    String decorationID,
    _ArrayMap<String, CustomLine> stagedIdMap,
  ) {
    final customLines = _decorationIDToCustomLine.get(decorationID);
    if (customLines != null) {
      _decorationIDToCustomLine.delete(decorationID);
      for (final customLine in customLines) {
        customLine.deleted = true;
        _invalidIndex = math.min(
          _invalidIndex ?? customLine.index,
          customLine.index,
        );
      }
    }
    final stagedLines = stagedIdMap.get(decorationID);
    if (stagedLines != null) {
      stagedIdMap.delete(decorationID);
      for (final line in stagedLines) {
        line.deleted = true;
      }
    }
  }

  void _doInsertOrChangeCustomLineHeight(
    String decorationId,
    int startLineNumber,
    int endLineNumber,
    num lineHeight,
    List<CustomLine> stagedInserts,
    _ArrayMap<String, CustomLine> stagedIdMap,
  ) {
    _doRemoveCustomLineHeight(decorationId, stagedIdMap);
    for (
      var lineNumber = startLineNumber;
      lineNumber <= endLineNumber;
      lineNumber++
    ) {
      final customLine = CustomLine(
        decorationId,
        -1,
        lineNumber,
        lineHeight,
        0,
      );
      stagedInserts.add(customLine);
      stagedIdMap.add(decorationId, customLine);
    }
  }

  void _flushStagedDecorationChanges(
    List<CustomLine> stagedInserts,
    _ArrayMap<String, CustomLine> stagedIdMap,
  ) {
    if (stagedInserts.isEmpty && _invalidIndex == null) {
      return;
    }
    for (final pendingChange in stagedInserts) {
      if (pendingChange.deleted) {
        continue;
      }
      final candidateInsertionIndex = _binarySearchOverOrderedCustomLinesArray(
        pendingChange.lineNumber,
      );
      final insertionIndex = candidateInsertionIndex >= 0
          ? candidateInsertionIndex
          : -(candidateInsertionIndex + 1);
      _orderedCustomLines.insert(insertionIndex, pendingChange);
      _invalidIndex = math.min(_invalidIndex ?? insertionIndex, insertionIndex);
    }
    stagedInserts.clear();
    stagedIdMap.clear();
    final invalidIndex = _invalidIndex;
    if (invalidIndex == null) {
      return;
    }
    final newDecorationIDToSpecialLine = _ArrayMap<String, CustomLine>();
    final newOrderedSpecialLines = <CustomLine>[];

    for (var i = 0; i < invalidIndex; i++) {
      final customLine = _orderedCustomLines[i];
      newOrderedSpecialLines.add(customLine);
      newDecorationIDToSpecialLine.add(customLine.decorationId, customLine);
    }

    var numberOfDeletions = 0;
    CustomLine? previousSpecialLine = invalidIndex > 0
        ? newOrderedSpecialLines[invalidIndex - 1]
        : null;
    for (var i = invalidIndex; i < _orderedCustomLines.length; i++) {
      final customLine = _orderedCustomLines[i];
      if (customLine.deleted) {
        numberOfDeletions++;
        continue;
      }
      customLine.index = i - numberOfDeletions;
      if (previousSpecialLine != null &&
          previousSpecialLine.lineNumber == customLine.lineNumber) {
        customLine.maximumSpecialHeight =
            previousSpecialLine.maximumSpecialHeight;
        customLine.prefixSum = previousSpecialLine.prefixSum;
      } else {
        var maximumSpecialHeight = customLine.specialHeight;
        for (var j = i; j < _orderedCustomLines.length; j++) {
          final nextSpecialLine = _orderedCustomLines[j];
          if (nextSpecialLine.deleted) {
            continue;
          }
          if (nextSpecialLine.lineNumber != customLine.lineNumber) {
            break;
          }
          maximumSpecialHeight = math.max(
            maximumSpecialHeight,
            nextSpecialLine.specialHeight,
          );
        }
        customLine.maximumSpecialHeight = maximumSpecialHeight;

        num prefixSum;
        if (previousSpecialLine != null) {
          prefixSum =
              previousSpecialLine.prefixSum +
              previousSpecialLine.maximumSpecialHeight +
              _defaultLineHeight *
                  (customLine.lineNumber - previousSpecialLine.lineNumber - 1);
        } else {
          prefixSum = _defaultLineHeight * (customLine.lineNumber - 1);
        }
        customLine.prefixSum = prefixSum;
      }
      previousSpecialLine = customLine;
      newOrderedSpecialLines.add(customLine);
      newDecorationIDToSpecialLine.add(customLine.decorationId, customLine);
    }
    _orderedCustomLines = newOrderedSpecialLines;
    _decorationIDToCustomLine = newDecorationIDToSpecialLine;
    _invalidIndex = null;
  }

  void _doLinesDeleted(int fromLineNumber, int toLineNumber) {
    final deleteCount = toLineNumber - fromLineNumber + 1;
    final numberOfCustomLines = _orderedCustomLines.length;
    final candidateStartIndexOfDeletion =
        _binarySearchOverOrderedCustomLinesArray(fromLineNumber);
    int startIndexOfDeletion;
    if (candidateStartIndexOfDeletion >= 0) {
      startIndexOfDeletion = candidateStartIndexOfDeletion;
      for (var i = candidateStartIndexOfDeletion - 1; i >= 0; i--) {
        if (_orderedCustomLines[i].lineNumber == fromLineNumber) {
          startIndexOfDeletion--;
        } else {
          break;
        }
      }
    } else {
      startIndexOfDeletion =
          candidateStartIndexOfDeletion == -(numberOfCustomLines + 1) &&
              candidateStartIndexOfDeletion != -1
          ? numberOfCustomLines - 1
          : -(candidateStartIndexOfDeletion + 1);
    }
    final candidateEndIndexOfDeletion =
        _binarySearchOverOrderedCustomLinesArray(toLineNumber);
    int endIndexOfDeletion;
    if (candidateEndIndexOfDeletion >= 0) {
      endIndexOfDeletion = candidateEndIndexOfDeletion;
      for (
        var i = candidateEndIndexOfDeletion + 1;
        i < numberOfCustomLines;
        i++
      ) {
        if (_orderedCustomLines[i].lineNumber == toLineNumber) {
          endIndexOfDeletion++;
        } else {
          break;
        }
      }
    } else {
      endIndexOfDeletion =
          candidateEndIndexOfDeletion == -(numberOfCustomLines + 1) &&
              candidateEndIndexOfDeletion != -1
          ? numberOfCustomLines - 1
          : -(candidateEndIndexOfDeletion + 1);
    }
    final isEndIndexBiggerThanStartIndex =
        endIndexOfDeletion > startIndexOfDeletion;
    final isEndIndexEqualToStartIndexAndCoversCustomLine =
        endIndexOfDeletion == startIndexOfDeletion &&
        startIndexOfDeletion < _orderedCustomLines.length &&
        _orderedCustomLines[startIndexOfDeletion].lineNumber >=
            fromLineNumber &&
        _orderedCustomLines[startIndexOfDeletion].lineNumber <= toLineNumber;

    if (isEndIndexBiggerThanStartIndex ||
        isEndIndexEqualToStartIndexAndCoversCustomLine) {
      num maximumSpecialHeightOnDeletedInterval = 0;
      for (var i = startIndexOfDeletion; i <= endIndexOfDeletion; i++) {
        maximumSpecialHeightOnDeletedInterval = math.max(
          maximumSpecialHeightOnDeletedInterval,
          _orderedCustomLines[i].maximumSpecialHeight,
        );
      }
      num prefixSumOnDeletedInterval = 0;
      if (startIndexOfDeletion > 0) {
        final previousSpecialLine =
            _orderedCustomLines[startIndexOfDeletion - 1];
        prefixSumOnDeletedInterval =
            previousSpecialLine.prefixSum +
            previousSpecialLine.maximumSpecialHeight +
            _defaultLineHeight *
                (fromLineNumber - previousSpecialLine.lineNumber - 1);
      } else {
        prefixSumOnDeletedInterval = fromLineNumber > 0
            ? (fromLineNumber - 1) * _defaultLineHeight
            : 0;
      }
      final firstSpecialLineDeleted = _orderedCustomLines[startIndexOfDeletion];
      final lastSpecialLineDeleted = _orderedCustomLines[endIndexOfDeletion];
      final firstSpecialLineAfterDeletion =
          endIndexOfDeletion + 1 < _orderedCustomLines.length
          ? _orderedCustomLines[endIndexOfDeletion + 1]
          : null;
      final heightOfFirstLineAfterDeletion =
          firstSpecialLineAfterDeletion != null &&
              firstSpecialLineAfterDeletion.lineNumber == toLineNumber + 1
          ? firstSpecialLineAfterDeletion.maximumSpecialHeight
          : _defaultLineHeight;
      final totalHeightDeleted =
          lastSpecialLineDeleted.prefixSum +
          lastSpecialLineDeleted.maximumSpecialHeight -
          firstSpecialLineDeleted.prefixSum +
          _defaultLineHeight *
              (toLineNumber - lastSpecialLineDeleted.lineNumber) +
          _defaultLineHeight *
              (firstSpecialLineDeleted.lineNumber - fromLineNumber) +
          heightOfFirstLineAfterDeletion -
          maximumSpecialHeightOnDeletedInterval;

      final decorationIdsSeen = <String>{};
      final newOrderedCustomLines = <CustomLine>[];
      final newDecorationIDToSpecialLine = _ArrayMap<String, CustomLine>();
      var numberOfDeletions = 0;
      for (var i = 0; i < _orderedCustomLines.length; i++) {
        final customLine = _orderedCustomLines[i];
        if (i < startIndexOfDeletion) {
          newOrderedCustomLines.add(customLine);
          newDecorationIDToSpecialLine.add(customLine.decorationId, customLine);
        } else if (i >= startIndexOfDeletion && i <= endIndexOfDeletion) {
          final decorationId = customLine.decorationId;
          if (!decorationIdsSeen.contains(decorationId)) {
            customLine.index -= numberOfDeletions;
            customLine.lineNumber = fromLineNumber;
            customLine.prefixSum = prefixSumOnDeletedInterval;
            customLine.maximumSpecialHeight =
                maximumSpecialHeightOnDeletedInterval;
            newOrderedCustomLines.add(customLine);
            newDecorationIDToSpecialLine.add(
              customLine.decorationId,
              customLine,
            );
          } else {
            numberOfDeletions++;
          }
        } else if (i > endIndexOfDeletion) {
          customLine.index -= numberOfDeletions;
          customLine.lineNumber -= deleteCount;
          customLine.prefixSum -= totalHeightDeleted;
          newOrderedCustomLines.add(customLine);
          newDecorationIDToSpecialLine.add(customLine.decorationId, customLine);
        }
        decorationIdsSeen.add(customLine.decorationId);
      }
      _orderedCustomLines = newOrderedCustomLines;
      _decorationIDToCustomLine = newDecorationIDToSpecialLine;
    } else {
      final totalHeightDeleted = deleteCount * _defaultLineHeight;
      for (var i = endIndexOfDeletion; i < _orderedCustomLines.length; i++) {
        final customLine = _orderedCustomLines[i];
        if (customLine.lineNumber > toLineNumber) {
          customLine.lineNumber -= deleteCount;
          customLine.prefixSum -= totalHeightDeleted;
        }
      }
    }
  }

  void _doLinesInserted(
    int fromLineNumber,
    int toLineNumber,
    List<CustomLine> stagedInserts,
    _ArrayMap<String, CustomLine> stagedIdMap,
  ) {
    final insertCount = toLineNumber - fromLineNumber + 1;
    final candidateStartIndexOfInsertion =
        _binarySearchOverOrderedCustomLinesArray(fromLineNumber);
    int startIndexOfInsertion;
    if (candidateStartIndexOfInsertion >= 0) {
      startIndexOfInsertion = candidateStartIndexOfInsertion;
      for (var i = candidateStartIndexOfInsertion - 1; i >= 0; i--) {
        if (_orderedCustomLines[i].lineNumber == fromLineNumber) {
          startIndexOfInsertion--;
        } else {
          break;
        }
      }
    } else {
      startIndexOfInsertion = -(candidateStartIndexOfInsertion + 1);
    }
    final toReAdd = <CustomLineHeightData>[];
    final decorationsImmediatelyAfter = <String>{};
    for (var i = startIndexOfInsertion; i < _orderedCustomLines.length; i++) {
      if (_orderedCustomLines[i].lineNumber == fromLineNumber) {
        decorationsImmediatelyAfter.add(_orderedCustomLines[i].decorationId);
      }
    }
    final decorationsImmediatelyBefore = <String>{};
    for (var i = startIndexOfInsertion - 1; i >= 0; i--) {
      if (_orderedCustomLines[i].lineNumber == fromLineNumber - 1) {
        decorationsImmediatelyBefore.add(_orderedCustomLines[i].decorationId);
      }
    }
    // collections.intersection iterates the second set, preserving its order.
    final decorationsWithGaps = decorationsImmediatelyAfter
        .where(decorationsImmediatelyBefore.contains)
        .toSet();
    final prefixSumToAdd = insertCount * _defaultLineHeight;
    for (var i = startIndexOfInsertion; i < _orderedCustomLines.length; i++) {
      _orderedCustomLines[i].lineNumber += insertCount;
      _orderedCustomLines[i].prefixSum += prefixSumToAdd;
    }

    if (decorationsWithGaps.isNotEmpty) {
      for (final decorationId in decorationsWithGaps) {
        final decoration = _decorationIDToCustomLine.get(decorationId);
        if (decoration != null) {
          final startLineNumber = decoration.fold<int>(
            fromLineNumber,
            (min, l) => math.min(min, l.lineNumber),
          );
          final endLineNumber = decoration.fold<int>(
            fromLineNumber,
            (max, l) => math.max(max, l.lineNumber),
          );
          final lineHeight = decoration.fold<num>(
            0,
            (max, l) => math.max(max, l.specialHeight),
          );
          toReAdd.add(
            CustomLineHeightData(
              decorationId,
              startLineNumber,
              endLineNumber,
              lineHeight,
            ),
          );
        }
      }
      for (final dec in toReAdd) {
        _doInsertOrChangeCustomLineHeight(
          dec.decorationId,
          dec.startLineNumber,
          dec.endLineNumber,
          dec.lineHeight,
          stagedInserts,
          stagedIdMap,
        );
      }
    }
  }

  int _binarySearchOverOrderedCustomLinesArray(int lineNumber) {
    // Inlined base/common/arrays.ts binarySearch2, including its insertion encoding.
    var low = 0;
    var high = _orderedCustomLines.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final line = _orderedCustomLines[mid];
      if (line.lineNumber < lineNumber) {
        low = mid + 1;
      } else if (line.lineNumber > lineNumber) {
        high = mid - 1;
      } else {
        return mid;
      }
    }
    return -(low + 1);
  }
}

class CustomLineHeightData {
  const CustomLineHeightData(
    this.decorationId,
    this.startLineNumber,
    this.endLineNumber,
    this.lineHeight,
  );

  final String decorationId;
  final int startLineNumber;
  final int endLineNumber;
  final num lineHeight;

  static List<CustomLineHeightData> fromDecorations(
    List<IModelDecoration> decorations,
    ICoordinatesConverter coordinatesConverter,
    IEditorConfiguration configuration,
  ) {
    final defaultLineHeight = configuration.options.get(
      EditorOption.lineHeight,
    );
    return decorations.map((d) {
      final viewRange = coordinatesConverter.convertModelRangeToViewRange(
        d.range,
      );
      final multiplier = d.options.lineHeight;
      return CustomLineHeightData(
        d.id,
        viewRange.startLineNumber,
        viewRange.endLineNumber,
        // JavaScript numeric truthiness also treats NaN as false.
        multiplier != null && multiplier != 0 && !multiplier.isNaN
            ? multiplier * defaultLineHeight
            : 0,
      );
    }).toList();
  }
}

class _ArrayMap<K, T> {
  final Map<K, List<T>> _map = {};

  void add(K key, T value) {
    (_map[key] ??= []).add(value);
  }

  List<T>? get(K key) => _map[key];
  void delete(K key) => _map.remove(key);
  void clear() => _map.clear();
}
