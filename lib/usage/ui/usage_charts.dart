import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'usage_style.dart';

/// A part of a dashboard: a card with its title, what it says under it,
/// and controls at its right ([trailing]).
class UsageCard extends StatelessWidget {
  const UsageCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.color,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  /// Its background; a shade off the page's by default.
  final Color? color;

  static Color get background =>
      Color.alphaBlend(AppColors.text.withValues(alpha: 0.035), AppColors.code);

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? background,
      borderRadius: BorderRadius.circular(12),
      border: switch (themeColors.get('contrastBorder')) {
        final border? => Border.all(color: border),
        null => null,
      },
    ),
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || trailing != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title case final title?)
                      Text(title, style: UsageText.heading),
                    if (subtitle case final subtitle?) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: UsageText.faint),
                    ],
                  ],
                ),
              ),
              if (trailing case final trailing?) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
        child,
      ],
    ),
  );
}

/// A number a view leads with: what it is, the number, a line under it;
/// a sparkline of it over the time beneath, the last point in the accent.
class UsageStatTile extends StatelessWidget {
  const UsageStatTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.trend,
    this.tone,
    this.icon,
  });

  final String label;
  final String value;
  final String? detail;

  /// Its values over the time (oldest first).
  final List<double>? trend;

  /// A status the number carries (errors): its mark.
  final Color? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
    decoration: BoxDecoration(
      color: UsageCard.background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon case final icon?) ...[
              Icon(icon, size: 12, color: tone ?? AppColors.textFaint),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UsageText.label,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // The value whole, the sparkline in what room is left: narrower,
        // or none.
        LayoutBuilder(
          builder: (context, constraints) {
            final text = TextPainter(
              text: TextSpan(
                text: value,
                style: DefaultTextStyle.of(context).style
                    .merge(UsageText.value),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final room = constraints.maxWidth - text.width - 8;
            text.dispose();
            final sparkline = math.min(60.0, room);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UsageText.value,
                  ),
                ),
                if (trend case final trend?
                    when trend.length > 1 && sparkline >= 28)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: SizedBox(
                      width: sparkline,
                      height: 26,
                      child: CustomPaint(
                        painter: _SparklinePainter(
                          trend,
                          color: tone ?? AppColors.accent,
                        ),
                      ),
                    ),
                  )
                else
                  // As tall as with one.
                  const SizedBox(height: 28),
              ],
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          detail ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UsageText.faint,
        ),
      ],
    ),
  );
}

/// A trend as a small area: its line, and under it the area fading to
/// nothing at the foot.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, {required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.fold(0.0, math.max);
    if (top <= 0) return;
    final step = size.width / (values.length - 1);
    Offset at(int i) => Offset(
      i * step,
      size.height - 1 - (values[i] / top) * (size.height - 4),
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.32),
              color.withValues(alpha: 0.10),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      !listEquals(old.values, values) || old.color != color;
}

/// Tiles in a grid as wide as it is: rows of as many as fit at
/// [minWidth], each as wide.
class UsageStatGrid extends StatelessWidget {
  const UsageStatGrid({
    super.key,
    required this.children,
    this.minWidth = 150,
    this.spacing = 8,
  });

  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fit = math.max(
        1,
        ((constraints.maxWidth + spacing) / (minWidth + spacing)).floor(),
      );
      // As few rows as fit, the tiles spread evenly over them: six in
      // rows of three, not four and two.
      final rows = (children.length / fit).ceil();
      final columns = math.max(1, (children.length / math.max(1, rows)).ceil());
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// The axes' text, painted: the app's font (painted text inherits none),
/// each digit as wide.
TextStyle _axisText(BuildContext context) =>
    DefaultTextStyle.of(context).style
        .merge(UsageText.faint)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// A series of a chart: its name and color.
typedef UsageSeries = ({String label, Color color});

/// The series' names, each its mark before it: a square for bars and
/// areas, a short line for lines.
class UsageLegend extends StatelessWidget {
  const UsageLegend({
    super.key,
    required this.series,
    this.lines = false,
    this.values,
  });

  final List<UsageSeries> series;
  final bool lines;

