// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/Buffer.ts (c58ea36).

import '../circular_list.dart';
import '../data/charsets.dart';
import '../lifecycle.dart';
import '../services/services.dart';
import '../task_queue.dart';
import '../types.dart';
import 'attribute_data.dart';
import 'buffer_line.dart';
import 'buffer_reflow.dart';
import 'cell_data.dart';
import 'constants.dart';
import 'marker.dart';
import 'types.dart';

/// 2^32 - 1
const int maxBufferSize = 4294967295;

/// Pending insertions of [Buffer._reflowSmaller].
class _ToInsert {
  _ToInsert(this.start, this.newLines);

  final int start;
  final List<BufferLine> newLines;
}

/// This class represents a terminal buffer (an internal state of the
/// terminal), where the following information is stored (in high-level):
///   - text content of this particular buffer
///   - cursor position
///   - scroll position
class Buffer extends Disposable implements IBuffer {
  Buffer(
    this._hasScrollback,
    this._optionsService,
    this._bufferService,
    this._logService,
  ) {
    _cols = _bufferService.cols;
    _rows = _bufferService.rows;
    lines = CircularList<IBufferLine>(_getCorrectBufferLength(_rows));
    scrollTop = 0;
    scrollBottom = _rows - 1;
    setupTabStops();
    _memoryCleanupQueue = IdleTaskQueue(_logService);
    register(toDisposable(() => _memoryCleanupQueue.clear()));
    register(toDisposable(() => clearAllMarkers()));
  }

  final bool _hasScrollback;
  final IOptionsService _optionsService;
  final IBufferService _bufferService;
  final ILogService _logService;

  @override
  late CircularList<IBufferLine> lines;
  @override
  int ydisp = 0;
  @override
  int ybase = 0;
  @override
  int y = 0;
  @override
  int x = 0;
  @override
  late int scrollBottom;
  @override
  late int scrollTop;
  @override
  Map<int, bool> tabs = <int, bool>{};
  @override
  int savedY = 0;
  @override
  int savedX = 0;
  @override
  IAttributeData savedCurAttrData = defaultAttrData.clone();
  @override
  ICharset? savedCharset = defaultCharset;
  @override
  List<ICharset?> savedCharsets = <ICharset?>[];
  @override
  int savedGlevel = 0;
  @override
  bool savedOriginMode = false;
  @override
  bool savedWraparoundMode = true;
  @override
  List<Marker> markers = <Marker>[];
  final ICellData _nullCell = CellData.fromCharData((
    0,
    nullCellChar,
    nullCellWidth,
    nullCellCode,
  ));
  final ICellData _whitespaceCell = CellData.fromCharData((
    0,
    whitespaceCellChar,
    whitespaceCellWidth,
    whitespaceCellCode,
  ));
  late int _cols;
  late int _rows;
  bool _isClearing = false;
  late final IdleTaskQueue _memoryCleanupQueue;
  int _memoryCleanupPosition = 0;

  @override
  ICellData getNullCell([IAttributeData? attr]) {
    if (attr != null) {
      _nullCell.fg = attr.fg;
      _nullCell.bg = attr.bg;
      _nullCell.extended = attr.extended;
    } else {
      _nullCell.fg = 0;
      _nullCell.bg = 0;
      _nullCell.extended = ExtendedAttrs();
    }
    return _nullCell;
  }

  @override
  ICellData getWhitespaceCell([IAttributeData? attr]) {
    if (attr != null) {
      _whitespaceCell.fg = attr.fg;
      _whitespaceCell.bg = attr.bg;
      _whitespaceCell.extended = attr.extended;
    } else {
      _whitespaceCell.fg = 0;
      _whitespaceCell.bg = 0;
      _whitespaceCell.extended = ExtendedAttrs();
    }
    return _whitespaceCell;
  }

  @override
  BufferLine getBlankLine(IAttributeData attr, [bool? isWrapped]) {
    return BufferLine(
      _bufferService.cols,
      getNullCell(attr),
      isWrapped ?? false,
    );
  }

