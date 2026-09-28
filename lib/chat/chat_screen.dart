import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kernel/kernel_types.dart';
import '../theme/cursor_theme.dart';
import 'agent_view.dart';
import 'chat_feed.dart';
import 'chat_history_view.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'composer/composer_embeds.dart';
import 'composer/composer_mock_data.dart';
import 'panels/activity_strip.dart';
import 'panels/health_banner.dart';
import 'panels/interaction_panel.dart';
import 'panels/context_usage_panel.dart';
import 'panels/todo_panel.dart';
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
    this.mentions = ComposerMockData.mentions,
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

  /// What `@` offers: the project's files and other context.
  final List<Suggestion> mentions;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  static const _maxContentWidth = 720.0;

  late final ChatSession _session = widget.session ?? ChatSession();
  final GlobalKey<ChatComposerState> _composerKey = GlobalKey();
  bool _contextPanelOpen = false;
  bool _renaming = false;

  /// The subagents opened, one in the other, innermost last: each shows
  /// over the conversation under it. One going back stays until it is out.
  final List<_AgentLayer> _layers = [];

  /// The subagent shown, if any (not one on its way out).
  _AgentLayer? get _agentShown =>
      _layers.lastOrNull?.leaving == false ? _layers.last : null;

  static const _layerDuration = Duration(milliseconds: 300);

  /// The subagents left open when this conversation last showed, as they
  /// were: no way in to play again.
  void _restoreAgents() {
    final path = _session.openAgents;
    for (var depth = 1; depth <= path.length; depth++) {
      final feed = SubagentFeed(_session, path.sublist(0, depth));
      // Gone since (its turn rewound): open no further in.
      if (feed.agent == null) {
        feed.dispose();
        _session.openAgents = path.sublist(0, depth - 1);
        return;
      }
      _layers.add(
        _AgentLayer(
          feed,
          AnimationController(vsync: this, duration: _layerDuration, value: 1),
        ),
      );
    }
    // Where Esc goes back from, as when it was opened.
    if (_layers.lastOrNull case final top?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) top.backFocus.requestFocus();
      });
    }
  }

  void _openAgent(AgentItem agent) {
    final id = agent.id;
    if (id == null) return;
    final layer = _AgentLayer(
      SubagentFeed(_session, [...?_agentShown?.feed.path, id]),
      AnimationController(vsync: this, duration: _layerDuration),
    );
    setState(() => _layers.add(layer));
    _session.openAgents = layer.feed.path;
    layer.controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) layer.backFocus.requestFocus();
    });
  }

  /// Goes back to [depth] subagents in (0: the conversation itself); one
  /// level up without it. The innermost slides out; those between go at once.
  void _back([int? depth]) {
    final shown = _layers.where((layer) => !layer.leaving).length;
    final keep = depth ?? shown - 1;
    if (keep < 0 || keep >= shown) return;
    final top = _layers.last;
    final between = _layers.sublist(keep, _layers.length - 1);
    setState(() {
      _layers.removeRange(keep, _layers.length - 1);
      top.leaving = true;
    });
    _session.openAgents = keep == 0 ? const [] : _layers[keep - 1].feed.path;
    for (final layer in between) {
      layer.dispose();
    }
    top.controller.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() => _layers.remove(top));
      top.dispose();
    });
    if (keep == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerKey.currentState?.focus();
      });
    } else {
      _layers[keep - 1].backFocus.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _session.attach();
    _restoreAgents();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerKey.currentState?.focus();
      });
    }
  }

  @override
  void dispose() {
    for (final layer in _layers) {
      layer.dispose();
    }
    _session.detach();
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  void _toggleContextPanel() {
    setState(() => _contextPanelOpen = !_contextPanelOpen);
    if (_contextPanelOpen) _session.refreshUsage();
  }

  void _answer(InteractionAnswer answer) {
    _session.answer(answer);
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

  Widget? _buildActivityStrip() {
    final tasks = _session.tasks ?? const [];
    final changes = _session.fileChanges;
    if (!ActivityStrip.hasContent(tasks, changes)) return null;
    return ActivityStrip(
      tasks: tasks,
      changes: changes,
      onDismissTask: _session.dismissTask,
      onKeep: _session.keepAllChanges,
      onUndo: _session.undoAllChanges,
      onStopTask: _session.stopTask,
      onOpenTask: (task) {
        if (_session.agentOf(task.toolUseId) case final agent?) {
          _openAgent(agent);
        }
      },
    );
  }

  /// The kernel's commands as suggestions, kept while its list is the same.
  List<Suggestion> _commandSuggestions() {
    final commands = _session.commands;
    if (!identical(commands, _commandSource)) {
      _commandSource = commands;
      _commands = [
        for (final command in commands)
          Suggestion(
            kind: SuggestionKind.command,
            label: command.name,
            detail: command.argumentHint.isEmpty
                ? command.description
                : '${command.argumentHint}  ${command.description}',
            icon: command.icon,
          ),
      ];
    }
    return _commands;
  }

  List<KernelCommand>? _commandSource;
  List<Suggestion> _commands = const [];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, child) => ComposerVocabulary(
        commands: _commandSuggestions(),
        mentions: widget.mentions,
        suggestFiles: _session.suggestFiles,
        child: child!,
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Scaffold(
      body: Column(
        children: [
          // Transparent Flutter-owned title bar under the native traffic lights.
          _buildTitleBar(),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                if (_agentShown != null)
                  const SingleActivator(LogicalKeyboardKey.escape): _back,
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ConversationLayer(
                    entrance: kAlwaysCompleteAnimation,
                    cover: _layers.firstOrNull?.animation,
                    interactive: _agentShown == null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ChatHistoryView(
                          feed: _session,
                          maxContentWidth: _maxContentWidth,
                          onOpenAgent: _openAgent,
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
                  for (final (i, layer) in _layers.indexed)
                    ConversationLayer(
                      key: ObjectKey(layer),
                      entrance: layer.animation,
                      cover: _layers.elementAtOrNull(i + 1)?.animation,
                      interactive: identical(layer, _agentShown),
                      child: _buildAgentPage(i, layer),
                    ),
                ],
              ),
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
                        child: HealthBanner.shows(_session.health)
                            ? HealthBanner(
                                health: _session.health,
                                kernelName: _session.kernel.label,
                                onRetry: _session.restart,
                              )
                            : null,
                      ),
                      _PanelSlot(
                        child: switch (_session.pendingInteraction) {
                          final request? => InteractionPanel(
                            key: ObjectKey(request),
                            request: request,
                            onAnswer: _answer,
                          ),
                          null => null,
                        },
                      ),
                      // A subagent's conversation takes no messages: how it
                      // is doing ends it instead (see _buildAgentPage).
                      _BottomSwitcher(
                        child: _agentShown == null
                            ? _buildDock()
                            : const SizedBox.shrink(key: ValueKey('none')),
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

  /// The subagent [layer], [index] in: the way here, and its conversation.
  Widget _buildAgentPage(int index, _AgentLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: _session,
          builder: (context, _) => SubagentHeader(
            trail: [
              for (final open in _layers.take(index + 1))
                open.feed.agent?.description ?? 'Subagent',
            ],
            onBack: _back,
            backFocusNode: layer.backFocus,
            maxContentWidth: _maxContentWidth,
          ),
        ),
        Expanded(
          child: ChatHistoryView(
            feed: layer.feed,
            maxContentWidth: _maxContentWidth,
            onOpenAgent: _openAgent,
            footer: ListenableBuilder(
              listenable: _session,
              builder: (context, _) => SubagentStatusBar(
                feed: layer.feed,
                onStop: _session.stopOf(layer.feed.path.last),
                onMoveToBackground: _session.moveToBackgroundOf(
                  layer.feed.path.last,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Under the session's own conversation: its panels and the composer.
  Widget _buildDock() {
    return Column(
      key: const ValueKey('dock'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelSlot(
          child: switch (_session.context) {
            final usage? when _contextPanelOpen => ContextUsagePanel(
              usage: usage,
              stats: _session.stats,
              onClose: _toggleContextPanel,
            ),
            _ => null,
          },
        ),
        _PanelSlot(
          child: TodoPanel.hasContent(_session.todos)
              ? TodoPanel(todos: _session.todos)
              : null,
        ),
        _PanelSlot(gap: 0, child: _buildActivityStrip()),
        ChatComposer(
          key: _composerKey,
          session: _session,
          draft: _session.draft,
          contextPanelOpen: _contextPanelOpen,
          onToggleContextPanel: _toggleContextPanel,
        ),
      ],
    );
  }
}

/// An open subagent: its conversation, and its way in and out.
class _AgentLayer {
  _AgentLayer(this.feed, this.controller)
    : animation = CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

  final SubagentFeed feed;
  final AnimationController controller;
  final CurvedAnimation animation;
  final FocusNode backFocus = FocusNode(debugLabel: 'Subagent back');

  /// Going back: sliding out, no longer the one shown.
  bool leaving = false;

  void dispose() {
    animation.dispose();
    controller.dispose();
    backFocus.dispose();
    feed.dispose();
  }
}

/// The composer and its panels, or a subagent's status in their place:
/// the one shown fades in. The height changes at once, as the panels'
/// do (see [_PanelSlot]); one at a time, the composer having a global key.
class _BottomSwitcher extends StatelessWidget {
  const _BottomSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _FadeIn(key: child.key, child: child);
}

/// Fades and rises into place once, when first built.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
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
