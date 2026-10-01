import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'chat_feed.dart';
import 'chat_keys.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'composer/composer_draft.dart';
import 'step_folds.dart';
import 'widgets/chat_item_view.dart';
import 'widgets/edge_fade_mask.dart';
import 'widgets/fold_line.dart';
import 'widgets/user_message_bubble.dart';

/// Virtualized, selectable conversation history followed by the live turn.
/// Sticks to the bottom while the user is there.
class ChatHistoryView extends StatefulWidget {
  const ChatHistoryView({
    super.key,
    required this.feed,
    this.maxContentWidth = 760,
    this.onOpenAgent,
    this.footer,
  });

  /// The conversation shown: a session's, or a subagent's.
  final ChatFeed feed;
  final double maxContentWidth;

  /// Opens a subagent's own conversation, from its card.
  final ValueChanged<AgentItem>? onOpenAgent;

  /// After the last item, as the conversation's end (e.g. how a subagent
  /// is doing).
  final Widget? footer;

  @override
  State<ChatHistoryView> createState() => _ChatHistoryViewState();

  /// Focuses the history [key] is on, for its keys (the list's: ↑/↓,
  /// Page Up/Down, Home/End) to scroll it.
  static void focus(GlobalKey key) =>
      (key.currentState as _ChatHistoryViewState?)?._selectionFocusNode
          .requestFocus();
}

