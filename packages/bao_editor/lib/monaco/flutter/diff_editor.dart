// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// A diff editor around two editors, after VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/browser/widget/diffEditor/diffEditorWidget.ts (the layout),
// diffEditorOptions.ts and common/config/diffEditor.ts (side by side above
// `renderSideBySideInlineBreakpoint`, else inline), components/
// diffEditorViewZones/renderLines.ts (the inline view's deleted code),
// features/overviewRulerFeature.ts and style.css.
//
// Deviations: side by side is laid out as JetBrains IDEs' diff viewer is.
// The two editors are not aligned with zones: each scrolls on its own, kept
// level with the other through the changes (JetBrains' SyncScrollSupport,
// the anchor going down the view as it scrolls down the text, as Meld's);
// the original's line numbers are at the split, by a band joining each
// change across it. Inline is a unified diff: the modified editor alone,
// the deleted code's line numbers the original's in its gutter, a bar at
// the gutter's edge by the changed lines and no signs. The overview has
// one lane and is the editors' scrollbar. No gutter menu, lightbulb on
// deleted code, accessible diff viewer or moved code; deleted code is not
// selectable, and draws tabs as the text engine shapes them. Unchanged
// lines are hidden (VS Code's hideUnchangedRegions, [DiffEditor.hideUnchanged])
// behind a bar that shows them all, not by steps or by the code's outline.
// Revert arrows and the like are the embedder's, laid over the editors
// ([DiffEditor.overlay]); side by side or inline can be forced
// ([DiffEditor.sideBySide]), and the inner changes highlighted by word,
// by line or not at all ([DiffEditor.highlight]).

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../vs/editor/common/diff/range_mapping.dart';
import 'diff_editor_model.dart';
import 'document_snapshot.dart';
import 'editor_scrollbar.dart';
import 'editor_surface.dart';
import 'editor_view_painters.dart';
import 'viewport_layout.dart' show HiddenLineRanges;
import 'wheel_glide.dart';

/// What the diff gives one of a diff editor's editors. Its editor shows no
/// vertical scrollbar (`EditorSurface.verticalScrollbar`): the diff's
/// overview is that.
class DiffEditorSide {
  const DiffEditorSide({
    required this.zones,
    required this.decorations,
    required this.scrollPosition,
    required this.sideBySide,
    this.hiddenLines,
    this.lineNumbers = true,
    this.lineNumbersMinChars = EditorViewGeometry.lineNumbersMinChars,
  });

  final List<EditorViewZone> zones;
  final List<EditorDecoration> decorations;

  /// Unchanged lines hidden ([DiffEditor.hideUnchanged]), for
  /// [EditorSurface.hiddenLines]; a bar in [zones] stands for each run.
  final HiddenLineRanges? hiddenLines;

  /// The editor's scroll, which the diff editor keeps level with the
  /// other's.
  final ValueNotifier<Offset> scrollPosition;

  /// Whether the two show side by side; else the modified shows alone.
  final bool sideBySide;

  /// Whether the editor shows its line numbers: side by side, the
  /// original's are at the split instead.
  final bool lineNumbers;

  /// The fewest digits its line numbers have room for
  /// (`EditorSurface.lineNumbersMinChars`): side by side, the modified's
  /// no wider than they are, close by the split.
  final int lineNumbersMinChars;
}

/// Where a diff editor's parts are, for what is laid over them
/// ([DiffEditor.overlay]): whether side by side; the split's left (the
/// original editor's width) and the band's in it, past the original's line
/// numbers (inline, both the modified editor's left); the modified editor's
/// left, and the editors' right; and side by side, the top of the
/// original's line [originalTop] (its line count + 1 for its end) as it is
/// scrolled now.
typedef DiffEditorLayout = ({
  bool sideBySide,
  double splitLeft,
  double bandLeft,
  double modifiedLeft,
  double contentWidth,
  double Function(int line)? originalTop,
});

/// Two editors, [original] and [modified], built for what the diff of
/// [model] gives each ([DiffEditorSide]): side by side with the split
/// between them, or, no wider than [inlineBreakpoint], the modified with the
/// deleted code in it; with the diff's overview at the right.
class DiffEditor extends StatefulWidget {
  const DiffEditor({
    super.key,
    required this.model,
    required this.original,
    required this.modified,
    required this.style,
    required this.theme,
    required this.colors,
    required this.dark,
    this.background,
    this.originalStyledLines,
    this.border,
    this.sashHover,
    this.sideBySide,
    this.highlight = DiffHighlight.characters,
    this.overlay,
    this.hideUnchanged = false,
    this.unchangedLabel,
    this.keepVisible,
    this.scrollPosition,
  });

  /// A modified line to show, its unchanged run not hidden.
  final int? keepVisible;

  /// How far the modified editor is scrolled, for the caller to keep
  /// (where a tab shown again was left); the editor's own when null.
  final ValueNotifier<Offset>? scrollPosition;

  /// Unchanged runs of lines hidden, but for [unchangedContext] lines next
  /// to the changes, behind a bar that shows them again (JetBrains'
  /// Collapse Unchanged Fragments).
  final bool hideUnchanged;

  /// The bar's text for [count] hidden lines.
  final String Function(int count)? unchangedLabel;

  /// Lines kept on each side of a change; and the fewest hidden.
  static const unchangedContext = 3;
  static const unchangedMinimum = 3;

  /// Side by side (true) or inline (false); by the width when null
  /// ([inlineBreakpoint]).
  final bool? sideBySide;

  /// How much of a changed line is marked.
  final DiffHighlight highlight;

  /// Laid over the editors, as they are laid out: the embedder's revert
  /// arrows and the like.
  final Widget Function(BuildContext context, DiffEditorLayout layout)? overlay;

  final DiffEditorModel model;
  final Widget Function(BuildContext context, DiffEditorSide side) original;
  final Widget Function(BuildContext context, DiffEditorSide side) modified;

  /// The editors' text style (the deleted code's and the split's line
  /// numbers' too).
  final TextStyle style;
  final EditorViewTheme theme;
  final DiffEditorColors colors;

