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

import '../base/smooth_scroll.dart';
import '../diagnostics/frame_watch.dart';
import '../ide/ide_find_widget.dart';
import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../usage/usage_ledger.dart';
import '../usage/usage_prices.dart';
import '../usage/usage_query.dart';
import '../usage/usage_record.dart';
import 'chat_column.dart';
import 'chat_feed.dart';
import 'selection/chat_selection.dart';
import 'chat_find.dart';
import 'chat_keys.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'composer/composer_draft.dart';
import 'reply_scroll.dart';
import 'rewind_files_prompt.dart';
import 'side_panel/file_link_menu.dart';
import 'steadiness.dart';
import 'step_folds.dart';
import 'user_message_style.dart';
import 'widgets/chat_item_view.dart';
import 'widgets/chat_minimap.dart';
import 'widgets/edge_fade_mask.dart';
import 'widgets/own_selection.dart';
import 'widgets/content_image.dart' show ChatImage, ChatImages;
import 'widgets/fold_line.dart';
import 'widgets/hover_builder.dart';
import 'widgets/turn_footer.dart';
import 'widgets/user_message_bubble.dart';

/// Virtualized, selectable conversation history followed by the live turn.
/// Sticks to the bottom while the user is there.
class ChatHistoryView extends StatefulWidget {
  const ChatHistoryView({
    super.key,
    required this.feed,
    this.maxContentWidth = 760,
    this.minimap = false,
    this.minimapRoom,
    this.onOpenAgent,
    this.onSetGoal,
    this.onFindClosed,
    this.after,
    this.forkAfter,
    this.underTitle = false,
  });

  /// The conversation shown: a session's, or a subagent's.
  final ChatFeed feed;
  final double maxContentWidth;

  /// Whether a minimap of it shows in the margin beside its column (on
  /// [ChatMinimap.side]), when there is room for one (see [ChatMinimap]).
  /// Its room is kept only once the conversation is long: until then there
  /// is none to show.
  final bool minimap;

  /// Told whether the column keeps the minimap's room, for what is level
  /// with it (a subagent's header).
  final ValueNotifier<bool>? minimapRoom;

  /// Opens a subagent's own conversation, from its card.
  final ValueChanged<AgentItem>? onOpenAgent;

  /// Sets a goal the agent proposed as the session's, from its card.
  final ValueChanged<String>? onSetGoal;

  /// Where the focus goes once its find bar closes (see [find]).
  final VoidCallback? onFindClosed;

  /// What shows under item [index], after its turn's footer, not of the
  /// conversation itself (the conversations asked beside it there); none
  /// for most.
  final Widget? Function(int index)? after;

  /// What forks the conversation from the end of the turn item [index]
  /// ends, its footer's button; none where it cannot be forked there.
  final VoidCallback? Function(int index)? forkAfter;

  /// Whether a row is right over it (its card's title): room of its own
  /// above the history, which then keeps less above its first item and a
  /// stuck message, and fades less deep at its top.
  final bool underTitle;

  @override
  State<ChatHistoryView> createState() => _ChatHistoryViewState();

  /// Focuses the history [key] is on, for its keys (the list's: ↑/↓,
  /// Page Up/Down, Home/End) to scroll it.
  static void focus(GlobalKey key) =>
      (key.currentState as _ChatHistoryViewState?)?._selectionFocusNode
          .requestFocus();

  /// Shows the find bar of the history [key] is on, looking for [query]
  /// when given (a search's), its first match brought into view.
  static void find(GlobalKey key, {String? query}) =>
      (key.currentState as _ChatHistoryViewState?)?._find.show(query: query);
}

/// Where a history was left, read up from its end: the row shown first and
/// how far its top was above the view's, the earlier history then read
/// ([ChatSession.prependedCount]), and the steps and folds opened or
/// closed. Its view is built anew when the conversation shows again
/// (another one shown in its place meanwhile), and goes back there.
typedef _LeftAt = ({
  int index,
  double above,
  int prepended,
  Map<int, bool> expanded,
  Map<(StepFoldKind, int), bool> folds,
  Set<int> unfolded,
});

/// Each conversation's, by its feed; none while at the end, followed.
final Expando<_LeftAt> _leftAt = Expando('chat history left at');

/// The conversations found long ([_ChatHistoryViewState._long]), by their
/// feeds: one shown again has its minimap (and the room for it) from its
/// first frame, not a few frames on, once it is laid out.
final Expando<bool> _longFeeds = Expando('chat history long');

