// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See packages/bao_xterm/lib/LICENSE.txt.
// Ported from xterm.js addons/addon-webgl/src/customGlyphs/CustomGlyphRasterizer.ts (c58ea36).
//
// Box drawing, block elements, shades, Powerline, sextants, legacy computing
// symbols and braille drawn by hand from customGlyphDefinitions, so that
// cells join without seams whatever the font. Upstream draws into the WebGL
// texture atlas' 2D context in device pixels; here the same geometry is drawn
// on a dart:ui Canvas: [paintCustomGlyph] scales the canvas to device pixels
// and runs upstream's code on it, with its pixel snapping (path functions'
// coordinates rounded to half pixels) and line widths (`devicePixelRatio *
// strokeWidth`, Powerline strokes `devicePixelRatio * fontSize / 12`).
//
// Deviations:
// - Shade patterns are drawn as device-pixel squares instead of a
//   CanvasPattern (no pattern canvas, so `createPatternCanvas` is not ported),
//   in the color's own alpha: upstream makes a `#rrggbbaa` fill opaque.
// - A negative glyph without a background color is cut out of its fill
//   (transparent) instead of drawn in the foreground over itself, and is
//   clipped to its rect, where upstream relies on the atlas dropping pixels
//   in the background color.
// - Unknown path commands are skipped without upstream's log message; the
//   shipped definitions have none (see the tests).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bao_xterm/addons/addon_webgl/custom_glyphs/custom_glyph_definitions.dart';
import 'package:bao_xterm/addons/addon_webgl/custom_glyphs/types.dart';

export 'package:bao_xterm/addons/addon_webgl/custom_glyphs/custom_glyph_definitions.dart'
    show blockPatternCodepoints;

/// Whether [codePoint] is drawn by [paintCustomGlyph] rather than the font.
bool isCustomGlyph(int codePoint) =>
    _definitionsByCodePoint.containsKey(codePoint);

/// Upstream's `tryDrawCustomGlyph`: paints [codePoint] in [color] into
/// [cell], returning whether it is a custom glyph (nothing is painted
/// otherwise).
///
/// [cell] is in the canvas' logical pixels, which [devicePixelRatio] maps to
/// device pixels; like xterm.js' cells it should start and end on device
/// pixels for lines to be crisp and to join. [fontSize] is the font size in
/// logical pixels (Powerline stroke widths follow it). [charSize] is the
/// character area without letter spacing and line height, centered in the
/// cell, for the glyphs drawn to it; it defaults to the cell's size.
///
/// [backgroundColor] is the cell's background, which the "negative" glyphs
/// (U+1FBB1, U+1FBB4, U+1FBBD-U+1FBBF) draw their shape in over a
/// foreground fill; without it the shape is cut out (transparent).
///
/// [variantOffset] shifts the shade patterns ([blockPatternCodepoints]):
/// bit 1 by one device pixel left, bit 0 one up. Upstream sets it to
/// `((x * deviceCellWidth) % 2) * 2 + ((y * deviceCellHeight) % 2)` for the
/// cell at column x and row y, so that shades tile across cells of odd
/// sizes. When null the pattern is anchored to the canvas' device pixel
/// origin, which is the same for cells painted in place.
bool paintCustomGlyph(
  Canvas canvas,
  int codePoint,
  Rect cell,
  Color color, {
  required double devicePixelRatio,
  required double fontSize,
  Size? charSize,
  Color? backgroundColor,
  int? variantOffset,
}) {
  final parts = _definitionsByCodePoint[codePoint];
  if (parts == null) {
    return false;
  }
  final dpr = devicePixelRatio;
  final xOffset = _snap(cell.left * dpr);
  final yOffset = _snap(cell.top * dpr);
  final deviceCellWidth = _snap(cell.width * dpr);
  final deviceCellHeight = _snap(cell.height * dpr);
  final deviceCharWidth = charSize == null
      ? deviceCellWidth
      : _snap(charSize.width * dpr);
  final deviceCharHeight = charSize == null
      ? deviceCellHeight
      : _snap(charSize.height * dpr);
  canvas.save();
  canvas.scale(1 / dpr);
  for (final part in parts) {
    _drawDefinitionPart(
      canvas,
      color,
      part,
      xOffset,
      yOffset,
      deviceCellWidth,
      deviceCellHeight,
      deviceCharWidth,
      deviceCharHeight,
      fontSize,
      dpr,
      backgroundColor,
      variantOffset,
    );
  }
  canvas.restore();
  return true;
}