  /// The theme is dark.
  final bool dark;

  /// The editors' background (`editor.background`): the split's and the
  /// overview's.
  final Color? background;

  /// The original's tokens, for the deleted code.
  final Map<int, List<TextSpan>>? originalStyledLines;

  /// `diffEditor.border`, at the split's edges.
  final Color? border;

  /// `sash.hoverBorder`: the split's edges while it is dragged or hovered.
  final Color? sashHover;

  /// `renderSideBySideInlineBreakpoint`.
  static const inlineBreakpoint = 900.0;

  /// The overview at the right, which scrolls the editors.
  static const overviewWidth = 12.0;

  /// The band joining a change's two sides, across the split.
  static const bandWidth = 40.0;

  /// `MINIMUM_EDITOR_WIDTH` of the sash.
  static const minimumEditorWidth = 100.0;

  @override
  State<DiffEditor> createState() => _DiffEditorState();
}

class _DiffEditorState extends State<DiffEditor> {
  final ValueNotifier<Offset> _ownScroll = ValueNotifier(Offset.zero);

  /// The original editor's, side by side, kept level with the modified's.
  final ValueNotifier<Offset> _originalScroll = ValueNotifier(Offset.zero);

  ValueNotifier<Offset> get _scroll => widget.scrollPosition ?? _ownScroll;

