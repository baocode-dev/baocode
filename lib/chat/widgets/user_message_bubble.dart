import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import '../composer/composer_embeds.dart';
import 'assistant_text.dart';
import 'fade_curve.dart';
import 'image_thumbnails.dart';

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
  const UserMessageBubble({
    super.key,
    required this.text,
    this.images = const [],
    this.onEdit,
    this.queued = false,
    this.onCancel,
  });

  final String text;
  final List<ImageAttachment> images;
  final VoidCallback? onEdit;

  /// Waiting for the agent to finish what it is doing.
  final bool queued;

  /// Takes the queued message back.
  final VoidCallback? onCancel;

  /// Its corners; what answers it is inset this much at either side.
  static const radius = 8.0;

  @override
  State<UserMessageBubble> createState() => _UserMessageBubbleState();
}

/// Lines shown of a collapsed message. Messages up to one line longer show
/// in full: hiding a single line is not worth it.
const _collapsedLines = 3;
const _lineHeight = 13.5 * 1.5;

const _messageStyle = TextStyle(
  color: CursorColors.textPrimary,
  fontSize: 13.5,
  height: 1.5,
  // Centers glyphs in the line box, which the inline tags center on.
  leadingDistribution: TextLeadingDistribution.even,
);

TextSpan _messageSpan(String text, ComposerVocabulary vocabulary) {
  final ops = composerDeltaFromText(text, vocabulary).toList();
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

  /// The press went to an image (which opens its preview instead). Its
  /// listener, deeper, hears the press first.
  bool _pressOnImage = false;

  void _handleDown(PointerDownEvent event) {
    final primary =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    final onImage = _pressOnImage;
    _pressOnImage = false;
    _pressedAt =
        primary && !onImage && !HardwareKeyboard.instance.isShiftPressed
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
    final bubble = _buildBubble(context);
    if (!widget.queued) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Opacity(opacity: 0.6, child: bubble),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 12,
                color: CursorColors.textFaint,
              ),
              const SizedBox(width: 4),
              const Text(
                'Queued',
                style: TextStyle(color: CursorColors.textFaint, fontSize: 11.5),
              ),
              if (widget.onCancel case final cancel?) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: cancel,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: CursorColors.accent,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(BuildContext context) {
    return Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: (_) => _pressedAt = null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: CursorColors.surfaceRaised,
          borderRadius: BorderRadius.circular(UserMessageBubble.radius),
          border: Border.all(color: CursorColors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.images.isNotEmpty)
              Listener(
                onPointerDown: (_) => _pressOnImage = true,
                child: ImageThumbnails(images: widget.images),
              ),
            if (widget.images.isNotEmpty && widget.text.isNotEmpty)
              const SizedBox(height: 8),
            if (widget.text.isNotEmpty || widget.images.isEmpty)
              _Collapsed(
                collapsedHeight: _lineHeight * _collapsedLines,
                collapseAbove: _lineHeight * (_collapsedLines + 1),
                content: Text.rich(
                  _messageSpan(widget.text, ComposerVocabulary.of(context)),
                ),
                overlay: const _CollapsedOverlay(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Over the bottom of a collapsed message, where its text fades out: an
/// expand icon.
class _CollapsedOverlay extends StatelessWidget {
  const _CollapsedOverlay();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: CursorColors.textMuted,
        ),
      ),
    );
  }
}

/// Shows [content] in full up to [collapseAbove]; beyond that, only its top
/// [collapsedHeight], fading out through its alpha at the bottom, with
/// [overlay] over the fade. Decided in layout, so
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

  /// Height of the overlay, at the bottom of the shown part, over which the
  /// text fades out.
  static const _overlayHeight = 44.0;

  /// How far the overlay (its icon) and the mask reach past the clipped
  /// text, into the bubble's bottom padding: on screen the clip edge can
  /// fall mid-pixel, and the clip keeps that whole row of pixels while a mask
  /// ending at the edge only partly covers it, leaving a row of glyphs at
  /// close to full strength (seen on the web, at some scroll offsets).
  static const _overlayOvershoot = 2.0;

  /// How far above the clip edge the text is faded out completely: the fade
  /// over the overlay is shifted up by this much, text below it hidden. The
  /// eased end of a fade is faint but not zero, and on the last line that
  /// faint trace shows as the tops of its glyphs.
  static const _fadeOffset = 10.0;

  bool _collapsed = false;

  final _maskLayer = LayerHandle<ShaderMaskLayer>();

  @override
  bool get alwaysNeedsCompositing => _collapsed;

  @override
  void dispose() {
    _maskLayer.layer = null;
    super.dispose();
  }

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
    final collapsed = full > _collapseAbove;
    if (collapsed != _collapsed) {
      _collapsed = collapsed;
      markNeedsCompositingBitsUpdate();
    }
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
      _maskLayer.layer = null;
      context.paintChild(_content, offset);
      return;
    }
    final overlayOffset = (_overlay.parentData! as _CollapsedParentData).offset;
    // Over the overlay, shifted up by [_fadeOffset]; below it the gradient
    // clamps to hidden, down through the overshoot.
    final fade = Rect.fromLTRB(
      0,
      overlayOffset.dy - _fadeOffset,
      size.width,
      size.height - _fadeOffset,
    );
    final samples = easedFade().toList().reversed;
    _maskLayer.layer = (_maskLayer.layer ?? ShaderMaskLayer())
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final (_, opacity) in samples)
            Color.fromRGBO(255, 255, 255, opacity),
        ],
        stops: [for (final (t, _) in samples) 1 - t],
      ).createShader(fade)
      ..maskRect = offset & Size(size.width, size.height + _overlayOvershoot)
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      _maskLayer.layer!,
      (context, offset) => context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => context.paintChild(_content, offset),
      ),
      offset,
    );
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
