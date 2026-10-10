import 'package:flutter/material.dart';

/// BaoCode's mark and name, side by side, drawn in pixels on one grid: every
/// stroke, the mark's and the letters', is one [cell] wide. Drawn rather than
/// set in a font, so nothing is bundled for seven letters.
class BaoWordmark extends StatelessWidget {
  const BaoWordmark({super.key, required this.color, this.cell = 2});

  final Color color;

  /// One dot of the grid, in logical pixels.
  final double cell;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'BaoCode',
      child: CustomPaint(
        size: _WordmarkPainter.sizeFor(cell),
        painter: _WordmarkPainter(color: color, cell: cell),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter({required this.color, required this.cell});

  final Color color;
  final double cell;

  /// The mark: the brand asset's 8 × 6 bun, a dot to its cells.
  static const _mark = [
    '..####..',
    '.#....#.',
    '#......#',
    '#.#..#.#',
    '#......#',
    '.######.',
  ];

  /// 5 × 5 capitals, sitting on the mark's bottom row; set wide, a small
  /// label rather than a title.
  static const _glyphs = {
    'B': ['####.', '#...#', '####.', '#...#', '####.'],
    'A': ['.###.', '#...#', '#####', '#...#', '#...#'],
    'O': ['.###.', '#...#', '#...#', '#...#', '.###.'],
    'C': ['.####', '#....', '#....', '#....', '.####'],
    'D': ['####.', '#...#', '#...#', '#...#', '####.'],
    'E': ['#####', '#....', '####.', '#....', '#####'],
  };
  static const _word = 'BAOCODE';
  static const _glyphW = 5, _glyphH = 5, _tracking = 2;

  /// Between the mark and the name.
  static const _gap = 4;

  static int get _markW => _mark.first.length;
  static int get _markH => _mark.length;

  static Size sizeFor(double cell) => Size(
    (_markW + _gap + _word.length * (_glyphW + _tracking) - _tracking) * cell,
    _markH * cell,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    void dots(List<String> rows, int col, int row) {
      for (var y = 0; y < rows.length; y++) {
        for (var x = 0; x < rows[y].length; x++) {
          if (rows[y][x] != '#') continue;
          canvas.drawRect(
            Rect.fromLTWH((col + x) * cell, (row + y) * cell, cell, cell),
            paint,
          );
        }
      }
    }

    dots(_mark, 0, 0);
    final row = _markH - _glyphH;
    var col = _markW + _gap;
    for (final letter in _word.split('')) {
      dots(_glyphs[letter]!, col, row);
      col += _glyphW + _tracking;
    }
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      old.color != color || old.cell != cell;
}
