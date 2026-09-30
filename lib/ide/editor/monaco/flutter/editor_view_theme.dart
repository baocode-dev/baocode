import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Colors for the painted editor's view parts. Defaults follow VS Code's
/// "Dark Modern" workbench colors (`editor.*`, `editorLineNumber.*`,
/// `scrollbarSlider.*`, `minimapSlider.*`, `editorOverviewRuler.*`). The editor
/// background, text color and caret color remain [EditorSurface] parameters.
@immutable
class EditorViewTheme {
  const EditorViewTheme({
    this.gutterBackground,
    this.lineNumberForeground = const Color(0xff6e7681),
    this.activeLineNumberForeground = const Color(0xffcccccc),
    this.currentLineBorder = const Color(0xff282828),
    this.currentLineBackground,
    this.inactiveSelectionBackground = const Color(0xff3a3d41),
    this.selectionHighlightBackground = const Color(0x26add6ff),
    this.bracketMatchBackground = const Color(0x1a006400),
    this.bracketMatchBorder = const Color(0xff888888),
    this.indentGuide = const Color(0xff404040),
    this.activeIndentGuide = const Color(0xff707070),
    this.whitespaceForeground = const Color(0x29e3e4e2),
    this.foldingControlForeground = const Color(0xffc5c5c5),
    this.foldPlaceholderForeground = const Color(0xff808080),
    this.foldPlaceholderBackground = const Color(0x33808080),
    this.foldedLineBackground = const Color(0x4d264f78),
    this.findMatchBackground = const Color(0xff9e6a03),
    this.findMatchHighlightBackground = const Color(0x55ea5c00),
    this.errorForeground = const Color(0xfff14c4c),
    this.warningForeground = const Color(0xffcca700),
    this.infoForeground = const Color(0xff3794ff),
    this.hintForeground = const Color(0xb3eeeeee),
    this.scrollbarShadow = const Color(0xff000000),
    this.scrollbarSliderBackground = const Color(0x66797979),
    this.scrollbarSliderHoverBackground = const Color(0xb3646464),
    this.scrollbarSliderActiveBackground = const Color(0x66bfbfbf),
    this.overviewRulerBorder = const Color(0x4d7f7f7f),
    this.overviewRulerFindMatchForeground = const Color(0x7ed18616),
    this.overviewRulerSelectionForeground = const Color(0xcca0a0a0),
    this.overviewRulerCursorForeground = const Color(0xcca0a0a0),
    this.minimapBackground,
    this.minimapSliderBackground = const Color(0x33797979),
    this.minimapSliderHoverBackground = const Color(0x59646464),
    this.minimapSliderActiveBackground = const Color(0x33bfbfbf),
    this.minimapSelectionHighlight = const Color(0xff264f78),
    this.minimapFindMatchHighlight = const Color(0xffd18616),
    this.overflowBackground = const Color(0xff297aa0),
    this.overflowForeground = const Color(0xffffffff),
  });