  @override
  bool get hasScrollback {
    return _hasScrollback && lines.maxLength > _rows;
  }

  @override
  bool get isCursorInViewport {
    final absoluteY = ybase + y;
    final relativeY = absoluteY - ydisp;
    return relativeY >= 0 && relativeY < _rows;
  }

  /// Gets the correct buffer length based on the [rows] provided, the
  /// terminal's scrollback and whether this buffer is flagged to have
  /// scrollback or not.
  int _getCorrectBufferLength(int rows) {
    if (!_hasScrollback) {
      return rows;
    }

    final correctBufferLength = rows + _optionsService.rawOptions.scrollback;

    return correctBufferLength > maxBufferSize
        ? maxBufferSize
        : correctBufferLength;
  }

  /// Fills the buffer's viewport with blank lines.
  void fillViewportRows([IAttributeData? fillAttr]) {
    if (lines.length == 0) {
      fillAttr ??= defaultAttrData;
      var i = _rows;
      while (i-- != 0) {
        lines.push(getBlankLine(fillAttr));
      }
    }
  }

  /// Clears the buffer to its initial state, discarding all previous data.
  void clear() {
    ydisp = 0;
    ybase = 0;
    y = 0;
    x = 0;
    lines = CircularList<IBufferLine>(_getCorrectBufferLength(_rows));
    scrollTop = 0;
    scrollBottom = _rows - 1;
    setupTabStops();
  }

  /// Resizes the buffer to [newCols] columns and [newRows] rows, adjusting
  /// its data accordingly.
  void resize(int newCols, int newRows) {
    // store reference to null cell with default attrs
    final nullCell = getNullCell(defaultAttrData);

    // count bufferlines with overly big memory to be cleaned afterwards
    var dirtyMemoryLines = 0;

    // Increase max length if needed before adjustments to allow space to fill
    // as required.
    final newMaxLength = _getCorrectBufferLength(newRows);
    if (newMaxLength > lines.maxLength) {
      lines.maxLength = newMaxLength;
    }

    // The following adjustments should only happen if the buffer has been
    // initialized/filled.
    if (lines.length > 0) {
      // Deal with columns increasing (reducing needs to happen after reflow)
      if (_cols < newCols) {
        for (var i = 0; i < lines.length; i++) {
          if (lines.get(i)!.resize(newCols, nullCell)) {
            dirtyMemoryLines++;
          }
        }
      }

      // Resize rows in both directions as needed
      var addToY = 0;
      if (_rows < newRows) {
        for (var y = _rows; y < newRows; y++) {
          if (lines.length < newRows + ybase) {
            final windowsPty = _optionsService.rawOptions.windowsPty;
            if (windowsPty.backend != null || windowsPty.buildNumber != null) {
              // Just add the new missing rows on Windows as conpty reprints
              // the screen with its view of the world. Once a line enters
              // scrollback for conpty it remains there
              lines.push(BufferLine(newCols, nullCell, false));
            } else {
              if (ybase > 0 && lines.length <= ybase + this.y + addToY + 1) {
                // There is room above the buffer and there are no empty
                // elements below the line, scroll up
                ybase--;
                addToY++;
                if (ydisp > 0) {
                  // Viewport is at the top of the buffer, must increase
                  // downwards
                  ydisp--;
                }
              } else {
                // Add a blank line if there is no buffer left at the top to
                // scroll to, or if there are blank lines after the cursor
                lines.push(BufferLine(newCols, nullCell, false));
              }
            }
          }
        }
      } else {
        // (this._rows >= newRows)
        for (var y = _rows; y > newRows; y--) {
          if (lines.length > newRows + ybase) {
            if (lines.length > ybase + this.y + 1) {
              // The line is a blank line below the cursor, remove it
              lines.pop();
            } else {
              // The line is the cursor, scroll down
              ybase++;
              ydisp++;
            }
          }
        }
      }

      // Reduce max length if needed after adjustments, this is done after as
      // it would otherwise cut data from the bottom of the buffer.
      if (newMaxLength < lines.maxLength) {
        // Trim from the top of the buffer and adjust ybase and ydisp.
        final amountToTrim = lines.length - newMaxLength;
        if (amountToTrim > 0) {
          lines.trimStart(amountToTrim);
          ybase = _max(ybase - amountToTrim, 0);
          ydisp = _max(ydisp - amountToTrim, 0);
          savedY = _max(savedY - amountToTrim, 0);
        }
        lines.maxLength = newMaxLength;
      }

      // Make sure that the cursor stays on screen
      x = _min(x, newCols - 1);
      y = _min(y, newRows - 1);
      if (addToY != 0) {
        y += addToY;
      }
      savedX = _min(savedX, newCols - 1);

      scrollTop = 0;
    }

    scrollBottom = newRows - 1;

    if (_isReflowEnabled) {
      _reflow(newCols, newRows);

      // Trim the end of the line off if cols shrunk
      if (_cols > newCols) {
        for (var i = 0; i < lines.length; i++) {
          if (lines.get(i)!.resize(newCols, nullCell)) {
            dirtyMemoryLines++;
          }
        }
      }
    }

    _cols = newCols;
    _rows = newRows;

    // Ensure the cursor position invariant: ybase + y must be within buffer
    // bounds. This can be violated during reflow or when shrinking rows
    if (lines.length > 0) {
      final maxY = _max(0, lines.length - ybase - 1);
      y = _min(y, maxY);
    }

    _memoryCleanupQueue.clear();
    // schedule memory cleanup only, if more than 10% of the lines are
    // affected
    if (dirtyMemoryLines > 0.1 * lines.length) {
      _memoryCleanupPosition = 0;
      _memoryCleanupQueue.enqueue(() => _batchedMemoryCleanup());
    }
  }

