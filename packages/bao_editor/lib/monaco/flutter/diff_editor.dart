// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// VS Code's diff editor around two editors, adapted from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/browser/widget/diffEditor/diffEditorWidget.ts (the layout),
// diffEditorOptions.ts and common/config/diffEditor.ts (side by side above
// `renderSideBySideInlineBreakpoint`, else inline),
// components/diffEditorSash.ts, components/diffEditorViewZones/
// diffEditorViewZones.ts and renderLines.ts (the zones and the inline view's
// deleted code), features/overviewRulerFeature.ts and style.css.
//
// Deviations: no gutter menu (stage, revert), lightbulb on deleted code,
// accessible diff viewer or moved code; deleted code is not selectable, and
// draws tabs as the text engine shapes them. Unchanged lines are hidden
// (VS Code's hideUnchangedRegions, [DiffEditor.hideUnchanged]) behind a bar
// that shows them all, not by steps or by the code's outline.
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
import 'viewport_layout.dart' show HiddenLineRanges;
import 'wheel_glide.dart';

/// What the diff gives one of a diff editor's editors.
class DiffEditorSide {
  const DiffEditorSide({
    required this.zones,
    required this.decorations,
    required this.scrollPosition,
    required this.sideBySide,
    this.hiddenLines,
  });

  final List<EditorViewZone> zones;
  final List<EditorDecoration> decorations;

  /// Unchanged lines hidden ([DiffEditor.hideUnchanged]), for
  /// [EditorSurface.hiddenLines]; a bar in [zones] stands for each run.
  final HiddenLineRanges? hiddenLines;

  /// Shared by the two editors, so that they scroll together.
  final ValueNotifier<Offset> scrollPosition;

  /// Whether the two show side by side (the original's glyph margin shows
  /// only then); else the original shows only its line numbers.
  final bool sideBySide;
}

/// Where a diff editor's parts are, for what is laid over them
/// ([DiffEditor.overlay]): whether side by side, the split's (or, inline,
/// the modified editor's left) x, and the width of the editors.
typedef DiffEditorLayout = ({
  bool sideBySide,
  double splitLeft,
  double modifiedLeft,
  double contentWidth,
});

/// Two editors, [original] and [modified], built for what the diff of
/// [model] gives each ([DiffEditorSide]): side by side with a sash between
/// them, or, no wider than [inlineBreakpoint], the modified with the
/// deleted code in it, and the original's line numbers beside; with the
/// diff's overview ruler at the right.
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
    this.originalStyledLines,
    this.border,
    this.sashHover,
    this.sideBySide,
    this.highlight = DiffHighlight.characters,
    this.overlay,
    this.hideUnchanged = false,
    this.unchangedLabel,
    this.keepVisible,
  });

  /// A modified line to show, its unchanged run not hidden.
  final int? keepVisible;

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

  /// The editors' text style (the deleted code's too).
  final TextStyle style;
  final EditorViewTheme theme;
  final DiffEditorColors colors;

  /// The theme is dark (the overview's background).
  final bool dark;

  /// The original's tokens, for the deleted code.
  final Map<int, List<TextSpan>>? originalStyledLines;

  /// `diffEditor.border`, between the two side by side.
  final Color? border;

  /// `sash.hoverBorder`.
  final Color? sashHover;

  /// `renderSideBySideInlineBreakpoint`.
  static const inlineBreakpoint = 900.0;

  /// `OverviewRulerFeature.ENTIRE_DIFF_OVERVIEW_WIDTH`.
  static const overviewWidth = 30.0;

  /// `MINIMUM_EDITOR_WIDTH` of the sash.
  static const minimumEditorWidth = 100.0;

  @override
  State<DiffEditor> createState() => _DiffEditorState();
}

class _DiffEditorState extends State<DiffEditor> {
  final ValueNotifier<Offset> _scroll = ValueNotifier(Offset.zero);