final Map<int, CustomGlyphCharacterDefinition> _definitionsByCodePoint = {
  for (final entry in customGlyphDefinitions.entries)
    entry.key.runes.single: entry.value,
};

/// Removes floating point noise from logical-to-device conversions, so that
/// cells on device pixels stay exactly on them.
double _snap(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < 1e-6 ? rounded : value;
}

void _drawDefinitionPart(
  Canvas ctx,
  Color color,
  CustomGlyphDefinitionPart part,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
  double deviceCharWidth,
  double deviceCharHeight,
  double fontSize,
  double devicePixelRatio,
  Color? backgroundColor,
  int? variantOffset,
) {
  // Handle scaleType - adjust dimensions and offset when scaling to character
  // area
  var drawWidth = deviceCellWidth;
  var drawHeight = deviceCellHeight;
  var drawXOffset = xOffset;
  var drawYOffset = yOffset;
  if (part.scaleType == CustomGlyphScaleType.char) {
    drawWidth = deviceCharWidth;
    drawHeight = deviceCharHeight;
    // Center the character within the cell
    drawXOffset = xOffset + (deviceCellWidth - deviceCharWidth) / 2;
    drawYOffset = yOffset + (deviceCellHeight - deviceCharHeight) / 2;
  }

  // Handle clipPath generically for any definition type
  final clipPath = part.clipPath;
  if (clipPath != null) {
    ctx.save();
    _applyClipPath(
      ctx,
      clipPath,
      drawXOffset,
      drawYOffset,
      drawWidth,
      drawHeight,
    );
  }

  switch (part.type) {
    case CustomGlyphDefinitionType.solidOctantBlockVector:
      _drawBlockVectorChar(
        ctx,
        color,
        part.data as List<ICustomGlyphSolidOctantBlockVector>,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
      );
    case CustomGlyphDefinitionType.blockPattern:
      _drawPatternChar(
        ctx,
        color,
        part.data as CustomGlyphPatternDefinition,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
        variantOffset,
      );
    case CustomGlyphDefinitionType.pathFunction:
      _drawPathFunctionCharacter(
        ctx,
        color,
        part.data,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
        devicePixelRatio,
        part.strokeWidth,
      );
    case CustomGlyphDefinitionType.path:
      _drawPathDefinitionCharacter(
        ctx,
        color,
        part.data,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
        devicePixelRatio,
        part.strokeWidth,
      );
    case CustomGlyphDefinitionType.pathNegative:
      _drawPathNegativeDefinitionCharacter(
        ctx,
        color,
        part.data as ICustomGlyphVectorShape,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
        devicePixelRatio,
        backgroundColor,
      );
    case CustomGlyphDefinitionType.vectorShape:
      _drawVectorShape(
        ctx,
        color,
        part.data as ICustomGlyphVectorShape,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
        fontSize,
        devicePixelRatio,
      );
    case CustomGlyphDefinitionType.braille:
      _drawBrailleCharacter(
        ctx,
        color,
        part.data as int,
        drawXOffset,
        drawYOffset,
        drawWidth,
        drawHeight,
      );
  }

  if (clipPath != null) {
    ctx.restore();
  }
}

Paint _fill(Color color) => Paint()..color = color;

/// The 2D context's stroke defaults: butt caps, miter joins, miter limit 10.
Paint _stroke(Color color, double lineWidth) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = lineWidth
  ..strokeMiterLimit = 10;

void _drawBlockVectorChar(
  Canvas ctx,
  Color color,
  List<ICustomGlyphSolidOctantBlockVector> charDefinition,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
) {
  final paint = _fill(color);
  for (var i = 0; i < charDefinition.length; i++) {
    final box = charDefinition[i];
    final xEighth = deviceCellWidth / 8;
    final yEighth = deviceCellHeight / 8;
    ctx.drawRect(
      Rect.fromLTWH(
        xOffset + box.x * xEighth,
        yOffset + box.y * yEighth,
        box.w * xEighth,
        box.h * yEighth,
      ),
      paint,
    );
  }
}

