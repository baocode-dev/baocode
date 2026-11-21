import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../chat_find.dart' show ChatFind, ChatFindRow;
import '../selection/chat_selection.dart';

/// A long text's segment (see [markdownSegments]), let go of while far out
/// of the list's view: a box as tall in its place, its text selected and
/// copied whole.
///
/// The list builds what it shows, but a long reply is one of its items: a
/// 240,000-character one held the engine's paragraphs of all of it, some
/// 150MB. Only in an item of the conversation's selection
/// ([ChatSelectionItemScope]), where it does not go while the item holds
/// one of its ends (which would fall in a box), nor while it [keep]s (the
/// segment still written), nor while the row holds the find's match at
/// hand (counted from every segment's marks).
class LazySegment extends StatefulWidget {
  const LazySegment({
    super.key,
    required this.text,
    required this.keep,
    required this.child,
  });

  /// The segment's markdown.
  final String text;
  final bool keep;
  final Widget child;

  /// How far from the view the segment shows again, and is let go of: a
  /// screen or two, for it to be there before it comes into view.
  static const showWithin = 1200.0;
  static const hideBeyond = 2400.0;

  @override
  State<LazySegment> createState() => _LazySegmentState();
}

class _LazySegmentState extends State<LazySegment> {
  bool _hidden = false;
  bool _keep = true;
  ChatSelectionItemScope? _scope;

  /// The segment as last laid out: its height at that width.
  ({String text, double width, double height})? _measured;

  ScrollPosition? _position;
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_checkSoon);
      _position = position?..addListener(_checkSoon);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_checkSoon);
    super.dispose();
  }

  void _laidOut(double width, double height) =>
      _measured = (text: widget.text, width: width, height: height);

  void _checkSoon() {
    if (_checking) return;
    _checking = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checking = false;
      if (mounted) _check();
    });
  }

  void _check() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) return;
    final view = viewport as RenderBox;
    final top = box.localToGlobal(Offset.zero, ancestor: view).dy;
    final bottom = top + box.size.height;
    final extent = view.size.height;
    final distance = top > extent
        ? top - extent
        : bottom < 0
        ? -bottom
        : 0.0;
    if (_hidden) {
      if (distance < LazySegment.showWithin) setState(() => _hidden = false);
      return;
    }
    final measured = _measured;
    final scope = _scope;
    if (distance > LazySegment.hideBeyond &&
        !_keep &&
        measured != null &&
        measured.text == widget.text &&
        measured.width == box.constraints.maxWidth &&
        scope != null &&
        !scope.holdsEnd) {
      setState(() => _hidden = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope = ChatSelectionItemScope.maybeOf(context);
    _keep = widget.keep || scope == null || ChatFindRow.holdsCurrent(context);
    final height = _measured?.height;
    if (_keep || height == null || _measured?.text != widget.text) {
      _hidden = false;
    }
    _checkSoon();
    return _SegmentSlot(
      placeholder: _hidden ? height : null,
      text: widget.text,
      onLaidOut: _laidOut,
      child: _hidden ? null : widget.child,
    );
  }
}

class _SegmentSlot extends SingleChildRenderObjectWidget {
  const _SegmentSlot({
    required this.placeholder,
    required this.text,
    required this.onLaidOut,
    super.child,
  });

  final double? placeholder;
  final String text;
  final void Function(double width, double height) onLaidOut;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSegmentSlot(onLaidOut)
        ..placeholder = placeholder
        ..text = text;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSegmentSlot renderObject,
  ) {
    renderObject
      ..onLaidOut = onLaidOut
      ..placeholder = placeholder
      ..text = text;
  }
}

/// The segment laid out, or, as a [placeholder], a box that tall with its
/// text to select whole.
class _RenderSegmentSlot extends RenderProxyBox implements ChatTextLeafSource {
  _RenderSegmentSlot(this.onLaidOut);

  /// Let go of: its text, whole.
  @override
  ChatTextLeaf? get chatTextLeaf =>
      _placeholder == null ? null : AtomicChatTextLeaf(this, _plainText);

  String? _plainOf;
  String _plain = '';
  String get _plainText {
    if (_plainOf != text) {
      _plainOf = text;
      _plain = ChatFind.markdownText(text).trim();
    }
    return _plain;
  }

  void Function(double width, double height) onLaidOut;

  double? get placeholder => _placeholder;
  double? _placeholder;
  set placeholder(double? value) {
    if (value == _placeholder) return;
    _placeholder = value;
    markNeedsLayout();
  }

  String text = '';

  bool get _shown => _placeholder == null && child != null;

  @override
  void performLayout() {
    if (!_shown) {
      size = constraints.constrain(
        Size(constraints.maxWidth, _placeholder ?? 0),
      );
      return;
    }
    child!.layout(constraints, parentUsesSize: true);
    size = child!.size;
    onLaidOut(constraints.maxWidth, size.height);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _shown
      ? child!.getDryLayout(constraints)
      : constraints.constrain(Size(constraints.maxWidth, _placeholder ?? 0));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _shown ? super.computeMinIntrinsicHeight(width) : (_placeholder ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _shown ? super.computeMaxIntrinsicHeight(width) : (_placeholder ?? 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shown) super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _shown && super.hitTestChildren(result, position: position);
}
