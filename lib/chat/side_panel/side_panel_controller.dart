import 'package:flutter/foundation.dart';

import 'file_open.dart';

/// A file the side panel shows: its text or its changes, as [request]
/// asked last.
class SidePanelTab {
  SidePanelTab(this.request);

  FileOpenRequest request;

  /// Goes up each time it is asked for again, for the preview to scroll to
  /// the lines asked for once more.
  int reveal = 0;

  String get path => request.path;
  bool get diff => request.diff;
}

enum SidePanelSection { changes, files, terminal }

/// Each conversation keeps its section and selected file and terminal.
class SidePanelTabs {
  SidePanelSection section = SidePanelSection.changes;
  final List<SidePanelTab> files = [];
  SidePanelTab? active;
  String? terminal;
  final Set<String> closedTerminals = {};
}

/// The agent window's side panel, at the right of the conversations as
/// the secondary side bar is in VS Code: the changes of the agent focused,
/// and the files opened from its conversation. Shown or not and its width
/// are the window's, kept between runs ([toJson]); the files open are each
/// conversation's own.
class AgentSidePanel extends ChangeNotifier {
  AgentSidePanel({Map<String, Object?>? state, this.onSave}) {
    _read(state);
  }

  /// As [state] (what [toJson] gave) has it, once that is read; not once
  /// it was shown, hidden or resized meanwhile.
  void restore(Map<String, Object?>? state) {
    if (state == null || _changed) return;
    _read(state);
    notifyListeners();
  }

  /// Shown, hidden or resized since it was made.
  bool _changed = false;

  void _read(Map<String, Object?>? state) {
    if (state?['shown'] case final bool shown) _shown = shown;
    if (state?['width'] case final num width) {
      _width = width.toDouble().clamp(minWidth, maxWidth);
    }
  }

  /// Told when what [toJson] gives changed, to keep it.
  final VoidCallback? onSave;

  static const defaultWidth = 460.0;
  static const minWidth = 280.0;
  static const maxWidth = 1200.0;

  /// The most files open at once, for a conversation: the oldest
  /// out of sight close.
  static const maxTabs = 12;

  bool get shown => _shown;
  bool _shown = false;

  double get width => _width;
  double _width = defaultWidth;

  final Expando<SidePanelTabs> _tabs = Expando();

  /// The files open for [conversation] (its session).
  SidePanelTabs tabsOf(Object conversation) =>
      _tabs[conversation] ??= SidePanelTabs();

  void show() => _setShown(true);
  void hide() => _setShown(false);
  void toggle() => _setShown(!_shown);

  void showSection(Object conversation, SidePanelSection section) {
    tabsOf(conversation).section = section;
    show();
    notifyListeners();
  }

  void openTerminal(Object conversation, String id) {
    final tabs = tabsOf(conversation);
    tabs.closedTerminals.remove(id);
    tabs.terminal = id;
    showSection(conversation, SidePanelSection.terminal);
  }

  void closeTerminal(Object conversation, String id) {
    final tabs = tabsOf(conversation);
    tabs.closedTerminals.add(id);
    if (tabs.terminal == id) tabs.terminal = null;
    notifyListeners();
  }

  void _setShown(bool shown) {
    if (shown == _shown) return;
    _shown = shown;
    _changed = true;
    notifyListeners();
    onSave?.call();
  }

  /// As dragged; kept once the drag ends ([save]).
  set width(double width) {
    final clamped = width.clamp(minWidth, maxWidth);
    if (clamped == _width) return;
    _width = clamped;
    _changed = true;
    notifyListeners();
  }

  void save() => onSave?.call();

  /// Shows [request] for [conversation], in front: in the tab of the same
  /// file (its text or its changes, as asked) if there is one.
  void open(Object conversation, FileOpenRequest request) {
    final tabs = tabsOf(conversation);
    var tab = tabs.files
        .where((tab) => tab.path == request.path && tab.diff == request.diff)
        .firstOrNull;
    if (tab == null) {
      tab = SidePanelTab(request);
      tabs.files.add(tab);
      while (tabs.files.length > maxTabs) {
        tabs.files.removeAt(0);
      }
    } else {
      tab
        ..request = request
        ..reveal += 1;
    }
    tabs.active = tab;
    tabs.section = SidePanelSection.files;
    if (!_shown) {
      _shown = true;
      _changed = true;
      onSave?.call();
    }
    notifyListeners();
  }

  /// Brings [tab] to the front for [conversation]; null for its changes.
  void activate(Object conversation, SidePanelTab? tab) {
    final tabs = tabsOf(conversation);
    if (tab != null) tabs.active = tab;
    tabs.section = tab == null
        ? SidePanelSection.changes
        : SidePanelSection.files;
    notifyListeners();
  }

  /// Closes [tab]; selects the one after it, else before it, else no file.
  void close(Object conversation, SidePanelTab tab) {
    final tabs = tabsOf(conversation);
    final index = tabs.files.indexOf(tab);
    if (index < 0) return;
    tabs.files.removeAt(index);
    if (identical(tabs.active, tab)) {
      tabs.active = tabs.files.isEmpty
          ? null
          : tabs.files[index.clamp(0, tabs.files.length - 1)];
    }
    notifyListeners();
  }

  Map<String, Object?> toJson() => {'shown': _shown, 'width': _width};
}
