import 'dart:math' as math;

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';

/// Notepad++-style eye icon button that toggles tail (`tail -f`) monitoring on
/// the active file. Disabled while the document has unsaved edits.
class IdeTailActionButton extends StatelessWidget {
  const IdeTailActionButton({
    super.key,
    required this.tailing,
    required this.onPressed,
    this.dirty = false,
  });

  final bool tailing;
  final bool dirty;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final disabled = !tailing && dirty;
    return IdeActionButton(
      icon: Codicons.eye,
      tooltip: disabled
          ? l10n.tailSaveFirst
          : tailing
          ? l10n.tailStop
          : l10n.tailStart,
      checked: tailing,
      color: tailing ? themeColors['textLink.foreground'] : null,
      onPressed: disabled ? null : onPressed,
    );
  }
}

/// Compact floating button shown at the bottom-right of a tailing editor when
/// the user scrolls up to inspect earlier lines. Clicking it scrolls back to
/// the bottom and resumes automatic tail scrolling.
class IdeTailJumpButton extends StatefulWidget {
  const IdeTailJumpButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<IdeTailJumpButton> createState() => _IdeTailJumpButtonState();
}

class _IdeTailJumpButtonState extends State<IdeTailJumpButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final background = _hover
        ? themeColors['toolbar.hoverBackground']
        : themeColors['editorWidget.background'];
    final border = themeColors['editorWidget.border'];
    final foreground = themeColors['textLink.foreground'];
    return IdeHover(
      message: l10n.tailResume,
      position: IdeHoverPosition.above,
      child: Semantics(
        button: true,
        label: l10n.tailResume,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(14),
                boxShadow: IdeHoverColors.shadow,
              ),
              child: Icon(Codicons.arrowDown, size: 15, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline editor tooltip anchored at the caret (VS Code's
/// `.monaco-editor-overlaymessage .message`), shown when the user tries to
/// edit a read-only tailing editor. Falls back to the bottom-center of the
/// visible text area when the caret is scrolled offscreen.
class IdeEditorCaretTooltip extends StatelessWidget {
  const IdeEditorCaretTooltip({
    super.key,
    required this.text,
    required this.view,
    required this.offset,
  });

  final String text;
  final EditorSurfaceView? view;
  final int offset;

  @override
  Widget build(BuildContext context) {
    final surface = view;
    final area = surface?.textArea;
    if (surface == null || area == null || area.isEmpty) {
      return const SizedBox.shrink();
    }
    final caret = surface.caretRectAt(offset);
    final anchor =
        caret ??
        Rect.fromLTWH(
          area.center.dx,
          math.max(area.top + 8, area.bottom - 20),
          0,
          0,
        );
    final colors = themeColors;
    return IgnorePointer(
      child: CustomSingleChildLayout(
        delegate: _CaretTooltipLayout(anchor, area),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors['editorHoverWidget.background'],
            border: Border.all(color: colors['inputValidation.infoBorder']),
            borderRadius: BorderRadius.circular(3),
            boxShadow: IdeHoverColors.shadow,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: colors['editorHoverWidget.foreground'],
              decoration: TextDecoration.none,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaretTooltipLayout extends SingleChildLayoutDelegate {
  _CaretTooltipLayout(this.anchor, this.bounds);

  final Rect anchor;
  final Rect bounds;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const gap = 4.0;
    final roomAbove = anchor.top - bounds.top;
    final roomBelow = bounds.bottom - anchor.bottom;
    final above =
        roomAbove >= childSize.height + gap || roomAbove >= roomBelow;
    final rawTop = above
        ? anchor.top - childSize.height - gap
        : anchor.bottom + gap;
    final rawLeft = anchor.width == 0
        ? anchor.left - childSize.width / 2
        : anchor.left;
    final maxLeft = math.max(bounds.left, bounds.right - childSize.width - 8);
    final maxTop = math.max(bounds.top, bounds.bottom - childSize.height - 8);
    return Offset(
      rawLeft.clamp(bounds.left, maxLeft).toDouble(),
      rawTop.clamp(bounds.top, maxTop).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_CaretTooltipLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.bounds != bounds;
}
