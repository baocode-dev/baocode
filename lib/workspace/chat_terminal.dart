import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_keys.dart';
import '../ide/file_service.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_modern_ui.dart';
import '../ide/ide_rows.dart';
import '../ide/terminal/links/terminal_links.dart';
import '../ide/terminal/terminal_hosts.dart';
import '../ide/terminal/terminal_instance.dart';
import '../ide/terminal/terminal_profiles.dart';
import '../ide/terminal/terminal_service.dart';
import '../ide/terminal/terminal_tasks.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../sidebar/sidebar.dart' show SidebarIconButton;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'terminal_deck.dart';

/// Toggle Terminal (⌃`): the chat window's panel, as the IDE's.
const toggleTerminalCommand = 'workbench.action.terminal.toggleTerminal';

/// Toggle Panel Visibility (no key by default): in the chat window, its
/// panel being the terminal's, the same as [toggleTerminalCommand].
const togglePanelCommand = 'workbench.action.togglePanel';

/// Create New Terminal (⌃⇧`).
const newTerminalCommand = 'workbench.action.terminal.new';

/// The chat window's terminals, in a panel under each conversation as the
/// IDE's is under its editor. Each project has its own, started in its
/// folder; each shows under the pane of that project (see
/// [ChatTerminalArea]), and the window's commands act on [root]'s, the
/// focused agent's project. They run on while their panel is hidden, or
/// shows another project's.
class ChatTerminals extends ChangeNotifier {
  ChatTerminals(
    this.backend, {
    required this.rootOf,
    this.backendFor,
    this.pathOf,
  });

  final TerminalBackend backend;

  /// What the terminals of a project run on, if not [backend] (a remote
  /// project's run on its host).
  final TerminalBackend Function(String root)? backendFor;

  /// The folder a project's terminals start in, if not [root] itself (a
  /// remote project's path on its host).
  final String Function(String root)? pathOf;

  /// The project the window's commands act on: the focused agent's; none
  /// without one.
  final String? Function() rootOf;

  /// Each project's terminals: the panel's under its conversation, and its
  /// side panel's terminal page's.
  final Map<String, TerminalService> _services = {};

  /// Which of the two places shows each terminal (see [TerminalDeck]).
  final hosts = TerminalHosts();

  /// The background command each project's panel shows, by id, in place
  /// of its active terminal.
  final Map<String, String> _shownTasks = {};

  String? get root => rootOf();

  /// The terminals of [root]; none until its panel first shows there.
  TerminalService? serviceOf(String? root) => switch (root) {
    final root? => _services[root],
    null => null,
  };

  /// The terminals of [root] (the focused project's); none until the panel
  /// first shows there.
  TerminalService? get current => serviceOf(root);

  /// The projects whose panel is open.
  final Set<String> _shown = {};

  /// Whether [root]'s panel shows: opened, and it has terminals. Open, it
  /// shows again for a project that has (none are made for one that has
  /// not, the agents gone through).
  bool shownFor(String root) =>
      _shown.contains(root) && (serviceOf(root)?.instances.isNotEmpty ?? false);

  /// Whether [root]'s panel, the focused project's, shows.
  bool get shown => switch (root) {
    final root? => shownFor(root),
    null => false,
  };

  /// Each project's panel as dragged; null: a third of the room, as the
  /// IDE's panel opens.
  final Map<String, double> _heights = {};

  /// How high [root]'s panel was dragged to; null while it is the room's
  /// third.
  double? heightOf(String root) => _heights[root];

  /// [root]'s panel dragged to [height]; null: back to the room's third.
  void setHeight(String root, double? height) {
    if (height == null) {
      _heights.remove(root);
    } else {
      _heights[root] = height;
    }
  }

  /// Once the panel shows a project's last terminal closed, it hides (as
  /// VS Code's `terminal.integrated.hideOnLastClosed`); this is told, for
  /// the keyboard to go back to the chat if the terminal had it.
  VoidCallback? onLastClosed;

  TerminalService _serviceOf(String root) => _services.putIfAbsent(root, () {
    late final TerminalService service;
    service = TerminalService(
      root: pathOf?.call(root) ?? root,
      backend: backendFor?.call(root) ?? backend,
    )..addListener(() => _changed(root, service));
    return service;
  });

  /// The terminals of the project in [root], for its side panel's page as
  /// for its panel (none made).
  TerminalService terminalsOf(String root) => _serviceOf(root);

  /// The background command [root]'s panel shows; none: its active
  /// terminal.
  String? taskShownOf(String root) => _shownTasks[root];

  /// [root]'s panel on the background command [id]; null: back on its
  /// active terminal.
  void showTask(String root, String? id) {
    if (_shownTasks[root] == id) return;
    if (id == null) {
      _shownTasks.remove(root);
    } else {
      _shownTasks[root] = id;
    }
    notifyListeners();
  }