/// Braille dot positions in octant coordinates (x, y for center of each dot
/// area). Columns: left=1-2, right=5-6 (leaving 0 and 7 as margins, 3-4 as
/// gap). Rows: 0-1, 2-3, 4-5, 6-7 for the 4 rows.
final Uint8List _brailleDotPositions = Uint8List.fromList([
  1, 0, // dot 1 - bit 0
  1, 2, // dot 2 - bit 1
  1, 4, // dot 3 - bit 2
  5, 0, // dot 4 - bit 3
  5, 2, // dot 5 - bit 4
  5, 4, // dot 6 - bit 5
  1, 6, // dot 7 - bit 6
  5, 6, // dot 8 - bit 7
]);

/// Draws a braille pattern
void _drawBrailleCharacter(
  Canvas ctx,
  Color color,
  int pattern,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
) {
  final xEighth = deviceCellWidth / 8;
  final paddingY = deviceCellHeight * 0.1;
  final usableHeight = deviceCellHeight * 0.8;
  final yEighth = usableHeight / 8;
  final radius = math.min(xEighth, yEighth);
  final paint = _fill(color);

  for (var bit = 0; bit < 8; bit++) {
    if (pattern & (1 << bit) != 0) {
      final x = _brailleDotPositions[bit * 2];
      final y = _brailleDotPositions[bit * 2 + 1];
      final cx = xOffset + (x + 1) * xEighth;
      final cy = yOffset + paddingY + (y + 1) * yEighth;
      ctx.drawCircle(Offset(cx, cy), radius, paint);
    }
  }
}

void _drawPathDefinitionCharacter(
  Canvas ctx,
  Color color,
  Object charDefinition,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
  double devicePixelRatio,
  double? strokeWidth,
) {
  final instructions = charDefinition is String
      ? charDefinition
      : (charDefinition as CustomGlyphPathDrawFunctionDefinition)(0, 0);
  final path = Path();
  var currentX = 0.0;
  var currentY = 0.0;
  var lastControlX = 0.0;
  var lastControlY = 0.0;
  var lastCommand = '';
  for (final instruction in instructions.split(' ')) {
    final type = instruction.isEmpty ? '' : instruction[0];
    final args = instruction.isEmpty
        ? const ['']
        : instruction.substring(1).split(',');
    if (type == 'Z') {
      path.close();
      lastCommand = type;
      continue;
    }
    if (type == 'V') {
      final y = yOffset + _parseFloat(args[0]) * deviceCellHeight;
      path.lineTo(currentX, y);
      currentY = y;
      lastControlX = currentX;
      lastControlY = currentY;
      lastCommand = type;
      continue;
    }
    if (type == 'H') {
      final x = xOffset + _parseFloat(args[0]) * deviceCellWidth;
      path.lineTo(x, currentY);
      currentX = x;
      lastControlX = currentX;
      lastControlY = currentY;
      lastCommand = type;
      continue;
    }
    if (args.length < 2 || args[0].isEmpty || args[1].isEmpty) {
      continue;
    }
    if (type == 'A') {
      // SVG arc: A rx,ry,xAxisRotation,largeArcFlag,sweepFlag,x,y
      final rx = _parseFloat(args[0]) * deviceCellWidth;
      final ry = _parseFloat(args[1]) * deviceCellHeight;
      final xAxisRotation = _parseFloat(args[2]) * math.pi / 180;
      final largeArcFlag = _parseInt(args[3], 10);
      final sweepFlag = _parseInt(args[4], 10);
      final x = xOffset + _parseFloat(args[5]) * deviceCellWidth;
      final y = yOffset + _parseFloat(args[6]) * deviceCellHeight;
      _drawSvgArc(
        path,
        currentX,
        currentY,
        rx,
        ry,
        xAxisRotation,
        largeArcFlag,
        sweepFlag,
        x,
        y,
      );
      currentX = x;
      currentY = y;
      continue;
    }
    final translatedArgs = [
      for (var i = 0; i < args.length; i++)
        i % 2 == 0
            ? xOffset + _parseFloat(args[i]) * deviceCellWidth
            : yOffset + _parseFloat(args[i]) * deviceCellHeight,
    ];
    if (type == 'M') {
      path.moveTo(translatedArgs[0], translatedArgs[1]);
      currentX = translatedArgs[0];
      currentY = translatedArgs[1];
      lastControlX = currentX;
      lastControlY = currentY;
    } else if (type == 'L') {
      path.lineTo(translatedArgs[0], translatedArgs[1]);
      currentX = translatedArgs[0];
      currentY = translatedArgs[1];
      lastControlX = currentX;
      lastControlY = currentY;
    } else if (type == 'Q') {
      path.quadraticBezierTo(
        translatedArgs[0],
        translatedArgs[1],
        translatedArgs[2],
        translatedArgs[3],
      );
      lastControlX = translatedArgs[0];
      lastControlY = translatedArgs[1];
      currentX = translatedArgs[2];
      currentY = translatedArgs[3];
    } else if (type == 'T') {
      // T uses reflection of last control point if previous command was Q or T
      double cpX;
      double cpY;
      if (lastCommand == 'Q' || lastCommand == 'T') {
        cpX = 2 * currentX - lastControlX;
        cpY = 2 * currentY - lastControlY;
      } else {
        cpX = currentX;
        cpY = currentY;
      }
      path.quadraticBezierTo(cpX, cpY, translatedArgs[0], translatedArgs[1]);
      lastControlX = cpX;
      lastControlY = cpY;
      currentX = translatedArgs[0];
      currentY = translatedArgs[1];
    } else if (type == 'C') {
      path.cubicTo(
        translatedArgs[0],
        translatedArgs[1],
        translatedArgs[2],
        translatedArgs[3],
        translatedArgs[4],
        translatedArgs[5],
      );
      lastControlX = translatedArgs[2];
      lastControlY = translatedArgs[3];
      currentX = translatedArgs[4];
      currentY = translatedArgs[5];
    }
    lastCommand = type;
  }
  if (strokeWidth != null) {
    ctx.drawPath(path, _stroke(color, devicePixelRatio * strokeWidth));
  } else {
    ctx.drawPath(path, _fill(color));
  }
}