  /// The split's place as a share of the width the editors have; null for
  /// `splitViewDefaultRatio`.
  double? _ratio;
  double? _dragStartLeft;
  bool _sashHover = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_diffChanged);
    _scroll.addListener(_modifiedScrolled);
    _originalScroll.addListener(_originalScrolled);
  }

  @override
  void didUpdateWidget(DiffEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_diffChanged);
      widget.model.addListener(_diffChanged);
      _shown.clear();
      _shownVersion++;
    }
    if (oldWidget.scrollPosition != widget.scrollPosition) {
      (oldWidget.scrollPosition ?? _ownScroll).removeListener(
        _modifiedScrolled,
      );
      _scroll.addListener(_modifiedScrolled);
    }
  }

  /// The unchanged runs shown again, by their first hidden original line.
  final Set<int> _shown = {};
  int _shownVersion = 0;

  /// The runs of unchanged lines to hide, one-based and inclusive, in the
  /// original and the modified.
  List<({int original, int modified, int count})> _unchanged(
    List<DetailedLineRangeMapping> mappings,
    int originalCount,
    int modifiedCount,
  ) {
    const context = DiffEditor.unchangedContext;
    final runs = <({int original, int modified, int count})>[];
    var original = 1;
    var modified = 1;
    for (var i = 0; i <= mappings.length; i++) {
      final mapping = i < mappings.length ? mappings[i] : null;
      final end = mapping?.original.startLineNumber ?? originalCount + 1;
      final modifiedEnd =
          mapping?.modified.startLineNumber ?? modifiedCount + 1;
      final length = math.min(end - original, modifiedEnd - modified);
      // From the top or to the bottom, no context there; the first line
      // shows all the same (a bar goes under a line).
      final from = original == 1 && modified == 1 ? 1 : context;
      final to = mapping == null ? 0 : context;
      final count = length - from - to;
      final keep = widget.keepVisible;
      if (count >= DiffEditor.unchangedMinimum &&
          !_shown.contains(original + from) &&
          (keep == null ||
              keep < modified + from ||
              keep >= modified + from + count)) {
        runs.add((
          original: original + from,
          modified: modified + from,
          count: count,
        ));
      }
      if (mapping == null) break;
      original = mapping.original.endLineNumberExclusive;
      modified = mapping.modified.endLineNumberExclusive;
    }
    return runs;
  }

  EditorViewZone _unchangedBar(int count, int after, int key) {
    void show() => setState(() {
      _shown.add(key);
      _shownVersion++;
    });
    return EditorViewZone(
      afterLineNumber: after,
      heightInLines: 1,
      interactive: true,
      content: _UnchangedBar(
        label: widget.unchangedLabel?.call(count) ?? '$count unchanged lines',
        colors: widget.colors,
        style: widget.style,
        onTap: show,
      ),
      margin: _UnchangedBar(colors: widget.colors, onTap: show),
    );
  }

  void _diffChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.model.removeListener(_diffChanged);
    _scroll.removeListener(_modifiedScrolled);
    _originalScroll.removeListener(_originalScrolled);
    _ownScroll.dispose();
    _originalScroll.dispose();
    _glyphs?.dispose();
    super.dispose();
  }

  // --- Keeping the sides level ----------------------------------------------

  /// Where the lines are on each side, as last laid out; null before.
  _DiffRows? _rows;

  /// Whether the editors show side by side, as last laid out.
  bool _sideBySide = false;

  /// One side scrolled, the other is being scrolled to follow it.
  bool _syncing = false;

  void _modifiedScrolled() => _sync(fromOriginal: false);
  void _originalScrolled() => _sync(fromOriginal: true);

  /// Scrolls the other side level with the one [fromOriginal] says.
  void _sync({required bool fromOriginal}) {
    final rows = _rows;
    if (rows == null || !_sideBySide || _syncing) return;
    final from = fromOriginal ? _originalScroll : _scroll;
    final to = fromOriginal ? _scroll : _originalScroll;
    final top = rows.levelTop(from.value.dy, fromOriginal: fromOriginal);
    _syncing = true;
    try {
      to.value = Offset(from.value.dx, top);
    } finally {
      _syncing = false;
    }
  }

  // --- The diff, as each editor shows it -------------------------------------

  // What was computed for the last diff, snapshots and mode.
  Object? _diffKey;
  ({
    List<DiffZone> zones,
    List<EditorDecoration> originalDecorations,
    List<EditorDecoration> modifiedDecorations,
  })?
  _diff;

  // And the editors' sides for it, with the original's tokens: these come
  // in as they are tokenized, and only the deleted code paints them.
  Object? _key;
  ({DiffEditorSide original, DiffEditorSide modified})? _sides;

  // Where the lines are on each side, past the zones and the hidden lines.
  _ZoneTops _originalTops = _ZoneTops(const []);
  _ZoneTops _modifiedTops = _ZoneTops(const []);

  ({DiffEditorSide original, DiffEditorSide modified}) _sidesFor(
    bool sideBySide,
    double lineHeight,
    TextScaler scaler,
  ) {
    final model = widget.model;
    final original = model.originalSnapshot;
    final modified = model.modified.snapshot;
    final mappings = model.mappings;
    final diffKey = (
      mappings,
      original,
      modified,
      sideBySide,
      widget.colors,
      widget.highlight,
    );
    if (_diff == null || diffKey != _diffKey) {
      _diffKey = diffKey;
      if (original != null && mappings != null) {
        final decorations = computeDiffDecorations(
          mappings,
          original,
          modified,
          widget.colors,
          highlight: widget.highlight,
          gutterBars: !sideBySide,
        );
        _diff = (
          zones: sideBySide ? const [] : computeDiffZones(mappings),
          originalDecorations: decorations.original,
          modifiedDecorations: decorations.modified,
        );
      } else {
        _diff = (
          zones: const [],
          originalDecorations: const [],
          modifiedDecorations: const [],
        );
      }
    }
    final diff = _diff!;
    final key = (
      diff,
      lineHeight,
      scaler,
      widget.originalStyledLines,
      widget.style,
      widget.hideUnchanged,
      widget.unchangedLabel != null,
      widget.keepVisible,
      _shownVersion,
    );
    if (_sides case final sides? when key == _key) return sides;
    _key = key;
    var originalZones = const <EditorViewZone>[];
    var modifiedZones = const <EditorViewZone>[];
    HiddenLineRanges? originalHidden;
    HiddenLineRanges? modifiedHidden;
    if (original != null) {
      modifiedZones = [
        for (final zone in diff.zones)
          _deletedCodeZone(
            zone,
            original,
            colors: widget.colors,
            style: widget.style,
            textScaler: scaler,
            styledLines: widget.originalStyledLines,
            highlight: widget.highlight,
          ),
      ];
      if (widget.hideUnchanged && mappings != null) {
        final runs = _unchanged(
          mappings,
          original.lineCount,
          (model.mappedSnapshot ?? modified).lineCount,
        );
        if (runs.isNotEmpty) {
          originalHidden = HiddenLineRanges([
            for (final run in runs)
              (run.original, run.original + run.count - 1),
          ]);
          modifiedHidden = HiddenLineRanges([
            for (final run in runs)
              (run.modified, run.modified + run.count - 1),
          ]);
          originalZones = [
            for (final run in runs)
              _unchangedBar(run.count, run.original - 1, run.original),
          ];
          modifiedZones = [
            ...modifiedZones,
            for (final run in runs)
              _unchangedBar(run.count, run.modified - 1, run.original),
          ];
        }
      }
    }
    _originalTops = _ZoneTops(const [], originalHidden);
    _modifiedTops = _ZoneTops([
      for (final zone in diff.zones) (zone.afterLineNumber, zone.heightInLines),
    ], modifiedHidden);
    return _sides = (
      original: DiffEditorSide(
        zones: originalZones,
        decorations: diff.originalDecorations,
        scrollPosition: _originalScroll,
        sideBySide: sideBySide,
        hiddenLines: originalHidden,
        lineNumbers: !sideBySide,
      ),
      modified: DiffEditorSide(
        zones: modifiedZones,
        decorations: diff.modifiedDecorations,
        scrollPosition: _scroll,
        sideBySide: sideBySide,
        hiddenLines: modifiedHidden,
        lineNumbersMinChars: sideBySide
            ? _minNumberChars
            : EditorViewGeometry.lineNumbersMinChars,
      ),
    );
  }

  /// [_DiffRows] for what is laid out, the same while it is.
  _DiffRows _rowsFor(double lineHeight, double height) {
    final model = widget.model;
    final rows = _rows;
    final mappings = model.mappings ?? const [];
    final originalLines = model.originalSnapshot?.lineCount ?? 1;
    final modifiedLines = model.modified.snapshot.lineCount;
    if (rows != null &&
        identical(rows.original, _originalTops) &&
        identical(rows.modified, _modifiedTops) &&
        identical(rows.mappings, mappings) &&
        rows.originalLines == originalLines &&
        rows.modifiedLines == modifiedLines &&
        rows.lineHeight == lineHeight &&
        rows.height == height) {
      return rows;
    }
    return _DiffRows(
      original: _originalTops,
      modified: _modifiedTops,
      mappings: mappings,
      originalLines: originalLines,
      modifiedLines: modifiedLines,
      lineHeight: lineHeight,
      height: height,
    );
  }

  // The line numbers' digits at the split.
  EditorGutterGlyphs? _glyphs;
  Object? _glyphsKey;

  EditorGutterGlyphs _glyphsFor(TextScaler scaler) {
    final theme = widget.theme;
    final key = (
      widget.style,
      scaler,
      theme.lineNumberForeground,
      theme.activeLineNumberForeground,
    );
    if (_glyphs case final glyphs? when key == _glyphsKey) return glyphs;
    _glyphs?.dispose();
    _glyphsKey = key;
    return _glyphs = EditorGutterGlyphs(
      style: widget.style,
      textScaler: scaler,
      foreground: theme.lineNumberForeground,
      activeForeground: theme.activeLineNumberForeground,
      placeholderForeground: theme.lineNumberForeground,
    );
  }

  /// The original's line numbers at the split: as many digits as its last
  /// line's, and room either side.
  static double _numbersWidth(EditorGutterGlyphs glyphs, int lineCount) =>
      _SplitPainter.numbersLeftPadding +
      (math.max(_minNumberChars, '$lineCount'.length) * glyphs.digitWidth)
          .roundToDouble() +
      _SplitPainter.numbersRightPadding;

  /// The fewest digits the line numbers by the split have room for.
  static const _minNumberChars = 2;

  double _splitLeft(double available) {
    final mid = (0.5 * available).floorToDouble();
    const min = DiffEditor.minimumEditorWidth;
    if (available <= min * 2) return mid;
    final left = ((_ratio ?? 0.5) * available).floorToDouble();
    return left.clamp(min, available - min);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final sideBySide =
            widget.sideBySide ?? width > DiffEditor.inlineBreakpoint;
        final glyphs = _glyphsFor(scaler);
        final lineHeight = glyphs.lineHeight;
        final sides = _sidesFor(sideBySide, lineHeight, scaler);
        final content = math.max(0.0, width - DiffEditor.overviewWidth);
        final originalLines = widget.model.originalSnapshot?.lineCount ?? 1;
        final numbers = sideBySide ? _numbersWidth(glyphs, originalLines) : 0.0;
        final split = numbers + DiffEditor.bandWidth;
        final splitLeft = sideBySide
            ? _splitLeft(math.max(0.0, content - split))
            : 0.0;
        final bandLeft = splitLeft + numbers;
        final modifiedLeft = sideBySide ? splitLeft + split : 0.0;
        final rows = _rowsFor(lineHeight, height);
        final placed = _rows;
        _rows = rows;
        if (sideBySide && !_sideBySide) {
          // The original editor is about to be made: scrolled level with the
          // modified from the first.
          _sideBySide = true;
          _sync(fromOriginal: false);
        } else if (sideBySide && !identical(rows, placed)) {
          // Laid out anew: level again, once the editors are.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _sync(fromOriginal: false);
          });
        }
        _sideBySide = sideBySide;
        // Not compared yet, unchanged lines to hide: not the whole text
        // first, then hidden (a long text is compared on another isolate).
        final waiting = widget.hideUnchanged && widget.model.mappings == null;
        final layout = (
          sideBySide: sideBySide,
          splitLeft: splitLeft,
          bandLeft: bandLeft,
          modifiedLeft: modifiedLeft,
          contentWidth: content,
          originalTop: sideBySide
              ? (int line) =>
                    rows.original.top(line.clamp(1, rows.originalLines + 1)) *
                        lineHeight -
                    _originalScroll.value.dy
              : null,
        );
        return Opacity(
          opacity: waiting ? 0 : 1,
          child: Stack(
            children: [
              if (sideBySide)
                Positioned(
                  left: 0,
                  top: 0,
                  width: splitLeft,
                  height: height,
                  child: widget.original(context, sides.original),
                ),
              Positioned(
                left: modifiedLeft,
                top: 0,
                width: math.max(0, content - modifiedLeft),
                height: height,
                child: widget.modified(context, sides.modified),
              ),
              if (sideBySide) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SplitPainter(
                        rows: rows,
                        originalScroll: _originalScroll,
                        modifiedScroll: _scroll,
                        splitLeft: splitLeft,
                        bandLeft: bandLeft,
                        modifiedLeft: modifiedLeft,
                        contentWidth: content,
                        glyphs: glyphs,
                        colors: widget.colors,
                        background: widget.background,
                        edge: _sashHover || _dragStartLeft != null
                            ? widget.sashHover ?? widget.border
                            : widget.border,
                      ),
                    ),
                  ),
                ),
                _sash(bandLeft, splitLeft, content - split, height),
              ],
              Positioned(
                left: content,
                top: 0,
                width: DiffEditor.overviewWidth,
                height: height,
                child: _DiffOverview(
                  scroll: _scroll,
                  rows: rows,
                  inline: !sideBySide,
                  colors: widget.colors,
                  theme: widget.theme,
                  background: widget.background,
                ),
              ),
              if (widget.overlay case final overlay?)
                Positioned.fill(
                  child: sideBySide
                      // The arrows by the original's lines follow it, which
                      // scrolls on its own over deleted lines.
                      ? ListenableBuilder(
                          listenable: _originalScroll,
                          builder: (context, _) => overlay(context, layout),
                        )
                      : overlay(context, layout),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The band's width of the split, which drags it.
  Widget _sash(double bandLeft, double left, double available, double height) {
    return Positioned(
      left: bandLeft,
      top: 0,
      width: DiffEditor.bandWidth,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _sashHover = true),
        onExit: (_) => setState(() => _sashHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragStartLeft = left),
          onHorizontalDragUpdate: (details) {
            final start = _dragStartLeft;
            if (start == null || available <= 0) return;
            _dragStartLeft = start + details.delta.dx;
            setState(() => _ratio = _dragStartLeft! / available);
          },
          onHorizontalDragEnd: (_) => setState(() => _dragStartLeft = null),
          onDoubleTap: () => setState(() => _ratio = null),
        ),
      ),
    );
  }
}

