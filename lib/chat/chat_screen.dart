import 'package:flutter/material.dart';

import '../theme/cursor_theme.dart';
import 'chat_history_view.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'panels/activity_strip.dart';
import 'panels/ask_question_panel.dart';
import 'panels/context_usage_panel.dart';
import 'widgets/inline_rename_field.dart';

/// Layout, top to bottom:
/// - history + live turn: a virtual list that yields height;
/// - feedback / modal / indicator panels: take the height they need;
/// - the composer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.title = 'Optimize virtual list scrolling',
    this.session,
    this.leading,
    this.trailing,
    this.titleBarInset,
    this.onRename,
    this.autofocus = false,
  });

  final String title;
  final ChatSession? session;

  /// Before the title, e.g. a button to show the sidebar.
  final Widget? leading;

  /// At the right of the title bar, e.g. a button to open the project.
  final Widget? trailing;

  /// Left of the title bar's content: by default clear of the native
  /// traffic lights, as when this is the whole window.
  final double? titleBarInset;

  /// Given, a double click on the title edits it.
  final ValueChanged<String>? onRename;

  /// Focuses the composer once shown, e.g. for a new agent.
  final bool autofocus;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxContentWidth = 720.0;

  late final ChatSession _session = widget.session ?? ChatSession();
  final GlobalKey<ChatComposerState> _composerKey = GlobalKey();
  bool _contextPanelOpen = false;
  bool _renaming = false;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerKey.currentState?.focus();
      });
    }
  }

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

  Widget _buildTitleBar() {
    const style = TextStyle(
      color: CursorColors.textMuted,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
    );
    final onRename = widget.onRename;
    final Widget title;
    if (_renaming && onRename != null) {
      title = SizedBox(
        width: 320,
        child: InlineRenameField(
          initial: widget.title,
          style: style.copyWith(color: CursorColors.textPrimary),
          onDone: (text) {
            if (text != null) onRename(text);
            setState(() => _renaming = false);
          },
        ),
      );
    } else {
      title = GestureDetector(
        onDoubleTap: onRename == null
            ? null
            : () => setState(() => _renaming = true),
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
    }
    return SizedBox(
      height: CursorMetrics.titleBarHeight,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.titleBarInset ?? CursorMetrics.trafficLightsWidth + 12,
          right: 8,
        ),
        child: Row(
          children: [
            if (widget.leading case final leading?) ...[
              leading,
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: title),
            ),
            if (widget.trailing case final trailing?) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Transparent Flutter-owned title bar under the native traffic lights.
          _buildTitleBar(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ChatHistoryView(
                  session: _session,
                  maxContentWidth: _maxContentWidth,
                ),
                ListenableBuilder(
                  listenable: _session,
                  builder: (context, _) => _session.itemCount == 0
                      ? const _EmptyHint()
                      : const SizedBox.shrink(),
                ),
              ],
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

/// Shown in place of the history while an agent has no messages yet.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 22,
              color: CursorColors.textFaint,
            ),
            SizedBox(height: 10),
            Text(
              'Plan, build, anything',
              style: TextStyle(color: CursorColors.textMuted, fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              '@ to add context · / for commands',
              style: TextStyle(color: CursorColors.textFaint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