  void _changed(String root, TerminalService service) {
    if (_shown.contains(root) && service.instances.isEmpty) {
      _shown.remove(root);
      notifyListeners();
      // Only the focused project's, whose terminal may have had the
      // keyboard: another's closing leaves the chat where it is.
      if (root == this.root) onLastClosed?.call();
      return;
    }
    notifyListeners();
  }

  /// [root]'s panel (the focused project's), with a terminal made if there
  /// is none, the active one focused.
  void show({String? root}) {
    final target = root ?? this.root;
    if (target == null) return;
    final service = _serviceOf(target);
    _shown.add(target);
    _shownTasks.remove(target);
    hosts.claim(service.ensureTerminal(), service);
    notifyListeners();
    _focusSoon(service);
  }

  /// Hides [root]'s panel (the focused project's); true if a terminal of it
  /// had the keyboard.
  bool hide({String? root}) {
    final target = root ?? this.root;
    if (target == null || !_shown.contains(target)) return false;
    final hadFocus = serviceOf(target)?.active?.focusNode.hasFocus ?? false;
    _shown.remove(target);
    notifyListeners();
    return hadFocus;
  }

  /// A new terminal for [root] (the focused project) on [profile]'s shell
  /// (else the default profile's), shown and focused.
  TerminalInstance? create({TerminalProfile? profile, String? root}) {
    final target = root ?? this.root;
    if (target == null) return null;
    final service = _serviceOf(target);
    final terminal = service.create(profile: profile);
    _shown.add(target);
    _shownTasks.remove(target);
    hosts.claim(terminal, service);
    notifyListeners();
    _focusSoon(service);
    return terminal;
  }

  /// Focus Next (Previous) Terminal Group, among [root]'s.
  void cycle({required bool next}) {
    final service = current;
    if (service == null) return;
    next ? service.focusNext() : service.focusPrevious();
    if (service.active case final active?) hosts.claim(active, service);
    _focusSoon(service);
  }

  /// Kill Terminal: the active one of [root]'s.
  void kill() => current?.kill();

  /// Once the panel is built (and lets its terminals have the keyboard).
  static void _focusSoon(TerminalService service) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      service.active?.focus();
    });
  }

  /// Whether one of the terminals has the keyboard.
  bool get focused => shown && (current?.active?.focusNode.hasFocus ?? false);

  /// Whether a shell is alive, or ([childProcesses]) one runs a command
  /// (`terminal.integrated.confirmOnExit`), in any project's terminals.
  bool running({required bool childProcesses}) {
    for (final service in _services.values) {
      for (final terminal in service.instances) {
        if (terminal.exited) continue;
        if (!childProcesses) return true;
        final command =
            terminal.shellIntegration?.commandDetection?.executingCommand;
        if (command != null && command.isNotEmpty) return true;
      }
    }
    return false;
  }

  /// Hangs up every terminal.
  @override
  void dispose() {
    for (final service in _services.values) {
      service.dispose();
    }
    _services.clear();
    hosts.dispose();
    super.dispose();
  }
}

/// [child] (a conversation) and, under it while its project's panel shows,
/// the terminal panel: its top edge drags it higher or lower (snapped shut
/// below half its least height), a double click on it gives it back a
/// third of the room. The conversation keeps [IdeRows.minChat].
///
/// Each pane has its own, in its width, so a project's terminals show
/// under its conversation and not across the window.
class ChatTerminalArea extends StatefulWidget {
  const ChatTerminalArea({
    super.key,
    required this.terminals,
    required this.root,
    required this.child,
    this.tasks,
    this.files,
    this.onOpenLink,
  });

  final ChatTerminals terminals;

  /// The project whose terminals the panel shows.
  final String root;

  final Widget child;

  /// The conversation's background commands, in a tab of the panel's, and
  /// what reads their output.
  final TerminalTasks? tasks;
  final IdeFileService? files;

  /// Opens a link ⌘-clicked (Ctrl-clicked off macOS) in a terminal.
  final ValueChanged<TerminalLink>? onOpenLink;

  /// The strip at the panel's top edge that takes the drag; its line is
  /// at the bottom of it, against the panel.
  static const sashHeight = 5.0;

  @override
  State<ChatTerminalArea> createState() => _ChatTerminalAreaState();
}

class _ChatTerminalAreaState extends State<ChatTerminalArea> {
  /// The rows and the pointer's height in the window when a drag began:
  /// the sash moves under the pointer, so the drag is measured from there.
  ({IdeRows rows, double room, double y})? _dragStart;
  bool _dragging = false;