/// What one editor shows of its text's changes against [model]'s original,
/// with no diff editor around it (an agent's change in the editor): the
/// original's deleted code in zones above the changes, its changed lines
/// decorated; none while the diff is not known.
({List<EditorViewZone> zones, List<EditorDecoration> decorations})
inlineDiffParts(
  DiffEditorModel model, {
  required DiffEditorColors colors,
  required TextStyle style,
  required TextScaler textScaler,
  Map<int, List<TextSpan>>? originalStyledLines,
}) {
  final original = model.originalSnapshot;
  final mappings = model.mappings;
  if (original == null || mappings == null) {
    return (zones: const [], decorations: const []);
  }
  return (
    zones: [
      for (final zone in computeDiffZones(mappings))
        _deletedCodeZone(
          zone,
          original,
          colors: colors,
          style: style,
          textScaler: textScaler,
          styledLines: originalStyledLines,
        ),
    ],
    decorations: computeDiffDecorations(
      mappings,
      original,
      model.modified.snapshot,
      colors,
      gutterBars: true,
    ).modified,
  );
}

/// The unscrolled tops of a side's lines in lines, past the zones above
/// them, less the [hidden] lines above them (each run with its one-line
/// bar).
class _ZoneTops {
  _ZoneTops(List<(int, double)> zones, [this.hidden]) {
    final sorted = [
      ...zones,
      if (hidden case final hidden?)
        for (final (start, end) in hidden.ranges)
          // The bar, less the lines it stands for.
          (start - 1, 1.0 - (end - start + 1)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    _after = [for (final zone in sorted) zone.$1];
    _sums = List.filled(sorted.length + 1, 0.0);
    for (var i = 0; i < sorted.length; i++) {
      _sums[i + 1] = _sums[i] + sorted[i].$2;
    }
  }

  final HiddenLineRanges? hidden;
  late final List<int> _after;
  late final List<double> _sums;

  /// [line]'s, past the zones after the lines before it.
  double top(int line) {
    var low = 0;
    var high = _after.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_after[mid] < line) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return line - 1.0 + _sums[low];
  }

  /// [line], or past the hidden run it is in.
  int shown(int line) => switch (hidden?.rangeContaining(line)) {
    (_, final end) => end + 1,
    null => line,
  };

  /// The first line shown whose bottom is below [y], of [lineCount] (one
  /// past them, below the last).
  int lineAt(double y, int lineCount) {
    var low = 1;
    var high = lineCount + 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (top(shown(mid)) + 1 <= y) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return math.min(shown(low), lineCount + 1);
  }
}

/// Where the lines of a diff's two sides are, laid out [height] high in
/// rows [lineHeight] high, and how one side is scrolled level with the
/// other.
class _DiffRows {
  _DiffRows({
    required this.original,
    required this.modified,
    required this.mappings,
    required this.originalLines,
    required this.modifiedLines,
    required this.lineHeight,
    required this.height,
  });

