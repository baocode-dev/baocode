/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/output/common/outputChannelModel.ts
// (`FileContentProvider`: start and end offsets, `reset(offset)`,
// `resetToEnd()`, reading from the end offset, a file shorter than what was
// read starts over from 0).
//
// Deviations: reads with a RandomAccessFile only the bytes after the end
// offset, and never past the last whole UTF-8 character (the rest is read
// with the next bytes); keeps at most [OutputFileTailer.maxBytes] of a file
// (the head of a bigger one is skipped, up to a line start); a missing file
// reads as nothing (upstream: FILE_NOT_FOUND ignored); no etag: a size that
// grew is new content.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What one [OutputFileTailer.read] found.
final class OutputTailRead {
  const OutputTailRead(this.text, {this.restarted = false, this.skipped = 0});

  /// The new text, whole characters only.
  final String text;

  /// The file was shorter than what had been read (truncated, rotated):
  /// what was shown is stale and [text] is from the file's start.
  final bool restarted;

  /// When more was new than [OutputFileTailer.maxBytes], the bytes of the
  /// content (from the start offset) before [text], which were not read:
  /// what was shown before is not contiguous with [text]. Else 0.
  final int skipped;
}

/// Follows a file a writer appends to (an output channel's, a log's): each
/// [read] returns only the bytes appended since the last one.
final class OutputFileTailer {
  OutputFileTailer(this.path, {this.maxBytes = defaultMaxBytes});

  static const defaultMaxBytes = 4 * 1024 * 1024;

  final String path;

  /// The most read at once: of more, only the last [maxBytes] (from the
  /// first line start in them).
  final int maxBytes;

  /// Where the content starts (moved by a clear or a replace).
  int get startOffset => _startOffset;
  int _startOffset = 0;

  /// Up to where the file was read.
  int get endOffset => _endOffset;
  int _endOffset = 0;

  /// Bumped by each reset: a read begun before one is dropped.
  int _generation = 0;

  /// Starts over from [offset] (else the start offset): the content is
  /// what follows it (`reset`). A clear or replace from the extension host
  /// passes its `till`.
  void reset([int? offset]) {
    _generation++;
    _startOffset = _endOffset = offset ?? _startOffset;
  }

  /// Drops what was read: the content starts after it (`resetToEnd`, the
  /// Clear Output action).
  void resetToEnd() {
    _generation++;
    _startOffset = _endOffset;
  }

  /// Reads what was appended since the last read; null when nothing was
  /// (or the file is missing, or a reset came meanwhile).
  Future<OutputTailRead?> read() async {
    final generation = _generation;
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final size = await file.length();
      if (generation != _generation) return null;
      var restarted = false;
      if (size < _endOffset) {
        // Truncated or rotated: upstream's `reset(0)` and `onDidReset`.
        _startOffset = _endOffset = 0;
        restarted = true;
      }
      var from = _endOffset;
      var skipped = 0;
      if (size - from > maxBytes) {
        skipped = size - maxBytes - from;
        from = size - maxBytes;
      }
      if (size <= from) {
        return restarted ? const OutputTailRead('', restarted: true) : null;
      }
      await file.setPosition(from);
      final bytes = await file.read(size - from);
      if (generation != _generation) return null;
      var begin = 0;
      if (skipped > 0) {
        // From the first whole line kept.
        final newline = bytes.indexOf(0x0a);
        begin = newline < 0 ? _firstCharStart(bytes) : newline + 1;
      }
      var end = bytes.length - incompleteUtf8Tail(bytes);
      if (end < begin) end = begin;
      _endOffset = from + end;
      if (end == begin && !restarted && skipped == 0) return null;
      return OutputTailRead(
        utf8.decode(Uint8List.sublistView(bytes, begin, end),
            allowMalformed: true),
        restarted: restarted,
        skipped: skipped > 0 ? from + begin - _startOffset : 0,
      );
    } on FileSystemException {
      // Not there (yet, or any more: a logs folder deleted).
      return null;
    } finally {
      await file?.close();
    }
  }

  static int _firstCharStart(Uint8List bytes) {
    var i = 0;
    while (i < bytes.length && i < 4 && bytes[i] & 0xc0 == 0x80) {
      i++;
    }
    return i;
  }
}

/// How many bytes at the end of [bytes] are the start of a UTF-8 character
/// whose other bytes are not there yet.
int incompleteUtf8Tail(List<int> bytes) {
  final n = bytes.length;
  for (var back = 1; back <= 4 && back <= n; back++) {
    final b = bytes[n - back];
    if (b & 0xc0 == 0x80) continue; // A continuation byte.
    final length = b < 0x80
        ? 1
        : b & 0xe0 == 0xc0
        ? 2
        : b & 0xf0 == 0xe0
        ? 3
        : b & 0xf8 == 0xf0
        ? 4
        : 1;
    return back < length ? back : 0;
  }
  return 0;
}