class _ChatHistoryViewState extends State<ChatHistoryView>
    with TickerProviderStateMixin, ChatKeyTarget {
  final _BottomAnchoredScrollController _scrollController =
      _BottomAnchoredScrollController();
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'Monad chat selection',
  );

  /// Steps the user opened (true) or closed (false). Others follow
  /// [defaultExpanded]: open while they stream or run, closed once done.
  final Map<int, bool> _expanded = {};

  // --- Folds ---------------------------------------------------------------
  //
  // Runs of quick steps fold into one line each, and a finished turn's work
  // into one line before its answer (see [StepFolds]). Every item keeps its
  // row: one a closed fold hides is laid out at no height.

  StepFolds _folds = StepFolds.none;

  /// Folds the user opened (true) or closed (false); others are closed.
  final Map<(StepFoldKind, int), bool> _foldOpen = {};

  /// Where the work of the turn that ended while the user read further up
  /// starts: it stays open, not to fold the history away under them, until
  /// they are back at the bottom or send again.
  int? _unfoldedTurn;

  /// Whether a turn was under way, as last seen: to tell when it ends.
  bool _wasLive = false;

  void _refold() => _folds = StepFolds.of(
    _feed.itemCount,
    _feed.itemAt,
    live: _feed.isStreaming,
  );

  bool _isFoldOpen(StepFold fold) =>
      _foldOpen[fold.key] ??
      (fold.kind == StepFoldKind.work && fold.start == _unfoldedTurn);

  void _toggleFold(StepFold fold) {
    for (var index = fold.start; index < fold.end; index++) {
      _animateItem(index);
    }
    setState(() => _foldOpen[fold.key] = !_isFoldOpen(fold));
  }

  StepRow _rowAt(int index) =>
      _folds.rowAt(index, _feed.itemAt(index), _isFoldOpen);

  /// Whether row [index] shows nothing: a closed fold hides its item.
  bool _isHidden(int index) => switch (_rowAt(index)) {
    (work: null, steps: null, item: false) => true,
    _ => false,
  };

  Iterable<ChatItem> _itemsIn(StepFold fold) => [
    for (var index = fold.start; index < fold.end; index++) _feed.itemAt(index),
  ];

  /// The work fold of the last turn, if it folds.
  StepFold? _lastTurnWork() {
    for (var index = _feed.itemCount - 1; index >= 0; index--) {
      if (_folds.workAt(index) case final fold?) return fold;
      if (_feed.itemAt(index) is UserMessageItem) return null;
    }
    return null;
  }

  /// Row [index] as text, as it shows: the lines of the folds it begins,
  /// and its item unless folded away.
  String _plainTextOf(int index) {
    final item = _feed.itemAt(index);
    final row = _folds.rowAt(index, item, _isFoldOpen);
    final l10n = context.l10n;
    return [
      if (row.work case StepFold(:final worked?) && final fold)
        WorkFoldLine.text(worked, turnEdits(_itemsIn(fold)), l10n: l10n),
      if (row.steps case final fold?)
        StepsFoldLine.text(StepTally(_itemsIn(fold)), l10n: l10n),
      if (row.item)
        chatItemPlainText(item, expanded: _isExpanded(index), l10n: l10n),
    ].join('\n');
  }

  // --- Motion --------------------------------------------------------------
  //
  // An item grows or shrinks smoothly when the user changes it (a node
  // expanded, a message edited), and at once otherwise: streamed text must
  // not lag behind, nor the list's hold on its bottom.

  static const _motionDuration = Duration(milliseconds: 220);
  static const _motionCurve = Curves.easeOutCubic;

  /// Per item, how many times the user has changed it: each time, its
  /// next change of height animates (see [_HeightMotion]).
  final Map<int, int> _motions = {};

  /// Animates item [index]'s next change of height (unless motion is
  /// turned down).
  void _animateItem(int index) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _motions[index] = (_motions[index] ?? 0) + 1;
  }

  /// The editor opening: its placeholder grows from the message's height
  /// to the editor's, and the editor shows as much of itself as it does.
  late final AnimationController _editorReveal = AnimationController(
    vsync: this,
    duration: _motionDuration,
    value: 1,
  );

  /// The message's height, where the placeholder grows from.
  double _editorFromHeight = 0;

  /// The placeholder's height now, opening or open.
  double get _editorShownHeight => _editorReveal.isCompleted
      ? _editorHeight
      : lerpDouble(
          _editorFromHeight,
          _editorHeight,
          _motionCurve.transform(_editorReveal.value),
        )!;

  /// The user message open for editing, if any, and the text it started
  /// from. The editor lives above the list (see [_buildEditorLayer]); the
  /// list holds a placeholder of its height.
  int? _editingIndex;
  String _editingText = '';
  List<ImageAttachment> _editingImages = const [];
  final GlobalKey _editorPlaceholderKey = GlobalKey();

  /// The status row's, kept as the items before it grow in number: it
  /// goes on where it was rather than start over.
  final GlobalKey _statusKey = GlobalKey();

  // --- Items coming in -----------------------------------------------------
  //
  // In a live turn, an item comes in fading (see [_Appear]); where it takes
  // the place of the status row showing, the row fades out there, over it,
  // rather than drop below it and fold: the one gives way to the other.

  /// The items but the status row, and whether that showed, as last seen.
  int _seenItems = 0;
  bool _statusShown = false;

  /// Items come in a live turn, until they have faded in.
  final Set<int> _appearing = {};

  /// The item the showing status row gave way to, while the row fades out
  /// over it.
  int? _handoffIndex;
  late final AnimationController _handoff =
      AnimationController(vsync: this, duration: _motionDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _handoffIndex != null) {
            setState(() => _handoffIndex = null);
          }
        });

  int get _contentCount {
    final count = _feed.itemCount;
    return count > 0 && _feed.itemAt(count - 1) is LiveStatusItem
        ? count - 1
        : count;
  }

  bool get _statusShowing {
    final count = _feed.itemCount;
    return count > 0 &&
        switch (_feed.itemAt(count - 1)) {
          LiveStatusItem(:final visible) => visible,
          _ => false,
        };
  }

  void _seeItems() {
    _seenItems = _contentCount;
    _statusShown = _statusShowing;
    _appearing.clear();
    _endHandoff();
  }

  void _endHandoff() {
    _handoff.stop();
    _handoffIndex = null;
  }

  /// Marks the items come since last seen, in a live turn, to fade in, and
  /// hands the status row over to the first of them.
  void _itemsCame() {
    final count = _contentCount;
    final statusShown = _statusShowing;
    _appearing.removeWhere((index) => index >= count);
    if (count > _seenItems &&
        _feed.isStreaming &&
        !MediaQuery.disableAnimationsOf(context)) {
      for (var index = _seenItems; index < count; index++) {
        // The user's own messages are in place as they are sent.
        if (_feed.itemAt(index) is! UserMessageItem) _appearing.add(index);
      }
      if (_statusShown &&
          !statusShown &&
          _appearing.contains(_seenItems) &&
          !_isHidden(_seenItems)) {
        _handoffIndex = _seenItems;
        _handoff.forward(from: 0);
      }
    }
    // Showing again, or gone, it is in its place.
    if (_handoffIndex case final index?
        when statusShown || index >= count || !_feed.isStreaming) {
      _endHandoff();
    }
    _seenItems = count;
    _statusShown = statusShown;
  }

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
    plainTextOf: _plainTextOf,
    onDragEdge: _autoScrollToward,
  );
  bool _reselectScheduled = false;
  Timer? _reselectTimer;
  EdgeDraggingAutoScroller? _autoScroller;

  final GlobalKey _listKey = GlobalKey();
  DateTime _lastWheel = DateTime(0);

  ChatFeed get _feed => widget.feed;
  bool get _atBottom => _scrollController.anchored;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _feed.addListener(_handleSessionChanged);
    _wasLive = _feed.isStreaming;
    _refold();
    _seeItems();
    _resumeEditing();
  }

  /// Opens the editor again on the message it was left open on, with what
  /// was typed in it.
  void _resumeEditing() {
    final editing = _feed.editing;
    if (editing == null) return;
    if (editing.index >= _feed.itemCount ||
        _feed.itemAt(editing.index) is! UserMessageItem) {
      _feed.editing = null;
      return;
    }
    final item = _feed.itemAt(editing.index) as UserMessageItem;
    _editingIndex = editing.index;
    _editingText = item.text;
    _editingImages = item.images;
  }

  @override
  void didUpdateWidget(ChatHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed != widget.feed) {
      oldWidget.feed.removeListener(_handleSessionChanged);
      widget.feed.addListener(_handleSessionChanged);
      _stickyKeys.clear();
      _stickyIndices = const {};
      _editingIndex = null;
      _foldOpen.clear();
      _unfoldedTurn = null;
      _wasLive = widget.feed.isStreaming;
      _refold();
      _seeItems();
      _resumeEditing();
    }
  }

  // --- Keys ------------------------------------------------------------------
  //
  // Focused (a click in it, or Focus Chat List), the list's keybindings
  // scroll it: by the steps Flutter's own scroll keys take.

  @override
  Object? chatContextKey(String key) => switch (key) {
    'listFocus' => _selectionFocusNode.hasPrimaryFocus,
    _ => null,
  };

  @override
  Map<String, VoidCallback> get chatCommands => {
    'list.focusDown': () => _scrollBy(_lineStep),
    'list.focusUp': () => _scrollBy(-_lineStep),
    'list.focusPageDown': () => _scrollBy(_pageStep),
    'list.focusPageUp': () => _scrollBy(-_pageStep),
    'list.focusFirst': () => _scrollBy(double.negativeInfinity),
    'list.focusLast': _jumpToBottom,
  };

  static const _lineStep = 50.0;
  double get _pageStep => _scrollController.hasClients
      ? _scrollController.position.viewportDimension * 0.8
      : 0;

  /// Scrolls by [delta], to either end at most: held to the bottom there.
  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target >= position.maxScrollExtent - 1) {
      _jumpToBottom();
      return;
    }
    _setAnchored(false);
    position.jumpTo(target);
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
    _feed.removeListener(_handleSessionChanged);
    _reselectTimer?.cancel();
    _autoScroller?.stopAutoScroll();
    _editorMoved.dispose();
    _editorReveal.dispose();
    _handoff.dispose();
    _selectionDelegate.dispose();
    _scrollController.dispose();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  bool _isExpanded(int index) =>
      _expanded[index] ?? defaultExpanded(_feed.itemAt(index));

  void _toggle(int index) {
    // A thought opens with its own motion.
    if (_feed.itemAt(index) is! ThinkingItem) _animateItem(index);
    setState(() => _expanded[index] = !_isExpanded(index));
  }

  /// A trackpad (macOS) scrolls the list as a pan gesture, with no press
  /// and no wheel signal: its drag, and the fling after it, set a scroll
  /// direction until they come to rest.
  bool get _userScrolling =>
      _pointersDown > 0 ||
      DateTime.now().difference(_lastWheel) <
          const Duration(milliseconds: 250) ||
      _scrollController.position.userScrollDirection != ScrollDirection.idle;

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
    // Back at the bottom: the turn read meanwhile folds.
    if (_atBottom && _unfoldedTurn != null) {
      setState(() => _unfoldedTurn = null);
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

  /// Either side of the scrollbar's thumb, still the bar.
  static const _scrollbarMargin = 4.0;

  /// The strip at the right of the list, beside its text: the scrollbar's.
  static const _scrollbarGutter = 24.0;

  void _handlePointerDown(PointerDownEvent event) {
    _pointersDown++;
    // A press stops the list where it is (a trackpad swipe's fling carries
    // on for a while), as it does in the platform's lists: a mouse is not
    // one of the list's drag devices, so nothing else would, and a
    // selection started on moving text lands wherever it has gone by then.
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      if (position.isScrollingNotifier.value) position.jumpTo(position.pixels);
    }
    // A press beside the bar, just missing it, neither starts a selection
    // nor clears one (as a browser's scrollbar).
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (list != null && list.hasSize) {
      final right = list.localToGlobal(Offset(list.size.width, 0)).dx;
      _selectionDelegate.suspended =
          event.position.dx >= right - _scrollbarGutter;
    }
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
        ..extending = false
        ..suspended = false;
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
      // Items only: not the footer after them.
      if (child.hasSize && _indexOf(child) < _feed.itemCount) yield child;
      child = sliver.childAfter(child);
    }
  }

  /// Whether item [index] is scrolled past the top, where the editor on it
  /// sticks (see [_editorTop]).
  bool _scrolledPast(int index) {
    for (final item in _laidOutItems()) {
      if (_indexOf(item) > index) return true;
      if (_indexOf(item) < index) continue;
      final viewport = RenderAbstractViewport.maybeOf(item);
      if (viewport is! RenderBox) return false;
      final top =
          item.localToGlobal(Offset.zero).dy -
          (viewport as RenderBox).localToGlobal(Offset.zero).dy +
          _gapBefore(index);
      return top < _editorInset;
    }
    return false;
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
    final startedStreaming = _feed.isStreaming && !_wasStreaming;
    _wasStreaming = _feed.isStreaming;
    final ended = _wasLive && !_feed.isStreaming;
    _wasLive = _feed.isStreaming;
    _refold();
    if (_feed.isStreaming) _unfoldedTurn = null;
    if (ended && !_atBottom) _unfoldedTurn = _lastTurnWork()?.start;
    final editing = _editingIndex;
    if (startedStreaming ||
        (editing != null &&
            (editing >= _feed.itemCount ||
                _feed.itemAt(editing) is! UserMessageItem))) {
      _editingIndex = null;
      _feed.editing = null;
    }
    if (startedStreaming) _jumpToBottom();
    _itemsCame();
    _scheduleStickyUpdate();
    setState(() {});
  }

  void _startEditing(int index) {
    final item = _feed.itemAt(index);
    if (item is! UserMessageItem) return;
    // Until the editor reports its height, hold the message's.
    final laidOut = _laidOutItems().where((box) => _indexOf(box) == index);
    _feed.editing = (index: index, draft: ComposerDraft());
    setState(() {
      _editingIndex = index;
      _editingText = item.text;
      _editingImages = item.images;
      _editComposerKey = GlobalKey();
      _editorHeight = _editorFromHeight = laidOut.isEmpty
          ? 0
          : laidOut.first.size.height - _gapBefore(index);
    });
    // Stuck to the top, it takes the place of the message's copy there, in
    // one go: nothing moves under it to follow.
    if (MediaQuery.disableAnimationsOf(context) || _scrolledPast(index)) {
      _editorReveal.value = 1;
    } else {
      _editorReveal.forward(from: 0);
    }
  }

  /// A press elsewhere in this conversation's column (its title bar, its
  /// history, the composer below) closes the editor. One beside it (the
  /// sidebar, to go to another conversation) leaves it open, to find again.
  void _handleTapOutsideEditor(PointerDownEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final column = box.localToGlobal(Offset.zero) & box.size;
    final x = event.position.dx;
    if (x >= column.left && x <= column.right) _cancelEditing();
  }

  void _cancelEditing() {
    _feed.editing = null;
    if (_editingIndex case final index?) {
      // Back to the message: from the editor's height to its own (stuck to
      // the top, to the message's copy there, in one go).
      if (!_scrolledPast(index)) _animateItem(index);
      setState(() => _editingIndex = null);
    }
  }

  void _setEditorHeight(double height) {
    if (height == _editorHeight || _editingIndex == null) return;
    setState(() => _editorHeight = height);
    _editorMoved.value++;
  }

  /// Room above the editor stuck to the top of the list.
  static const _editorInset = 8.0;

  /// Where the editor goes, relative to [layer]: on its placeholder, but
  /// never above the top of the list (it sticks there once scrolled past).
  /// Null when the placeholder is below the built items, out of view.
  double? _editorTop(RenderBox layer) {
    const inset = _editorInset;
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
  static const _stickyInset = AppMetrics.contentInset;

  /// Height of the fade under the stuck message, over the transcript
  /// scrolling beneath it.
  static const _stickyFade = 16.0;

  /// How far the list scrolls while the stuck message comes in (and goes
  /// as the next pushes it away): as far as the list's top fade reaches.
  static const _stickyEase = 32.0;

  /// Which copies are built is settled after layout, with the items where
  /// the scroll put them: a frame late, but ready before any scroll brings
  /// their message to the top (the one at the top now is built in layout,
  /// besides). Which one shows, and where, is read at paint ([_stickyTop]),
  /// so a copy takes over in the very frame its message scrolls past.
  void _scheduleStickyUpdate() {
    if (_stickyUpdateScheduled) return;
    _stickyUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickyUpdateScheduled = false;
      if (!mounted) return;
      final indices = {
        ?_topTurnMessage(),
        for (final item in _laidOutItems())
          if (_feed.itemAt(_indexOf(item)) is UserMessageItem) _indexOf(item),
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
      if (_feed.itemAt(index) is! UserMessageItem) continue;
      if (_messageTop(index, list)! >= _stickyInset) break;
      passed = index;
    }
    if (passed != null || first == null) return passed;
    // Scrolled past long ago: above the laid-out items.
    for (var index = first - 1; index >= 0; index--) {
      if (_feed.itemAt(index) is UserMessageItem) return index;
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
      if (next <= index || _feed.itemAt(next) is! UserMessageItem) {
        continue;
      }
      final nextTop = _messageTop(next, list)!;
      if (nextTop <= 0) return null;
      return math.min(0.0, nextTop - sticky.size.height);
    }
    return 0;
  }

  /// How far in the stuck message [index] has come, 0 to 1; null while it is
  /// not stuck. It takes over from its message in the list faded at the top
  /// as that one was, by the list's top fade, and loses that fade as the
  /// list scrolls on, the fade below it coming in; pushed away by the next
  /// message, it fades at the top as the list does again.
  double? _stickyIn(int index) {
    final top = _stickyTop(index);
    if (top == null) return null;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    final message = list == null ? null : _messageTop(index, list);
    // Not laid out: scrolled past long ago.
    final past = message == null ? _stickyEase : _stickyInset - message;
    return (math.min(past, _stickyEase + top) / _stickyEase).clamp(0.0, 1.0);
  }

  /// How much of the list's top fade there is: under the stuck message,
  /// the fade below it comes in with it; the list's own is always there.
  double _listTopFade() {
    final cover = _stickyCover();
    if (cover == null || cover <= 0) return 1;
    return _stickyIn(_topTurnMessage()!) ?? 1;
  }

  /// How far down the stuck message covers the list, above its fade; null
  /// while none is. Read as the list is painted, the stuck one being where
  /// [_stickyTop] puts it.
  double? _stickyCover() {
    final index = _topTurnMessage();
    if (index == null || index == _editingIndex) return null;
    final top = _stickyTop(index);
    final sticky =
        _stickyKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    if (top == null || sticky == null || !sticky.hasSize) return null;
    return top + sticky.size.height - _stickyFade;
  }

  Widget _buildSticky(int index) {
    final item = _feed.itemAt(index) as UserMessageItem;
    final repaint = Listenable.merge([_scrollController, _editorMoved]);
    // A copy of the message in the list: not read out twice.
    return ExcludeSemantics(
      child: ClipRect(
        // Faded at the top as the list is, while it comes in and goes.
        child: EdgeFadeMask(
          top: true,
          bottom: false,
          topFadeAmount: () => 1 - (_stickyIn(index) ?? 1),
          repaint: repaint,
          child: _StickyFollower(
            top: (_) => _stickyTop(index),
            repaint: repaint,
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
                    // Nothing under it: the transcript is hidden there (see
                    // _stickyCover), not painted over, as over the window's
                    // material no color would match the page around it.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        _gutter,
                        _stickyInset,
                        _gutter,
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
                            images: item.images,
                            onEdit: _feed.canEditMessages
                                ? () => _startEditing(index)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    // Where the transcript fades back in.
                    const SizedBox(height: _stickyFade),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorLayer(int index) {
    final shadow = themeColors['widget.shadow'];
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
              repaint: Listenable.merge([
                _scrollController,
                _editorMoved,
                _editorReveal,
              ]),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: _gutter),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.maxContentWidth,
                    ),
                    // Opening, as much of it as its placeholder has room
                    // for: it does not cover what is below it yet.
                    child: AnimatedBuilder(
                      animation: _editorReveal,
                      builder: (context, child) => ClipRect(
                        clipper: _RevealClipper(_editorShownHeight),
                        clipBehavior: _editorReveal.isCompleted
                            ? Clip.none
                            : Clip.hardEdge,
                        child: child,
                      ),
                      child: _SizeReporter(
                        onSize: (size) => _setEditorHeight(size.height),
                        // Lifted off the transcript: it floats over it when
                        // stuck to the top. (Outside the reported size.)
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              // A deep, soft drop plus a tight contact
                              // shadow, or it does not read against the page.
                              BoxShadow(
                                color: shadow,
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: shadow.withValues(alpha: shadow.a * 0.6),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
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
                              onTapOutside: _handleTapOutsideEditor,
                              child: ChatComposer(
                                key: _editComposerKey,
                                // Only a session's own messages are edited.
                                session: _feed as ChatSession,
                                initialText: _editingText,
                                initialImages: _editingImages,
                                draft: _feed.editing?.draft,
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
    _feed.editing = null;
    if (!_scrolledPast(index)) _animateItem(index);
    setState(() {
      _editingIndex = null;
      // Everything after the message is replaced; so are its steps.
      _expanded.removeWhere((i, _) => i > index);
      _foldOpen.removeWhere((key, _) => key.$2 > index);
      _unfoldedTurn = null;
    });
    _feed.editMessage(index, message);
  }

  double _insetOf(int index) =>
      _feed.itemAt(index) is UserMessageItem ? 0 : UserMessageBubble.radius;

  Widget _buildItem(int index) {
    final item = _feed.itemAt(index);
    if (index == _editingIndex) {
      return AnimatedBuilder(
        animation: _editorReveal,
        builder: (context, _) =>
            SizedBox(key: _editorPlaceholderKey, height: _editorShownHeight),
      );
    }
    final row = _folds.rowAt(index, item, _isFoldOpen);
    final folds = [?row.work, ?row.steps];
    // Folded away.
    if (folds.isEmpty && !row.item) {
      return const SizedBox(width: double.infinity);
    }
    Widget? shown;
    if (row.item) {
      final view = ChatItemView(
        key: item is LiveStatusItem ? _statusKey : ValueKey(index),
        item: item,
        expanded: _isExpanded(index),
        onToggle: () => _toggle(index),
        onEdit: item is UserMessageItem && _feed.canEditMessages
            ? () => _startEditing(index)
            : null,
        onCancelQueued: () => _feed.cancelQueued(index),
        onMoveToBackground: _feed.moveToBackgroundAt(index),
        onStop: _feed.stopAt(index),
        onOpen: switch ((item, widget.onOpenAgent)) {
          (final AgentItem agent, final open?) when agent.id != null =>
            () => open(agent),
          _ => null,
        },
      );
      shown = switch (item) {
        // Meanwhile over the item it gave way to.
        LiveStatusItem() when _handoffIndex != null => const SizedBox(
          width: double.infinity,
        ),
        LiveStatusItem() => view,
        _ => _Appear(
          key: ValueKey(('appear', index)),
          appear: _appearing.contains(index),
          onShown: () => _appearing.remove(index),
          ghost: index == _handoffIndex ? _statusGhost(index) : null,
          child: view,
        ),
      };
    }
    return _ItemSelectionScope(
      index: index,
      delegate: _selectionDelegate,
      child: folds.isEmpty
          ? shown!
          // Steps line up on the left, folds' lines too.
          : SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.work case StepFold(:final worked?) && final fold) ...[
                    WorkFoldLine(
                      worked: worked,
                      edits: turnEdits(_itemsIn(fold)),
                      expanded: _isFoldOpen(fold),
                      onToggle: () => _toggleFold(fold),
                    ),
                    // Words under it stand apart, as under any step.
                    if (row.steps == null && row.item && !isStep(item))
                      const SizedBox(height: 10),
                  ],
                  if (row.steps case final fold?)
                    StepsFoldLine(
                      tally: StepTally(_itemsIn(fold)),
                      expanded: _isFoldOpen(fold),
                      onToggle: () => _toggleFold(fold),
                    ),
                  ?shown,
                ],
              ),
            ),
    );
  }

  /// The status row, fading out over [index], where it was: as much above
  /// the item's top as its gap was less than the item's.
  ({Widget row, double top})? _statusGhost(int index) {
    final status = _feed.itemAt(_feed.itemCount - 1);
    if (status is! LiveStatusItem) return null;
    final previous = index == 0 ? null : _feed.itemAt(index - 1);
    return (
      row: ChatItemView(key: _statusKey, item: status),
      top: _gapBetween(previous, status) - _gapBefore(index),
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

  /// Vertical gap above [index]: roomy between turns, none between steps.
  double _gapBefore(int index) => _gapBetween(
    index == 0 ? null : _feed.itemAt(index - 1),
    _feed.itemAt(index),
  );

  double _gapBetween(ChatItem? previous, ChatItem item) {
    if (previous == null) return 0;
    if (item is UserMessageItem) return 32;
    if (previous is UserMessageItem) return 14;
    // Steps follow one another as a list.
    if (isStep(item) && isStep(previous)) return 0;
    return 10;
  }

  /// The side margin for the width the history has; see [chatGutter].
  double _gutter = 24;

  /// The history as built for [_gutter], until this builds again: a new
  /// width with the same margin (a pane being resized) only lays it out
  /// anew, rather than build (and parse) every message shown each frame.
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    _built = null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = chatGutter(constraints.maxWidth);
        if (_built == null || gutter != _gutter) {
          _gutter = gutter;
          _built = _buildHistory(context);
        }
        return _built!;
      },
    );
  }

  Widget _buildHistory(BuildContext context) {
    return Shortcuts(
      shortcuts: _selectionShortcuts,
      // Sees every press and wheel event, the scrollbar's too.
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
        child: MouseRegion(
          onEnter: (_) => _setPointerInside(true),
          onExit: (_) => _setPointerInside(false),
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (!_isPointerInside) return Colors.transparent;
                final colors = themeColors;
                if (states.contains(WidgetState.dragged)) {
                  return colors['scrollbarSlider.activeBackground'];
                }
                if (states.contains(WidgetState.hovered)) {
                  return colors['scrollbarSlider.hoverBackground'];
                }
                return colors['scrollbarSlider.background'];
              }),
              // The thumb as thin as ever, easier to catch: its track (what
              // takes a press) is that much wider on both sides.
              crossAxisMargin: _scrollbarMargin,
            ),
            // Above the selection: the bar takes a press on it alone (what
            // it covers is not hit-tested), so dragging it never selects.
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              child: SelectionArea(
                focusNode: _selectionFocusNode,
                // Focus on click rather than hover so the composer keeps
                // focus while the pointer passes over the history.
                child: SelectionContainer(
                  delegate: _selectionDelegate,
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
                            // Hidden under the stuck message, fading in
                            // below it.
                            topCover: _stickyCover,
                            coverFade: _stickyFade,
                            topFadeAmount: _listTopFade,
                            repaint: Listenable.merge([
                              _scrollController,
                              _editorMoved,
                            ]),
                            // Its bar is the one around the selection, above; not a second
                            // one of the platform's own.
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: SuperListView.builder(
                                key: _listKey,
                                controller: _scrollController,
                                itemCount:
                                    _feed.itemCount +
                                    (widget.footer == null ? 0 : 1),
                                cacheExtent: 900,
                                padding: EdgeInsets.fromLTRB(
                                  _gutter,
                                  20,
                                  _gutter,
                                  24,
                                ),
                                itemBuilder: (context, index) {
                                  if (index == _feed.itemCount) {
                                    return Align(
                                      alignment: Alignment.topCenter,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: widget.maxContentWidth,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 20,
                                          ),
                                          child: widget.footer,
                                        ),
                                      ),
                                    );
                                  }
                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: widget.maxContentWidth,
                                      ),
                                      child: Padding(
                                        // All but the user's messages a
                                        // little narrower than those.
                                        padding: EdgeInsets.only(
                                          top: _isHidden(index)
                                              ? 0
                                              : _gapBefore(index),
                                          left: _insetOf(index),
                                          right: _insetOf(index),
                                        ),
                                        child: _HeightMotion(
                                          motion: _motions[index] ?? 0,
                                          child: _buildItem(index),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // Built in layout, after the list: the copy of
                        // the message at the top is there in the very frame
                        // the list is laid out (a conversation just opened
                        // has it from its first frame).
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, _) => Stack(
                              children: [
                                for (final index in {
                                  ..._stickyIndices,
                                  ?_topTurnMessage(),
                                })
                                  if (index != _editingIndex &&
                                      index < _feed.itemCount &&
                                      _feed.itemAt(index) is UserMessageItem)
                                    Positioned.fill(
                                      key: ValueKey(('sticky', index)),
                                      child: _buildSticky(index),
                                    ),
                              ],
                            ),
                          ),
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

/// The conversation's side margin at [width]: roomy in a wide window, and
/// tighter in a narrow pane (e.g. beside the Fast Ide), where a wide margin
/// on both sides would crowd the text and the composer. Never under the
/// scrollbar's track (its thumb and margins), so a press at the end of a
/// line selects text rather than grabbing the bar.
double chatGutter(double width) => width < 600 ? 16 : 24;

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
          // With the key that does the same in the conversation (End: the
          // list's Focus Last).
          child: IdeHover(
            message: ChatKeys.titleWithKey(
              context.l10n.cmdTerminalScrollToBottom,
              'list.focusLast',
              const {'listFocus': true, 'inputFocus': false},
            ),
            position: IdeHoverPosition.above,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderStrong),
                    boxShadow: [
                      BoxShadow(
                        color: themeColors['widget.shadow'],
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 15,
                    color: AppColors.text,
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
  static const wheelSpeed = 2.2;

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

  /// A press in the scrollbar's gutter is under way: pointer selection
  /// events change nothing.
  bool suspended = false;

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
    if (suspended &&
        (event is SelectionEdgeUpdateEvent ||
            event is ClearSelectionEvent ||
            event is SelectWordSelectionEvent ||
            event is SelectParagraphSelectionEvent)) {
      return SelectionResult.none;
    }
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

/// Down to [height], and wide of the sides for the shadows.
class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper(this.height);

  final double height;

  static const _shadowRoom = 80.0;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -_shadowRoom,
    -_shadowRoom,
    size.width + _shadowRoom,
    height,
  );

  @override
  bool shouldReclip(_RevealClipper old) => old.height != height;
}

/// An item come in a live turn: it fades in, rising a little, where it is
/// (its height at once, as streamed text's is, so the list keeps its hold
/// on its bottom). [ghost], the status row whose place it took, fades out
/// over it meanwhile, where the row was. At once where motion is turned
/// down.
class _Appear extends StatefulWidget {
  const _Appear({
    super.key,
    required this.appear,
    required this.onShown,
    required this.child,
    this.ghost,
  });

  final bool appear;

  /// Once it has faded in.
  final VoidCallback onShown;
  final ({Widget row, double top})? ghost;
  final Widget child;

  static const duration = Duration(milliseconds: 260);

  /// How far below its place it begins.
  static const rise = 6.0;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  /// Only for one come in: what was there already stays as it is.
  AnimationController? _controller;
  late final Animation<double> _eased = CurvedAnimation(
    parent: _controller!,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.appear) return;
    _controller = AnimationController(vsync: this, duration: _Appear.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onShown();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FadeTransition(
          opacity: _eased,
          child: AnimatedBuilder(
            animation: _eased,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _Appear.rise * (1 - _eased.value)),
              child: child,
            ),
            child: widget.child,
          ),
        ),
        if (widget.ghost case (:final row, :final top))
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: SelectionContainer.disabled(child: row),
            ),
          ),
      ],
    );
  }
}

