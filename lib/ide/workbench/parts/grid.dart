// The parts laid out (upstream layout.ts' grid): the activity bar, the
// side bar, the editor and the panel below it, the chat, each sash over
// the line between two; the status bar under all but the chat, whose row
// has its right items as fit. Built again as the layout and the debugger
// change; each part as its own services do.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../debug/ui/debug_toolbar.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/islands.dart';
import '../../ide_columns.dart';
import '../../ide_layout.dart';
import '../../ide_modern_ui.dart';
import '../../ide_rows.dart';
import '../../ide_status_bar.dart';
import '../../ide_tab_bar.dart';
import '../../services/debug_view.dart';
import '../../services/language.dart';
import '../../services/layout.dart';
import '../options.dart';
import '../services.dart';
import '../style.dart';
import '../views.dart';
import 'activity_bar.dart';
import 'editor.dart';
import 'panel.dart';
import 'sash.dart';
import 'side_bar.dart';
import 'status_bar.dart';

class WorkbenchGrid extends StatefulWidget {
  const WorkbenchGrid({super.key, required this.options});

  final WorkbenchOptions options;

  @override
  State<WorkbenchGrid> createState() => _WorkbenchGridState();
}

class _WorkbenchGridState extends State<WorkbenchGrid> {
  late WorkbenchServices _services;
  late LayoutService _service;

