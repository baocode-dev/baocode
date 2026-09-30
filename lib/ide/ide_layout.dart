import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/codicons.dart';
import 'ide_commands.dart';
import 'ide_hover.dart';
import 'lsp_ui/problems_panel.dart';

/// Which of the workbench's parts show: the primary side bar, the panel and
/// the chat. The workbench's title bar toggles them, and so does the header
/// Windows draws, the workbench having no title bar of its own there; the
/// workbench follows either.
///
/// Where the side bar and the chat do not both fit beside the editor, the
/// side bar gives way ([sidebarVisible]); one opened as the user asks
/// ([showSidebar], [showChat]) closes the other instead (a deviation: VS
/// Code's grid has a window wide enough for all its parts).
class IdeLayout extends ChangeNotifier {
  bool _sidebar = true;
  bool get sidebar => _sidebar;
  set sidebar(bool value) {
    if (value == _sidebar) return;
    _sidebar = value;
    // Upstream's `setSideBarHidden(false)`: the maximized chat gives the
    // editor back first.
    if (value) _chatMaximized = false;
    notifyListeners();
  }

  bool _chat = true;
  bool get chat => _chat;
  set chat(bool value) {
    if (value == _chat) return;
    _chat = value;
    if (!value) _chatMaximized = false;
    notifyListeners();
  }

  /// Whether the chat has the editor's place (and the side bar's): VS
  /// Code's maximized secondary side bar, which the chat's sash dragged
  /// past the editor's minimum makes. Showing the side bar, hiding the chat
  /// or opening an editor ends it; the panel stays, below the chat.
  bool get chatMaximized => _chatMaximized;
  bool _chatMaximized = false;
  set chatMaximized(bool value) {
    if (value == _chatMaximized) return;
    _chatMaximized = value;
    if (value) {
      _chat = true;
      _sidebar = false;
    }
    notifyListeners();
  }

  /// Whether the side bar and the chat both fit beside the editor, as the
  /// workbench last laid them out.
  bool get roomForBoth => _roomForBoth;
  bool _roomForBoth = true;
  set roomForBoth(bool value) {
    if (value == _roomForBoth) return;
    _roomForBoth = value;
    notifyListeners();
  }

  /// Whether the side bar shows: [sidebar], and not given way to the chat.
  bool get sidebarVisible =>
      _sidebar && !_chatMaximized && (_roomForBoth || !_chat);

  /// Shows the side bar, as the user asked: the chat closes where the two
  /// do not both fit.
  void showSidebar() {
    if (sidebarVisible) return;
    _sidebar = true;
    _chatMaximized = false;
    if (!_roomForBoth) _chat = false;
    notifyListeners();
  }

  /// Shows the chat, as the user asked: the side bar closes where the two
  /// do not both fit.
  void showChat() {
    if (_chat) return;
    _chat = true;
    if (!_roomForBoth) _sidebar = false;
    notifyListeners();
  }

  /// Toggle Primary Side Bar Visibility: hides the side bar showing, else
  /// shows it (see [showSidebar]).
  void toggleSidebar() => sidebarVisible ? sidebar = false : showSidebar();

  /// Toggle Chat, as [toggleSidebar].
  void toggleChat() => _chat ? chat = false : showChat();

  /// The panel's tab, or null when the panel is hidden.
  IdePanelTab? _panel;
  IdePanelTab? get panel => _panel;
  set panel(IdePanelTab? tab) {
    if (tab != null) _lastPanel = tab;
    if (tab == _panel) return;
    _panel = tab;
    notifyListeners();
  }

  /// The tab the panel shows again when toggled back.
  IdePanelTab get lastPanel => _lastPanel;
  IdePanelTab _lastPanel = IdePanelTab.problems;

  /// VS Code's Toggle Panel: the panel as it was last, or hidden.
  void togglePanel() => panel = panel == null ? _lastPanel : null;
}

enum _Part { sidebar, panel, chat }

/// One of VS Code's layout controls: a part's toggle, its icon showing
/// whether the part is open.
class IdeLayoutToggle extends StatelessWidget {
  const IdeLayoutToggle.sidebar(this.layout, {super.key})
    : _part = _Part.sidebar;
  const IdeLayoutToggle.panel(this.layout, {super.key}) : _part = _Part.panel;
  const IdeLayoutToggle.chat(this.layout, {super.key}) : _part = _Part.chat;

  final IdeLayout layout;
  final _Part _part;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: layout,
    builder: (context, _) {
      final (icon, tooltip, toggle) = switch (_part) {
        _Part.sidebar => (
          layout.sidebarVisible
              ? Codicons.layoutSidebarLeft
              : Codicons.layoutSidebarLeftOff,
          'Toggle Primary Side Bar (${const IdeKeybinding(LogicalKeyboardKey.keyB, primary: true).label()})',
          layout.toggleSidebar,
        ),
        _Part.panel => (
          layout.panel != null ? Codicons.layoutPanel : Codicons.layoutPanelOff,
          'Toggle Panel (${const IdeKeybinding(LogicalKeyboardKey.backquote, control: true).label()})',
          layout.togglePanel,
        ),
        _Part.chat => (
          layout.chat
              ? Codicons.layoutSidebarRight
              : Codicons.layoutSidebarRightOff,
          'Toggle Chat (${const IdeKeybinding(LogicalKeyboardKey.keyJ, primary: true).label()})',
          layout.toggleChat,
        ),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IdeActionButton(icon: icon, tooltip: tooltip, onPressed: toggle),
      );
    },
  );
}
