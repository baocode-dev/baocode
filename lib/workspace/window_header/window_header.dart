import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ide/ide_layout.dart';
import '../../ide/ide_modern_ui.dart';
import '../../sidebar/sidebar.dart';
import '../../theme/codicons.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../back_to_chat_button.dart';
import '../open_in_editor_button.dart';
import '../pin_window_button.dart';
import '../window_controls.dart';
import '../workspace.dart';
import 'about_dialog.dart';
import 'header_menu.dart';
import 'header_menu_bar.dart';
import 'window_buttons.dart';

/// The bar the Windows app draws itself, over everything: the menu bar, the
/// sidebar toggle, the session's tools and the window buttons (see
/// [WindowControls.drawsHeader]). Over the IDE it is the IDE's title bar, as
/// the IDE draws its own on macOS: the side bar's toggle after the menus,
/// and the panel's and the chat's, the pin and the way back to the chat on
/// the right.
///
/// It tells the window where its controls are; the window leaves those pixels
/// to Flutter, drags itself by the rest of the strip, and runs the three
/// window buttons (see [WindowControls.setHitTestAreas]).
class WindowHeader extends StatefulWidget {
  const WindowHeader({
    super.key,
    required this.workspace,
    required this.sidebarShown,
    required this.onToggleSidebar,
    required this.pinned,
    required this.onTogglePin,
    required this.onOpenFolder,
    required this.onToggleContextPanel,
    this.project,
    this.ideLayout,
  });

  final Workspace workspace;

  /// The project the session works in, for opening it in an editor; null
  /// before there is one.
  final Project? project;

  /// Whether the sidebar is shown (the toggle offers the other way).
  final bool sidebarShown;

  final VoidCallback onToggleSidebar;

  /// Over the IDE, which of its parts show, for its layout toggles.
  final IdeLayout? ideLayout;

  /// The window is kept above other apps' windows.
  final bool pinned;
  final ValueChanged<bool> onTogglePin;

  /// The File menu's Open Folder: asks for a folder and opens it.
  final Future<void> Function() onOpenFolder;

  /// The View menu's Context Panel: the current chat's.
  final VoidCallback onToggleContextPanel;

  @override
  State<WindowHeader> createState() => _WindowHeaderState();
}

class _WindowHeaderState extends State<WindowHeader> {
  /// The controls the window leaves to Flutter, read back as rectangles
  /// after each layout (see [_report]).
  final _toggle = GlobalKey(debugLabel: 'header sidebar');
  final _panel = GlobalKey(debugLabel: 'header panel');
  final _chat = GlobalKey(debugLabel: 'header chat');
  final _menus = GlobalKey(debugLabel: 'header menus');
  final _pin = GlobalKey(debugLabel: 'header pin');
  final _open = GlobalKey(debugLabel: 'header open in editor');
  final _back = GlobalKey(debugLabel: 'header back to chat');
  final _minimize = GlobalKey(debugLabel: 'window minimize');
  final _maximize = GlobalKey(debugLabel: 'window maximize');
  final _close = GlobalKey(debugLabel: 'window close');

