/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/output/common/outputChannelModel.ts
// (`LOG_ENTRY_REGEX`, `parseLogEntryAt`: a log entry is its line and the
// lines after it up to the next entry).
//
// Deviations: an output channel's text is kept as lines (the panel shows
// them in a list, not a text model), at most [OutputText.maxChars]
// characters: the oldest lines go first.

import '../../host/init_data.dart' show ExtHostLogLevel;

/// `LOG_ENTRY_REGEX`: `2024-01-31 12:00:00.000 [info] [category]`.
final logEntryPattern = RegExp(
  r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\s(\[(info|trace|debug|error|warning)\])\s(\[(.*?)\])?',
);

/// The level a log line starts with; null when it is not an entry's first
/// line.
ExtHostLogLevel? logLevelOfLine(String line) =>
    switch (logEntryPattern.firstMatch(line)?.group(3)) {
      'trace' => ExtHostLogLevel.trace,
      'debug' => ExtHostLogLevel.debug,
      'info' => ExtHostLogLevel.info,
      'warning' => ExtHostLogLevel.warning,
      'error' => ExtHostLogLevel.error,
      _ => null,
    };

/// An output channel's text, as lines, appended to in pieces of any size
/// (a line can come in several).
final class OutputText {
  OutputText({this.maxChars = defaultMaxChars, this.parseLevels = false});

  static const defaultMaxChars = 4 * 1024 * 1024;

  /// The most kept; past it, the oldest lines are dropped (down to three
  /// quarters, so that it is not done on every append).
  final int maxChars;

  /// Whether lines are log entries (`[info]`…) whose [levelAt] the panel
  /// filters on.
  final bool parseLevels;

  final List<String> _lines = [];
  final List<ExtHostLogLevel?> _levels = [];

  /// The last line, not ended yet.
  String _partial = '';
  int _chars = 0;

  /// Lines dropped from the start to keep under [maxChars] since the last
  /// [clear].
  int get droppedLines => _droppedLines;
  int _droppedLines = 0;

  /// Bumped by each change.
  int get revision => _revision;
  int _revision = 0;

  int get length => _lines.length + (_partial.isEmpty ? 0 : 1);
  bool get isEmpty => length == 0;

  String operator [](int index) {
    final line = index < _lines.length ? _lines[index] : _partial;
    return line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  }

  /// The level of the log entry line [index] is part of (null before the
  /// first entry, or when not [parseLevels]).
  ExtHostLogLevel? levelAt(int index) {
    if (!parseLevels) return null;
    if (index < _levels.length) return _levels[index];
    return logLevelOfLine(_partial) ??
        (_levels.isEmpty ? null : _levels.last);
  }

  /// All of it, lines joined with `\n`.
  String get text => [for (var i = 0; i < length; i++) this[i]].join('\n');

  void append(String text) {
    if (text.isEmpty) return;
    _revision++;
    final pieces = (_partial + text).split('\n');
    _chars -= _partial.length;
    _partial = pieces.removeLast();
    for (final line in pieces) {
      _lines.add(line);
      _chars += line.length + 1;
      if (parseLevels) {
        _levels.add(
          logLevelOfLine(line) ?? (_levels.isEmpty ? null : _levels.last),
        );
      }
    }
    _chars += _partial.length;
    if (_chars > maxChars) _trim();
  }

  void clear() {
    if (_lines.isEmpty && _partial.isEmpty && _droppedLines == 0) return;
    _revision++;
    _lines.clear();
    _levels.clear();
    _partial = '';
    _chars = 0;
    _droppedLines = 0;
  }

  void _trim() {
    final target = maxChars * 3 ~/ 4;
    var drop = 0;
    while (drop < _lines.length && _chars > target) {
      _chars -= _lines[drop].length + 1;
      drop++;
    }
    _lines.removeRange(0, drop);
    if (parseLevels) _levels.removeRange(0, drop);
    _droppedLines += drop;
    if (_chars > target && _partial.length > target) {
      // One line longer than all that is kept: its end.
      _chars -= _partial.length - target;
      _partial = _partial.substring(_partial.length - target);
      _droppedLines++;
    }
  }
}
