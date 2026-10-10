import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import '../composer/composer_embeds.dart';
import '../user_message_style.dart';
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

  /// The bubble in [item] (an item of the history, laid out): where it is
  /// on screen and its outline, for [UserMessageEditMorph] to open from.
  static UserMessageFrame? frameIn(RenderObject item) {
    _RenderWidthFactor? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is _RenderWidthFactor) {
        found = node;
      } else {
        node.visitChildren(visit);
      }
    }

    visit(item);
    final box = found?.child;
    if (box == null || !box.attached || !box.hasSize) return null;
    final fitted = UserMessageStyle.current.value == UserMessageStyle.bubble;
    return (
      rect: box.localToGlobal(Offset.zero) & box.size,
      radius: fitted ? _MessageShape.radius : radius,
      tail: fitted ? 1.0 : 0.0,
    );
  }

  @override
  State<UserMessageBubble> createState() => _UserMessageBubbleState();
}

/// A message's bubble: where it is on screen, its corners' radius, and how
/// much of a tail it has (see [UserMessageStyle.bubble]).
typedef UserMessageFrame = ({Rect rect, double radius, double tail});

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

/// [text], its tokens and references to its [images] as tags; after it,
/// tags for the images it does not refer to. The tags open the images:
/// there are no thumbnails.
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
  final tagged = {
    for (final op in ops)
      if (op.data case {ComposerImageEmbed.type: final data})
        ComposerImageEmbed.decode(data),
  };
  // Numbered as they would be in the text; one sent before images were
  // numbered by its place among them.
  final untagged = [
    for (final (i, image) in images.indexed)
      if (!tagged.contains(image.number)) (image.number ?? i + 1, image),
  ];
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
          {ComposerPastedTextEmbed.type: final data} =>
            ComposerPastedTextChip.span(data, _messageStyle),
          final Map<dynamic, dynamic> data => ComposerTokenChip.span(
            data[ComposerTokenEmbed.type],
            _messageStyle,
          ),
          _ => const TextSpan(),
        },
      for (final (i, (number, image)) in untagged.indexed) ...[
        if (i > 0 || text.isNotEmpty) const TextSpan(text: ' '),
        ComposerImageChip.span(number, image, _messageStyle),
      ],
    ],
  );
}

class _UserMessageBubbleState extends State<UserMessageBubble> {
  final _selection = _MessageSelectionDelegate();
  Offset? _pressedAt;