  final _ZoneTops original;
  final _ZoneTops modified;
  final List<LineRangeMapping> mappings;
  final int originalLines;
  final int modifiedLines;
  final double lineHeight;
  final double height;

  /// The sides' tops, in lines, where their changes start and end: between
  /// two, a side's lines go with the other's in proportion.
  late final List<double> _originalStops = _stops(true);
  late final List<double> _modifiedStops = _stops(false);

  List<double> _stops(bool originalSide) {
    final tops = originalSide ? original : modified;
    final lines = originalSide ? originalLines : modifiedLines;
    final stops = <double>[0];
    void add(int line) =>
        stops.add(math.max(stops.last, tops.top(line.clamp(1, lines + 1))));
    for (final mapping in mappings) {
      final range = originalSide ? mapping.original : mapping.modified;
      add(range.startLineNumber);
      add(range.endLineNumberExclusive);
    }
    add(lines + 1);
    return stops;
  }

  /// [y] of one side, in lines, as the other's: proportionally between
  /// the stops, past the last as far as past it.
  double _level(double y, {required bool fromOriginal}) {
    final from = fromOriginal ? _originalStops : _modifiedStops;
    final to = fromOriginal ? _modifiedStops : _originalStops;
    if (y >= from.last) return to.last + y - from.last;
    var low = 0;
    var high = from.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (from[mid] <= y) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    // A stop at the same place as the next stands for nothing.
    final i = math.min(low, from.length - 2);
    final span = from[i + 1] - from[i];
    if (span <= 0) return to[i + 1];
    return to[i] + (y - from[i]) / span * (to[i + 1] - to[i]);
  }

  double contentHeight({required bool originalSide}) =>
      (originalSide ? original : modified).top(
        (originalSide ? originalLines : modifiedLines) + 1,
      ) *
      lineHeight;

  /// As far as the side scrolls (`scrollBeyondLastLine`).
  double scrollHeight({required bool originalSide}) => math.max(
    contentHeight(originalSide: originalSide) +
        math.max(0.0, height - lineHeight),
    height,
  );

  /// The other side's top for one side's [top]: at a point going from
  /// the view's top to its bottom as the side is scrolled from its top to
  /// where its last line is at the bottom, the two show the same place.
  double levelTop(double top, {required bool fromOriginal}) {
    final range = contentHeight(originalSide: fromOriginal) - height;
    final share = range <= 0 ? 0.0 : (top / range).clamp(0.0, 1.0);
    final anchor = top + share * height;
    final level = _level(anchor / lineHeight, fromOriginal: fromOriginal);
    final max = math.max(
      0.0,
      scrollHeight(originalSide: !fromOriginal) - height,
    );
    return (level * lineHeight - share * height).clamp(0.0, max);
  }
}

/// The split, side by side: its background, the original's line numbers
/// (on its changed lines' margin color), and across it a band from each
/// change's original lines to its modified ones, colored as the two
/// sides' margins; where a side has no lines, a line across it there. The
/// bars of the hidden unchanged lines are joined across it as well.
class _SplitPainter extends CustomPainter {
  _SplitPainter({
    required this.rows,
    required this.originalScroll,
    required this.modifiedScroll,
    required this.splitLeft,
    required this.bandLeft,
    required this.modifiedLeft,
    required this.contentWidth,
    required this.glyphs,
    required this.colors,
    required this.background,
    required this.edge,
  }) : super(repaint: Listenable.merge([originalScroll, modifiedScroll]));

  final _DiffRows rows;
  final ValueNotifier<Offset> originalScroll;
  final ValueNotifier<Offset> modifiedScroll;
  final double splitLeft;
  final double bandLeft;
  final double modifiedLeft;
  final double contentWidth;
  final EditorGutterGlyphs glyphs;
  final DiffEditorColors colors;
  final Color? background;
  final Color? edge;