/// Converts SVG arc parameters to a center parameterized arc. Based on the
/// SVG spec's endpoint to center parameterization conversion.
void _drawSvgArc(
  Path ctx,
  double x1,
  double y1,
  double rx,
  double ry,
  double phi,
  double largeArcFlag,
  double sweepFlag,
  double x2,
  double y2,
) {
  // Handle degenerate cases
  if (rx == 0 || ry == 0) {
    ctx.lineTo(x2, y2);
    return;
  }

  rx = rx.abs();
  ry = ry.abs();

  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  // Step 1: Compute (x1', y1')
  final dx = (x1 - x2) / 2;
  final dy = (y1 - y2) / 2;
  final x1p = cosPhi * dx + sinPhi * dy;
  final y1p = -sinPhi * dx + cosPhi * dy;

  // Step 2: Compute (cx', cy')
  var rxSq = rx * rx;
  var rySq = ry * ry;
  final x1pSq = x1p * x1p;
  final y1pSq = y1p * y1p;

  // Correct radii if necessary
  final lambda = x1pSq / rxSq + y1pSq / rySq;
  if (lambda > 1) {
    final lambdaSqrt = math.sqrt(lambda);
    rx *= lambdaSqrt;
    ry *= lambdaSqrt;
    rxSq = rx * rx;
    rySq = ry * ry;
  }

  var sq =
      (rxSq * rySq - rxSq * y1pSq - rySq * x1pSq) /
      (rxSq * y1pSq + rySq * x1pSq);
  if (sq < 0) sq = 0;
  final coef = (largeArcFlag == sweepFlag ? -1 : 1) * math.sqrt(sq);
  final cxp = coef * (rx * y1p / ry);
  final cyp = coef * -(ry * x1p / rx);

  // Step 3: Compute (cx, cy) from (cx', cy')
  final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
  final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

  // Step 4: Compute angles
  final ux = (x1p - cxp) / rx;
  final uy = (y1p - cyp) / ry;
  final vx = (-x1p - cxp) / rx;
  final vy = (-y1p - cyp) / ry;

  final startAngle = math.atan2(uy, ux);
  var dTheta = math.atan2(vy, vx) - startAngle;

  if (sweepFlag == 0 && dTheta > 0) {
    dTheta -= 2 * math.pi;
  } else if (sweepFlag == 1 && dTheta < 0) {
    dTheta += 2 * math.pi;
  }

  _ellipse(ctx, cx, cy, rx, ry, phi, startAngle, dTheta);
}

