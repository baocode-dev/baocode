/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A graph row's lanes and node, drawn as VS Code draws its SVG: lanes
// passing through, curving in and out, the commit's circle (a ring for
// HEAD, a double circle for merges, a dashed one for incoming and
// outgoing changes), and under an expanded commit, its lanes continuing
// past its changes.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/scm/browser/scmHistory.ts
// (`renderSCMHistoryItemGraph`, `renderSCMHistoryGraphPlaceholder`) and the
// circles' strokes and fills in media/scm.css. Lanes are drawn in their
// color ids (`asCssVariable`) as the current color theme has them.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/workbench_theme.dart';
import 'git_model.dart';

const _laneHeight = 22.0;
const _laneWidth = 11.0;
const _curveRadius = 5.0;
const _circleRadius = 4.0;
const _circleStroke = 2.0;

/// The width of [row]'s graph.
double ideGraphWidth(IdeGraphRow row) =>
    _laneWidth *
    (math.max(math.max(row.inputLanes.length, row.outputLanes.length), 1) + 1);

/// The width of the lanes drawn beside an expanded commit's changes.
double ideGraphPlaceholderWidth(List<IdeGraphLane> lanes) =>
    _laneWidth * (lanes.length + 1);

class IdeGraphPainter extends CustomPainter {
  IdeGraphPainter(
    this.row, {
    required this.background,
    this.hovered = false,
    this.expanded = false,
  }) : colors = themeColors;

  final IdeGraphRow row;

  /// The color theme's colors, which the lanes' ids name.
  final WorkbenchColors colors;

  /// What is behind the row (the side bar, or its hover or selection): the
  /// circles' outlines and hollow centers are this color.
  final Color background;

  /// A hovered row's circles lose their outline.
  final bool hovered;

  /// An expanded commit's line down to its changes is 3px wide.
  final bool expanded;

