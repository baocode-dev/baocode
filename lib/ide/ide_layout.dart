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
    notifyListeners();
  }

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
          layout.sidebar
              ? Codicons.layoutSidebarLeft
              : Codicons.layoutSidebarLeftOff,
          'Toggle Primary Side Bar (${const IdeKeybinding(LogicalKeyboardKey.keyB, primary: true).label()})',
          () => layout.sidebar = !layout.sidebar,
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
          () => layout.chat = !layout.chat,
        ),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IdeActionButton(icon: icon, tooltip: tooltip, onPressed: toggle),
      );
    },
  );
}