/// The 2D context's `ellipse`: a line to the arc's start, then the arc,
/// sweeping [sweepAngle] (negative is counterclockwise) from [startAngle].
void _ellipse(
  Path ctx,
  double cx,
  double cy,
  double rx,
  double ry,
  double rotation,
  double startAngle,
  double sweepAngle,
) {
  if (rotation == 0) {
    ctx.arcTo(
      Rect.fromCenter(center: Offset(cx, cy), width: 2 * rx, height: 2 * ry),
      startAngle,
      sweepAngle,
      false,
    );
    return;
  }
  final arc = Path()
    ..arcTo(
      Rect.fromCenter(center: Offset.zero, width: 2 * rx, height: 2 * ry),
      startAngle,
      sweepAngle,
      true,
    );
  final cos = math.cos(rotation);
  final sin = math.sin(rotation);
  ctx.extendWithPath(
    arc,
    Offset.zero,
    matrix4: Float64List.fromList([
      cos, sin, 0, 0, //
      -sin, cos, 0, 0,
      0, 0, 1, 0,
      cx, cy, 0, 1,
    ]),
  );
}

/// Draws a "negative" path where the background color is used to draw the
/// shape on top of a foreground-filled cell. This creates the appearance of a
/// cutout without using actual transparency, which allows SPAA (subpixel
/// anti-aliasing) to work correctly. Without [backgroundColor] the shape is
/// cut out.
void _drawPathNegativeDefinitionCharacter(
  Canvas ctx,
  Color color,
  ICustomGlyphVectorShape charDefinition,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
  double devicePixelRatio,
  Color? backgroundColor,
) {
  final rect = Rect.fromLTWH(
    xOffset,
    yOffset,
    deviceCellWidth,
    deviceCellHeight,
  );
  ctx.save();
  // Upstream's square caps reach past the rect in the background color, which
  // the atlas drops; clip so that the neighbours are left alone.
  ctx.clipRect(rect);
  if (backgroundColor == null) {
    ctx.saveLayer(rect, Paint());
  }

  // First, fill the entire cell with foreground color
  ctx.drawRect(rect, _fill(color));

  // Then draw the "negative" shape with the background color
  final paint = Paint()
    ..color = backgroundColor ?? const Color(0xFF000000)
    ..blendMode = backgroundColor == null ? BlendMode.clear : BlendMode.srcOver
    ..strokeWidth = devicePixelRatio
    ..strokeCap = StrokeCap.square
    ..strokeMiterLimit = 10;
  final path = Path();
  for (final instruction in charDefinition.d.split(' ')) {
    final type = instruction.isEmpty ? '' : instruction[0];
    final args = instruction.isEmpty
        ? const ['']
        : instruction.substring(1).split(',');
    if (args.length < 2 || args[0].isEmpty || args[1].isEmpty) {
      if (type == 'Z') {
        path.close();
      }
      continue;
    }
    final translatedArgs = [
      for (var i = 0; i < args.length; i++)
        i % 2 == 0
            ? xOffset + _parseFloat(args[i]) * deviceCellWidth
            : yOffset + _parseFloat(args[i]) * deviceCellHeight,
    ];
    if (type == 'M') {
      path.moveTo(translatedArgs[0], translatedArgs[1]);
    } else if (type == 'L') {
      path.lineTo(translatedArgs[0], translatedArgs[1]);
    }
  }

  if (charDefinition.type == CustomGlyphVectorType.stroke) {
    paint.style = PaintingStyle.stroke;
  }
  ctx.drawPath(path, paint);

  if (backgroundColor == null) {
    ctx.restore();
  }
  ctx.restore();
}

/// Pixel squares of a pattern over a rect of whole device pixels, by the
/// pattern, the rect's phase in it and its size.
final Map<(CustomGlyphPatternDefinition, int, int, int, int), Path>
_cachedPatterns = {};

