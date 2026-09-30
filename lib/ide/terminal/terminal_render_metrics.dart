// Copyright (c) 2016 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/browser/services/CharSizeService.ts,
// src/browser/renderer/dom/WidthCache.ts and the cell geometry of
// addons/addon-webgl/src/WebglRenderer.ts (`_updateDimensions`) (c58ea36);
// the fit is VS Code 6a598d4a's `getXtermScaledDimensions`
// (src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts).
//
// Text is measured with dart:ui paragraphs in the style the rows are drawn
// in: one 'W' (32 of them, as the DOM strategy) for the cell, and each other
// character once, for the spacing that keeps it on the grid.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'xterm/common/services/services.dart';

/// The font the terminal draws in, from the options.
class TerminalFont {
  const TerminalFont({
    required this.family,
    this.fallback = const [],
    required this.size,
    this.weight = ui.FontWeight.w400,
    this.weightBold = ui.FontWeight.w700,
  });

  /// From the options: `fontFamily` is a CSS family list (its first family
  /// and the fallbacks), `fontWeight`/`fontWeightBold` are CSS weights.
  factory TerminalFont.fromOptions(RequiredTerminalOptions options) {
    final families = parseFontFamilies(options.fontFamily);
    return TerminalFont(
      family: families.isEmpty ? 'monospace' : families.first,
      fallback: families.length > 1 ? families.sublist(1) : const [],
      size: options.fontSize,
      weight: fontWeightOf(options.fontWeight, ui.FontWeight.w400),
      weightBold: fontWeightOf(options.fontWeightBold, ui.FontWeight.w700),
    );
  }

  final String family;
  final List<String> fallback;
  final double size;
  final ui.FontWeight weight;
  final ui.FontWeight weightBold;

  @override
  bool operator ==(Object other) =>
      other is TerminalFont &&
      other.family == family &&
      _sameList(other.fallback, fallback) &&
      other.size == size &&
      other.weight == weight &&
      other.weightBold == weightBold;

