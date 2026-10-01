/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The workbench hover: VS Code's one look for every tooltip in the Fast Ide.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/hover/browser/{hover.ts,hover.css,hoverWidget.ts} and
// src/vs/base/browser/ui/hover/hoverWidget.css, with the color theme's
// `editorHoverWidget.*` colors.
//
// Placement: `element` (upstream's default for action bars: beside the
// target, by [IdeHoverPosition]) or `mouse` ([IdeHover.followMouse], the
// default hover delegate of labels and list rows,
// `getDefaultHoverDelegate('mouse')`: below the target from 10px right of
// the pointer, updatableHoverWidget.ts and hoverWidget.ts `layout`).
//
// Deviations: Flutter's [RawTooltip] does the showing and hiding. It shows
// at once when another hover is still up (VS Code: hidden less than 200 ms
// ago), and hides 100 ms after the pointer leaves, not at once. A hover
// with a pointer does not flip to the other side (they sit at the window's
// edges: the activity bar, the status bar). No actions or status bar row.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/workbench_theme.dart' show themeColors;

/// The workbench hover's colors, in the color theme.
abstract final class IdeHoverColors {
  static Color get background => themeColors['editorHoverWidget.background'];
  static Color get foreground => themeColors['editorHoverWidget.foreground'];
  static Color get border => themeColors['editorHoverWidget.border'];
  static Color get link => themeColors['textLink.foreground'];
  static Color get codeBlock => themeColors['textCodeBlock.background'];

  /// `--vscode-shadow-lg` (workbench/browser/media/style.css): the same in
  /// every theme.
  static const shadow = [BoxShadow(color: Color(0x24000000), blurRadius: 12)];
}

/// Which side of its target a hover shows on.
enum IdeHoverPosition { below, above, right, left }

/// `workbench.hover.delay`: 1500 ms on macOS, 500 ms elsewhere.
Duration get ideHoverDelay => defaultTargetPlatform == TargetPlatform.macOS
    ? const Duration(milliseconds: 1500)
    : const Duration(milliseconds: 500);

/// A hover's box: VS Code's `.monaco-hover.workbench-hover`.
class IdeHoverBox extends StatelessWidget {
  const IdeHoverBox({
    super.key,
    required this.child,
    this.compact = true,
    this.maxWidth = 700,
    this.padding,
    this.radius = 5,
  });

  final Widget child;

  /// 12px text and less padding, as action bars' hovers are.
  final bool compact;
  final double maxWidth;

  /// Defaults to `.hover-contents`: 4px 8px, compact 2px 8px.
  final EdgeInsets? padding;

  /// 5, or 3 with a pointer.
  final double radius;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: IdeHoverColors.background,
        border: Border.all(color: IdeHoverColors.border),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: IdeHoverColors.shadow,
      ),
      child: Padding(
        padding:
            padding ??
            EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 2 : 4),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: IdeHoverColors.foreground,
            fontSize: compact ? 12 : 13,
            height: 19 / (compact ? 12 : 13),
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w400,
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Shows [message] (or [content]) in a workbench hover while [child] is
/// hovered, after [ideHoverDelay].
class IdeHover extends StatefulWidget {
  const IdeHover({
    super.key,
    this.message,
    this.content,
    this.position = IdeHoverPosition.below,
    this.pointer = false,
    this.compact = true,
    this.followMouse = false,
    this.excludeFromSemantics = false,
    required this.child,
  }) : assert(message != null || content != null);

  /// Also the tooltip screen readers announce.
  final String? message;

  /// Shown instead of [message].
  final Widget? content;
  final IdeHoverPosition position;

  /// A small arrow at the target, as the activity bar's and the status
  /// bar's hovers have.
  final bool pointer;
  final bool compact;

  /// The `mouse` placement: below [child] (above when there is no room),
  /// its left edge 10px right of where the pointer was ([position] and
  /// [pointer] do not apply).
  final bool followMouse;

  /// For a [child] that has [message] as its own semantics label already.
  final bool excludeFromSemantics;
  final Widget child;

  static const _gap = 4.0;
  static const _pointerSize = 3.0;

  @override
  State<IdeHover> createState() => _IdeHoverState();
}

