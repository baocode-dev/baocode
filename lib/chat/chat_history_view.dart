import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../theme/cursor_theme.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'widgets/chat_item_view.dart';

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
  final Set<int> _expandedThinking = <int>{};
  bool _isPointerInside = false;
  bool _wasStreaming = false;
  bool _shownAtBottom = true;

  /// Content extends below the viewport, so the bottom fade is needed. Unlike
  /// [_atBottom] this has no tolerance: a few pixels of overflow still show.
  bool _contentBelow = false;

  /// Pointer held down in the list (drag, scrollbar) or a wheel event just
  /// arrived: only then does a scroll change whether we stick to the bottom.
  int _pointersDown = 0;
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
    _scrollController.dispose();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  void _toggleThinking(int index) {
    setState(() {
      if (!_expandedThinking.add(index)) {
        _expandedThinking.remove(index);
      }
    });
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
    _syncContentBelow();
  }

  void _syncContentBelow() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    final below = position.pixels < position.maxScrollExtent - 0.5;
    if (below != _contentBelow) setState(() => _contentBelow = below);
  }

  bool _handleMetricsChanged(ScrollMetricsNotification notification) {
    _syncContentBelow();
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
    if (startedStreaming) _jumpToBottom();
    setState(() {});
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
          onPointerDown: (_) {
            _pointersDown++;
            _selectionFocusNode.requestFocus();
          },
          onPointerUp: (_) => _pointersDown--,
          onPointerCancel: (_) => _pointersDown--,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _lastWheel = DateTime.now();
          },
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
                child: Stack(
                  fit: StackFit.expand,
                  // Lets the bottom fade overshoot the list edge.
                  clipBehavior: Clip.none,
                  children: [
                    NotificationListener<ScrollMetricsNotification>(
                      onNotification: _handleMetricsChanged,
                      child: SuperListView.builder(
                        controller: _scrollController,
                        itemCount: _session.itemCount,
                        cacheExtent: 900,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
                                child: ChatItemView(
                                  key: ValueKey(index),
                                  item: _session.itemAt(index),
                                  expanded: _expandedThinking.contains(index),
                                  onToggle: () => _toggleThinking(index),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Soft fade where content continues below the edge (none
                    // when pinned to the bottom: nothing is below). It
                    // overshoots the list by 2px: on screen the bottom edge
                    // can fall mid-pixel, and the list's clip keeps that
                    // whole row while an edge-aligned fade only half covers
                    // it, leaving a sliver of glyphs above the panels. The
                    // panels paint over the overshoot.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -2,
                      height: 30,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _contentBelow ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x00181818),
                                  Color(0x99181818),
                                  CursorColors.background,
                                ],
                                stops: [0, 0.5, 0.75],
                              ),
                            ),
                          ),
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