  @override
  int get hashCode =>
      Object.hash(family, Object.hashAll(fallback), size, weight, weightBold);
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The families of a CSS `font-family` list, unquoted.
List<String> parseFontFamilies(String cssFamilies) => [
  for (final part in cssFamilies.split(','))
    if (_unquote(part.trim()) case final family when family.isNotEmpty) family,
];

String _unquote(String s) {
  if (s.length >= 2 &&
      (s.startsWith('"') && s.endsWith('"') ||
          s.startsWith("'") && s.endsWith("'"))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

/// A CSS font weight (`normal`, `bold`, `100` ... `900` or a number).
ui.FontWeight fontWeightOf(Object weight, ui.FontWeight fallback) {
  final value = switch (weight) {
    'normal' => 400,
    'bold' => 700,
    final num n => n.round(),
    final String s => int.tryParse(s),
    _ => null,
  };
  if (value == null) return fallback;
  final index = ((value.clamp(100, 900) + 50) ~/ 100) - 1;
  return ui.FontWeight.values[index];
}

/// Typographic features off, as xterm.js draws cell by cell
/// (`font-kerning: none`, no ligatures).
const List<ui.FontFeature> terminalFontFeatures = [
  ui.FontFeature.disable('kern'),
  ui.FontFeature.disable('liga'),
  ui.FontFeature.disable('calt'),
];

/// The paragraph and text styles rows are drawn in, and the measures they
/// give: upstream's CharSizeService and WidthCache.
class TerminalTextMetrics {
  TerminalTextMetrics(this.font) {
    paragraphStyle = ui.ParagraphStyle(
      fontFamily: font.family,
      fontSize: font.size,
      fontWeight: font.weight,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      strutStyle: ui.StrutStyle(
        fontFamily: font.family,
        fontFamilyFallback: font.fallback,
        fontSize: font.size,
        fontWeight: font.weight,
        leading: 0,
        forceStrutHeight: true,
      ),
    );
    _measure();
  }

  final TerminalFont font;

  /// Every row's paragraph style: one line, the font's height whatever
  /// fallback fonts a row draws in.
  late final ui.ParagraphStyle paragraphStyle;

  /// The measured character: 'W''s advance and the line's height, in
  /// logical pixels (upstream `ICharSizeService.width`/`height`).
  double charWidth = 0;
  double charHeight = 0;

  /// The paragraph's alphabetic baseline from its top.
  double baseline = 0;

  bool get hasValidSize => charWidth > 0 && charHeight > 0;

  // Widths by style: bit 0 bold, bit 1 italic. ASCII and Latin-1 in a flat
  // table (NaN: not measured yet), the rest in maps.
  final Float64List _latin1 = Float64List(256 * 4)
    ..fillRange(0, 256 * 4, 0.0 / 0.0);
  final List<Map<String, double>> _others = List.generate(
    4,
    (_) => <String, double>{},
  );

  /// A text style of the rows, without a color.
  ui.TextStyle textStyle({
    required bool bold,
    required bool italic,
    ui.Color? color,
    double letterSpacing = 0,
    List<ui.Shadow>? shadows,
  }) => ui.TextStyle(
    color: color,
    fontFamily: font.family,
    fontFamilyFallback: font.fallback,
    fontSize: font.size,
    fontWeight: bold ? font.weightBold : font.weight,
    fontStyle: italic ? ui.FontStyle.italic : ui.FontStyle.normal,
    letterSpacing: letterSpacing,
    fontFeatures: terminalFontFeatures,
    shadows: shadows,
  );

  void _measure() {
    const repeat = 32;
    final paragraph = _layout('W' * repeat, bold: false, italic: false);
    final width = paragraph.maxIntrinsicWidth / repeat;
    final height = paragraph.height;
    // Keep the previous size for an unusable measure, as upstream does.
    if (width > 0 && height > 0) {
      charWidth = width;
      charHeight = height;
      baseline = paragraph.alphabeticBaseline;
    }
    paragraph.dispose();
  }

  ui.Paragraph _layout(
    String text, {
    required bool bold,
    required bool italic,
  }) {
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle(bold: bold, italic: italic))
      ..addText(text);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  /// The advance of [chars] (one cell's characters) in the style, in
  /// logical pixels (upstream `WidthCache.get`).
  double width(String chars, {required bool bold, required bool italic}) {
    final variant = (bold ? 1 : 0) | (italic ? 2 : 0);
    if (chars.length == 1) {
      final code = chars.codeUnitAt(0);
      if (code < 256) {
        final index = variant * 256 + code;
        final cached = _latin1[index];
        if (!cached.isNaN) return cached;
        return _latin1[index] = _measureText(chars, bold, italic);
      }
    }
    return _others[variant][chars] ??= _measureText(chars, bold, italic);
  }

  /// [width] of one code point, without a string for Latin-1 ones.
  double widthOfCodePoint(
    int code, {
    required bool bold,
    required bool italic,
  }) {
    if (code < 256) {
      final index = ((bold ? 1 : 0) | (italic ? 2 : 0)) * 256 + code;
      final cached = _latin1[index];
      if (!cached.isNaN) return cached;
    }
    return width(String.fromCharCode(code), bold: bold, italic: italic);
  }

  double _measureText(String chars, bool bold, bool italic) {
    final paragraph = _layout(chars, bold: bold, italic: italic);
    final width = paragraph.maxIntrinsicWidth;
    paragraph.dispose();
    return width;
  }
}

/// Upstream `IRenderDimensions`: the cell and character in device pixels
/// (whole ones, so that cells tile the device pixel grid), and the cell in
/// logical pixels.
class TerminalRenderDimensions {
  const TerminalRenderDimensions._({
    required this.devicePixelRatio,
    required this.deviceCharWidth,
    required this.deviceCharHeight,
    required this.deviceCharLeft,
    required this.deviceCharTop,
    required this.deviceCellWidth,
    required this.deviceCellHeight,
  });

  /// WebglRenderer's `_updateDimensions`: the character's width floored and
  /// height ceiled to device pixels, the line height and letter spacing
  /// (in device pixels, as upstream) added around it.
  factory TerminalRenderDimensions.compute({
    required double charWidth,
    required double charHeight,
    required double lineHeight,
    required double letterSpacing,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio;
    final deviceCharWidth = (charWidth * dpr).floor();
    final deviceCharHeight = (charHeight * dpr).ceil();
    final deviceCellHeight = (deviceCharHeight * lineHeight).floor();
    final deviceCharTop = lineHeight == 1
        ? 0
        : ((deviceCellHeight - deviceCharHeight) / 2).round();
    final deviceCellWidth = deviceCharWidth + letterSpacing.round();
    final deviceCharLeft = (letterSpacing / 2).floor();
    return TerminalRenderDimensions._(
      devicePixelRatio: dpr,
      deviceCharWidth: math.max(deviceCharWidth, 1),
      deviceCharHeight: math.max(deviceCharHeight, 1),
      deviceCharLeft: deviceCharLeft,
      deviceCharTop: deviceCharTop,
      deviceCellWidth: math.max(deviceCellWidth, 1),
      deviceCellHeight: math.max(deviceCellHeight, 1),
    );
  }

  final double devicePixelRatio;
  final int deviceCharWidth;
  final int deviceCharHeight;
  final int deviceCharLeft;
  final int deviceCharTop;
  final int deviceCellWidth;
  final int deviceCellHeight;

  double get cellWidth => deviceCellWidth / devicePixelRatio;
  double get cellHeight => deviceCellHeight / devicePixelRatio;
  double get charWidth => deviceCharWidth / devicePixelRatio;
  double get charHeight => deviceCharHeight / devicePixelRatio;
  double get charLeft => deviceCharLeft / devicePixelRatio;
  double get charTop => deviceCharTop / devicePixelRatio;

  /// The grid that fits [width] x [height] logical pixels, at least 1 x 1
  /// (VS Code's `getXtermScaledDimensions`).
  ({int cols, int rows}) fit(double width, double height) {
    final dpr = devicePixelRatio;
    return (
      cols: math.max((width * dpr / deviceCellWidth).floor(), 1),
      rows: math.max((height * dpr / deviceCellHeight).floor(), 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalRenderDimensions &&
      other.devicePixelRatio == devicePixelRatio &&
      other.deviceCharWidth == deviceCharWidth &&
      other.deviceCharHeight == deviceCharHeight &&
      other.deviceCharLeft == deviceCharLeft &&
      other.deviceCharTop == deviceCharTop &&
      other.deviceCellWidth == deviceCellWidth &&
      other.deviceCellHeight == deviceCellHeight;

  @override
  int get hashCode => Object.hash(
    devicePixelRatio,
    deviceCharWidth,
    deviceCharHeight,
    deviceCharLeft,
    deviceCharTop,
    deviceCellWidth,
    deviceCellHeight,
  );
}
