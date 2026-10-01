// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/StringBuilder.ts (c58ea36).

/// Accumulates string data from multiple chunks without O(n²) string
/// concatenation.
class StringBuilder {
  final List<String> _chunks = <String>[];
  int _length = 0;

  /// Length in UTF-16 code units.
  int get length => _length;

  void reset() {
    _chunks.clear();
    _length = 0;
  }

  void append(String chunk) {
    _chunks.add(chunk);
    _length += chunk.length;
  }

  @override
  String toString() {
    return _chunks.join();
  }
}

/// String builder that rejects payloads larger than a fixed limit.
class LimitedStringBuilder {
  LimitedStringBuilder(this._limit);

  final StringBuilder _builder = StringBuilder();
  final int _limit;

  int get length => _builder.length;

  int get limit => _limit;

  void reset() {
    _builder.reset();
  }

  /// Returns true if the limit was exceeded (the buffer is cleared in that
  /// case).
  bool append(String chunk) {
    _builder.append(chunk);
    if (_builder.length > _limit) {
      _builder.reset();
      return true;
    }
    return false;
  }

  @override
  String toString() {
    return _builder.toString();
  }
}
