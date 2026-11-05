// The window's parts as they are laid out (upstream `IWorkbenchLayoutService`,
// layout.ts, with the view and panel services' `openViewContainer` and
// `openPaneComposite`): the side bar's view, the parts' sizes, the panel
// maximized, which part has the keyboard; and what shows (the side bar,
// the panel's tab, the chat) is the workspace's IdeLayout, which the
// window's header toggles as well.

import 'package:flutter/widgets.dart';

import '../ide_columns.dart';
import '../ide_layout.dart';
import '../lsp_ui/problems_panel.dart' show IdePanelTab;
import '../workbench/contributions.dart';
import '../workbench/storage.dart';
import '../workbench/views.dart';

class LayoutService extends ChangeNotifier
    implements WorkbenchStorageParticipant {
  LayoutService({required this.host, required this._layout});

  final WorkbenchHost host;

  /// What shows: the workspace's (another after one is swapped).
  final IdeLayout Function() _layout;
  IdeLayout get layout => _layout();

  /// The side bar's view.
  IdeSideView get view => _view;
  IdeSideView _view = IdeSideView.explorer;
  set view(IdeSideView view) {
    if (_view == view) return;
    _view = view;
    notifyListeners();
  }

  /// The widths the side bar and the chat open at, and have while there is
  /// room (see [IdeColumns.fit]); the panel's height below the editor,
  /// null for a third of the column (see IdeRows). Set as their sashes
  /// are dragged.
  double sidebarWidth = IdeColumns.defaultSidebar;
  double chatWidth = IdeColumns.defaultChat;
  double? panelHeight;

  /// A sash dragged or reset: the parts laid out again, the window kept.
  void resized() => notifyListeners();

  /// Whether the panel is maximized (Toggle Maximized Panel); unset as the
  /// panel's sash is dragged.
  bool panelMaximized = false;

  /// Around the side bar, the panel and the chat: for `sideBarFocus`,
  /// `panelFocus` and `auxiliaryBarFocus`.
  final sidebarFocus = FocusNode(
    debugLabel: 'ide side bar',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final panelFocus = FocusNode(
    debugLabel: 'ide panel',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final chatFocus = FocusNode(
    debugLabel: 'ide chat',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// What gives a view (a panel's tab) the keyboard as it shows, where
  /// not the first thing in it (upstream `IViewPaneContainer.focus`).
  final Map<IdeSideView, VoidCallback> _viewFocus = {};
  final Map<IdePanelTab, VoidCallback> _panelFocus = {};

  /// [focus] gives [view] the keyboard as it shows, until the returned
  /// callback runs.
  VoidCallback focusViewWith(IdeSideView view, VoidCallback focus) {
    _viewFocus[view] = focus;
    return () {
      if (_viewFocus[view] == focus) _viewFocus.remove(view);
    };
  }

  /// [focus] shows the panel's [tab] and gives it the keyboard (Focus into
  /// Panel), until the returned callback runs.
  VoidCallback focusPanelWith(IdePanelTab tab, VoidCallback focus) {
    _panelFocus[tab] = focus;
    return () {
      if (_panelFocus[tab] == focus) _panelFocus.remove(tab);
    };
  }

  IdeLayout? _attached;
  IdePanelTab? _shownPanel;

  /// Follows [layout], the workspace's.
  void attach(IdeLayout layout) {
    _attached = layout..addListener(_layoutChanged);
    _shownPanel = layout.panel;
  }

  void detach() {
    _attached?.removeListener(_layoutChanged);
    _attached = null;
  }

  /// A part shown or hidden, here or from the window's header.
  void _layoutChanged() {
    final panel = layout.panel;
    if (panel != _shownPanel) {
      _shownPanel = panel;
      // Upstream restores a maximized panel as it hides.
      if (panel == null) panelMaximized = false;
      // What had the keyboard there goes: it goes back to the editor.
      if (panelFocus.hasFocus) host.focusSoon();
    }
    notifyListeners();
  }

  bool get sidebarShown => layout.sidebar;
  bool get chatShown => layout.chat;

  /// The panel's tab, or null when the panel is hidden; and the one it
  /// shows again when toggled back.
  IdePanelTab? get panel => layout.panel;
  set panel(IdePanelTab? tab) => layout.panel = tab;
  IdePanelTab get lastPanel => layout.lastPanel;

  /// [view] in the side bar, shown, with the keyboard where it takes it as
  /// it shows (the explorer's tree).
  void showView(IdeSideView view) {
    _view = view;
    layout.showSidebar();
    notifyListeners();
    if (_viewFocus[view] case final focus?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.context != null) focus();
      });
    }
  }

  void toggleSidebar() => layout.toggleSidebar();
  void toggleChat() => layout.toggleChat();

  /// VS Code's Toggle Panel: the panel as it was last, or hidden.
  void togglePanel() => panel = panel == null ? lastPanel : null;

  /// The panel on [tab], or hidden.
  void togglePanelTab(IdePanelTab tab) => panel = panel == tab ? null : tab;

  /// Toggle Maximized Panel: the panel shown maximized, or back as high as
  /// it was.
  void toggleMaximizedPanel() {
    if (panel == null) {
      panelMaximized = true;
      panel = lastPanel;
    } else {
      panelMaximized = !panelMaximized;
      notifyListeners();
    }
  }

  /// Focus into Panel: the panel shown, and what it shows focused.
  void focusPanel() {
    final tab = panel ?? lastPanel;
    if (_panelFocus[tab] case final focus?) return focus();
    panel = tab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context == null) return;
      panelFocus.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  /// Focus into Primary Side Bar: it shown, its view focused.
  void focusSideBar() {
    showView(_view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context == null || sidebarFocus.hasFocus) return;
      sidebarFocus.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  /// The layout's context keys (upstream's `SideBarVisibleContext`,
  /// `PanelFocusContext`…); null for others.
  Object? contextKey(String key) => switch (key) {
    'sideBarVisible' => layout.sidebarVisible,
    'sideBarFocus' => sidebarFocus.hasFocus,
    'activeViewlet' => layout.sidebarVisible ? _view.viewletId : null,
    'explorerViewletFocus' =>
      sidebarFocus.hasFocus && _view == IdeSideView.explorer,
    'foldersViewVisible' ||
    'explorerViewletVisible' => sidebarShown && _view == IdeSideView.explorer,
    'panelVisible' => panel != null,
    'panelFocus' => panelFocus.hasFocus,
    'panelMaximized' => panel != null && panelMaximized,
    'activePanel' => panel?.panelId,
    'auxiliaryBarVisible' => chatShown,
    'auxiliaryBarFocus' => chatFocus.hasFocus,
    'focusedView' => focusedView ?? '',
    'inDebugRepl' =>
      panelFocus.hasFocus && (panel ?? lastPanel) == IdePanelTab.debugConsole,
    _ => null,
  };

  /// The id of the side bar's or the panel's view with the keyboard
  /// (upstream `focusedView`); a view's own tree says its own first (the
  /// explorer's).
  String? get focusedView {
    if (sidebarFocus.hasFocus) {
      return switch (_view) {
        IdeSideView.explorer => 'outline',
        IdeSideView.search => 'workbench.view.search',
        IdeSideView.sourceControl => 'workbench.scm',
        IdeSideView.debug => 'workbench.debug.viewlet',
        IdeSideView.extensions => 'workbench.views.extensions.installed',
      };
    }
    if (panelFocus.hasFocus) return (panel ?? lastPanel).viewId;
    return null;
  }

  @override
  void restoreState(Map<String, Object?> kept) {
    double? size(String key) => switch (kept[key]) {
      final num value when value.isFinite && value > 0 => value.toDouble(),
      _ => null,
    };
    sidebarWidth = size('sidebarWidth') ?? sidebarWidth;
    chatWidth = size('chatWidth') ?? chatWidth;
    panelHeight = size('panelHeight');
    if (kept['view'] case final String name) {
      _view = IdeSideView.values.asNameMap()[name] ?? _view;
    }
  }

  @override
  void saveState(Map<String, Object?> into) {
    into
      ..['sidebarWidth'] = sidebarWidth
      ..['chatWidth'] = chatWidth
      ..addAll({'panelHeight': ?panelHeight})
      ..addAll(layout.toJson())
      ..['view'] = _view.name;
  }

  @override
  void dispose() {
    detach();
    sidebarFocus.dispose();
    panelFocus.dispose();
    chatFocus.dispose();
    super.dispose();
  }
}

extension on IdeSideView {
  /// Upstream's id of the view container (`activeViewlet`).
  String get viewletId => switch (this) {
    IdeSideView.explorer => 'workbench.view.explorer',
    IdeSideView.search => 'workbench.view.search',
    IdeSideView.sourceControl => 'workbench.view.scm',
    IdeSideView.debug => 'workbench.view.debug',
    IdeSideView.extensions => 'workbench.view.extensions',
  };
}

extension on IdePanelTab {
  /// Upstream's id of the panel (`activePanel`).
  String get panelId => switch (this) {
    IdePanelTab.problems => 'workbench.panel.markers',
    IdePanelTab.references => 'workbench.panel.referenceSearch',
    IdePanelTab.debugConsole => 'workbench.panel.repl',
    IdePanelTab.terminal => 'terminal',
  };

  /// Upstream's id of its view (`focusedView`).
  String get viewId => switch (this) {
    IdePanelTab.problems => 'workbench.panel.markers.view',
    IdePanelTab.references => 'workbench.panel.referenceSearch',
    IdePanelTab.debugConsole => 'workbench.panel.repl',
    IdePanelTab.terminal => 'terminal',
  };
}