class _ChatHistoryViewState extends State<ChatHistoryView>
    with TickerProviderStateMixin, ChatKeyTarget {
  final _BottomAnchoredScrollController _scrollController =
      _BottomAnchoredScrollController();
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'BaoCode chat selection',
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

  /// Where the work of the turns that ended while the user read further up
  /// starts: it stays open, not to fold the history away under them, until
  /// they are back at the bottom or send again. (Turns the agent takes up on
  /// its own, one after another, may end meanwhile.)
  final Set<int> _unfoldedTurns = {};

  /// Whether a turn was under way, as last seen: to tell when it ends.
  bool _wasLive = false;

  void _refold() {
    _folds = StepFolds.of(
      _feed.itemCount,
      _feed.itemAt,
      live: _feed.isStreaming,
    );
    _liveStart = null;
    if (!_feed.isStreaming) return;
    for (var index = _feed.itemCount - 1; index >= 0; index--) {
      if (_feed.itemAt(index) case UserMessageItem(queued: false)) {
        _liveStart = index + 1;
        break;
      }
    }
  }

  /// Where the turn under way's items start; null when none is.
  int? _liveStart;

  /// What shows of the turn under way only while it lasts, steadied: a
  /// closed run's step under way, a thought open as it streams. What is
  /// done in a blink never shows, rather than flash; what showed stays a
  /// moment before it folds away.
  late final Steadiness _steady = Steadiness(
    onChange: () {
      if (mounted) setState(() {});
    },
  );

  bool _isLive(int index) => switch (_liveStart) {
    final start? => index >= start,
    null => false,
  };

  bool _isFoldOpen(StepFold fold) =>
      _foldOpen[fold.key] ??
      (fold.kind == StepFoldKind.work && _unfoldedTurns.contains(fold.start));

  void _toggleFold(StepFold fold) {
    final open = !_isFoldOpen(fold);
    for (var index = fold.start; index < fold.end; index++) {
      _animateItem(index);
    }
    if (!MediaQuery.disableAnimationsOf(context)) {
      final items = [for (var i = fold.start; i < fold.end; i++) i];
      if (open) {
        _entering.addAll(items);
        WidgetsBinding.instance.addPostFrameCallback((_) => _entering.clear());
      } else {
        _leaving.addAll(items);
        _leavingDone?.cancel();
        _leavingDone = Timer(_motionDuration * 2, () {
          if (mounted) setState(_leaving.clear);
        });
      }
    }
    setState(() => _foldOpen[fold.key] = open);
  }

  /// What row [index] shows. Of a run under way the user has not opened
  /// or closed: its step under way once it has run a moment, and a step
  /// that showed kept a moment before it folds away (see [_steady]).
  StepRow _rowAt(int index) {
    final item = _shownAt(index);
    final row = _folds.rowAt(index, item, _isFoldOpen);
    if (!_isLive(index) || !isQuickStep(item) || row.work != null) return row;
    final steps = _folds.stepsAt(index);
    if (steps != null && _foldOpen.containsKey(steps.key)) return row;
    final key = (#row, index);
    final bool shown;
    if (steps == null) {
      // Showing anyway: from now, to keep it a moment once a run takes it.
      shown = _steady.shows(key, wanted: row.item, delayed: false);
    } else {
      // A closed run's: shown only while under way.
      shown = _steady.shows(key, wanted: row.item);
    }
    return (work: row.work, steps: row.steps, item: shown);
  }

  /// Whether row [index] shows nothing: a closed fold hides its item.
  bool _isHidden(int index) => switch (_rowAt(index)) {
    (work: null, steps: null, item: false) => true,
    _ => false,
  };

  Iterable<ChatItem> _itemsIn(StepFold fold) => [
    for (var index = fold.start; index < fold.end; index++) _feed.itemAt(index),
  ];

  // --- Turn costs ------------------------------------------------------------
  //
  // Each finished turn's cost at the current model prices (UsagePrices),
  // from the session's calls kept in UsageLedger: updates as calls are
  // recorded and as prices change, without waiting on the CLI's own cost
  // (which is 0 for custom upstreams).

  String? _usageSessionId;
  int _usageSessionVersion = -1;
  List<UsageCall> _usageCalls = const [];
  Map<int, UsageCost> _turnCosts = const {};

  void _syncUsageSession() {
    final id = _session?.sessionId;
    if (id == _usageSessionId) return;
    _usageSessionId = id;
    _usageSessionVersion = -1;
    _usageCalls = const [];
    _turnCosts = const {};
    if (id != null) unawaited(_loadUsageCalls(id));
  }

  Future<void> _loadUsageCalls(String id) async {
    final ledger = UsageLedger.current;
    final version = ledger.sessionVersion(id);
    final calls = await ledger.ofSession(id);
    if (!mounted || id != _usageSessionId) return;
    _usageSessionVersion = version;
    _usageCalls = calls;
    final next = _computeTurnCosts();
    if (_turnCostsChanged(_turnCosts, next)) {
      setState(() => _turnCosts = next);
    }
  }

  void _handleUsageLedgerChanged() {
    final id = _session?.sessionId;
    if (id == null) return;
    if (id != _usageSessionId) {
      _syncUsageSession();
      return;
    }
    if (UsageLedger.current.sessionVersion(id) == _usageSessionVersion) return;
    unawaited(_loadUsageCalls(id));
  }

  void _handleUsagePricesChanged() {
    if (_usageCalls.isEmpty) return;
    final next = _computeTurnCosts();
    if (_turnCostsChanged(_turnCosts, next)) {
      setState(() => _turnCosts = next);
    }
  }

  Map<int, UsageCost> _computeTurnCosts() {
    if (_usageCalls.isEmpty) return const {};
    final prompts = <int>[];
    final spans = <TurnSpan>[];
    final count = _feed.itemCount;
    for (var i = 0; i < count; i++) {
      if (_feed.itemAt(i) case UserMessageItem(
        queued: false,
        :final sentAt,
        :final worked,
      )) {
        prompts.add(i);
        spans.add((sentAt: sentAt, worked: worked));
      }
    }
    final costs = turnCostsOf(_usageCalls, spans);
    return {
      for (var i = 0; i < prompts.length; i++)
        if (spans[i].worked != null && costs[i] != null) prompts[i]: costs[i]!,
    };
  }

  static bool _turnCostsChanged(Map<int, UsageCost> a, Map<int, UsageCost> b) {
    if (a.length != b.length) return true;
    for (final MapEntry(:key, :value) in a.entries) {
      final other = b[key];
      if (other == null ||
          other.text != value.text ||
          other.unpriced != value.unpriced) {
        return true;
      }
    }
    return false;
  }

  /// The footer under item [index], when it ends a finished turn: its
  /// answer to copy, a fork from there, how fast, how long, and what it
  /// cost.
  Widget? _turnFooter(int index) {
    final prompt = _folds.turnEndingAt(index);
    if (prompt == null) return null;
    final message = _feed.itemAt(prompt);
    if (message is! UserMessageItem) return null;
    // The answer: the words after the turn's last step.
    final words = <String>[];
    for (var i = index; i > prompt; i--) {
      final item = _feed.itemAt(i);
      if (item is AssistantTextItem) {
        words.insert(0, item.text);
      } else if (item is! ThinkingItem) {
        break;
      }
    }
    return TurnFooter(
      answer: words.isEmpty ? null : words.join('\n\n'),
      onFork: widget.forkAfter?.call(index),
      worked: message.worked,
      usage: message.usage,
      cost: _turnCosts[prompt],
    );
  }

  /// Under the status row of the turn under way, the last of all, whether
  /// the row shows or not: how fast the model writes, how long the turn
  /// has taken, and the tokens so far.
  Widget? _liveFooter(int index) {
    if (!_feed.isStreaming || index != _feed.itemCount - 1) return null;
    return switch (_feed.itemAt(index)) {
      LiveStatusItem(:final output, :final startedAt)
          when startedAt != null || (output?.tokens ?? 0) > 0 =>
        TurnFooter(
          live: output ?? const TurnOutput(tokens: 0),
          since: startedAt,
        ),
      _ => null,
    };
  }

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
    final item = _shownAt(index);
    final row = _rowAt(index);
    final l10n = context.l10n;
    return [
      if (row.work case StepFold(:final worked?) && final fold)
        WorkFoldLine.text(
          worked,
          turnEdits(_itemsIn(fold)),
          l10n: l10n,
          stopped: fold.stopped,
        ),
      if (row.steps case final fold?)
        StepsFoldLine.text(StepTally(_itemsIn(fold)), l10n: l10n),
      if (row.item)
        chatItemCopyText(item, expanded: _isExpanded(index), l10n: l10n),
    ].where((text) => text.isNotEmpty).join('\n');
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
  late final AnimationController _editorReveal =
      AnimationController(vsync: this, duration: _motionDuration, value: 1)
        ..addStatusListener((status) {
          if (status.isCompleted) _ensureEditorVisible();
        });

  /// The message's height, where the placeholder grows from.
  double _editorFromHeight = 0;

  /// The message's frame, which the editor's grows from; none if it was not
  /// on screen.
  UserMessageFrame? _editorFrom;

  /// The placeholder's height now, opening or open.
  double get _editorShownHeight =>
      lerpDouble(_editorFromHeight, _editorHeight, _editorOpened)!;

  /// How far the editor has opened (curved), 1 open.
  double get _editorOpened => _editorReveal.isCompleted
      ? 1
      : _motionCurve.transform(_editorReveal.value);

  /// The editor closed, its frame shrinking back into the message's, from
  /// as far as it had opened ([_closingFrom]); the message at [_closingIndex]
  /// is back in the list, under it. Gone once there.
  late final AnimationController _editorClose =
      AnimationController(vsync: this, duration: _motionDuration)
        ..addStatusListener((status) {
          if (status.isCompleted && _closingIndex != null) {
            setState(() => _closingIndex = null);
          }
        });
  int? _closingIndex;
  double _closingFrom = 1;

  /// The user message open for editing, if any, and the text it started
  /// from. The editor lives above the list (see [_buildEditorLayer]); the
  /// list holds a placeholder of its height. Where messages cannot be
  /// edited (e.g. a subagent's), it opens read only, in a viewer in the
  /// editor's place ([_viewerScroll] scrolling it).
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
    _itemCountSeen = _feed.itemCount;
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

  // --- Words streaming in --------------------------------------------------
  //
  // Most of a turn's changes are a few more characters in its last item, or
  // its status row's time and tokens: many a second, from each session
  // streaming. Shown one by one, a long conversation's view is built anew
  // for each, and a dozen at once take the frames from everything else.
  // Such changes show together, at most every [_wordsGap]; the first after
  // a pause at once. An item coming or going, the status row showing or
  // not, a turn starting or ending, the earlier history coming: at once,
  // as before (items fade in, the status row hands over to them, and a
  // sent message's reply stops at its start, from what each change shows).
  // What came meanwhile is in the feed already: only showing it waits.

  /// The least time between showings of streamed words: while watched (at
  /// the end of the conversation, the app in front), and otherwise.
  static const _wordsGap = Duration(milliseconds: 66);
  static const _wordsGapUnwatched = Duration(milliseconds: 250);

  /// Running from the last showing of streamed words until the next may
  /// come; [_wordsWaiting] when words came meanwhile, to show at its end.
  Timer? _wordsCooldown;
  bool _wordsWaiting = false;

  /// The feed's items, as last seen: a change that keeps their number
  /// (and the status row as it was) only streams words.
  int _itemCountSeen = 0;

  bool get _watched =>
      _atBottom &&
      switch (SchedulerBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed => true,
        _ => false,
      };

  /// Shows a change at once; streamed words waiting show with it.
  void _showNow() {
    _wordsWaiting = false;
    setState(() {});
  }

  /// Shows streamed words now, or at the end of the cooldown under way.
  void _showWords() {
    if (_wordsCooldown != null) {
      _wordsWaiting = true;
      return;
    }
    setState(() {});
    _wordsCooldown = Timer(
      _watched ? _wordsGap : _wordsGapUnwatched,
      _wordsCooledDown,
    );
  }

  void _wordsCooledDown() {
    _wordsCooldown = null;
    if (!mounted || !_wordsWaiting) return;
    _wordsWaiting = false;
    _showWords();
  }

  double _editorHeight = 0;
  final Object _editorTapRegion = Object();
  GlobalKey<ChatComposerState> _editComposerKey = GlobalKey();
  final ScrollController _viewerScroll = ScrollController();

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

  /// The press went to a sticky copy of a message, over the list.
  bool _pressOnSticky = false;

  /// The press went to the minimap, beside the list.
  bool _pressOnMinimap = false;

  // --- Scrubbing ---------------------------------------------------------------
  //
  // The minimap's glass or the bar's thumb dragged: each frame a jump to rows
  // not built yet. The list builds none ahead of the view meanwhile (it
  // would build three views' worth a frame, for nothing: the next frame is
  // somewhere else); after, it builds them again by steps.

  /// How far past the view, either side, the list builds rows ahead.
  static const _cacheExtent = 900.0;
  double _cache = _cacheExtent;
  bool _scrubbing = false;
  Timer? _scrubEnded;

  void _scrub(bool on) {
    _scrubEnded?.cancel();
    if (on) {
      _scrubbing = true;
      if (_cache != 0) setState(() => _cache = 0);
      return;
    }
    if (!_scrubbing) return;
    _scrubbing = false;
    _scrubEnded = Timer(const Duration(milliseconds: 150), _buildAhead);
  }

  /// A third of [_cacheExtent] more each frame, until all of it.
  void _buildAhead() {
    if (!mounted || _scrubbing || _cache >= _cacheExtent) return;
    setState(() => _cache = math.min(_cacheExtent, _cache + _cacheExtent / 3));
    SchedulerBinding.instance.addPostFrameCallback((_) => _buildAhead());
  }

  /// Where a press that selects the list's text went down, while held.
  Offset? _dragFrom;
  bool _isPointerInside = false;
  bool _shownAtBottom = true;

  /// Content extends below the viewport, so the bottom fade is needed. Unlike
  /// [_atBottom] this has no tolerance: a few pixels of overflow still show.
  bool _contentBelow = false;
  bool _contentAbove = false;

  /// The devices with a button held down in the list (drag, scrollbar), by
  /// [PointerEvent.device]. Held, or a wheel event just arrived: only then
  /// does a scroll change whether we stick to the bottom.
  final Set<int> _pressedDevices = {};
  int get _pointersDown => _pressedDevices.length;

  /// The conversation's selection: the one copy of it (see
  /// [ChatSelectionController]).
  late final ChatSelectionController _selection = ChatSelectionController(
    plainTextOf: _plainTextOf,
    itemCount: () => _feed.itemCount,
  );
  bool _reselectScheduled = false;

  /// What the text in the list registers with: nothing comes of it (see
  /// [ChatSelectionController]).
  final _inertSelection = StaticSelectionContainerDelegate();

  /// Scrolls the list while a drag selection is held past its edge.
  Ticker? _autoScroll;
  Duration _autoScrolled = Duration.zero;

  final GlobalKey _listKey = GlobalKey();
  final ListController _listController = ListController();
  DateTime _lastWheel = DateTime(0);

  ChatFeed get _feed => widget.feed;
  bool get _atBottom => _scrollController.anchored;

  // --- Find ------------------------------------------------------------------

  final ChatFind _find = ChatFind();
  bool _findShown = false;

  /// The last of [ChatFind.reveals] seen.
  int _findReveals = 0;

  void _findChanged() {
    if (_find.visible != _findShown) {
      _findShown = _find.visible;
      if (!_findShown) widget.onFindClosed?.call();
    }
    if (_find.reveals == _findReveals) return;
    _findReveals = _find.reveals;
    final match = _find.currentMatch;
    if (match == null) return;
    final index = match.item;
    _setAnchored(false);
    if (_isHidden(index)) {
      final folds = [?_folds.workAt(index), ?_folds.stepsAt(index)];
      setState(() {
        for (final fold in folds) {
          _foldOpen[fold.key] = true;
        }
      });
    } else if (_listController.isAttached) {
      // In view, its marks bring the match into view themselves.
      if (_listController.visibleRange case (final first, final last)
          when index >= _itemOfRow(first) && index <= _itemOfRow(last)) {
        return;
      }
    }
    // Brought near, its marks bring the match into view once built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _seek(index, match.fraction);
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController
      ..laidOut = _keepLaidOut
      ..stopAt = _replyStart;
    _find
      ..feed = _feed
      ..addListener(_findChanged);
    _scrollController.addListener(_handleScroll);
    _feed.addListener(_handleSessionChanged);
    _statusIndex = _lastStatusIndex();
    UserMessageStyle.current.addListener(_handleStyleChanged);
    ChatMinimap.side.addListener(_handleStyleChanged);
    UsageLedger.current.addListener(_handleUsageLedgerChanged);
    UsagePrices.current.addListener(_handleUsagePricesChanged);
    // Its size, for a slow frame's line in the event log.
    FrameWatch.notes[this] = _frameNote;
    _wasLive = _feed.isStreaming;
    _prependedSeen = _session?.prependedCount ?? 0;
    _long = _longFeeds[_feed] ?? false;
    _refold();
    _syncUsageSession();
    _seeItems();
    _resumeEditing();
    _goBack();
  }

  /// What a slow frame's line says of it: its items, and what only a live
  /// session holds (subagents' tasks at work, their own conversations).
  String _frameNote() {
    var subagents = 0;
    void count(List<ChatItem> children) {
      subagents += children.length;
      for (final child in children) {
        if (child is AgentItem) count(child.children);
      }
    }

    for (var index = 0; index < _feed.itemCount; index++) {
      if (_feed.itemAt(index) case AgentItem(:final children)) count(children);
    }
    final running = [
      for (final task in _session?.tasks ?? const [])
        if (task.status == CommandStatus.running) task,
    ].length;
    return [
      '${_feed.itemCount} items',
      if (_feed.isStreaming) 'streaming',
      if (running > 0) '$running tasks running',
      if (subagents > 0) '$subagents in subagents',
    ].join(', ');
  }

  /// The row shown first, as last scrolled to while not at the end (see
  /// [_firstShown]): kept as where the history was left.
  ({int index, double above})? _shownFirst;
  bool _shownFirstScheduled = false;

  /// Notes where [feed] is left: none at its end.
  void _noteLeft(ChatFeed feed) {
    final shown = _shownFirst;
    _leftAt[feed] = _atBottom || shown == null
        ? null
        : (
            index: shown.index,
            above: shown.above,
            prepended: _session?.prependedCount ?? 0,
            expanded: {..._expanded},
            folds: {..._foldOpen},
            unfolded: {..._unfoldedTurns},
          );
  }

  /// Back where [_feed] was left, if read up from its end (see [_leftAt]):
  /// its rows moved on by the earlier history read since.
  void _goBack() {
    final left = _leftAt[_feed];
    if (left == null) return;
    final moved = math.max(0, (_session?.prependedCount ?? 0) - left.prepended);
    _expanded.addAll({
      for (final MapEntry(:key, :value) in left.expanded.entries)
        key + moved: value,
    });
    _foldOpen.addAll({
      for (final MapEntry(key: (kind, start), :value) in left.folds.entries)
        (kind, start + moved): value,
    });
    _unfoldedTurns.addAll({for (final start in left.unfolded) start + moved});
    final index = left.index + moved;
    if (index >= _feed.itemCount) return;
    _scrollController.anchored = false;
    _shownAtBottom = false;
    _shownFirst = (index: index, above: left.above);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keepAt(index, left.above);
    });
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
      _long = _longFeeds[widget.feed] ?? false;
      _noteLeft(oldWidget.feed);
      _shownFirst = null;
      oldWidget.feed.removeListener(_handleSessionChanged);
      widget.feed.addListener(_handleSessionChanged);
      _statusIndex = _lastStatusIndex();
      _find.feed = widget.feed;
      // Another conversation: what was selected was in the one before.
      _selection.clear();
      _stickyKeys.clear();
      _stickyIndices = const {};
      _editingIndex = null;
      _closingIndex = null;
      _foldOpen.clear();
      _unfoldedTurns.clear();
      // Another conversation's rows: the list takes them as it finds them.
      _rows = const [];
      _leaving.clear();
      _entering.clear();
      _wasLive = widget.feed.isStreaming;
      _usageSessionId = null;
      _usageSessionVersion = -1;
      _usageCalls = const [];
      _turnCosts = const {};
      _refold();
      _syncUsageSession();
      _seeItems();
      _resumeEditing();
      _goBack();
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
    FrameWatch.notes.remove(this);
    _noteLeft(_feed);
    _steady.dispose();
    _wordsCooldown?.cancel();
    _feed.removeListener(_handleSessionChanged);
    _find
      ..removeListener(_findChanged)
      ..dispose();
    UserMessageStyle.current.removeListener(_handleStyleChanged);
    ChatMinimap.side.removeListener(_handleStyleChanged);
    UsageLedger.current.removeListener(_handleUsageLedgerChanged);
    UsagePrices.current.removeListener(_handleUsagePricesChanged);
    _scrubEnded?.cancel();
    _leavingDone?.cancel();
    _autoScroll?.dispose();
    _letGo();
    _editorMoved.dispose();
    _editorReveal.dispose();
    _editorClose.dispose();
    _viewerScroll.dispose();
    _handoff.dispose();
    _selection.dispose();
    _inertSelection.dispose();
    _menu.remove();
    _listController.dispose();
    _scrollController.dispose();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  /// Open as the user left it; else as [defaultExpanded] says, steadied
  /// while the turn is under way: a thought of a blink stays closed.
  bool _isExpanded(int index) {
    if (_expanded[index] case final open?) return open;
    final item = _shownAt(index);
    final open = defaultExpanded(item);
    if (!_isLive(index) || item is! ThinkingItem) return open;
    return _steady.shows((#open, index), wanted: open);
  }

  /// What row [index] shows: a run of thoughts as one (see [StepFolds]).
  ChatItem _shownAt(int index) => _folds.shownAt(index, _feed.itemAt(index));

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

  // --- Earlier turns -----------------------------------------------------------
  //
  // A long conversation is read from its end (see [LoadsHistory]): the turns
  // before are read when the list is scrolled near its top, or the bar above
  // its first item is pressed. That bar is not a row of the list, so no index
  // is moved by it; the room for it is the list's top padding.

  /// The list's room above its first item: as at its sides (the gutter),
  /// where a message as wide as the chat lets it be sticks too (see
  /// [_stickyInset]); less under a row ([ChatHistoryView.underTitle]). And
  /// the bar's height after it.
  double get _chatTopPadding => widget.underTitle ? 12 : _gutter;
  static const _earlierBarHeight = 40.0;

  /// How near the top the list is scrolled before the earlier turns are read.
  static const _earlierReach = 300.0;

  ChatSession? get _session => switch (_feed) {
    final ChatSession session => session,
    _ => null,
  };

  /// There are earlier turns to read, or they are being read: room for
  /// the bar.
  bool get _earlierRoom => switch (_session) {
    final session? => session.hasEarlierHistory || session.loadingEarlier,
    null => false,
  };

  /// Whether the list was last laid out with room for the bar, and for
  /// whose turns.
  (ChatSession?, bool) _earlierRoomLaidOut = (null, false);

  /// [_earlierRoom], what is in the list kept where it is as the room comes
  /// or goes (the last of the earlier turns read): scrolled by as much,
  /// unless at the top, where the bar goes with it.
  bool _keepEarlierRoom() {
    final session = _session;
    final room = _earlierRoom;
    final (laidOutFor, laidOut) = _earlierRoomLaidOut;
    _earlierRoomLaidOut = (session, room);
    if (!identical(laidOutFor, session) || laidOut == room) return room;
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      if (position.hasPixels && position.pixels > 0) {
        position.correctBy(
          room
              ? _earlierBarHeight
              : -math.min(_earlierBarHeight, position.pixels),
        );
      }
    }
    return room;
  }

  /// Reading them brought nothing: not tried again until asked to.
  bool _earlierFailed = false;
  bool _earlierQueued = false;

  /// How many items were put before the others, as last seen.
  int _prependedSeen = 0;

  /// The first item shown, and how far its top is above the view's, when the
  /// earlier turns were asked for: to put it back where it was.
  ({int index, double above})? _held;

  /// Reads the earlier turns once the frame is done, if the list is near its
  /// top (and it is not the first read, nor under way).
  void _wantEarlier() {
    if (_earlierQueued || _session?.hasEarlierHistory != true) return;
    _earlierQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _earlierQueued = false;
      if (!mounted || _earlierFailed || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      if (position.pixels - position.minScrollExtent <= _earlierReach) {
        _loadEarlier();
      }
    });
  }

  Future<void> _loadEarlier() async {
    final session = _session;
    if (session == null || !session.hasEarlierHistory) return;
    if (session.loadingEarlier) return;
    final before = session.prependedCount;
    _held = _firstShown();
    await session.loadEarlier();
    // Its items come with the kernel's events, a moment later.
    await Future<void>.delayed(Duration.zero);
    _held = null;
    if (!mounted) return;
    final failed =
        session.hasEarlierHistory && session.prependedCount == before;
    if (failed != _earlierFailed) setState(() => _earlierFailed = failed);
    if (!failed) _wantEarlier();
  }

  /// The first row that shows any of it, and how far its top is above the
  /// view's (below it, if less than 0).
  ({int index, double above})? _firstShown() {
    for (final item in _laidOutItems()) {
      if (RenderAbstractViewport.maybeOf(item) case final RenderBox viewport) {
        final top = viewport.localToGlobal(Offset.zero).dy;
        final itemTop = item.localToGlobal(Offset.zero).dy;
        if (itemTop + item.size.height <= top) continue;
        return (index: _indexOf(item), above: top - itemTop);
      }
      return null;
    }
    return null;
  }

  /// [count] items were put before the others: what is kept by index moves
  /// with its items.
  void _shiftIndexes(int count) {
    final expanded = {
      for (final MapEntry(:key, :value) in _expanded.entries)
        key + count: value,
    };
    _expanded
      ..clear()
      ..addAll(expanded);
    final opened = {
      for (final MapEntry(key: (kind, start), :value) in _foldOpen.entries)
        (kind, start + count): value,
    };
    _foldOpen
      ..clear()
      ..addAll(opened);
    final unfolded = {for (final start in _unfoldedTurns) start + count};
    _unfoldedTurns
      ..clear()
      ..addAll(unfolded);
    final motions = {
      for (final MapEntry(:key, :value) in _motions.entries) key + count: value,
    };
    _motions
      ..clear()
      ..addAll(motions);
    // The same rows, of the items now at their indexes; the new ones come
    // with the next [_syncRows].
    _rows = [for (final index in _rows) index + count];
    _leaving.clear();
    _entering.clear();
    _seenItems += count;
    _appearing.clear();
    _endHandoff();
    _stickyKeys.clear();
    _stickyIndices = const {};
    if (_shownFirst case (:final index, :final above)) {
      _shownFirst = (index: index + count, above: above);
    }
    if (_editingIndex case final index?) _editingIndex = index + count;
    if (_closingIndex case final index?) _closingIndex = index + count;
    if (_feed.editing case (:final index, :final draft)) {
      _feed.editing = (index: index + count, draft: draft);
    }
    _selection.shiftItems(count);
  }

  /// [count] rows are put before the others, not laid out yet: the list
  /// takes them as new rows before its first (it would take them as rows
  /// after its last, the extents it measured moved to other rows), and
  /// moves down by them at once, so what is shown stays where it is, not a
  /// frame of them shown in its place. False when it cannot now.
  bool _keepAbove(int count) {
    if (!_scrollController.hasClients ||
        !_listController.isAttached ||
        _listController.isLocked ||
        _listController.numberOfItems != _rows.length) {
      return false;
    }
    final position = _scrollController.position;
    if (!position.hasPixels) return false;
    final shown = _firstShown();
    // Still laid out as it was, at its row before.
    final shownRow = shown == null ? null : _rowOf(shown.index);
    // The new rows, estimated.
    _syncRows();
    var added = 0;
    while (added < _rows.length && _rows[added] < count) {
      added++;
    }
    var above = 0.0;
    for (var row = 0; row < added; row++) {
      above += _listController.extentForIndex(row).$1;
    }
    if (shown case (:final index, above: _)) {
      _keepShown = switch (_endAboveOf(index, laidOutRow: shownRow)) {
        final end? => (
          index: index,
          above: end,
          scrolled: _scrollController.scrolled,
        ),
        null => null,
      };
    }
    // Not a jump: one would take the end as it was, and keep to it.
    position.correctBy(above);
    _forgetRows = true;
    _listKey.currentContext?.findRenderObject()?.markNeedsLayout();
    return true;
  }

  /// The row shown first when rows were put before it, and how far its end
  /// was above the view's top, and the list scrolled then (see
  /// [_BottomAnchoredScrollController.scrolled]): put back there once the
  /// list is laid out.
  ({int index, double above, double scrolled})? _keepShown;

  /// How far the list is to move to put the row shown first back where it
  /// was (see [_keepShown]), once laid out: the rows before it laid out,
  /// those estimated, but the one the view's top came to, measured below
  /// it. Moved on as far as the list was scrolled meanwhile (a wheel's
  /// notch, in the frame they came in), not back.
  double _keepShownLaidOut() {
    final keep = _keepShown;
    _keepShown = null;
    if (keep == null) return 0;
    final above = _endAboveOf(keep.index);
    if (above == null) return 0;
    return keep.above - above + _scrollController.scrolled - keep.scrolled;
  }

  /// How far the list is to move once laid out: the row under a press held
  /// to select kept where it was, if there is one ([_dragRow]); else the
  /// row shown first, rows put before it ([_keepShown]).
  double _keepLaidOut() {
    final shown = _keepShownLaidOut();
    return _keepDragRowLaidOut() ?? shown;
  }

  /// The row under a press held to select, the text in it under the
  /// pointer (the piece the selection's end is in), how far that text's
  /// top was above the view's top, and the list scrolled then: rows above
  /// it folding away (a turn's steps into "Worked for…"), a thought
  /// closing, a line come in above the text in its own row, or a row laid
  /// out taller than taken for move what is under the pointer, and the
  /// selection's end with it, unless the list is moved back by as much (a
  /// browser's scroll anchoring, to the deepest thing under the pointer).
  ({int index, RenderBox? box, double above, double scrolled})? _dragRow;

  /// The row under the pointer held to select, remembered (see
  /// [_dragRow]): at the press, as it moves, and as the list scrolls on.
  void _rememberDragRow() {
    final at = _dragAt ?? _dragFrom;
    final shown = _shownRect();
    final sliver = _findSliver();
    if (at == null ||
        shown == null ||
        sliver == null ||
        !sliver.attached ||
        !_scrollController.hasClients) {
      _dragRow = null;
      return;
    }
    // On screen, as the rows are painted (not laid out: a row's place in
    // the list and where it shows differ by what is over the list).
    final y = at.dy.clamp(shown.top, shown.bottom - 1);
    final pixels = _scrollController.position.pixels;
    RenderBox? row;
    var above = 0.0;
    var bestGap = double.infinity;
    for (var child = sliver.firstChild; child != null;) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      final offset = data.layoutOffset;
      if (offset != null && child.hasSize) {
        final top = child.localToGlobal(Offset.zero).dy;
        final gap = y < top
            ? top - y
            : y > top + child.size.height
            ? y - top - child.size.height
            : 0.0;
        if (gap < bestGap) {
          bestGap = gap;
          row = child;
          above = pixels - sliver.constraints.precedingScrollExtent - offset;
        }
      }
      child = sliver.childAfter(child);
    }
    if (row == null) {
      _dragRow = null;
      return;
    }
    // The piece of text the end is in, if in this row: its top, not the
    // row's.
    RenderBox? box;
    final end = _dragAt != null ? _selection.focus : _selection.anchor;
    if (end != null) {
      final item = _selection.builtItems[end.item];
      final leaves = item != null && item.attached ? item.leaves() : null;
      if (leaves != null && end.leaf < leaves.length) {
        final leaf = leaves[end.leaf].box;
        final inRow = leaf.attached ? _laidOutTopIn(leaf, row) : null;
        if (inRow != null) {
          box = leaf;
          above -= inRow;
        }
      }
    }
    _dragRow = (
      index: _indexOf(row),
      box: box,
      above: above,
      scrolled: _scrollController.scrolled,
    );
  }

  /// Where [box]'s top is in [row], by where each box on the way is laid
  /// out in its parent (in layout: a paint transform may not be asked for
  /// then, and one only painted, as a row coming in slides, is not where
  /// the text is laid out); null if [box] is not in [row].
  static double? _laidOutTopIn(RenderBox box, RenderBox row) {
    var top = 0.0;
    RenderObject node = box;
    while (!identical(node, row)) {
      final data = node.parentData;
      final parent = node.parent;
      if (parent == null) return null;
      if (data is BoxParentData) top += data.offset.dy;
      node = parent;
    }
    return top;
  }

  /// How far the list is to move to put the text under a press held to
  /// select back where it was (see [_dragRow]), moved on as far as the
  /// list was scrolled meanwhile; null while no press is held, or its row
  /// is not laid out.
  double? _keepDragRowLaidOut() {
    final keep = _dragRow;
    if (keep == null) return null;
    if (_dragFrom == null || _pointersDown <= 0) {
      _dragRow = null;
      return null;
    }
    final sliver = _findSliver();
    if (sliver == null) return null;
    for (var child = sliver.firstChild; child != null;) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      final offset = data.layoutOffset;
      if (offset != null && _indexOf(child) == keep.index) {
        var above =
            _scrollController.position.pixels -
            sliver.constraints.precedingScrollExtent -
            offset;
        // Its text's top, where it is in the row now (laid out already);
        // gone (built anew), the row's, from here on.
        var box = keep.box;
        final inRow = box != null && box.attached
            ? _laidOutTopIn(box, child)
            : null;
        if (inRow == null) {
          box = null;
        } else {
          above -= inRow;
        }
        final index = keep.index;
        // Taken to the end, it follows what is written (see
        // [_BottomAnchoredScrollPosition]): that, not this, moves it.
        if (_scrollController.anchored) {
          _dragRow = (
            index: index,
            box: box,
            above: above,
            scrolled: _scrollController.scrolled,
          );
          return null;
        }
        // Built anew, nothing to keep to this time.
        if (keep.box != null && box == null) {
          _dragRow = (
            index: index,
            box: null,
            above: above,
            scrolled: _scrollController.scrolled,
          );
          return null;
        }
        // As far as the list goes: past its top or end it would be put
        // back, and moved again, each time it is laid out.
        final position = _scrollController.position;
        final move =
            (position.pixels +
                    keep.above -
                    above +
                    _scrollController.scrolled -
                    keep.scrolled)
                .clamp(position.minScrollExtent, position.maxScrollExtent) -
            position.pixels;
        // Too little to move it by (see
        // [_BottomAnchoredScrollPosition.applyContentDimensions]): kept to
        // where it was, not to here, for what is left to add up and be made
        // up for once it is enough.
        if (move.abs() < 0.5) return null;
        _dragRow = (
          index: index,
          box: box,
          above: above + move,
          scrolled: _scrollController.scrolled,
        );
        return move;
      }
      child = sliver.childAfter(child);
    }
    return null;
  }

  /// How far row [index]'s end is above the view's top, if it is laid out:
  /// by where the list has it, so also while it is laid out. Its end, not
  /// its top: the room above it is not the same when a turn comes before
  /// it.
  double? _endAboveOf(int index, {int? laidOutRow}) {
    final sliver = _findSliver();
    if (sliver == null || !_scrollController.hasClients) return null;
    for (var child = sliver.firstChild; child != null;) {
      final data = child.parentData! as SliverMultiBoxAdaptorParentData;
      if (laidOutRow == null
          ? _indexOf(child) == index
          : data.index == laidOutRow) {
        final offset = data.layoutOffset;
        if (offset == null) return null;
        return _scrollController.position.pixels -
            sliver.constraints.precedingScrollExtent -
            offset -
            _listController.extentForIndex(_rowOf(index)).$1;
      }
      child = sliver.childAfter(child);
    }
    return null;
  }

  /// The rows laid out are let go before the list is next laid out (see
  /// [_forgetRowsLaidOut]).
  bool _forgetRows = false;

  /// Lets go of the rows laid out, once built with the items now at their
  /// indexes: kept where they are, each would show the item now at its
  /// index where the one before was, and the list keep to them. Laid out
  /// anew, from the extents, the list keeps what is shown in place as it
  /// measures the rows before it.
  void _forgetRowsLaidOut(RenderObject list) {
    if (!_forgetRows) return;
    _forgetRows = false;
    void forget(RenderObject node) {
      if (node is RenderSliverMultiBoxAdaptor) {
        node.visitChildren((child) {
          (child.parentData! as SliverMultiBoxAdaptorParentData).layoutOffset =
              null;
        });
      } else {
        node.visitChildren(forget);
      }
    }

    forget(list);
  }

  /// Puts row [index] where it was (see [_held]), [above] its top above the
  /// view's, once the rows put before it are laid out.
  void _keepAt(int index, double above) {
    if (!_scrollController.hasClients || !_listController.isAttached) return;
    if (index >= _feed.itemCount || _rows.isEmpty) return;
    final height = _scrollController.position.viewportDimension;
    _listController.jumpToItem(
      index: _rowOf(index),
      scrollController: _scrollController,
      alignment: above < 0 && height > 0 ? -above / height : 0,
      rect: Rect.fromLTWH(0, math.max(above, 0), 0, 0),
    );
  }

  /// The bar above the first item: shows the earlier turns are read, as
  /// they are once it is near; reads them on a press, once that brought
  /// nothing. It scrolls with the list.
  Widget _earlierBar() => Positioned.fill(
    child: ListenableBuilder(
      listenable: Listenable.merge([_scrollController, _feed]),
      builder: (context, _) {
        final session = _session;
        final position = _scrollController.hasClients
            ? _scrollController.position
            : null;
        if (session == null ||
            position == null ||
            !position.hasPixels ||
            !(session.hasEarlierHistory || session.loadingEarlier) ||
            position.pixels > _chatTopPadding + _earlierBarHeight) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned(
              top: _chatTopPadding - position.pixels,
              left: 0,
              right: 0,
              height: _earlierBarHeight,
              child: Center(
                child: session.loadingEarlier || !_earlierFailed
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : HoverBuilder(
                        cursor: SystemMouseCursors.click,
                        builder: (context, hovered) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() => _earlierFailed = false);
                            _loadEarlier();
                          },
                          child: Container(
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hovered
                                  ? themeColors['toolbar.hoverBackground']
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              context.l10n.chatLoadEarlier,
                              style: TextStyle(
                                color: hovered
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    ),
  );

  void _handleScroll() {
    // (Held to select, it follows nothing till let go: see
    // [_handlePointerUp].)
    if (_userScrolling && !(_dragFrom != null && _pointersDown > 0)) {
      final position =
          _scrollController.position as _BottomAnchoredScrollPosition;
      final end = position.maxScrollExtent - 1;
      // Re-anchor only at the very end: any tolerance would snap a small
      // scroll up straight back to the bottom on the next layout. Nor while
      // a wheel's notch takes the list up from there: its first frame may
      // move it less than that.
      _scrollController.anchored =
          position.pixels >= end && position.headedTo >= end;
      // Taken to the end: what is written is followed again.
      if (_scrollController.anchored) _toReplyStart = false;
    }
    if (_shownAtBottom != _atBottom) {
      setState(() => _shownAtBottom = _atBottom);
    }
    if (!_atBottom && !_shownFirstScheduled) {
      // Once the rows are laid out where it scrolled to.
      _shownFirstScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _shownFirstScheduled = false;
        if (mounted && !_atBottom) _shownFirst = _firstShown() ?? _shownFirst;
      });
    }
    // Back at the bottom: the turn read meanwhile folds.
    if (_atBottom && _unfoldedTurns.isNotEmpty) {
      setState(_unfoldedTurns.clear);
    }
    _syncEdgeFades();
    _scheduleStickyUpdate();
    if (_dragAt != null) _scheduleDragReselect();
    _wantEarlier();
  }

  /// Scrolling with the wheel or trackpad mid-drag moves text under a
  /// still pointer: the selection's end goes with the pointer, once the
  /// rows are laid out where the list went.
  void _scheduleDragReselect() {
    if (_reselectScheduled) return;
    _reselectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reselectScheduled = false;
      if (mounted) _extendToPointer();
    });
  }

  /// The strip at the right of the list, beside its text: the scrollbar's.
  static const _scrollbarGutter = 24.0;

  /// Where the press that selects is now, once it has moved: the
  /// selection's end follows it.
  Offset? _dragAt;

  /// Whether the list followed what is written before the press held now
  /// (see [_handlePointerDown]).
  bool _followedBeforePress = false;

  /// Whether this view's press holds [ChatSelectionHold] now.
  bool _holding = false;

  void _letGo() {
    if (!_holding) return;
    _holding = false;
    ChatSelectionHold.held.value = false;
  }

  /// Presses in a row in one place: two select a word, three a line.
  int _clicks = 0;
  Duration _lastPress = Duration.zero;
  Offset? _lastPressAt;

  final ContextMenuController _menu = ContextMenuController();

  /// Whether [event] landed on an interactive scrollbar anywhere inside this
  /// view (a table's sideways bar, a code block's, a step card's, …).
  bool _hitScrollbar(PointerDownEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(event.position));
    for (final entry in result.path) {
      if (entry is! BoxHitTestEntry) continue;
      final target = entry.target;
      if (target is RenderCustomPaint) {
        final foreground = target.foregroundPainter;
        if (foreground is ScrollbarPainter &&
            foreground.hitTestInteractive(entry.localPosition, event.kind)) {
          return true;
        }
        final background = target.painter;
        if (background is ScrollbarPainter &&
            background.hitTestInteractive(entry.localPosition, event.kind)) {
          return true;
        }
      }
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pressedDevices.add(event.device);
    _menu.remove();
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
    var onBar = false;
    if (list != null && list.hasSize) {
      final right = list.localToGlobal(Offset(list.size.width, 0)).dx;
      onBar = !_minimapShown && event.position.dx >= right - _scrollbarGutter;
    }
    // Nor one in what selects on its own (an edit card's editor) or on an
    // inner scrollbar (a table's, a code block's, a step card's): dragging a
    // bar must not select text under it or take focus.
    final own = OwnSelection.pressedIn(event);
    final onInnerBar =
        !onBar &&
        !own &&
        !_pressInEditor &&
        !_pressOnSticky &&
        !_pressOnMinimap &&
        _hitScrollbar(event);
    if ((_pressOnMinimap || onBar) && event.buttons == kPrimaryMouseButton) {
      _scrub(true);
    }
    final elsewhere =
        _pressInEditor ||
        own ||
        onBar ||
        onInnerBar ||
        _pressOnSticky ||
        _pressOnMinimap ||
        event.kind != PointerDeviceKind.mouse;
    _dragFrom = elsewhere || event.buttons != kPrimaryMouseButton
        ? null
        : event.position;
    _dragAt = null;
    // A press that may select stops the list following what is written,
    // while held: the text under the pointer would go on up, and the
    // selection's start or end with it. A click lets it follow again; a
    // drag leaves it where it is (taken to the end, it follows again).
    _followedBeforePress = _dragFrom != null && _scrollController.anchored;
    if (_followedBeforePress) _scrollController.anchored = false;
    final onSticky = _pressOnSticky;
    final onMinimap = _pressOnMinimap;
    final inEditor = _pressInEditor;
    _pressOnSticky = false;
    _pressOnMinimap = false;
    if (_pressInEditor) {
      _pressInEditor = false;
    } else if (!own && !onInnerBar) {
      _selectionFocusNode.requestFocus();
    }
    if (!elsewhere && event.buttons & kSecondaryMouseButton != 0) {
      _openMenu(event.position);
      return;
    }
    // A touch on the text (no drag selects with one) lets go of what is
    // selected, as a click does.
    if (elsewhere &&
        event.kind != PointerDeviceKind.mouse &&
        !own &&
        !onBar &&
        !onInnerBar &&
        !onSticky &&
        !onMinimap &&
        !inEditor) {
      _selection.clear();
    }
    if (_dragFrom == null) return;
    // Presses in a row, near each other and soon after each other.
    final again =
        _lastPressAt != null &&
        (event.position - _lastPressAt!).distance <= kDoubleTapSlop &&
        event.timeStamp - _lastPress <= kDoubleTapTimeout;
    _clicks = again ? _clicks + 1 : 1;
    _lastPress = event.timeStamp;
    _lastPressAt = event.position;
    final pos = _selection.positionAt(event.position);
    if (pos == null) {
      _selection.clear();
      return;
    }
    // Shift+click extends the selection (desktop only, as in Flutter).
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => true,
      _ => false,
    };
    if (desktop && HardwareKeyboard.instance.isShiftPressed) {
      _selection.extendNearestTo(pos);
    } else if (_clicks >= 2) {
      final unit = _clicks == 2
          ? TextGranularity.word
          : TextGranularity.paragraph;
      if (_selection.unitAt(pos, unit) case (final start, final end)) {
        _selection.selectUnit(start, end, unit);
      }
    } else {
      _selection.start(pos);
    }
    _rememberDragRow();
    // What follows its own end in the conversation holds still meanwhile.
    ChatSelectionHold.held.value = _holding = true;
  }

  void _handlePointerUp(PointerEvent event) {
    if (!_pressedDevices.remove(event.device)) return;
    final selecting = _dragFrom != null;
    if (_followedBeforePress && _dragAt == null) {
      _scrollController.anchored = true;
    } else if (selecting && _dragAt != null && _scrollController.hasClients) {
      // A drag let go at the end: what is written is followed again (not
      // while held, see [_autoScrollTick]).
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 1) {
        _setAnchored(true);
      }
    }
    _followedBeforePress = false;
    _dragFrom = null;
    _dragAt = null;
    _dragRow = null;
    _letGo();
    // Its focus taken while held (a panel come up): back, for the keys to
    // copy what it selected.
    if (selecting && _selection.hasSelection && !_selectionFocusNode.hasFocus) {
      _selectionFocusNode.requestFocus();
    }
    if (_pointersDown <= 0) {
      _scrub(false);
      _autoScroll?.stop();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final from = _dragFrom;
    if (from == null) return;
    // A press that has not moved is a click, not a drag.
    if (_dragAt == null &&
        (event.position - from).distance < kPrecisePointerHitSlop) {
      return;
    }
    _dragAt = event.position;
    _extendToPointer();
    _rememberDragRow();
    _autoScrollToward(event.position);
  }

  /// What shows of the list, globally: below the stuck message, if one
  /// is.
  Rect? _shownRect() {
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (list == null || !list.attached || !list.hasSize) return null;
    final rect = MatrixUtils.transformRect(
      list.getTransformTo(null),
      Offset.zero & list.size,
    );
    final under = _stickyBottom();
    if (under == null || under < rect.top) return rect;
    return Rect.fromLTRB(
      rect.left,
      math.min(under + 1, rect.bottom - 1),
      rect.right,
      rect.bottom,
    );
  }

  /// The bottom of the stuck message, on screen; null while none is.
  double? _stickyBottom() {
    final cover = _stickyCover();
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (cover == null || list == null || !list.attached || !list.hasSize) {
      return null;
    }
    final bottom = cover + _stickyFade;
    if (bottom <= 0) return null;
    return list.localToGlobal(Offset(0, bottom)).dy;
  }

  /// The selection's moving end to where the pointer is, held, on the text
  /// that shows: past the list's top or bottom (on the title, the
  /// composer), the line at that edge, not one built beyond it and hidden;
  /// over the stuck message, the text just under it (what shows there is a
  /// copy of a message above, not the text the list has under it).
  void _extendToPointer() {
    final at = _dragAt;
    if (at == null) return;
    var used = at;
    final shown = _shownRect();
    if (shown != null) {
      used = Offset(
        at.dx,
        at.dy.clamp(shown.top, math.max(shown.top, shown.bottom - 1)),
      );
    }
    final pos = _selection.positionAt(used, shown: shown);
    if (pos != null) _selection.extendTo(pos, unitAt: _selection.unitAt);
  }

  /// A device moving with no button down, though its release never came
  /// here (let go outside the window, or as another window took the
  /// focus): released now. Held on, its drag's end went on following the
  /// pointer at each wheel step, and scrolling selected text.
  void _handlePointerHover(PointerHoverEvent event) {
    if (_pressedDevices.contains(event.device)) _handlePointerUp(event);
  }

  /// Scrolls while a drag selection is held past an edge.
  void _autoScrollToward(Offset globalPosition) {
    if (_autoScrollSpeed() == 0) return;
    final ticker = _autoScroll ??= createTicker(_autoScrollTick);
    if (ticker.isActive) return;
    _autoScrolled = Duration.zero;
    ticker.start();
  }

  /// How fast the list goes for the drag held where it is, in points a
  /// second (up, less than 0): 30 times how far past its edge, up to 20
  /// points. Over the stuck message as past the top: the list goes on up,
  /// the text under the message coming out from under it.
  double _autoScrollSpeed() {
    final at = _dragAt;
    if (at == null || _pointersDown <= 0 || !_scrollController.hasClients) {
      return 0;
    }
    final scrollable = _scrollController.position.context as ScrollableState;
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return 0;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final under = _stickyBottom();
    final past = under != null && at.dy < under
        ? -math.max(under - at.dy, top - at.dy)
        : at.dy < top
        ? at.dy - top
        : at.dy > bottom
        ? at.dy - bottom
        : 0.0;
    return past.clamp(-20.0, 20.0) * 30;
  }

  /// A frame of it: the list moved on from where it is now (not toward a
  /// place set before, which a row laid out above, its height corrected,
  /// would have moved: the text under the pointer leaping).
  void _autoScrollTick(Duration elapsed) {
    final speed = _autoScrollSpeed();
    if (speed == 0) {
      _autoScroll?.stop();
      return;
    }
    final seconds = (elapsed - _autoScrolled).inMicroseconds / 1e6;
    _autoScrolled = elapsed;
    final position = _scrollController.position;
    final to = (position.pixels + speed * math.min(seconds, 0.05)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((to - position.pixels).abs() < 0.01) return;
    // The row under the pointer as it is now, and the move counted as
    // scrolled: kept moving on, not put back (see [_dragRow]).
    _rememberDragRow();
    final before = position.pixels;
    position.jumpTo(to);
    _scrollController.scrolled += position.pixels - before;
    // Come to the end, it does not follow what is written while held: the
    // text under the pointer would go on up, and the selection's end with
    // it. Let go there, it does.
    _scrollController.anchored = false;
  }

  void _copySelection() {
    final text = _selection.selectedText();
    if (text == null) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  late final Map<Type, Action<Intent>> _selectionActions = {
    CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
      onInvoke: (_) {
        _copySelection();
        return null;
      },
    ),
    SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
      onInvoke: (_) {
        _selection.selectAll();
        return null;
      },
    ),
  };

  /// A right click: a file link's menu on one; else copy and select all,
  /// the word under the pointer selected when nothing is.
  void _openMenu(Offset at) {
    if (fileLinkMenuAt(context, at) case final menu?) {
      unawaited(menu.show(context, at));
      return;
    }
    if (!_selection.hasSelection) {
      if (_selection.positionAt(at) case final pos?) {
        if (_selection.unitAt(pos, TextGranularity.word) case (
          final start,
          final end,
        )) {
          _selection.selectUnit(start, end, TextGranularity.word);
        }
      }
    }
    _menu.show(
      context: context,
      contextMenuBuilder: (context) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(primaryAnchor: at),
        buttonItems: [
          if (_selection.hasSelection)
            ContextMenuButtonItem(
              type: ContextMenuButtonType.copy,
              onPressed: () {
                _copySelection();
                _menu.remove();
              },
            ),
          ContextMenuButtonItem(
            type: ContextMenuButtonType.selectAll,
            onPressed: () {
              _selection.selectAll();
              _menu.remove();
            },
          ),
        ],
      ),
    );
  }

  /// Item [index]'s row, its text in the conversation's selection.
  Widget _selectable(int index, Widget child) => ChatSelectionItemScope(
    index: index,
    controller: _selection,
    // Text scrolled in it (a code block's) has its highlight move with it,
    // and a drag held over it its end with the pointer.
    child: NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _selection.builtItems[index]?.markNeedsPaint();
        if (_dragAt != null) _scheduleDragReselect();
        return false;
      },
      child: ChatSelectionItem(
        index: index,
        controller: _selection,
        color:
            DefaultSelectionStyle.of(context).selectionColor ??
            AppColors.textSelection,
        child: child,
      ),
    ),
  );

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
      // (One given no place in this layout yet, after a jump: not where it
      // shows.)
      final placed =
          (child.parentData! as SliverMultiBoxAdaptorParentData).layoutOffset !=
          null;
      if (placed && child.hasSize && _indexOf(child) < _feed.itemCount) {
        yield child;
      }
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

  /// The item of a laid-out row.
  int _indexOf(RenderBox item) =>
      _itemOfRow((item.parentData! as SliverMultiBoxAdaptorParentData).index!);

  void _syncEdgeFades() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    final below = position.pixels < position.maxScrollExtent - 0.5;
    final above = position.pixels > position.minScrollExtent + 0.5;
    final long =
        _long ||
        position.maxScrollExtent - position.minScrollExtent >=
            position.viewportDimension * ChatMinimap.longAfter;
    if (long) _longFeeds[_feed] = true;
    if (below != _contentBelow || above != _contentAbove || long != _long) {
      setState(() {
        _contentBelow = below;
        _contentAbove = above;
        _long = long;
      });
    }
  }

  bool _handleMetricsChanged(ScrollMetricsNotification notification) {
    // Let go of as it laid out (see [_replyStart]).
    if (_shownAtBottom != _atBottom) {
      setState(() => _shownAtBottom = _atBottom);
    }
    _syncEdgeFades();
    _scheduleStickyUpdate();
    _editorMoved.value++;
    _wantEarlier();
    return false;
  }

  /// Whether the list, following the reply to a message sent, stops with
  /// the message at the top ([ReplyScroll.start]): until the user takes it
  /// back to the end, or the turn ends.
  bool _toReplyStart = false;

  /// The offset that has the message of the turn under way at the top,
  /// as its stuck copy would be, while the list stops there; null while it
  /// does not, or the message is not laid out. Read during layout.
  double? _replyStart() {
    if (!_toReplyStart || ReplyScroll.current.value != ReplyScroll.start) {
      return null;
    }
    final index = (_liveStart ?? 0) - 1;
    if (index < 0) return null;
    for (final item in _laidOutItems()) {
      if (_indexOf(item) != index) continue;
      final offset =
          (item.parentData! as SliverMultiBoxAdaptorParentData).layoutOffset;
      final sliver = item.parent;
      if (offset == null || sliver is! RenderSliver) return null;
      return sliver.constraints.precedingScrollExtent +
          offset +
          _gapBefore(index) -
          _stickyInset;
    }
    return null;
  }

  void _setAnchored(bool value) {
    _scrollController.anchored = value;
    if (_shownAtBottom != value) setState(() => _shownAtBottom = value);
  }

  /// Where the turn's status row is, while it is the last item.
  int? _statusIndex;

  int? _lastStatusIndex() {
    final count = _feed.itemCount;
    return count > 0 && _feed.itemAt(count - 1) is LiveStatusItem
        ? count - 1
        : null;
  }

  void _handleSessionChanged() {
    final prepended = _session?.prependedCount ?? 0;
    final moved = prepended - _prependedSeen;
    _prependedSeen = prepended;
    if (moved > 0) _shiftIndexes(moved);
    // The turn's status row, the last, put on below what came in before
    // it: what is selected in it with it, not on what came in its place.
    final statusWas = _statusIndex == null ? null : _statusIndex! + moved;
    final count = _feed.itemCount;
    _statusIndex = _lastStatusIndex();
    if (statusWas != null &&
        _statusIndex != null &&
        statusWas < count &&
        _feed.itemAt(statusWas) is! LiveStatusItem) {
      _selection.moveItem(statusWas, _statusIndex!);
      if (_dragRow case final row? when row.index == statusWas) {
        _dragRow = (
          index: _statusIndex!,
          box: row.box,
          above: row.above,
          scrolled: row.scrolled,
        );
      }
    }
    final startedStreaming = _feed.isStreaming && !_wasLive;
    final ended = _wasLive && !_feed.isStreaming;
    _wasLive = _feed.isStreaming;
    if (moved > 0 || ended || startedStreaming) _steady.clear();
    // A turn the agent took up on its own (a background task's report)
    // leaves the user reading where they are, the turns they read open.
    final sent = _feed.isStreaming && !_feed.isUnprompted;
    _refold();
    // Once folded: what of them is hidden takes no room.
    if (moved > 0) {
      if (_keepAbove(moved)) {
        _held = null;
      } else if (_held case (:final index, :final above)) {
        _held = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _keepAt(index + moved, above);
        });
      }
    }
    if (sent) _unfoldedTurns.clear();
    if (ended && !_atBottom) {
      if (_lastTurnWork() case final fold?) _unfoldedTurns.add(fold.start);
    }
    final editing = _editingIndex;
    if (startedStreaming) _closingIndex = null;
    if (startedStreaming ||
        (editing != null &&
            (editing >= _feed.itemCount ||
                _feed.itemAt(editing) is! UserMessageItem))) {
      _editingIndex = null;
      _feed.editing = null;
    }
    // Sending a message always brings the live turn into view.
    if (startedStreaming && sent) {
      _jumpToBottom();
      _toReplyStart = true;
    }
    if (ended) _toReplyStart = false;
    final wordsOnly =
        _feed.isStreaming &&
        !startedStreaming &&
        moved == 0 &&
        count == _itemCountSeen &&
        _statusShowing == _statusShown;
    if (!wordsOnly) {
      _syncUsageSession();
      if (_usageCalls.isNotEmpty) _turnCosts = _computeTurnCosts();
    }
    _itemCountSeen = count;
    _itemsCame();
    _scheduleStickyUpdate();
    if (wordsOnly) {
      _showWords();
    } else {
      _showNow();
    }
    _wantEarlier();
  }

  void _startEditing(int index) {
    final item = _feed.itemAt(index);
    if (item is! UserMessageItem) return;
    // Until the editor reports its height, hold the message's.
    final laidOut = _laidOutItems().where((box) => _indexOf(box) == index);
    if (_feed.canEditMessages) {
      _feed.editing = (index: index, draft: ComposerDraft());
    }
    _editorClose.stop();
    setState(() {
      _closingIndex = null;
      _editingIndex = index;
      _editingText = item.text;
      _editingImages = item.images;
      _editComposerKey = GlobalKey();
      _editorHeight = _editorFromHeight = laidOut.isEmpty
          ? 0
          : laidOut.first.size.height - _gapBefore(index);
      _editorFrom = laidOut.isEmpty
          ? null
          : UserMessageBubble.frameIn(laidOut.first);
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
      // Back to the message: from the editor's height to its own, the
      // editor's frame shrinking back into the message's (stuck to the top,
      // to the message's copy there, in one go).
      final animate = !_scrolledPast(index);
      if (animate) _animateItem(index);
      final close =
          animate &&
          _editorFrom != null &&
          !MediaQuery.disableAnimationsOf(context);
      _editorReveal.stop();
      setState(() {
        _editingIndex = null;
        _closingIndex = close ? index : null;
        _closingFrom = _editorOpened;
      });
      if (close) _editorClose.forward(from: 0);
    }
  }

  void _setEditorHeight(double height) {
    if (height == _editorHeight || _editingIndex == null) return;
    setState(() => _editorHeight = height);
    _editorMoved.value++;
    if (_editorReveal.isCompleted) _ensureEditorVisible();
  }

  /// Once the placeholder has its full height, reveal only what extends
  /// below the history. The editor is painted above the list, so its own
  /// scrollable cannot bring it into view there.
  void _ensureEditorVisible() {
    final index = _editingIndex;
    if (index == null) return;
    final key = _editComposerKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _editingIndex != index ||
          _editComposerKey != key ||
          !_scrollController.hasClients) {
        return;
      }
      final placeholder = _editorPlaceholderKey.currentContext
          ?.findRenderObject();
      if (placeholder == null || !placeholder.attached) return;
      unawaited(
        _scrollController.position.ensureVisible(
          placeholder,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  /// Room above the editor stuck to the top of the list: as above the
  /// stuck message it opens from.
  double get _editorInset => _stickyInset;

  /// Where the editor goes, relative to [layer]: on its placeholder, but
  /// never above the top of the list (it sticks there once scrolled past),
  /// unless the user's messages do not stick ([_sticks]). Null when the
  /// placeholder is out of the built items, out of view.
  double? _editorTop(RenderBox layer) {
    final inset = _editorInset;
    // Closing: on the message, below its gap (its placeholder is gone).
    if (_closingIndex case final index?) {
      final item = _laidOutItems()
          .where((box) => _indexOf(box) == index)
          .firstOrNull;
      if (item == null) return null;
      final top =
          item.localToGlobal(Offset(0, _gapBefore(index))).dy -
          layer.localToGlobal(Offset.zero).dy;
      return _sticks ? math.max(top, inset) : top;
    }
    // Not findRenderObject: painted in the frame whose layout dropped the
    // placeholder's item, its element is inactive (and its box detached)
    // until the frame ends.
    final placeholder =
        (_editorPlaceholderKey.currentContext as Element?)?.renderObject
            as RenderBox?;
    if (placeholder != null && placeholder.attached && placeholder.hasSize) {
      final top =
          placeholder.localToGlobal(Offset.zero).dy -
          layer.localToGlobal(Offset.zero).dy;
      return _sticks ? math.max(top, inset) : top;
    }
    final first = _laidOutItems().firstOrNull;
    final index = _editingIndex;
    if (_sticks && first != null && index != null && index < _indexOf(first)) {
      return inset;
    }
    return null;
  }

  // --- The sticky user message ---------------------------------------------

  /// Room above the stuck message: as above the list's first item, and at
  /// its sides where it is as wide as the chat lets it be (the gutter).
  double get _stickyInset => _chatTopPadding;

  /// Height of the fade under the stuck message, over the transcript
  /// scrolling beneath it.
  static const _stickyFade = 16.0;

  /// How far the list scrolls while the stuck message comes in (and goes
  /// as the next pushes it away): as far as the list's top fade reaches.
  double get _stickyEase => _topFade;

  /// How deep the list's top fade is: less under a row, which keeps it
  /// apart from what is above already ([ChatHistoryView.underTitle]).
  double get _topFade => widget.underTitle ? 24 : 32;

  /// Which copies are built is settled after layout, with the items where
  /// the scroll put them: a frame late, but ready before any scroll brings
  /// their message to the top (the one at the top now is built in layout,
  /// besides). Which one shows, and where, is read at paint ([_stickyTop]),
  /// so a copy takes over in the very frame its message scrolls past.
  /// Whether the user's messages stick to the top (see [UserMessageStyle]).
  static bool get _sticks =>
      UserMessageStyle.current.value == UserMessageStyle.sticky;

  void _handleStyleChanged() {
    setState(() {});
    _editorMoved.value++;
    _scheduleStickyUpdate();
  }

  void _scheduleStickyUpdate() {
    if (_stickyUpdateScheduled) return;
    _stickyUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickyUpdateScheduled = false;
      if (!mounted) return;
      final indices = {
        ?_topTurnMessage(),
        if (_sticks)
          for (final item in _laidOutItems())
            if (_sticksAt(_indexOf(item))) _indexOf(item),
      };
      if (setEquals(indices, _stickyIndices)) return;
      _stickyKeys.removeWhere((index, _) => !indices.contains(index));
      setState(() => _stickyIndices = indices);
    });
  }

  /// Whether the item at [index] is a message the user sent, which sticks
  /// at the top: not a subagent's.
  bool _sticksAt(int index) => switch (_feed.itemAt(index)) {
    UserMessageItem(fromAgent: null) => true,
    _ => false,
  };

  /// The user message of the turn at the top of the view: the last one
  /// scrolled past the top. (It keeps the top while the next one, below,
  /// pushes it away.)
  int? _topTurnMessage() {
    if (!_sticks) return null;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (list == null || !list.attached || !list.hasSize) return null;
    int? first;
    int? passed;
    for (final item in _laidOutItems()) {
      final index = _indexOf(item);
      first ??= index;
      if (!_sticksAt(index)) continue;
      if (_messageTop(index, list)! >= _stickyInset) break;
      passed = index;
    }
    if (passed != null || first == null) return passed;
    // Scrolled past long ago: above the laid-out items.
    for (var index = first - 1; index >= 0; index--) {
      if (_sticksAt(index)) return index;
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
      if (next <= index || !_sticksAt(next)) {
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
          topFadeLength: _topFade,
          topFadeAmount: () => 1 - (_stickyIn(index) ?? 1),
          repaint: repaint,
          child: _StickyFollower(
            top: (_) => _stickyTop(index),
            repaint: repaint,
            child: Align(
              alignment: Alignment.topCenter,
              child: Listener(
                onPointerDown: (_) => _pressOnSticky = true,
                // Not in the list: pass scrolling on.
                onPointerSignal: _forwardWheel,
                onPointerPanZoomStart: _startForwardedPan,
                onPointerPanZoomUpdate: _updateEditorPan,
                onPointerPanZoomEnd: _endForwardedPan,
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
                      child: ChatColumn(
                        maxWidth: widget.maxContentWidth,
                        right: _columnRight,
                        left: _columnLeft,
                        room: _room,
                        roomFrom: ChatMinimap.roomFrom,
                        roomRight: _roomRight,
                        child: UserMessageBubble(
                          key: ValueKey(('sticky', index)),
                          text: item.text,
                          images: item.images,
                          onEdit: () => _startEditing(index),
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
    final closing = _editingIndex == null;
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
                _editorClose,
              ]),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: _gutter),
                  child: ChatColumn(
                    maxWidth: widget.maxContentWidth,
                    right: _columnRight,
                    left: _columnLeft,
                    room: _room,
                    roomFrom: ChatMinimap.roomFrom,
                    roomRight: _roomRight,
                    // Opening, the message's frame grows into the editor's;
                    // without one, as much of it as its placeholder has room
                    // for. It does not cover what is below it yet.
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _editorReveal,
                        _editorClose,
                      ]),
                      builder: (context, child) => _editorFrom != null
                          ? UserMessageEditMorph(
                              from: _editorFrom!,
                              progress: closing
                                  ? _closingFrom *
                                        (1 -
                                            _motionCurve.transform(
                                              _editorClose.value,
                                            ))
                                  : _editorOpened,
                              closing: closing,
                              border: _feed.canEditMessages
                                  ? AppColors.bubbleBorder(focused: true)
                                  : AppColors.bubbleBorder(),
                              child: child,
                            )
                          : ClipRect(
                              clipper: _RevealClipper(_editorShownHeight),
                              clipBehavior: _editorReveal.isCompleted
                                  ? Clip.none
                                  : Clip.hardEdge,
                              child: child,
                            ),
                      child: _SizeReporter(
                        // Its own for each message opened: the one before's
                        // editor (closed by the same press) is still here;
                        // were it as tall as this one, its height reported
                        // already, the placeholder would keep the message's.
                        key: ObjectKey(_editComposerKey),
                        onSize: (size) => _setEditorHeight(size.height),
                        // Closing, it is only to be seen.
                        child: IgnorePointer(
                          ignoring: closing,
                          child: ExcludeFocus(
                            excluding: closing,
                            child: Listener(
                              // The editor takes focus itself; see _handlePointerDown.
                              onPointerDown: (_) => _pressInEditor = true,
                              // The editor is not in the list: pass the wheel on.
                              onPointerSignal: _forwardWheel,
                              onPointerPanZoomStart: _startForwardedPan,
                              onPointerPanZoomUpdate: _updateEditorPan,
                              onPointerPanZoomEnd: _endForwardedPan,
                              child: TapRegion(
                                groupId: _editorTapRegion,
                                onTapOutside: _handleTapOutsideEditor,
                                child: !_feed.canEditMessages
                                    ? UserMessageViewer(
                                        text: _editingText,
                                        images: _editingImages,
                                        controller: _viewerScroll,
                                        onClose: _cancelEditing,
                                      )
                                    : ChatComposer(
                                        key: _editComposerKey,
                                        // Only a session's own messages are edited.
                                        session: _feed as ChatSession,
                                        initialText: _editingText,
                                        initialImages: _editingImages,
                                        draft: _feed.editing?.draft,
                                        tapRegionGroupId: _editorTapRegion,
                                        onSubmit: (message) => unawaited(
                                          _submitEdit(index, message),
                                        ),
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
  // Nor does it over the minimap, beside it: that passes all of it on.

  /// Whether the editor's text area has anything to scroll.
  bool get _editorScrolls {
    final inner = _feed.canEditMessages
        ? _editComposerKey.currentState?.editorScrollPosition
        : _viewerScroll.hasClients
        ? _viewerScroll.position
        : null;
    return inner != null && inner.maxScrollExtent > inner.minScrollExtent;
  }

  void _forwardWheel(PointerSignalEvent event) {
    if (_editorScrolls) return; // The text area's, even at its ends.
    _wheelList(event);
  }

  void _wheelList(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      _scrollController.position.pointerScroll(
        (event as PointerScrollEvent).scrollDelta.dy,
      );
    });
  }

  VelocityTracker? _panVelocity;
  double _panForwarded = 0;

  void _startForwardedPan(PointerPanZoomStartEvent event) {
    _panVelocity = VelocityTracker.withKind(event.kind);
    _panForwarded = 0;
  }

  void _updateEditorPan(PointerPanZoomUpdateEvent event) {
    if (!_editorScrolls) _panList(event);
  }

  void _panList(PointerPanZoomUpdateEvent event) {
    if (!_scrollController.hasClients) return;
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
    _panForwarded += delta;
    _panVelocity?.addPosition(event.timeStamp, Offset(0, _panForwarded));
  }

  void _endForwardedPan(PointerPanZoomEndEvent event) {
    final tracker = _panVelocity;
    _panVelocity = null;
    if (tracker == null || _panForwarded == 0) return;
    if (!_scrollController.hasClients) return;
    final velocity = tracker.getVelocity().pixelsPerSecond.dy;
    final position = _scrollController.position;
    if (velocity.abs() > kMinFlingVelocity &&
        position is ScrollPositionWithSingleContext) {
      _lastWheel = DateTime.now();
      position.goBallistic(velocity);
    }
  }

  /// Whether the edited message waits on whether the files go back.
  bool _askingRewind = false;

  Future<void> _submitEdit(int index, ComposerMessage message) async {
    if (_askingRewind) return;
    _askingRewind = true;
    final feed = _feed;
    final bool? revertFiles;
    try {
      revertFiles = feed is ChatSession
          ? await askRewindFiles(context, () => feed.rewindPlanAt(index))
          : false;
    } finally {
      _askingRewind = false;
    }
    // Turned down: still being edited.
    if (revertFiles == null || !mounted || _editingIndex != index) return;
    _feed.editing = null;
    if (!_scrolledPast(index)) _animateItem(index);
    setState(() {
      _editingIndex = null;
      _closingIndex = null;
      // Everything after the message is replaced; so are its steps.
      _expanded.removeWhere((i, _) => i > index);
      _foldOpen.removeWhere((key, _) => key.$2 > index);
      _unfoldedTurns.clear();
    });
    if (feed is ChatSession) {
      feed.editMessage(
        index,
        message,
        from: UserPlace.computer,
        revertFiles: revertFiles,
      );
    } else {
      feed.editMessage(index, message, from: UserPlace.computer);
    }
  }

  /// Row [index] of the list: [child] in the column, [gap] below the row
  /// before it.
  Widget _row(int index, {required double gap, required Widget child}) =>
      ChatColumn(
        maxWidth: widget.maxContentWidth,
        right: _columnRight,
        left: _columnLeft,
        room: _room,
        roomFrom: ChatMinimap.roomFrom,
        roomRight: _roomRight,
        child: Padding(
          // All but the user's messages a little narrower than those.
          padding: EdgeInsets.only(
            top: gap,
            left: _insetOf(index),
            right: _insetOf(index),
          ),
          child: ChatFindRow(
            index: index,
            child: _HeightMotion(
              motion: _motions[index] ?? 0,
              fromNothing: _entering.contains(index),
              child: child,
            ),
          ),
        ),
      );

  // --- Rows ------------------------------------------------------------------
  //
  // The list has a row for each item that shows; a closed fold's items have
  // none. A long conversation is mostly turns' work folded away, thousands
  // of items: rows of no height for them would all be within the list's
  // reach, all built and laid out each time the history is (a second a
  // frame for 5,600 of them). So the list's rows are numbered apart from
  // the items: [_rows] has the item of each.

  /// The item of each row of the list, in order.
  List<int> _rows = const [];

  /// Items a fold closing hides: rows still while they shrink to nothing.
  final Set<int> _leaving = {};
  Timer? _leavingDone;

  /// Items a fold opening shows: their rows, new, grow from nothing.
  final Set<int> _entering = {};

  bool _hasRow(int index) =>
      !_isHidden(index) ||
      index == _editingIndex ||
      _leaving.contains(index) ||
      widget.after?.call(index) != null;

  /// The row of item [index]; for one with none, the row before it (the
  /// first, if none is).
  int _rowOf(int index) {
    var low = 0;
    var high = _rows.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_rows[mid] <= index) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return math.max(0, low - 1);
  }

  /// The item of [row]; past the last item for one past the last row.
  int _itemOfRow(int row) => row < _rows.length ? _rows[row] : _feed.itemCount;

  /// The rows as the items show now. The list is told of each row come or
  /// gone, so the extents it measured stay with their rows.
  void _syncRows() {
    final rows = [
      for (var index = 0; index < _feed.itemCount; index++)
        if (_hasRow(index)) index,
    ];
    if (listEquals(rows, _rows)) return;
    final before = _rows;
    _rows = rows;
    // Not laid out yet, or with other rows (another conversation's): it
    // takes them as it finds them.
    if (!_listController.isAttached ||
        _listController.numberOfItems != before.length) {
      return;
    }
    var old = 0;
    var row = 0;
    while (old < before.length || row < rows.length) {
      if (row == rows.length ||
          (old < before.length && before[old] < rows[row])) {
        _listController.removeItem(row);
        old++;
      } else if (old == before.length || rows[row] < before[old]) {
        _listController.addItem(row);
        row++;
      } else {
        old++;
        row++;
      }
    }
  }

  /// Row [index], folded away while it shrinks to nothing (see [_leaving]).
  Widget _hiddenRow(int index) =>
      _row(index, gap: 0, child: const SizedBox(width: double.infinity));

  double _insetOf(int index) =>
      _feed.itemAt(index) is UserMessageItem ? 0 : UserMessageBubble.radius;

  Widget _buildItem(int index) {
    final item = _shownAt(index);
    if (index == _editingIndex) {
      return AnimatedBuilder(
        animation: _editorReveal,
        builder: (context, _) =>
            SizedBox(key: _editorPlaceholderKey, height: _editorShownHeight),
      );
    }
    final row = _rowAt(index);
    final folds = [?row.work, ?row.steps];
    final footer = switch ((
      _turnFooter(index) ?? _liveFooter(index),
      widget.after?.call(index),
    )) {
      (final footer, null) => footer,
      (null, final after?) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: after,
      ),
      (final footer?, final after?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          footer,
          Padding(padding: const EdgeInsets.only(top: 10), child: after),
        ],
      ),
    };
    // Folded away (what the turn under way has written showing still).
    if (folds.isEmpty && !row.item) {
      return footer == null
          ? const SizedBox(width: double.infinity)
          : SizedBox(width: double.infinity, child: footer);
    }
    Widget? shown;
    if (row.item) {
      final view = ChatItemView(
        key: item is LiveStatusItem ? _statusKey : ValueKey(index),
        item: item,
        expanded: _isExpanded(index),
        onToggle: () => _toggle(index),
        onEdit: item is UserMessageItem && item.fromAgent == null
            ? () => _startEditing(index)
            : null,
        onMoveToBackground: _feed.moveToBackgroundAt(index),
        onStop: _feed.stopAt(index),
        onOpen: switch ((item, widget.onOpenAgent)) {
          (final AgentItem agent, final open?) when agent.id != null =>
            () => open(agent),
          _ => null,
        },
        onSetGoal: widget.onSetGoal,
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
    return _selectable(
      index,
      folds.isEmpty && footer == null
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
                      stopped: fold.stopped,
                      edits: turnEdits(_itemsIn(fold)),
                      images: foldImages(_itemsIn(fold)),
                      webIcons: foldWebIcons(_itemsIn(fold)),
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
                      images: foldImages(_itemsIn(fold)),
                      webIcons: foldWebIcons(_itemsIn(fold)),
                      expanded: _isFoldOpen(fold),
                      onToggle: () => _toggleFold(fold),
                    ),
                  ?shown,
                  ?footer,
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

  /// The height taken for [row] until it is laid out, toward the list's
  /// extent (and so its scrollbar): none for one a closed fold hides (see
  /// [_leaving]). (Asked with no row, the list wants one height for all,
  /// unless none: 0.)
  double _estimateExtent(int? row, double crossAxisExtent) => switch (row) {
    null => 0,
    _ when row < _rows.length && _isHidden(_rows[row]) => 0,
    _ => 100,
  };

  void _jumpToBottom() {
    _toReplyStart = false;
    _setAnchored(true);
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      position.jumpTo(position.maxScrollExtent);
    }
  }

  void _setPointerInside(bool value) {
    if (_isPointerInside != value) setState(() => _isPointerInside = value);
  }

  // --- Minimap ---------------------------------------------------------------

  /// Row [index] as the minimap samples it.
  ChatMinimapRow _minimapRow(int index) {
    final item = _shownAt(index);
    final row = _rowAt(index);
    final hidden = row.work == null && row.steps == null && !row.item;
    return (
      item: item,
      shown: row.item,
      foldLines:
          (row.work?.worked != null ? 1 : 0) + (row.steps != null ? 1 : 0),
      gap: hidden ? 0 : _gapBefore(index),
    );
  }

  /// The list's sliver, as last found; found again once it is gone.
  RenderSliverMultiBoxAdaptor? _sliver;

  /// The rows in view, as laid out: the first and the last, and how far
  /// down each the view's edge is. Read every frame of a scroll (by the
  /// minimap, as it paints): from where the list laid them out, along it.
  ChatMinimapSpan? _spanInView() {
    var sliver = _sliver;
    if (sliver == null || !sliver.attached) sliver = _sliver = _findSliver();
    if (sliver == null || sliver.geometry == null) return null;
    final view = sliver.constraints.viewportMainAxisExtent;
    // Where the sliver paints from in the view: its padding's and its own
    // offsets.
    var lead = 0.0;
    for (
      RenderObject? node = sliver;
      node is RenderSliver;
      node = node.parent
    ) {
      if (node.parentData case final SliverPhysicalParentData data) {
        lead += data.paintOffset.dy;
      }
    }
    final count = _feed.itemCount;
    int? first;
    int? last;
    var firstAt = 0.0;
    var lastAt = 1.0;
    for (var item = sliver.firstChild; item != null;) {
      final index = _indexOf(item);
      final height = item.hasSize ? item.size.height : 0.0;
      if (index < count && height > 0) {
        final top = lead + sliver.childMainAxisPosition(item);
        if (top >= view) break;
        if (top + height > 0) {
          if (first == null) {
            first = index;
            firstAt = (-top / height).clamp(0.0, 1.0);
          }
          last = index;
          lastAt = ((view - top) / height).clamp(0.0, 1.0);
        }
      }
      item = sliver.childAfter(item);
    }
    if (first == null || last == null) return null;
    return (first: first, firstAt: firstAt, last: last, lastAt: lastAt);
  }

  /// Scrolls row [index] to the top of the view, [fraction] of the way
  /// down it, laid out yet or not.
  void _seek(int index, double fraction) {
    if (!_scrollController.hasClients || !_listController.isAttached) return;
    if (index >= _feed.itemCount || _rows.isEmpty) return;
    _setAnchored(false);
    final row = _rowOf(index);
    final (extent, _) = _listController.extentForIndex(row);
    _listController.jumpToItem(
      index: row,
      scrollController: _scrollController,
      alignment: 0,
      rect: Rect.fromLTWH(0, fraction * extent, 0, 0),
    );
  }

  /// The column's left and width in the history, [width] wide: as
  /// [_buildHistory] lays it out.
  ({double left, double width}) _columnIn(double width) {
    final gutter = chatGutter(width);
    final column = RenderChatColumn.place(
      width - 2 * gutter,
      maxWidth: widget.maxContentWidth,
      right: math.max(0.0, _inset - gutter),
      left: math.max(0.0, _insetLeft - gutter),
      room: _roomAt(gutter),
      roomFrom: ChatMinimap.roomFrom,
      roomRight: _roomRight,
    );
    return (left: gutter + column.left, width: column.width);
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

  /// How far the column keeps clear of the right margin's inner edge, for
  /// what floats at the right of the chat (see [ChatColumnInset]).
  double _columnRight = 0;

  /// What floats at the right of the chat takes, as last built (see
  /// [ChatColumnInset]).
  double _inset = 0;

  /// As [_columnRight] and [_inset], at the left (the side panel at the
  /// conversations' left).
  double _columnLeft = 0;
  double _insetLeft = 0;

  /// Whether the history is long: what it does not show is more than
  /// [ChatMinimap.longAfter] of what it does, as last laid out (estimated
  /// past what is built: near enough). Once it is, it stays so for the
  /// conversation: its steps folded and unfolded, an early one most of
  /// all, do not take the minimap away and bring it back.
  bool _long = false;

  /// Whether there is a minimap to show: once the history is [_long].
  bool get _wantsMinimap => _long && _feed.itemCount > 0;

  /// Whether the column keeps room for the minimap: once there is one to
  /// show. Narrower then, the history only grows taller, and scrolls on.
  bool get _keepsRoom => widget.minimap && _wantsMinimap;

  /// The room the column keeps either side of it for the minimap, within
  /// the margin of [gutter] (see [ChatColumn.room]).
  double _roomAt(double gutter) =>
      _keepsRoom ? math.max(0.0, ChatMinimap.room - gutter) : 0;

  double get _room => _roomAt(_gutter);

  /// Whether the room is the column's right (see [ChatMinimap.side]).
  bool get _roomRight => ChatMinimap.side.value == ChatMinimapSide.right;

  /// Whether the minimap has room beside the column, as last built.
  bool _minimapFits = false;

  /// Whether the minimap shows: the scrollbar then does not, it stands in
  /// for it.
  bool get _minimapShown => _minimapFits && _wantsMinimap;

  /// The history as built for [_gutter] and [_columnRight], until this
  /// builds again: a new width with the same margin (a pane being resized)
  /// only lays it out anew, rather than build (and parse) every message
  /// shown each frame.
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    _built = null;
    _syncRows();
    if (widget.minimapRoom case final room? when room.value != _keepsRoom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) room.value = _keepsRoom;
      });
    }
    final inset = _inset = ChatColumnInset.of(context);
    final insetLeft = _insetLeft = ChatColumnInset.leftOf(context);
    // A picture shown whole goes on to the others: ← and →.
    return ChatImages(
      all: _images,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = chatGutter(constraints.maxWidth);
          final right = math.max(0.0, inset - gutter);
          final left = math.max(0.0, insetLeft - gutter);
          final minimapFits =
              widget.minimap &&
              ChatMinimap.besides(
                    _columnIn(constraints.maxWidth),
                    width: constraints.maxWidth,
                    side: ChatMinimap.side.value,
                  ) !=
                  null;
          if (_built == null ||
              gutter != _gutter ||
              right != _columnRight ||
              left != _columnLeft ||
              minimapFits != _minimapFits) {
            _gutter = gutter;
            _columnRight = right;
            _columnLeft = left;
            _minimapFits = minimapFits;
            _built = _buildHistory(context);
          }
          return _built!;
        },
      ),
    );
  }

  /// Every picture the chat's tools returned, in order.
  List<ChatImage> _images() =>
      foldImages([for (var i = 0; i < _feed.itemCount; i++) _feed.itemAt(i)]);

  Widget _buildHistory(BuildContext context) {
    final outerBars = ScrollbarTheme.of(context);
    return Shortcuts(
      shortcuts: _selectionShortcuts,
      // Sees every press and wheel event, the scrollbar's too.
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerUp,
        onPointerMove: _handlePointerMove,
        onPointerHover: _handlePointerHover,
        // Runs before the list handles the signal (that is resolved after
        // every target has seen it).
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) _lastWheel = DateTime.now();
        },
        child: MouseRegion(
          onEnter: (_) => _setPointerInside(true),
          onExit: (_) => _setPointerInside(false),
          // The list's own bar, shown while the pointer is in and the minimap
          // is not.
          child: ScrollbarTheme(
            data: outerBars.copyWith(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (!_isPointerInside || _minimapShown) {
                  return Colors.transparent;
                }
                final colors = themeColors;
                if (states.contains(WidgetState.dragged)) {
                  return colors['scrollbarSlider.activeBackground'];
                }
                if (states.contains(WidgetState.hovered)) {
                  return colors['scrollbarSlider.hoverBackground'];
                }
                return colors['scrollbarSlider.background'];
              }),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Above the selection: the bar takes a press on it alone (what
                // it covers is not hit-tested), so dragging it never selects.
                Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: !_minimapShown,
                  // What is in the list keeps the bars it had (a table's).
                  child: ScrollbarTheme(
                    data: outerBars,
                    // Focused on a press rather than hover, so the composer
                    // keeps the keys while the pointer passes over the
                    // history.
                    // (Its actions around the focus, which looks for them
                    // from where it is up.)
                    child: Actions(
                      actions: _selectionActions,
                      child: Focus(
                        focusNode: _selectionFocusNode,
                        // The text's selection is the conversation's (see
                        // [_selectable]), not Flutter's: the text registers
                        // here, which says it is text to select (an icon is
                        // not), and is sent nothing.
                        child: SelectionContainer(
                          delegate: _inertSelection,
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
                                  topFadeLength: _topFade,
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
                                    child: ChatFindScope(
                                      find: _find,
                                      child: _BeforeLayout(
                                        key: _listKey,
                                        onLayout: _forgetRowsLaidOut,
                                        child: SuperListView.builder(
                                          controller: _scrollController,
                                          listController: _listController,
                                          itemCount: _rows.length,
                                          // Rows come and go before others
                                          // (folds opening and closing):
                                          // each keeps its own.
                                          findChildIndexCallback: (key) =>
                                              switch (key) {
                                                ValueKey<int>(:final value)
                                                    when _rows.isNotEmpty &&
                                                        _rows[_rowOf(value)] ==
                                                            value =>
                                                  _rowOf(value),
                                                _ => null,
                                              },
                                          extentEstimation: _estimateExtent,
                                          cacheExtent: _cache,
                                          padding: EdgeInsets.fromLTRB(
                                            _gutter,
                                            _chatTopPadding +
                                                (_keepEarlierRoom()
                                                    ? _earlierBarHeight
                                                    : 0),
                                            _gutter,
                                            24,
                                          ),
                                          itemBuilder: (context, row) {
                                            final index = _rows[row];
                                            return KeyedSubtree(
                                              key: ValueKey(index),
                                              child:
                                                  _isHidden(index) &&
                                                      index != _editingIndex &&
                                                      widget.after?.call(
                                                            index,
                                                          ) ==
                                                          null
                                                  ? _hiddenRow(index)
                                                  : _row(
                                                      index,
                                                      gap: _gapBefore(index),
                                                      child: _buildItem(index),
                                                    ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _earlierBar(),
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
                                            _feed.itemAt(index)
                                                is UserMessageItem)
                                          Positioned.fill(
                                            key: ValueKey(('sticky', index)),
                                            child: _buildSticky(index),
                                          ),
                                    ],
                                  ),
                                ),
                              ),
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
                // Over the list, outside its selection: the editor's presses,
                // keys and right clicks are its own, its text selected by it
                // alone (the history's selection took drags begun in it, and
                // ⌘C with nothing selected in it copied what the history had).
                if (_editingIndex ?? _closingIndex case final index?)
                  _buildEditorLayer(index),
                // Beside the list, not over it: a press on it selects nothing.
                if (widget.minimap)
                  Positioned.fill(
                    child: ChatMinimap(
                      // Another conversation's: its glass not sprung over
                      // from where the last one's was.
                      key: ObjectKey(_feed),
                      rowCount: _feed.itemCount,
                      rowAt: _minimapRow,
                      span: _spanInView,
                      moved: Listenable.merge([
                        _scrollController,
                        _editorMoved,
                      ]),
                      columnIn: _columnIn,
                      at: ChatMinimap.side.value,
                      long: _long,
                      scrolling: () =>
                          _scrollController.hasClients && _userScrolling,
                      onSeek: _seek,
                      onSeekEnd: _jumpToBottom,
                      onPointerDown: (_) => _pressOnMinimap = true,
                      onPointerSignal: _wheelList,
                      onPointerPanZoomStart: _startForwardedPan,
                      onPointerPanZoomUpdate: _panList,
                      onPointerPanZoomEnd: _endForwardedPan,
                    ),
                  ),
                // Over the history's top right, as the editor's; over the
                // side panel's rail too, where it floats there.
                Positioned(
                  top: 0,
                  left: _gutter,
                  right: _gutter,
                  child: _inset > 0 ? _OverRail(child: _findBar()) : _findBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _findBar() => Align(
    alignment: Alignment.topRight,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: IdeFindWidget.width),
      child: ChatFindBar(find: _find),
    ),
  );
}

/// [child] where it would be laid out, but in the overlay: over what floats
/// over the chat (the side panel's rail, which is outside it).
class _OverRail extends StatefulWidget {
  const _OverRail({required this.child});

  final Widget child;

  @override
  State<_OverRail> createState() => _OverRailState();
}

class _OverRailState extends State<_OverRail> {
  final _portal = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _portal,
    overlayChildBuilder: (context, info) {
      final rect = MatrixUtils.transformRect(
        info.childPaintTransform,
        Offset.zero & info.childSize,
      );
      return Stack(
        children: [
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            child: widget.child,
          ),
        ],
      );
    },
    child: const SizedBox(height: 0),
  );
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
class _BottomAnchoredScrollController extends SmoothScrollController {
  bool anchored = true;

  /// While [anchored]: the furthest it follows to, if anywhere; there it
  /// lets go (see [ReplyScroll.start]).
  double? Function()? stopAt;

  /// Once the list is laid out: how far to move it, laid out again then.
  double Function()? laidOut;

  /// How far the list has been scrolled in all (a wheel, a drag, a fling):
  /// not what layout corrects it by.
  double scrolled = 0;

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

/// A mouse wheel's notches glide it ([WheelGliding]), each frame by what
/// the curve went since the last: the list moves itself as it lays out a
/// row above for the first time, taller or shorter than it took it for
/// (see [_ChatHistoryViewState._estimateExtent]), to keep what shows where
/// it was; all the way up a conversation just opened. That stays moved.
class _BottomAnchoredScrollPosition extends ScrollPositionWithSingleContext
    with WheelGliding {
  _BottomAnchoredScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _BottomAnchoredScrollController controller;

  @override
  double setPixels(double newPixels) {
    final before = pixels;
    final overscroll = super.setPixels(newPixels);
    controller.scrolled += pixels - before;
    return overscroll;
  }

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
    if (controller.anchored && hasPixels && activity is! DragScrollActivity) {
      if (controller.stopAt?.call() case final stop?
          when stop < maxScrollExtent) {
        // As far as it follows: let go there (or here, past it already).
        controller.anchored = false;
        final target = math
            .max(stop, pixels)
            .clamp(minScrollExtent, maxScrollExtent);
        if (target != pixels) {
          correctPixels(target);
          return false;
        }
      }
    }
    if (controller.anchored &&
        hasPixels &&
        pixels != maxScrollExtent &&
        activity is! DragScrollActivity) {
      // Re-run layout at the new offset; the virtual list may refine its
      // extent estimate for the tail, which converges in a pass or two.
      correctPixels(maxScrollExtent);
      return false;
    }
    final move = hasPixels ? controller.laidOut?.call() ?? 0.0 : 0.0;
    if (move.abs() >= 0.5) {
      correctPixels(pixels + move);
      return false;
    }
    return accepted;
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
  const _SizeReporter({super.key, required this.onSize, required super.child});

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
            child: IgnorePointer(child: ChatUnselectable(child: row)),
          ),
      ],
    );
  }
}

/// Its child, and when [motion] changes, the child's next change of height
/// over a moment rather than at once; any other change at once. Moving
/// already, it takes a new height in its stride.
class _HeightMotion extends StatefulWidget {
  const _HeightMotion({
    required this.motion,
    this.fromNothing = false,
    required this.child,
  });

  final int motion;

  /// New, it grows from no height (with [motion] changed, as it would
  /// have, had it been there).
  final bool fromNothing;
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
    fromNothing: widget.fromNothing,
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
    required this.fromNothing,
    required this.progress,
    required this.onStart,
    super.child,
  });

  final int motion;
  final bool fromNothing;
  final Animation<double> progress;
  final VoidCallback onStart;

  @override
  _RenderHeightMotion createRenderObject(BuildContext context) =>
      _RenderHeightMotion(
        motion,
        progress,
        onStart: onStart,
        fromNothing: fromNothing,
      );

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
  _RenderHeightMotion(
    this._motion,
    this._progress, {
    required this.onStart,
    bool fromNothing = false,
  }) {
    if (fromNothing) {
      _from = _to = 0;
      _armed = true;
    }
  }

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
      _clipRect,
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  Rect get _clipRect => Rect.fromLTRB(-80, -80, size.width + 80, size.height);

  // What is cut off does not show: not a place to select in (see
  // RenderChatSelectionItem.positionAt), nor where floating elements show.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      this.child != null && size.height < this.child!.size.height
      ? _clipRect
      : null;
}

/// [child], [onLayout] called with it before it is laid out (once what is
/// in it is built).
class _BeforeLayout extends SingleChildRenderObjectWidget {
  const _BeforeLayout({super.key, required this.onLayout, super.child});

  final void Function(RenderObject child) onLayout;

  @override
  _RenderBeforeLayout createRenderObject(BuildContext context) =>
      _RenderBeforeLayout(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBeforeLayout renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderBeforeLayout extends RenderProxyBox {
  _RenderBeforeLayout(this.onLayout);

  void Function(RenderObject child) onLayout;

  @override
  void performLayout() {
    if (child case final child?) onLayout(child);
    super.performLayout();
  }
}