  static const numbersLeftPadding = 10.0;
  static const numbersRightPadding = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height;
    final lineHeight = rows.lineHeight;
    final originalTop = originalScroll.value.dy;
    final modifiedTop = modifiedScroll.value.dy;
    double left(int line) =>
        rows.original.top(line.clamp(1, rows.originalLines + 1)) * lineHeight -
        originalTop;
    double right(int line) =>
        rows.modified.top(line.clamp(1, rows.modifiedLines + 1)) * lineHeight -
        modifiedTop;
    final paint = Paint();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, contentWidth, height));
    if (background case final color?) {
      canvas.drawRect(
        Rect.fromLTRB(splitLeft, 0, modifiedLeft, height),
        paint..color = color,
      );
    }

    // A band from [top]..[bottom] at the band's left to [rightTop]..
    // [rightBottom] at its right, from the numbers' left on.
    void band(
      double top,
      double bottom,
      double rightTop,
      double rightBottom,
      Color leftColor,
      Color rightColor, {
      Color? leftEdge,
      Color? rightEdge,
    }) {
      if (math.max(bottom, rightBottom) < 0 ||
          math.min(top, rightTop) > height) {
        return;
      }
      final x0 = bandLeft;
      final x1 = modifiedLeft;
      final mid = (x0 + x1) / 2;
      canvas.drawRect(
        Rect.fromLTRB(splitLeft, top, bandLeft, bottom),
        paint..color = leftColor,
      );
      final path = Path()
        ..moveTo(x0, top)
        ..cubicTo(mid, top, mid, rightTop, x1, rightTop)
        ..lineTo(x1, rightBottom)
        ..cubicTo(mid, rightBottom, mid, bottom, x0, bottom)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..shader = LinearGradient(colors: [leftColor, rightColor])
              .createShader(Rect.fromLTRB(x0, 0, x1, 1)),
      );
      if (leftEdge == null || rightEdge == null) return;
      // Its edges drawn, the band's shape clear where it is faint.
      canvas.drawPath(
        Path()
          ..moveTo(x0, top)
          ..cubicTo(mid, top, mid, rightTop, x1, rightTop)
          ..moveTo(x0, bottom)
          ..cubicTo(mid, bottom, mid, rightBottom, x1, rightBottom),
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(colors: [leftEdge, rightEdge])
              .createShader(Rect.fromLTRB(x0, 0, x1, 1)),
      );
    }

    if (rows.original.hidden case final hidden?) {
      if (colors.unchangedBackground case final color?) {
        final modifiedHidden = rows.modified.hidden;
        final runs = hidden.ranges.toList();
        final modifiedRuns = modifiedHidden?.ranges.toList() ?? const [];
        for (var i = 0; i < runs.length && i < modifiedRuns.length; i++) {
          // The bar is the line over the first line past the run.
          final bottom = left(runs[i].$2 + 1);
          final rightBottom = right(modifiedRuns[i].$2 + 1);
          band(
            bottom - lineHeight,
            bottom,
            rightBottom - lineHeight,
            rightBottom,
            color,
            color,
          );
        }
      }
    }

    final mappings = rows.mappings;
    for (final mapping in mappings) {
      final o = mapping.original;
      final m = mapping.modified;
      final top = left(o.startLineNumber);
      final bottom = left(o.endLineNumberExclusive);
      final rightTop = right(m.startLineNumber);
      final rightBottom = right(m.endLineNumberExclusive);
      final removed = colors.removedGutter ?? colors.removedLine;
      final inserted = colors.insertedGutter ?? colors.insertedLine;
      final leftColor = o.isEmpty ? inserted : removed;
      final rightColor = m.isEmpty ? removed : inserted;
      if (leftColor == null || rightColor == null) continue;
      // The edges a deeper shade of the blocks' own color, not the bars'
      // louder one: of a piece with what they go round.
      Color edge(Color fill) =>
          fill.withValues(alpha: math.min(1.0, fill.a * 2.6));
      final leftEdge = edge(leftColor);
      final rightEdge = edge(rightColor);
      band(
        top,
        bottom,
        rightTop,
        rightBottom,
        leftColor,
        rightColor,
        leftEdge: leftEdge,
        rightEdge: rightEdge,
      );
      // The band's edges go on across each side, round the change's lines
      // there (one line where a side has none of them).
      void across(double y, double from, double to, Color? color) {
        if (color == null || y < -1 || y > height + 1) return;
        canvas.drawRect(
          Rect.fromLTRB(from, y - 0.5, to, y + 0.5),
          paint..color = color,
        );
      }

      across(top, 0, bandLeft, leftEdge);
      if (!o.isEmpty) across(bottom, 0, bandLeft, leftEdge);
      across(rightTop, modifiedLeft, contentWidth, rightEdge);
      if (!m.isEmpty) {
        across(rightBottom, modifiedLeft, contentWidth, rightEdge);
      }
    }

    // The original's line numbers, over their lines' colors.
    canvas.clipRect(Rect.fromLTRB(splitLeft, 0, bandLeft, height));
    final numbersRight = bandLeft - numbersRightPadding;
    var line = rows.original.lineAt(
      originalTop / lineHeight,
      rows.originalLines,
    );
    while (line <= rows.originalLines) {
      final top = left(line);
      if (top >= height) break;
      glyphs.paintNumber(
        canvas,
        line,
        numbersRight,
        top + (lineHeight - glyphs.lineHeight) / 2,
      );
      line = rows.original.shown(line + 1);
    }
    canvas.restore();

    if (edge case final color?) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(splitLeft, 0, 1, height), paint);
      canvas.drawRect(Rect.fromLTWH(modifiedLeft - 1, 0, 1, height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplitPainter old) =>
      !identical(old.rows, rows) ||
      old.originalScroll != originalScroll ||
      old.modifiedScroll != modifiedScroll ||
      old.splitLeft != splitLeft ||
      old.bandLeft != bandLeft ||
      old.modifiedLeft != modifiedLeft ||
      old.contentWidth != contentWidth ||
      old.glyphs != glyphs ||
      old.colors != colors ||
      old.background != background ||
      old.edge != edge;
}

/// The overview, at the right: a mark by each change of the modified side
/// as its lines are laid out (inline, its deleted code's too), and the
/// slider over it; a press scrolls the modified editor as a scrollbar's
/// would.
class _DiffOverview extends StatefulWidget {
  const _DiffOverview({
    required this.scroll,
    required this.rows,
    required this.inline,
    required this.colors,
    required this.theme,
    required this.background,
  });

  final ValueNotifier<Offset> scroll;
  final _DiffRows rows;
  final bool inline;
  final DiffEditorColors colors;
  final EditorViewTheme theme;
  final Color? background;

  @override
  State<_DiffOverview> createState() => _DiffOverviewState();
}

