import 'package:flutter/widgets.dart';

import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
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
/// ([showSidebar], [showChat]) has the editor give way instead
/// ([editorHidden]), or, with too little room even for the two, closes the
/// other (a deviation: VS Code's grid has a window wide enough for all its
/// parts).
class IdeLayout extends ChangeNotifier {
  bool _sidebar = true;
  bool get sidebar => _sidebar;
  set sidebar(bool value) {
    if (value == _sidebar) return;
    _sidebar = value;
    // What the editor gave way to is gone.
    if (!value) _editorHidden = false;
    notifyListeners();
  }

  bool _chat = true;
  bool get chat => _chat;
  set chat(bool value) {
    if (value == _chat) return;
    _chat = value;
    if (!value) _editorHidden = false;
    notifyListeners();
  }

  /// Whether the editor gives way to the chat (and the side bar, if that
  /// shows): the chat's sash dragged past the editor's minimum, which
  /// maximizes the chat (VS Code's maximized secondary side bar,
  /// `setAuxiliaryBarMaximized`), or a side opened where the three do not
  /// fit. Hiding either side or opening an editor ([showEditor]) ends it;
  /// the panel stays, below. See [editorVisible].
  bool get editorHidden => _editorHidden;
  bool _editorHidden = false;

  /// Whether the editor shows: hidden, the chat has its place, and the side
  /// bar beside it, where there is room for the two but not the three.
  bool get editorVisible =>
      !(_editorHidden &&
          _chat &&
          (!_sidebar || (!_roomForBoth && _roomForSides)));

  /// The chat alone in the editor's place.
  bool get chatMaximized => !editorVisible && !_sidebar;

  /// Upstream's `showEditorIfHidden`: an editor opened.
  void showEditor() {
    if (!_editorHidden) return;
    _editorHidden = false;
    notifyListeners();
  }

  /// The parts as a sash's drag leaves them.
  void resize({
    required bool sidebar,
    required bool chat,
    required bool editorHidden,
  }) {
    editorHidden = editorHidden && chat;
    if (sidebar == _sidebar && chat == _chat && editorHidden == _editorHidden) {
      return;
    }
    _sidebar = sidebar;
    _chat = chat;
    _editorHidden = editorHidden;
    notifyListeners();
  }

  /// Whether the side bar and the chat both fit beside the editor, and
  /// whether they do without it, as the workbench last laid them out.
  bool get roomForBoth => _roomForBoth;
  bool _roomForBoth = true;
  bool get roomForSides => _roomForSides;
  bool _roomForSides = true;

  void setRoom({required bool both, required bool sides}) {
    if (both == _roomForBoth && sides == _roomForSides) return;
    _roomForBoth = both;
    _roomForSides = sides;
    notifyListeners();
  }

  /// Whether the side bar shows: [sidebar], and not given way to the chat.
  bool get sidebarVisible =>
      _sidebar && (!editorVisible || _roomForBoth || !_chat);

  /// Shows the side bar, as the user asked: where it and the chat do not
  /// both fit beside the editor, the editor gives way, or, with too little
  /// room for the two even so, the chat closes.
  void showSidebar() {
    if (sidebarVisible) return;
    _sidebar = true;
    if (!_chat || _roomForBoth) {
      _editorHidden = false;
    } else if (_roomForSides) {
      _editorHidden = true;
    } else {
      _chat = false;
      _editorHidden = false;
    }
    notifyListeners();
  }

  /// Shows the chat, as the user asked: as [showSidebar], the editor or
  /// else the side bar gives way.
  void showChat() {
    if (_chat) return;
    _chat = true;
    if (_sidebar && !_roomForBoth) {
      if (_roomForSides) {
        _editorHidden = true;
      } else {
        _sidebar = false;
      }
    }
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

  /// The tab the panel shows again when toggled back: TERMINAL at first,
  /// the panel's default view (upstream registers the terminal's view
  /// container with `isDefault: true`, terminal.contribution.ts); PROBLEMS
  /// where there are no [terminals].
  IdePanelTab get lastPanel => !terminals && _lastPanel == IdePanelTab.terminal
      ? IdePanelTab.problems
      : _lastPanel;
  IdePanelTab _lastPanel = IdePanelTab.terminal;

  /// Whether the panel has TERMINAL: terminals run here (not on the web).
  bool terminals = true;

  /// VS Code's Toggle Panel: the panel as it was last, or hidden.
  void togglePanel() => panel = panel == null ? lastPanel : null;
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
      final l10n = context.l10n;
      String? keys(String command) =>
          KeybindingService.instance.labelFor(command);
      final (icon, tooltip, toggle) = switch (_part) {
        _Part.sidebar => (
          layout.sidebarVisible
              ? Codicons.layoutSidebarLeft
              : Codicons.layoutSidebarLeftOff,
          ideWithKeybinding(
            l10n.layoutTogglePrimarySideBar,
            keys('workbench.action.toggleSidebarVisibility'),
          ),
          layout.toggleSidebar,
        ),
        _Part.panel => (
          layout.panel != null ? Codicons.layoutPanel : Codicons.layoutPanelOff,
          // Toggle Panel's, else Toggle Terminal's (⌃`), which it is here.
          ideWithKeybinding(
            l10n.layoutTogglePanel,
            keys('workbench.action.togglePanel') ??
                keys('workbench.action.terminal.toggleTerminal'),
          ),
          layout.togglePanel,
        ),
        _Part.chat => (
          layout.chat
              ? Codicons.layoutSidebarRight
              : Codicons.layoutSidebarRightOff,
          ideWithKeybinding(
            l10n.layoutToggleChat,
            keys('workbench.action.toggleAuxiliaryBar'),
          ),
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
