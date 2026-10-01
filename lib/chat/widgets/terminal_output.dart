import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../ide/terminal/terminal_colors.dart';
import '../../ide/terminal/xterm/common/buffer/cell_data.dart';
import '../../ide/terminal/xterm/common/buffer/constants.dart';
import '../../ide/terminal/xterm/common/buffer/types.dart';
import '../../ide/terminal/xterm/common/types.dart';
import '../../ide/terminal/xterm/headless/terminal.dart' as xterm;
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show WorkbenchColors, themeColors;

/// What a command printed, as a terminal shows it: in color, and with what
/// it wrote over (a `\r` progress line, a line erased and printed again) as
/// it ended up.
///
/// Output that asks nothing of a terminal (no escape, `\r` or backspace)
/// comes back as it is, trimmed at the end. The rest goes through a headless
/// terminal wide and long enough to hold it, read back from its buffer.
/// Results are cached by output, which never changes for an item: a new
/// output comes as a new string. They have the theme's colors in them: a
/// new color theme renders them again.
TerminalOutput terminalOutput(String output) {
  if (!output.contains('\x1b') &&
      !output.contains('\r') &&
      !output.contains('\b')) {
    return TerminalOutput._plain(output.trimRight());
  }
  final colors = themeColors;
  final terminal = terminalColorTheme.value;
  if (!identical(colors, _cacheColors) ||
      !identical(terminal, _cacheTerminal)) {
    _cache.clear();
    _cacheColors = colors;
    _cacheTerminal = terminal;
  }
  final result = _cache.remove(output) ?? _render(output);
  _cache[output] = result;
  if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
  return result;
}

/// The last outputs rendered, least recently used first: enough for the
/// open steps of a conversation and the growing output of a running one.
final _cache = <String, TerminalOutput>{};
const _cacheSize = 64;

/// The themes [_cache] was rendered in.
WorkbenchColors? _cacheColors;
TerminalColorTheme? _cacheTerminal;

/// The widest a line gets before it wraps (and is joined back).
const _maxColumns = 500;

/// The fewest columns: programs assume a screen at least this wide, e.g.
/// to move right.
const _minColumns = 80;

/// The terminal's rows: how far up a program can move to rewrite.
const _screenRows = 50;

/// The most lines kept; longer output keeps its end, as a terminal's
/// scrollback does.
const _maxLines = 10000;

/// The most cells the terminal holds (12 bytes each): very long output gets
/// fewer columns, its long lines wrapping and joined back.
const _maxCells = 1 << 20;

/// The step's own colors stand for the terminal's default ones: its text on
/// its box.
Color get _foreground => AppColors.textMuted;
Color get _background => AppColors.code;

/// The terminal's palette, the color theme's ([terminalColorTheme]).
List<Color> get _palette => terminalColorTheme.value.palette;

/// [output] written to a headless terminal and read back.
TerminalOutput _render(String output) {
  // One column per code unit of the longest line (two where it may be
  // wide, eight for a tab), so that nothing wraps that would not on a wide
  // screen.
  var lines = 1;
  var widest = 0;
  var width = 0;
  var total = 0;
  for (var i = 0; i < output.length; i++) {
    final unit = output.codeUnitAt(i);
    if (unit == 0x0A) {
      lines++;
      widest = math.max(widest, width);
      width = 0;
      continue;
    }
    final cells = unit == 0x09 ? 8 : (unit < 0x1100 ? 1 : 2);
    width += cells;
    total += cells;
  }
  widest = math.max(widest, width);
  final cols = math.min(
    widest.clamp(_minColumns, _maxColumns),
    math.max(_minColumns, _maxCells ~/ math.min(lines, _maxLines)),
  );
  final rows = math.min(lines, _screenRows);
  // Every line (the long ones wrapped), the screen on top: room for a clear
  // to push it up.
  final scrollback = math.min(lines + total ~/ cols, _maxLines);

  final terminal = xterm.Terminal(
    ITerminalOptions(
      cols: cols,
      rows: rows,
      scrollback: scrollback,
      // Agents' output has bare `\n`s.
      convertEol: true,
      // A clear keeps what was printed before it, as in VS Code.
      scrollOnEraseInDisplay: true,
      logLevel: 'off',
    ),
  );
  try {
    terminal.writeSync(output);
    final buffers = terminal.buffers;
    return _output([
      ..._lines(buffers.normal),
      // Still on the alternate screen (a full-screen program cut short):
      // what it shows follows.
      if (buffers.active == buffers.alt) ..._lines(buffers.alt),
    ]);
  } finally {
    terminal.dispose();
  }
}

typedef _Style = ({
  Color? foreground,
  Color? background,
  bool bold,
  bool italic,
  bool underline,
  bool strikethrough,
});