  /// The sash's place as a share of the width; null for
  /// `splitViewDefaultRatio`.
  double? _ratio;
  double? _dragStartLeft;
  bool _sashHover = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_diffChanged);
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

  EditorViewZone _unchangedBar(int count, int after, int key) => EditorViewZone(
    afterLineNumber: after,
    heightInLines: 1,
    interactive: true,
    content: _UnchangedBar(
      label: widget.unchangedLabel?.call(count) ?? '$count unchanged lines',
      colors: widget.colors,
      style: widget.style,
      onTap: () => setState(() {
        _shown.add(key);
        _shownVersion++;
      }),
    ),
  );

  void _diffChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.model.removeListener(_diffChanged);
    _scroll.dispose();
    super.dispose();
  }

  // What was computed for the last diff, snapshots and mode.
  Object? _diffKey;
  ({
    List<DiffZone> originalZones,
    List<DiffZone> modifiedZones,
    List<EditorDecoration> originalDecorations,
    List<EditorDecoration> modifiedDecorations,
  })?
  _diff;

  // And the editors' sides for it, with the original's tokens: these come
  // in as they are tokenized, and only the deleted code paints them.
  Object? _key;
  ({DiffEditorSide original, DiffEditorSide modified})? _sides;

  // Where the lines are on each side for the overview, past the zones and
  // the hidden lines.
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
        final zones = computeDiffZones(
          computeDiffAlignments(
            mappings,
            original,
            innerHunkAlignment: sideBySide,
          ),
          sideBySide: sideBySide,
        );
        final decorations = computeDiffDecorations(
          mappings,
          original,
          modified,
          widget.colors,
          highlight: widget.highlight,
        );
        _diff = (
          originalZones: zones.original,
          modifiedZones: zones.modified,
          originalDecorations: decorations.original,
          modifiedDecorations: decorations.modified,
        );
      } else {
        _diff = (
          originalZones: const [],
          modifiedZones: const [],
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
      originalZones = [
        for (final zone in diff.originalZones) _viewZone(zone, original),
      ];
      modifiedZones = [
        for (final zone in diff.modifiedZones) _viewZone(zone, original),
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
            ...originalZones,
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
    _originalTops = _ZoneTops(diff.originalZones, originalHidden);
    _modifiedTops = _ZoneTops(diff.modifiedZones, modifiedHidden);
    final originalDecorations = diff.originalDecorations;
    final modifiedDecorations = diff.modifiedDecorations;
    return _sides = (
      original: DiffEditorSide(
        zones: originalZones,
        decorations: originalDecorations,
        scrollPosition: _scroll,
        sideBySide: sideBySide,
        hiddenLines: originalHidden,
      ),
      modified: DiffEditorSide(
        zones: modifiedZones,
        decorations: modifiedDecorations,
        scrollPosition: _scroll,
        sideBySide: sideBySide,
        hiddenLines: modifiedHidden,
      ),
    );
  }

  EditorViewZone _viewZone(DiffZone zone, DocumentSnapshot original) =>
      switch (zone.kind) {
        DiffZoneKind.fill => EditorViewZone(
          afterLineNumber: zone.afterLineNumber,
          heightInLines: zone.heightInLines,
          content: CustomPaint(
            painter: _DiagonalFillPainter(widget.colors.diagonalFill),
          ),
          margin: zone.gutterDelete
              ? ColoredBox(
                  color: widget.colors.removedGutter ?? Colors.transparent,
                )
              : null,
        ),
        DiffZoneKind.deletedCode => _deletedCodeZone(
          zone,
          original,
          colors: widget.colors,
          style: widget.style,
          textScaler: MediaQuery.textScalerOf(context),
          styledLines: widget.originalStyledLines,
        ),
      };

  double _lineHeight(TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      strutStyle: StrutStyle.fromTextStyle(
        widget.style,
        forceStrutHeight: true,
      ),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  double _sashLeft(double width) {
    final mid = (0.5 * width).floorToDouble();
    const min = DiffEditor.minimumEditorWidth;
    if (width <= min * 2) return mid;
    final left = ((_ratio ?? 0.5) * width).floorToDouble();
    return left.clamp(min, width - min);
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
        final lineHeight = _lineHeight(scaler);
        final sides = _sidesFor(sideBySide, lineHeight, scaler);
        final content = width - DiffEditor.overviewWidth;
        final double originalWidth;
        final double modifiedLeft;
        if (sideBySide) {
          originalWidth = _sashLeft(content);
          modifiedLeft = originalWidth;
        } else {
          final original = widget.model.originalSnapshot;
          originalWidth = math.max(
            5,
            EditorSurface.lineNumbersRight(
              style: widget.style,
              textScaler: scaler,
              lineCount: original?.lineCount ?? 1,
              glyphMargin: false,
            ),
          );
          modifiedLeft = originalWidth;
        }
        final shadow = widget.theme.scrollbarShadow;
        // Not compared yet, unchanged lines to hide: not the whole text
        // first, then hidden (a long text is compared on another isolate).
        final waiting = widget.hideUnchanged && widget.model.mappings == null;
        return Opacity(
          opacity: waiting ? 0 : 1,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: originalWidth,
                height: height,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: sideBySide ? originalWidth : originalWidth + 200,
                    maxWidth: sideBySide ? originalWidth : originalWidth + 200,
                    child: widget.original(context, sides.original),
                  ),
                ),
              ),
              Positioned(
                left: modifiedLeft,
                top: 0,
                width: math.max(0, content - modifiedLeft),
                height: height,
                child: widget.modified(context, sides.modified),
              ),
              if (sideBySide) ...[
                // `.editor.original` and `.editor.modified`: a 1px border and
                // a shadow each side of the split.
                Positioned(
                  left: originalWidth - 6,
                  top: 0,
                  width: 12,
                  height: height,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SplitShadowPainter(shadow, widget.border),
                    ),
                  ),
                ),
                _sash(originalWidth, content, height),
              ],
              Positioned(
                left: content,
                top: 0,
                width: DiffEditor.overviewWidth,
                height: height,
                child: _overview(sides, lineHeight, height),
              ),
              if (widget.overlay case final overlay?)
                Positioned.fill(
                  child: overlay(context, (
                    sideBySide: sideBySide,
                    splitLeft: originalWidth,
                    modifiedLeft: modifiedLeft,
                    contentWidth: content,
                  )),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sash(double left, double content, double height) {
    const size = 4.0;
    return Positioned(
      left: left - size / 2,
      top: 0,
      width: size,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _sashHover = true),
        onExit: (_) => setState(() => _sashHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragStartLeft = left,
          onHorizontalDragUpdate: (details) {
            final start = _dragStartLeft;
            if (start == null || content <= 0) return;
            _dragStartLeft = start + details.delta.dx;
            setState(() => _ratio = _dragStartLeft! / content);
          },
          onHorizontalDragEnd: (_) => _dragStartLeft = null,
          onDoubleTap: () => setState(() => _ratio = null),
          child: switch (widget.sashHover) {
            final color? when _sashHover || _dragStartLeft != null =>
              ColoredBox(color: color),
            _ => const SizedBox.expand(),
          },
        ),
      ),
    );
  }

  Widget _overview(
    ({DiffEditorSide original, DiffEditorSide modified}) sides,
    double lineHeight,
    double height,
  ) {
    final model = widget.model;
    final original = model.originalSnapshot;
    final modifiedLines = model.modified.snapshot.lineCount;
    final originalLines = original?.lineCount ?? 1;
    double linesOf(List<EditorViewZone> zones, int lines) =>
        lines + zones.fold(0.0, (sum, zone) => sum + zone.heightInLines);
    final hidden = sides.modified.hiddenLines?.hiddenLineCount ?? 0;
    final contentHeight =
        linesOf(sides.modified.zones, modifiedLines - hidden) * lineHeight;
    // `scrollBeyondLastLine`.
    final scrollHeight = math.max(
      contentHeight + math.max(0.0, height - lineHeight),
      height,
    );
    return _DiffOverview(
      scroll: _scroll,
      mappings: model.mappings ?? const [],
      originalTops: _originalTops,
      modifiedTops: _modifiedTops,
      originalLineCount: originalLines,
      lineHeight: lineHeight,
      scrollHeight: scrollHeight,
      viewportHeight: height,
      colors: widget.colors,
      theme: widget.theme,
      dark: widget.dark,
    );
  }
}