  bool _batchedMemoryCleanup() {
    var normalRun = true;
    if (_memoryCleanupPosition >= lines.length) {
      // cleanup made it once through all lines, thus rescan in loop below to
      // also catch shifted lines, which should finish rather quick if there
      // are no more cleanups pending
      _memoryCleanupPosition = 0;
      normalRun = false;
    }
    var counted = 0;
    while (_memoryCleanupPosition < lines.length) {
      counted += lines.get(_memoryCleanupPosition++)!.cleanupMemory();
      // cleanup max 100 lines per batch
      if (counted > 100) {
        return true;
      }
    }
    // normal runs always need another rescan afterwards
    // if we made it here with normalRun=false, we are in a final run
    // and can end the cleanup task for sure
    return normalRun;
  }

  bool get _isReflowEnabled {
    final windowsPty = _optionsService.rawOptions.windowsPty;
    final buildNumber = windowsPty.buildNumber;
    if (buildNumber != null && buildNumber != 0) {
      return _hasScrollback &&
          windowsPty.backend == 'conpty' &&
          buildNumber >= 21376;
    }
    return _hasScrollback;
  }

  void _reflow(int newCols, int newRows) {
    if (_cols == newCols) {
      return;
    }

    // Iterate through rows, ignore the last one as it cannot be wrapped
    if (newCols > _cols) {
      _reflowLarger(newCols, newRows);
    } else {
      _reflowSmaller(newCols, newRows);
    }
  }

  void _reflowLarger(int newCols, int newRows) {
    final reflowCursorLine = _optionsService.rawOptions.reflowCursorLine;
    final toRemove = reflowLargerGetLinesToRemove(
      lines,
      _cols,
      newCols,
      ybase + y,
      getNullCell(defaultAttrData),
      reflowCursorLine,
    );
    if (toRemove.isNotEmpty) {
      final newLayoutResult = reflowLargerCreateNewLayout(lines, toRemove);
      reflowLargerApplyNewLayout(lines, newLayoutResult.layout);
      _reflowLargerAdjustViewport(
        newCols,
        newRows,
        newLayoutResult.countRemoved,
      );
    }
  }

