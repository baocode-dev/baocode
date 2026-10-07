import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../kernel/kernel_types.dart';
import '../keybindings/chat_keybindings.dart';
import '../l10n/l10n.dart';
import '../remote/remote_status.dart' show ClaudeInstallBanner, SshHostBanner;
import '../theme/app_theme.dart';
import '../workspace/title_bar_double_click.dart';
import 'agent_view.dart';
import 'chat_feed.dart';
import 'chat_history_view.dart';
import 'chat_keys.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'composer/composer.dart';
import 'composer/composer_embeds.dart';
import 'composer/composer_mock_data.dart';
import 'panels/activity_strip.dart';
import 'panels/health_banner.dart';
import 'panels/interaction_panel.dart';
import 'panels/context_usage_panel.dart';
import 'panels/goal_panel.dart';
import 'panels/todo_panel.dart';
import 'widgets/agent_step.dart';
import 'widgets/code_citation.dart';
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
    this.embedded = false,
    this.windowTitleBar = true,
    this.titleBar = true,
    this.focused = true,
    this.onOpenChange,
    this.onOpenCode,
    this.colorizeCode,
    this.colorizeCodeBlock,
    this.start,
    this.startHint,
  });

  final String title;
  final ChatSession? session;

  /// Before the title, e.g. a button to show the sidebar.
  final Widget? leading;

  /// At the right of the title bar, e.g. a button to open the project.
  final Widget? trailing;

  /// Left of the title bar's [leading]: by default clear of the native
  /// traffic lights, as when this is the whole window. The title and
  /// [trailing] keep to the conversation's column, clear of both.
  final double? titleBarInset;

  /// Given, a double click on the title edits it.
  final ValueChanged<String>? onRename;

  /// Focuses the composer once shown, e.g. for a new agent.
  final bool autofocus;

  /// When true, omit the window title row so this screen can live in a pane.
  final bool embedded;

  /// Whether its title bar is in the window's own (at the top, under the
  /// macOS traffic lights' row): a double click on it does what one on the
  /// system's does. Not so for a pane below another.
  final bool windowTitleBar;

  /// Whether it shows its title row: not where the window's header shows
  /// the title (Windows' narrow window); renaming shows it all the same.
  final bool titleBar;

  /// Whether it is the conversation focused, of several side by side: the
  /// others' titles are dimmer.
  final bool focused;

  /// Opens a changed file's changes: against [original], its text before
  /// the agent changed it, or the file alone where that is not known.
  final void Function(FileChange change, Future<String> Function()? original)?
  onOpenChange;

  /// Opens a file the agent cited (see [CodeCitationCard]) with lines
  /// [start] to [end] (from 1) selected.
  final void Function(String path, int start, int end)? onOpenCode;

  /// Colors the code the agent cites.
  final CodeColorizer? colorizeCode;

  /// Colors code blocks by the language their fences name.
  final CodeBlockColorizer? colorizeCodeBlock;

  /// Over the composer while nothing was sent, e.g. where the agent is to
  /// work: given, the composer waits in the middle of the screen until then.
  final Widget? start;

  /// In place of the hint over the composer while nothing was sent (with
  /// [start]): the setup checklist, say, which builds [hint] when it has
  /// nothing to show.
  final Widget Function(BuildContext context, Widget hint)? startHint;

  @override
  State<ChatScreen> createState() => _ChatScreenState();

  /// Shows or hides the context usage panel of the chat [key] is on, as the
  /// window's View menu asks (see window_header/), wherever the focus is.
  static void toggleContextPanel(GlobalKey key) =>
      (key.currentState as _ChatScreenState?)?._toggleContextPanel();

  /// Focuses the input of the chat [key] is on (e.g. an agent just opened
  /// by its keybinding).
  static void focusInput(GlobalKey key) =>
      (key.currentState as _ChatScreenState?)?._focusInput();
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, ChatKeyTarget {
  static const _maxContentWidth = 720.0;

  late final ChatSession _session = widget.session ?? ChatSession();
  final GlobalKey<ChatComposerState> _composerKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();
  bool _contextPanelOpen = false;
  bool _renaming = false;

  /// Nothing was sent yet: the composer is in the middle, under [start].
  bool get _starting => widget.start != null && _session.itemCount == 0;
  late bool _wasStarting = _starting;

  /// Lays the screen out anew as the first message moves the composer down
  /// (the rest of the session's changes are the builders' below).
  void _checkStarting() {
    if (_starting != _wasStarting) setState(() => _wasStarting = _starting);
  }

  /// Around the chat: has the focus while anything in it does, and sees
  /// the keys it lets through (see [ChatKeys.dispatch]).
  final FocusNode _keyScope = FocusNode(
    debugLabel: 'Chat',
    canRequestFocus: false,
    skipTraversal: true,
  );

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

  void _setGoal(String condition) => _session.setGoal(condition);

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
    _session.addListener(_checkStarting);
    _restoreAgents();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composerKey.currentState?.focus();
      });
    }
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _wasStarting = _starting;
  }

  @override
  void dispose() {
    _session.removeListener(_checkStarting);
    _keyScope.dispose();
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

  // --- Keys ------------------------------------------------------------------

  /// The input, back from the subagents shown (they have none).
  void _focusInput() {
    if (_agentShown != null) {
      _back(0);
    } else {
      _composerKey.currentState?.focus();
    }
  }

  /// The conversation shown, for its keys to scroll it.
  void _focusList() =>
      ChatHistoryView.focus(_agentShown?.historyKey ?? _historyKey);

  bool get _renames => widget.onRename != null && !widget.embedded;

  @override
  Object? chatContextKey(String key) => switch (key) {
    ChatContextKeys.inChat => _keyScope.hasFocus,
    ChatContextKeys.requestInProgress => _session.isStreaming,
    ChatContextKeys.hasToolConfirmation =>
      _session.pendingInteraction is ApprovalRequest,
    ChatContextKeys.subagentVisible => _agentShown != null,
    _ => null,
  };

  @override
  Map<String, VoidCallback> get chatCommands => {
    ChatCommandIds.focusInput: _focusInput,
    ChatCommandIds.focusList: _focusList,
    if (_session.isStreaming) ChatCommandIds.cancel: _session.stop,
    if (_session.pendingInteraction is ApprovalRequest) ...{
      ChatCommandIds.acceptTool: () =>
          _answer(const ApprovalAnswer(ApprovalDecision.allowOnce)),
      ChatCommandIds.skipTool: () =>
          _answer(const ApprovalAnswer(ApprovalDecision.deny)),
    },
    ChatCommandIds.toggleContextPanel: _toggleContextPanel,
    if (_renames)
      ChatCommandIds.renameAgent: () => setState(() => _renaming = true),
    if (_agentShown != null) ChatCommandIds.closeSubagent: _back,
  };

  Widget _buildTitleBar() {
    final style = TextStyle(
      color: widget.focused ? AppColors.textMuted : AppColors.textFaint,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
    );
    final onRename = widget.onRename;
    final inset = widget.titleBarInset ?? AppMetrics.trafficLightsWidth + 12;
    final Widget title;
    if (_renaming && onRename != null) {
      title = SizedBox(
        width: 320,
        child: InlineRenameField(
          initial: widget.title,
          style: style.copyWith(color: AppColors.textPrimary),
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
    final bar = SizedBox(
      height: AppMetrics.titleBarHeight,
      child: CustomMultiChildLayout(
        delegate: _TitleBarLayout(inset: inset),
        children: [
          if (widget.leading case final leading?)
            LayoutId(id: _TitleBarSlot.leading, child: leading),
          LayoutId(
            id: _TitleBarSlot.title,
            child: Row(
              children: [
                Expanded(
                  // The title, where the conversation begins: at its start,
                  // as the row macOS draws has it (Windows draws none of
                  // it: see window_header/).
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                if (widget.trailing case final trailing?) ...[
                  const SizedBox(width: 8),
                  TitleBarControls(child: trailing),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    // Beside the title (a double click renames it) and the buttons, a
    // double click does what one on the system's title bar does.
    return widget.windowTitleBar ? TitleBarDoubleClick(child: bar) : bar;
  }

  Widget? _buildActivityStrip() {
    final tasks = _session.tasks ?? const [];
    final changes = _session.fileChanges;
    if (!ActivityStrip.hasContent(tasks, changes)) return null;
    final open = widget.onOpenChange;
    return ActivityStrip(
      tasks: tasks,
      changes: changes,
      root: _session.root ?? '.',
      onKeep: _session.keepAllChanges,
      onUndo: _session.undoAllChanges,
      onKeepFiles: _session.keepChanges,
      onUndoFiles: _session.undoChanges,
      onOpenFile: open == null
          ? null
          : (change) => open(change, _session.originalOf(change)),
      onStopTask: _session.stopTask,
      onOpenTask: (task) {
        if (_session.agentOf(task.toolUseId) case final agent?) {
          _openAgent(agent);
        }
      },
      // A subagent's last step, as its card has it.
      detailOf: (task) => switch (_session.agentOf(task.toolUseId)) {
        final agent? => AgentStep.latest(agent, l10n: context.l10n),
        null => null,
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
      builder: (context, child) => CodeCitationScope(
        root: _session.root,
        onOpen: widget.onOpenCode,
        colorize: widget.colorizeCode,
        colorizeBlock: widget.colorizeCodeBlock,
        child: ComposerVocabulary(
          commands: _commandSuggestions(),
          child: child!,
        ),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    // The keys the focus in it lets through: the chat's keybindings.
    return Focus(
      focusNode: _keyScope,
      // Never focused itself: nothing for assistive technologies.
      includeSemantics: false,
      onKeyEvent: (node, event) =>
          ChatKeys.dispatch(event) ?? KeyEventResult.ignored,
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      body: Column(
        children: [
          // The session's title, in the row the window's header leaves it
          // (macOS draws a title bar of its own over it; see AppMetrics).
          if (!widget.embedded && (widget.titleBar || _renaming))
            _buildTitleBar(),
          // Esc goes back from a subagent: a keybinding of the chat's
          // (closeSubagent).
          Expanded(
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
                        key: _historyKey,
                        feed: _session,
                        maxContentWidth: _maxContentWidth,
                        onOpenAgent: _openAgent,
                        onSetGoal: _setGoal,
                      ),
                      ListenableBuilder(
                        listenable: _session,
                        builder: (context, _) => switch (widget.startHint) {
                          _ when _session.itemCount != 0 =>
                            const SizedBox.shrink(),
                          final build? when _starting => Align(
                            alignment: Alignment.bottomCenter,
                            child: SingleChildScrollView(
                              child: _ConversationColumn(
                                maxWidth: _maxContentWidth,
                                child: build(
                                  context,
                                  const IgnorePointer(
                                    child: Padding(
                                      padding: EdgeInsets.only(bottom: 16),
                                      child: _EmptyHintText(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Just over the composer, where it waits in the
                          // middle.
                          _ => _EmptyHint(above: _starting),
                        },
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
          ListenableBuilder(
            listenable: _session,
            // Level with the history's text, laid out (not built) for the
            // width: a pane being resized does not build the composer anew.
            builder: (context, _) => _ConversationColumn(
              maxWidth: _maxContentWidth,
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
                  // A remote project's host out of reach: said once, by the
                  // banner above when the agent failed on it.
                  if (!HealthBanner.shows(_session.health))
                    SshHostBanner(location: _session.kernelContext.cwd),
                  // Claude Code being put on a remote project's host.
                  ClaudeInstallBanner(location: _session.kernelContext.cwd),
                  _PanelSlot(
                    child: switch (_session.pendingInteraction) {
                      final request? => InteractionPanel(
                        key: ObjectKey(request),
                        request: request,
                        onAnswer: _answer,
                        kernel: _session.kernel.id,
                      ),
                      null => null,
                    },
                  ),
                  if (widget.start case final start? when _starting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: start,
                    ),
                  // A subagent's conversation takes no messages.
                  _BottomSwitcher(
                    child: _agentShown == null
                        ? _buildDock()
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                ],
              ),
            ),
          ),
          // As much room under it as over it.
          if (_wasStarting) const Spacer(),
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
                open.feed.agent?.description ?? context.l10n.chatSubagent,
            ],
            onBack: _back,
            backFocusNode: layer.backFocus,
            maxContentWidth: _maxContentWidth,
          ),
        ),
        Expanded(
          child: ChatHistoryView(
            key: layer.historyKey,
            feed: layer.feed,
            maxContentWidth: _maxContentWidth,
            onOpenAgent: _openAgent,
            onSetGoal: _setGoal,
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
        // First: what all the rest works toward.
        _PanelSlot(
          child: switch (_session.goal) {
            final goal? => GoalPanel(
              goal: goal,
              activity: switch (_session) {
                ChatSession(pendingInteraction: _?) => GoalActivity.needsYou,
                ChatSession(isStreaming: true) => GoalActivity.working,
                _ => GoalActivity.waiting,
              },
              onSet: _session.canSend ? _setGoal : null,
              onClear: _session.canSend ? _session.clearGoal : null,
              onDismiss: _session.dismissGoal,
            ),
            null => null,
          },
        ),
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

enum _TitleBarSlot { leading, title }

/// The width of the conversation's column (the history's text, the
/// composer) in a screen [width] wide: [chatGutter] in from either side, and
/// no wider than [maxWidth], in the middle.
double _columnWidth(double width, double maxWidth) =>
    math.max(0, math.min(width - 2 * chatGutter(width), maxWidth));

/// The title bar's [_TitleBarSlot.leading] at [inset], clear of the traffic
/// lights; the title and the buttons after it across the conversation's
/// column, clear of the leading.
class _TitleBarLayout extends MultiChildLayoutDelegate {
  _TitleBarLayout({required this.inset});

  final double inset;

  /// Between the leading and the title.
  static const _gap = 6.0;

  /// The least from the right side, where the column reaches it.
  static const _endInset = 8.0;

  @override
  void performLayout(Size size) {
    var start = inset;
    if (hasChild(_TitleBarSlot.leading)) {
      final leading = layoutChild(
        _TitleBarSlot.leading,
        BoxConstraints.loose(size),
      );
      positionChild(
        _TitleBarSlot.leading,
        Offset(inset, (size.height - leading.height) / 2),
      );
      start += leading.width + _gap;
    }
    final column =
        (size.width -
            _columnWidth(size.width, _ChatScreenState._maxContentWidth)) /
        2;
    final left = math.max(start, column);
    final width = math.max(
      0.0,
      size.width - left - math.max(_endInset, column),
    );
    layoutChild(
      _TitleBarSlot.title,
      BoxConstraints.tightFor(width: width, height: size.height),
    );
    positionChild(_TitleBarSlot.title, Offset(left, 0));
  }

  @override
  bool shouldRelayout(_TitleBarLayout oldDelegate) =>
      oldDelegate.inset != inset;
}

/// [child] 16 in from either side and no wider than [maxWidth], in the
/// middle, with 12 under it, at any width. Worked out as it is laid out, so a
/// new width only lays [child] out again.
class _ConversationColumn extends SingleChildRenderObjectWidget {
  const _ConversationColumn({required this.maxWidth, required super.child});

  final double maxWidth;

  @override
  _RenderConversationColumn createRenderObject(BuildContext context) =>
      _RenderConversationColumn(maxWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderConversationColumn renderObject,
  ) {
    renderObject.maxWidth = maxWidth;
  }
}

class _RenderConversationColumn extends RenderShiftedBox {
  _RenderConversationColumn(this._maxWidth) : super(null);

  double get maxWidth => _maxWidth;
  double _maxWidth;
  set maxWidth(double value) {
    if (value == _maxWidth) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  static const _gutter = 16.0;
  static const _bottom = 12.0;

  double _width(double width) =>
      math.max(0, math.min(width - 2 * _gutter, _maxWidth));

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    return BoxConstraints.tightFor(width: _width(constraints.maxWidth))
        .copyWith(maxHeight: math.max(0.0, constraints.maxHeight - _bottom));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final height =
        child?.getDryLayout(_childConstraints(constraints)).height ?? 0;
    return constraints.constrain(Size(constraints.maxWidth, height + _bottom));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(_width(width)) ?? 0) + _bottom;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(_width(width)) ?? 0) + _bottom;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final child = this.child;
    var height = 0.0;
    if (child != null) {
      final childConstraints = _childConstraints(constraints);
      child.layout(childConstraints, parentUsesSize: true);
      (child.parentData! as BoxParentData).offset = Offset(
        (width - childConstraints.maxWidth) / 2,
        0,
      );
      height = child.size.height;
    }
    size = constraints.constrain(Size(width, height + _bottom));
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
  final GlobalKey historyKey = GlobalKey();

  /// Going back: sliding out, no longer the one shown.
  bool leaving = false;

  void dispose() {
    animation.dispose();
    controller.dispose();
    backFocus.dispose();
    feed.dispose();
  }
}

/// The composer and its panels, or nothing in their place (a subagent's
/// conversation): the one shown fades in. The height changes at once, as the panels'
/// do (see [_PanelSlot]); one at a time, the composer having a global key.
class _BottomSwitcher extends StatefulWidget {
  const _BottomSwitcher({required this.child});

  final Widget child;

  @override
  State<_BottomSwitcher> createState() => _BottomSwitcherState();
}

class _BottomSwitcherState extends State<_BottomSwitcher> {
  /// Whether it has shown another child since the first: the one it opens
  /// with is simply there, with the conversation.
  bool _switched = false;

  @override
  void didUpdateWidget(_BottomSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child.key != oldWidget.child.key) _switched = true;
  }

  @override
  Widget build(BuildContext context) =>
      _FadeIn(key: widget.child.key, animate: _switched, child: widget.child);
}

/// Fades and rises into place once, when first built with [animate].
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
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
  const _EmptyHint({this.above = false});

  /// At the bottom, over the composer, rather than in the middle.
  final bool above;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: above ? Alignment.bottomCenter : Alignment.center,
        child: Padding(
          padding: EdgeInsets.only(bottom: above ? 28 : 0),
          child: const _EmptyHintText(),
        ),
      ),
    );
  }
}

/// [_EmptyHint]'s words, where they are put.
class _EmptyHintText extends StatelessWidget {
  const _EmptyHintText();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_outlined, size: 22, color: AppColors.textFaint),
        SizedBox(height: 10),
        Text(
          context.l10n.chatEmptyTitle,
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        SizedBox(height: 4),
        Text(
          context.l10n.chatEmptyHint,
          style: TextStyle(color: AppColors.textFaint, fontSize: 12),
        ),
      ],
    );
  }
}