void _drawPatternChar(
  Canvas ctx,
  Color color,
  CustomGlyphPatternDefinition charDefinition,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
  int? variantOffset,
) {
  final width = charDefinition[0].length;
  final height = charDefinition.length;
  // Upstream fills the cell with a repeating pattern whose pixel (0, 0) is on
  // the atlas' device pixel (-dx, -dy), cells being drawn at even offsets.
  int originX = 0;
  int originY = 0;
  if (variantOffset != null) {
    // Apply pattern offset to ensure seamless tiling across cells when cell
    // dimensions are odd. variantOffset encodes: bit 1 = x pixel shift, bit 0
    // = y pixel shift.
    final dx = (variantOffset >> 1) & 1;
    final dy = variantOffset & 1;
    originX = xOffset.round() - dx;
    originY = yOffset.round() - dy;
  }
  final left = xOffset.floor();
  final top = yOffset.floor();
  final right = (xOffset + deviceCellWidth).ceil();
  final bottom = (yOffset + deviceCellHeight).ceil();
  final phaseX = (left - originX) % width;
  final phaseY = (top - originY) % height;
  final w = right - left;
  final h = bottom - top;
  if (_cachedPatterns.length > 64) {
    _cachedPatterns.clear();
  }
  final path = _cachedPatterns[(charDefinition, phaseX, phaseY, w, h)] ??=
      _patternPath(charDefinition, phaseX, phaseY, w, h);
  ctx.save();
  ctx.clipRect(
    Rect.fromLTWH(xOffset, yOffset, deviceCellWidth, deviceCellHeight),
  );
  ctx.translate(left.toDouble(), top.toDouble());
  ctx.drawPath(
    path,
    Paint()
      ..color = color
      ..isAntiAlias = false,
  );
  ctx.restore();
}

Path _patternPath(
  CustomGlyphPatternDefinition pattern,
  int phaseX,
  int phaseY,
  int w,
  int h,
) {
  final path = Path();
  for (var y = 0; y < h; y++) {
    final row = pattern[(y + phaseY) % pattern.length];
    var x = 0;
    while (x < w) {
      if (row[(x + phaseX) % row.length] == 0) {
        x++;
        continue;
      }
      // A run of set pixels as one rect.
      final start = x;
      while (x < w && row[(x + phaseX) % row.length] != 0) {
        x++;
      }
      path.addRect(
        Rect.fromLTWH(
          start.toDouble(),
          y.toDouble(),
          (x - start).toDouble(),
          1,
        ),
      );
    }
  }
  return path;
}

void _drawPathFunctionCharacter(
  Canvas ctx,
  Color color,
  Object charDefinition,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
  double devicePixelRatio,
  double? strokeWidth,
) {
  ctx.save();
  ctx.clipRect(
    Rect.fromLTWH(xOffset, yOffset, deviceCellWidth, deviceCellHeight),
  );

  final path = Path();
  String actualInstructions;
  if (charDefinition is CustomGlyphPathDrawFunctionDefinition) {
    const xp = .15;
    final yp = .15 / deviceCellHeight * deviceCellWidth;
    actualInstructions = charDefinition(xp, yp);
  } else {
    actualInstructions = charDefinition as String;
  }
  final state = _SvgPathState();
  for (final instruction in actualInstructions.split(' ')) {
    if (instruction.isEmpty) {
      continue;
    }
    final type = instruction[0];
    if (type == 'Z') {
      path.close();
      state.lastCommand = type;
      continue;
    }
    final f = _svgToCanvasInstructionMap[type];
    if (f == null) {
      continue;
    }
    final args = instruction.substring(1).split(',');
    if (args.length < 2 || args[0].isEmpty || args[1].isEmpty) {
      continue;
    }
    f(
      path,
      _translateArgs(
        args,
        deviceCellWidth,
        deviceCellHeight,
        xOffset,
        yOffset,
        true,
        devicePixelRatio,
        0,
        0,
        false,
      ),
      state,
    );
    state.lastCommand = type;
  }
  if (strokeWidth != null) {
    ctx.drawPath(path, _stroke(color, devicePixelRatio * strokeWidth));
  } else {
    ctx.drawPath(path, _fill(color));
  }
  ctx.restore();
}

