// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/BufferService.ts (c58ea36).

import '../buffer/buffer_set.dart';
import '../buffer/types.dart';
import '../event.dart';
import '../lifecycle.dart';
import 'services.dart';

abstract final class BufferServiceConstants {
  /// Less than 2 can mess with wide chars.
  static const int minimumCols = 2;
  static const int minimumRows = 1;
}

class BufferService extends Disposable implements IBufferService {
  BufferService(IOptionsService optionsService, ILogService logService) {
    _onResize = register(Emitter<IBufferResizeEvent>());
    onResize = _onResize.event;
    _onScroll = register(Emitter<int>());
    onScroll = _onScroll.event;
    cols = _max(
      optionsService.rawOptions.cols,
      BufferServiceConstants.minimumCols,
    );
    rows = _max(
      optionsService.rawOptions.rows,
      BufferServiceConstants.minimumRows,
    );
    buffers = register(BufferSet(optionsService, this, logService));
    register(
      buffers.onBufferActivate((e) {
        _onScroll.fire(e.activeBuffer.ydisp);
      }),
    );
  }

  @override
  late int cols;
  @override
  late int rows;
  @override
  late final IBufferSet buffers;

  /// Whether the user is scrolling (locks the scroll position)
  @override
  bool isUserScrolling = false;

  late final Emitter<IBufferResizeEvent> _onResize;
  @override
  late final IEvent<IBufferResizeEvent> onResize;
  late final Emitter<int> _onScroll;
  @override
  late final IEvent<int> onScroll;

  @override
  IBuffer get buffer => buffers.active;

  /// An IBufferline to clone/copy from for new blank lines
  IBufferLine? _cachedBlankLine;

  @override
  void resize(int cols, int rows) {
    final colsChanged = this.cols != cols;
    final rowsChanged = this.rows != rows;
    this.cols = cols;
    this.rows = rows;
    buffers.resize(cols, rows);
    _onResize.fire(
      IBufferResizeEvent(
        cols: cols,
        rows: rows,
        colsChanged: colsChanged,
        rowsChanged: rowsChanged,
      ),
    );
  }

  @override
  void reset() {
    buffers.reset();
    isUserScrolling = false;
  }

  /// Scroll the terminal down 1 row, creating a blank line.
  ///
  /// [eraseAttr] is the attribute data to use the for blank line,
  /// [isWrapped] whether the new line is wrapped from the previous line.
  @override
  void scroll(IAttributeData eraseAttr, [bool? isWrapped]) {
    final wrapped = isWrapped ?? false;
    final buffer = this.buffer;

    var newLine = _cachedBlankLine;
    if (newLine == null ||
        newLine.length != cols ||
        newLine.getFg(0) != eraseAttr.fg ||
        newLine.getBg(0) != eraseAttr.bg) {
      newLine = buffer.getBlankLine(eraseAttr, wrapped);
      _cachedBlankLine = newLine;
    }
    newLine.isWrapped = wrapped;

    final topRow = buffer.ybase + buffer.scrollTop;
    final bottomRow = buffer.ybase + buffer.scrollBottom;

    if (buffer.scrollTop == 0) {
      // Determine whether the buffer is going to be trimmed after insertion.
      final willBufferBeTrimmed = buffer.lines.isFull;

      // Insert the line using the fastest method
      if (bottomRow == buffer.lines.length - 1) {
        if (willBufferBeTrimmed) {
          buffer.lines.recycle().copyFrom(newLine, true);
        } else {
          buffer.lines.push(newLine.clone(true));
        }
      } else {
        buffer.lines.splice(bottomRow + 1, 0, <IBufferLine>[
          newLine.clone(true),
        ]);
      }

      // Only adjust ybase and ydisp when the buffer is not trimmed
      if (!willBufferBeTrimmed) {
        buffer.ybase++;
        // Only scroll the ydisp with ybase if the user has not scrolled up
        if (!isUserScrolling) {
          buffer.ydisp++;
        }
      } else {
        // When the buffer is full and the user has scrolled up, keep the text
        // stable unless ydisp is right at the top
        if (isUserScrolling) {
          buffer.ydisp = _max(buffer.ydisp - 1, 0);
        }
      }
    } else {
      // scrollTop is non-zero which means no line will be going to the
      // scrollback, instead we can just shift them in-place.
      final scrollRegionHeight = bottomRow - topRow + 1; // as it's zero-based
      buffer.lines.shiftElements(topRow + 1, scrollRegionHeight - 1, -1);
      buffer.lines.set(bottomRow, newLine.clone(true));
    }

    // Move the viewport to the bottom of the buffer unless the user is
    // scrolling.
    if (!isUserScrolling) {
      buffer.ydisp = buffer.ybase;
    }

    _onScroll.fire(buffer.ydisp);
  }

  /// Scroll the display of the terminal
  ///
  /// [disp] is the number of lines to scroll down (negative scroll up).
  /// [suppressScrollEvent] doesn't emit the scroll event as scrollLines. This
  /// is used to avoid unwanted events being handled by the viewport when the
  /// event was triggered from the viewport originally.
  @override
  void scrollLines(int disp, [bool? suppressScrollEvent]) {
    final buffer = this.buffer;
    if (disp < 0) {
      if (buffer.ydisp == 0) {
        return;
      }
      isUserScrolling = true;
    } else if (disp + buffer.ydisp >= buffer.ybase) {
      isUserScrolling = false;
    }

    final oldYdisp = buffer.ydisp;
    buffer.ydisp = _max(_min(buffer.ydisp + disp, buffer.ybase), 0);

    // No change occurred, don't trigger scroll/refresh
    if (oldYdisp == buffer.ydisp) {
      return;
    }

    if (suppressScrollEvent != true) {
      _onScroll.fire(buffer.ydisp);
    }
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;
}