/// Its child, and when [motion] changes, the child's next change of height
/// over a moment rather than at once; any other change at once. Moving
/// already, it takes a new height in its stride.
class _HeightMotion extends StatefulWidget {
  const _HeightMotion({required this.motion, required this.child});

  final int motion;
  final Widget child;

  @override
  State<_HeightMotion> createState() => _HeightMotionState();
}

class _HeightMotionState extends State<_HeightMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _ChatHistoryViewState._motionDuration,
    value: 1,
  );

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _HeightMotionBox(
    motion: widget.motion,
    progress: _progress,
    onStart: () {
      if (mounted) _progress.forward(from: 0);
    },
    child: widget.child,
  );
}

class _HeightMotionBox extends SingleChildRenderObjectWidget {
  const _HeightMotionBox({
    required this.motion,
    required this.progress,
    required this.onStart,
    super.child,
  });

  final int motion;
  final Animation<double> progress;
  final VoidCallback onStart;

  @override
  _RenderHeightMotion createRenderObject(BuildContext context) =>
      _RenderHeightMotion(motion, progress, onStart: onStart);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightMotion renderObject,
  ) {
    renderObject
      ..motion = motion
      ..progress = progress
      ..onStart = onStart;
  }
}

class _RenderHeightMotion extends RenderProxyBox {
  _RenderHeightMotion(this._motion, this._progress, {required this.onStart});

