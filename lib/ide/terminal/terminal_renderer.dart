// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See packages/bao_xterm/lib/LICENSE.txt.
// Ported from xterm.js addons/addon-webgl/src/WebglRenderer.ts
// (`_updateModel`), CellColorResolver.ts, TextureAtlas.ts (the colors and
// the decorations of `_drawToCache`), RectangleRenderer.ts (backgrounds and
// the cursor) and renderLayer/LinkRenderLayer.ts, and from
// src/browser/renderer/shared/RendererUtils.ts, SelectionRenderModel.ts and
// src/browser/services/RenderService.ts (c58ea36).
//
// VS Code draws the terminal with the WebGL renderer; this draws what it
// draws, with dart:ui. Each viewport row becomes a model: its cells' code
// points and resolved colors and styles (selection, cursor, decorations,
// inverse, bold as bright, dim and the minimum contrast ratio applied).
// Models are rebuilt for the rows reported dirty (or all on a scroll, a
// resize, a selection or theme change), and a row's pictures (its
// backgrounds; its text as one paragraph with custom glyphs and lines) are
// recorded only when its model is new: pictures are cached by model, so a
// scroll reuses the rows it moves. A color change drops them all, as
// upstream takes a new texture atlas. Painting replays the backgrounds of all
// rows, then their text, then the cursor, as upstream's layers.
//
// Text keeps to the grid as the DOM renderer keeps it: each run of a row's
// paragraph gets the letter spacing that makes its characters' advances
// whole cells (a paragraph adds half the spacing before a glyph and half
// after, so glyphs sit up to half that off the cell's left edge). Cells
// drawn by hand ([isCustomGlyph]) are spaces in the paragraph. A leading LRO
// keeps right-to-left text in cell order, as upstream draws it.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'terminal_custom_glyphs.dart';
import 'terminal_render_blink.dart';
import 'terminal_render_metrics.dart';
import 'terminal_render_source.dart';
import 'terminal_render_theme.dart';

import 'package:bao_xterm/common/buffer/attribute_data.dart';
import 'package:bao_xterm/common/buffer/cell_data.dart';
import 'package:bao_xterm/common/buffer/constants.dart';
import 'package:bao_xterm/common/color.dart';
import 'package:bao_xterm/common/input/text_decoder.dart';
import 'package:bao_xterm/common/lifecycle.dart';
import 'package:bao_xterm/common/services/services.dart';
import 'package:bao_xterm/common/types.dart';

/// Upstream `INVERTED_DEFAULT_COLOR`: a link underline in the background
/// color.
const int invertedDefaultColor = 257;

/// Opacity of dim text.
const double dimOpacity = 0.5;

/// Upstream `isPowerlineGlyph`: Powerline symbols, which are left out of
/// the minimum contrast ratio.
bool isPowerlineGlyph(int codepoint) =>
    0xE0A4 <= codepoint && codepoint <= 0xE0D6;

/// Upstream `isEmoji`, for [allowRescaling].
bool isEmoji(int codepoint) =>
    codepoint >= 0x1F600 && codepoint <= 0x1F64F || // Emoticons
    codepoint >= 0x1F300 &&
        codepoint <= 0x1F5FF || // Misc Symbols and Pictographs
    codepoint >= 0x1F680 && codepoint <= 0x1F6FF || // Transport and Map
    codepoint >= 0x2600 && codepoint <= 0x26FF || // Misc symbols
    codepoint >= 0x2700 && codepoint <= 0x27BF || // Dingbats
    codepoint >= 0xFE00 && codepoint <= 0xFE0F || // Variation Selectors
    codepoint >= 0x1F900 &&
        codepoint <= 0x1F9FF || // Supplemental Symbols and Pictographs
    codepoint >= 0x1F1E6 && codepoint <= 0x1F1FF;

/// Upstream `allowRescaling`: whether a one cell glyph [glyphWidth] device
/// pixels wide is squeezed into its cell (`rescaleOverlappingGlyphs`).
bool allowRescaling(
  int codepoint,
  int width,
  double glyphWidth,
  int deviceCellWidth,
) =>
    // Is single cell width
    width == 1 &&
    // Glyph exceeds cell bounds, add 50% to avoid hurting readability by
    // rescaling glyphs that barely overlap
    glyphWidth > (deviceCellWidth * 1.5).ceil() &&
    // Never rescale ascii
    codepoint > 0xFF &&
    // Never rescale emoji
    !isEmoji(codepoint) &&
    // Never rescale powerline or nerd fonts
    !isPowerlineGlyph(codepoint) &&
    !(0xE000 <= codepoint && codepoint <= 0xF8FF);

/// Upstream `treatGlyphAsBackgroundColor`: glyphs that draw a background
/// (Powerline, box drawing, blocks).
bool treatGlyphAsBackgroundColor(int codepoint) =>
    isPowerlineGlyph(codepoint) || (0x2500 <= codepoint && codepoint <= 0x259F);

/// A selection to paint, as xterm.js' `handleSelectionChanged` gets it:
/// [start] and [end] are cells with 0-based columns and buffer lines (not
/// viewport rows); [end] is exclusive.
@immutable
class TerminalSelectionRange {
  const TerminalSelectionRange({
    required this.start,
    required this.end,
    this.columnSelectMode = false,
  });

  final ({int x, int y}) start;
  final ({int x, int y}) end;
  final bool columnSelectMode;

  @override
  bool operator ==(Object other) =>
      other is TerminalSelectionRange &&
      other.start == start &&
      other.end == end &&
      other.columnSelectMode == columnSelectMode;

  @override
  int get hashCode => Object.hash(start, end, columnSelectMode);
}

/// A hovered link's underline (upstream `ILinkifierEvent`): viewport rows
/// [y1] to [y2], from column [x1] on the first to [x2] (exclusive) on the
/// last, [cols] wide. [fg] is the palette color to draw it in,
/// [invertedDefaultColor] for the background, null for the foreground.
@immutable
class TerminalLinkUnderline {
  const TerminalLinkUnderline({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.cols,
    this.fg,
  });

  final int x1;
  final int y1;
  final int x2;
  final int y2;
  final int cols;
  final int? fg;

  @override
  bool operator ==(Object other) =>
      other is TerminalLinkUnderline &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      other.cols == cols &&
      other.fg == fg;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2, cols, fg);
}

// A row model: per cell [code, width, bg, fg, flags, underline color].
const int _stride = 6;
const int _iCode = 0;
const int _iWidth = 1;
const int _iBg = 2;
const int _iFg = 3;
const int _iFlags = 4;
const int _iUnderline = 5;

// Cell flags.
const int _fBold = 1;
const int _fItalic = 2;
const int _fGlyph = 4; // text to draw
const int _fCustom = 8; // drawn by paintCustomGlyph
const int _fStrike = 16;
const int _fOverline = 32;
const int _fUnderlineShift = 6; // 3 bits: 0 none, else UnderlineStyle
const int _fUnderlineMask = 7 << _fUnderlineShift;
const int _fVariantShift = 9; // 2 bits: shade variant
const int _fCombined = 1 << 11; // code indexes the row's strings
const int _fRescale = 1 << 12; // text squeezed into its cell, drawn alone
const int _fDecorations = _fStrike | _fOverline | _fUnderlineMask;

final class _RowModel {
  _RowModel(this.data, this.strings, this.hash);

  static final _RowModel empty = _RowModel(Uint32List(0), const [], 0);

  final Uint32List data;
  final List<String> strings;
  final int hash;

  @override
  int get hashCode => hash;

  @override
  bool operator ==(Object other) {
    if (other is! _RowModel || other.hash != hash) return false;
    return _equals(other.data, other.strings);
  }

  bool _equals(Uint32List otherData, List<String> otherStrings) {
    if (otherData.length != data.length ||
        otherStrings.length != strings.length) {
      return false;
    }
    for (var i = 0; i < data.length; i++) {
      if (otherData[i] != data[i]) return false;
    }
    for (var i = 0; i < strings.length; i++) {
      if (otherStrings[i] != strings[i]) return false;
    }
    return true;
  }
}