  void _reflowLargerAdjustViewport(int newCols, int newRows, int countRemoved) {
    final nullCell = getNullCell(defaultAttrData);
    // Adjust viewport based on number of items removed
    var viewportAdjustments = countRemoved;
    while (viewportAdjustments-- > 0) {
      if (ybase == 0) {
        if (y > 0) {
          y--;
        }
        if (lines.length < newRows) {
          // Add an extra row at the bottom of the viewport
          lines.push(BufferLine(newCols, nullCell, false));
        }
      } else {
        if (ydisp == ybase) {
          ydisp--;
        }
        ybase--;
      }
    }
    savedY = _max(savedY - countRemoved, 0);
  }

  void _reflowSmaller(int newCols, int newRows) {
    final reflowCursorLine = _optionsService.rawOptions.reflowCursorLine;
    final nullCell = getNullCell(defaultAttrData);
    // Gather all BufferLines that need to be inserted into the Buffer here so
    // that they can be batched up and only committed once
    final toInsert = <_ToInsert>[];
    var countToInsert = 0;
    // Go backwards as many lines may be trimmed and this will avoid
    // considering them
    for (var y = lines.length - 1; y >= 0; y--) {
      // Check whether this line is a problem
      var nextLine = lines.get(y) as BufferLine?;
      if (nextLine == null ||
          !nextLine.isWrapped && nextLine.getTrimmedLength() <= newCols) {
        continue;
      }

      // Gather wrapped lines and adjust y to be the starting line
      final wrappedLines = <BufferLine>[nextLine];
      while (nextLine!.isWrapped && y > 0) {
        nextLine = lines.get(--y) as BufferLine;
        wrappedLines.insert(0, nextLine);
      }

      if (!reflowCursorLine) {
        // If these lines contain the cursor don't touch them, the program
        // will handle fixing up wrapped lines with the cursor
        final absoluteY = ybase + this.y;
        if (absoluteY >= y && absoluteY < y + wrappedLines.length) {
          continue;
        }
      }

      final lastLineLength = wrappedLines[wrappedLines.length - 1]
          .getTrimmedLength();
      final destLineLengths = reflowSmallerGetNewLineLengths(
        wrappedLines,
        _cols,
        newCols,
      );
      // Upstream reads past either end of destLineLengths as undefined; -1
      // stands in for it (it is never used as a length).
      int destLineLengthAt(int index) =>
          index >= 0 && index < destLineLengths.length
          ? destLineLengths[index]
          : -1;
      final linesToAdd = destLineLengths.length - wrappedLines.length;
      int trimmedLines;
      if (ybase == 0 && this.y != lines.length - 1) {
        // If the top section of the buffer is not yet filled
        trimmedLines = _max(0, this.y - lines.maxLength + linesToAdd);
      } else {
        trimmedLines = _max(0, lines.length - lines.maxLength + linesToAdd);
      }

      // Add the new lines
      final newLines = <BufferLine>[];
      for (var i = 0; i < linesToAdd; i++) {
        final newLine = getBlankLine(defaultAttrData, true);
        newLines.add(newLine);
      }
      if (newLines.isNotEmpty) {
        toInsert.add(
          // countToInsert here gets the actual index, taking into account
          // other inserted items. using this we can iterate through the list
          // forwards
          _ToInsert(y + wrappedLines.length + countToInsert, newLines),
        );
        countToInsert += newLines.length;
      }
      wrappedLines.addAll(newLines);

      // Copy buffer data to new locations, this needs to happen backwards to
      // do in-place
      var destLineIndex =
          destLineLengths.length - 1; // Math.floor(cellsNeeded / newCols);
      var destCol = destLineLengthAt(destLineIndex); // cellsNeeded % newCols;
      if (destCol == 0) {
        destLineIndex--;
        destCol = destLineLengthAt(destLineIndex);
      }
      var srcLineIndex = wrappedLines.length - linesToAdd - 1;
      var srcCol = lastLineLength;
      while (srcLineIndex >= 0) {
        final cellsToCopy = _min(srcCol, destCol);
        if (destLineIndex < 0 || destLineIndex >= wrappedLines.length) {
          // Sanity check that the line exists, this has been known to fail
          // for an unknown reason which would stop the reflow from happening
          // if an exception would throw.
          break;
        }
        wrappedLines[destLineIndex].copyCellsFrom(
          wrappedLines[srcLineIndex],
          srcCol - cellsToCopy,
          destCol - cellsToCopy,
          cellsToCopy,
          true,
        );
        destCol -= cellsToCopy;
        if (destCol == 0) {
          destLineIndex--;
          destCol = destLineLengthAt(destLineIndex);
        }
        srcCol -= cellsToCopy;
        if (srcCol == 0) {
          srcLineIndex--;
          final wrappedLinesIndex = _max(srcLineIndex, 0);
          srcCol = getWrappedLineTrimmedLength(
            wrappedLines,
            wrappedLinesIndex,
            _cols,
          );
        }
      }

      // Null out the end of the line ends if a wide character wrapped to the
      // following line
      for (var i = 0; i < wrappedLines.length; i++) {
        if (i < destLineLengths.length && destLineLengths[i] < newCols) {
          wrappedLines[i].setCell(destLineLengths[i], nullCell);
        }
      }

      // Adjust viewport as needed
      var viewportAdjustments = linesToAdd - trimmedLines;
      while (viewportAdjustments-- > 0) {
        if (ybase == 0) {
          if (this.y < newRows - 1) {
            this.y++;
            lines.pop();
          } else {
            ybase++;
            ydisp++;
          }
        } else {
          // Ensure ybase does not exceed its maximum value
          if (ybase <
              _min(lines.maxLength, lines.length + countToInsert) - newRows) {
            if (ybase == ydisp) {
              ydisp++;
            }
            ybase++;
          }
        }
      }
      savedY = _min(savedY + linesToAdd, ybase + newRows - 1);
    }

    // Rearrange lines in the buffer if there are any insertions, this is done
    // at the end rather than earlier so that it's a single O(n) pass through
    // the buffer, instead of O(n^2) from many costly calls to
    // CircularList.splice.
    if (toInsert.isNotEmpty) {
      // Record buffer insert events and then play them back backwards so that
      // the indexes are correct
      final insertEvents = <IInsertEvent>[];

      // Record original lines so they don't get overridden when we rearrange
      // the list
      final originalLines = <BufferLine>[];
      for (var i = 0; i < lines.length; i++) {
        originalLines.add(lines.get(i) as BufferLine);
      }
      final originalLinesLength = lines.length;

      var originalLineIndex = originalLinesLength - 1;
      var nextToInsertIndex = 0;
      _ToInsert? nextToInsert = toInsert[nextToInsertIndex];
      lines.length = _min(lines.maxLength, lines.length + countToInsert);
      var countInsertedSoFar = 0;
      for (
        var i = _min(
          lines.maxLength - 1,
          originalLinesLength + countToInsert - 1,
        );
        i >= 0;
        i--
      ) {
        if (nextToInsert != null &&
            nextToInsert.start > originalLineIndex + countInsertedSoFar) {
          // Insert extra lines here, adjusting i as needed
          for (
            var nextI = nextToInsert.newLines.length - 1;
            nextI >= 0;
            nextI--
          ) {
            lines.set(i--, nextToInsert.newLines[nextI]);
          }
          i++;

          // Create insert events for later
          insertEvents.add(
            IInsertEvent(
              index: originalLineIndex + 1,
              amount: nextToInsert.newLines.length,
            ),
          );

          countInsertedSoFar += nextToInsert.newLines.length;
          nextToInsert = ++nextToInsertIndex < toInsert.length
              ? toInsert[nextToInsertIndex]
              : null;
        } else {
          lines.set(i, originalLines[originalLineIndex--]);
        }
      }

      // Update markers
      var insertCountEmitted = 0;
      for (var i = insertEvents.length - 1; i >= 0; i--) {
        insertEvents[i].index += insertCountEmitted;
        lines.onInsertEmitter.fire(insertEvents[i]);
        insertCountEmitted += insertEvents[i].amount;
      }
      final amountToTrim = _max(
        0,
        originalLinesLength + countToInsert - lines.maxLength,
      );
      if (amountToTrim > 0) {
        lines.onTrimEmitter.fire(amountToTrim);
      }
    }
  }