class _DiffOverviewState extends State<_DiffOverview>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _dragging = false;
  double _dragOffset = 0;

  /// A mouse wheel's notches gliding the editors, stopped as anything else
  /// scrolls them.
  WheelGlider? _wheel;
  bool _gliding = false;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(_DiffOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll.removeListener(_scrolled);
      widget.scroll.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_scrolled);
    _wheel?.dispose();
    super.dispose();
  }

  void _scrolled() {
    if (!_gliding) _wheel?.stop();
  }

  double get _scrollHeight => widget.rows.scrollHeight(originalSide: false);

  ScrollbarSlider _slider(double top) => ScrollbarSlider.compute(
    trackSize: widget.rows.height,
    visibleSize: widget.rows.height,
    scrollSize: _scrollHeight,
    scrollPosition: top,
  );

  double _maxTop() => math.max(0.0, _scrollHeight - widget.rows.height);

  void _scrollTo(double top) {
    final value = widget.scroll.value;
    widget.scroll.value = Offset(value.dx, top.clamp(0.0, _maxTop()));
  }

  void _down(PointerDownEvent event) {
    final slider = _slider(widget.scroll.value.dy);
    if (!slider.needed) return;
    final y = event.localPosition.dy;
    if (y < slider.position || y >= slider.position + slider.size) {
      // `scrollbar.scrollByPage` is off: the slider centers on the press.
      _scrollTo((y - slider.size / 2) / slider.ratio);
      _dragOffset = slider.size / 2;
    } else {
      _dragOffset = y - slider.position;
    }
    setState(() => _dragging = true);
  }

  void _move(PointerMoveEvent event) {
    if (!_dragging) return;
    final slider = _slider(widget.scroll.value.dy);
    if (!slider.needed || slider.ratio <= 0) return;
    _scrollTo((event.localPosition.dy - _dragOffset) / slider.ratio);
  }

  void _up(PointerEvent _) {
    if (_dragging) setState(() => _dragging = false);
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (event.kind != PointerDeviceKind.mouse) {
      _scrollTo(widget.scroll.value.dy + dy);
      return;
    }
    // Over a few frames, as the editors take a wheel's notch.
    (_wheel ??= WheelGlider(vsync: this, move: _glide)).add(
      Offset(0, dy),
      at: widget.scroll.value,
      max: Offset(0, _maxTop()),
      frame: WheelGlide.frameOf(context),
    );
  }

  ({bool x, bool y}) _glide(Offset by) {
    final top = widget.scroll.value.dy + by.dy;
    _gliding = true;
    try {
      _scrollTo(top);
    } finally {
      _gliding = false;
    }
    return (x: true, y: widget.scroll.value.dy == top);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerSignal: _signal,
      // The changes in a layer of their own: a scroll repaints the slider
      // only.
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: _DiffOverviewPainter(
                rows: widget.rows,
                inline: widget.inline,
                colors: widget.colors,
                background: widget.background,
              ),
            ),
          ),
          CustomPaint(
            painter: _DiffOverviewSliderPainter(
              scroll: widget.scroll,
              viewportHeight: widget.rows.height,
              scrollHeight: _scrollHeight,
              color: _dragging
                  ? widget.theme.scrollbarSliderActiveBackground
                  : _hover
                  ? widget.theme.scrollbarSliderHoverBackground
                  : widget.theme.scrollbarSliderBackground,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The overview's marks: lines put in, taken out (side by side, a tick
/// where they were), or both, each in its color.
class _DiffOverviewPainter extends CustomPainter {
  _DiffOverviewPainter({
    required this.rows,
    required this.inline,
    required this.colors,
    required this.background,
  });

  final _DiffRows rows;
  final bool inline;
  final DiffEditorColors colors;
  final Color? background;

  /// The marks' inset from the overview's sides.
  static const _inset = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (background case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    final scrollHeight = rows.scrollHeight(originalSide: false);
    final scale = scrollHeight <= 0 ? 0.0 : size.height / scrollHeight;
    final lineHeight = rows.lineHeight;
    final tops = rows.modified;
    final paint = Paint()..isAntiAlias = true;
    for (final mapping in rows.mappings) {
      final o = mapping.original;
      final m = mapping.modified;
      final color = switch ((o.isEmpty, m.isEmpty)) {
        (true, _) => colors.overviewInserted,
        (_, true) => colors.overviewRemoved,
        _ => colors.overviewModified ?? colors.overviewInserted,
      };
      if (color == null) continue;
      final start = tops.top(
        m.startLineNumber.clamp(1, rows.modifiedLines + 1),
      );
      final end = tops.top(
        m.endLineNumberExclusive.clamp(1, rows.modifiedLines + 1),
      );
      // Inline, the deleted code is above the lines put in.
      final first = inline ? start - o.length : start;
      final top = first * lineHeight * scale;
      final bottom = end * lineHeight * scale;
      final height = math.max(bottom - top, 3.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            _inset,
            bottom - top < 3 ? (top + bottom - height) / 2 : top,
            size.width - 2 * _inset,
            height,
          ),
          const Radius.circular(1.5),
        ),
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiffOverviewPainter old) =>
      !identical(old.rows, rows) ||
      old.inline != inline ||
      old.colors != colors ||
      old.background != background;
}

/// The overview's slider, where the modified editor is scrolled to.
class _DiffOverviewSliderPainter extends CustomPainter {
  _DiffOverviewSliderPainter({
    required this.scroll,
    required this.viewportHeight,
    required this.scrollHeight,
    required this.color,
  }) : super(repaint: scroll);

  final ValueNotifier<Offset> scroll;
  final double viewportHeight;
  final double scrollHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final slider = ScrollbarSlider.compute(
      trackSize: viewportHeight,
      visibleSize: viewportHeight,
      scrollSize: scrollHeight,
      scrollPosition: scroll.value.dy,
    );
    if (!slider.needed) return;
    canvas.drawRect(
      Rect.fromLTWH(0, slider.position, size.width, slider.size),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _DiffOverviewSliderPainter old) =>
      !identical(old.scroll, scroll) ||
      old.viewportHeight != viewportHeight ||
      old.scrollHeight != scrollHeight ||
      old.color != color;
}

/// A [DiffZone]: [original]'s deleted lines, numbered as the original
/// numbers them, on the removed margin with its bar at the edge; marked
/// as much as [highlight] says, as the inserted lines are.
EditorViewZone _deletedCodeZone(
  DiffZone zone,
  DocumentSnapshot original, {
  required DiffEditorColors colors,
  required TextStyle style,
  required TextScaler textScaler,
  Map<int, List<TextSpan>>? styledLines,
  DiffHighlight highlight = DiffHighlight.characters,
}) => EditorViewZone(
  afterLineNumber: zone.afterLineNumber,
  heightInLines: zone.heightInLines,
  firstLineNumber: zone.deleted.startLineNumber,
  content: CustomPaint(
    painter: _DeletedCodePainter(
      original: original,
      lines: zone.deleted,
      diff: zone.diff,
      styledLines: styledLines,
      style: style,
      textScaler: textScaler,
      lineBackground: highlight == DiffHighlight.none
          ? null
          : colors.removedLine,
      textBackground:
          highlight == DiffHighlight.none || highlight == DiffHighlight.lines
          ? null
          : colors.removedText,
      words: highlight == DiffHighlight.words,
    ),
  ),
  margin: CustomPaint(
    painter: _DeletedCodeMarginPainter(
      background: colors.removedGutter,
      bar: colors.removedBar,
    ),
  ),
);

/// The inline view's deleted code (`renderLines` in a `line-delete` zone):
/// the original's [lines] with their tokens, on the removed line
/// background, the removed text's on the inner changes.
class _DeletedCodePainter extends CustomPainter {
  _DeletedCodePainter({
    required this.original,
    required this.lines,
    required this.diff,
    required this.styledLines,
    required this.style,
    required this.textScaler,
    required this.lineBackground,
    required this.textBackground,
    this.words = false,
  });

  final DocumentSnapshot original;
  final LineRange lines;
  final DetailedLineRangeMapping? diff;
  final Map<int, List<TextSpan>>? styledLines;
  final TextStyle style;
  final TextScaler textScaler;
  final Color? lineBackground;
  final Color? textBackground;

  /// The inner changes grown to the words they are in.
  final bool words;

  @override
  void paint(Canvas canvas, Size size) {
    final count = lines.length;
    if (count <= 0) return;
    final lineHeight = size.height / count;
    if (lineBackground case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    for (var i = 0; i < count; i++) {
      final line = lines.startLineNumber + i;
      if (line > original.lineCount) break;
      final text = original.text.substring(
        original.lineStarts[line - 1],
        original.contentEnds[line - 1],
      );
      final spans = styledLines?[line];
      final matches =
          spans != null &&
          spans.map((span) => span.toPlainText()).join() == text;
      final painter = TextPainter(
        text: TextSpan(
          style: style,
          children: matches ? spans : null,
          text: matches ? null : text,
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        strutStyle: strut,
      )..layout();
      final top = i * lineHeight;
      final background = textBackground;
      if (background != null) {
        for (final change in diff?.innerChanges ?? const <RangeMapping>[]) {
          final range = change.originalRange;
          if (line < range.startLineNumber || line > range.endLineNumber) {
            continue;
          }
          var start = line == range.startLineNumber ? range.startColumn - 1 : 0;
          var end = line == range.endLineNumber
              ? range.endColumn - 1
              : text.length;
          if (words) (start, end) = diffWordRange(text, start, end);
          double x(int column) => painter
              .getOffsetForCaret(
                TextPosition(offset: column.clamp(0, text.length)),
                Rect.zero,
              )
              .dx;
          // Past the line's end, to the zone's (`shouldFillLineOnLineBreak`).
          final right = line < range.endLineNumber ? size.width : x(end);
          if (right <= x(start) && start == end) {
            canvas.drawRect(
              Rect.fromLTWH(x(start) - 1, top, 3, lineHeight),
              Paint()..color = background,
            );
          } else {
            canvas.drawRect(
              Rect.fromLTRB(x(start), top, right, top + lineHeight),
              Paint()..color = background,
            );
          }
        }
      }
      painter.paint(canvas, Offset(0, top + (lineHeight - painter.height) / 2));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _DeletedCodePainter old) =>
      !identical(old.original, original) ||
      old.lines.startLineNumber != lines.startLineNumber ||
      old.lines.endLineNumberExclusive != lines.endLineNumberExclusive ||
      !identical(old.diff, diff) ||
      !identical(old.styledLines, styledLines) ||
      old.style != style ||
      old.textScaler != textScaler ||
      old.lineBackground != lineBackground ||
      old.textBackground != textBackground ||
      old.words != words;
}

/// The deleted code's margin: the removed gutter background, and a bar at
/// its edge as by the inserted lines.
class _DeletedCodeMarginPainter extends CustomPainter {
  _DeletedCodeMarginPainter({required this.background, required this.bar});

  final Color? background;
  final Color? bar;

  @override
  void paint(Canvas canvas, Size size) {
    if (background case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    if (bar case final color?) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, EditorGutterPainter.gutterBarWidth, size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeletedCodeMarginPainter old) =>
      old.background != background || old.bar != bar;
}

/// What stands for a run of hidden unchanged lines: a bar across the
/// editor (its margin too, with no [label]) that shows them again.
class _UnchangedBar extends StatefulWidget {
  const _UnchangedBar({
    required this.colors,
    required this.onTap,
    this.label,
    this.style,
  });

  final String? label;
  final DiffEditorColors colors;
  final TextStyle? style;
  final VoidCallback onTap;

  /// The codicon `unfold`.
  static const _icon = IconData(0xeb73, fontFamily: 'codicon');

  @override
  State<_UnchangedBar> createState() => _UnchangedBarState();
}

class _UnchangedBarState extends State<_UnchangedBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final foreground = colors.unchangedForeground;
    final color = foreground?.withValues(
      alpha: foreground.a * (_hover ? 1 : 0.75),
    );
    final label = widget.label;
    final style = widget.style ?? const TextStyle();
    final size = (style.fontSize ?? 13) - 1;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ColoredBox(
          color: colors.unchangedBackground ?? Colors.transparent,
          child: label == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_UnchangedBar._icon, size: size, color: color),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: style.copyWith(
                            color: color,
                            fontSize: size,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