/// What one editor shows of its text's changes against [model]'s original,
/// with no diff editor around it (as the inline view's modified editor):
/// the original's deleted code in zones above the changes, its changed
/// lines decorated; none while the diff is not known.
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
  final zones = computeDiffZones(
    computeDiffAlignments(mappings, original, innerHunkAlignment: false),
    sideBySide: false,
  ).modified;
  return (
    zones: [
      for (final zone in zones)
        if (zone.kind == DiffZoneKind.deletedCode)
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
    ).modified,
  );
}

/// `.diffOverview`: the original's changes in the left lane, the
/// modified's in the right, and the viewport over both; a press scrolls the
/// modified editor as its scrollbar would.
class _DiffOverview extends StatefulWidget {
  const _DiffOverview({
    required this.scroll,
    required this.mappings,
    required this.originalTops,
    required this.modifiedTops,
    required this.originalLineCount,
    required this.lineHeight,
    required this.scrollHeight,
    required this.viewportHeight,
    required this.colors,
    required this.theme,
    required this.dark,
  });

  final ValueNotifier<Offset> scroll;
  final List<DetailedLineRangeMapping> mappings;
  final _ZoneTops originalTops;
  final _ZoneTops modifiedTops;
  final int originalLineCount;
  final double lineHeight;
  final double scrollHeight;
  final double viewportHeight;
  final DiffEditorColors colors;
  final EditorViewTheme theme;
  final bool dark;

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