/// Applies a clip path to the canvas from SVG-like path instructions.
void _applyClipPath(
  Canvas ctx,
  String clipPath,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
) {
  final path = Path();
  for (final instruction in clipPath.split(' ')) {
    final type = instruction.isEmpty ? '' : instruction[0];
    if (type == 'Z') {
      path.close();
      continue;
    }
    final args = instruction.isEmpty
        ? const ['']
        : instruction.substring(1).split(',');
    if (args.length < 2 || args[0].isEmpty || args[1].isEmpty) {
      continue;
    }
    final x = xOffset + _parseFloat(args[0]) * deviceCellWidth;
    final y = yOffset + _parseFloat(args[1]) * deviceCellHeight;
    if (type == 'M') {
      path.moveTo(x, y);
    } else if (type == 'L') {
      path.lineTo(x, y);
    }
  }
  ctx.clipPath(path);
}

void _drawVectorShape(
  Canvas ctx,
  Color color,
  ICustomGlyphVectorShape charDefinition,
  double xOffset,
  double yOffset,
  double deviceCellWidth,
  double deviceCellHeight,
  double fontSize,
  double devicePixelRatio,
) {
  // Clip the cell to make sure drawing doesn't occur beyond bounds. As
  // upstream, the clip stays for the glyph's later parts.
  ctx.clipRect(
    Rect.fromLTWH(xOffset, yOffset, deviceCellWidth, deviceCellHeight),
  );

  final path = Path();
  // Scale the stroke with DPR and font size
  final cssLineWidth = fontSize / 12;
  final lineWidth = devicePixelRatio * cssLineWidth;
  final state = _SvgPathState();
  for (final instruction in charDefinition.d.split(' ')) {
    if (instruction.isEmpty) {
      continue;
    }
    final type = instruction[0];
    if (type == 'Z') {
      path.close();
      state.lastCommand = type;
      continue;
    }
    final f = _svgToCanvasInstructionMap[type];
    if (f == null) {
      continue;
    }
    final args = instruction.substring(1).split(',');
    if (args.length < 2 || args[0].isEmpty || args[1].isEmpty) {
      continue;
    }
    f(
      path,
      _translateArgs(
        args,
        deviceCellWidth,
        deviceCellHeight,
        xOffset,
        yOffset,
        false,
        devicePixelRatio,
        (charDefinition.leftPadding ?? 0) * (cssLineWidth / 2),
        (charDefinition.rightPadding ?? 0) * (cssLineWidth / 2),
      ),
      state,
    );
    state.lastCommand = type;
  }
  if (charDefinition.type == CustomGlyphVectorType.stroke) {
    ctx.drawPath(path, _stroke(color, lineWidth));
  } else {
    ctx.drawPath(path, _fill(color));
  }
}

double _clamp(double value, double max, [double min = 0]) =>
    math.max(math.min(value, max), min);

final class _SvgPathState {
  double currentX = 0;
  double currentY = 0;
  double lastControlX = 0;
  double lastControlY = 0;
  String lastCommand = '';
}

typedef _SvgInstruction = void Function(
  Path ctx,
  List<double> args,
  _SvgPathState state,
);

final Map<String, _SvgInstruction> _svgToCanvasInstructionMap = {
  'C': (ctx, args, state) {
    ctx.cubicTo(args[0], args[1], args[2], args[3], args[4], args[5]);
    state.lastControlX = args[2];
    state.lastControlY = args[3];
    state.currentX = args[4];
    state.currentY = args[5];
  },
  'L': (ctx, args, state) {
    ctx.lineTo(args[0], args[1]);
    state.lastControlX = state.currentX = args[0];
    state.lastControlY = state.currentY = args[1];
  },
  'M': (ctx, args, state) {
    ctx.moveTo(args[0], args[1]);
    state.lastControlX = state.currentX = args[0];
    state.lastControlY = state.currentY = args[1];
  },
  'Q': (ctx, args, state) {
    ctx.quadraticBezierTo(args[0], args[1], args[2], args[3]);
    state.lastControlX = args[0];
    state.lastControlY = args[1];
    state.currentX = args[2];
    state.currentY = args[3];
  },
  'T': (ctx, args, state) {
    double cpX;
    double cpY;
    if (state.lastCommand == 'Q' || state.lastCommand == 'T') {
      cpX = 2 * state.currentX - state.lastControlX;
      cpY = 2 * state.currentY - state.lastControlY;
    } else {
      cpX = state.currentX;
      cpY = state.currentY;
    }
    ctx.quadraticBezierTo(cpX, cpY, args[0], args[1]);
    state.lastControlX = cpX;
    state.lastControlY = cpY;
    state.currentX = args[0];
    state.currentY = args[1];
  },
};