  /// Which parts show: the workspace's (see [IdeLayout]).
  IdeLayout get _layout => widget.options.workspace.layout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = WorkbenchScope.of(context);
    _service = _services.get<LayoutService>();
  }

  @override
  void dispose() {
    _statusUnderChat.dispose();
    super.dispose();
  }

  /// [change] made to the sizes: the parts laid out again, the window
  /// kept.
  void _resize(VoidCallback change) {
    change();
    _service.resized();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_service, _services.get<DebugViewService>()]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) =>
          _split(context, _services, constraints.biggest),
    ),
  );

  /// The widths, and the room for them, when a sash's drag began: it
  /// follows the pointer from there, so what it pushed aside or snapped
  /// shut comes back as it returns. (The room is the start's: the chat
  /// snapped shut takes the window's gap beside it along.)
  ({IdeColumns columns, double room})? _dragStart;

  /// Whether the chat's sash is being dragged: snapped shut, it stays till
  /// the drag ends, so the drag can bring the chat back.
  bool _chatSashDragging = false;

  /// The panel's height, and the room for it, when its sash's drag began.
  ({IdeRows rows, double room})? _panelDragStart;

  /// The chat, kept mounted (and its state kept) while hidden.
  /// [trailing]: the status bar's right items, in the row under its card.
  Widget _chatSlot(double width, {Widget? trailing}) {
    final shown = width > 0;
    final laidOut = shown ? width : _service.chatWidth;
    return SizedBox(
      key: const ValueKey('ide-chat'),
      width: width,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: laidOut,
        maxWidth: laidOut,
        child: Offstage(
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(
              excluding: !shown,
              child: _chatPart(trailing: trailing),
            ),
          ),
        ),
      ),
    );
  }

  /// The chat, which keeps its state as it moves to the editor's place,
  /// maximized, and back: its tabs on the window's color over its card.
  Widget _chatPart({Widget? trailing}) => Padding(
    key: _chatKey,
    padding: EdgeInsets.symmetric(horizontal: WorkbenchStyle.gap / 2),
    child: IslandFootTrailing(
      trailing: trailing,
      onRoom: (room) {
        _chatFootRoom = room;
        _fitStatus();
      },
      child: HeadedIsland(
        header: IdeTabStrip.height,
        // In its own column, down to the window's foot: its branch under
        // its card, in the status bar's row, then [trailing]; in the
        // editor's place, the panel under it.
        footer: _layout.editorVisible ? Islands.belowHeight : 0,
        color: AppColors.code,
        // Not islands: beside the editor, the secondary side bar, the side
        // bar's line on its left; its row in line with the status bar.
        border: _layout.editorVisible ? Border(left: SideBarPart.line) : null,
        footerLine: IdeStatusBar.line,
        footerColor: themeColors.get('statusBar.background'),
        child: Focus(focusNode: _service.chatFocus, child: widget.options.chat),
      ),
    ),
  );
  final _chatKey = GlobalKey(debugLabel: 'ide chat');

  /// How many of the status bar's right items, from its end, are in the
  /// row under the chat, after its branch: as many as fit there, the rest
  /// at the end of the bar under the rest.
  final _statusUnderChat = ValueNotifier(0);

  /// The status bar's right items' widths, by index, wherever they are.
  final _statusWidths = <int, double>{};

  /// How many right items the status bar has.
  int _statusRight = 0;

  /// The room for them under the chat, after its branch.
  double _chatFootRoom = 0;
  bool _fittingStatus = false;

  void _noteStatusWidth(int index, double width) {
    _statusWidths[index] = width;
    _fitStatus();
  }

  /// [_statusUnderChat] from what was measured: told in layout, set after
  /// the frame.
  void _fitStatus() {
    if (_fittingStatus) return;
    _fittingStatus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fittingStatus = false;
      if (!mounted) return;
      var (width, fit) = (0.0, 0);
      for (var i = _statusRight - 1; i >= 0; i--) {
        final item = _statusWidths[i];
        if (item == null || width + item > _chatFootRoom) break;
        width += item;
        fit++;
      }
      _statusUnderChat.value = fit;
    });
  }

  /// What [IdeLayout.roomForBoth] and [IdeLayout.roomForSides] are to be,
  /// from the last layout: the layout's listeners build, so it is told
  /// after the frame.
  ({bool both, bool sides}) _room = (both: true, sides: true);
  bool _roomPending = false;

  void _noteRoom(({bool both, bool sides}) room) {
    _room = room;
    if ((room.both == _layout.roomForBoth &&
            room.sides == _layout.roomForSides) ||
        _roomPending) {
      return;
    }
    _roomPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomPending = false;
      if (mounted) _layout.setRoom(both: _room.both, sides: _room.sides);
    });
  }

  /// The side bar and its sash, which keep their state (and a drag) as they
  /// move beside the chat in the editor's place, and back.
  final _sidebarKey = GlobalKey(debugLabel: 'ide side bar');
  final _sidebarSashKey = GlobalKey(debugLabel: 'ide side bar sash');

  /// The parts, flush and square: the activity bar, the side bar, the
  /// editor (the panel below it) and the chat, each sash over the line
  /// between two (VS Code's `sash-size`, half on either side). The chat
  /// stays on the right however narrow the window (see [IdeColumns.fit]).
  /// With the editor hidden ([IdeLayout.editorHidden]), the chat has its
  /// place, beside the side bar if that shows, the panel below the two.
  /// [statusChanges]: what changes the status bar.
  Widget _split(BuildContext context, WorkbenchServices services, Size size) {
    // The activity bar's room: its lane at the right the half gap the card
    // after it keeps, so the card is against it, its items as far from
    // either side.
    final bar = IdeModernUI.activityBarWidth - WorkbenchStyle.gap / 2;
    // The editor hidden, the chat is sized as though it were there: dragged
    // back, the editor comes out where the pointer is.
    final room = size.width - bar;
    _noteRoom((
      both: IdeColumns.roomForBoth(room),
      sides: IdeColumns.roomForSides(room),
    ));
    final editorHidden = !_layout.editorVisible;
    final columns = IdeColumns.fit(
      room,
      sidebar: _layout.sidebar ? _service.sidebarWidth : null,
      chat: _layout.chat ? _service.chatWidth : null,
      editorHidden: editorHidden,
    );
    final sidebarVisible = columns.sidebar > 0;
    final chatVisible = columns.chat > 0;
    // Source Control, the Git log, has the side bar's and the editor's
    // place, above the panel; the editor is kept, back as another view
    // shows.
    final gitLog =
        !editorHidden &&
        sidebarVisible &&
        _service.view == IdeSideView.sourceControl;
    final sidebar = SizedBox(
      key: const ValueKey('ide-sidebar'),
      width: columns.sidebar,
      child: KeyedSubtree(
        key: _sidebarKey,
        child: SideBarPart(options: widget.options),
      ),
    );
    // With the side bar hidden, by the activity bar: dragged out, it opens
    // the side bar.
    final sidebarSash = KeyedSubtree(
      key: _sidebarSashKey,
      child: WorkbenchSash(
        key: const ValueKey('ide-sidebar-sash'),
        canMoveBack: sidebarVisible,
        canMoveForward: columns.canGrowSidebar(room),
        onStart: () => _dragStart = (columns: columns, room: room),
        onDrag: (dx) => _dragTo((start, room) => start.dragSidebar(room, dx)),
        onReset: () => _resize(() {
          _layout.showSidebar();
          _service.sidebarWidth = IdeColumns.defaultSidebar;
        }),
      ),
    );
    final chatSash = WorkbenchSash(
      key: const ValueKey('ide-chat-sash'),
      canMoveBack: columns.canGrowChat(room),
      canMoveForward: chatVisible,
      onStart: () {
        _dragStart = (columns: columns, room: room);
        _chatSashDragging = true;
      },
      onEnd: () {
        if (mounted) setState(() => _chatSashDragging = false);
      },
      onDrag: (dx) => _dragTo((start, room) => start.dragChat(room, dx)),
      onReset: () => _resize(() {
        _layout
          ..showChat()
          ..showEditor();
        _service.chatWidth = IdeColumns.defaultChat;
      }),
    );
    // The chat in its column, the status bar's right items are in the row
    // under its card, after its branch, against the window's edge, as many
    // as fit there; the bar under the rest has the others.
    final underChat = !editorHidden && chatVisible;
    // The language servers', whose progress it shows, change as they start.
    final language = services.get<LanguageService>();
    Listenable status() => Listenable.merge([
      workbenchStatusChanges(services, widget.options),
      _statusUnderChat,
    ]);
    int under(int right) {
      _statusRight = right;
      return underChat ? math.min(_statusUnderChat.value, right) : 0;
    }

    final statusBar = ListenableBuilder(
      listenable: language,
      builder: (context, _) => ListenableBuilder(
        listenable: status(),
        builder: (context, _) {
          final bar = workbenchStatusBar(context, services, widget.options);
          final right = bar.right;
          return IdeStatusBar(
            left: bar.left,
            right: right.sublist(0, right.length - under(right.length)),
            onRightWidth: _noteStatusWidth,
          );
        },
      ),
    );
    final statusTrailing = underChat
        ? ListenableBuilder(
            listenable: language,
            builder: (context, _) => ListenableBuilder(
              listenable: status(),
              builder: (context, _) {
                final right = workbenchStatusBar(
                  context,
                  services,
                  widget.options,
                ).right;
                final start = right.length - under(right.length);
                return IdeStatusBarTrailing(
                  right: right.sublist(start),
                  onWidth: (i, width) => _noteStatusWidth(start + i, width),
                );
              },
            ),
          )
        : null;
    final chat = KeyedSubtree(
      key: const ValueKey('ide-chat'),
      child: _chatPart(),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The status bar under all but the chat, which has its own
              // row there (its branch, then the bar's right items), as in
              // the agents' window.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: bar,
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: IdeModernUI.activityBarWidth,
                              maxWidth: IdeModernUI.activityBarWidth,
                              child: KeyedSubtree(
                                key: const ValueKey('ide-activity-bar'),
                                child: ActivityBarPart(
                                  sidebarShowing: sidebarVisible,
                                ),
                              ),
                            ),
                          ),
                          if (!editorHidden && sidebarVisible && !gitLog)
                            sidebar,
                          Expanded(
                            key: const ValueKey('ide-editor-column'),
                            child: _editorColumn(
                              size.height - IdeStatusBar.height,
                              inPlace: gitLog
                                  ? KeyedSubtree(
                                      key: _sidebarKey,
                                      child: SideBarPart(
                                        options: widget.options,
                                        border: false,
                                      ),
                                    )
                                  : !editorHidden
                                  ? null
                                  : sidebarVisible
                                  ? Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              sidebar,
                                              Expanded(child: chat),
                                            ],
                                          ),
                                        ),
                                        positionedSash(
                                          columns.sidebar,
                                          room,
                                          sidebarSash,
                                        ),
                                      ],
                                    )
                                  : chat,
                            ),
                          ),
                        ],
                      ),
                    ),
                    statusBar,
                  ],
                ),
              ),
              if (!editorHidden)
                _chatSlot(columns.chat, trailing: statusTrailing),
            ],
          ),
        ),
        if (!editorHidden && !gitLog)
          positionedSash(bar + columns.sidebar, size.width, sidebarSash),
        if (!editorHidden && (chatVisible || _chatSashDragging))
          positionedSash(size.width - columns.chat, size.width, chatSash)
        else if (editorHidden && !sidebarVisible)
          // The chat maximized: its sash is by the activity bar, and
          // dragged back, the editor comes out.
          positionedSash(bar, size.width, chatSash),
      ],
    );
  }

  /// The editor, and below it the panel (the terminal), as VS Code's panel
  /// at the bottom, centered: under the editor only. Hidden, the panel
  /// leaves its sash at the bottom. [inPlace] has the editor's place where
  /// it is hidden (the chat, and the side bar beside it), above the panel;
  /// the editor is kept, as the chat hidden is.
  Widget _editorColumn(double height, {Widget? inPlace}) {
    final hidden = inPlace != null;
    final shown = _layout.panel != null;
    final room = height;
    final rows = IdeRows.fit(
      room,
      panel: !shown
          ? null
          : _service.panelMaximized
          ? double.infinity
          : _service.panelHeight ?? IdeRows.defaultPanel(room),
      minAbove: hidden ? IdeRows.minChat : IdeRows.minEditor,
    );
    final panelVisible = rows.panel > 0;
    final debug = _services.get<DebugViewService>().service;
    final editor = KeyedSubtree(
      key: const ValueKey('ide-editor'),
      child: EditorPart(options: widget.options),
    );
    final toolbarLocation = debug?.settings().toolBarLocation;
    // In the middle of the gap over the panel's card.
    final sashTop =
        (height -
                rows.panel +
                WorkbenchStyle.gap / 2 -
                WorkbenchStyle.sashWidth / 2)
            .clamp(0.0, math.max(0.0, height - WorkbenchStyle.sashWidth))
            .toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: hidden,
                      child: TickerMode(
                        enabled: !hidden,
                        child: ExcludeFocus(
                          excluding: hidden,
                          child: toolbarLocation == 'floating' && debug != null
                              ? FloatingDebugToolbar(
                                  service: debug,
                                  child: editor,
                                )
                              : editor,
                        ),
                      ),
                    ),
                    ?inPlace,
                  ],
                ),
              ),
              _panelSlot(rows.panel),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: sashTop,
          height: WorkbenchStyle.sashWidth,
          child: WorkbenchSash(
            key: const ValueKey('ide-panel-sash'),
            axis: Axis.vertical,
            canMoveBack: rows.canGrowPanel(room),
            canMoveForward: panelVisible,
            onStart: () => _panelDragStart = (rows: rows, room: room),
            onDrag: _dragPanel,
            onReset: () => _resize(() {
              _layout.panel ??= _layout.lastPanel;
              _service.panelHeight = null;
            }),
          ),
        ),
      ],
    );
  }

  /// The panel's sash, [dy] from where its drag began. Snapped shut, the
  /// panel opens again (⌃`) as high as it was.
  void _dragPanel(double dy) {
    final start = _panelDragStart;
    if (start == null) return;
    final next = start.rows.drag(start.room, dy);
    _resize(() {
      _service.panelMaximized = false;
      if (next.panel > 0) {
        _layout.panel ??= _layout.lastPanel;
        _service.panelHeight = next.panel;
      } else if (start.rows.panel > 0) {
        _layout.panel = null;
        _service.panelHeight = start.rows.panel;
      }
    });
  }

  /// The panel, kept mounted (and its terminals running) while hidden.
  Widget _panelSlot(double height) {
    final shown = height > 0;
    final laidOut = shown ? height : _service.panelHeight ?? IdeRows.minPanel;
    return SizedBox(
      key: const ValueKey('ide-panel'),
      height: height,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: laidOut,
        maxHeight: laidOut,
        child: Offstage(
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(
              excluding: !shown,
              child: PanelPart(options: widget.options),
            ),
          ),
        ),
      ),
    );
  }

  /// Where a sash's drag has got to, [drag] from its start. A part pushed
  /// or snapped shut opens again (⌘B, ⌘J) as wide as it was, and the chat
  /// maximized comes back as wide as it was.
  void _dragTo(IdeColumns Function(IdeColumns start, double room) drag) {
    final start = _dragStart;
    if (start == null) return;
    final columns = start.columns;
    final next = drag(columns, start.room);
    _resize(() {
      if (next.sidebar > 0) {
        _service.sidebarWidth = next.sidebar;
      } else if (columns.sidebar > 0) {
        _service.sidebarWidth = columns.sidebar;
      }
      // With the editor hidden, the chat's width is the room's, not its
      // own: from there it comes back as wide as it was, and maximized, as
      // wide as when the drag began.
      if (next.editorHidden) {
        if (!columns.editorHidden && columns.chat > 0) {
          _service.chatWidth = columns.chat;
        }
      } else if (next.chat > 0) {
        if (!columns.editorHidden || columns.sidebar == 0) {
          _service.chatWidth = next.chat;
        }
      } else if (columns.chat > 0 && !columns.editorHidden) {
        _service.chatWidth = columns.chat;
      }
      _layout.resize(
        sidebar:
            !next.chatMaximized &&
            (next.sidebar > 0 || (columns.sidebar == 0 && _layout.sidebar)),
        chat: next.chat > 0 || (columns.chat == 0 && _layout.chat),
        editorHidden: next.editorHidden,
      );
    });
  }
}