  /// The bubble's, moved rather than built anew as the message leaves the
  /// queue: a selection container built anew around [_selection] would ask
  /// it about text still laid out in the old one, before it has a size of
  /// its own, and fail to build.
  final GlobalKey _bubbleKey = GlobalKey();

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
    return ValueListenableBuilder(
      valueListenable: UserMessageStyle.current,
      builder: (context, style, _) => _build(context, style),
    );
  }

  Widget _build(BuildContext context, UserMessageStyle style) {
    final fitted = style == UserMessageStyle.bubble;
    final message = KeyedSubtree(
      key: _bubbleKey,
      child: _buildBubble(context, fitted: fitted),
    );
    // As tall a tree either way, the bubble moving nowhere as the style
    // changes. Fitted: at the right, as wide as its text up to most of the
    // column; the Align takes the column's width, which centers what is
    // narrower.
    final bubble = Align(
      alignment: Alignment.centerRight,
      child: _WidthFactor(
        maxWidthFactor: fitted ? _fittedWidth : 1,
        child: message,
      ),
    );
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

  /// The most of the column a [UserMessageStyle.bubble] bubble takes.
  static const _fittedWidth = 0.85;

  Widget _buildBubble(BuildContext context, {required bool fitted}) {
    final vocabulary = ComposerVocabulary.of(context);
    return Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: (_) => _pressedAt = null,
      child: ImagePressScope(
        onPress: () => _pressOnImage = true,
        child: Container(
          // Constraints either way: a Container without them leaves out their
          // box, building its child anew as the style changes.
          constraints: fitted
              ? const BoxConstraints()
              : const BoxConstraints.tightFor(width: double.infinity),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          // As its editor and viewer: the chat input's.
          decoration: fitted
              ? ShapeDecoration(
                  color: AppColors.bubbleFill,
                  shape: _MessageShape(
                    side: BorderSide(color: AppColors.bubbleBorder()),
                  ),
                )
              : BoxDecoration(
                  color: AppColors.bubbleFill,
                  borderRadius: BorderRadius.circular(UserMessageBubble.radius),
                  border: Border.all(color: AppColors.bubbleBorder()),
                ),
          child: SelectionContainer(
            delegate: _selection,
            child: _Collapsed(
              shrinkWrap: fitted,
              collapsedHeight: _lineHeight * _collapsedLines,
              collapseAbove: _lineHeight * (_collapsedLines + 1),
              content: InlineCodeText(
                _messageSpan(widget.text, vocabulary, widget.images),
              ),
              overlay: const _CollapsedOverlay(),
            ),
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
    final UserMessageViewer(:text, :images, :controller) = widget;
    final vocabulary = ComposerVocabulary.of(context);
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
          // The editor's (see ChatComposer).
          color: AppColors.bubbleFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.bubbleBorder()),
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
                    child: InlineCodeText(
                      _messageSpan(text, vocabulary, images),
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

  /// Text built anew comes in before the text it replaces goes (that goes
  /// once the frame is built): the newer one stays.
  @override
  void add(Selectable selectable) {
    _text?.removeListener(notifyListeners);
    _text = selectable;
    selectable.addListener(notifyListeners);
    notifyListeners();
  }

  @override
  void remove(Selectable selectable) {
    selectable.removeListener(notifyListeners);
    if (selectable != _text) return;
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
    required this.shrinkWrap,
    required this.collapsedHeight,
    required this.collapseAbove,
    required Widget content,
    required Widget overlay,
  }) : super(children: [content, overlay]);

  /// As wide as the text, rather than as the room it has.
  final bool shrinkWrap;
  final double collapsedHeight;
  final double collapseAbove;

  @override
  _RenderCollapsed createRenderObject(BuildContext context) =>
      _RenderCollapsed(shrinkWrap, collapsedHeight, collapseAbove);

  @override
  void updateRenderObject(BuildContext context, _RenderCollapsed renderObject) {
    renderObject
      ..shrinkWrap = shrinkWrap
      ..collapsedHeight = collapsedHeight
      ..collapseAbove = collapseAbove;
  }
}

class _CollapsedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCollapsed extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CollapsedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CollapsedParentData> {
  _RenderCollapsed(
    this._shrinkWrap,
    this._collapsedHeight,
    this._collapseAbove,
  );

  bool _shrinkWrap;
  set shrinkWrap(bool value) {
    if (value == _shrinkWrap) return;
    _shrinkWrap = value;
    markNeedsLayout();
  }

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
      Size(
        _shrinkWrap ? _content.size.width : constraints.maxWidth,
        _collapsed ? _collapsedHeight : full,
      ),
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

/// Lets its child be at most [maxWidthFactor] of the width it is given.
class _WidthFactor extends SingleChildRenderObjectWidget {
  const _WidthFactor({required this.maxWidthFactor, super.child});

  final double maxWidthFactor;

  @override
  _RenderWidthFactor createRenderObject(BuildContext context) =>
      _RenderWidthFactor(maxWidthFactor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWidthFactor renderObject,
  ) {
    renderObject.maxWidthFactor = maxWidthFactor;
  }
}

class _RenderWidthFactor extends RenderProxyBox {
  _RenderWidthFactor(this._maxWidthFactor);

  double _maxWidthFactor;
  set maxWidthFactor(double value) {
    if (value == _maxWidthFactor) return;
    _maxWidthFactor = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    if (_maxWidthFactor == 1 || !constraints.hasBoundedWidth) {
      return constraints;
    }
    final maxWidth = constraints.maxWidth * _maxWidthFactor;
    return constraints.copyWith(
      minWidth: math.min(constraints.minWidth, maxWidth),
      maxWidth: maxWidth,
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      child.getDryLayout(_childConstraints(constraints)),
    );
  }
}

/// A [UserMessageStyle.bubble] bubble's outline: its editor's corners
/// (see ChatComposer), and a tail hooked out of its bottom right, toward
/// its sender, as a chat's. The tail takes a strip at the right
/// ([dimensions]), the body the rest.
class _MessageShape extends OutlinedBorder {
  const _MessageShape({super.side});

  static const radius = 10.0;
  static const tailWidth = 7.0;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.only(right: tailWidth);

  @override
  _MessageShape copyWith({BorderSide? side}) =>
      _MessageShape(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => _MessageShape(side: side.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  /// The outline in [rect], with [tail] of the tail (0: none, a rounded
  /// rectangle's corner in its place) and corners of [radius].
  static Path _path(Rect rect, {double tail = 1, double radius = radius}) {
    final r = radius;
    final Rect(:left, :top, :right, :bottom) = rect;
    final body = right - tailWidth * tail;
    // The bottom right corner, from the body's side, as three curves: the
    // tail's (down the body's side and out to its tip, back under it, up
    // into the body and round the rest of the corner)...
    final p0 = Offset(body - 3.5, bottom - 2.5);
    final q = Offset(body - 6, bottom);
    final p1 = Offset(body - r, bottom);
    final hooked = [
      Offset(body, bottom - 6),
      Offset(body + 2, bottom - 1),
      Offset(body + tailWidth, bottom),
      Offset(body + tailWidth - 4, bottom + 0.5),
      Offset(body - 1, bottom - 0.5),
      p0,
      p0 + (q - p0) * (2 / 3),
      p1 + (q - p1) * (2 / 3),
      p1,
    ];
    // ...or a plain corner's: on down the side, and its arc in two halves.
    final center = Offset(body - r, bottom - r);
    final h = 0.26521 * r;
    const s = math.sqrt1_2;
    final middle = center + Offset(r * s, r * s);
    final end = Offset(body - r, bottom);
    final plain = [
      Offset(body, bottom - 16 + (16 - r) / 3),
      Offset(body, bottom - 16 + (16 - r) * 2 / 3),
      Offset(body, bottom - r),
      Offset(body, bottom - r + h),
      middle + Offset(h * s, -h * s),
      middle,
      middle + Offset(-h * s, h * s),
      end + Offset(h, 0),
      end,
    ];
    final corner = [
      for (var i = 0; i < hooked.length; i++)
        Offset.lerp(plain[i], hooked[i], tail)!,
    ];
    final path = Path()
      ..moveTo(left + r, top)
      ..lineTo(body - r, top)
      ..arcToPoint(Offset(body, top + r), radius: Radius.circular(r))
      ..lineTo(body, bottom - 16);
    for (var i = 0; i < corner.length; i += 3) {
      path.cubicTo(
        corner[i].dx,
        corner[i].dy,
        corner[i + 1].dx,
        corner[i + 1].dy,
        corner[i + 2].dx,
        corner[i + 2].dy,
      );
    }
    return path
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  bool operator ==(Object other) =>
      other is _MessageShape && other.side == side;

  @override
  int get hashCode => side.hashCode;
}

/// A message opening for editing: its editor ([child]), in the outline of
/// the bubble it opens from ([from], see [UserMessageBubble.frameIn]), which
/// grows into the editor's own as [progress] goes from 0 to 1, the editor's
/// contents coming in. One frame, from the bubble's to the editor's, its
/// line turning to [border]; at 1, the editor's own.
///
/// [closing], it goes back the other way, over the message back in its
/// place: from a bubble, what it fills fades with the editor's contents,
/// into the message's.
class UserMessageEditMorph extends SingleChildRenderObjectWidget {
  const UserMessageEditMorph({
    super.key,
    required this.from,
    required this.progress,
    required this.border,
    this.closing = false,
    super.child,
  });

  final UserMessageFrame from;
  final double progress;
  final Color border;
  final bool closing;

  /// The editor's corners (see ChatComposer).
  static const radius = 10.0;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEditMorph(
    from: from,
    progress: progress,
    fill: AppColors.bubbleFill,
    fromBorder: AppColors.bubbleBorder(),
    border: border,
    closing: closing,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    renderObject as _RenderEditMorph
      ..from = from
      ..progress = progress
      ..fill = AppColors.bubbleFill
      ..fromBorder = AppColors.bubbleBorder()
      ..border = border
      ..closing = closing;
  }
}

class _RenderEditMorph extends RenderProxyBox {
  _RenderEditMorph({
    required this._from,
    required this._progress,
    required this._fill,
    required this._fromBorder,
    required this._border,
    required this._closing,
  });

  UserMessageFrame _from;
  set from(UserMessageFrame value) {
    if (value == _from) return;
    _from = value;
    _fromHere = null;
    markNeedsPaint();
  }

  /// [_from]'s rect where this was first painted: it moves with this after,
  /// as the list scrolls.
  Rect? _fromHere;

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsPaint();
  }

  Color _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color _fromBorder;
  set fromBorder(Color value) {
    if (value == _fromBorder) return;
    _fromBorder = value;
    markNeedsPaint();
  }

  Color _border;
  set border(Color value) {
    if (value == _border) return;
    _border = value;
    markNeedsPaint();
  }

  bool _closing;
  set closing(bool value) {
    if (value == _closing) return;
    _closing = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipPathLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null && _progress < 1;

  @override
  void paint(PaintingContext context, Offset offset) {
    final t = _progress;
    if (t >= 1 || child == null) {
      _clip.layer = null;
      _opacity.layer = null;
      super.paint(context, offset);
      return;
    }
    final from = _fromHere ??= _from.rect.shift(-localToGlobal(Offset.zero));
    final rect = Rect.lerp(from, Offset.zero & size, t)!;
    final radius =
        _from.radius + (UserMessageEditMorph.radius - _from.radius) * t;
    final tail = _from.tail * (1 - t);
    Path outline(Rect rect) =>
        _MessageShape._path(rect, tail: tail, radius: radius);

    // From a frame as wide as this, the editor's text is where the
    // message's was: it shows from the start. From a narrower one (a bubble)
    // it is not; it comes in over the first part of the way.
    final moves =
        from.left.abs() > 0.5 || (from.right - size.width).abs() > 0.5;
    final alpha = moves
        ? (Curves.easeOut.transform(math.min(1, t * 1.5)) * 255).round()
        : 255;
    context.canvas.drawPath(
      outline(rect).shift(offset),
      Paint()
        ..color = _closing
            ? _fill.withValues(alpha: _fill.a * alpha / 255)
            : _fill,
    );
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      rect,
      outline(rect),
      (context, offset) {
        if (alpha == 255) {
          _opacity.layer = null;
          super.paint(context, offset);
          return;
        }
        _opacity.layer = context.pushOpacity(
          offset,
          alpha,
          super.paint,
          oldLayer: _opacity.layer,
        );
      },
      oldLayer: _clip.layer,
    );
    context.canvas.drawPath(
      outline(rect.deflate(0.5)).shift(offset),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color.lerp(_fromBorder, _border, t)!,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _opacity.layer = null;
    super.dispose();
  }
}
