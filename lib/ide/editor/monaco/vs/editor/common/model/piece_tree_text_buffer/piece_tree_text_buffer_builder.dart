/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code pieceTreeTextBufferBuilder.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.

import 'piece_tree_base.dart' as tree;
import 'piece_tree_text_buffer.dart';

enum DefaultEndOfLine { lf, crlf }

/// The upstream factory returns both the buffer and the same object as its
/// disposable. Dart callers dispose the [textBuffer] directly.
class PieceTreeTextBufferFactory {
  PieceTreeTextBufferFactory(
    this._chunks,
    this._bom,
    this._cr,
    this._lf,
    this._crlf,
    this._containsRTL,
    this._containsUnusualLineTerminators,
    this._isBasicASCII,
    this._normalizeEOL,
  );

  final List<tree.StringBuffer> _chunks;
  final String _bom;
  final int _cr;
  final int _lf;
  final int _crlf;
  final bool _containsRTL;
  final bool _containsUnusualLineTerminators;
  final bool _isBasicASCII;
  final bool _normalizeEOL;

  String _getEOL(DefaultEndOfLine defaultEOL) {
    final totalEOLCount = _cr + _lf + _crlf;
    if (totalEOLCount == 0) {
      return defaultEOL == DefaultEndOfLine.lf ? '\n' : '\r\n';
    }
    return _cr + _crlf > totalEOLCount / 2 ? '\r\n' : '\n';
  }

  PieceTreeTextBuffer create(DefaultEndOfLine defaultEOL) {
    final eol = _getEOL(defaultEOL);
    final chunks = List<tree.StringBuffer>.of(_chunks);
    if (_normalizeEOL &&
        ((eol == '\r\n' && (_cr > 0 || _lf > 0)) ||
            (eol == '\n' && (_cr > 0 || _crlf > 0)))) {
      for (var i = 0; i < chunks.length; i++) {
        final value = chunks[i].buffer.replaceAll(RegExp(r'\r\n|\r|\n'), eol);
        chunks[i] = tree.StringBuffer(value, tree.createLineStartsFast(value));
      }
    }
    return PieceTreeTextBuffer(
      chunks,
      _bom,
      eol,
      _containsRTL,
      _containsUnusualLineTerminators,
      _isBasicASCII,
      _normalizeEOL,
    );
  }

  String getFirstLineText(int lengthLimit) => _chunks.first.buffer
      .substring(0, lengthLimit.clamp(0, _chunks.first.buffer.length))
      .split(RegExp(r'\r\n|\r|\n'))
      .first;
}

class PieceTreeTextBufferBuilder {
  final List<tree.StringBuffer> _chunks = [];
  final List<int> _tmpLineStarts = [];
  String _bom = '';
  bool _hasPreviousChar = false;
  int _previousChar = 0;
  int _cr = 0;
  int _lf = 0;
  int _crlf = 0;
  bool _containsRTL = false;
  bool _containsUnusualLineTerminators = false;
  bool _isBasicASCII = true;

  void acceptChunk(String chunk) {
    if (chunk.isEmpty) return;
    if (_chunks.isEmpty && _bom.isEmpty && chunk.startsWith('﻿')) {
      _bom = '﻿';
      chunk = chunk.substring(1);
    }
    // Keep a CR or leading UTF-16 surrogate with the next chunk.
    if (chunk.isEmpty) return;
    final lastChar = chunk.codeUnitAt(chunk.length - 1);
    if (lastChar == 13 || (lastChar >= 0xd800 && lastChar <= 0xdbff)) {
      _acceptChunk1(chunk.substring(0, chunk.length - 1), false);
      _hasPreviousChar = true;
      _previousChar = lastChar;
    } else {
      _acceptChunk1(chunk, false);
      _hasPreviousChar = false;
      _previousChar = lastChar;
    }
  }

  void _acceptChunk1(String chunk, bool allowEmptyStrings) {
    if (!allowEmptyStrings && chunk.isEmpty) return;
    _acceptChunk2(
      _hasPreviousChar ? String.fromCharCode(_previousChar) + chunk : chunk,
    );
  }

  void _acceptChunk2(String chunk) {
    final starts = tree.createLineStarts(_tmpLineStarts, chunk);
    _chunks.add(tree.StringBuffer(chunk, starts.lineStarts));
    _cr += starts.cr;
    _lf += starts.lf;
    _crlf += starts.crlf;
    if (!starts.isBasicASCII) {
      _isBasicASCII = false;
      if (!_containsRTL) _containsRTL = containsRTL(chunk);
      if (!_containsUnusualLineTerminators) {
        _containsUnusualLineTerminators = containsUnusualLineTerminators(chunk);
      }
    }
  }

  PieceTreeTextBufferFactory finish([bool normalizeEOL = true]) {
    _finish();
    return PieceTreeTextBufferFactory(
      _chunks,
      _bom,
      _cr,
      _lf,
      _crlf,
      _containsRTL,
      _containsUnusualLineTerminators,
      _isBasicASCII,
      normalizeEOL,
    );
  }

  void _finish() {
    if (_chunks.isEmpty) {
      // A lone deferred CR/surrogate must be appended exactly once. Calling
      // _acceptChunk1 here would prepend it before the append below.
      _acceptChunk2('');
    }
    if (_hasPreviousChar) {
      _hasPreviousChar = false;
      final last = _chunks.removeLast();
      final value = last.buffer + String.fromCharCode(_previousChar);
      _chunks.add(tree.StringBuffer(value, tree.createLineStartsFast(value)));
      if (_previousChar == 13) _cr++;
      if (_previousChar >= 0xd800 && _previousChar <= 0xdbff) {
        _isBasicASCII = false;
      }
    }
  }
}

bool isBasicASCII(String text) =>
    RegExp(r'^[\t\n\r\x20-\x7E]*$').hasMatch(text);

bool containsUnusualLineTerminators(String text) =>
    RegExp(r'[  ]').hasMatch(text);

// The matcher from VS Code base/common/strings.ts, classifying Unicode R/AL.
final RegExp _rtl = RegExp(
  r'(?:[־׀׃׆א-״؈؋؍؛-ي٭-ٯٱ-ەۥۦۮۯۺ-ܐܒ-ܯݍ-ޥޱ-ߪߴߵߺ߾-ࠕࠚࠤࠨ࠰-ࡘ࡞-ࢎࢠ-ࣉ‏יִײַ-ﬨשׁ-ﴽﵐ-ﷇﷰ-﷼ﹰ-ﻼ]|\uD802[\uDC00-\uDD1B\uDD20-\uDE00\uDE10-\uDE35\uDE40-\uDEE4\uDEEB-\uDF35\uDF40-\uDFFF]|\uD803[\uDC00-\uDD23\uDE80-\uDEA9\uDEAD-\uDF45\uDF51-\uDF81\uDF86-\uDFF6]|\uD83A[\uDC00-\uDCCF\uDD00-\uDD43\uDD4B-\uDFFF]|\uD83B[\uDC00-\uDEBB])',
);
bool containsRTL(String text) => _rtl.hasMatch(text);