List<double> _translateArgs(
  List<String> args,
  double cellWidth,
  double cellHeight,
  double xOffset,
  double yOffset,
  bool doClamp,
  double devicePixelRatio, [
  double leftPadding = 0,
  double rightPadding = 0,
  bool clampToCell = true,
]) {
  final result = [
    for (final e in args) _orIfFalsy(_parseFloat(e), () => _parseInt(e)),
  ];

  if (result.length < 2) {
    throw ArgumentError('Too few arguments for instruction');
  }

  for (var x = 0; x < result.length; x += 2) {
    // Translate from 0-1 to 0-cellWidth
    result[x] *=
        cellWidth -
        (leftPadding * devicePixelRatio) -
        (rightPadding * devicePixelRatio);
    // Round to the nearest 0.5 to ensure a crisp line at 100%
    // devicePixelRatio, and optionally clamp to the cell bounds.
    if (doClamp && result[x] != 0) {
      final rounded = _mathRound(result[x] + 0.5) - 0.5;
      result[x] = clampToCell ? _clamp(rounded, cellWidth, 0) : rounded;
    }
    // Apply the cell's offset (ie. x*cellWidth)
    result[x] += xOffset + (leftPadding * devicePixelRatio);
  }

  for (var y = 1; y < result.length; y += 2) {
    // Translate from 0-1 to 0-cellHeight
    result[y] *= cellHeight;
    // Round to the nearest 0.5 to ensure a crisp line at 100%
    // devicePixelRatio, and optionally clamp to the cell bounds.
    if (doClamp && result[y] != 0) {
      final rounded = _mathRound(result[y] + 0.5) - 0.5;
      result[y] = clampToCell ? _clamp(rounded, cellHeight, 0) : rounded;
    }
    // Apply the cell's offset (ie. x*cellHeight)
    result[y] += yOffset;
  }

  return result;
}

/// JavaScript's `a || b` on numbers: `b` when `a` is 0 or NaN.
double _orIfFalsy(double a, double Function() b) => a == 0 || a.isNaN ? b() : a;

/// JavaScript's `Math.round`: halves round up, not away from zero.
double _mathRound(double value) {
  final rounded = value.roundToDouble();
  return rounded - value == -0.5 ? rounded + 1 : rounded;
}

final RegExp _floatPrefix = RegExp(
  r'^[+-]?(?:Infinity|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)',
);

/// JavaScript's `parseFloat`: the longest numeric prefix, else NaN (path data
/// such as `L1,.27Z` relies on it).
double _parseFloat(String s) {
  final match = _floatPrefix.firstMatch(s.trimLeft());
  if (match == null) {
    return double.nan;
  }
  final text = match[0]!;
  if (text.endsWith('Infinity')) {
    return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  return double.parse(text);
}

final RegExp _intPrefix = RegExp(r'^([+-]?)(0[xX][0-9a-fA-F]+|\d+)');

/// JavaScript's `parseInt`, as a double (NaN without digits); a `0x` prefix
/// reads hexadecimal unless [radix] is 10.
double _parseInt(String s, [int? radix]) {
  final match = _intPrefix.firstMatch(s.trimLeft());
  if (match == null) {
    return double.nan;
  }
  var digits = match[2]!;
  final isHex = digits.length > 1 && (digits[1] == 'x' || digits[1] == 'X');
  if (isHex && radix == 10) {
    digits = '0';
  }
  final value = isHex && radix != 10
      ? int.parse(digits.substring(2), radix: 16)
      : int.parse(digits);
  return match[1] == '-' ? -value.toDouble() : value.toDouble();
}
