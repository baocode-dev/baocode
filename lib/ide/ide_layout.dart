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
/// Where the three do not fit, the one the user last asked for stays
/// ([showSidebar], [showChat], or an editor opened, [showEditor]); of the
/// rest, the editor gives way first, then the side bar, then the chat. One
/// that gave way to what the user asked for stays hidden until asked for
/// again; one that gave way to a narrow window is back as it widens. With
/// too little room even for the side bar and the chat, one opened closes
/// the other (a deviation: VS Code's grid has a window wide enough for all
/// its parts).
class IdeLayout extends ChangeNotifier {
  bool _sidebar = true;
  bool get sidebar => _sidebar;
  set sidebar(bool value) {
    if (value == _sidebar) return;
    _sidebar = value;
    notifyListeners();
  }

  bool _chat = true;
  bool get chat => _chat;
  set chat(bool value) {
    if (value == _chat) return;
    _chat = value;
    // With the chat gone, the editor has its place again.
    if (!value) _editorHidden = false;
    notifyListeners();
  }

  /// Whether the editor gives way to the chat (and the side bar, if that
  /// shows), as the user left it: the chat's sash dragged past the editor's
  /// minimum, which maximizes the chat (VS Code's maximized secondary side
  /// bar, `setAuxiliaryBarMaximized`), or a side opened where the three do
  /// not fit. Hiding the chat or opening an editor ([showEditor]) ends it;
  /// the panel stays, below. See [editorVisible].
  bool get editorHidden => _editorHidden;
  bool _editorHidden = false;

  /// Whether an editor was what the user last asked for: where the three
  /// do not fit, the side bar gives way to it, not it to the side bar.
  bool _editorAsked = false;

  /// Whether the editor shows: not where it gave way to the chat
  /// ([editorHidden]), nor to the chat and the side bar in a window too
  /// narrow for the three, unless it was what the user last asked for.
  bool get editorVisible =>
      !_chat || (!_editorHidden && (_editorAsked || !_sidebar || _roomForBoth));

  /// The chat alone in the editor's place.
  bool get chatMaximized => !editorVisible && !sidebarVisible;

  /// Upstream's `showEditorIfHidden`: an editor opened. Where it had given
  /// way to the side bar and the chat, with no room for the three, the side
  /// bar stays, where the user opened it from, and the chat closes.
  void showEditor() {
    if (!_editorHidden && _editorAsked) return;
    if (_chat && !editorVisible && sidebarVisible && !_roomForBoth) {
      _chat = false;
    }
    _editorHidden = false;
    _editorAsked = true;
    notifyListeners();
  }

  /// The parts as a sash's drag leaves them.
  void resize({
    required bool sidebar,
    required bool chat,
    required bool editorHidden,
  }) {
    editorHidden = editorHidden && chat;
    // The editor dragged out is asked for.
    final asked = _editorAsked || (!editorVisible && !editorHidden);
    if (sidebar == _sidebar &&
        chat == _chat &&
        editorHidden == _editorHidden &&
        asked == _editorAsked) {
      return;
    }
    _sidebar = sidebar;
    _chat = chat;
    _editorHidden = editorHidden;
    _editorAsked = asked;
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

  /// Whether the side bar shows: [sidebar], and not given way to the
  /// editor the user asked for, nor to the chat alone in too little room.
  bool get sidebarVisible =>
      _sidebar && (!_chat || (editorVisible ? _roomForBoth : _roomForSides));

  /// Shows the side bar, as the user asked: where it and the chat do not
  /// both fit beside the editor, the editor gives way, or, with too little
  /// room for the two even so, the chat closes. The editor hidden, it stays
  /// so.
  void showSidebar() {
    if (sidebarVisible) return;
    _sidebar = true;
    _editorAsked = false;
    if (!_chat) {
      _editorHidden = false;
    } else if (!_roomForBoth) {
      if (_roomForSides) {
        _editorHidden = true;
      } else {
        _chat = false;
        _editorHidden = false;
      }
    }
    notifyListeners();
  }

  /// Shows the chat, as the user asked: as [showSidebar], the editor or
  /// else the side bar gives way.
  void showChat() {
    if (_chat) return;
    _chat = true;
    _editorAsked = false;
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
  /// shows it (see [showSidebar]). Hidden, its room is the chat's where the
  /// editor gave way: the editor is not back until asked for.
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

  /// Which parts show, to [restore] in the next run.
  Map<String, Object?> toJson() => {
    'sidebar': _sidebar,
    'chat': _chat,
    'panel': ?_panel?.name,
  };

  /// The parts as [toJson] kept them, as the workspace is made: the
  /// terminal's panel only where [terminals] run, and References not, with
  /// nothing to show again.
  void restore(Map<String, Object?> kept) {
    _sidebar = kept['sidebar'] != false;
    _chat = kept['chat'] != false;
    _editorHidden = false;
    final panel = switch (kept['panel']) {
      'problems' => IdePanelTab.problems,
      'terminal' when terminals => IdePanelTab.terminal,
      _ => null,
    };
    if (panel != null) _lastPanel = panel;
    _panel = panel;
    notifyListeners();
  }
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
