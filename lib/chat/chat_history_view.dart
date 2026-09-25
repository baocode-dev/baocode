import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../theme/cursor_theme.dart';
import 'chat_models.dart';
import 'mock_conversation.dart';
import 'widgets/chat_item_view.dart';

/// Virtualized, selectable conversation history.
class ChatHistoryView extends StatefulWidget {
  const ChatHistoryView({super.key, this.maxContentWidth = 760});

  final double maxContentWidth;

  @override
  State<ChatHistoryView> createState() => _ChatHistoryViewState();
}

class _ChatHistoryViewState extends State<ChatHistoryView> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'Monad chat selection',
  );
  final Set<int> _expandedThinking = <int>{};
  bool _isPointerInside = false;

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

  void _setPointerInside(bool value) {
    if (_isPointerInside != value) setState(() => _isPointerInside = value);
  }

  /// Vertical gap above [index]: roomy between turns, tight between tool rows.
  static double _gapBefore(int index) {
    if (index == 0) return 0;
    final item = MockConversation.itemAt(index);
    final previous = MockConversation.itemAt(index - 1);
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
        child: MouseRegion(
          onEnter: (_) {
            _selectionFocusNode.requestFocus();
            _setPointerInside(true);
          },
          onExit: (_) => _setPointerInside(false),
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              thumbColor: WidgetStatePropertyAll(
                _isPointerInside ? const Color(0xFF4A4A4A) : Colors.transparent,
              ),
            ),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SuperListView.builder(
                    controller: _scrollController,
                    itemCount: MockConversation.itemCount,
                    cacheExtent: 900,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 64),
                    itemBuilder: (context, index) {
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: widget.maxContentWidth,
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(top: _gapBefore(index)),
                            child: ChatItemView(
                              key: ValueKey(index),
                              item: MockConversation.itemAt(index),
                              expanded: _expandedThinking.contains(index),
                              onToggle: () => _toggleThinking(index),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 32,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00181818),
                              CursorColors.background,
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
}
