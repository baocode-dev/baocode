import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat/chat_screen.dart';
import 'sidebar/sidebar.dart';
import 'theme/cursor_theme.dart';
import 'workspace/open_in_editor_button.dart';
import 'workspace/workspace.dart';

/// The window: the agents sidebar on the left, the selected agent's chat
/// on the right.
///
/// The sidebar can be dragged wider or narrower and hidden (⌘B or its
/// button). In a narrow window it is hidden by default and opens over the
/// chat as a drawer instead of pushing it aside.
class Workbench extends StatefulWidget {
  const Workbench({super.key, required this.workspace});

  final Workspace workspace;

  /// Below this width the sidebar becomes a drawer.
  static const narrowWidth = 900.0;
  static const minSidebarWidth = 200.0;
  static const maxSidebarWidth = 420.0;

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  static const _duration = Duration(milliseconds: 200);

  double _width = 260;
  bool _dragging = false;

  /// Shown beside the chat (wide window).
  bool _docked = true;

  /// Shown over the chat (narrow window). A closed drawer is not built,
  /// once it has slid out.
  bool _drawerOpen = false;
  bool _drawerClosing = false;
  bool _narrow = false;

  Workspace get _workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  /// ⌘B (Ctrl+B elsewhere) from anywhere, including the composer, which
  /// swallows other shortcuts: a keyboard handler sees every key first.
  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyB) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final mac =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command = mac ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (!command || keyboard.isShiftPressed || keyboard.isAltPressed) {
      return false;
    }
    _toggle();
    return true;
  }

  void _toggle() {
    setState(() {
      if (_narrow) {
        _drawerClosing = _drawerOpen;
        _drawerOpen = !_drawerOpen;
      } else {
        _docked = !_docked;
      }
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() {
      _drawerOpen = false;
      _drawerClosing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < Workbench.narrowWidth;
        if (narrow != _narrow) {
          _narrow = narrow;
          // Crossing the breakpoint never leaves a drawer over the chat.
          _drawerOpen = false;
          _drawerClosing = false;
        }
        return ColoredBox(
          color: CursorColors.background,
          child: ListenableBuilder(
            listenable: _workspace,
            builder: (context, _) =>
                narrow ? _buildNarrow(constraints) : _buildWide(),
          ),
        );
      },
    );
  }

  Widget _buildWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: _dragging ? Duration.zero : _duration,
          curve: Curves.easeOutCubic,
          width: _docked ? _width : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: _width,
              maxWidth: _width,
              child: _buildSidebar(),
            ),
          ),
        ),
        if (_docked) _buildResizeHandle(),
        Expanded(child: _buildChat(showToggle: !_docked)),
      ],
    );
  }

  Widget _buildNarrow(BoxConstraints constraints) {
    final width = _width.clamp(0.0, constraints.maxWidth * 0.85);
    return Stack(
      children: [
        Positioned.fill(child: _buildChat(showToggle: true)),
        // Scrim: a click outside closes the drawer.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_drawerOpen,
            child: GestureDetector(
              onTap: _closeDrawer,
              child: AnimatedOpacity(
                opacity: _drawerOpen ? 1 : 0,
                duration: _duration,
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: _duration,
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          left: _drawerOpen ? 0 : -width - 24,
          width: width,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: CursorColors.border)),
              boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 24)],
            ),
            child: _drawerOpen || _drawerClosing
                ? _buildSidebar(onOpened: _closeDrawer)
                : null,
          ),
          onEnd: () {
            if (_drawerClosing) setState(() => _drawerClosing = false);
          },
        ),
      ],
    );
  }

  Widget _buildSidebar({VoidCallback? onOpened}) {
    return Sidebar(
      workspace: _workspace,
      onCollapse: _toggle,
      onOpened: onOpened,
    );
  }

  /// The border between sidebar and chat, draggable to resize.
  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => setState(() {
          _width = (_width + details.delta.dx).clamp(
            Workbench.minSidebarWidth,
            Workbench.maxSidebarWidth,
          );
        }),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: Container(
          width: 5,
          alignment: Alignment.centerLeft,
          child: Container(
            width: 1,
            color: _dragging ? CursorColors.accent : CursorColors.border,
          ),
        ),
      ),
    );
  }

  Widget _buildChat({required bool showToggle}) {
    final thread = _workspace.selected;
    return ChatScreen(
      key: ObjectKey(thread),
      session: thread.session,
      title: thread.title,
      autofocus: thread.session.itemCount == 0,
      onRename: (title) => _workspace.rename(thread, title),
      // Beside the sidebar, the traffic lights are over it, not here.
      titleBarInset: showToggle ? CursorMetrics.trafficLightsWidth + 8 : 12,
      leading: showToggle
          ? SidebarIconButton(
              icon: Icons.view_sidebar_outlined,
              flip: true,
              tooltip: 'Show sidebar',
              onTap: _toggle,
            )
          : null,
      trailing: OpenInEditorButton(
        workspace: _workspace,
        project: thread.project,
      ),
    );
  }
}
