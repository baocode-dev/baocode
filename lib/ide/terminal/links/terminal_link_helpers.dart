/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Between a wrapped line's text, where the detectors find links by string
// index, and the buffer's cells, where the links are drawn: wide characters
// take two cells and emoji two code units.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalLinkHelpers.ts. `updateLinkWithRelativeCwd` takes the cwd of the
// line (shell integration's command detection, upstream's capability
// store) instead of the capabilities; the path modules are package:path's
// contexts, joined the Node.js way ([joinPath]).

import 'package:path/path.dart' as p;

import '../xterm/typings/xterm_headless.dart';
import 'link_computer.dart';
import 'terminal_link_parsing.dart';
import 'terminal_link_resolver.dart';

/// Converts a possibly wrapped link's range (comprised of string indices)
/// into a buffer range that plays nicely with xterm.js
///
/// [lines] is a single line (not the entire buffer), [bufferWidth] the number
/// of columns in the terminal, [range] the link range - string indices, and
/// [startLine] the absolute y position (on the buffer) of the line.
IBufferRange convertLinkRangeToBuffer(
  List<IBufferLine> lines,
  int bufferWidth,
  IRange range,
  int startLine,
) {
  final bufferRange = IBufferRange(
    start: IBufferCellPosition(
      x: range.startColumn,
      y: range.startLineNumber + startLine,
    ),
    end: IBufferCellPosition(
      x: range.endColumn - 1,
      y: range.endLineNumber + startLine,
    ),
  );

  // Shift start range right for each wide character before the link
  var startOffset = 0;
  final startWrappedLineCount = (range.startColumn / bufferWidth).ceil();
  for (var y = 0; y < startWrappedLineCount; y++) {
    final lineLength = _min(
      bufferWidth,
      (range.startColumn - 1) - y * bufferWidth,
    );
    var lineOffset = 0;
    // Sanity check for line, apparently this can happen but it's not clear
    // under what circumstances this happens. Continue on, skipping the
    // remainder of start offset if this happens to minimize impact.
    if (y >= lines.length) {
      break;
    }
    final line = lines[y];
    for (var x = 0; x < _min(bufferWidth, lineLength + lineOffset); x++) {
      final cell = line.getCell(x);
      // This is unexpected but it means the character doesn't exist, so we
      // shouldn't add to the offset
      if (cell == null) {
        break;
      }
      final width = cell.getWidth();
      if (width == 2) {
        lineOffset++;
      }
      final char = cell.getChars();
      if (char.length > 1) {
        lineOffset -= char.length - 1;
      }
    }
    startOffset += lineOffset;
  }

  // Shift end range right for each wide character inside the link
  var endOffset = 0;
  final endWrappedLineCount = (range.endColumn / bufferWidth).ceil();
  for (
    var y = _max(0, startWrappedLineCount - 1);
    y < endWrappedLineCount;
    y++
  ) {
    final start = y == startWrappedLineCount - 1
        ? (range.startColumn - 1 + startOffset) % bufferWidth
        : 0;
    final lineLength = _min(
      bufferWidth,
      range.endColumn + startOffset - y * bufferWidth,
    );
    var lineOffset = 0;
    // Sanity check for line, apparently this can happen but it's not clear
    // under what circumstances this happens. Continue on, skipping the
    // remainder of start offset if this happens to minimize impact.
    if (y >= lines.length) {
      break;
    }
    final line = lines[y];
    for (var x = start; x < _min(bufferWidth, lineLength + lineOffset); x++) {
      final cell = line.getCell(x);
      // This is unexpected but it means the character doesn't exist, so we
      // shouldn't add to the offset
      if (cell == null) {
        break;
      }
      final width = cell.getWidth();
      final chars = cell.getChars();
      // Offset for null cells following wide characters
      if (width == 2) {
        lineOffset++;
      }
      // Offset for early wrapping when the last cell in row is a wide
      // character
      if (x == bufferWidth - 1 && chars == '') {
        lineOffset++;
      }
      // Offset multi-code characters like emoji
      if (chars.length > 1) {
        lineOffset -= chars.length - 1;
      }
    }
    endOffset += lineOffset;
  }

  // Apply the width character offsets to the result
  bufferRange.start.x += startOffset;
  bufferRange.end.x += startOffset + endOffset;

  // Convert back to wrapped lines
  while (bufferRange.start.x > bufferWidth) {
    bufferRange.start.x -= bufferWidth;
    bufferRange.start.y++;
  }
  while (bufferRange.end.x > bufferWidth) {
    bufferRange.end.x -= bufferWidth;
    bufferRange.end.y++;
  }

  return bufferRange;
}