/// [buffer]'s lines, rows that wrap joined, as pieces of one style each;
/// without the empty lines at the end.
List<List<(String, _Style)>> _lines(IBuffer buffer) {
  final lines = <List<(String, _Style)>>[];
  final cell = CellData();
  final rows = buffer.lines;
  for (var y = 0; y < rows.length; y++) {
    final row = rows.get(y)!;
    if (!row.isWrapped || lines.isEmpty) lines.add([]);
    final line = lines.last;
    // A row the next continues counts whole.
    final end = (y + 1 < rows.length && rows.get(y + 1)!.isWrapped)
        ? row.length
        : row.getTrimmedLength();
    var start = 0;
    while (start < end) {
      final fg = row.getFg(start);
      final bg = row.getBg(start);
      var stop = start + 1;
      while (stop < end &&
          (row.getWidth(stop) == 0 ||
              (row.getFg(stop) == fg && row.getBg(stop) == bg))) {
        stop++;
      }
      row.loadCell(start, cell);
      line.add((row.translateToString(false, start, stop), _styleOf(cell)));
      start = stop;
    }
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// [cell]'s look as VS Code's terminal draws it: inverse swaps the colors
/// (the default ones too), bold brightens the first eight, dim halves the
/// text's opacity and invisible text is not seen.
_Style _styleOf(CellData cell) {
  final inverse = cell.isInverse() != 0;
  final bold = cell.isBold() != 0;
  var foreground =
      _color(inverse ? cell.bg : cell.fg, bright: bold) ??
      (inverse ? _background : null);
  final background =
      _color(inverse ? cell.fg : cell.bg) ?? (inverse ? _foreground : null);
  if (cell.isInvisible() != 0) {
    foreground = const Color(0x00000000);
  } else if (cell.isDim() != 0) {
    foreground = (foreground ?? _foreground).withValues(alpha: 0.5);
  }
  return (
    foreground: foreground,
    background: background,
    bold: bold,
    italic: cell.isItalic() != 0,
    underline: cell.isUnderline() != 0,
    strikethrough: cell.isStrikethrough() != 0,
  );
}

/// The color of an attribute word, null for the default.
Color? _color(int word, {bool bright = false}) {
  switch (word & Attributes.cmMask) {
    case Attributes.cmP16:
    case Attributes.cmP256:
      final index = word & Attributes.pcolorMask;
      return _palette[bright && index < 8 ? index + 8 : index];
    case Attributes.cmRgb:
      return Color(0xFF000000 | (word & Attributes.rgbMask));
  }
  return null;
}

/// [lines] as runs of one style, trimmed at the end.
TerminalOutput _output(List<List<(String, _Style)>> lines) {
  final runs = <TerminalRun>[];
  final text = StringBuffer();
  _Style? style;
  void flush() {
    if (style case final style? when text.isNotEmpty) {
      runs.add(
        TerminalRun(
          text.toString(),
          foreground: style.foreground,
          background: style.background,
          bold: style.bold,
          italic: style.italic,
          underline: style.underline,
          strikethrough: style.strikethrough,
        ),
      );
    }
    text.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    // A line break goes with whatever comes before it.
    if (i > 0) text.write('\n');
    for (final (piece, pieceStyle) in lines[i]) {
      if (pieceStyle != style && text.isNotEmpty) flush();
      style = pieceStyle;
      text.write(piece);
    }
    style ??= _plainStyle;
  }
  flush();

  while (runs.isNotEmpty) {
    final last = runs.removeLast();
    final trimmed = last.text.trimRight();
    if (trimmed.isEmpty) continue;
    runs.add(last._withText(trimmed));
    break;
  }
  return TerminalOutput._(runs);
}

const _Style _plainStyle = (
  foreground: null,
  background: null,
  bold: false,
  italic: false,
  underline: false,
  strikethrough: false,
);

/// What a command printed, as shown: [terminalOutput].
class TerminalOutput {
  TerminalOutput._(this.runs)
    : text = runs.map((run) => run.text).join(),
      styled = runs.any((run) => run.style != null);

  TerminalOutput._plain(this.text)
    : runs = [if (text.isNotEmpty) TerminalRun(text)],
      styled = false;

  /// The text shown, its lines joined with `\n`: what copying it gives.
  final String text;

  /// [text] in runs of one style each.
  final List<TerminalRun> runs;

  /// Whether any run has a style of its own; else [text] shows plain.
  final bool styled;

  /// [runs] as spans, over the step's style.
  late final TextSpan span = TextSpan(
    children: [
      for (final run in runs) TextSpan(text: run.text, style: run.style),
    ],
  );
}

/// A run of output in one style. A null color is the step's own: its text's,
/// or no background.
class TerminalRun {
  const TerminalRun(
    this.text, {
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
  });

  final String text;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  /// Its style over the step's, null when it has none.
  TextStyle? get style {
    if (foreground == null &&
        background == null &&
        !bold &&
        !italic &&
        !underline &&
        !strikethrough) {
      return null;
    }
    return TextStyle(
      color: foreground,
      backgroundColor: background,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline || strikethrough
          ? TextDecoration.combine([
              if (underline) TextDecoration.underline,
              if (strikethrough) TextDecoration.lineThrough,
            ])
          : null,
    );
  }

  TerminalRun _withText(String text) => TerminalRun(
    text,
    foreground: foreground,
    background: background,
    bold: bold,
    italic: italic,
    underline: underline,
    strikethrough: strikethrough,
  );

  @override
  bool operator ==(Object other) =>
      other is TerminalRun &&
      other.text == text &&
      other.foreground == foreground &&
      other.background == background &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough;

  @override
  int get hashCode => Object.hash(
    text,
    foreground,
    background,
    bold,
    italic,
    underline,
    strikethrough,
  );

  @override
  String toString() {
    final attributes = [
      if (foreground case final color?) 'foreground: $color',
      if (background case final color?) 'background: $color',
      if (bold) 'bold',
      if (italic) 'italic',
      if (underline) 'underline',
      if (strikethrough) 'strikethrough',
    ];
    return 'TerminalRun(${[jsonEncode(text), ...attributes].join(', ')})';
  }
}