  /// The view colors a workbench theme gives ([color] looks a color id up:
  /// the theme's, else the registry's default), else the Dark Modern ones.
  factory EditorViewTheme.fromColors(Color? Function(String id) color) {
    const d = EditorViewTheme();
    Color c(String id, Color fallback) => color(id) ?? fallback;
    final cursor = color('editorCursor.foreground');
    return EditorViewTheme(
      gutterBackground: color('editorGutter.background'),
      lineNumberForeground: c(
        'editorLineNumber.foreground',
        d.lineNumberForeground,
      ),
      activeLineNumberForeground: c(
        'editorLineNumber.activeForeground',
        d.activeLineNumberForeground,
      ),
      currentLineBorder: c('editor.lineHighlightBorder', d.currentLineBorder),
      currentLineBackground: color('editor.lineHighlightBackground'),
      inactiveSelectionBackground: c(
        'editor.inactiveSelectionBackground',
        d.inactiveSelectionBackground,
      ),
      selectionHighlightBackground: c(
        'editor.selectionHighlightBackground',
        d.selectionHighlightBackground,
      ),
      bracketMatchBackground: c(
        'editorBracketMatch.background',
        d.bracketMatchBackground,
      ),
      bracketMatchBorder: c('editorBracketMatch.border', d.bracketMatchBorder),
      indentGuide: c('editorIndentGuide.background1', d.indentGuide),
      activeIndentGuide: c(
        'editorIndentGuide.activeBackground1',
        d.activeIndentGuide,
      ),
      whitespaceForeground: c(
        'editorWhitespace.foreground',
        d.whitespaceForeground,
      ),
      foldingControlForeground: c(
        'editorGutter.foldingControlForeground',
        d.foldingControlForeground,
      ),
      foldPlaceholderForeground: c(
        'editor.foldPlaceholderForeground',
        d.foldPlaceholderForeground,
      ),
      foldedLineBackground: c('editor.foldBackground', d.foldedLineBackground),
      findMatchBackground: c(
        'editor.findMatchBackground',
        d.findMatchBackground,
      ),
      findMatchHighlightBackground: c(
        'editor.findMatchHighlightBackground',
        d.findMatchHighlightBackground,
      ),
      errorForeground: c('editorError.foreground', d.errorForeground),
      warningForeground: c('editorWarning.foreground', d.warningForeground),
      infoForeground: c('editorInfo.foreground', d.infoForeground),
      hintForeground: c('editorHint.foreground', d.hintForeground),
      scrollbarShadow: c('scrollbar.shadow', d.scrollbarShadow),
      scrollbarSliderBackground: c(
        'scrollbarSlider.background',
        d.scrollbarSliderBackground,
      ),
      scrollbarSliderHoverBackground: c(
        'scrollbarSlider.hoverBackground',
        d.scrollbarSliderHoverBackground,
      ),
      scrollbarSliderActiveBackground: c(
        'scrollbarSlider.activeBackground',
        d.scrollbarSliderActiveBackground,
      ),
      overviewRulerBorder: c(
        'editorOverviewRuler.border',
        d.overviewRulerBorder,
      ),
      overviewRulerFindMatchForeground: c(
        'editorOverviewRuler.findMatchForeground',
        d.overviewRulerFindMatchForeground,
      ),
      overviewRulerSelectionForeground: c(
        'editorOverviewRuler.selectionHighlightForeground',
        d.overviewRulerSelectionForeground,
      ),
      // `cursorColorSingle`: the cursor color at 70%.
      overviewRulerCursorForeground: cursor == null
          ? d.overviewRulerCursorForeground
          : cursor.withValues(alpha: cursor.a * 0.7),
      minimapBackground: color('minimap.background'),
      minimapSliderBackground: c(
        'minimapSlider.background',
        d.minimapSliderBackground,
      ),
      minimapSliderHoverBackground: c(
        'minimapSlider.hoverBackground',
        d.minimapSliderHoverBackground,
      ),
      minimapSliderActiveBackground: c(
        'minimapSlider.activeBackground',
        d.minimapSliderActiveBackground,
      ),
      minimapSelectionHighlight: c(
        'minimap.selectionHighlight',
        d.minimapSelectionHighlight,
      ),
      minimapFindMatchHighlight: c(
        'minimap.findMatchHighlight',
        d.minimapFindMatchHighlight,
      ),
      overflowBackground:
          color('button.background') ??
          color('editor.background') ??
          d.overflowBackground,
      overflowForeground:
          color('button.foreground') ??
          color('editor.foreground') ??
          d.overflowForeground,
    );
  }

  /// Defaults to the editor background.
  final Color? gutterBackground;
  final Color lineNumberForeground;
  final Color activeLineNumberForeground;

  /// Border of the current line (`editor.lineHighlightBorder`), painted when
  /// the primary selection is empty.
  final Color currentLineBorder;

  /// Optional fill of the current line (`editor.lineHighlightBackground`).
  final Color? currentLineBackground;

  /// Selection color while the editor is unfocused.
  final Color inactiveSelectionBackground;

  /// Other occurrences of a selected word (`editor.selectionHighlightBackground`).
  final Color selectionHighlightBackground;
  final Color bracketMatchBackground;
  final Color bracketMatchBorder;
  final Color indentGuide;
  final Color activeIndentGuide;
  final Color whitespaceForeground;
  final Color foldingControlForeground;
  final Color foldPlaceholderForeground;
  final Color foldPlaceholderBackground;

  /// Background of a collapsed region's header line (`editor.foldBackground`).
  final Color foldedLineBackground;

  /// Current find match (`editor.findMatchBackground`).
  final Color findMatchBackground;

  /// Other find matches (`editor.findMatchHighlightBackground`).
  final Color findMatchHighlightBackground;
  final Color errorForeground;
  final Color warningForeground;
  final Color infoForeground;

