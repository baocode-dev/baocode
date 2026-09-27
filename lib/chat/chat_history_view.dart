import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../theme/cursor_theme.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'widgets/chat_item_view.dart';
import 'widgets/edge_fade_mask.dart';
import 'widgets/user_message_bubble.dart';

/// Virtualized, selectable conversation history followed by the live turn.
/// Sticks to the bottom while the user is there.
class ChatHistoryView extends StatefulWidget {
  const ChatHistoryView({
    super.key,
    required this.session,
    this.maxContentWidth = 760,
  });

  final ChatSession session;
  final double maxContentWidth;

  @override
  State<ChatHistoryView> createState() => _ChatHistoryViewState();
}

class _ChatHistoryViewState extends State<ChatHistoryView> {
  final _BottomAnchoredScrollController _scrollController =
      _BottomAnchoredScrollController();
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'Monad chat selection',
  );

  /// Thoughts the user opened (true) or closed (false). Others are open
  /// while they stream and closed once done.
  final Map<int, bool> _thinkingExpanded = {};

  /// The user message open for editing, if any, and the text it started
  /// from. The editor lives above the list (see [_buildEditorLayer]); the
  /// list holds a placeholder of its height.
  int? _editingIndex;
  String _editingText = '';
  final GlobalKey _editorPlaceholderKey = GlobalKey();
  double _editorHeight = 0;
  final Object _editorTapRegion = Object();
  GlobalKey<ChatComposerState> _editComposerKey = GlobalKey();

  /// Pinged when the placeholder may have moved without a scroll.
  final ValueNotifier<int> _editorMoved = ValueNotifier(0);

  /// User messages with a copy ready to stick to the top: the one of the
  /// turn at the top of the view, and every one laid out, any of which the
  /// next scroll may bring there. The copy of the turn at the top shows once
  /// its message has scrolled past (see [_stickyTop]).
  Set<int> _stickyIndices = const {};
  bool _stickyUpdateScheduled = false;
  final Map<int, GlobalKey> _stickyKeys = {};

  /// The current press started in the message editor: it takes focus
  /// itself, the history must not.
  bool _pressInEditor = false;
  bool _isPointerInside = false;
  bool _wasStreaming = false;
  bool _shownAtBottom = true;

  /// Content extends below the viewport, so the bottom fade is needed. Unlike
  /// [_atBottom] this has no tolerance: a few pixels of overflow still show.
  bool _contentBelow = false;
  bool _contentAbove = false;

  /// Pointer held down in the list (drag, scrollbar) or a wheel event just
  /// arrived: only then does a scroll change whether we stick to the bottom.
  int _pointersDown = 0;

  late final _ChatSelectionDelegate _selectionDelegate = _ChatSelectionDelegate(
    locate: _locateItemPoint,
    resolve: _resolveItemPoint,
    beyondBuilt: _beyondBuiltItems,
    plainTextOf: (index) => chatItemPlainText(
      _session.itemAt(index),
      expanded: _isThinkingExpanded(index),
    ),
    onDragEdge: _autoScrollToward,
  );
  bool _reselectScheduled = false;
  Timer? _reselectTimer;
  EdgeDraggingAutoScroller? _autoScroller;

  final GlobalKey _listKey = GlobalKey();
  DateTime _lastWheel = DateTime(0);

  ChatSession get _session => widget.session;
  bool get _atBottom => _scrollController.anchored;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _session.addListener(_handleSessionChanged);
  }

  @override
  void didUpdateWidget(ChatHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_handleSessionChanged);
      widget.session.addListener(_handleSessionChanged);
    }
  }

  static const Map<ShortcutActivator, Intent> _selectionShortcuts = {
    SingleActivator(LogicalKeyboardKey.keyA, meta: true): SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
    SingleActivator(LogicalKeyboardKey.keyA, control: true):
        SelectAllTextIntent(SelectionChangedCause.keyboard),
    SingleActivator(LogicalKeyboardKey.keyC, meta: true):
        CopySelectionTextIntent.copy,
    SingleActivator(LogicalKeyboardKey.keyC, control: true):
        CopySelectionTextIntent.copy,
  };

  @override
  void dispose() {
    _session.removeListener(_handleSessionChanged);
    _reselectTimer?.cancel();
    _autoScroller?.stopAutoScroll();
    _editorMoved.dispose();
    _selectionDelegate.dispose();
    _scrollController.dispose();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  bool _isThinkingExpanded(int index) =>
      _thinkingExpanded[index] ??
      switch (_session.itemAt(index)) {
        ThinkingItem(:final streaming) => streaming,
        _ => false,
      };

  void _toggleThinking(int index) {
    setState(() => _thinkingExpanded[index] = !_isThinkingExpanded(index));
  }

  bool get _userScrolling =>
      _pointersDown > 0 ||
      DateTime.now().difference(_lastWheel) < const Duration(milliseconds: 250);

  void _handleScroll() {
    if (_userScrolling) {
      final position = _scrollController.position;
      // Re-anchor only at the very end: any tolerance would snap a small
      // scroll up straight back to the bottom on the next layout.
      _scrollController.anchored =
          position.pixels >= position.maxScrollExtent - 1;
    }
    if (_shownAtBottom != _atBottom) {
      setState(() => _shownAtBottom = _atBottom);
    }
    _syncEdgeFades();
    _scheduleStickyUpdate();
    if (_pointersDown > 0) _scheduleDragReselect();
  }

  /// Flutter only extends a drag selection when the pointer moves (or on its
  /// own edge auto-scroll). Scrolling with the wheel or trackpad mid-drag
  /// moves content under a still pointer, so the next move jumps the end
  /// across many items at once and the ones in between (some just built)
  /// are left unselected. Re-apply the drag end after every scroll step, once
  /// layout has registered the new items (after the frame's microtasks).
  void _scheduleDragReselect() {
    if (_reselectScheduled) return;
    _reselectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reselectTimer = Timer(Duration.zero, () {
        _reselectScheduled = false;
        if (mounted && _pointersDown > 0) _selectionDelegate.reapplyDragEnd();
      });
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointersDown++;
    if (_pressInEditor) {
      _pressInEditor = false;
    } else {
      _selectionFocusNode.requestFocus();
    }
    // Shift+click extends the selection (desktop only, as in Flutter).
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => true,
      _ => false,
    };
    _selectionDelegate.extending =
        desktop &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        HardwareKeyboard.instance.isShiftPressed;
  }

  void _handlePointerUp(PointerEvent event) {
    _pointersDown--;
    if (_pointersDown <= 0) {
      _autoScroller?.stopAutoScroll();
      _selectionDelegate
        ..endDrag()
        ..extending = false;
    }
  }

  /// Scrolls while a drag selection is held near or past an edge, as the
  /// list's own selection handling would (see [_ChatSelectionDelegate]).
  void _autoScrollToward(Offset globalPosition) {
    if (_pointersDown <= 0 || !_scrollController.hasClients) return;
    final scrollable = _scrollController.position.context as ScrollableState;
    if (_autoScroller?.scrollable != scrollable) {
      _autoScroller?.stopAutoScroll();
      _autoScroller = EdgeDraggingAutoScroller(
        scrollable,
        onScrollViewScrolled: _selectionDelegate.reapplyDragEnd,
        velocityScalar: 30,
      );
    }
    _autoScroller!.startAutoScrollIfNecessary(
      Rect.fromCenter(center: globalPosition, width: 0, height: 0),
    );
  }

  // --- Item-relative selection points --------------------------------------

  RenderSliverMultiBoxAdaptor? _findSliver() {
    RenderSliverMultiBoxAdaptor? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderSliverMultiBoxAdaptor) {
        found = object;
      } else {
        object.visitChildren(visit);
      }
    }

    final root = _listKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  /// Laid-out items (built and positioned, not merely kept alive).
  Iterable<RenderBox> _laidOutItems() sync* {
    final sliver = _findSliver();
    if (sliver == null || !sliver.attached) return;
    for (var child = sliver.firstChild; child != null;) {
      if (child.hasSize) yield child;
      child = sliver.childAfter(child);
    }
  }

  static int _indexOf(RenderBox item) =>
      (item.parentData! as SliverMultiBoxAdaptorParentData).index!;

  /// The item under (or nearest to) [globalPosition] and the point within it.
  _ItemPoint? _locateItemPoint(Offset globalPosition) {
    RenderBox? best;
    var bestDistance = double.infinity;
    for (final item in _laidOutItems()) {
      final top = item.localToGlobal(Offset.zero).dy;
      final bottom = top + item.size.height;
      final distance = globalPosition.dy < top
          ? top - globalPosition.dy
          : globalPosition.dy > bottom
          ? globalPosition.dy - bottom
          : 0.0;
      if (distance < bestDistance) {
        best = item;
        bestDistance = distance;
        if (distance == 0) break;
      }
    }
    if (best == null) return null;
    return (index: _indexOf(best), local: best.globalToLocal(globalPosition));
  }

  /// Where [point] is now, or null when its item is not laid out.
  Offset? _resolveItemPoint(_ItemPoint point) {
    for (final item in _laidOutItems()) {
      if (_indexOf(item) == point.index) return item.localToGlobal(point.local);
    }
    return null;
  }

  /// A point just past the laid-out items on the side of the unbuilt item
  /// [index]: above the first for an earlier item, below the last for a
  /// later one. A selection edge there covers every built item on that side.
  Offset? _beyondBuiltItems(int index) {
    RenderBox? first;
    RenderBox? last;
    for (final item in _laidOutItems()) {
      first ??= item;
      last = item;
    }
    if (first == null || last == null) return null;
    if (index < _indexOf(first)) {
      return first.localToGlobal(Offset.zero) - const Offset(0, 1);
    }
    return last.localToGlobal(last.size.bottomRight(Offset.zero)) +
        const Offset(0, 1);
  }

  void _syncEdgeFades() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    final below = position.pixels < position.maxScrollExtent - 0.5;
    final above = position.pixels > position.minScrollExtent + 0.5;
    if (below != _contentBelow || above != _contentAbove) {
      setState(() {
        _contentBelow = below;
        _contentAbove = above;
      });
    }
  }

  bool _handleMetricsChanged(ScrollMetricsNotification notification) {
    _syncEdgeFades();
    _scheduleStickyUpdate();
    _editorMoved.value++;
    return false;
  }

  void _setAnchored(bool value) {
    _scrollController.anchored = value;
    if (_shownAtBottom != value) setState(() => _shownAtBottom = value);
  }

  void _handleSessionChanged() {
    // Sending a message always brings the live turn into view.
    final startedStreaming = _session.isStreaming && !_wasStreaming;
    _wasStreaming = _session.isStreaming;
    final editing = _editingIndex;
    if (startedStreaming ||
        (editing != null &&
            (editing >= _session.itemCount ||
                _session.itemAt(editing) is! UserMessageItem))) {
      _editingIndex = null;
    }
    if (startedStreaming) _jumpToBottom();
    _scheduleStickyUpdate();
    setState(() {});
  }

  void _startEditing(int index) {
    final item = _session.itemAt(index);
    if (item is! UserMessageItem) return;
    // Until the editor reports its height, hold the message's.
    final laidOut = _laidOutItems().where((box) => _indexOf(box) == index);
    setState(() {
      _editingIndex = index;
      _editingText = item.text;
      _editComposerKey = GlobalKey();
      _editorHeight = laidOut.isEmpty
          ? 0
          : laidOut.first.size.height - _gapBefore(index);
    });
  }

  void _cancelEditing() {
    if (_editingIndex != null) setState(() => _editingIndex = null);
  }

  void _setEditorHeight(double height) {
    if (height == _editorHeight || _editingIndex == null) return;
    setState(() => _editorHeight = height);
    _editorMoved.value++;
  }

  /// Where the editor goes, relative to [layer]: on its placeholder, but
  /// never above the top of the list (it sticks there once scrolled past).
  /// Null when the placeholder is below the built items, out of view.
  double? _editorTop(RenderBox layer) {
    const inset = 8.0;
    final placeholder =
        _editorPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;
    if (placeholder != null && placeholder.attached && placeholder.hasSize) {
      final top =
          placeholder.localToGlobal(Offset.zero).dy -
          layer.localToGlobal(Offset.zero).dy;
      return math.max(top, inset);
    }
    final first = _laidOutItems().firstOrNull;
    final index = _editingIndex;
    if (first != null && index != null && index < _indexOf(first)) return inset;
    return null;
  }

  // --- The sticky user message ---------------------------------------------

  /// Room above the stuck message, as above the editor stuck to the top.
  static const _stickyInset = 8.0;

  /// Height of the fade under the stuck message, over the transcript
  /// scrolling beneath it.
  static const _stickyFade = 16.0;

  /// Which copies are built is settled after layout, with the items where
  /// the scroll put them: a frame late, but ready before any scroll brings
  /// their message to the top. Which one shows, and where, is read at paint
  /// ([_stickyTop]), so a copy takes over in the very frame its message
  /// scrolls past.
  void _scheduleStickyUpdate() {
    if (_stickyUpdateScheduled) return;
    _stickyUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickyUpdateScheduled = false;
      if (!mounted) return;
      final indices = {
        ?_topTurnMessage(),
        for (final item in _laidOutItems())
          if (_session.itemAt(_indexOf(item)) is UserMessageItem)
            _indexOf(item),
      };
      if (setEquals(indices, _stickyIndices)) return;
      _stickyKeys.removeWhere((index, _) => !indices.contains(index));
      setState(() => _stickyIndices = indices);
    });
  }

  /// The user message of the turn at the top of the view: the last one
  /// scrolled past the top. (It keeps the top while the next one, below,
  /// pushes it away.)
  int? _topTurnMessage() {
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (list == null || !list.attached || !list.hasSize) return null;
    int? first;
    int? passed;
    for (final item in _laidOutItems()) {
      final index = _indexOf(item);
      first ??= index;
      if (_session.itemAt(index) is! UserMessageItem) continue;
      if (_messageTop(index, list)! >= _stickyInset) break;
      passed = index;
    }
    if (passed != null || first == null) return passed;
    // Scrolled past long ago: above the laid-out items.
    for (var index = first - 1; index >= 0; index--) {
      if (_session.itemAt(index) is UserMessageItem) return index;
    }
    return null;
  }

  /// Top of the laid-out message [index] (below its gap), relative to the
  /// [list]; null when it is not laid out. Measured within the list, which
  /// is laid out when this is read from the sticky's layout (its ancestors
  /// may not be yet).
  double? _messageTop(int index, RenderBox list) {
    for (final item in _laidOutItems()) {
      if (_indexOf(item) != index) continue;
      return item
          .localToGlobal(Offset(0, _gapBefore(index)), ancestor: list)
          .dy;
    }
    return null;
  }

  /// Where the stuck message goes (its layer and the list share their top):
  /// at the top once its own copy has scrolled past, pushed up and away by
  /// the next message. Null (not shown) while its own copy is in place.
  double? _stickyTop(int index) {
    if (_topTurnMessage() != index) return null;
    final sticky =
        _stickyKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (sticky == null || !sticky.hasSize || list == null) return null;
    for (final item in _laidOutItems()) {
      final next = _indexOf(item);
      if (next <= index || _session.itemAt(next) is! UserMessageItem) {
        continue;
      }
      final nextTop = _messageTop(next, list)!;
      if (nextTop <= 0) return null;
      return math.min(0.0, nextTop - sticky.size.height);
    }
    return 0;
  }

  Widget _buildSticky(int index) {
    final item = _session.itemAt(index) as UserMessageItem;
    // A copy of the message in the list: not read out twice.
    return ExcludeSemantics(
      child: ClipRect(
        child: _StickyFollower(
          top: (_) => _stickyTop(index),
          repaint: Listenable.merge([_scrollController, _editorMoved]),
          child: Align(
            alignment: Alignment.topCenter,
            child: Listener(
              // Not in the list: pass scrolling on.
              onPointerSignal: _forwardWheel,
              onPointerPanZoomStart: _startEditorPan,
              onPointerPanZoomUpdate: _updateEditorPan,
              onPointerPanZoomEnd: _endEditorPan,
              child: Column(
                key: _stickyKeys.putIfAbsent(index, GlobalKey.new),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Over the transcript scrolling beneath: the page's own
                  // color, fading out below.
                  ColoredBox(
                    color: CursorColors.background,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        _stickyInset,
                        24,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: widget.maxContentWidth,
                          ),
                          child: UserMessageBubble(
                            key: ValueKey(('sticky', index)),
                            text: item.text,
                            onEdit: () => _startEditing(index),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const IgnorePointer(
                    child: SizedBox(
                      height: _stickyFade,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              CursorColors.background,
                              Color(0x00181818),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorLayer(int index) {
    return Positioned.fill(
      // The editor's text area scrolls on its own. It is not inside the list,
      // so its scroll notifications would reach the history's scrollbar as
      // if they were the list's (depth 0) and move its thumb: keep them here.
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) => true,
          child: ClipRect(
            child: _StickyFollower(
              top: _editorTop,
              repaint: Listenable.merge([_scrollController, _editorMoved]),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.maxContentWidth,
                    ),
                    child: _SizeReporter(
                      onSize: (size) => _setEditorHeight(size.height),
                      // Lifted off the transcript: it floats over it when
                      // stuck to the top. (Outside the reported size.)
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            // Dark UI: a deep, soft drop plus a tight contact
                            // shadow, or it does not read against the page.
                            BoxShadow(
                              color: Color(0xA6000000),
                              blurRadius: 32,
                              offset: Offset(0, 12),
                            ),
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Listener(
                          // The editor takes focus itself; see _handlePointerDown.
                          onPointerDown: (_) => _pressInEditor = true,
                          // The editor is not in the list: pass the wheel on.
                          onPointerSignal: _forwardWheel,
                          onPointerPanZoomStart: _startEditorPan,
                          onPointerPanZoomUpdate: _updateEditorPan,
                          onPointerPanZoomEnd: _endEditorPan,
                          child: TapRegion(
                            groupId: _editorTapRegion,
                            onTapOutside: (_) => _cancelEditing(),
                            child: ChatComposer(
                              key: _editComposerKey,
                              session: _session,
                              initialText: _editingText,
                              tapRegionGroupId: _editorTapRegion,
                              onSubmit: (message) =>
                                  _submitEdit(index, message),
                              onCancel: _cancelEditing,
                            ),
                          ),
                        ),
                      ),
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

  // --- Scrolling over the editor ------------------------------------------
  //
  // The editor is above the list, not in it, so the list never sees a wheel
  // or trackpad scroll over the editor. Like CSS `overscroll-behavior:
  // contain`: while the editor's text area has anything to scroll, scrolling
  // over the editor scrolls only that, and stops at its ends; nothing spills
  // over into the list (its momentum would move the page on its own). Only a
  // text area with nothing to scroll passes scrolling on to the list, or the
  // editor stuck to the top would be a dead spot for scrolling the page.

  /// Whether the editor's text area has anything to scroll.
  bool get _editorScrolls {
    final inner = _editComposerKey.currentState?.editorScrollPosition;
    return inner != null && inner.maxScrollExtent > inner.minScrollExtent;
  }

  void _forwardWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    if (_editorScrolls) return; // The text area's, even at its ends.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      _scrollController.position.pointerScroll(
        (event as PointerScrollEvent).scrollDelta.dy,
      );
    });
  }

  VelocityTracker? _editorPanVelocity;
  double _editorPanForwarded = 0;

  void _startEditorPan(PointerPanZoomStartEvent event) {
    _editorPanVelocity = VelocityTracker.withKind(event.kind);
    _editorPanForwarded = 0;
  }

  void _updateEditorPan(PointerPanZoomUpdateEvent event) {
    if (!_scrollController.hasClients || _editorScrolls) return;
    // Fingers moving down reveal what is above: the offset goes down.
    final delta = -event.panDelta.dy;
    if (delta == 0) return;
    final position = _scrollController.position;
    _lastWheel = DateTime.now(); // Counts as the user scrolling.
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _editorPanForwarded += delta;
    _editorPanVelocity?.addPosition(
      event.timeStamp,
      Offset(0, _editorPanForwarded),
    );
  }

  void _endEditorPan(PointerPanZoomEndEvent event) {
    final tracker = _editorPanVelocity;
    _editorPanVelocity = null;
    if (tracker == null || _editorPanForwarded == 0) return;
    if (!_scrollController.hasClients) return;
    final velocity = tracker.getVelocity().pixelsPerSecond.dy;
    final position = _scrollController.position;
    if (velocity.abs() > kMinFlingVelocity &&
        position is ScrollPositionWithSingleContext) {
      _lastWheel = DateTime.now();
      position.goBallistic(velocity);
    }
  }

  void _submitEdit(int index, ComposerMessage message) {
    setState(() {
      _editingIndex = null;
      // Everything after the message is replaced; so are its thoughts.
      _thinkingExpanded.removeWhere((i, _) => i > index);
    });
    _session.editMessage(index, message);
  }

  Widget _buildItem(int index) {
    final item = _session.itemAt(index);
    if (index == _editingIndex) {
      return SizedBox(key: _editorPlaceholderKey, height: _editorHeight);
    }
    return _ItemSelectionScope(
      index: index,
      delegate: _selectionDelegate,
      child: ChatItemView(
        key: ValueKey(index),
        item: item,
        expanded: _isThinkingExpanded(index),
        onToggle: () => _toggleThinking(index),
        onEdit: item is UserMessageItem ? () => _startEditing(index) : null,
      ),
    );
  }

  void _jumpToBottom() {
    _setAnchored(true);
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      position.jumpTo(position.maxScrollExtent);
    }
  }

  void _setPointerInside(bool value) {
    if (_isPointerInside != value) setState(() => _isPointerInside = value);
  }

  /// Vertical gap above [index]: roomy between turns, tight between tool rows.
  double _gapBefore(int index) {
    if (index == 0) return 0;
    final item = _session.itemAt(index);
    final previous = _session.itemAt(index - 1);
    if (item is UserMessageItem) return 32;
    if (previous is UserMessageItem) return 14;
    if (item is ToolCallItem && previous is ToolCallItem) return 0;
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _selectionShortcuts,
      child: SelectionArea(
        focusNode: _selectionFocusNode,
        // Focus on click rather than hover so the composer keeps focus while
        // the pointer passes over the history.
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerUp,
          // Runs before the list handles the signal (that is resolved after
          // every target has seen it).
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            _lastWheel = DateTime.now();
            _scrollController.signalKind = event.kind;
          },
          child: SelectionContainer(
            delegate: _selectionDelegate,
            child: MouseRegion(
              onEnter: (_) => _setPointerInside(true),
              onExit: (_) => _setPointerInside(false),
              child: ScrollbarTheme(
                data: ScrollbarTheme.of(context).copyWith(
                  thumbColor: WidgetStatePropertyAll(
                    _isPointerInside
                        ? const Color(0xFF4A4A4A)
                        : Colors.transparent,
                  ),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  // Items register their text with the selection delegate
                  // themselves (see [_ItemSelectionScope]); nothing else in
                  // here is selectable, and the list's own selection handling
                  // (which can only see built items) stays out of the way.
                  child: SelectionContainer.disabled(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NotificationListener<ScrollMetricsNotification>(
                          onNotification: _handleMetricsChanged,
                          // Soft fades where content continues past an edge
                          // (none when nothing is there, e.g. pinned to the
                          // bottom).
                          child: EdgeFadeMask(
                            top: _contentAbove,
                            bottom: _contentBelow,
                            child: SuperListView.builder(
                              key: _listKey,
                              controller: _scrollController,
                              itemCount: _session.itemCount,
                              cacheExtent: 900,
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                20,
                                24,
                                24,
                              ),
                              itemBuilder: (context, index) {
                                return Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: widget.maxContentWidth,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: _gapBefore(index),
                                      ),
                                      child: _buildItem(index),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        for (final index in _stickyIndices)
                          if (index != _editingIndex &&
                              index < _session.itemCount &&
                              _session.itemAt(index) is UserMessageItem)
                            Positioned.fill(
                              key: ValueKey(('sticky', index)),
                              child: _buildSticky(index),
                            ),
                        if (_editingIndex case final index?)
                          _buildEditorLayer(index),
                        Positioned(
                          right: 0,
                          left: 0,
                          bottom: 12,
                          child: Center(
                            child: _JumpToBottomButton(
                              visible: !_shownAtBottom,
                              onTap: _jumpToBottom,
                            ),
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

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.4),
          duration: const Duration(milliseconds: 150),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: CursorColors.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: CursorColors.borderStrong),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 12),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_downward_rounded,
                  size: 15,
                  color: CursorColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the viewport pinned to the end while [anchored], applied during
/// layout so growing content or a shrinking viewport never shows a frame
/// that is off the bottom.
class _BottomAnchoredScrollController extends ScrollController {
  bool anchored = true;

  /// The device of the scroll signal being handled (set before the list
  /// handles it), so only mouse wheels get sped up.
  PointerDeviceKind? signalKind;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _BottomAnchoredScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _BottomAnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _BottomAnchoredScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _BottomAnchoredScrollController controller;

  /// Mouse wheels arrive as small per-notch deltas that make a long
  /// transcript slow to move through. Trackpads keep their native 1:1 feel,
  /// whether they arrive as pan gestures or (on the web) as scroll signals.
  static const wheelSpeed = 1.8;

  @override
  void pointerScroll(double delta) => super.pointerScroll(
    controller.signalKind == PointerDeviceKind.mouse
        ? delta * wheelSpeed
        : delta,
  );

  @override
  void jumpTo(double value) {
    if (hasContentDimensions) {
      controller.anchored = value >= maxScrollExtent - 1;
    }
    super.jumpTo(value);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (controller.anchored &&
        hasPixels &&
        pixels != maxScrollExtent &&
        activity is! DragScrollActivity) {
      // Re-run layout at the new offset; the virtual list may refine its
      // extent estimate for the tail, which converges in a pass or two.
      correctPixels(maxScrollExtent);
      return false;
    }
    return accepted;
  }
}

/// A point inside a list item, stable while the item scrolls, is re-laid out
/// or is rebuilt (unlike a global position, or a scroll offset, which
/// the list shifts as it corrects its estimated item extents).
typedef _ItemPoint = ({int index, Offset local});

/// One end of the selection, in model terms.
typedef _SelectionEdge = ({_ItemPoint point, TextGranularity granularity});

/// Registers the text of item [index] with [delegate], tagged with the index.
class _ItemSelectionScope extends StatefulWidget {
  const _ItemSelectionScope({
    required this.index,
    required this.delegate,
    required this.child,
  });

  final int index;
  final _ChatSelectionDelegate delegate;
  final Widget child;

  @override
  State<_ItemSelectionScope> createState() => _ItemSelectionScopeState();
}

class _ItemSelectionScopeState extends State<_ItemSelectionScope> {
  late final _ItemRegistrar _registrar = _ItemRegistrar(
    widget.delegate,
    widget.index,
  );

  @override
  void didUpdateWidget(_ItemSelectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registrar.index = widget.index;
  }

  @override
  Widget build(BuildContext context) {
    return SelectionRegistrarScope(registrar: _registrar, child: widget.child);
  }
}

class _ItemRegistrar implements SelectionRegistrar {
  _ItemRegistrar(this.delegate, this.index);

  final _ChatSelectionDelegate delegate;
  int index;

  @override
  void add(Selectable selectable) =>
      delegate._addItemSelectable(selectable, this);

  @override
  void remove(Selectable selectable) =>
      delegate._removeItemSelectable(selectable);
}

/// Selection across the whole history, not just the items that are built.
///
/// Flutter's selection lives in the widgets: only built text can be
/// selected, and a virtual list builds a screenful. So the selection is kept
/// here as two model points (item index + position within the item), and
/// the built items are kept in sync with it:
///
/// - Each built item's text registers here tagged with its index
///   ([_ItemSelectionScope]), ordered by index rather than by comparing
///   screen positions.
/// - Whenever items are built or released, the built text is re-selected
///   from the model: an edge in a built item goes exactly there, an edge in
///   an unbuilt item goes just past the built items on its side, so
///   everything in between shows as selected.
/// - Copying takes the two end items from what is selected on screen (or
///   what was, if they have since been released) and every item in between
///   from the model ([chatItemPlainText]), built or not.
///
/// It also does what the list's own selection handling would: auto-scroll a
/// drag held at an edge, and follow a drag while wheel-scrolling.
class _ChatSelectionDelegate extends StaticSelectionContainerDelegate {
  _ChatSelectionDelegate({
    required this.locate,
    required this.resolve,
    required this.beyondBuilt,
    required this.plainTextOf,
    required this.onDragEdge,
  });

  final _ItemPoint? Function(Offset globalPosition) locate;

  /// Where [point] is now, or null when its item is not built.
  final Offset? Function(_ItemPoint point) resolve;

  /// Where to put an edge for the unbuilt item at an index.
  final Offset? Function(int index) beyondBuilt;
  final String Function(int index) plainTextOf;
  final void Function(Offset globalPosition) onDragEdge;

  /// A Shift+click is in progress: it moves the end and keeps the start.
  bool extending = false;

  final Map<Selectable, _ItemRegistrar> _items = {};
  _SelectionEdge? _start;
  _SelectionEdge? _end;
  SelectionEdgeUpdateEvent? _dragEnd;

  /// Selected text of the end items, for when they are no longer built.
  final Map<int, String> _endText = {};

  void _addItemSelectable(Selectable selectable, _ItemRegistrar item) {
    _items[selectable] = item;
    add(selectable);
  }

  void _removeItemSelectable(Selectable selectable) {
    _items.remove(selectable);
    remove(selectable);
  }

  int _itemOf(Selectable selectable) => _items[selectable]?.index ?? -1;

  @override
  Comparator<Selectable> get compareOrder => (a, b) {
    final byItem = _itemOf(a).compareTo(_itemOf(b));
    return byItem != 0 ? byItem : _compareReadingOrder(a, b);
  };

  /// Reading order within an item, by where each piece of text starts: its
  /// first line. (Comparing whole bounding boxes misorders inline tags: the
  /// text after a tag wraps back to the left edge, so its box starts left
  /// of the tag.)
  static int _compareReadingOrder(Selectable a, Selectable b) {
    Rect firstLine(Selectable selectable) {
      final boxes = selectable.boundingBoxes;
      return MatrixUtils.transformRect(
        selectable.getTransformTo(null),
        boxes.isEmpty ? Rect.zero : boxes.first,
      );
    }

    final lineA = firstLine(a);
    final lineB = firstLine(b);
    final overlap =
        math.min(lineA.bottom, lineB.bottom) - math.max(lineA.top, lineB.top);
    if (overlap > math.min(lineA.height, lineB.height) / 2) {
      return lineA.left.compareTo(lineB.left);
    }
    return lineA.top.compareTo(lineB.top);
  }

  Offset? _positionOf(_SelectionEdge edge) =>
      resolve(edge.point) ?? beyondBuilt(edge.point.index);

  _SelectionEdge? _edgeAt(Offset globalPosition, TextGranularity granularity) {
    final point = locate(globalPosition);
    return point == null ? null : (point: point, granularity: granularity);
  }

  /// The model point of the selection's current start or end in the built
  /// text, after an event that placed it there (word, select all, keys).
  _SelectionEdge? _edgeFromGeometry({required bool end}) {
    final index = end ? currentSelectionEndIndex : currentSelectionStartIndex;
    if (index < 0 || index >= selectables.length) return null;
    final selectable = selectables[index];
    final point = end
        ? selectable.value.endSelectionPoint
        : selectable.value.startSelectionPoint;
    if (point == null) return null;
    final global = MatrixUtils.transformPoint(
      selectable.getTransformTo(null),
      point.localPosition - Offset(0, point.lineHeight / 2),
    );
    return _edgeAt(global, TextGranularity.character);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final SelectionResult result;
    switch (event) {
      // [SelectableRegion] restarts the selection on a Shift+click when it
      // cannot see the start; the start is known here, so keep it.
      case ClearSelectionEvent() ||
              SelectionEdgeUpdateEvent(type: SelectionEventType.startEdgeUpdate)
          when extending && _start != null:
        return SelectionResult.none;
      case ClearSelectionEvent():
        _start = _end = null;
        _dragEnd = null;
        _endText.clear();
        return super.dispatchSelectionEvent(event);
      case SelectionEdgeUpdateEvent(type: SelectionEventType.startEdgeUpdate):
        _start = _edgeAt(event.globalPosition, event.granularity);
        _refreshEdgeLocations();
        result = super.dispatchSelectionEvent(event);
      case SelectionEdgeUpdateEvent():
        _end = _edgeAt(event.globalPosition, event.granularity);
        _dragEnd = event;
        _refreshEdgeLocations();
        result = super.dispatchSelectionEvent(event);
        onDragEdge(event.globalPosition);
      case SelectAllSelectionEvent() ||
          SelectWordSelectionEvent() ||
          SelectParagraphSelectionEvent():
        result = super.dispatchSelectionEvent(event);
        _start = _edgeFromGeometry(end: false);
        _end = _edgeFromGeometry(end: true);
        _dragEnd = null;
      case GranularlyExtendSelectionEvent(:final isEnd) ||
          DirectionallyExtendSelectionEvent(:final isEnd):
        _refreshEdgeLocations();
        result = super.dispatchSelectionEvent(event);
        if (isEnd) {
          _end = _edgeFromGeometry(end: true) ?? _end;
        } else {
          _start = _edgeFromGeometry(end: false) ?? _start;
        }
      default:
        result = super.dispatchSelectionEvent(event);
    }
    _rememberEndText();
    return result;
  }

  /// [StaticSelectionContainerDelegate] replays the last edge positions to
  /// text that joins the selection, assuming nothing moves; in a list it
  /// does, so give it where the edges are now.
  void _refreshEdgeLocations() {
    for (final (edge, forEnd) in [(_start, false), (_end, true)]) {
      if (edge == null) continue;
      if (_positionOf(edge) case final position?) {
        updateLastSelectionEdgeLocation(
          globalSelectionEdgeLocation: position,
          forEnd: forEnd,
        );
      }
    }
  }

  @override
  void didChangeSelectables() {
    // Items were built or released: re-select the built text from the model.
    final start = _start;
    final end = _end;
    if (start != null && end != null) {
      final startPosition = _positionOf(start);
      final endPosition = _positionOf(end);
      if (startPosition != null && endPosition != null) {
        handleClearSelection(const ClearSelectionEvent());
        handleSelectionEdgeUpdate(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: startPosition,
            granularity: start.granularity,
          ),
        );
        handleSelectionEdgeUpdate(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition: endPosition,
            granularity: end.granularity,
          ),
        );
      }
    }
    super.didChangeSelectables();
    _rememberEndText();
  }

  void reapplyDragEnd() {
    final end = _dragEnd;
    if (end == null) return;
    dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forEnd(
        globalPosition: end.globalPosition,
        granularity: end.granularity,
      ),
    );
  }

  void endDrag() => _dragEnd = null;

  // --- Copy ----------------------------------------------------------------

  /// The selected text of item [index] as shown, or null if not built.
  /// Text blocks on the same row are joined by a space, rows by a newline.
  String? _builtText(int index) {
    String? text;
    Rect? previous;
    for (final selectable in selectables) {
      if (_itemOf(selectable) != index) continue;
      text ??= '';
      final content = selectable.getSelectedContent()?.plainText ?? '';
      if (content.isEmpty) continue;
      final transform = selectable.getTransformTo(null);
      final box = selectable.boundingBoxes
          .map((rect) => MatrixUtils.transformRect(transform, rect))
          .fold<Rect?>(null, (all, rect) => all?.expandToInclude(rect) ?? rect);
      if (text.isNotEmpty) {
        final sameRow =
            previous != null &&
            box != null &&
            box.top < previous.bottom - 1 &&
            previous.top < box.bottom - 1;
        final spaced =
            text.endsWith(' ') ||
            text.endsWith('\n') ||
            content.startsWith(' ');
        text += !sameRow ? '\n' : (spaced ? '' : ' ');
      }
      text += content;
      previous = box;
    }
    return text;
  }

  void _rememberEndText() {
    final ends = {?_start?.point.index, ?_end?.point.index};
    _endText.removeWhere((index, _) => !ends.contains(index));
    for (final index in ends) {
      if (_builtText(index) case final text?) _endText[index] = text;
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    final start = _start?.point.index;
    final end = _end?.point.index;
    if (start == null || end == null) return super.getSelectedContent();
    final first = start < end ? start : end;
    final last = start < end ? end : start;
    final buffer = StringBuffer();
    void write(String? text) {
      if (text == null || text.isEmpty) return;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(text);
    }

    write(_builtText(first) ?? _endText[first]);
    if (last != first) {
      for (var index = first + 1; index < last; index++) {
        write(plainTextOf(index));
      }
      write(_builtText(last) ?? _endText[last]);
    }
    return buffer.isEmpty
        ? null
        : SelectedContent(plainText: buffer.toString());
  }
}

/// Paints [child] at the offset [top] gives, read at paint time: after
/// layout, so it tracks a widget elsewhere in the tree in the same frame.
/// Paints nothing when [top] is null. [repaint] says when it may change.
class _StickyFollower extends SingleChildRenderObjectWidget {
  const _StickyFollower({
    required this.top,
    required this.repaint,
    required super.child,
  });

  final double? Function(RenderBox layer) top;
  final Listenable repaint;

  @override
  _RenderStickyFollower createRenderObject(BuildContext context) =>
      _RenderStickyFollower(top, repaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStickyFollower renderObject,
  ) {
    renderObject
      ..top = top
      ..repaint = repaint;
  }
}

class _RenderStickyFollower extends RenderProxyBox {
  _RenderStickyFollower(this.top, this._repaint);

  double? Function(RenderBox layer) top;
  double? _paintedTop;

  Listenable _repaint;
  set repaint(Listenable value) {
    if (identical(value, _repaint)) return;
    if (attached) {
      _repaint.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _repaint = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintedTop = top(this);
    if (child case final child? when _paintedTop != null) {
      context.paintChild(child, offset + Offset(0, _paintedTop!));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final painted = _paintedTop;
    final child = this.child;
    if (painted == null || child == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, painted),
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _paintedTop ?? 0, 0, 1);
  }

  // Not painted: nothing of the child shows (floating elements anchored in
  // it hide, see FloatingLayer.hideWhenClipped).
  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _paintedTop == null ? Rect.zero : null;
}

/// Reports [child]'s size after layout whenever it changes.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  _RenderSizeReporter createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(reported);
    });
  }
}