  VoidCallback onStart;

  int _motion;
  set motion(int value) {
    if (value == _motion) return;
    _motion = value;
    _armed = true;
    markNeedsLayout();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (value == _progress) return;
    if (attached) _progress.removeListener(markNeedsLayout);
    _progress = value;
    if (attached) _progress.addListener(markNeedsLayout);
  }

  /// The next change of height animates.
  bool _armed = false;

  /// Moving from the next frame on (the animation cannot start in layout).
  bool _starting = false;

  double? _from;
  double? _to;

  final _clip = LayerHandle<ClipRectLayer>();

  bool get _moving => _starting || _progress.isAnimating;

  double get _height => lerpDouble(
    _from,
    _to,
    _starting
        ? 0
        : _ChatHistoryViewState._motionCurve.transform(_progress.value),
  )!;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final target = child.size.height;
    if (_to == null || !(_armed || _moving)) {
      _from = _to = target;
    } else if (target != _to) {
      _from = _height;
      _to = target;
      if (!_starting) {
        _starting = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _starting = false;
          if (attached) onStart();
        });
      }
    }
    _armed = false;
    size = constraints.constrain(Size(child.size.width, _height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (size.height >= child.size.height) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    // Growing, what is not in yet; room at the sides for shadows.
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(-80, -80, size.width + 80, size.height),
      super.paint,
      oldLayer: _clip.layer,
    );
  }
}