  static Paint _stroke(Color color, [double width = 1]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    const w = _laneWidth;
    const h = _laneHeight;
    final commit = row.commit;
    final input = row.inputLanes;
    final output = row.outputLanes;
    final inputIndex = input.indexWhere((lane) => lane.id == commit.id);
    final circleIndex = row.circleIndex;
    final circleColor = colors[row.circleColor];

    var outputIndex = 0;
    for (var index = 0; index < input.length; index++) {
      final color = colors[input[index].color];
      if (input[index].id == commit.id) {
        if (index != circleIndex) {
          // The base commit's lane curves into its circle: / then -.
          final path = Path()
            ..moveTo(w * (index + 1), 0)
            ..arcToPoint(Offset(w * index, w), radius: const Radius.circular(w))
            ..lineTo(w * (circleIndex + 1), w);
          canvas.drawPath(path, _stroke(color));
        } else {
          outputIndex++;
        }
      } else if (outputIndex < output.length &&
          input[index].id == output[outputIndex].id) {
        if (index == outputIndex) {
          canvas.drawLine(
            Offset(w * (index + 1), 0),
            Offset(w * (index + 1), h),
            _stroke(color),
          );
        } else {
          // A lane moving left: | / - / |.
          final path = Path()
            ..moveTo(w * (index + 1), 0)
            ..lineTo(w * (index + 1), 6)
            ..arcToPoint(
              Offset(w * (index + 1) - _curveRadius, h / 2),
              radius: const Radius.circular(_curveRadius),
            )
            ..lineTo(w * (outputIndex + 1) + _curveRadius, h / 2)
            ..arcToPoint(
              Offset(w * (outputIndex + 1), h / 2 + _curveRadius),
              radius: const Radius.circular(_curveRadius),
              clockwise: false,
            )
            ..lineTo(w * (outputIndex + 1), h);
          canvas.drawPath(path, _stroke(color));
        }
        outputIndex++;
      }
    }

    // The other parents' lanes leave the circle: - then \.
    for (final parent in commit.parentIds.skip(1)) {
      final parentIndex = output.lastIndexWhere((lane) => lane.id == parent);
      if (parentIndex < 0) continue;
      final path = Path()
        ..moveTo(w * parentIndex, h / 2)
        ..arcToPoint(
          Offset(w * (parentIndex + 1), h),
          radius: const Radius.circular(w),
        )
        ..moveTo(w * parentIndex, h / 2)
        ..lineTo(w * (circleIndex + 1), h / 2);
      canvas.drawPath(path, _stroke(colors[output[parentIndex].color]));
    }

    final x = w * (circleIndex + 1);
    if (inputIndex >= 0) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h / 2),
        _stroke(colors[input[inputIndex].color]),
      );
    }
    if (commit.parentIds.isNotEmpty) {
      canvas.drawLine(
        Offset(x, h / 2),
        Offset(x, h),
        _stroke(circleColor, expanded ? 3 : 1),
      );
    }

    // The circles, as the SVG paints them: a fill, then a stroke centered
    // on the radius. The first circle's stroke is the outline around it.
    final center = Offset(x, w);
    final outline = hovered ? const Color(0x00000000) : background;
    void circle(double radius, double stroke, Color? fill, Color strokeColor) {
      if (fill != null) {
        canvas.drawCircle(center, radius, Paint()..color = fill);
      }
      canvas.drawCircle(center, radius, _stroke(strokeColor, stroke));
    }

    switch (row.kind) {
      case IdeGraphRowKind.head:
        circle(_circleRadius + 3, _circleStroke, circleColor, outline);
        circle(_circleStroke, _circleRadius, background, background);
      case IdeGraphRowKind.incomingChanges || IdeGraphRowKind.outgoingChanges:
        circle(_circleRadius + 3, _circleStroke, circleColor, outline);
        circle(_circleRadius + 1, _circleStroke + 1, null, background);
        canvas.drawCircle(
          center,
          _circleRadius + 1,
          Paint()..color = background,
        );
        _dashedCircle(canvas, center, _circleRadius + 1, circleColor);
      case IdeGraphRowKind.node when commit.parentIds.length > 1:
        circle(_circleRadius + 2, _circleStroke, circleColor, outline);
        circle(_circleRadius - 1, _circleStroke, circleColor, background);
      case IdeGraphRowKind.node:
        circle(_circleRadius + 1, _circleStroke, circleColor, outline);
    }
  }

  /// `stroke-dasharray: 4,2` from the circle's rightmost point, clockwise.
  static void _dashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _circleStroke - 1
      ..color = color;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final circumference = 2 * math.pi * radius;
    for (var start = 0.0; start < circumference; start += 6) {
      final length = math.min(4.0, circumference - start);
      canvas.drawArc(rect, start / radius, length / radius, false, paint);
    }
  }

  @override
  bool shouldRepaint(IdeGraphPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.colors != colors ||
      oldDelegate.background != background ||
      oldDelegate.hovered != hovered ||
      oldDelegate.expanded != expanded;
}

/// The lanes beside an expanded commit's changes: straight down, the
/// commit's own ([highlight]) 3px wide.
class IdeGraphPlaceholderPainter extends CustomPainter {
  IdeGraphPlaceholderPainter(this.lanes, {this.highlight})
    : colors = themeColors;

  final List<IdeGraphLane> lanes;
  final int? highlight;

  /// The color theme's colors, which the lanes' ids name.
  final WorkbenchColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (index, lane) in lanes.indexed) {
      final x = _laneWidth * (index + 1);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, _laneHeight),
        IdeGraphPainter._stroke(colors[lane.color], index == highlight ? 3 : 1),
      );
    }
  }

  @override
  bool shouldRepaint(IdeGraphPlaceholderPainter oldDelegate) =>
      oldDelegate.lanes != lanes ||
      oldDelegate.colors != colors ||
      oldDelegate.highlight != highlight;
}