  /// The dots under a hint (`editorHint.foreground`).
  final Color hintForeground;
  final Color scrollbarShadow;
  final Color scrollbarSliderBackground;
  final Color scrollbarSliderHoverBackground;
  final Color scrollbarSliderActiveBackground;
  final Color overviewRulerBorder;
  final Color overviewRulerFindMatchForeground;
  final Color overviewRulerSelectionForeground;
  final Color overviewRulerCursorForeground;

  /// Defaults to the editor background.
  final Color? minimapBackground;
  final Color minimapSliderBackground;
  final Color minimapSliderHoverBackground;
  final Color minimapSliderActiveBackground;
  final Color minimapSelectionHighlight;
  final Color minimapFindMatchHighlight;

  /// The "Show more (…)" pill of a line cut at `stopRenderingLineAfter`
  /// (`.mtkoverflow`: `button.background`, `button.foreground`).
  final Color overflowBackground;
  final Color overflowForeground;

  @override
  bool operator ==(Object other) =>
      other is EditorViewTheme &&
      other.gutterBackground == gutterBackground &&
      other.lineNumberForeground == lineNumberForeground &&
      other.activeLineNumberForeground == activeLineNumberForeground &&
      other.currentLineBorder == currentLineBorder &&
      other.currentLineBackground == currentLineBackground &&
      other.inactiveSelectionBackground == inactiveSelectionBackground &&
      other.selectionHighlightBackground == selectionHighlightBackground &&
      other.bracketMatchBackground == bracketMatchBackground &&
      other.bracketMatchBorder == bracketMatchBorder &&
      other.indentGuide == indentGuide &&
      other.activeIndentGuide == activeIndentGuide &&
      other.whitespaceForeground == whitespaceForeground &&
      other.foldingControlForeground == foldingControlForeground &&
      other.foldPlaceholderForeground == foldPlaceholderForeground &&
      other.foldPlaceholderBackground == foldPlaceholderBackground &&
      other.foldedLineBackground == foldedLineBackground &&
      other.findMatchBackground == findMatchBackground &&
      other.findMatchHighlightBackground == findMatchHighlightBackground &&
      other.errorForeground == errorForeground &&
      other.warningForeground == warningForeground &&
      other.infoForeground == infoForeground &&
      other.hintForeground == hintForeground &&
      other.scrollbarShadow == scrollbarShadow &&
      other.scrollbarSliderBackground == scrollbarSliderBackground &&
      other.scrollbarSliderHoverBackground == scrollbarSliderHoverBackground &&
      other.scrollbarSliderActiveBackground ==
          scrollbarSliderActiveBackground &&
      other.overviewRulerBorder == overviewRulerBorder &&
      other.overviewRulerFindMatchForeground ==
          overviewRulerFindMatchForeground &&
      other.overviewRulerSelectionForeground ==
          overviewRulerSelectionForeground &&
      other.overviewRulerCursorForeground == overviewRulerCursorForeground &&
      other.minimapBackground == minimapBackground &&
      other.minimapSliderBackground == minimapSliderBackground &&
      other.minimapSliderHoverBackground == minimapSliderHoverBackground &&
      other.minimapSliderActiveBackground == minimapSliderActiveBackground &&
      other.minimapSelectionHighlight == minimapSelectionHighlight &&
      other.minimapFindMatchHighlight == minimapFindMatchHighlight &&
      other.overflowBackground == overflowBackground &&
      other.overflowForeground == overflowForeground;

  @override
  int get hashCode => Object.hashAll([
    gutterBackground,
    lineNumberForeground,
    activeLineNumberForeground,
    currentLineBorder,
    currentLineBackground,
    inactiveSelectionBackground,
    selectionHighlightBackground,
    bracketMatchBackground,
    bracketMatchBorder,
    indentGuide,
    activeIndentGuide,
    whitespaceForeground,
    foldingControlForeground,
    foldPlaceholderForeground,
    foldPlaceholderBackground,
    foldedLineBackground,
    findMatchBackground,
    findMatchHighlightBackground,
    errorForeground,
    warningForeground,
    infoForeground,
    hintForeground,
    scrollbarShadow,
    scrollbarSliderBackground,
    scrollbarSliderHoverBackground,
    scrollbarSliderActiveBackground,
    overviewRulerBorder,
    overviewRulerFindMatchForeground,
    overviewRulerSelectionForeground,
    overviewRulerCursorForeground,
    minimapBackground,
    minimapSliderBackground,
    minimapSliderHoverBackground,
    minimapSliderActiveBackground,
    minimapSelectionHighlight,
    minimapFindMatchHighlight,
    overflowBackground,
    overflowForeground,
  ]);
}
