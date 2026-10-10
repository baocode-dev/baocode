/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// How VS Code picks one end-of-line sequence for a text model, and the line
// splitting every mirror of that model uses.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeTextBufferBuilder.ts
// (`PieceTreeTextBufferFactory._getEOL`, the BOM handling of
// `PieceTreeTextBufferBuilder.acceptChunk`),
// src/vs/editor/common/model/textModel.ts (`TextModel._MODEL_SYNC_LIMIT`),
// src/vs/base/common/strings.ts (`splitLines`, `UTF8_BOM_CHARACTER`).
//
// Deviations:
// - Counting runs over the whole string instead of the builder's chunks
//   (same result: a CRLF split across chunks is rejoined upstream too).

/// `strings.UTF8_BOM_CHARACTER`.
const String utf8BomCharacter = '﻿';

/// `TextModel._MODEL_SYNC_LIMIT`: models whose text is longer than this many
/// UTF-16 code units are not synchronized to the extension host
/// (`ITextModel.isTooLargeForSyncing`).
const int modelSyncLimit = 50 * 1024 * 1024;

/// `TextModel.isTooLargeForSyncing` for a model of [textLength] code units
/// (the text without its BOM, as `TextBuffer.getLength` counts).
bool isModelTooLargeForSyncing(int textLength) => textLength > modelSyncLimit;

/// `/\r\n|\r|\n/`: the line breaks every model and mirror recognizes.
final RegExp lineBreakPattern = RegExp('\r\n|\r|\n');

/// `strings.splitLines`.
List<String> splitLines(String text) => text.split(lineBreakPattern);

/// Line break counts of a text, as the buffer builder keeps them.
class LineBreakCounts {
  LineBreakCounts({this.cr = 0, this.lf = 0, this.crlf = 0});

  /// Counts the breaks of [text].
  factory LineBreakCounts.of(String text) {
    final counts = LineBreakCounts();
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0D) {
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
          counts.crlf++;
          i++;
        } else {
          counts.cr++;
        }
      } else if (c == 0x0A) {
        counts.lf++;
      }
    }
    return counts;
  }

  /// Lone `\r`.
  int cr;

  /// Lone `\n`.
  int lf;
  int crlf;

  int get total => cr + lf + crlf;

  /// Adds (or with [sign] -1 removes) one break [eol] (`\r\n`, `\r` or `\n`).
  void count(String eol, [int sign = 1]) {
    switch (eol) {
      case '\r\n':
        crlf += sign;
      case '\r':
        cr += sign;
      case '\n':
        lf += sign;
    }
  }

  /// `PieceTreeTextBufferFactory._getEOL`: the model EOL for these counts.
  /// Lone CRs count as CRLF; ties go to `\n`; no breaks at all take
  /// [defaultEol].
  String modelEol(String defaultEol) {
    final totalEOLCount = total;
    final totalCRCount = cr + crlf;
    if (totalEOLCount == 0) {
      // This is an empty file or a file with precisely one line
      return defaultEol == '\r\n' ? '\r\n' : '\n';
    }
    if (totalCRCount > totalEOLCount / 2) {
      // More than half of the file contains \r\n ending lines
      return '\r\n';
    }
    // At least one line more ends in \n
    return '\n';
  }

  /// The break kind the text uses most, for text BaoCode inserts into the
  /// raw file. Ties prefer [modelEol], then `\n`, `\r\n`, `\r`; no breaks at
  /// all give [modelEol].
  String dominant(String modelEol) {
    if (total == 0) return modelEol;
    int countOf(String eol) => switch (eol) {
      '\r\n' => crlf,
      '\r' => cr,
      _ => lf,
    };
    var best = modelEol;
    for (final candidate in const ['\n', '\r\n', '\r']) {
      if (countOf(candidate) > countOf(best)) best = candidate;
    }
    return best;
  }
}

/// Replaces every line break of [text] with [eol].
String normalizeEol(String text, String eol) =>
    text.replaceAll(lineBreakPattern, eol);