  /// What the window was last told, so an unchanged header is not told
  /// again.
  List<Rect>? _reported;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  /// Checks where the controls are after every frame, for as long as the
  /// header is there: they move without it being built again (the editor
  /// button's label is its own to change). No frame is asked for, and the
  /// window hears only of a change (see [_report]).
  void _watch() {
    if (!mounted) return;
    _report();
    SchedulerBinding.instance.addPostFrameCallback((_) => _watch());
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.workspace.layout == WorkspaceLayout.ide
        ? widget.ideLayout
        : null;
    final ide = layout != null;
    // A Material of its own, as the sidebar has: the strip is outside the
    // chat's Scaffold, and this is what gives its text the app's own style.
    // Over the chat, the line under it is what tells it apart from what it
    // sits over — Flutter's own pixels are the whole of the window's top on
    // Windows (see WindowControls.drawsHeader), so the system draws none.
    // Over the IDE it is the IDE's title bar: its color, no line, and the
    // way back to the chat on the right, as on macOS.
    final colors = themeColors;
    return Material(
      color: ide ? IdeModernUI.shell : colors['titleBar.activeBackground'],
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: ide
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.get('titleBar.border') ?? CursorColors.border,
                  ),
                ),
        ),
        child: SizedBox(
          height: CursorMetrics.headerHeight,
          child: Row(
            children: [
              const SizedBox(width: 6),
              KeyedSubtree(
                key: _menus,
                child: HeaderMenuBar(items: _items),
              ),
              const SizedBox(width: 4),
              KeyedSubtree(
                key: _toggle,
                child: switch (layout) {
                  final layout? => IdeLayoutToggle.sidebar(layout),
                  // The IDE's layout icons: the icon shows whether it is
                  // open.
                  null => SidebarIconButton(
                    icon: widget.sidebarShown
                        ? Codicons.layoutSidebarLeft
                        : Codicons.layoutSidebarLeftOff,
                    tooltip: widget.sidebarShown
                        ? 'Hide sidebar'
                        : 'Show sidebar',
                    onTap: widget.onToggleSidebar,
                  ),
                },
              ),
              const Spacer(),
              if (layout != null) ...[
                KeyedSubtree(key: _panel, child: IdeLayoutToggle.panel(layout)),
                KeyedSubtree(key: _chat, child: IdeLayoutToggle.chat(layout)),
                const SizedBox(width: 2),
              ],
              KeyedSubtree(
                key: _pin,
                child: PinWindowButton(
                  pinned: widget.pinned,
                  onChanged: widget.onTogglePin,
                ),
              ),
              // The chat's; the IDE is the editor there.
              if (widget.project case final project? when !ide) ...[
                const SizedBox(width: 6),
                KeyedSubtree(
                  key: _open,
                  child: OpenInEditorButton(
                    workspace: widget.workspace,
                    project: project,
                  ),
                ),
              ],
              if (ide) ...[
                const SizedBox(width: 8),
                KeyedSubtree(
                  key: _back,
                  child: BackToChatButton(
                    onPressed: () =>
                        widget.workspace.layout = WorkspaceLayout.chat,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              WindowButtons(
                minimizeKey: _minimize,
                maximizeKey: _maximize,
                closeKey: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tells the window where the header's controls are: the rest of the strip
  /// drags it, and its three buttons are the system's own to run.
  void _report() {
    final controls = <Rect>[
      for (final key in [_toggle, _menus, _panel, _chat, _pin, _open, _back])
        ?_rect(key),
    ];
    final minimize = _rect(_minimize);
    final maximize = _rect(_maximize);
    final close = _rect(_close);
    // Not laid out yet (or going away): leave the window as it is.
    if (minimize == null || maximize == null || close == null) return;
    if (listEquals(_reported, [minimize, maximize, close, ...controls])) return;
    _reported = [minimize, maximize, close, ...controls];
    WindowControls.setHitTestAreas(
      height: CursorMetrics.headerHeight,
      controls: controls,
      minimize: minimize,
      maximize: maximize,
      close: close,
    );
  }

  /// Where [key]'s widget is in the window, in the app's own pixels; null
  /// while it is not laid out, or was not built at all (no project, so no
  /// editor button).
  Rect? _rect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// What a menu holds: this app's own commands, in the order such menus
  /// usually keep them. Read when the menu opens, so what is ticked and the
  /// recent projects are the ones there are now.
  List<HeaderMenuItem> _items(HeaderMenu menu) => switch (menu) {
    HeaderMenu.file => [
      HeaderMenuItem('Open Folder…', onSelected: widget.onOpenFolder),
      for (final (index, project) in _recent.indexed) ...[
        if (index == 0) const HeaderMenuItem.rule(),
        HeaderMenuItem(
          project.name,
          onSelected: () => widget.workspace.openFolder(project.path),
        ),
      ],
      const HeaderMenuItem.rule(),
      HeaderMenuItem(
        'Close Window',
        shortcut: 'Alt+F4',
        onSelected: () => WindowControls.windowCommand('close'),
      ),
    ],
    HeaderMenu.edit => [
      HeaderMenuItem(
        'Undo',
        shortcut: 'Ctrl+Z',
        onSelected: () => WindowControls.runEditCommand('undo'),
      ),
      HeaderMenuItem(
        'Redo',
        shortcut: 'Ctrl+Y',
        onSelected: () => WindowControls.runEditCommand('redo'),
      ),
      const HeaderMenuItem.rule(),
      HeaderMenuItem(
        'Cut',
        shortcut: 'Ctrl+X',
        onSelected: () => WindowControls.runEditCommand('cut'),
      ),
      HeaderMenuItem(
        'Copy',
        shortcut: 'Ctrl+C',
        onSelected: () => WindowControls.runEditCommand('copy'),
      ),
      HeaderMenuItem(
        'Paste',
        shortcut: 'Ctrl+V',
        onSelected: () => WindowControls.runEditCommand('paste'),
      ),
      const HeaderMenuItem.rule(),
      HeaderMenuItem(
        'Select All',
        shortcut: 'Ctrl+A',
        onSelected: () => WindowControls.runEditCommand('selectAll'),
      ),
    ],
    HeaderMenu.view => [
      if (widget.workspace.layout == WorkspaceLayout.ide)
        HeaderMenuItem(
          'Back to Chat',
          onSelected: () => widget.workspace.layout = WorkspaceLayout.chat,
        )
      else
        HeaderMenuItem(
          widget.sidebarShown ? 'Hide Sidebar' : 'Show Sidebar',
          shortcut: 'Ctrl+B',
          onSelected: widget.onToggleSidebar,
        ),
      HeaderMenuItem(
        'Keep on Top',
        checked: widget.pinned,
        onSelected: () => widget.onTogglePin(!widget.pinned),
      ),
      const HeaderMenuItem.rule(),
      HeaderMenuItem('Context Panel', onSelected: widget.onToggleContextPanel),
    ],
    HeaderMenu.help => [
      HeaderMenuItem('About Monad', onSelected: () => showAboutMonad(context)),
    ],
  };

  /// The projects File offers under the folder picker: the most recent ones,
  /// as the workspace keeps them.
  List<Project> get _recent => widget.workspace.projects.take(5).toList();
}