  ChatTerminals get _terminals => widget.terminals;
  String get _root => widget.root;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _terminals,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final service = _terminals.serviceOf(_root);
        final shown = _terminals.shownFor(_root);
        final room = constraints.maxHeight - ChatTerminalArea.sashHeight;
        final rows = IdeRows.fit(
          room,
          panel: shown
              ? _terminals.heightOf(_root) ?? IdeRows.defaultPanel(room)
              : null,
          minAbove: IdeRows.minChat,
        );
        // The conversations stay the first child, whether the panel shows
        // or not, so they are never built anew for it.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: widget.child),
            if (shown && service != null && rows.panel > 0) ...[
              _sash(rows, room),
              SizedBox(
                height: rows.panel,
                child: _ChatTerminalPanel(
                  // The shared panel can move to another pane of the same
                  // project without remounting its focused terminal.
                  key: GlobalObjectKey(service),
                  terminals: _terminals,
                  root: _root,
                  service: service,
                  tasks: widget.tasks,
                  files: widget.files,
                  onOpenLink: widget.onOpenLink,
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _sash(IdeRows rows, double room) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    child: GestureDetector(
      key: const ValueKey('chat-terminal-sash'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (details) => setState(() {
        _dragging = true;
        _dragStart = (rows: rows, room: room, y: details.globalPosition.dy);
      }),
      onVerticalDragUpdate: (details) {
        final start = _dragStart;
        if (start == null) return;
        final next = start.rows.drag(
          start.room,
          details.globalPosition.dy - start.y,
        );
        if (next.panel > 0) {
          _terminals.setHeight(_root, next.panel);
          setState(() {});
        } else {
          // Snapped shut: it opens again as high as it was.
          _terminals.setHeight(_root, start.rows.panel);
          _endDrag();
          _terminals.hide(root: _root);
        }
      },
      onVerticalDragEnd: (_) => _endDrag(),
      onVerticalDragCancel: _endDrag,
      onDoubleTap: () => setState(() => _terminals.setHeight(_root, null)),
      child: Container(
        height: ChatTerminalArea.sashHeight,
        // The panel's own top, nothing under it showing through; the line
        // where the conversation ends.
        color: themeColors.get('terminal.background') ?? AppColors.code,
        alignment: Alignment.topCenter,
        // At rest the line between the two; dragged, as thick as the IDE's
        // sashes, in their `sash.hoverBorder`.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: _dragging ? IdeModernUI.gap : 1,
          color: _dragging ? IdeModernUI.sashHover : AppColors.partBorder,
        ),
      ),
    ),
  );

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragStart = null;
    });
  }
}

/// The panel: the project's terminals as a [TerminalDeck], as the side
/// panel's terminal page shows them; Hide at the end of its tabs.
class _ChatTerminalPanel extends StatelessWidget {
  const _ChatTerminalPanel({
    super.key,
    required this.terminals,
    required this.root,
    required this.service,
    this.tasks,
    this.files,
    this.onOpenLink,
  });

  final ChatTerminals terminals;

  /// The project the panel is of: what New Terminal makes one for, and
  /// Hide hides.
  final String root;

  final TerminalService service;
  final TerminalTasks? tasks;
  final IdeFileService? files;
  final ValueChanged<TerminalLink>? onOpenLink;

  @override
  Widget build(BuildContext context) => TerminalDeck(
    key: const ValueKey('chat-terminal-panel'),
    // One panel a project, wherever it shows.
    place: service,
    hosts: terminals.hosts,
    terminals: service,
    // A background command chosen, else the active terminal (which the
    // window's terminal commands act on).
    shown: terminals.taskShownOf(root) ?? service.active,
    onShow: (id) {
      if (id case final TerminalInstance shell) {
        terminals.showTask(root, null);
        service.setActive(shell);
      } else if (id case final String task) {
        terminals.showTask(root, task);
      }
    },
    onNew: () => terminals.create(root: root),
    onNewWithProfile: (profile) =>
        terminals.create(profile: profile, root: root),
    tasks: tasks,
    files: files,
    skipShell: chatTerminalSkipShell,
    onOpenLink: onOpenLink,
    trailing: IdeActionButton(
      icon: Codicons.close,
      tooltip: KeybindingService.instance.titleWithKeybinding(
        context.l10n.chatTerminalHide,
        toggleTerminalCommand,
      ),
      onPressed: () => terminals.hide(root: root),
    ),
  );
}

/// The window's keys skip the shell of a terminal in it: those it has run
/// (see ChatKeys).
const chatTerminalSkipShell = <ShortcutActivator>[_HandledByWindow()];

/// A key the window's keyboard handler ran a command for (which sees every
/// key before the focus does): not the shell's.
class _HandledByWindow extends ShortcutActivator {
  const _HandledByWindow();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      ChatKeys.isHandled(event);

  @override
  Iterable<LogicalKeyboardKey>? get triggers => null;

  @override
  String debugDescribeKeys() => 'run by the window';
}

/// The title bar's button for the panel: the IDE's layout icon, which
/// shows whether it is open. Its hover is Toggle Terminal's title, the one
/// the keyboard page lists.
class ChatTerminalToggle extends StatelessWidget {
  const ChatTerminalToggle({
    super.key,
    required this.shown,
    required this.onTap,
    this.size = 24,
  });

  final bool shown;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => SidebarIconButton(
    icon: shown ? Codicons.layoutPanel : Codicons.layoutPanelOff,
    tooltip: context.l10n.cmdToggleTerminal,
    command: toggleTerminalCommand,
    size: size,
    onTap: onTap,
  );
}