  /// Translates a buffer line to a string, with optional start and end
  /// columns. Wide characters will count as two columns in the resulting
  /// string. This function is useful for getting the actual text underneath
  /// the raw selection position.
  ///
  /// [lineIndex] is the absolute index of the line being translated,
  /// [trimRight] whether to trim whitespace to the right, [startCol] the
  /// column to start at and [endCol] the column to end at.
  @override
  String translateBufferLineToString(
    int lineIndex,
    bool trimRight, [
    int startCol = 0,
    int? endCol,
  ]) {
    final line = lines.get(lineIndex);
    if (line == null) {
      return '';
    }
    return line.translateToString(trimRight, startCol, endCol);
  }

  @override
  ({int first, int last}) getWrappedRangeForLine(int y) {
    var first = y;
    var last = y;
    // Scan upwards for wrapped lines
    while (first > 0 && lines.get(first)!.isWrapped) {
      first--;
    }
    // Scan downwards for wrapped lines
    while (last + 1 < lines.length && lines.get(last + 1)!.isWrapped) {
      last++;
    }
    return (first: first, last: last);
  }

  /// Setup the tab stops, starting from index [i].
  void setupTabStops([int? i]) {
    int start;
    if (i != null) {
      start = tabs[i] != true ? prevStop(i) : i;
    } else {
      tabs = <int, bool>{};
      start = 0;
    }

    for (; start < _cols; start += _optionsService.rawOptions.tabStopWidth) {
      tabs[start] = true;
    }
  }

