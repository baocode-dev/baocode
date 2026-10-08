import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../composer/composer_embeds.dart';
import 'assistant_text.dart';
import 'fade_curve.dart';
import 'image_thumbnails.dart';
import 'inline_code.dart';

/// A sent user message, echoed as text: `@paths`, `[path:lines]` and a
/// leading `/command` in it show as the same inline tags as in the composer.
/// The lines a message carries after its text (see [codeAppendix]) show in
/// their tags only.
/// Clicking it opens it when [onEdit] is set: for editing, or where it
/// cannot be edited (e.g. what a subagent was asked), read only (see
/// [UserMessageViewer]). Dragging still selects text.
///
/// A long message shows its first lines, fading out at the bottom over an
/// expand icon; the click that opens it shows it all (scrolling past the
/// editor's maximum height).
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

TextStyle get _messageStyle => TextStyle(
  color: AppColors.textPrimary,
  fontSize: 13.5,
  height: 1.5,
  // Centers glyphs in the line box, which the inline tags center on.
  leadingDistribution: TextLeadingDistribution.even,
);

/// [text], its tokens and references to its [images] as tags.
TextSpan _messageSpan(
  String text,
  ComposerVocabulary vocabulary,
  List<ImageAttachment> images,
) {
  final byNumber = {for (final image in images) ?image.number: image};
  final ops = composerDeltaFromText(
    text,
    vocabulary,
    images: byNumber.keys.toSet(),
  ).toList();
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
          {ComposerImageEmbed.type: final data} => ComposerImageChip.span(
            ComposerImageEmbed.decode(data),
            byNumber[ComposerImageEmbed.decode(data)],
            _messageStyle,
          ),
          {ComposerCodeEmbed.type: final data} => ComposerCodeChip.span(
            data,
            _messageStyle,
          ),
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
  final _selection = _MessageSelectionDelegate();
  Offset? _pressedAt;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  /// The press went to an image (which opens its preview instead). It
  /// hears the press first, being deeper (see [ImagePressScope]).
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
              Icon(
                Icons.schedule_rounded,
                size: 12,
                color: AppColors.textFaint,
              ),
              const SizedBox(width: 4),
              Text(
                context.l10n.messageQueued,
                style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
              ),
              if (widget.onCancel case final cancel?) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: cancel,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      context.l10n.commonCancel,
                      style: TextStyle(color: AppColors.accent, fontSize: 11.5),
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
      child: ImagePressScope(
        onPress: () => _pressOnImage = true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(UserMessageBubble.radius),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.images.isNotEmpty)
                ImageThumbnails(images: widget.images),
              // As in its editor (the composer), so editing moves nothing.
              if (widget.images.isNotEmpty && widget.text.isNotEmpty)
                const SizedBox(height: 10),
              if (widget.text.isNotEmpty || widget.images.isEmpty)
                SelectionContainer(
                  delegate: _selection,
                  child: _Collapsed(
                    collapsedHeight: _lineHeight * _collapsedLines,
                    collapseAbove: _lineHeight * (_collapsedLines + 1),
                    content: InlineCodeText(
                      _messageSpan(
                        widget.text,
                        ComposerVocabulary.of(context),
                        widget.images,
                      ),
                    ),
                    overlay: const _CollapsedOverlay(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sent message opened where it cannot be edited: all of it, in place
/// of its bubble as the editor would be and looking like it, but read only.
/// Past the editor's maximum height it scrolls ([controller]); Esc closes
/// it ([onClose]).
class UserMessageViewer extends StatefulWidget {
  const UserMessageViewer({
    super.key,
    required this.text,
    this.images = const [],
    this.controller,
    required this.onClose,
  });

  final String text;
  final List<ImageAttachment> images;
  final ScrollController? controller;
  final VoidCallback onClose;

  /// As the editor's: ten lines, or a third of the window if less.
  static double maxHeight(BuildContext context) => math.max(
    _lineHeight * _collapsedLines,
    math.min(_lineHeight * 10, MediaQuery.sizeOf(context).height / 3),
  );

  @override
  State<UserMessageViewer> createState() => _UserMessageViewerState();
}

class _UserMessageViewerState extends State<UserMessageViewer> {
  /// Taken as it opens, as the editor's is: from the history, which had it
  /// for the click.
  final FocusNode _focus = FocusNode(debugLabel: 'Message viewer');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final UserMessageViewer(:text, :images, :controller) = widget;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          // The editor's, over the page (see ChatComposer).
          color: Color.alphaBlend(
            colors['chat.requestBubbleBackground'],
            colors['editor.background'],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors['agentsChatInput.border']),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: UserMessageViewer.maxHeight(context),
          ),
          // A slim bar, as the editor's.
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              thickness: const WidgetStatePropertyAll(4),
              crossAxisMargin: 3,
            ),
            child: Scrollbar(
              controller: controller,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  // Its own selection: not the history's.
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (images.isNotEmpty) ImageThumbnails(images: images),
                        if (images.isNotEmpty && text.isNotEmpty)
                          const SizedBox(height: 10),
                        if (text.isNotEmpty)
                          InlineCodeText(
                            _messageSpan(
                              text,
                              ComposerVocabulary.of(context),
                              images,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// The full message stays laid out for copying, but only its shown part
/// receives pointer selection. Paint clips do not clip selection events.
class _MessageSelectionDelegate extends SelectionContainerDelegate
    with ChangeNotifier {
  // Text.rich owns the fragment and inline-tag selection beneath this boundary.
  Selectable? _text;

  @override
  void add(Selectable selectable) {
    assert(_text == null);
    _text = selectable;
    selectable.addListener(notifyListeners);
    notifyListeners();
  }

  @override
  void remove(Selectable selectable) {
    assert(_text == selectable);
    selectable.removeListener(notifyListeners);
    _text = null;
    notifyListeners();
  }

  @override
  int get contentLength => _text?.contentLength ?? 0;

  @override
  SelectedContent? getSelectedContent() => _text?.getSelectedContent();

  @override
  SelectedContentRange? getSelection() => _text?.getSelection();

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) =>
      _text?.pushHandleLayers(startHandle, endHandle);

  @override
  void dispose() {
    _text?.removeListener(notifyListeners);
    super.dispose();
  }

  SelectionResult _resultAt(Offset globalPosition) {
    final transform = getTransformTo(null)..invert();
    return SelectionUtils.getResultBasedOnRect(
      Offset.zero & containerSize,
      MatrixUtils.transformPoint(transform, globalPosition),
    );
  }

  /// Move an outside edge past all the text, not merely past the clip: this
  /// clears a selection on the same side and includes the full message when
  /// a selection crosses it on its way to another item.
  Offset _outsideText(SelectionResult result, Offset globalPosition) {
    var bounds = Offset.zero & containerSize;
    if (_text case final text?) {
      final transform = getTransformFrom(text);
      for (final rect in text.boundingBoxes) {
        bounds = bounds.expandToInclude(
          MatrixUtils.transformRect(transform, rect),
        );
      }
    }
    final inverse = getTransformTo(null)..invert();
    if (SelectionUtils.getResultBasedOnRect(
          bounds,
          MatrixUtils.transformPoint(inverse, globalPosition),
        ) ==
        result) {
      return globalPosition;
    }
    final local = result == SelectionResult.previous
        ? bounds.topLeft - const Offset(0, 1)
        : bounds.bottomRight + const Offset(0, 1);
    return MatrixUtils.transformPoint(getTransformTo(null), local);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final text = _text;
    if (text == null) return SelectionResult.none;
    switch (event) {
      case SelectionEdgeUpdateEvent():
        final result = _resultAt(event.globalPosition);
        if (result == SelectionResult.end) {
          return text.dispatchSelectionEvent(event);
        }
        final position = _outsideText(result, event.globalPosition);
        text.dispatchSelectionEvent(
          event.type == SelectionEventType.startEdgeUpdate
              ? SelectionEdgeUpdateEvent.forStart(
                  globalPosition: position,
                  granularity: event.granularity,
                )
              : SelectionEdgeUpdateEvent.forEnd(
                  globalPosition: position,
                  granularity: event.granularity,
                ),
        );
        return result;
      case SelectParagraphSelectionEvent(absorb: true):
        return text.dispatchSelectionEvent(event);
      case SelectWordSelectionEvent(:final globalPosition) ||
          SelectParagraphSelectionEvent(:final globalPosition):
        final result = _resultAt(globalPosition);
        if (result == SelectionResult.end) {
          return text.dispatchSelectionEvent(event);
        }
        text.dispatchSelectionEvent(const ClearSelectionEvent());
        return result;
      default:
        return text.dispatchSelectionEvent(event);
    }
  }

  @override
  SelectionGeometry get value {
    final text = _text;
    if (text == null) {
      return const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: false,
      );
    }
    final geometry = text.value;
    if (!hasSize) return geometry;
    final bounds = Offset.zero & containerSize;
    final transform = getTransformFrom(text);
    SelectionPoint? visible(SelectionPoint? point) {
      if (point == null) return null;
      final local = MatrixUtils.transformPoint(transform, point.localPosition);
      if (!bounds.inflate(0.5).contains(local)) return null;
      return SelectionPoint(
        localPosition: local,
        lineHeight: point.lineHeight,
        handleType: point.handleType,
      );
    }

    return SelectionGeometry(
      startSelectionPoint: visible(geometry.startSelectionPoint),
      endSelectionPoint: visible(geometry.endSelectionPoint),
      selectionRects: [
        for (final rect in geometry.selectionRects)
          if (bounds.intersect(MatrixUtils.transformRect(transform, rect))
              case final clipped when !clipped.isEmpty && clipped.isFinite)
            clipped,
      ],
      status: geometry.status,
      hasContent: geometry.hasContent,
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