  ScrollbarSlider _slider(double top) => ScrollbarSlider.compute(
    trackSize: widget.viewportHeight,
    visibleSize: widget.viewportHeight,
    scrollSize: widget.scrollHeight,
    scrollPosition: top,
  );

  double _maxTop() =>
      math.max(0.0, widget.scrollHeight - widget.viewportHeight);

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
                mappings: widget.mappings,
                originalTops: widget.originalTops,
                modifiedTops: widget.modifiedTops,
                lineHeight: widget.lineHeight,
                scrollHeight: widget.scrollHeight,
                colors: widget.colors,
                dark: widget.dark,
              ),
            ),
          ),
          CustomPaint(
            painter: _DiffOverviewSliderPainter(
              scroll: widget.scroll,
              viewportHeight: widget.viewportHeight,
              scrollHeight: widget.scrollHeight,
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

/// The unscrolled tops of lines in lines, past the zones above them, less
/// the [hidden] lines above them (each run with its one-line bar).
class _ZoneTops {
  _ZoneTops(List<DiffZone> zones, [HiddenLineRanges? hidden]) {
    final sorted = [
      for (final zone in zones) (zone.afterLineNumber, zone.heightInLines),
      if (hidden != null)
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
}

/// The overview's background and the changes of the two sides.
class _DiffOverviewPainter extends CustomPainter {
  _DiffOverviewPainter({
    required this.mappings,
    required this.originalTops,
    required this.modifiedTops,
    required this.lineHeight,
    required this.scrollHeight,
    required this.colors,
    required this.dark,
  });

  final List<DetailedLineRangeMapping> mappings;
  final _ZoneTops originalTops;
  final _ZoneTops modifiedTops;
  final double lineHeight;
  final double scrollHeight;
  final DiffEditorColors colors;
  final bool dark;

  static const _lane = DiffEditor.overviewWidth / 2;

  @override
  void paint(Canvas canvas, Size size) {
    // `.monaco-diff-editor.vs(-dark) .diffOverview`.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0x03ffffff) : const Color(0x08000000),
    );
    final scale = scrollHeight <= 0 ? 0.0 : size.height / scrollHeight;
    final paint = Paint();
    void zone(LineRange range, _ZoneTops tops, double left, Color? color) {
      if (range.isEmpty || color == null) return;
      final top = tops.top(range.startLineNumber) * lineHeight * scale;
      final bottom =
          tops.top(range.endLineNumberExclusive) * lineHeight * scale;
      canvas.drawRect(
        Rect.fromLTRB(left, top, left + _lane, math.max(bottom, top + 2)),
        paint..color = color,
      );
    }

    for (final mapping in mappings) {
      zone(mapping.original, originalTops, 0, colors.overviewRemoved);
      zone(mapping.modified, modifiedTops, _lane, colors.overviewInserted);
    }
  }

  @override
  bool shouldRepaint(covariant _DiffOverviewPainter old) =>
      !identical(old.mappings, mappings) ||
      !identical(old.originalTops, originalTops) ||
      !identical(old.modifiedTops, modifiedTops) ||
      old.lineHeight != lineHeight ||
      old.scrollHeight != scrollHeight ||
      old.colors != colors ||
      old.dark != dark;
}

/// The overview's slider, where the editors are scrolled to.
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

/// `.diagonal-fill`: `diffEditor.diagonalFill` stripes, 8px apart.
class _DiagonalFillPainter extends CustomPainter {
  _DiagonalFillPainter(this.color);

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color == null || size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.sqrt2
      ..isAntiAlias = true;
    // `linear-gradient(-45deg, ...)` in 8px tiles: two bands an eighth of
    // the gradient wide each, rising to the right.
    for (var x = -size.height; x < size.width + 8; x += 4) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalFillPainter old) => old.color != color;
}

/// A [DiffZoneKind.deletedCode] zone: [original]'s deleted lines, with the
/// removed signs in its margin.
EditorViewZone _deletedCodeZone(
  DiffZone zone,
  DocumentSnapshot original, {
  required DiffEditorColors colors,
  required TextStyle style,
  required TextScaler textScaler,
  Map<int, List<TextSpan>>? styledLines,
}) => EditorViewZone(
  afterLineNumber: zone.afterLineNumber,
  heightInLines: zone.heightInLines,
  content: CustomPaint(
    painter: _DeletedCodePainter(
      original: original,
      lines: zone.deleted!,
      diff: zone.diff,
      styledLines: styledLines,
      style: style,
      textScaler: textScaler,
      lineBackground: colors.removedLine,
      textBackground: colors.removedText,
    ),
  ),
  margin: CustomPaint(
    painter: _DeletedCodeMarginPainter(
      lines: zone.deleted!.length,
      background: colors.removedGutter,
      sign: colors.signForeground,
      style: style,
      textScaler: textScaler,
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
  });

  final DocumentSnapshot original;
  final LineRange lines;
  final DetailedLineRangeMapping? diff;
  final Map<int, List<TextSpan>>? styledLines;
  final TextStyle style;
  final TextScaler textScaler;
  final Color? lineBackground;
  final Color? textBackground;

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
          final start = line == range.startLineNumber
              ? range.startColumn - 1
              : 0;
          final end = line == range.endLineNumber
              ? range.endColumn - 1
              : text.length;
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
      old.textBackground != textBackground;
}

/// `.inline-deleted-margin-view-zone`: the removed gutter background, and a
/// `delete-sign` on each line at the margin's right end.
class _DeletedCodeMarginPainter extends CustomPainter {
  _DeletedCodeMarginPainter({
    required this.lines,
    required this.background,
    required this.sign,
    required this.style,
    required this.textScaler,
  });

  final int lines;
  final Color? background;
  final Color? sign;
  final TextStyle style;
  final TextScaler textScaler;

  /// `lineDecorationsWidth`.
  static const _signWidth = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (background case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    if (lines <= 0) return;
    final lineHeight = size.height / lines;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(diffRemoveIcon.codePoint),
        style: TextStyle(
          fontFamily: diffRemoveIcon.fontFamily,
          fontSize: 11,
          height: 1,
          color: (sign ?? style.color ?? const Color(0xffcccccc)).withValues(
            alpha: 0.7,
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    for (var i = 0; i < lines; i++) {
      painter.paint(
        canvas,
        Offset(
          size.width - _signWidth,
          i * lineHeight + (lineHeight - painter.height) / 2,
        ),
      );
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _DeletedCodeMarginPainter old) =>
      old.lines != lines ||
      old.background != background ||
      old.sign != sign ||
      old.style != style ||
      old.textScaler != textScaler;
}

/// The two editors' `box-shadow`s (`scrollbar.shadow`) and borders
/// (`diffEditor.border`) at the split, drawn [size] wide centered on it.
class _SplitShadowPainter extends CustomPainter {
  _SplitShadowPainter(this.shadow, this.border);

  final Color shadow;
  final Color? border;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.width / 2;
    final transparent = shadow.withValues(alpha: 0);
    // `6px 0 5px -5px`: a shadow a pixel or so wide each side.
    canvas.drawRect(
      Rect.fromLTRB(middle - 3, 0, middle, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            transparent,
            shadow.withValues(alpha: shadow.a * 0.6),
          ],
        ).createShader(Rect.fromLTRB(middle - 3, 0, middle, size.height)),
    );
    canvas.drawRect(
      Rect.fromLTRB(middle, 0, middle + 3, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            shadow.withValues(alpha: shadow.a * 0.6),
            transparent,
          ],
        ).createShader(Rect.fromLTRB(middle, 0, middle + 3, size.height)),
    );
    if (border case final color?) {
      canvas.drawRect(
        Rect.fromLTWH(middle - 1, 0, 1, size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplitShadowPainter old) =>
      old.shadow != shadow || old.border != border;
}

/// What stands for a run of hidden unchanged lines: a bar across the
/// editor that shows them again.
class _UnchangedBar extends StatefulWidget {
  const _UnchangedBar({
    required this.label,
    required this.colors,
    required this.style,
    required this.onTap,
  });

  final String label;
  final DiffEditorColors colors;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  State<_UnchangedBar> createState() => _UnchangedBarState();
}

class _UnchangedBarState extends State<_UnchangedBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.colors.unchangedForeground;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ColoredBox(
          color: widget.colors.unchangedBackground ?? Colors.transparent,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '⋯  ${widget.label}',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: widget.style.copyWith(
                  color: foreground,
                  fontSize: (widget.style.fontSize ?? 13) - 1,
                  height: 1,
                  decoration: _hover ? TextDecoration.underline : null,
                  decorationColor: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