/// A row's recorded backgrounds and text.
final class _RowPictures {
  _RowPictures(this.background, this.foreground);

  final ui.Picture? background;
  final ui.Picture? foreground;

  void dispose() {
    background?.dispose();
    foreground?.dispose();
  }
}

/// Paints a [TerminalRenderSource]'s viewport; the widget hosts it.
///
/// Changes that need a repaint call [onNeedsPaint]; the host paints once
/// per frame with [paint], which brings the rows up to date first (upstream
/// RenderService's debounced `refreshRows`). [onDimensionsChanged] tells
/// the host the cell size changed (a font option, the pixel ratio).
class TerminalRenderer {
  TerminalRenderer(
    this.source, {
    required this.onNeedsPaint,
    this.onDimensionsChanged,
    this._devicePixelRatio = 1,
    this._isFocused = false,
  }) {
    _textBlink = TerminalTextBlink(() => _refreshAll());
    _textBlink.setIntervalDuration(_options.blinkIntervalDuration);
    _updateCursorBlink(requestPaint: false);
    _updateColors();
    final store = _store;
    store.add(
      source.onRender((e) {
        markRowsDirty(e.start, e.end);
      }),
    );
    store.add(source.onScroll((_) => _refreshAll()));
    store.add(source.onResize((_) => _refreshAll()));
    store.add(source.onBufferActivate((_) => _refreshAll()));
    store.add(
      source.onCursorMove((_) {
        _cursorBlink?.restartBlinkAnimation();
      }),
    );
    store.add(
      source.themeService.onChangeColors((_) {
        // Upstream `_handleColorChange`: a texture atlas for the new colors
        // (the pictures here, which may hold the background) and a full
        // refresh.
        _clearPictures();
        _updateColors();
        _refreshAll();
      }),
    );
    final options = source.optionsService;
    store.add(
      options.onMultipleOptionChange(const [
        'drawBoldTextInBrightColors',
        'letterSpacing',
        'lineHeight',
        'fontFamily',
        'fontSize',
        'fontWeight',
        'fontWeightBold',
        'minimumContrastRatio',
        'rescaleOverlappingGlyphs',
      ], _handleGlyphOptionsChanged),
    );
    store.add(
      options.onMultipleOptionChange(const [
        'cursorBlink',
        'cursorStyle',
      ], _updateCursorBlink),
    );
    store.add(
      options.onSpecificOptionChange<int>(
        'blinkIntervalDuration',
        (duration) => _textBlink.setIntervalDuration(duration),
      ),
    );
    store.add(options.onOptionChange((_) => _refreshAll()));
    final decorations = source.decorationService;
    if (decorations != null) {
      store.add(decorations.onDecorationRegistered((_) => _refreshAll()));
      store.add(decorations.onDecorationRemoved((_) => _refreshAll()));
    }
  }

  final TerminalRenderSource source;

  /// Asks the host for a paint (it coalesces them into one per frame).
  final VoidCallback onNeedsPaint;

  /// Tells the host the cell size changed.
  final VoidCallback? onDimensionsChanged;

  final DisposableStore _store = DisposableStore();
  late final TerminalTextBlink _textBlink;
  TerminalCursorBlink? _cursorBlink;
  bool _disposed = false;

  RequiredTerminalOptions get _options => source.optionsService.rawOptions;