  /// What each comes to, after its name.
  final List<String>? values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final (i, item) in series.indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: lines ? 12 : 8,
              height: lines ? 2 : 8,
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: BorderRadius.circular(lines ? 1 : 2),
              ),
            ),
            const SizedBox(width: 6),
            Text(item.label, style: UsageText.muted),
            if (values case final values? when i < values.length) ...[
              const SizedBox(width: 5),
              Text(values[i], style: UsageText.tabular),
            ],
          ],
        ),
    ],
  );
}

/// A clean top for an axis over [max], and its ticks' step: 1, 2 or 5
/// times a power of ten.
({double top, double step}) niceScale(double max, {int ticks = 4}) {
  if (max <= 0) return (top: 1, step: 0.25);
  final raw = max / ticks;
  final power = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final fraction = raw / power;
  final nice = fraction <= 1
      ? 1
      : fraction <= 2
      ? 2
      : fraction <= 2.5
      ? 2.5
      : fraction <= 5
      ? 5
      : 10;
  final step = nice * power;
  return (top: (max / step).ceil() * step, step: step);
}

/// The readout of a chart's hover: a heading, then each series' value
/// (the value first, strong; its name after it, keyed by a short line).
class UsageTooltip extends StatelessWidget {
  const UsageTooltip({
    super.key,
    required this.title,
    required this.rows,
    this.footer,
  });

  final String title;
  final List<({Color? color, String value, String label})> rows;

  /// Under the rows, faint: what a click does.
  final String? footer;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 280),
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: themeColors['widget.shadow'],
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: UsageText.faint),
        const SizedBox(height: 4),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (row.color case final color?) ...[
                  Container(
                    width: 10,
                    height: 2,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  row.value,
                  style: UsageText.tabular.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UsageText.muted,
                  ),
                ),
              ],
            ),
          ),
        if (footer case final footer?) ...[
          const SizedBox(height: 6),
          Text(footer, style: UsageText.faint),
        ],
      ],
    ),
  );
}

/// Places [tooltip] beside [x] in a chart [width] wide: right of it,
/// left where it would run off.
class _TooltipLayer extends StatelessWidget {
  const _TooltipLayer({
    required this.x,
    required this.width,
    required this.tooltip,
  });

  final double x;
  final double width;
  final Widget tooltip;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: _TooltipDelegate(x),
    child: IgnorePointer(child: tooltip),
  );
}

class _TooltipDelegate extends SingleChildLayoutDelegate {
  _TooltipDelegate(this.x);

  final double x;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    var left = x + 12;
    if (left + child.width > size.width) left = x - 12 - child.width;
    return Offset(left.clamp(0, math.max(0, size.width - child.width)), 0);
  }

  @override
  bool shouldRelayout(_TooltipDelegate old) => old.x != x;
}

/// A column of a [UsageColumnChart]: its stretch of time, a value a
/// series.
typedef UsageColumn = ({String label, String title, List<double> values});

/// Columns over time, each its series stacked (a 2px gap of the surface
/// between them, the top's end rounded), on a hairline grid; a hover on a
/// column lifts it and reads out each series.
class UsageColumnChart extends StatefulWidget {
  const UsageColumnChart({
    super.key,
    required this.columns,
    required this.series,
    required this.format,
    this.height = 180,
    this.onTapColumn,
    this.selected,
    this.marks = const {},
    this.hint,
    this.selectedHint,
  });

  final List<UsageColumn> columns;
  final List<UsageSeries> series;
  final String Function(double value) format;
  final double height;
  final ValueChanged<int>? onTapColumn;

  /// The column picked, kept lifted.
  final int? selected;

  /// Columns something happened at (a compaction), by index: a mark over
  /// each, what it was in its readout.
  final Map<int, String> marks;

  /// Under a column's readout: what a click on it does; on the one
  /// [selected], [selectedHint] (a click there unpicks it).
  final String? hint;
  final String? selectedHint;

  @override
  State<UsageColumnChart> createState() => _UsageColumnChartState();
}

class _UsageColumnChartState extends State<UsageColumnChart> {
  int? _hovered;