  /// Move the cursor to the previous tab stop from the given position
  /// (default is current).
  @override
  int prevStop([int? x]) {
    var col = x ?? this.x;
    while (tabs[--col] != true && col > 0) {}
    return col >= _cols
        ? _cols - 1
        : col < 0
        ? 0
        : col;
  }

  /// Move the cursor one tab stop forward from the given position (default
  /// is current).
  @override
  int nextStop([int? x]) {
    var col = x ?? this.x;
    while (tabs[++col] != true && col < _cols) {}
    return col >= _cols
        ? _cols - 1
        : col < 0
        ? 0
        : col;
  }

  /// Clears markers on line [y].
  @override
  void clearMarkers(int y) {
    _isClearing = true;
    for (var i = 0; i < markers.length; i++) {
      if (markers[i].line == y) {
        markers[i].dispose();
        markers.removeAt(i--);
      }
    }
    _isClearing = false;
  }

  /// Clears markers on all lines
  @override
  void clearAllMarkers() {
    _isClearing = true;
    for (var i = 0; i < markers.length; i++) {
      markers[i].dispose();
    }
    markers.clear();
    _isClearing = false;
  }

  @override
  Marker addMarker(int y) {
    final marker = Marker(y);
    markers.add(marker);
    marker.register(
      lines.onTrim((amount) {
        marker.line -= amount;
        // The marker should be disposed when the line is trimmed from the
        // buffer
        if (marker.line < 0) {
          marker.dispose();
        }
      }),
    );
    marker.register(
      lines.onInsert((event) {
        if (marker.line >= event.index) {
          marker.line += event.amount;
        }
      }),
    );
    marker.register(
      lines.onDelete((event) {
        // Delete the marker if it's within the range
        if (marker.line >= event.index &&
            marker.line < event.index + event.amount) {
          marker.dispose();
        }

        // Shift the marker if it's after the deleted range
        if (marker.line > event.index) {
          marker.line -= event.amount;
        }
      }),
    );
    marker.register(marker.onDispose((_) => _removeMarker(marker)));
    return marker;
  }

  void _removeMarker(Marker marker) {
    if (!_isClearing) {
      final index = markers.indexOf(marker);
      if (index != -1) {
        markers.removeAt(index);
      }
    }
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;
}