  // --- Host state -----------------------------------------------------

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio || value <= 0) return;
    _devicePixelRatio = value;
    _dimensions = null;
    _clearPictures();
    onDimensionsChanged?.call();
    _refreshAll();
  }

  bool _isFocused;
  bool get isFocused => _isFocused;

  /// The terminal's focus: the cursor's style and the selection's color
  /// follow it (upstream `handleFocus`/`handleBlur`).
  set isFocused(bool value) {
    if (value == _isFocused) return;
    _isFocused = value;
    if (value) {
      _cursorBlink?.resume();
    } else {
      _cursorBlink?.pause();
    }
    _refreshAll();
  }

  /// Whether the viewport is on screen; blinking text stops when not.
  set viewportVisible(bool value) => _textBlink.setViewportVisible(value);

  TerminalSelectionRange? _selection;
  TerminalSelectionRange? get selection => _selection;

  /// The selection to paint (upstream `handleSelectionChanged`).
  set selection(TerminalSelectionRange? value) {
    if (value == _selection) return;
    _selection = value;
    _refreshAll();
  }

  TerminalLinkUnderline? _linkUnderline;
  TerminalLinkUnderline? get linkUnderline => _linkUnderline;

  /// The hovered link's underline, or null (upstream's link layer).
  set linkUnderline(TerminalLinkUnderline? value) {
    if (value == _linkUnderline) return;
    _linkUnderline = value;
    _requestPaint();
  }

  /// Shows the cursor and restarts its blinking, as on input (upstream
  /// `handleCursorMove`, and the mouse down that restarts it).
  void restartCursorBlink() => _cursorBlink?.restartBlinkAnimation();

  // --- Metrics ----------------------------------------------------------

  TerminalTextMetrics? _metrics;
  TerminalRenderDimensions? _dimensions;

  /// The font's measures.
  TerminalTextMetrics get metrics {
    var metrics = _metrics;
    if (metrics == null) {
      metrics = _metrics = TerminalTextMetrics(
        TerminalFont.fromOptions(_options),
      );
      _dimensions = null;
      _styles.clear();
    }
    return metrics;
  }

  /// Measures the font again, as when fonts were installed or loaded.
  void remeasure() => _handleGlyphOptionsChanged();

  /// The cell geometry (upstream `IRenderDimensions`).
  TerminalRenderDimensions get dimensions {
    final metrics = this.metrics;
    return _dimensions ??= TerminalRenderDimensions.compute(
      charWidth: metrics.charWidth,
      charHeight: metrics.charHeight,
      lineHeight: _options.lineHeight,
      letterSpacing: _options.letterSpacing,
      devicePixelRatio: _devicePixelRatio,
    );
  }

  void _handleGlyphOptionsChanged() {
    final contrast = source.themeService.colors;
    contrast.contrastCache.clear();
    contrast.halfContrastCache.clear();
    final before = _dimensions;
    _metrics = null;
    _dimensions = null;
    _clearPictures();
    _updateColors();
    if (dimensions != before) onDimensionsChanged?.call();
    _refreshAll();
  }

  // --- Dirty rows -------------------------------------------------------

  int _rows = 0;
  int _cols = 0;
  List<_RowModel?> _models = [];
  List<_RowPictures?> _pictures = [];
  Uint8List _dirty = Uint8List(0);
  final LinkedHashMap<_RowModel, _RowPictures> _cache =
      LinkedHashMap<_RowModel, _RowPictures>();
  final List<bool> _rowHasBlink = [];
  int _rowHasBlinkCount = 0;
  int _paintedYdisp = -1;
  Object? _paintedBuffer;
  (int, int, bool, String?)? _paintedCursor;
  Timer? _syncOutputTimeout;

  /// Marks viewport rows [start] to [end] for a rebuild (upstream
  /// `refreshRows`); the next paint rebuilds them.
  void markRowsDirty(int start, int end) {
    if (_disposed) return;
    final first = math.max(start, 0);
    final last = math.min(end, _dirty.length - 1);
    if (first <= last) _dirty.fillRange(first, last + 1, 1);
    _requestPaint();
  }

  void _refreshAll() {
    if (_disposed) return;
    _dirty.fillRange(0, _dirty.length, 1);
    _requestPaint();
  }

  void _requestPaint() {
    if (!_disposed) onNeedsPaint();
  }

  void _resize(int cols, int rows) {
    // Pictures in use are in the cache, which disposes of them.
    _cols = cols;
    _rows = rows;
    _models = List<_RowModel?>.filled(rows, null);
    _pictures = List<_RowPictures?>.filled(rows, null);
    _dirty = Uint8List(rows)..fillRange(0, rows, 1);
    _rowHasBlink
      ..clear()
      ..addAll(List<bool>.filled(rows, false));
    _rowHasBlinkCount = 0;
  }

  void _clearPictures() {
    for (final pictures in _cache.values) {
      pictures.dispose();
    }
    _cache.clear();
    _pictures = List<_RowPictures?>.filled(_rows, null);
    _models = List<_RowModel?>.filled(_rows, null);
    _dirty.fillRange(0, _dirty.length, 1);
  }

  // --- Colors -----------------------------------------------------------

  late TerminalColorSet _colors;
  final Int32List _ansiArgb = Int32List(256);
  int _foregroundArgb = 0;
  int _backgroundArgb = 0;
  int _cursorArgb = 0;

  /// The theme's background, which the host fills the terminal with.
  ui.Color get backgroundColor => ui.Color(_backgroundArgb);

  void _updateColors() {
    _colors = source.themeService.colors;
    final ansi = _colors.ansi;
    for (var i = 0; i < 256; i++) {
      _ansiArgb[i] = _opaqueArgb(ansi[i].rgba);
    }
    _foregroundArgb = _opaqueArgb(_colors.foreground.rgba);
    _backgroundArgb = _opaqueArgb(_colors.background.rgba);
    _cursorArgb = argbOfRgba(_colors.cursor.rgba);
  }

  static int _opaqueArgb(int rgba) => 0xFF000000 | (rgba >>> 8);

  /// Upstream `_resolveBackgroundRgba`.
  int _resolveBackgroundRgba(int bgColorMode, int bgColor, bool inverse) {
    switch (bgColorMode) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        return _colors.ansi[bgColor].rgba;
      case Attributes.cmRgb:
        return (bgColor << 8) & 0xFFFFFFFF;
      default:
        return inverse ? _colors.foreground.rgba : _colors.background.rgba;
    }
  }

  /// Upstream `_resolveForegroundRgba`.
  int _resolveForegroundRgba(
    int fgColorMode,
    int fgColor,
    bool inverse,
    bool bold,
  ) {
    switch (fgColorMode) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        if (_drawBoldTextInBrightColors && bold && fgColor < 8) {
          fgColor += 8;
        }
        return _colors.ansi[fgColor].rgba;
      case Attributes.cmRgb:
        return (fgColor << 8) & 0xFFFFFFFF;
      default:
        return inverse ? _colors.background.rgba : _colors.foreground.rgba;
    }
  }

  static int _colorOf(int word) {
    switch (word & Attributes.cmMask) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        return word & Attributes.pcolorMask;
      case Attributes.cmRgb:
        return word & Attributes.rgbMask;
      default:
        return -1;
    }
  }

  /// Upstream TextureAtlas' `_getForegroundColor`: the glyph's color for
  /// resolved attribute words, as `0xAARRGGBB`.
  int _glyphArgb(int fg, int bg, bool excludeFromContrastRatioDemands) {
    final inverse = (fg & FgFlags.inverse) != 0;
    final bold = (fg & FgFlags.bold) != 0;
    final dim = (bg & BgFlags.dim) != 0;
    var fgColor = _colorOf(fg);
    var fgColorMode = fg & Attributes.cmMask;
    var bgColor = _colorOf(bg);
    var bgColorMode = bg & Attributes.cmMask;
    if (inverse) {
      final temp = fgColor;
      fgColor = bgColor;
      bgColor = temp;
      final temp2 = fgColorMode;
      fgColorMode = bgColorMode;
      bgColorMode = temp2;
    }

    // The minimum contrast ratio, with its result not dimmed, as upstream.
    final ratio = _minimumContrastRatio;
    if (ratio != 1 && !excludeFromContrastRatioDemands) {
      final bgRgba = _resolveBackgroundRgba(bgColorMode, bgColor, inverse);
      final fgRgba = _resolveForegroundRgba(
        fgColorMode,
        fgColor,
        inverse,
        bold,
      );
      final cache = dim ? _colors.halfContrastCache : _colors.contrastCache;
      IColor? adjusted;
      if (cache.has(bgRgba, fgRgba)) {
        adjusted = cache.getColor(bgRgba, fgRgba);
      } else {
        // Dim cells only require half the contrast, otherwise they wouldn't
        // be distinguishable from non-dim cells
        final result = rgba.ensureContrastRatio(
          bgRgba,
          fgRgba,
          ratio / (dim ? 2 : 1),
        );
        adjusted = result == null
            ? null
            : channels.toColor(
                (result >> 24) & 0xFF,
                (result >> 16) & 0xFF,
                (result >> 8) & 0xFF,
              );
        cache.setColor(bgRgba, fgRgba, adjusted);
      }
      if (adjusted != null) return _opaqueArgb(adjusted.rgba);
    }

    int argb;
    switch (fgColorMode) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        if (_drawBoldTextInBrightColors && bold && fgColor < 8) {
          fgColor += 8;
        }
        argb = _ansiArgb[fgColor];
      case Attributes.cmRgb:
        argb = 0xFF000000 | fgColor;
      default:
        argb = inverse ? _backgroundArgb : _foregroundArgb;
    }
    if (dim) {
      // color.multiplyOpacity: the alpha halved, rounded as Math.round.
      final alpha = ((argb >>> 24) * dimOpacity + 0.5).floor();
      argb = (alpha << 24) | (argb & 0xFFFFFF);
    }
    return argb;
  }

  /// Upstream RectangleRenderer's `_updateRectangle`: the cell's background,
  /// 0 for the theme's (not drawn).
  int _cellBackgroundArgb(int fg, int bg) {
    if ((fg & FgFlags.inverse) != 0) {
      switch (fg & Attributes.cmMask) {
        case Attributes.cmP16:
        case Attributes.cmP256:
          return _ansiArgb[fg & Attributes.pcolorMask];
        case Attributes.cmRgb:
          return 0xFF000000 | (fg & Attributes.rgbMask);
        default:
          return _foregroundArgb;
      }
    }
    switch (bg & Attributes.cmMask) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        return _ansiArgb[bg & Attributes.pcolorMask];
      case Attributes.cmRgb:
        return 0xFF000000 | (bg & Attributes.rgbMask);
      default:
        return 0;
    }
  }

  // Per frame.
  bool _drawBoldTextInBrightColors = true;
  double _minimumContrastRatio = 1;
  bool _rescaleOverlappingGlyphs = false;

  // --- Cell color resolution (CellColorResolver) ------------------------

  int _resultFg = 0;
  int _resultBg = 0;
  int _resultExt = 0;
  int _ovFg = 0;
  int _ovBg = 0;
  bool _hasFg = false;
  bool _hasBg = false;
  bool _hasDecorations = false;
  late final void Function(IInternalDecoration d) _applyDecoration =
      _applyDecorationColors;

  void _applyDecorationColors(IInternalDecoration d) {
    final bg = d.backgroundColorRGB;
    if (bg != null) {
      _ovBg = (bg.rgba >>> 8) & Attributes.rgbMask;
      _hasBg = true;
    }
    final fg = d.foregroundColorRGB;
    if (fg != null) {
      _ovFg = (fg.rgba >>> 8) & Attributes.rgbMask;
      _hasFg = true;
    }
  }

  /// Upstream `CellColorResolver.resolve`: the cell's attribute words with
  /// decorations and the selection applied, into `_result*`.
  void _resolve(CellData cell, int x, int row, bool isSelected) {
    _resultBg = cell.bg;
    _resultFg = cell.fg;
    _resultExt = (cell.bg & BgFlags.hasExtended) != 0 ? cell.extended.ext : 0;
    _ovBg = 0;
    _ovFg = 0;
    _hasBg = false;
    _hasFg = false;
    final colors = _colors;
    final decorations = source.decorationService;

    // Apply decorations on the bottom layer
    if (_hasDecorations) {
      decorations!.forEachDecorationAtCell(x, row, 'bottom', _applyDecoration);
    }

    // Apply the selection color if needed
    if (isSelected) {
      final selection =
          (_isFocused
                  ? colors.selectionBackgroundOpaque
                  : colors.selectionInactiveBackgroundOpaque)
              .rgba;
      // If the cell has a bg color, retain the color by blending it with the
      // selection color
      if ((_resultFg & FgFlags.inverse) != 0 ||
          (_resultBg & Attributes.cmMask) != Attributes.cmDefault) {
        int bgRgba;
        // Resolve the standard bg color
        if ((_resultFg & FgFlags.inverse) != 0) {
          switch (_resultFg & Attributes.cmMask) {
            case Attributes.cmP16:
            case Attributes.cmP256:
              bgRgba = colors.ansi[_resultFg & Attributes.pcolorMask].rgba;
            case Attributes.cmRgb:
              bgRgba = ((_resultFg & Attributes.rgbMask) << 8) | 0xFF;
            default:
              bgRgba = colors.foreground.rgba;
          }
        } else {
          switch (_resultBg & Attributes.cmMask) {
            case Attributes.cmP16:
            case Attributes.cmP256:
              bgRgba = colors.ansi[_resultBg & Attributes.pcolorMask].rgba;
            default:
              bgRgba = ((_resultBg & Attributes.rgbMask) << 8) | 0xFF;
          }
        }
        // Blend with selection bg color
        _ovBg =
            (rgba.blend(bgRgba, (selection & 0xFFFFFF00) | 0x80) >>> 8) &
            Attributes.rgbMask;
      } else {
        _ovBg = (selection >>> 8) & Attributes.rgbMask;
      }
      _hasBg = true;

      // Apply explicit selection foreground if present
      final selectionForeground = colors.selectionForeground;
      if (selectionForeground != null) {
        _ovFg = (selectionForeground.rgba >>> 8) & Attributes.rgbMask;
        _hasFg = true;
      }

      // Overwrite fg as bg if it's a special decorative glyph (eg. powerline)
      if (treatGlyphAsBackgroundColor(cell.getCode())) {
        // Inverse default background should be treated as transparent
        if ((_resultFg & FgFlags.inverse) != 0 &&
            (_resultBg & Attributes.cmMask) == Attributes.cmDefault) {
          _ovFg = (selection >>> 8) & Attributes.rgbMask;
        } else {
          int fgRgba;
          if ((_resultFg & FgFlags.inverse) != 0) {
            switch (_resultBg & Attributes.cmMask) {
              case Attributes.cmP16:
              case Attributes.cmP256:
                fgRgba = colors.ansi[_resultBg & Attributes.pcolorMask].rgba;
              default:
                fgRgba = ((_resultBg & Attributes.rgbMask) << 8) | 0xFF;
            }
          } else {
            switch (_resultFg & Attributes.cmMask) {
              case Attributes.cmP16:
              case Attributes.cmP256:
                fgRgba = colors.ansi[_resultFg & Attributes.pcolorMask].rgba;
              case Attributes.cmRgb:
                fgRgba = ((_resultFg & Attributes.rgbMask) << 8) | 0xFF;
              default:
                fgRgba = colors.foreground.rgba;
            }
          }
          _ovFg =
              (rgba.blend(fgRgba, (selection & 0xFFFFFF00) | 0x80) >>> 8) &
              Attributes.rgbMask;
        }
        _hasFg = true;
      }
    }

    // Apply decorations on the top layer
    if (_hasDecorations) {
      decorations!.forEachDecorationAtCell(x, row, 'top', _applyDecoration);
    }

    // Convert any overrides from rgba to the fg/bg packed format. This
    // resolves the inverse flag ahead of time.
    var bg = _ovBg;
    var fg = _ovFg;
    if (_hasBg) {
      if (isSelected) {
        // Non-RGB attributes from model + force non-dim + override + force
        // RGB color mode
        bg =
            (cell.bg & ~Attributes.rgbMask & ~BgFlags.dim) |
            bg |
            Attributes.cmRgb;
      } else {
        bg = (cell.bg & ~Attributes.rgbMask) | bg | Attributes.cmRgb;
      }
    }
    if (_hasFg) {
      // Non-RGB attributes from model + force disable inverse + override +
      // force RGB color mode
      fg =
          (cell.fg & ~Attributes.rgbMask & ~FgFlags.inverse) |
          fg |
          Attributes.cmRgb;
    }

    // Handle case where inverse was specified by only one of bg override or
    // fg override was set, resolving the other inverse color and setting the
    // inverse flag if needed.
    if ((_resultFg & FgFlags.inverse) != 0) {
      if (_hasBg && !_hasFg) {
        // Resolve bg color type (default color has a different meaning in fg
        // vs bg)
        if ((_resultBg & Attributes.cmMask) == Attributes.cmDefault) {
          fg =
              (_resultFg &
                  ~(Attributes.rgbMask | FgFlags.inverse | Attributes.cmMask)) |
              ((colors.background.rgba >>> 8) & Attributes.rgbMask) |
              Attributes.cmRgb;
        } else {
          fg =
              (_resultFg &
                  ~(Attributes.rgbMask | FgFlags.inverse | Attributes.cmMask)) |
              _resultBg & (Attributes.rgbMask | Attributes.cmMask);
        }
        _hasFg = true;
      }
      if (!_hasBg && _hasFg) {
        // Resolve bg color type (default color has a different meaning in fg
        // vs bg)
        if ((_resultFg & Attributes.cmMask) == Attributes.cmDefault) {
          bg =
              (_resultBg & ~(Attributes.rgbMask | Attributes.cmMask)) |
              ((colors.foreground.rgba >>> 8) & Attributes.rgbMask) |
              Attributes.cmRgb;
        } else {
          bg =
              (_resultBg & ~(Attributes.rgbMask | Attributes.cmMask)) |
              _resultFg & (Attributes.rgbMask | Attributes.cmMask);
        }
        _hasBg = true;
      }
    }

    // Use the override if it exists
    if (_hasBg) _resultBg = bg & 0xFFFFFFFF;
    if (_hasFg) _resultFg = fg & 0xFFFFFFFF;
  }

  // --- Row models -------------------------------------------------------

  final CellData _workCell = CellData();
  final AttributeData _workAttributes = AttributeData();
  Uint32List _scratch = Uint32List(0);
  final List<String> _scratchStrings = [];

  // The cursor as the models draw it.
  int _cursorRow = -1; // buffer line
  int _cursorX = 0;
  bool _cursorVisible = false;
  String? _cursorStyleNow; // the style drawn (focused or inactive)

  // The selection's cells on the row being built: [_selStart, _selEnd).
  int _selStart = 0;
  int _selEnd = 0;

  void _selectionOnRow(int row) {
    _selStart = 0;
    _selEnd = 0;
    final selection = _selection;
    if (selection == null) return;
    final start = selection.start;
    final end = selection.end;
    if (start.x == end.x && start.y == end.y) return;
    if (selection.columnSelectMode) {
      // Upstream's rows are start's to end's, as given.
      if (row < start.y || row > end.y) return;
      if (start.x <= end.x) {
        _selStart = start.x;
        _selEnd = end.x;
      } else {
        _selStart = end.x;
        _selEnd = start.x;
      }
      return;
    }
    if (row > start.y && row < end.y) {
      _selStart = 0;
      _selEnd = 1 << 30;
    } else if (start.y == end.y && row == start.y) {
      _selStart = start.x;
      _selEnd = end.x;
    } else if (start.y < end.y && row == end.y) {
      _selStart = 0;
      _selEnd = end.x;
    } else if (start.y < end.y && row == start.y) {
      _selStart = start.x;
      _selEnd = 1 << 30;
    }
  }

  /// Builds viewport row [y]'s model into the scratch arrays and returns
  /// it, reusing [previous] when equal.
  _RowModel _buildModel(int y, _RowModel? previous) {
    final buffer = source.buffer;
    final row = y + buffer.ydisp;
    final line = buffer.lines.get(row);
    if (line == null) {
      _setRowBlink(y, false);
      return _RowModel.empty;
    }
    final cols = _cols;
    if (_scratch.length != cols * _stride) {
      _scratch = Uint32List(cols * _stride);
    }
    final data = _scratch;
    final strings = _scratchStrings..clear();
    final cell = _workCell;
    final attrs = _workAttributes;
    final extended = attrs.extended;
    final dims = dimensions;
    _selectionOnRow(row);
    final isCursorRow = _cursorVisible && row == _cursorRow;
    final cursorBlock = isCursorRow && _cursorStyleNow == 'block';
    var lastCursorX = -1;
    final textBlinkHidden = _textBlink.isEnabled && !_textBlink.isBlinkOn;
    var rowHasBlink = false;

    // The last resolutions, reused while cells repeat their attributes.
    var lastFg = -1;
    var lastBg = -1;
    var lastBgArgb = 0;
    var glyphFg = -1;
    var glyphBg = -1;
    var glyphExclude = false;
    var glyphArgbCached = 0;

    var hash = cols;
    for (var x = 0; x < cols; x++) {
      line.loadCell(x, cell);
      final width = cell.getWidth();
      final isCombined = cell.isCombined() != 0;
      final code = isCombined
          ? cell.combinedData.codeUnitAt(0)
          : cell.content & Content.codepointMask;
      final isSelected = x >= _selStart && x < _selEnd;
      if (!rowHasBlink && cell.isBlink() != 0) rowHasBlink = true;

      if (!isSelected && !_hasDecorations) {
        _resultFg = cell.fg;
        _resultBg = cell.bg;
        _resultExt = (cell.bg & BgFlags.hasExtended) != 0
            ? cell.extended.ext
            : 0;
      } else {
        _resolve(cell, x, row, isSelected);
      }

      // Override colors for cursor cell
      if (cursorBlock) {
        if (x == _cursorX) lastCursorX = _cursorX + width - 1;
        if (x >= _cursorX && x <= lastCursorX) {
          _resultFg =
              Attributes.cmRgb |
              ((_colors.cursorAccent.rgba >>> 8) & Attributes.rgbMask);
          _resultBg =
              Attributes.cmRgb |
              ((_colors.cursor.rgba >>> 8) & Attributes.rgbMask);
        }
      }
      if (textBlinkHidden && cell.isBlink() != 0) {
        _resultFg |= FgFlags.invisible;
      }
      final fg = _resultFg;
      final bg = _resultBg;

      if (fg != lastFg || bg != lastBg) {
        lastBgArgb = _cellBackgroundArgb(fg, bg);
      }
      final base = x * _stride;
      data[base + _iWidth] = width;
      data[base + _iBg] = lastBgArgb;
      var flags = 0;
      var codeOut = 0;
      var glyphArgb = 0;
      var underlineArgb = 0;
      if (width != 0 && code != 0 && (fg & FgFlags.invisible) == 0) {
        final exclude = treatGlyphAsBackgroundColor(code);
        if (fg != glyphFg || bg != glyphBg || exclude != glyphExclude) {
          glyphArgbCached = _glyphArgb(fg, bg, exclude);
          glyphFg = fg;
          glyphBg = bg;
          glyphExclude = exclude;
        }
        glyphArgb = glyphArgbCached;
        if ((fg & FgFlags.bold) != 0) flags |= _fBold;
        if ((bg & BgFlags.italic) != 0) flags |= _fItalic;
        if (isCombined) {
          flags |= _fCombined | _fGlyph;
          codeOut = strings.length;
          strings.add(cell.combinedData);
        } else {
          codeOut = code;
          if (isCustomGlyph(code)) {
            flags |= _fCustom;
            if (blockPatternCodepoints.contains(code)) {
              final variant =
                  ((x * dims.deviceCellWidth) % 2) * 2 +
                  ((row * dims.deviceCellHeight) % 2);
              flags |= variant << _fVariantShift;
            }
          } else if (code != 0x20) {
            // Upstream measures the glyph's ink; this its advance.
            flags |=
                _rescaleOverlappingGlyphs &&
                    allowRescaling(
                      code,
                      width,
                      metrics.widthOfCodePoint(
                            code,
                            bold: (fg & FgFlags.bold) != 0,
                            italic: (bg & BgFlags.italic) != 0,
                          ) *
                          dims.devicePixelRatio,
                      dims.deviceCellWidth,
                    )
                ? _fRescale
                : _fGlyph;
          }
        }
        attrs
          ..fg = fg
          ..bg = bg;
        extended.ext = _resultExt;
        if (attrs.isUnderline() != 0) {
          final style = extended.underlineStyle;
          flags |=
              (style == UnderlineStyle.none ? UnderlineStyle.single : style) <<
              _fUnderlineShift;
          if (attrs.isUnderlineColorDefault()) {
            underlineArgb = glyphArgb;
          } else if (attrs.isUnderlineColorRGB()) {
            underlineArgb = 0xFF000000 | attrs.getUnderlineColor();
          } else {
            var index = attrs.getUnderlineColor();
            if (_drawBoldTextInBrightColors &&
                attrs.isBold() != 0 &&
                index < 8) {
              index += 8;
            }
            underlineArgb = _ansiArgb[index];
          }
        }
        if ((fg & FgFlags.strikethrough) != 0) flags |= _fStrike;
        if ((bg & BgFlags.overline) != 0) flags |= _fOverline;
      }
      lastFg = fg;
      lastBg = bg;
      data[base + _iCode] = codeOut;
      data[base + _iFg] = glyphArgb;
      data[base + _iFlags] = flags;
      data[base + _iUnderline] = underlineArgb;
      hash = _mix(hash, codeOut);
      hash = _mix(hash, width);
      hash = _mix(hash, lastBgArgb);
      hash = _mix(hash, glyphArgb);
      hash = _mix(hash, flags);
      hash = _mix(hash, underlineArgb);
    }
    for (final s in strings) {
      hash = _mix(hash, s.hashCode);
    }
    _setRowBlink(y, rowHasBlink);
    if (previous != null &&
        previous.hash == hash &&
        previous._equals(data, strings)) {
      return previous;
    }
    return _RowModel(Uint32List.fromList(data), List.of(strings), hash);
  }

  static int _mix(int hash, int value) =>
      (hash * 31 + (value & 0x3FFFFFFF)) & 0x3FFFFFFF;

  void _setRowBlink(int y, bool hasBlink) {
    if (y >= _rowHasBlink.length || _rowHasBlink[y] == hasBlink) return;
    _rowHasBlink[y] = hasBlink;
    _rowHasBlinkCount += hasBlink ? 1 : -1;
  }

  // --- Row pictures -----------------------------------------------------

  final Map<(int, int, double), ui.TextStyle> _styles = {};
  final ui.Paint _paint = ui.Paint();

  ui.TextStyle _style(int argb, int variant, double spacing) =>
      _styles[(argb, variant, spacing)] ??= metrics.textStyle(
        bold: variant & _fBold != 0,
        italic: variant & _fItalic != 0,
        color: ui.Color(argb),
        letterSpacing: spacing,
      );

  _RowPictures _picturesFor(_RowModel model) {
    final cached = _cache.remove(model);
    if (cached != null) {
      _cache[model] = cached;
      return cached;
    }
    final pictures = _RowPictures(
      _recordBackground(model),
      _recordForeground(model),
    );
    _cache[model] = pictures;
    _debugPictureRows?.add(_building);
    debugPictureBuilds++;
    return pictures;
  }

  int _building = 0;

  void _trimCache() {
    final keep = _rows * 2 + 16;
    if (_cache.length <= keep) return;
    final inUse = Set<_RowPictures>.identity()..addAll(_pictures.nonNulls);
    final stale = <_RowModel>[];
    for (final entry in _cache.entries) {
      if (_cache.length - stale.length <= keep) break;
      if (!inUse.contains(entry.value)) stale.add(entry.key);
    }
    for (final key in stale) {
      _cache.remove(key)!.dispose();
    }
  }

  ui.Picture? _recordBackground(_RowModel model) {
    final data = model.data;
    final cols = data.length ~/ _stride;
    ui.PictureRecorder? recorder;
    ui.Canvas? canvas;
    final dims = dimensions;
    final cellWidth = dims.cellWidth;
    final cellHeight = dims.cellHeight;
    var start = 0;
    var current = 0;
    void flush(int end) {
      if (current == 0 || end <= start) return;
      recorder ??= ui.PictureRecorder();
      canvas ??= ui.Canvas(recorder!);
      canvas!.drawRect(
        ui.Rect.fromLTRB(start * cellWidth, 0, end * cellWidth, cellHeight),
        _paint..color = ui.Color(current),
      );
    }

    for (var x = 0; x < cols; x++) {
      final bg = data[x * _stride + _iBg];
      if (bg != current) {
        flush(x);
        start = x;
        current = bg;
      }
    }
    flush(cols);
    return recorder?.endRecording();
  }

  String _charsOf(_RowModel model, int base) {
    final code = model.data[base + _iCode];
    if (model.data[base + _iFlags] & _fCombined != 0) {
      return model.strings[code];
    }
    return stringFromCodePoint(code);
  }

  ui.Picture? _recordForeground(_RowModel model) {
    final data = model.data;
    final cols = data.length ~/ _stride;
    var lastGlyph = -1;
    var others = false;
    for (var x = 0; x < cols; x++) {
      final flags = data[x * _stride + _iFlags];
      if (flags & _fGlyph != 0) lastGlyph = x;
      if (flags & (_fCustom | _fRescale | _fDecorations) != 0) others = true;
    }
    if (lastGlyph < 0 && !others) return null;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dims = dimensions;
    final metrics = this.metrics;
    if (lastGlyph >= 0) _drawText(canvas, model, lastGlyph, dims, metrics);
    if (others) _drawCustomAndLines(canvas, model, dims);
    return recorder.endRecording();
  }

  static const String _lro = '\u202D';

  void _drawText(
    ui.Canvas canvas,
    _RowModel model,
    int lastGlyph,
    TerminalRenderDimensions dims,
    TerminalTextMetrics metrics,
  ) {
    final data = model.data;
    final cellWidth = dims.cellWidth;
    final builder = ui.ParagraphBuilder(metrics.paragraphStyle)
      ..pushStyle(_style(0, 0, 0))
      ..addText(_lro)
      ..pop();
    final text = StringBuffer();
    var runArgb = 0;
    var runVariant = 0;
    var runSpacing = 0.0;
    var runHasGlyph = false;
    void flush() {
      if (text.isEmpty) return;
      builder
        ..pushStyle(_style(runArgb, runVariant, runSpacing))
        ..addText(text.toString())
        ..pop();
      text.clear();
    }

    for (var x = 0; x <= lastGlyph; x++) {
      final base = x * _stride;
      final width = data[base + _iWidth];
      if (width == 0) continue;
      final flags = data[base + _iFlags];
      if (flags & _fGlyph != 0) {
        final variant = flags & (_fBold | _fItalic);
        final bold = variant & _fBold != 0;
        final italic = variant & _fItalic != 0;
        final argb = data[base + _iFg];
        final code = data[base + _iCode];
        final combined = flags & _fCombined != 0;
        final spacing =
            width * cellWidth -
            (combined
                ? metrics.width(model.strings[code], bold: bold, italic: italic)
                : metrics.widthOfCodePoint(code, bold: bold, italic: italic));
        if (text.isNotEmpty &&
            (spacing != runSpacing ||
                runHasGlyph && (argb != runArgb || variant != runVariant) ||
                !runHasGlyph && variant != runVariant)) {
          flush();
        }
        if (text.isEmpty || !runHasGlyph) {
          runArgb = argb;
          runVariant = variant;
        }
        runSpacing = spacing;
        runHasGlyph = true;
        if (combined) {
          text.write(model.strings[code]);
        } else {
          text.writeCharCode(code);
        }
      } else {
        // A space holds the cell: in the run's style when its advance fits.
        final spacing =
            width * cellWidth -
            metrics.width(
              ' ',
              bold: runVariant & _fBold != 0,
              italic: runVariant & _fItalic != 0,
            );
        if (text.isNotEmpty && spacing != runSpacing) {
          flush();
          runHasGlyph = false;
        }
        if (text.isEmpty) {
          runHasGlyph = false;
          runArgb = 0;
        }
        runSpacing = spacing;
        text.write(' ');
      }
    }
    flush();
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    // The character box's bottom on its device pixel, as upstream draws text
    // on the `ideographic` baseline there.
    canvas.drawParagraph(
      paragraph,
      ui.Offset(
        dims.charLeft,
        dims.charTop + dims.charHeight - metrics.charHeight,
      ),
    );
    paragraph.dispose();
  }

  void _drawCustomAndLines(
    ui.Canvas canvas,
    _RowModel model,
    TerminalRenderDimensions dims,
  ) {
    final data = model.data;
    final cols = data.length ~/ _stride;
    final dpr = dims.devicePixelRatio;
    final cellWidth = dims.cellWidth;
    final cellHeight = dims.cellHeight;
    final fontSize = _options.fontSize;
    final charSize = ui.Size(dims.charWidth, dims.charHeight);
    for (var x = 0; x < cols; x++) {
      final base = x * _stride;
      final flags = data[base + _iFlags];
      if (flags & (_fCustom | _fRescale | _fDecorations) == 0) continue;
      final width = data[base + _iWidth];
      final argb = data[base + _iFg];
      if (flags & _fCustom != 0) {
        final bg = data[base + _iBg];
        paintCustomGlyph(
          canvas,
          data[base + _iCode],
          ui.Rect.fromLTWH(x * cellWidth, 0, cellWidth, cellHeight),
          ui.Color(argb),
          devicePixelRatio: dpr,
          fontSize: fontSize,
          charSize: charSize,
          backgroundColor: ui.Color(bg == 0 ? _backgroundArgb : bg),
          variantOffset: blockPatternCodepoints.contains(data[base + _iCode])
              ? (flags >> _fVariantShift) & 3
              : null,
        );
      }
      if (flags & _fRescale != 0) {
        _drawRescaled(canvas, x, data[base + _iCode], flags, argb, dims);
      }
      if (flags & _fDecorations != 0) {
        _drawLines(
          canvas,
          x,
          width,
          flags,
          argb,
          data[base + _iUnderline],
          dims,
        );
      }
    }
  }

  /// A one cell glyph wider than a cell and a half, squeezed to the cell
  /// less a pixel (upstream GlyphRenderer's `rescaleOverlappingGlyphs`).
  void _drawRescaled(
    ui.Canvas canvas,
    int x,
    int code,
    int flags,
    int argb,
    TerminalRenderDimensions dims,
  ) {
    final metrics = this.metrics;
    final bold = flags & _fBold != 0;
    final italic = flags & _fItalic != 0;
    final advance = metrics.widthOfCodePoint(code, bold: bold, italic: italic);
    if (advance <= 0) return;
    final builder = ui.ParagraphBuilder(metrics.paragraphStyle)
      ..pushStyle(_style(argb, flags & (_fBold | _fItalic), 0))
      ..addText(stringFromCodePoint(code));
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    canvas
      ..save()
      ..translate(
        x * dims.cellWidth + dims.charLeft,
        dims.charTop + dims.charHeight - metrics.charHeight,
      )
      ..scale((dims.deviceCellWidth - 1) / dims.devicePixelRatio / advance, 1)
      ..drawParagraph(paragraph, ui.Offset.zero)
      ..restore();
    paragraph.dispose();
  }

  /// Underline, overline and strikethrough of a cell, in upstream's device
  /// pixel geometry (TextureAtlas `_drawToCache`).
  void _drawLines(
    ui.Canvas canvas,
    int x,
    int width,
    int flags,
    int argb,
    int underlineArgb,
    TerminalRenderDimensions dims,
  ) {
    final dpr = dims.devicePixelRatio;
    final fontSize = _options.fontSize;
    final cellW = dims.deviceCellWidth;
    final charH = dims.deviceCharHeight;
    // The character box's origin, in device pixels.
    final left = x * cellW + dims.deviceCharLeft;
    final top = dims.deviceCharTop;
    final lineWidth = math.max(1, (fontSize * dpr / 15).floor());
    final yOffset = lineWidth.isOdd ? 0.5 : 0.0;
    void rect(double l, double t, double r, double b, int color) {
      canvas.drawRect(
        ui.Rect.fromLTRB(l / dpr, t / dpr, r / dpr, b / dpr),
        _paint..color = ui.Color(color),
      );
    }

    final underline = (flags & _fUnderlineMask) >> _fUnderlineShift;
    if (underline != UnderlineStyle.none) {
      final color = underlineArgb;
      final yTopDefault = top + charH - yOffset;
      final yBotDefault = yTopDefault + lineWidth * 2;
      final half = lineWidth / 2;
      for (var i = 0; i < width; i++) {
        final xLeft = (left + i * cellW).toDouble();
        final xRight = xLeft + cellW;
        switch (underline) {
          case UnderlineStyle.double:
            rect(xLeft, yTopDefault - half, xRight, yTopDefault + half, color);
            rect(xLeft, yBotDefault - half, xRight, yBotDefault + half, color);
          case UnderlineStyle.curly:
            // Upstream's zigzag (Monaco's 6x3 SVG), below the character box.
            final yTop = top + charH + 1 - 4.0;
            final yBot = yTop + 3 * dpr;
            final scaleX = cellW / 6;
            final scaleY = (yBot - yTop) / 3;
            canvas.save();
            canvas.clipRect(
              ui.Rect.fromLTRB(
                xLeft / dpr,
                yTop / dpr,
                xRight / dpr,
                yBot / dpr,
              ),
            );
            final path = ui.Path();
            for (final polygon in _curlyPolygons) {
              for (var p = 0; p < polygon.length; p += 2) {
                final px = (xLeft + polygon[p] * scaleX) / dpr;
                final py = (yBot - polygon[p + 1] * scaleY) / dpr;
                if (p == 0) {
                  path.moveTo(px, py);
                } else {
                  path.lineTo(px, py);
                }
              }
              path.close();
            }
            canvas.drawPath(path, _paint..color = ui.Color(color));
            canvas.restore();
          case UnderlineStyle.dotted:
            // Dots and gaps of the line's width, in phase across cells.
            final period = lineWidth * 2;
            var px = xLeft;
            while (px < xRight) {
              final phase = px.round() % period;
              if (phase < lineWidth) {
                final end = math.min(px + (lineWidth - phase), xRight);
                rect(px, yTopDefault - half, end, yTopDefault + half, color);
                px = end + lineWidth;
              } else {
                px += period - phase;
              }
            }
          case UnderlineStyle.dashed:
            final xChWidth = cellW;
            final line = (0.6 * xChWidth).floor();
            final gap = (0.3 * xChWidth).floor();
            rect(
              xLeft,
              yTopDefault - half,
              xLeft + line,
              yTopDefault + half,
              color,
            );
            rect(
              xLeft + line + gap,
              yTopDefault - half,
              xRight,
              yTopDefault + half,
              color,
            );
          default:
            rect(xLeft, yTopDefault - half, xRight, yTopDefault + half, color);
        }
      }
    }

    final charWidth = dims.deviceCharWidth * width;
    if (flags & _fOverline != 0) {
      final half = lineWidth / 2;
      final y = top + yOffset;
      rect(
        left.toDouble(),
        y - half,
        left + charWidth.toDouble(),
        y + half,
        argb,
      );
    }
    if (flags & _fStrike != 0) {
      final strikeWidth = math.max(1, (fontSize * dpr / 10).floor());
      // Upstream offsets by the width the canvas last stroked with: the
      // overline's, else (in the steady state) the last strikethrough's.
      final previous = flags & _fOverline != 0 ? lineWidth : strikeWidth;
      final y = top + (charH / 2).floor() - (previous.isOdd ? 0.5 : 0.0);
      final half = strikeWidth / 2;
      rect(
        left.toDouble(),
        y - half,
        left + charWidth.toDouble(),
        y + half,
        argb,
      );
    }
  }

  static const List<List<double>> _curlyPolygons = [
    [0, 2, 1, 3, 2.4, 3, 0, 0.6],
    [5.5, 0, 2.5, 3, 1.1, 3, 4.1, 0],
    [4, 0, 6, 2, 6, 0.6, 5.4, 0],
  ];

  // --- Frame ------------------------------------------------------------

  /// Brings the rows up to date: the cursor, the scroll position and the
  /// size are compared with the last frame's; dirty rows get new models and
  /// changed models new pictures. Rows outside [firstVisible] to
  /// [lastVisible] stay dirty until they show.
  void _update(int firstVisible, int lastVisible) {
    final cols = source.cols;
    final rows = source.rows;
    if (cols != _cols || rows != _rows) _resize(cols, rows);
    final buffer = source.buffer;
    if (buffer.ydisp != _paintedYdisp || !identical(buffer, _paintedBuffer)) {
      _paintedYdisp = buffer.ydisp;
      _paintedBuffer = buffer;
      _dirty.fillRange(0, _dirty.length, 1);
    }

    // Synchronized output holds the rows as they are, for a second at most.
    if (source.synchronizedOutput) {
      _syncOutputTimeout ??= Timer(const Duration(seconds: 1), () {
        _syncOutputTimeout = null;
        source.synchronizedOutput = false;
        _refreshAll();
      });
      return;
    }
    _syncOutputTimeout?.cancel();
    _syncOutputTimeout = null;

    // The cursor. DECSCUSR may have turned its blinking on or off.
    final options = _options;
    if ((source.cursorBlink ?? options.cursorBlink) != (_cursorBlink != null)) {
      _updateCursorBlink(requestPaint: false);
    }
    final style = source.cursorStyle ?? options.cursorStyle;
    _cursorRow = buffer.ybase + buffer.y;
    _cursorX = math.min(buffer.x, math.max(cols - 1, 0));
    _cursorVisible =
        source.isCursorInitialized &&
        !source.isCursorHidden &&
        (_cursorBlink?.isCursorVisible ?? true);
    _cursorStyleNow = _isFocused ? style : options.cursorInactiveStyle;
    final cursor = (_cursorRow, _cursorX, _cursorVisible, _cursorStyleNow);
    final painted = _paintedCursor;
    if (painted != cursor) {
      if (painted != null) _markBufferRowDirty(painted.$1);
      _markBufferRowDirty(_cursorRow);
      _paintedCursor = cursor;
    }

    _drawBoldTextInBrightColors = options.drawBoldTextInBrightColors;
    _minimumContrastRatio = options.minimumContrastRatio;
    _rescaleOverlappingGlyphs = options.rescaleOverlappingGlyphs;
    final decorations = source.decorationService;
    _hasDecorations = decorations != null && decorations.decorations.isNotEmpty;
    for (var y = math.max(firstVisible, 0); y <= lastVisible && y < rows; y++) {
      if (_dirty[y] == 0) continue;
      _dirty[y] = 0;
      final previous = _models[y];
      final model = _buildModel(y, previous);
      _debugModelRows?.add(y);
      debugModelBuilds++;
      if (identical(model, previous) && _pictures[y] != null) continue;
      _models[y] = model;
      _building = y;
      _pictures[y] = _picturesFor(model);
    }
    _textBlink.setNeedsBlinkInViewport(_rowHasBlinkCount > 0);
    _trimCache();
  }

  void _markBufferRowDirty(int line) {
    final y = line - source.buffer.ydisp;
    if (y >= 0 && y < _dirty.length) _dirty[y] = 1;
  }

  /// Paints the rows at [origin] (the grid's top left), then the cursor and
  /// the link underline. Only rows that meet the canvas' clip are brought
  /// up to date and drawn.
  void paint(ui.Canvas canvas, ui.Offset origin) {
    if (_disposed) return;
    final dims = dimensions;
    if (!metrics.hasValidSize) return;
    final cellHeight = dims.cellHeight;
    final clip = canvas.getLocalClipBounds();
    final rows = source.rows;
    final first = ((clip.top - origin.dy) / cellHeight).floor();
    final last = ((clip.bottom - origin.dy) / cellHeight).ceil() - 1;
    final firstVisible = math.max(first, 0);
    final lastVisible = math.min(last, rows - 1);
    _debugModelRows?.clear();
    _debugPictureRows?.clear();
    _update(firstVisible, lastVisible);
    debugPaints++;

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (var y = firstVisible; y <= lastVisible && y < _pictures.length; y++) {
      final picture = _pictures[y]?.background;
      if (picture == null) continue;
      canvas.save();
      canvas.translate(0, y * cellHeight);
      canvas.drawPicture(picture);
      canvas.restore();
    }
    for (var y = firstVisible; y <= lastVisible && y < _pictures.length; y++) {
      final picture = _pictures[y]?.foreground;
      if (picture == null) continue;
      canvas.save();
      canvas.translate(0, y * cellHeight);
      canvas.drawPicture(picture);
      canvas.restore();
    }
    _paintCursor(canvas, dims);
    _paintLinkUnderline(canvas, dims);
    canvas.restore();
  }

  /// The cursor's cell in the grid, or null when it is not in view: where
  /// the IME's composition goes.
  ui.Rect? get cursorRect {
    final buffer = source.buffer;
    final y = buffer.ybase + buffer.y - buffer.ydisp;
    if (y < 0 || y >= source.rows) return null;
    final dims = dimensions;
    final x = math.min(buffer.x, source.cols - 1);
    return ui.Rect.fromLTWH(
      x * dims.cellWidth,
      y * dims.cellHeight,
      dims.cellWidth,
      dims.cellHeight,
    );
  }

  /// Upstream RectangleRenderer's `updateCursor`: the cursor styles other
  /// than the block, which the row models draw.
  void _paintCursor(ui.Canvas canvas, TerminalRenderDimensions dims) {
    if (!_cursorVisible) return;
    final style = _cursorStyleNow;
    if (style == null || style == 'block' || style == 'none') return;
    final buffer = source.buffer;
    final y = _cursorRow - buffer.ydisp;
    if (y < 0 || y >= source.rows) return;
    final line = buffer.lines.get(_cursorRow);
    final width = line?.getWidth(_cursorX) ?? 1;
    final cellWidth = dims.cellWidth;
    final cellHeight = dims.cellHeight;
    final left = _cursorX * cellWidth;
    final top = y * cellHeight;
    // One device pixel is `dpr` of them: a logical pixel.
    const edge = 1.0;
    final paint = _paint..color = ui.Color(_cursorArgb);
    if (style == 'bar' || style == 'outline') {
      final barWidth = style == 'bar' ? _options.cursorWidth.toDouble() : edge;
      canvas.drawRect(ui.Rect.fromLTWH(left, top, barWidth, cellHeight), paint);
    }
    if (style == 'underline' || style == 'outline') {
      canvas.drawRect(
        ui.Rect.fromLTWH(
          left,
          top + cellHeight - edge,
          width * cellWidth,
          edge,
        ),
        paint,
      );
    }
    if (style == 'outline') {
      canvas.drawRect(
        ui.Rect.fromLTWH(left, top, width * cellWidth, edge),
        paint,
      );
      canvas.drawRect(
        ui.Rect.fromLTWH(
          left + width * cellWidth - edge,
          top,
          edge,
          cellHeight,
        ),
        paint,
      );
    }
  }

  /// Upstream LinkRenderLayer: a line at the bottom of the link's cells.
  void _paintLinkUnderline(ui.Canvas canvas, TerminalRenderDimensions dims) {
    final e = _linkUnderline;
    if (e == null) return;
    final int argb;
    if (e.fg == invertedDefaultColor) {
      argb = _backgroundArgb;
    } else if (e.fg != null && e.fg! >= 0 && e.fg! < 256) {
      argb = _ansiArgb[e.fg!];
    } else {
      argb = _foregroundArgb;
    }
    final paint = _paint..color = ui.Color(argb);
    final dpr = dims.devicePixelRatio;
    void fill(int x, int y, int width) {
      if (y < 0 || y >= source.rows || width <= 0) return;
      final top = ((y + 1) * dims.deviceCellHeight - dpr - 1) / dpr;
      canvas.drawRect(
        ui.Rect.fromLTWH(x * dims.cellWidth, top, width * dims.cellWidth, 1),
        paint,
      );
    }

    if (e.y1 == e.y2) {
      fill(e.x1, e.y1, e.x2 - e.x1);
    } else {
      fill(e.x1, e.y1, e.cols - e.x1);
      for (var y = e.y1 + 1; y < e.y2; y++) {
        fill(0, y, e.cols);
      }
      fill(0, e.y2, e.x2);
    }
  }

  /// Upstream `_updateCursorBlink`: a blinking cursor for DECSCUSR's or the
  /// option's blinking. The cursor's rows are found dirty at the next paint.
  void _updateCursorBlink({bool requestPaint = true}) {
    final blink = source.cursorBlink ?? _options.cursorBlink;
    _cursorBlink?.dispose();
    _cursorBlink = blink
        ? TerminalCursorBlink(_requestPaint, isFocused: _isFocused)
        : null;
    if (requestPaint) _requestPaint();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _store.dispose();
    _textBlink.dispose();
    _cursorBlink?.dispose();
    _syncOutputTimeout?.cancel();
    for (final pictures in _cache.values) {
      pictures.dispose();
    }
    _cache.clear();
  }

  // --- Debugging --------------------------------------------------------

  /// Row models built, and row pictures recorded, since creation.
  @visibleForTesting
  int debugModelBuilds = 0;
  @visibleForTesting
  int debugPictureBuilds = 0;
  @visibleForTesting
  int debugPaints = 0;

  List<int>? _debugModelRows;
  List<int>? _debugPictureRows;

  /// Starts recording which viewport rows the last paint rebuilt.
  @visibleForTesting
  void debugTrackRows() {
    _debugModelRows = [];
    _debugPictureRows = [];
  }

  /// The rows whose models the last paint rebuilt (after [debugTrackRows]).
  @visibleForTesting
  List<int> get debugLastModelRows => List.of(_debugModelRows ?? const []);

  /// The rows whose pictures the last paint recorded (after
  /// [debugTrackRows]).
  @visibleForTesting
  List<int> get debugLastPictureRows => List.of(_debugPictureRows ?? const []);

  /// Viewport row [y]'s text as last built (spaces for empty cells, none at
  /// the end).
  @visibleForTesting
  String? debugRowText(int y) {
    if (y < 0 || y >= _models.length) return null;
    final model = _models[y];
    if (model == null) return null;
    final text = StringBuffer();
    final cols = model.data.length ~/ _stride;
    for (var x = 0; x < cols; x++) {
      final base = x * _stride;
      final width = model.data[base + _iWidth];
      if (width == 0) continue;
      final flags = model.data[base + _iFlags];
      text.write(
        flags & (_fGlyph | _fCustom | _fRescale) != 0
            ? _charsOf(model, base)
            : ' ',
      );
    }
    return text.toString().trimRight();
  }

  /// The colors cell ([x], [y]) was last built with: its glyph's (0 when it
  /// draws none) and its background's (0 for the theme's).
  @visibleForTesting
  ({ui.Color? fg, ui.Color? bg, ui.Color? underline})? debugCellColors(
    int x,
    int y,
  ) {
    if (y < 0 || y >= _models.length) return null;
    final model = _models[y];
    if (model == null || (x + 1) * _stride > model.data.length) return null;
    final base = x * _stride;
    final fg = model.data[base + _iFg];
    final bg = model.data[base + _iBg];
    final underline = model.data[base + _iUnderline];
    return (
      fg: fg == 0 ? null : ui.Color(fg),
      bg: bg == 0 ? null : ui.Color(bg),
      underline: underline == 0 ? null : ui.Color(underline),
    );
  }

  /// The number of row pictures cached.
  @visibleForTesting
  int get debugCachedPictures => _cache.length;
}