class _IdeHoverState extends State<IdeHover> {
  /// Where the pointer last moved over the target, in the target.
  Offset? _mouse;

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    if (widget.message?.isEmpty ?? false) return widget.child;
    return RawTooltip(
      semanticsTooltip: widget.excludeFromSemantics ? null : widget.message,
      hoverDelay: ideHoverDelay,
      triggerMode: TooltipTriggerMode.manual,
      animationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 100),
        reverseDuration: Duration.zero,
      ),
      positionDelegate: widget.followMouse ? _placeAtMouse : _place,
      tooltipBuilder: (context, animation) =>
          FadeTransition(opacity: animation, child: _box()),
      child: widget.followMouse
          ? MouseRegion(
              onHover: (event) => _mouse = event.localPosition,
              child: widget.child,
            )
          : widget.child,
    );
  }

  /// `target.x = e.x + 10` (hoverService.ts `setupManagedHover`), and
  /// hoverWidget.ts' coordinates for it: `target.bottom - 2` below, or
  /// ending at `target.top` when the window's bottom is in the way; at the
  /// target's left + 2 when left of the window.
  Offset _placeAtMouse(TooltipPositionContext context) {
    final target = context.target;
    final half = context.targetSize / 2;
    final size = context.tooltipSize;
    final overlay = context.overlaySize;
    final left = target.dx - half.width;
    // No pointer yet (focus): the target's left.
    var x = switch (_mouse) {
      final mouse? => left + mouse.dx + 10,
      null => left,
    };
    if (x < 0) x = left + 2;
    final bottom = target.dy + half.height;
    final y = bottom + size.height > overlay.height
        ? target.dy - half.height - size.height
        : bottom - 2;
    return Offset(
      x.clamp(0, math.max(0, overlay.width - size.width)),
      y.clamp(0, math.max(0, overlay.height - size.height)),
    );
  }

  Widget _box() {
    final box = IdeHoverBox(
      compact: widget.compact,
      radius: widget.pointer ? 3 : 5,
      child: widget.content ?? Text(widget.message!),
    );
    if (!widget.pointer) return box;
    return CustomPaint(
      foregroundPainter: _PointerPainter(
        widget.position,
        background: IdeHoverColors.background,
        border: IdeHoverColors.border,
      ),
      child: box,
    );
  }

  Offset _place(TooltipPositionContext context) {
    final target = context.target;
    final half = context.targetSize / 2;
    final size = context.tooltipSize;
    final overlay = context.overlaySize;
    final gap = IdeHover._gap + (widget.pointer ? IdeHover._pointerSize : 0);
    var side = widget.position;
    // Flip to the other side when this one has no room (pointers stay).
    if (!widget.pointer) {
      side = switch (side) {
        IdeHoverPosition.below
            when target.dy + half.height + gap + size.height > overlay.height &&
                target.dy - half.height - gap - size.height >= 0 =>
          IdeHoverPosition.above,
        IdeHoverPosition.above
            when target.dy - half.height - gap - size.height < 0 =>
          IdeHoverPosition.below,
        IdeHoverPosition.right
            when target.dx + half.width + gap + size.width > overlay.width =>
          IdeHoverPosition.left,
        IdeHoverPosition.left
            when target.dx - half.width - gap - size.width < 0 =>
          IdeHoverPosition.right,
        _ => side,
      };
    }
    final Offset offset = switch (side) {
      IdeHoverPosition.below => Offset(
        target.dx - size.width / 2,
        target.dy + half.height + gap,
      ),
      IdeHoverPosition.above => Offset(
        target.dx - size.width / 2,
        target.dy - half.height - gap - size.height,
      ),
      IdeHoverPosition.right => Offset(
        target.dx + half.width + gap,
        target.dy - size.height / 2,
      ),
      IdeHoverPosition.left => Offset(
        target.dx - half.width - gap - size.width,
        target.dy - size.height / 2,
      ),
    };
    return Offset(
      offset.dx.clamp(0, math.max(0, overlay.width - size.width)),
      offset.dy.clamp(0, math.max(0, overlay.height - size.height)),
    );
  }
}

/// `.workbench-hover-pointer`: a 6px square turned 45°, half outside the
/// hover's edge facing the target.
class _PointerPainter extends CustomPainter {
  const _PointerPainter(
    this.position, {
    required this.background,
    required this.border,
  });

  final IdeHoverPosition position;
  final Color background;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final (center, angle) = switch (position) {
      IdeHoverPosition.right => (Offset(0, size.height / 2), math.pi / 4),
      IdeHoverPosition.left => (
        Offset(size.width, size.height / 2),
        -3 * math.pi / 4,
      ),
      IdeHoverPosition.below => (Offset(size.width / 2, 0), 3 * math.pi / 4),
      IdeHoverPosition.above => (
        Offset(size.width / 2, size.height),
        -math.pi / 4,
      ),
    };
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angle);
    const square = Rect.fromLTWH(-3, -3, 6, 6);
    canvas.drawRect(square, Paint()..color = background);
    // The two sides outside the hover carry its border.
    final edge = Paint()
      ..color = border
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(square.bottomLeft, square.topLeft, edge)
      ..drawLine(square.bottomLeft, square.bottomRight, edge)
      ..restore();
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.background != background ||
      oldDelegate.border != border;
}

/// An action bar button: a codicon in a 22px square that lights up on
/// hover (`.monaco-action-bar .action-label`, workbench/browser/media/
/// style.css), with a workbench hover.
class IdeActionButton extends StatefulWidget {
  const IdeActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 22,
    this.width,
    this.iconSize = 16,
    this.color,
    this.checked = false,
    this.hoverPosition = IdeHoverPosition.below,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  /// [size] when null; narrower for a dropdown's chevron beside its
  /// primary action (`.monaco-dropdown-with-primary`).
  final double? width;
  final double iconSize;

  /// `icon.foreground` when null.
  final Color? color;

  /// Shown pressed (`.action-item.active`), as while its menu is open.
  final bool checked;
  final IdeHoverPosition hoverPosition;

  static Color get hoverBackground => themeColors['toolbar.hoverBackground'];
  static Color get activeBackground => themeColors['toolbar.activeBackground'];
  static Color get foreground => themeColors['icon.foreground'];

  @override
  State<IdeActionButton> createState() => _IdeActionButtonState();
}

class _IdeActionButtonState extends State<IdeActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // High contrast themes outline it on hover (dashed upstream).
    final outline = enabled && _hover
        ? themeColors.get('toolbar.hoverOutline')
        : null;
    return IdeHover(
      message: widget.tooltip,
      position: widget.hoverPosition,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: widget.checked ? true : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              width: widget.width ?? widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: !enabled
                    ? null
                    : widget.checked
                    ? IdeActionButton.activeBackground
                    : _hover
                    ? IdeActionButton.hoverBackground
                    : null,
                borderRadius: BorderRadius.circular(5),
              ),
              foregroundDecoration: outline == null
                  ? null
                  : BoxDecoration(
                      border: Border.all(color: outline),
                      borderRadius: BorderRadius.circular(5),
                    ),
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.color ?? IdeActionButton.foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