// JavaScript's Math.min/max on numbers; ints here.
int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

IViewportRange convertBufferRangeToViewport(
  IBufferRange bufferRange,
  int viewportY,
) {
  return IViewportRange(
    start: IViewportRangePosition(
      x: bufferRange.start.x - 1,
      y: bufferRange.start.y - viewportY - 1,
    ),
    end: IViewportRangePosition(
      x: bufferRange.end.x - 1,
      y: bufferRange.end.y - viewportY - 1,
    ),
  );
}

String getXtermLineContent(
  IBuffer buffer,
  int lineStart,
  int lineEnd,
  int cols,
) {
  // Cap the maximum number of lines generated to prevent potential
  // performance problems. This is more of a sanity check as the wrapped line
  // should already be trimmed down at this point.
  final maxLineLength = _max(2048, cols * 2);
  lineEnd = _min(lineEnd, lineStart + maxLineLength);
  final content = StringBuffer();
  for (var i = lineStart; i <= lineEnd; i++) {
    // Make sure only 0 to cols are considered as resizing when windows mode
    // is enabled will retain buffer data outside of the terminal width as
    // reflow is disabled.
    final line = buffer.getLine(i);
    if (line != null) {
      content.write(line.translateToString(true, 0, cols));
    }
  }
  return content.toString();
}

List<IBufferRange> getXtermRangesByAttr(
  IBuffer buffer,
  int lineStart,
  int lineEnd,
  int cols,
) {
  IBufferCellPosition? bufferRangeStart;
  var lastFgAttr = -1;
  var lastBgAttr = -1;
  final ranges = <IBufferRange>[];
  for (var y = lineStart; y <= lineEnd; y++) {
    final line = buffer.getLine(y);
    if (line == null) {
      continue;
    }
    for (var x = 0; x < cols; x++) {
      final cell = line.getCell(x);
      if (cell == null) {
        break;
      }
      // HACK: Re-construct the attributes from fg and bg, this is hacky as it
      // relies upon the internal buffer bit layout
      final thisFgAttr =
          cell.isBold() |
          cell.isInverse() |
          cell.isStrikethrough() |
          cell.isUnderline();
      final thisBgAttr = cell.isDim() | cell.isItalic();
      if (lastFgAttr == -1 || lastBgAttr == -1) {
        bufferRangeStart = IBufferCellPosition(x: x, y: y);
      } else {
        if (lastFgAttr != thisFgAttr || lastBgAttr != thisBgAttr) {
          // TODO: x overflow
          final bufferRangeEnd = IBufferCellPosition(x: x, y: y);
          ranges.add(
            IBufferRange(start: bufferRangeStart!, end: bufferRangeEnd),
          );
          bufferRangeStart = IBufferCellPosition(x: x, y: y);
        }
      }
      lastFgAttr = thisFgAttr;
      lastBgAttr = thisBgAttr;
    }
  }
  return ranges;
}

/// For shells with the CommandDetection capability, the cwd for a command
/// relative to the line of the particular link can be used to narrow down
/// the result for an exact file match.
///
/// [cwd] is the cwd of the link's line (upstream reads it from the command
/// detection capability for line `y`); null when unknown.
List<String>? updateLinkWithRelativeCwd(
  String? cwd,
  String text,
  p.Context osPath,
) {
  if (cwd == null || cwd.isEmpty) {
    return null;
  }
  final result = <String>[];
  final sep = osPath.separator;
  if (!text.contains(sep)) {
    result.add(_resolve(osPath, '$cwd$sep$text'));
  } else {
    var commonDirs = 0;
    var i = 0;
    final cwdPath = cwd.split(sep).reversed.toList();
    final linkPath = text.split(sep);
    // Get all results as candidates, prioritizing the link with the most
    // common directories. For example if in the directory /home/common and
    // the link is common/file, the result should be:
    // `['/home/common/common/file', '/home/common/file']`. The first is the
    // most likely as cwd detection is active.
    while (i < cwdPath.length) {
      result.add(
        _resolve(osPath, '$cwd$sep${linkPath.skip(commonDirs).join(sep)}'),
      );
      if (i < linkPath.length && cwdPath[i] == linkPath[i]) {
        commonDirs++;
      } else {
        break;
      }
      i++;
    }
  }
  return result;
}

/// Node.js' `path.resolve` of one path: absolute against the process's cwd.
String _resolve(p.Context osPath, String path) =>
    osPath.normalize(osPath.absolute(path));

/// The path module of [os].
p.Context osPathModule(OperatingSystem os) => osPathContext(os);