  static const _axisWidth = 44.0;
  static const _labelsHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    final columns = widget.columns;
    final max = columns.fold(
      0.0,
      (top, column) =>
          math.max(top, column.values.fold(0.0, (sum, v) => sum + v)),
    );
    final scale = niceScale(max);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = constraints.maxWidth - _axisWidth;
          final slot = columns.isEmpty ? 0.0 : plotWidth / columns.length;
          int? indexAt(double dx) {
            if (columns.isEmpty) return null;
            final i = ((dx - _axisWidth) / slot).floor();
            return i < 0 || i >= columns.length ? null : i;
          }

          final hovered = _hovered;
          return MouseRegion(
            onHover: (event) {
              final i = indexAt(event.localPosition.dx);
              if (i != _hovered) setState(() => _hovered = i);
            },
            onExit: (_) => setState(() => _hovered = null),
            cursor: widget.onTapColumn == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final i = indexAt(details.localPosition.dx);
                if (i != null) widget.onTapColumn?.call(i);
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ColumnsPainter(
                        columns: columns,
                        colors: [for (final s in widget.series) s.color],
                        scale: scale,
                        hovered: hovered,
                        selected: widget.selected,
                        marks: widget.marks.keys.toSet(),
                        mark: UsagePalette.marker,
                        selection: AppColors.accent,
                        axisWidth: _axisWidth,
                        labelsHeight: _labelsHeight,
                        grid: UsagePalette.grid,
                        surface: UsageCard.background,
                        hover: AppColors.hover,
                        textStyle: _axisText(context),
                        format: widget.format,
                      ),
                    ),
                  ),
                  if (hovered != null && hovered < columns.length)
                    Positioned.fill(
                      child: _TooltipLayer(
                        x: _axisWidth + slot * (hovered + 0.5),
                        width: constraints.maxWidth,
                        tooltip: UsageTooltip(
                          title: columns[hovered].title,
                          footer: hovered == widget.selected
                              ? widget.selectedHint ?? widget.hint
                              : widget.hint,
                          rows: [
                            if (widget.marks[hovered] case final mark?)
                              (
                                color: UsagePalette.marker,
                                value: '◆',
                                label: mark,
                              ),
                            for (final (i, s) in widget.series.indexed)
                              if (i < columns[hovered].values.length &&
                                  columns[hovered].values[i] > 0)
                                (
                                  color: s.color,
                                  value: widget.format(
                                    columns[hovered].values[i],
                                  ),
                                  label: s.label,
                                ),
                            if (widget.series.length > 1)
                              (
                                color: null,
                                value: widget.format(
                                  columns[hovered].values.fold(
                                    0.0,
                                    (sum, v) => sum + v,
                                  ),
                                ),
                                label: '∑',
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ColumnsPainter extends CustomPainter {
  _ColumnsPainter({
    required this.columns,
    required this.colors,
    required this.scale,
    required this.hovered,
    required this.axisWidth,
    required this.labelsHeight,
    required this.grid,
    required this.surface,
    required this.hover,
    required this.textStyle,
    required this.format,
    this.selected,
    this.marks = const {},
    this.mark,
    this.selection,
  });

  final List<UsageColumn> columns;
  final List<Color> colors;
  final ({double top, double step}) scale;
  final int? hovered;
  final int? selected;
  final Set<int> marks;
  final Color? mark;
  final Color? selection;
  final double axisWidth;
  final double labelsHeight;
  final Color grid;
  final Color surface;
  final Color hover;
  final TextStyle textStyle;
  final String Function(double value) format;

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    TextAlign? align,
    double? left,
    double? right,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    // Kept within the plot, off the values' axis.
    if (right != null) dx = math.min(dx, right - painter.width);
    if (left != null) dx = math.max(dx, left);
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
    painter.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      axisWidth,
      marks.isEmpty ? 6 : 12,
      size.width,
      size.height - labelsHeight,
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // The grid: a hairline a tick, the values at the left.
    for (var v = 0.0; v <= scale.top + 1e-9; v += scale.step) {
      final y =
          (plot.bottom - v / scale.top * plot.height).roundToDouble() + 0.5;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(
        canvas,
        format(v),
        Offset(plot.left - 8, y),
        align: TextAlign.right,
      );
    }
    if (columns.isEmpty) return;
    final slot = plot.width / columns.length;
    final width = math.min(24.0, math.max(1.5, slot * 0.64));
    if (selected case final i? when i < columns.length) {
      final band = math.max(slot, 6.0);
      // Square, as the columns' sides are.
      canvas.drawRect(
        Rect.fromLTWH(
          plot.left + slot * (i + 0.5) - band / 2,
          plot.top,
          band,
          plot.height,
        ),
        Paint()..color = (selection ?? hover).withValues(alpha: 0.16),
      );
    }
    if (hovered case final i? when i != selected) {
      canvas.drawRect(
        Rect.fromLTWH(plot.left + slot * i, plot.top, slot, plot.height),
        Paint()..color = hover,
      );
    }
    final gap = width >= 6 ? 2.0 : 0.0;
    for (final (i, column) in columns.indexed) {
      final x = plot.left + slot * i + (slot - width) / 2;
      var y = plot.bottom;
      final shown = [
        for (final (s, value) in column.values.indexed)
          if (value > 0) (s, value),
      ];
      for (final (n, (s, value)) in shown.indexed) {
        final h = value / scale.top * plot.height;
        final top = n == shown.length - 1;
        final rect = Rect.fromLTRB(x, y - h, x + width, y - (n > 0 ? gap : 0));
        if (rect.height > 0) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: Radius.circular(top ? math.min(4, width / 2) : 0),
              topRight: Radius.circular(top ? math.min(4, width / 2) : 0),
            ),
            Paint()
              ..color = colors[s % colors.length].withValues(
                alpha: hovered == null || hovered == i || selected == i
                    ? 1
                    : 0.55,
              ),
          );
        }
        y -= h;
      }
      // Something happened here: a diamond over it, at the plot's top.
      if (marks.contains(i)) {
        final cx = x + width / 2;
        final top = plot.top - 7;
        canvas.drawPath(
          Path()
            ..moveTo(cx, top - 4)
            ..lineTo(cx + 4, top)
            ..lineTo(cx, top + 4)
            ..lineTo(cx - 4, top)
            ..close(),
          Paint()..color = mark ?? hover,
        );
      }
    }
    // The time under the columns: as many labels as fit.
    final every = math.max(1, (64 / slot).ceil());
    for (var i = 0; i < columns.length; i += every) {
      _text(
        canvas,
        columns[i].label,
        Offset(plot.left + slot * (i + 0.5), size.height - labelsHeight / 2),
        align: TextAlign.center,
        left: plot.left + 4,
        right: plot.right,
      );
    }
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) =>
      old.columns != columns ||
      old.hovered != hovered ||
      old.selected != selected ||
      old.scale != scale ||
      old.colors.length != colors.length ||
      old.grid != grid;
}

/// A line of a [UsageLineChart]: its points (x in milliseconds since the
/// epoch), oldest first.
class UsageLine {
  const UsageLine({
    required this.label,
    required this.color,
    required this.points,
    this.area = false,
  });

  final String label;
  final Color color;
  final List<({double x, double y})> points;

  /// Washed under, faintly: the line that matters.
  final bool area;
}

/// Something that happened at a time, on a [UsageLineChart]: a hairline
/// across it, a mark at its top.
typedef UsageMarker = ({double x, String label, Color color});

/// Lines over time, on a hairline grid; markers across it where something
/// happened (a compaction). A crosshair follows the pointer, snapping to
/// the nearest point, and reads out each line's value there.
class UsageLineChart extends StatefulWidget {
  const UsageLineChart({
    super.key,
    required this.lines,
    required this.format,
    required this.xLabel,
    this.markers = const [],
    this.height = 200,
    this.onTapPoint,
  });

  final List<UsageLine> lines;
  final List<UsageMarker> markers;
  final String Function(double value) format;

  /// A time on the x axis, as shown.
  final String Function(double x) xLabel;
  final double height;

  /// The point of [line] picked: its index there.
  final void Function(int line, int index)? onTapPoint;

  @override
  State<UsageLineChart> createState() => _UsageLineChartState();
}

class _UsageLineChartState extends State<UsageLineChart> {
  double? _x;

  static const _axisWidth = 44.0;
  static const _labelsHeight = 18.0;

  ({double min, double max}) get _xs {
    var min = double.infinity, max = -double.infinity;
    for (final line in widget.lines) {
      for (final point in line.points) {
        min = math.min(min, point.x);
        max = math.max(max, point.x);
      }
    }
    for (final marker in widget.markers) {
      min = math.min(min, marker.x);
      max = math.max(max, marker.x);
    }
    if (min == double.infinity) return (min: 0, max: 1);
    if (min == max) return (min: min - 60000, max: max + 60000);
    return (min: min, max: max);
  }

  /// The point nearest [x] among all the lines'.
  ({int line, int index})? _nearest(double x) {
    ({int line, int index})? best;
    var distance = double.infinity;
    for (final (l, line) in widget.lines.indexed) {
      for (final (i, point) in line.points.indexed) {
        final d = (point.x - x).abs();
        if (d < distance) {
          distance = d;
          best = (line: l, index: i);
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final xs = _xs;
    final max = widget.lines.fold(
      0.0,
      (top, line) =>
          line.points.fold(top, (top, point) => math.max(top, point.y)),
    );
    final scale = niceScale(max);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = constraints.maxWidth - _axisWidth - 8;
          double toX(double dx) =>
              xs.min + (dx - _axisWidth) / plotWidth * (xs.max - xs.min);
          double toDx(double x) =>
              _axisWidth + (x - xs.min) / (xs.max - xs.min) * plotWidth;
          final hovered = switch (_x) {
            final x? => _nearest(x),
            null => null,
          };
          final snapped = hovered == null
              ? null
              : widget.lines[hovered.line].points[hovered.index].x;
          // Each line's value at the snapped time: its last point by then.
          List<({Color? color, String value, String label})> readout() => [
            for (final line in widget.lines)
              if (line.points.lastWhere(
                    (p) => p.x <= snapped! + 1,
                    orElse: () => (x: double.nan, y: double.nan),
                  )
                  case final point when !point.x.isNaN)
                (
                  color: line.color,
                  value: widget.format(point.y),
                  label: line.label,
                ),
            for (final marker in widget.markers)
              if ((marker.x - snapped!).abs() <=
                  (xs.max - xs.min) / plotWidth * 6)
                (color: marker.color, value: '◆', label: marker.label),
          ];
          return MouseRegion(
            onHover: (event) =>
                setState(() => _x = toX(event.localPosition.dx)),
            onExit: (_) => setState(() => _x = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final picked = _nearest(toX(details.localPosition.dx));
                if (picked != null) {
                  widget.onTapPoint?.call(picked.line, picked.index);
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LinesPainter(
                        lines: widget.lines,
                        markers: widget.markers,
                        xs: xs,
                        scale: scale,
                        crosshair: snapped,
                        axisWidth: _axisWidth,
                        labelsHeight: _labelsHeight,
                        grid: UsagePalette.grid,
                        surface: UsageCard.background,
                        crosshairColor: AppColors.textFaint,
                        textStyle: _axisText(context),
                        format: widget.format,
                        xLabel: widget.xLabel,
                      ),
                    ),
                  ),
                  if (snapped != null)
                    Positioned.fill(
                      child: _TooltipLayer(
                        x: toDx(snapped),
                        width: constraints.maxWidth,
                        tooltip: UsageTooltip(
                          title: widget.xLabel(snapped),
                          rows: readout(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter({
    required this.lines,
    required this.markers,
    required this.xs,
    required this.scale,
    required this.crosshair,
    required this.axisWidth,
    required this.labelsHeight,
    required this.grid,
    required this.surface,
    required this.crosshairColor,
    required this.textStyle,
    required this.format,
    required this.xLabel,
  });

  final List<UsageLine> lines;
  final List<UsageMarker> markers;
  final ({double min, double max}) xs;
  final ({double top, double step}) scale;
  final double? crosshair;
  final double axisWidth;
  final double labelsHeight;
  final Color grid;
  final Color surface;
  final Color crosshairColor;
  final TextStyle textStyle;
  final String Function(double value) format;
  final String Function(double x) xLabel;

  void _text(Canvas canvas, String text, Offset at, {TextAlign? align}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
    painter.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      axisWidth,
      10,
      size.width - 8,
      size.height - labelsHeight,
    );
    Offset at(double x, double y) => Offset(
      plot.left + (x - xs.min) / (xs.max - xs.min) * plot.width,
      plot.bottom - y / scale.top * plot.height,
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 0.0; v <= scale.top + 1e-9; v += scale.step) {
      final y =
          (plot.bottom - v / scale.top * plot.height).roundToDouble() + 0.5;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(
        canvas,
        format(v),
        Offset(plot.left - 8, y),
        align: TextAlign.right,
      );
    }
    // The markers under the lines: a hairline, a diamond at the top.
    for (final marker in markers) {
      final x = at(marker.x, 0).dx;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = marker.color.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      final diamond = Path()
        ..moveTo(x, plot.top - 5)
        ..lineTo(x + 4, plot.top - 1)
        ..lineTo(x, plot.top + 3)
        ..lineTo(x - 4, plot.top - 1)
        ..close();
      canvas.drawPath(diamond, Paint()..color = marker.color);
    }
    for (final line in lines) {
      if (line.points.isEmpty) continue;
      final path = Path();
      for (final (i, point) in line.points.indexed) {
        final offset = at(point.x, point.y);
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      if (line.area && line.points.length > 1) {
        final area = Path.from(path)
          ..lineTo(at(line.points.last.x, 0).dx, plot.bottom)
          ..lineTo(at(line.points.first.x, 0).dx, plot.bottom)
          ..close();
        canvas.drawPath(
          area,
          Paint()..color = line.color.withValues(alpha: 0.10),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      // A lone point, or the last: a dot ringed in the surface.
      final end = at(line.points.last.x, line.points.last.y);
      canvas.drawCircle(end, 6, Paint()..color = surface);
      canvas.drawCircle(end, 4, Paint()..color = line.color);
    }
    if (crosshair case final x?) {
      final dx = at(x, 0).dx;
      canvas.drawLine(
        Offset(dx, plot.top),
        Offset(dx, plot.bottom),
        Paint()
          ..color = crosshairColor
          ..strokeWidth = 1,
      );
      for (final line in lines) {
        for (final point in line.points) {
          if ((point.x - x).abs() < 1) {
            final offset = at(point.x, point.y);
            canvas.drawCircle(offset, 6, Paint()..color = surface);
            canvas.drawCircle(offset, 4, Paint()..color = line.color);
          }
        }
      }
    }
    // A few times along the bottom.
    final count = math.max(2, (plot.width / 110).floor());
    for (var i = 0; i < count; i++) {
      final x = xs.min + (xs.max - xs.min) * i / (count - 1);
      _text(
        canvas,
        xLabel(x),
        Offset(
          (at(x, 0).dx).clamp(plot.left + 20, plot.right - 20),
          size.height - labelsHeight / 2,
        ),
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) =>
      old.lines != lines ||
      old.markers != markers ||
      old.crosshair != crosshair ||
      old.scale != scale ||
      old.grid != grid;
}

/// A row of a [UsageRankList].
class UsageRankItem {
  const UsageRankItem({
    required this.key,
    required this.label,
    required this.value,
    required this.valueText,
    this.detail,
    this.secondary,
    this.color,
    this.segments,
    this.leading,
  });

  final String key;
  final String label;

  /// Before its name: an upstream's, a model's icon.
  final Widget? leading;
  final String? detail;
  final double value;
  final String valueText;

  /// After the value, fainter: its calls, its share.
  final String? secondary;

  /// Its bar's color: the list's one color unless given.
  final Color? color;

  /// The bar in parts (each its color), in place of one [color].
  final List<(double, Color)>? segments;
}

/// The largest first, each a bar of its share of the largest under its
/// name; [limit] shown till Show All. A click picks one ([onTap]).
class UsageRankList extends StatefulWidget {
  const UsageRankList({
    super.key,
    required this.items,
    this.limit = 6,
    this.onTap,
    this.selected = const {},
    this.color,
    this.empty,
    this.moreLabel,
    this.lessLabel,
  });

  final List<UsageRankItem> items;
  final int limit;
  final ValueChanged<UsageRankItem>? onTap;
  final Set<String> selected;
  final Color? color;
  final String? empty;
  final String Function(int count)? moreLabel;
  final String? lessLabel;

  @override
  State<UsageRankList> createState() => _UsageRankListState();
}

class _UsageRankListState extends State<UsageRankList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(widget.empty ?? '—', style: UsageText.faint),
      );
    }
    final top = items.fold(0.0, (top, item) => math.max(top, item.value));
    final shown = _all ? items : items.take(widget.limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in shown)
          _RankRow(
            item: item,
            fraction: top <= 0 ? 0 : item.value / top,
            color: item.color ?? widget.color ?? UsagePalette.series(1),
            selected: widget.selected.contains(item.key),
            onTap: widget.onTap == null ? null : () => widget.onTap!(item),
          ),
        if (items.length > widget.limit)
          Align(
            alignment: Alignment.centerLeft,
            child: HoverBuilder(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: () => setState(() => _all = !_all),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(
                    _all
                        ? (widget.lessLabel ?? '−')
                        : (widget.moreLabel?.call(items.length) ??
                              '+${items.length - widget.limit}'),
                    style: UsageText.muted.copyWith(
                      color: hovered ? AppColors.text : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.item,
    required this.fraction,
    required this.color,
    required this.selected,
    this.onTap,
  });

  final UsageRankItem item;
  final double fraction;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// Wide enough for what follows the value on its row.
  static const _inlineWidth = 460.0;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.10)
              : hovered && onTap != null
              ? AppColors.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Too narrow for all on its row: what follows the value on a
            // line of its own, under the name.
            final below =
                item.secondary != null && constraints.maxWidth < _inlineWidth;
            final secondaryStyle = UsageText.faint.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            );
            final row = Row(
              children: [
                if (item.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: item.label, style: UsageText.body),
                        if (item.detail case final detail?)
                          TextSpan(text: '  $detail', style: UsageText.faint),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                UsageMiniBar(
                  fraction: fraction,
                  color: color,
                  segments: item.segments,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 40),
                  child: Text(
                    item.valueText,
                    textAlign: TextAlign.right,
                    style: UsageText.tabular.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (item.secondary case final secondary? when !below) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 40),
                    child: Text(
                      secondary,
                      textAlign: TextAlign.right,
                      style: secondaryStyle,
                    ),
                  ),
                ],
              ],
            );
            if (!below) return row;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row,
                Padding(
                  padding: EdgeInsets.only(
                    left: item.leading == null ? 0 : 19,
                    top: 1,
                  ),
                  child: Text(
                    item.secondary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// A share as a short bar on its row: of the largest, in one color or in
/// parts ([segments]), on a faint track.
class UsageMiniBar extends StatelessWidget {
  const UsageMiniBar({
    super.key,
    required this.fraction,
    required this.color,
    this.segments,
    this.width = 72,
    this.height = 6,
  });

  final double fraction;
  final Color color;
  final List<(double, Color)>? segments;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final filled = math.max(2.0, width * fraction.clamp(0, 1));
    final radius = height / 2;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.hover,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          SizedBox(
            width: filled,
            child: switch (segments) {
              final segments? => CustomPaint(
                size: Size(filled, height),
                painter: _StackPainter(
                  segments,
                  surface: UsageCard.background,
                  radius: radius,
                ),
              ),
              null => Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// A whole in parts, along a bar: a 2px gap of the surface between them,
/// the ends rounded.
class _StackPainter extends CustomPainter {
  _StackPainter(
    this.segments, {
    required this.surface,
    this.radius = 4,
    this.hovered,
  });

  final List<(double, Color)> segments;
  final Color surface;
  final double radius;
  final int? hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (sum, s) => sum + s.$1);
    if (total <= 0) return;
    final shown = [
      for (final (i, s) in segments.indexed)
        if (s.$1 > 0) (i, s),
    ];
    final gaps = (shown.length - 1) * 2.0;
    final room = math.max(0.0, size.width - gaps);
    var x = 0.0;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );
    for (final (n, (i, (value, color))) in shown.indexed) {
      final w = value / total * room;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w, size.height),
        Paint()
          ..color = color.withValues(
            alpha: hovered == null || hovered == i ? 1 : 0.45,
          ),
      );
      x += w + (n < shown.length - 1 ? 2 : 0);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StackPainter old) =>
      old.segments != segments || old.hovered != hovered;
}

/// A part of a [UsageStackBar].
typedef UsagePart = ({String label, double value, Color color, String text});

/// A whole in parts, one bar of them, and under it each part's name, its
/// value and its share; a hover on a part (or its name) lifts it.
class UsageStackBar extends StatefulWidget {
  const UsageStackBar({
    super.key,
    required this.parts,
    this.height = 10,
    this.columns = 2,
    this.selected = const {},
    this.onTap,
    this.minColumnWidth = 200,
  });

  final List<UsagePart> parts;
  final double height;

  /// The names under it, in up to this many columns, each at least
  /// [minColumnWidth] wide.
  final int columns;
  final double minColumnWidth;

  /// The parts picked (by index), marked; a click on a name toggles it
  /// when [onTap] is given.
  final Set<int> selected;
  final ValueChanged<int>? onTap;

  @override
  State<UsageStackBar> createState() => _UsageStackBarState();
}

class _UsageStackBarState extends State<UsageStackBar> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final parts = widget.parts;
    final total = parts.fold(0.0, (sum, p) => sum + p.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => MouseRegion(
            onHover: (event) {
              // The part under the pointer, as laid out.
              final shown = [
                for (final (i, p) in parts.indexed)
                  if (p.value > 0) (i, p),
              ];
              final room = constraints.maxWidth - (shown.length - 1) * 2;
              var x = 0.0;
              int? found;
              for (final (i, p) in shown) {
                final w = total <= 0 ? 0 : p.value / total * room;
                if (event.localPosition.dx <= x + w + 1) {
                  found = i;
                  break;
                }
                x += w + 2;
              }
              if (found != _hovered) setState(() => _hovered = found);
            },
            onExit: (_) => setState(() => _hovered = null),
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: CustomPaint(
                painter: _StackPainter(
                  [for (final p in parts) (p.value, p.color)],
                  surface: UsageCard.background,
                  radius: widget.height / 2.5,
                  hovered: _hovered,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            // As many as fit, up to [columns].
            final columns = math.max(
              1,
              math.min(
                widget.columns,
                ((constraints.maxWidth + 16) / (widget.minColumnWidth + 16))
                    .floor(),
              ),
            );
            final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 2,
              children: [
                for (final (i, part) in parts.indexed)
                  if (part.value > 0)
                    MouseRegion(
                      cursor: widget.onTap == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _hovered = i),
                      onExit: (_) => setState(() => _hovered = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onTap == null
                            ? null
                            : () => widget.onTap!(i),
                        child: Container(
                          width: width,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: widget.selected.contains(i)
                                ? AppColors.accent.withValues(alpha: 0.14)
                                : _hovered == i
                                ? AppColors.hover
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: part.color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  part.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: UsageText.muted,
                                ),
                              ),
                              Text(
                                part.text,
                                style: UsageText.tabular.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  total <= 0
                                      ? ''
                                      : UsageFormat.percent(part.value / total),
                                  textAlign: TextAlign.right,
                                  style: UsageText.faint.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// What shows where there is nothing to count: an icon, a line, what to
/// do about it.
class UsageEmpty extends StatelessWidget {
  const UsageEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: AppColors.accent),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: UsageText.heading),
        if (detail case final detail?) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              detail,
              textAlign: TextAlign.center,
              style: UsageText.muted,
            ),
          ),
        ],
        if (action case final action?) ...[const SizedBox(height: 14), action],
      ],
    ),
  );
}
