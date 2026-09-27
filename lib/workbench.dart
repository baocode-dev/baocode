import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat/chat_screen.dart';
import 'sidebar/sidebar.dart';
import 'theme/cursor_theme.dart';
import 'workspace/open_in_editor_button.dart';
import 'workspace/pin_window_button.dart';
import 'workspace/window_controls.dart';
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
  static const narrowWidth = 720.0;
  static const minSidebarWidth = 200.0;
  static const maxSidebarWidth = 420.0;

  /// The sidebar leaves at least this much of the window beside it.
  static const sidebarWindowMargin = 20.0;

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  static const _duration = Duration(milliseconds: 200);

  /// The border between sidebar and chat: a line at the left of a strip
  /// this wide, which takes the resize drag.
  static const _handleWidth = 5.0;

  /// The width set by dragging. Shown as [_shownWidth], which a narrow
  /// window may cap below it for now.
  double _width = 260;

  /// Of the window, from the last layout.
  double _windowWidth = double.infinity;

  /// At most 20 short of the window's width, so the border (and its drag
  /// strip) stays in it.
  double get _maxWidth => math.min(
    Workbench.maxSidebarWidth,
    _windowWidth - Workbench.sidebarWindowMargin,
  );

  double get _shownWidth =>
      _width.clamp(math.min(Workbench.minSidebarWidth, _maxWidth), _maxWidth);
  bool _dragging = false;

  /// Pointer and sidebar width when the resize drag began.
  ({double x, double width})? _dragOrigin;

  /// Shown beside the chat (wide window).
  bool _docked = true;

  /// Shown over the chat (narrow window). A closed drawer is not built,
  /// once it has slid out.
  bool _drawerOpen = false;
  bool _drawerClosing = false;
  bool _narrow = false;

  Workspace get _workspace => widget.workspace;

  /// The window is kept above other apps' windows.
  bool _pinned = false;

  void _setPinned(bool pinned) {
    setState(() => _pinned = pinned);
    WindowControls.setAlwaysOnTop(pinned);
  }

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
        _windowWidth = constraints.maxWidth;
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
            builder: (context, _) => narrow ? _buildNarrow() : _buildWide(),
          ),
        );
      },
    );
  }

  Widget _buildWide() {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: _dragging ? Duration.zero : _duration,
          curve: Curves.easeOutCubic,
          width: _docked ? _shownWidth : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: _shownWidth,
              maxWidth: _shownWidth,
              child: _buildSidebar(),
            ),
          ),
        ),
        if (_docked) _buildResizeHandle(),
        Expanded(child: _buildChat(showToggle: !_docked)),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [row, if (_dragging) _resizeCursorLayer],
    );
  }

  Widget _buildNarrow() {
    // The same sidebar and border as when docked, at the same width.
    const handleWidth = _WorkbenchState._handleWidth;
    return Stack(
      fit: StackFit.expand,
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
        // Only the slide animates; the width follows the drag or the window
        // at once (animating it too would leave the sidebar overflowing its
        // box while the window grows).
        TweenAnimationBuilder<double>(
          tween: Tween(end: _drawerOpen ? 1 : 0),
          duration: _duration,
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (_drawerClosing) setState(() => _drawerClosing = false);
          },
          builder: (context, shown, child) => Positioned(
            top: 0,
            bottom: 0,
            left: -(_shownWidth + handleWidth + 24) * (1 - shown),
            width: _shownWidth + handleWidth,
            child: child!,
          ),
          child: _drawerOpen || _drawerClosing
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _shownWidth,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(color: Color(0x80000000), blurRadius: 24),
                          ],
                        ),
                        child: _buildSidebar(onOpened: _closeDrawer),
                      ),
                    ),
                    _buildResizeHandle(),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        if (_dragging) _resizeCursorLayer,
      ],
    );
  }

  /// While resizing, the pointer may be far from the border: the resize
  /// cursor everywhere, and no hover effects under it.
  static const _resizeCursorLayer = MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
  );

  Widget _buildSidebar({VoidCallback? onOpened}) {
    return Sidebar(
      workspace: _workspace,
      onCollapse: _toggle,
      onOpened: onOpened,
    );
  }

  void _endDrag() {
    setState(() {
      _dragging = false;
      _dragOrigin = null;
    });
  }

  /// The border between sidebar and chat, draggable to resize.
  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        // Its clicks stay its own (not the drawer's scrim, under it).
        behavior: HitTestBehavior.opaque,
        // From the press, not from where the drag was recognized, so the
        // border stays under the pointer.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) => setState(() {
          _dragging = true;
          _dragOrigin = (x: details.globalPosition.dx, width: _shownWidth);
        }),
        // Where the pointer is relative to where it was pressed, not the
        // sum of the moves: past the min or max the border waits there, and
        // follows again only once the pointer is back at it.
        onHorizontalDragUpdate: (details) => setState(() {
          final origin = _dragOrigin!;
          _width = (origin.width + details.globalPosition.dx - origin.x).clamp(
            math.min(Workbench.minSidebarWidth, _maxWidth),
            _maxWidth,
          );
        }),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: Container(
          width: _handleWidth,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PinWindowButton(pinned: _pinned, onChanged: _setPinned),
          const SizedBox(width: 6),
          OpenInEditorButton(workspace: _workspace, project: thread.project),
        ],
      ),
    );
  }
}
