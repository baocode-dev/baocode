/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The workbench hover: VS Code's one look for every tooltip in the Fast Ide.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/hover/browser/{hover.ts,hover.css,hoverWidget.ts} and
// src/vs/base/browser/ui/hover/hoverWidget.css, with the colors of Dark 2026
// (extensions/theme-defaults/themes/2026-dark.json), its default theme.
//
// Deviations: Flutter's [RawTooltip] does the showing and hiding. It shows
// at once when another hover is still up (VS Code: hidden less than 200 ms
// ago), and hides 100 ms after the pointer leaves, not at once. A hover
// with a pointer does not flip to the other side (they sit at the window's
// edges: the activity bar, the status bar). No actions or status bar row.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// VS Code's Dark 2026 hover colors.
abstract final class IdeHoverColors {
  /// `editorHoverWidget.background`.
  static const background = Color(0xFF202122);

  /// `editorHoverWidget.foreground` (`editorWidget.foreground`).
  static const foreground = Color(0xFFBFBFBF);

  /// `editorHoverWidget.border`.
  static const border = Color(0xFF2A2B2C);

  /// `textLink.foreground`.
  static const link = Color(0xFF48A0C7);

  /// `textCodeBlock.background`.
  static const codeBlock = Color(0xFF242526);

  /// `--vscode-shadow-lg`.
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
class IdeHover extends StatelessWidget {
  const IdeHover({
    super.key,
    this.message,
    this.content,
    this.position = IdeHoverPosition.below,
    this.pointer = false,
    this.compact = true,
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
  final Widget child;

  static const _gap = 4.0;
  static const _pointerSize = 3.0;

  @override
  Widget build(BuildContext context) {
    if (message?.isEmpty ?? false) return child;
    return RawTooltip(
      semanticsTooltip: message,
      hoverDelay: ideHoverDelay,
      triggerMode: TooltipTriggerMode.manual,
      animationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 100),
        reverseDuration: Duration.zero,
      ),
      positionDelegate: _place,
      tooltipBuilder: (context, animation) =>
          FadeTransition(opacity: animation, child: _box()),
      child: child,
    );
  }

  Widget _box() {
    final box = IdeHoverBox(
      compact: compact,
      radius: pointer ? 3 : 5,
      child: content ?? Text(message!),
    );
    if (!pointer) return box;
    return CustomPaint(
      foregroundPainter: _PointerPainter(position),
      child: box,
    );
  }

  Offset _place(TooltipPositionContext context) {
    final target = context.target;
    final half = context.targetSize / 2;
    final size = context.tooltipSize;
    final overlay = context.overlaySize;
    final gap = _gap + (pointer ? _pointerSize : 0);
    var side = position;
    // Flip to the other side when this one has no room (pointers stay).
    if (!pointer) {
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
  const _PointerPainter(this.position);

  final IdeHoverPosition position;

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
    canvas.drawRect(square, Paint()..color = IdeHoverColors.background);
    // The two sides outside the hover carry its border.
    final border = Paint()
      ..color = IdeHoverColors.border
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(square.bottomLeft, square.topLeft, border)
      ..drawLine(square.bottomLeft, square.bottomRight, border)
      ..restore();
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) =>
      oldDelegate.position != position;
}

/// An action bar button: a codicon in a 22px square that lights up on
/// hover (`.monaco-action-bar .action-label`), with a workbench hover.
class IdeActionButton extends StatefulWidget {
  const IdeActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 22,
    this.iconSize = 16,
    this.color,
    this.checked = false,
    this.hoverPosition = IdeHoverPosition.below,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  /// `icon.foreground` when null.
  final Color? color;

  /// Shown pressed, as a toggle that is on.
  final bool checked;
  final IdeHoverPosition hoverPosition;

  /// `toolbar.hoverBackground`.
  static const hoverBackground = Color(0x505A5D5E);

  /// `icon.foreground` (Dark 2026).
  static const foreground = Color(0xFF8C8C8C);

  @override
  State<IdeActionButton> createState() => _IdeActionButtonState();
}

class _IdeActionButtonState extends State<IdeActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
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
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled && (_hover || widget.checked)
                    ? IdeActionButton.hoverBackground
                    : null,
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
