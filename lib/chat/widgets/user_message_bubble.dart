import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';
import '../composer/composer_embeds.dart';
import 'assistant_text.dart';

/// A sent user message, echoed as text: `@mentions` and a leading
/// `/command` in it show as the same inline tags as in the composer.
/// Clicking it opens it for editing when [onEdit] is set; dragging still
/// selects text.
///
/// A long message shows its first lines, fading out at the bottom over an
/// expand icon; the click that opens the editor shows it all (the editor
/// scrolls past its own maximum height).
///
/// The click is read from raw pointer events rather than a tap recognizer:
/// a recognizer would compete with the history's text selection for the
/// same press, and win Shift+clicks meant to extend the selection.
class UserMessageBubble extends StatefulWidget {
  const UserMessageBubble({super.key, required this.text, this.onEdit});

  final String text;
  final VoidCallback? onEdit;

  @override
  State<UserMessageBubble> createState() => _UserMessageBubbleState();
}

/// Lines shown of a collapsed message. Messages up to one line longer show
/// in full: hiding a single line is not worth it.
const _collapsedLines = 6;
const _lineHeight = 13.5 * 1.5;

const _messageStyle = TextStyle(
  color: CursorColors.textPrimary,
  fontSize: 13.5,
  height: 1.5,
  // Centers glyphs in the line box, which the inline tags center on.
  leadingDistribution: TextLeadingDistribution.even,
);

TextSpan _messageSpan(String text) {
  final ops = composerDeltaFromText(text).toList();
  return TextSpan(
    style: _messageStyle,
    children: [
      for (final (i, op) in ops.indexed)
        switch (op.data) {
          // The document's closing newline is not part of the message.
          final String data when i == ops.length - 1 => inlineCodeSpan(
            data.substring(0, data.length - 1),
            _messageStyle,
          ),
          final String data => inlineCodeSpan(data, _messageStyle),
          final Map<dynamic, dynamic> data => ComposerTokenChip.span(
            data[ComposerTokenEmbed.type],
            _messageStyle,
          ),
          _ => const TextSpan(),
        },
    ],
  );
}

class _UserMessageBubbleState extends State<UserMessageBubble> {
  Offset? _pressedAt;

  void _handleDown(PointerDownEvent event) {
    final primary =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    _pressedAt = primary && !HardwareKeyboard.instance.isShiftPressed
        ? event.position
        : null;
  }

  void _handleUp(PointerUpEvent event) {
    final pressedAt = _pressedAt;
    _pressedAt = null;
    if (pressedAt == null) return;
    // A click, not the end of a drag selection.
    if ((event.position - pressedAt).distance <= kTouchSlop) {
      widget.onEdit?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: (_) => _pressedAt = null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: CursorColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CursorColors.borderStrong),
        ),
        child: _Collapsed(
          collapsedHeight: _lineHeight * _collapsedLines,
          collapseAbove: _lineHeight * (_collapsedLines + 1),
          content: Text.rich(_messageSpan(widget.text)),
          overlay: const _CollapsedOverlay(),
        ),
      ),
    );
  }
}

/// Over the bottom of a collapsed message: the text fades into the bubble,
/// above an expand icon.
class _CollapsedOverlay extends StatelessWidget {
  const _CollapsedOverlay();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x00262626),
              Color(0xCC262626),
              CursorColors.surfaceRaised,
            ],
            stops: [0, 0.5, 0.8],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: CursorColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Shows [content] in full up to [collapseAbove]; beyond that, only its top
/// [collapsedHeight], with [overlay] over the bottom. Decided in layout, so
/// a long message never shows a frame at full height first.
class _Collapsed extends MultiChildRenderObjectWidget {
  _Collapsed({
    required this.collapsedHeight,
    required this.collapseAbove,
    required Widget content,
    required Widget overlay,
  }) : super(children: [content, overlay]);

  final double collapsedHeight;
  final double collapseAbove;

  @override
  _RenderCollapsed createRenderObject(BuildContext context) =>
      _RenderCollapsed(collapsedHeight, collapseAbove);

  @override
  void updateRenderObject(BuildContext context, _RenderCollapsed renderObject) {
    renderObject
      ..collapsedHeight = collapsedHeight
      ..collapseAbove = collapseAbove;
  }
}

class _CollapsedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCollapsed extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CollapsedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CollapsedParentData> {
  _RenderCollapsed(this._collapsedHeight, this._collapseAbove);

  double _collapsedHeight;
  set collapsedHeight(double value) {
    if (value == _collapsedHeight) return;
    _collapsedHeight = value;
    markNeedsLayout();
  }

  double _collapseAbove;
  set collapseAbove(double value) {
    if (value == _collapseAbove) return;
    _collapseAbove = value;
    markNeedsLayout();
  }

  /// Height of the overlay, at the bottom of the shown part.
  static const _overlayHeight = 44.0;

  /// How far the overlay reaches past the clipped text, unclipped: on
  /// screen the clip edge can fall mid-pixel, and the clip keeps that whole
  /// row of text while an edge-aligned overlay only half covers it. Below is
  /// the bubble's padding, the overlay's end color.
  static const _overlayOvershoot = 2.0;

  bool _collapsed = false;

  RenderBox get _content => firstChild!;
  RenderBox get _overlay => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CollapsedParentData) {
      child.parentData = _CollapsedParentData();
    }
  }

  @override
  void performLayout() {
    _content.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final full = _content.size.height;
    _collapsed = full > _collapseAbove;
    size = constraints.constrain(
      Size(constraints.maxWidth, _collapsed ? _collapsedHeight : full),
    );
    final overlayHeight = _overlayHeight.clamp(0.0, size.height);
    _overlay.layout(
      BoxConstraints.tight(Size(size.width, overlayHeight + _overlayOvershoot)),
    );
    (_overlay.parentData! as _CollapsedParentData).offset = Offset(
      0,
      size.height - overlayHeight,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_collapsed) {
      context.paintChild(_content, offset);
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(_content, offset),
    );
    final overlayOffset = (_overlay.parentData! as _CollapsedParentData).offset;
    context.paintChild(_overlay, offset + overlayOffset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Hidden text is not hit; the overlay itself takes no pointers.
    if (!size.contains(position)) return false;
    return _content.hitTest(result, position: position);
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _collapsed ? Offset.zero & size : null;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _content.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _content.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) {
    final full = _content.getMinIntrinsicHeight(width);
    return full > _collapseAbove ? _collapsedHeight : full;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);
}
