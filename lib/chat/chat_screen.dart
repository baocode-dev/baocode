import 'package:flutter/material.dart';

import '../theme/cursor_theme.dart';
import 'chat_history_view.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'panels/activity_strip.dart';
import 'panels/ask_question_panel.dart';
import 'panels/context_usage_panel.dart';

/// Layout, top to bottom:
/// - history + live turn: a virtual list that yields height;
/// - feedback / modal / indicator panels: take the height they need;
/// - the composer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.title = 'Optimize virtual list scrolling',
    this.session,
  });

  final String title;
  final ChatSession? session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxContentWidth = 760.0;

  late final ChatSession _session = widget.session ?? ChatSession();
  final GlobalKey<ChatComposerState> _composerKey = GlobalKey();
  bool _contextPanelOpen = false;

  @override
  void dispose() {
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  void _toggleContextPanel() {
    setState(() => _contextPanelOpen = !_contextPanelOpen);
  }

  void _answerQuestion(String summary) {
    _session.answerQuestion(summary);
    _composerKey.currentState?.focus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Transparent Flutter-owned title bar under the native traffic lights.
          Container(
            height: 30,
            alignment: Alignment.center,
            child: Text(
              widget.title,
              style: const TextStyle(
                color: CursorColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ChatHistoryView(
              session: _session,
              maxContentWidth: _maxContentWidth,
            ),
          ),
          ListenableBuilder(
            listenable: _session,
            builder: (context, _) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _maxContentWidth + 48,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PanelSlot(
                        child: switch (_session.pendingQuestion) {
                          final request? => AskQuestionPanel(
                            key: ObjectKey(request),
                            request: request,
                            onSubmit: _answerQuestion,
                          ),
                          null => null,
                        },
                      ),
                      _PanelSlot(
                        child: _contextPanelOpen
                            ? ContextUsagePanel(
                                session: _session,
                                onClose: _toggleContextPanel,
                              )
                            : null,
                      ),
                      _PanelSlot(
                        gap: 0,
                        child: ActivityStrip.hasContent(_session)
                            ? ActivityStrip(session: _session)
                            : null,
                      ),
                      ChatComposer(
                        key: _composerKey,
                        session: _session,
                        contextPanelOpen: _contextPanelOpen,
                        onToggleContextPanel: _toggleContextPanel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A panel above the composer, or nothing. It appears and disappears at
/// once (no size or fade transition): the history above yields the height.
class _PanelSlot extends StatelessWidget {
  const _PanelSlot({required this.child, this.gap = 8});

  final Widget? child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final panel = child;
    if (panel == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: panel,
    );
  }
}
