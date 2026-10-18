import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../base/give_way_row.dart';
import '../base/smooth_scroll.dart';
import '../chat/composer/file_drop.dart';
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/scroll_edge_fade.dart';
import '../ide/ide_dialog.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_input.dart';
import '../ide/ide_list.dart';
import '../ide/ide_menu.dart';
import '../ide/ide_motion.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../models/auxiliary_model_menu.dart';
import '../models/model_providers.dart';
import '../platform/app_platform.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/pin_window_button.dart';
import '../workspace/window_controls.dart';
import 'stash_actions.dart' show stashReferenceOf, stashProjectIcon;
import 'stash_controller.dart';
import 'stash_editor.dart' show StashAttachment, StashAttachmentIcon, StashRefs;
import 'stash_note.dart';
import 'stash_note_editor.dart';
import 'stash_settings.dart';
import 'stash_view.dart' show stashStatusLabel;

/// The top bar's height, and the search's row beside it.
const _barHeight = 40.0;

/// The stash's floating panel (see docs/stash.md): what the shortcut
/// shows over any app, with a new stash. What is written is kept as it is
/// typed (⌘S writes it at once); ⌘N starts another, ⌘W or Esc (or the
/// shortcut again) closes it. "All" lists every stash beside it, to go on
/// with one.
class StashPanelView extends StatefulWidget {
  const StashPanelView({
    super.key,
    required this.controller,
    required this.viewId,
  });

  final StashController controller;
  final int viewId;

  @override
  State<StashPanelView> createState() => _StashPanelViewState();
}

class _StashPanelViewState extends State<StashPanelView> {
  final GlobalKey<StashNoteEditorState> _editor = GlobalKey();
  final FocusNode _focus = FocusNode(debugLabel: 'stash');

  /// The list of all's: left with the keyboard as a stash opens from it.
  final FocusNode _listFocus = FocusNode(debugLabel: 'stash list');

  StashController get _controller => widget.controller;

  int _presentation = -1;

  /// "Saved" shows in the footer a moment after ⌘S.
  bool _saved = false;
  Timer? _savedTimer;

  /// Narrower than this, there is no room for the list of all: neither it
  /// nor its button shows.
  static const _narrow = 560.0;
  static const _listWidth = 220.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _controller.store.addListener(_changed);
    _controller.onHiding = _flush;
    _keepOnTop();
    WindowControls.handleEditCommands(widget.viewId);
    WindowControls.setMenuCommands(widget.viewId, _menuCommand);
    FileDrops.listen(widget.viewId);
    FileDrops.setUnhandledDrop(widget.viewId, (files) {
      final editor = _editor.currentState?.editor;
      if (editor == null) return false;
      unawaited(editor.insertFiles(files));
      return true;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.store.removeListener(_changed);
    if (_controller.onHiding == _flush) _controller.onHiding = null;
    WindowControls.setMenuCommands(widget.viewId, null);
    FileDrops.setUnhandledDrop(widget.viewId, null);
    _savedTimer?.cancel();
    _focus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  /// Whether the panel was last asked to stay on top.
  bool? _onTop;

  /// The panel over other apps' windows while pinned, as the pin is.
  void _keepOnTop() {
    final pinned = _controller.pinned;
    if (pinned == _onTop) return;
    _onTop = pinned;
    unawaited(WindowControls.setAlwaysOnTop(pinned, viewId: widget.viewId));
  }

  void _changed() {
    if (!mounted) return;
    _keepOnTop();
    setState(() {});
    if (_controller.presentation != _presentation) {
      _presentation = _controller.presentation;
      // Shown again: the keyboard in its text, at its end; unless it was
      // opened from the list, which keeps it (its arrows go on).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_listFocus.hasFocus) return;
        _editor.currentState?.focusEnd();
      });
    }
  }

  Future<void> _flush() async => _editor.currentState?.flush();

  Future<void> _save() async {
    await _flush();
    if (!mounted) return;
    _savedTimer?.cancel();
    setState(() => _saved = true);
    _savedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  void _close() => unawaited(_controller.hide());

  void _new() => unawaited(_controller.startNew());

  /// Says the stash clearly, in the background (see
  /// [StashController.clarify]): what it has written first.
  Future<void> _clarify(int id) async {
    await _flush();
    await _controller.clarify(id);
  }

  /// The panel's own keys (StashPanel.swift sends them, ahead of the app's
  /// menu), Esc among them.
  void _menuCommand(String command) {
    switch (command) {
      case 'baocode.stash.close' || 'workbench.action.closeWindow':
        _close();
      case 'baocode.stash.save':
        unawaited(_save());
      case 'baocode.stash.new':
        _new();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = AppPlatform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (!command || keyboard.isShiftPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyW) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_save());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      _new();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final note = _controller.editing == null
        ? null
        : _controller.store.byId(_controller.editing!);
    final mac = AppPlatform.isMacOS;
    final editor = StashNoteEditor(
      key: _editor,
      store: _controller.store,
      id: _controller.editing,
      generation: _controller.presentation,
      create: (body) => _controller.ensureNote(body: body),
      autofocus: true,
      attachments: true,
      refs: _controller.refs((href) {
        if (StashRefs.stashOf(href) case final id?) {
          unawaited(_controller.edit(id));
        }
      }),
      placeholder: l10n.stashPlaceholder,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
    );
    // As the main window is: the stash on the conversation's color, a tint
    // over the system's material (see StashPanel.swift) where there is
    // one, the list of all on the material itself, as the sidebar. The
    // window's own corners and edge, as the main window's (the system's).
    // Its dialogs and menus come in lively, not as the IDE's.
    return IdeMotion(
      lively: true,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < _narrow;
            final showAll = _controller.showAll;
            Widget all() => _AllStashes(
              controller: _controller,
              focusNode: _listFocus,
              onPick: (id) => unawaited(_controller.edit(id)),
              onEdit: () => _editor.currentState?.focusEnd(),
              flush: _flush,
            );
            final main = ColoredBox(
              color: AppColors.conversationSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    viewId: widget.viewId,
                    note: note,
                    showAll: showAll,
                    onAll: narrow ? null : () => _controller.showAll = !showAll,
                    onNew: _new,
                    onClose: _close,
                    projectLabel: _projectLabel(note),
                    onProject: _pickProject,
                    headline: note == null
                        ? ''
                        : _controller.store.headline(note),
                    pinned: _controller.pinned,
                    onPinned: (pinned) => _controller.pinned = pinned,
                    clarify: switch (note) {
                      final note? when !note.isBlank =>
                        (compact) => _ClarifyPill(
                          clarifying: _controller.clarifying(note.id),
                          failure: _controller.clarifyFailure(note.id),
                          onClarify: () => _clarify(note.id),
                          onCancel: () => _controller.cancelClarify(note.id),
                          compact: compact,
                        ),
                      _ => null,
                    },
                  ),
                  Expanded(child: editor),
                  _Footer(
                    status: _saved ? l10n.stashSaved : null,
                    hints: [
                      (mac ? '⌘S' : 'Ctrl+S', l10n.stashHintSave),
                      (mac ? '⌘N' : 'Ctrl+N', l10n.stashHintNew),
                      (mac ? '⌘W' : 'Ctrl+W', l10n.stashHintClose),
                    ],
                  ),
                ],
              ),
            );
            if (!showAll || narrow) return main;
            // As the main window is: the sidebar the whole height, the
            // stash beside it.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: _listWidth, child: all()),
                Expanded(child: main),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The project the stash is about: its own, none until one is picked.
  String? _projectLabel(StashNote? note) {
    final project = note?.project;
    if (project == null) return null;
    for (final known in _controller.workspace.projects) {
      if (known.path == project) return known.name;
    }
    return p.basename(project);
  }

  Future<void> _pickProject(Rect anchor) async {
    final l10n = context.l10n;
    final current = _controller.editing == null
        ? null
        : _controller.store.byId(_controller.editing!)?.project;
    Future<void> set(String? project) async {
      final id = await _controller.ensureNote();
      await _controller.store.update(id, (note) {
        note.project = project;
        note.suggestedProject = project == null ? note.suggestedProject : '';
      }, touch: false);
    }

    await showIdeMenu(
      context,
      anchor: anchor,
      entries: [
        IdeMenuAction(
          l10n.stashNoProject,
          checked: current == null,
          onSelected: () => unawaited(set(null)),
        ),
        const IdeMenuSeparator(),
        for (final project in _controller.workspace.projects)
          IdeMenuAction(
            project.name,
            icon: stashProjectIcon(_controller.workspace, project),
            checked: project.path == current,
            onSelected: () => unawaited(set(project.path)),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.viewId,
    required this.note,
    required this.showAll,
    required this.onAll,
    required this.onNew,
    required this.onClose,
    required this.projectLabel,
    required this.onProject,
    required this.headline,
    required this.pinned,
    required this.onPinned,
    this.clarify,
  });

  /// Says the stash clearly, [compact] its icon alone; none while there is
  /// nothing written.
  final Widget Function(bool compact)? clarify;

  /// Whether the panel stays over other apps' windows; the pin changes it.
  final bool pinned;
  final ValueChanged<bool> onPinned;

  /// What the stash is called (see [StashStore.headline]).
  final String headline;

  final int viewId;
  final StashNote? note;
  final bool showAll;

  /// Null in a panel too narrow for the list: no button.
  final VoidCallback? onAll;
  final VoidCallback onNew;
  final VoidCallback onClose;
  final String? projectLabel;
  final void Function(Rect anchor) onProject;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final note = this.note;
    final mac = AppPlatform.isMacOS;
    final projectLabel = this.projectLabel;
    // Its icon alone, its tooltip names the project.
    Widget project({required bool compact}) => Builder(
      builder: (context) => _PillButton(
        icon: Codicons.folder,
        label: compact ? null : projectLabel ?? l10n.stashNoProject,
        faint: projectLabel == null,
        tooltip: compact
            ? '${l10n.stashProjectTooltip} · '
                  '${projectLabel ?? l10n.stashNoProject}'
            : l10n.stashProjectTooltip,
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          onProject(box.localToGlobal(Offset.zero) & box.size);
        },
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Moves the panel, as a title bar does.
      onPanStart: (_) => unawaited(
        WindowControls.channelFor(viewId)
            .invokeMethod<void>('dragWindow')
            .catchError((Object _) {}),
      ),
      child: Container(
        height: _barHeight,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        // Too narrow, the pills give way to their icons, All's first, then
        // New's, Say Clearly's, the project's; then the stash's number. The
        // pin and the close button never do.
        child: GiveWayRow(
          children: [
            if (onAll case final onAll?)
              GiveWay(
                priority: 0,
                compact: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PillButton(
                    icon: Codicons.layoutSidebarLeft,
                    tooltip: l10n.stashAllTooltip,
                    active: showAll,
                    onTap: onAll,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PillButton(
                    icon: Codicons.layoutSidebarLeft,
                    label: l10n.stashAll,
                    tooltip: l10n.stashAllTooltip,
                    active: showAll,
                    onTap: onAll,
                  ),
                ),
              )
            else
              const GiveWay(SizedBox(width: 6)),
            GiveWay(
              priority: 1,
              compact: _PillButton(
                icon: Codicons.add,
                tooltip: l10n.stashNewTooltip,
                onTap: onNew,
              ),
              _PillButton(
                icon: Codicons.add,
                label: l10n.stashNewButton,
                tooltip: l10n.stashNewTooltip,
                onTap: onNew,
              ),
            ),
            GiveWay(
              priority: 4,
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  note == null ? l10n.stashNew : note.tag,
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Its title, else its first line, else the text in its pictures.
            GiveWay.fill(
              minWidth: 16,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ),
            ),
            if (clarify case final clarify?)
              GiveWay(
                priority: 2,
                compact: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: clarify(true),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: clarify(false),
                ),
              ),
            GiveWay(
              priority: 3,
              compact: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: project(compact: true),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: project(compact: false),
              ),
            ),
            GiveWay(
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: PinWindowButton(pinned: pinned, onChanged: onPinned),
              ),
            ),
            GiveWay(
              _PillButton(
                icon: Codicons.close,
                tooltip: '${l10n.stashHintClose}  ${mac ? '⌘W' : 'Ctrl+W'}',
                onTap: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every stash, beside the one written in, as the explorer lists files:
/// searched and filtered, sorted (or in the order dragged), built as they
/// scroll into view. A click opens one; with Cmd (Ctrl) or Shift, selects
/// more, to drag, delete or change together; the keyboard moves in it.
class _AllStashes extends StatefulWidget {
  const _AllStashes({
    required this.controller,
    required this.focusNode,
    required this.onPick,
    required this.onEdit,
    required this.flush,
  });

  final StashController controller;

  /// The list's, which the panel leaves the keyboard in as a stash opens.
  final FocusNode focusNode;
  final ValueChanged<int> onPick;

  /// Enter, or a double click: the keyboard to the text.
  final VoidCallback onEdit;

  /// Writes what is typed, before the stashes change.
  final Future<void> Function() flush;

  @override
  State<_AllStashes> createState() => _AllStashesState();
}

enum _Shown { all, open, done }

class _AllStashesState extends State<_AllStashes> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = SmoothScrollController();
  final GlobalKey _listKey = GlobalKey();
  _Shown _shown = _Shown.all;

  /// A project's path, '' for none; null for all.
  String? _project;

  /// The rows selected, and the one a Shift click selects from.
  Set<int> _selection = {};
  int? _anchor;

  /// The stash the panel showed when last built: one opened elsewhere is
  /// the selection then.
  int? _editing;

  /// Being dragged; where they would go (before the row at that index).
  List<int>? _dragging;
  int? _dropAt;
  Timer? _autoScroll;

  /// Each stash's picture or file for its icon, while its text is the same.
  final Map<int, (String, StashAttachment?)> _icons = {};

  static const _rowHeight = 28.0;
  static const _listPadding = EdgeInsets.fromLTRB(2, 0, 2, 8);

  StashController get _controller => widget.controller;

  bool get _command {
    final keyboard = HardwareKeyboard.instance;
    return AppPlatform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    widget.focusNode.addListener(_focusChanged);
    _renameFocus.addListener(_renameFocusChanged);
  }

  @override
  void didUpdateWidget(_AllStashes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focusChanged);
    _autoScroll?.cancel();
    _query.dispose();
    _scroll.dispose();
    _renameText.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  List<StashNote> _notes() {
    final store = _controller.store;
    final among = store.notes.where((note) {
      final shown = switch (_shown) {
        _Shown.all => true,
        _Shown.open => note.status != StashStatus.done,
        _Shown.done => note.status == StashStatus.done,
      };
      final project = switch (_project) {
        null => true,
        '' => note.project == null,
        final project => note.project == project,
      };
      return shown && project;
    });
    if (_query.text.trim().isNotEmpty) {
      return store.search(_query.text, among: among);
    }
    return store.sorted(among, _controller.sort);
  }

  /// Dragged into an order of their own: not among search results (in the
  /// order they match).
  bool get _canReorder => _query.text.trim().isEmpty;

  // --- Selection ----------------------------------------------------------------

  /// A click: with Shift, selects from the last one clicked; with Cmd
  /// (Ctrl), adds it to the selection or takes it out; else opens it.
  void _click(List<StashNote> notes, StashNote note) {
    widget.focusNode.requestFocus();
    if (HardwareKeyboard.instance.isShiftPressed) {
      _selectRange(notes, note.id);
    } else if (_command) {
      setState(() {
        _anchor = note.id;
        if (!_selection.remove(note.id)) _selection.add(note.id);
      });
    } else {
      _open(note.id);
    }
  }

  void _open(int id) {
    setState(() {
      _selection = {id};
      _anchor = id;
    });
    widget.onPick(id);
  }

  void _selectRange(List<StashNote> notes, int id) {
    final ids = [for (final note in notes) note.id];
    final to = ids.indexOf(id);
    if (to < 0) return;
    var from = _anchor == null ? -1 : ids.indexOf(_anchor!);
    if (from < 0) {
      from = to;
      _anchor = id;
    }
    setState(() {
      _selection = {...ids.sublist(math.min(from, to), math.max(from, to) + 1)};
    });
  }

  /// What the menu, Delete or a drag act on for [note]: the selection when
  /// it is in it, else it alone; as the list shows them.
  List<int> _targets(List<StashNote> notes, StashNote note) {
    if (_selection.length < 2 || !_selection.contains(note.id)) {
      return [note.id];
    }
    return [
      for (final note in notes)
        if (_selection.contains(note.id)) note.id,
    ];
  }

  // --- Keyboard -----------------------------------------------------------------

  /// The explorer's commands this list runs, by their keybindings (the
  /// user's own among them): moving, selecting, opening, renaming,
  /// deleting, copying and pasting as the files are.
  static const _commands = {
    'list.focusDown',
    'list.focusUp',
    'list.focusPageDown',
    'list.focusPageUp',
    'list.focusFirst',
    'list.focusLast',
    'list.expandSelectionDown',
    'list.expandSelectionUp',
    'list.selectAll',
    'list.clear',
    'list.select',
    'list.toggleExpand',
    'filesExplorer.openFilePreserveFocus',
    'renameFile',
    'moveFileToTrash',
    'deleteFile',
    'filesExplorer.copy',
    'filesExplorer.paste',
  };

  /// As the explorer's rows are when they have the keyboard: a file (not
  /// a folder, not the root) that can go to the trash.
  Object? _context(String key) => switch (key) {
    'listFocus' ||
    'filesExplorerFocus' ||
    'foldersViewVisible' ||
    'listSupportsMultiselect' ||
    'explorerResourceMoveableToTrash' => true,
    // Escape takes back a selection of more than one; else it closes the
    // panel.
    'listHasSelectionOrFocus' => _selection.length > 1,
    _ => false,
  };

  KeyEventResult _key(List<StashNote> notes, KeyEvent event) {
    if (event is KeyUpEvent || notes.isEmpty || _renaming != null) {
      return KeyEventResult.ignored;
    }
    final found = KeybindingService.instance.resolveEvent(
      event,
      context: _context,
      canRun: (item) => _commands.contains(item.command),
    );
    if (found is! KeybindingFound) return KeyEventResult.ignored;
    _run(notes, found.command);
    return KeyEventResult.handled;
  }

  void _run(List<StashNote> notes, String command) {
    final ids = [for (final note in notes) note.id];
    final at = ids.indexOf(_editing ?? -1);
    final current = at < 0 ? null : notes[at];
    void move(int to, {bool extend = false}) {
      to = to.clamp(0, ids.length - 1);
      if (extend) {
        _anchor ??= at < 0 ? ids[to] : ids[at];
        _selectRange(notes, ids[to]);
        // The row moved to is the one shown, the selection kept.
        widget.onPick(ids[to]);
      } else {
        _open(ids[to]);
      }
      ideRevealRow(_scroll, to, rowHeight: _rowHeight);
    }

    final page = math.max(
      1,
      ideRowsPerPage(_scroll, rowHeight: _rowHeight) - 1,
    );
    switch (command) {
      case 'list.focusDown':
        move(at < 0 ? 0 : at + 1);
      case 'list.focusUp':
        move(at < 0 ? 0 : at - 1);
      case 'list.focusPageDown':
        move(at + page);
      case 'list.focusPageUp':
        move(at - page);
      case 'list.focusFirst':
        move(0);
      case 'list.focusLast':
        move(ids.length - 1);
      case 'list.expandSelectionDown':
        move(at < 0 ? 0 : at + 1, extend: true);
      case 'list.expandSelectionUp':
        move(at < 0 ? 0 : at - 1, extend: true);
      case 'list.selectAll':
        setState(() => _selection = {...ids});
      case 'list.clear':
        setState(() => _selection = {?_editing});
      case 'list.select':
        widget.onEdit();
      case 'list.toggleExpand' || 'filesExplorer.openFilePreserveFocus':
        if (current != null) _open(current.id);
      case 'renameFile':
        if (current != null) _rename(current);
      case 'moveFileToTrash' || 'deleteFile':
        if (current != null) {
          unawaited(_delete(notes, _targets(notes, current)));
        }
      case 'filesExplorer.copy':
        if (current != null) unawaited(_copy(notes, _targets(notes, current)));
      case 'filesExplorer.paste':
        unawaited(_paste());
    }
  }

  // --- Renaming, copying, pasting -------------------------------------------------

  /// The stash whose title is being typed in its row.
  int? _renaming;
  final TextEditingController _renameText = TextEditingController();
  final FocusNode _renameFocus = FocusNode(debugLabel: 'stash rename');

  /// Its title typed in its row, as a file's name is: Enter keeps it,
  /// Escape (or nothing typed) leaves it as it was.
  void _rename(StashNote note) {
    _renameText
      ..text = _controller.store.headline(note)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.store.headline(note).length,
      );
    setState(() => _renaming = note.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renameFocus.requestFocus();
    });
  }

  void _renameFocusChanged() {
    // Clicked away: kept, as the explorer keeps a name typed.
    if (!_renameFocus.hasFocus && _renaming != null) _endRename(keep: true);
  }

  void _endRename({required bool keep}) {
    final id = _renaming;
    if (id == null) return;
    final title = _renameText.text.trim();
    setState(() => _renaming = null);
    widget.focusNode.requestFocus();
    final note = _controller.store.byId(id);
    if (!keep || note == null || title == _controller.store.headline(note)) {
      return;
    }
    unawaited(
      _controller.store.update(id, (note) => note.title = title, touch: false),
    );
  }

  /// [ids]' texts, one after another, their pictures and files by where
  /// they are: what a message or another app takes in.
  Future<void> _copy(List<StashNote> notes, List<int> ids) async {
    await widget.flush();
    final store = _controller.store;
    final text = [
      for (final id in ids)
        if (store.byId(id) case final note?) stashReferenceOf(store, note).text,
    ].where((text) => text.isNotEmpty).join('\n\n---\n\n');
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// The clipboard's text as a new stash, shown (as a file pasted in the
  /// explorer is made there).
  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    final note = await _controller.store.create(body: text);
    if (!mounted) return;
    await _controller.edit(note.id);
    if (mounted) _open(note.id);
  }

  // --- Changing them ------------------------------------------------------------

  Future<void> _delete(List<StashNote> notes, List<int> ids) async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: ids.length == 1
          ? l10n.stashDeleteOne('#${ids.single}')
          : l10n.stashDeleteMany(ids.length),
      detail: l10n.stashDeleteDetail,
      buttons: [l10n.stashDelete],
    );
    if (choice != 0 || !mounted) return;
    final editing = _controller.editing;
    // The one shown goes: the next one below it (else above) is shown.
    StashNote? next;
    if (editing != null && ids.contains(editing)) {
      final at = notes.indexWhere((note) => note.id == editing);
      next =
          notes.skip(at + 1).where((n) => !ids.contains(n.id)).firstOrNull ??
          notes
              .take(math.max(0, at))
              .where((n) => !ids.contains(n.id))
              .lastOrNull;
      if (next != null) await _controller.edit(next.id);
    }
    for (final id in ids) {
      await _controller.store.delete(id);
    }
    if (editing != null && ids.contains(editing) && next == null) {
      await _controller.startNew();
    }
    if (!mounted) return;
    setState(() {
      _selection = {?_controller.editing};
      _anchor = _controller.editing;
    });
  }

  Future<void> _merge(List<int> ids) async {
    final l10n = context.l10n;
    final sorted = [...ids]..sort();
    final choice = await showIdeDialog(
      context,
      message: l10n.stashMergeTitle(sorted.map((id) => '#$id').join(', ')),
      detail: l10n.stashMergeDetail('#${sorted.first}'),
      buttons: [l10n.stashMerge],
      type: IdeDialogType.question,
    );
    if (choice != 0 || !mounted) return;
    await widget.flush();
    final kept = await _controller.store.merge(sorted);
    if (kept == null || !mounted) return;
    if (ids.contains(_controller.editing)) await _controller.edit(kept.id);
    if (mounted) _open(kept.id);
  }

  Future<void> _each(
    List<int> ids,
    void Function(StashNote note) change,
  ) async {
    await widget.flush();
    for (final id in ids) {
      await _controller.store.update(id, change, touch: false);
    }
  }

  Future<void> _menu(
    List<StashNote> notes,
    StashNote note,
    Offset position,
  ) async {
    final l10n = context.l10n;
    final ids = _targets(notes, note);
    final several = ids.length > 1;
    await showIdeMenu(
      context,
      position: position,
      entries: [
        if (!several) ...[
          IdeMenuAction(l10n.stashOpen, onSelected: () => _open(note.id)),
          IdeMenuAction(
            l10n.commonRename,
            keybinding: _keys('renameFile'),
            onSelected: () => _rename(note),
          ),
          IdeMenuAction(
            note.pinned ? l10n.stashUnpin : l10n.stashPin,
            onSelected: () =>
                unawaited(_each(ids, (n) => n.pinned = !note.pinned)),
          ),
        ],
        IdeMenuAction(
          l10n.stashStatus,
          submenu: [
            for (final status in StashStatus.values)
              IdeMenuAction(
                stashStatusLabel(l10n, status),
                checked: !several && status == note.status,
                onSelected: () =>
                    unawaited(_each(ids, (n) => n.status = status)),
              ),
          ],
        ),
        IdeMenuAction(
          l10n.stashLinkProject,
          submenu: [
            IdeMenuAction(
              l10n.stashNoProject,
              checked: !several && note.project == null,
              onSelected: () => unawaited(_each(ids, (n) => n.project = null)),
            ),
            const IdeMenuSeparator(),
            for (final project in _controller.workspace.projects)
              IdeMenuAction(
                project.name,
                icon: stashProjectIcon(_controller.workspace, project),
                checked: !several && note.project == project.path,
                onSelected: () => unawaited(
                  _each(ids, (n) {
                    n.project = project.path;
                    n.suggestedProject = '';
                  }),
                ),
              ),
          ],
        ),
        if (several)
          IdeMenuAction(
            l10n.stashMerge,
            onSelected: () => unawaited(_merge(ids)),
          ),
        const IdeMenuSeparator(),
        if (!several && WindowControls.canRevealInFileManager)
          IdeMenuAction(
            l10n.stashReveal,
            onSelected: () => unawaited(
              WindowControls.revealInFileManager(
                p.join(_controller.store.root, '${note.id}.md'),
              ),
            ),
          ),
        IdeMenuAction(
          l10n.commonCopy,
          keybinding: _keys('filesExplorer.copy'),
          onSelected: () => unawaited(_copy(notes, ids)),
        ),
        IdeMenuAction(
          l10n.stashDelete,
          keybinding: _keys('moveFileToTrash'),
          onSelected: () => unawaited(_delete(notes, ids)),
        ),
      ],
    );
  }

  /// [command]'s keys here, for the menu to show.
  String? _keys(String command) =>
      KeybindingService.instance.labelFor(command, context: _context);

  /// How the list is ordered, a submenu of the filter's.
  IdeMenuAction _sortEntry(AppLocalizations l10n) => IdeMenuAction(
    l10n.stashSort,
    submenu: [
      for (final (sort, label) in [
        (StashSort.updated, l10n.stashSortUpdated),
        (StashSort.created, l10n.stashSortCreated),
        (StashSort.number, l10n.stashSortNumber),
        (StashSort.manual, l10n.stashSortManual),
      ])
        IdeMenuAction(
          label,
          checked: _controller.sort == sort,
          onSelected: () => _controller.sort = sort,
        ),
    ],
  );

  Future<void> _filter(Rect anchor) async {
    final l10n = context.l10n;
    final projects = _controller.workspace.projects;
    await showIdeMenu(
      context,
      anchor: anchor,
      entries: [
        _sortEntry(l10n),
        const IdeMenuSeparator(),
        for (final (shown, label) in [
          (_Shown.all, l10n.stashFilterAnyStatus),
          (_Shown.open, l10n.stashFilterOpen),
          (_Shown.done, l10n.stashStatusDone),
        ])
          IdeMenuAction(
            label,
            checked: _shown == shown,
            onSelected: () => setState(() => _shown = shown),
          ),
        const IdeMenuSeparator(),
        IdeMenuAction(
          l10n.stashFilterAnyProject,
          checked: _project == null,
          onSelected: () => setState(() => _project = null),
        ),
        IdeMenuAction(
          l10n.stashNoProject,
          checked: _project == '',
          onSelected: () => setState(() => _project = ''),
        ),
        for (final project in projects)
          IdeMenuAction(
            project.name,
            icon: stashProjectIcon(_controller.workspace, project),
            checked: _project == project.path,
            onSelected: () => setState(() => _project = project.path),
          ),
      ],
    );
  }

  // --- Dragging -----------------------------------------------------------------

  /// Where a drag at [global] would put what is dragged: before the row at
  /// the index (the count of them: after the last); the list scrolled
  /// while it is near its top or bottom.
  void _dragAt(Offset global, int count) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final local = box.globalToLocal(global);
    final y = local.dy + _scroll.offset - _listPadding.top;
    final at = (y / _rowHeight).round().clamp(0, count);
    if (at != _dropAt) setState(() => _dropAt = at);
    const edge = 24.0;
    final step = local.dy < edge
        ? -6.0
        : local.dy > box.size.height - edge
        ? 6.0
        : 0.0;
    _autoScroll?.cancel();
    _autoScroll = step == 0
        ? null
        : Timer.periodic(const Duration(milliseconds: 16), (_) {
            if (!_scroll.hasClients) return;
            final position = _scroll.position;
            _scroll.jumpTo(
              (_scroll.offset + step).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
          });
  }

  void _dragEnded() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (!mounted) return;
    setState(() {
      _dragging = null;
      _dropAt = null;
    });
  }

  /// [moving] put before the row at [at] of [notes]: the order of all of
  /// them from then on (the list sorted as dragged).
  Future<void> _drop(List<StashNote> notes, List<int> moving, int at) async {
    final before = notes
        .skip(at)
        .where((note) => !moving.contains(note.id))
        .firstOrNull;
    final after = notes
        .take(at)
        .where((note) => !moving.contains(note.id))
        .lastOrNull;
    if (before == null && after == null) return;
    final store = _controller.store;
    // As they show now, every one of them: what is not shown keeps its
    // place among the rest.
    final ids = [
      for (final note in store.sorted(store.notes, _controller.sort))
        if (!moving.contains(note.id)) note.id,
    ];
    final index = before != null
        ? ids.indexOf(before.id)
        : ids.indexOf(after!.id) + 1;
    ids.insertAll(index, moving);
    if (_controller.sort != StashSort.manual) {
      _controller.sort = StashSort.manual;
    }
    await store.reorder(ids);
  }

  // --- Building -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notes = _notes();
    final editing = _controller.editing;
    if (editing != _editing) {
      // Opened elsewhere (New, a link, the keyboard): it is the selection.
      _editing = editing;
      if (!_selection.contains(editing)) {
        _selection = {?editing};
        _anchor = editing;
      }
    }
    final filtered = _shown != _Shown.all || _project != null;
    Widget button(
      IconData icon,
      String tooltip,
      Future<void> Function(Rect anchor) onTap, {
      bool active = false,
    }) => Builder(
      builder: (context) => _PillButton(
        icon: icon,
        tooltip: tooltip,
        active: active,
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          unawaited(onTap(box.localToGlobal(Offset.zero) & box.size));
        },
      ),
    );
    return Container(
      decoration: BoxDecoration(
        // The chat's sidebar's.
        color: AppColors.sidebarSurface,
        border: Border(right: BorderSide(color: AppColors.partBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: _barHeight,
            padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: IdeInputBox(
                    controller: _query,
                    placeholder: l10n.stashSearchPlaceholder,
                    fontSize: 12.5,
                    semanticsLabel: l10n.stashSearchPlaceholder,
                  ),
                ),
                const SizedBox(width: 2),
                button(
                  Codicons.filter,
                  l10n.stashFilter,
                  _filter,
                  active: filtered,
                ),
              ],
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      l10n.stashNoMatch,
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  )
                : Focus(
                    focusNode: widget.focusNode,
                    onKeyEvent: (_, event) => _key(notes, event),
                    child: _list(notes),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<StashNote> notes) {
    final list = ListView.builder(
      key: _listKey,
      controller: _scroll,
      padding: _listPadding,
      itemExtent: _rowHeight,
      itemCount: notes.length,
      itemBuilder: (context, index) => _row(notes, notes[index]),
    );
    final dropAt = _dropAt;
    return DragTarget<_StashRows>(
      onWillAcceptWithDetails: (_) => true,
      onLeave: (_) => setState(() => _dropAt = null),
      onAcceptWithDetails: (details) {
        final at = _dropAt;
        _dragEnded();
        if (at != null) unawaited(_drop(notes, details.data.ids, at));
      },
      builder: (context, _, _) => Stack(
        children: [
          Positioned.fill(child: ScrollEdgeFade(child: list)),
          // Where they would go: a line between the rows.
          if (dropAt != null && _scroll.hasClients)
            Positioned(
              left: 8,
              right: 8,
              top: _listPadding.top + dropAt * _rowHeight - _scroll.offset - 1,
              height: 2,
              child: IgnorePointer(child: ColoredBox(color: AppColors.accent)),
            ),
        ],
      ),
    );
  }

  /// [icon] title, as the explorer's rows: its number over the title's end
  /// on hover; the title, number, time and project in its tooltip.
  Widget _row(List<StashNote> notes, StashNote note) {
    final l10n = context.l10n;
    final store = _controller.store;
    final focused = widget.focusNode.hasFocus;
    final selected = _selection.contains(note.id);
    final active = selected && focused;
    final done = note.status == StashStatus.done;
    final headline = store.headline(note);
    final title = note.isDraft
        ? l10n.stashDraft
        : headline.isEmpty
        ? l10n.stashNew
        : headline;
    final foreground = active
        ? IdeListColors.activeSelectionForeground
        : selected
        ? IdeListColors.inactiveSelectionForeground
        : AppColors.text;
    var known = _icons[note.id];
    if (known == null || known.$1 != note.body) {
      known = _icons[note.id] = (note.body, StashAttachmentIcon.of(note.body));
    }
    final icon = known.$2;
    final project = note.project;
    final tooltip = [
      title,
      [
        note.tag,
        _when(note.updated),
        if (project != null) p.basename(project),
      ].join(' · '),
    ].join('\n');
    final row = IdeListRow(
      height: _rowHeight,
      selected: selected,
      focusedItem: note.id == _editing,
      focused: focused,
      tooltip: _dragging == null ? tooltip : null,
      onTap: () => _click(notes, note),
      onDoubleTap: widget.onEdit,
      onContextMenu: (position) {
        widget.focusNode.requestFocus();
        unawaited(_menu(notes, note, position));
      },
      builder: (context, hovered) {
        final renaming = _renaming == note.id;
        // Its number over the end of the title on hover, on the row's own
        // color (made opaque), the title fading under it.
        final background = Color.alphaBlend(
          selected
              ? (focused
                    ? IdeListColors.activeSelection
                    : IdeListColors.inactiveSelection)
              : IdeListColors.hover,
          AppColors.background,
        );
        final number = Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: IgnorePointer(
            child: Row(
              children: [
                Container(
                  width: 16,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [background.withValues(alpha: 0), background],
                    ),
                  ),
                ),
                ColoredBox(
                  color: background,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, right: 6),
                    child: Center(
                      child: Text(
                        note.tag,
                        style: TextStyle(
                          color: active
                              ? foreground.withValues(alpha: 0.75)
                              : AppColors.textMuted,
                          // The title's size: on its baseline.
                          fontSize: 12.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        return Opacity(
          opacity: done || (_dragging?.contains(note.id) ?? false) ? 0.5 : 1,
          // The row's whole height, the title centered in it as the number.
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: Center(
                        child: icon == null
                            ? Icon(
                                Codicons.note,
                                size: 14,
                                color: active
                                    ? foreground
                                    : AppColors.textFaint,
                              )
                            : StashAttachmentIcon(
                                attachment: icon,
                                store: store,
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: renaming
                          ? IdeInputBox(
                              controller: _renameText,
                              focusNode: _renameFocus,
                              fontSize: 12.5,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              onSubmitted: (_) => _endRename(keep: true),
                              shortcuts: {
                                const SingleActivator(
                                  LogicalKeyboardKey.escape,
                                ): () =>
                                    _endRename(keep: false),
                              },
                            )
                          : Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: note.isDraft && !active
                                    ? AppColors.textMuted
                                    : foreground,
                                fontSize: 12.5,
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                    ),
                    if (note.pinned && !renaming)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Codicons.pinned,
                          size: 12,
                          color: active ? foreground : AppColors.textFaint,
                        ),
                      ),
                  ],
                ),
              ),
              if (hovered && !renaming && _dragging == null) number,
            ],
          ),
        );
      },
    );
    final moving = _targets(notes, note);
    return Draggable<_StashRows>(
      key: ValueKey(note.id),
      data: _StashRows(moving),
      maxSimultaneousDrags: _canReorder ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => setState(() => _dragging = moving),
      onDragUpdate: (details) => _dragAt(details.globalPosition, notes.length),
      onDragEnd: (_) => _dragEnded(),
      feedback: _DragFeedback(
        label: moving.length == 1
            ? '${note.tag}  $title'
            : l10n.stashCount(moving.length),
      ),
      child: row,
    );
  }

  /// `14:05` today, `10/3` this year, `2024/10/3` before.
  static String _when(DateTime time) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return '${two(time.hour)}:${two(time.minute)}';
    }
    if (time.year == now.year) return '${time.month}/${time.day}';
    return '${time.year}/${time.month}/${time.day}';
  }
}

/// Rows of the list of all, dragged to another place in it.
class _StashRows {
  const _StashRows(this.ids);

  final List<int> ids;
}

/// What follows the pointer while rows are dragged.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(12, 4),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: themeColors['list.activeSelectionBackground'],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.partBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: themeColors['list.activeSelectionForeground'],
          fontSize: 12,
          decoration: TextDecoration.none,
        ),
      ),
    ),
  );
}

/// A button of the panel's bars: with a [label], a capsule (an icon
/// before it, a faint outline round it); an icon alone, a circle.
class _PillButton extends StatelessWidget {
  const _PillButton({
    this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.faint = false,
    this.active = false,
  });

  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;
  final bool faint;
  final bool active;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: tooltip,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final label = this.label;
        final lit = active || hovered;
        final color = faint && !lit
            ? AppColors.textFaint
            : lit
            ? AppColors.text
            : AppColors.textMuted;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            height: 24,
            constraints: const BoxConstraints(minWidth: 24),
            padding: EdgeInsets.fromLTRB(
              label == null ? 0 : 8,
              0,
              label == null ? 0 : 10,
              0,
            ),
            decoration: BoxDecoration(
              color: lit ? AppColors.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: label == null
                  ? null
                  : Border.all(color: AppColors.partBorder),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon case final icon?) Icon(icon, size: 13, color: color),
                if (label != null) ...[
                  if (icon != null) const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Say Clearly in the bar, as in the Stash page's detail: the model it
/// asks picked by its arrow (one for every AI action, picked the first
/// time it is used); a click cancels while it goes on; where it failed,
/// why in its tooltip, and a click tries again.
class _ClarifyPill extends StatelessWidget {
  const _ClarifyPill({
    required this.clarifying,
    required this.failure,
    required this.onClarify,
    required this.onCancel,
    this.compact = false,
  });

  final bool clarifying;
  final StashClarifyFailure? failure;
  final Future<void> Function() onClarify;
  final VoidCallback onCancel;

  /// Its icon without its words, in a bar with no room for them.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = this.failure;
    final error = themeColors['errorForeground'];
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final color = failure != null
            ? error
            : hovered
            ? AppColors.text
            : AppColors.textMuted;
        final icon = Icon(
          clarifying
              ? Codicons.stop
              : failure == null
              ? Codicons.sparkle
              : Codicons.error,
          size: 13,
          color: color,
        );
        return Container(
          height: 24,
          decoration: BoxDecoration(
            color: hovered ? AppColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.partBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(
                builder: (context) => IdeHover(
                  message: clarifying
                      ? l10n.stashCancelClarify
                      : switch (failure) {
                          null => l10n.stashExpandHint,
                          (changed: true, message: _) =>
                            l10n.stashClarifyChanged,
                          (changed: false, :final message) =>
                            l10n.stashExpandFailed(
                              message ?? l10n.stashAiNoAnswer,
                            ),
                        },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: clarifying
                        ? onCancel
                        : () {
                            final anchor = anchorOf(context);
                            if (anchor == null) return;
                            unawaited(
                              withActionsModel(context, anchor, onClarify),
                            );
                          },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          if (!compact) ...[
                            const SizedBox(width: 5),
                            Text(
                              clarifying
                                  ? l10n.stashCancelClarify
                                  : failure != null
                                  ? l10n.stashClarifyFailedShort
                                  : l10n.stashExpand,
                              maxLines: 1,
                              style: TextStyle(color: color, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 12, color: AppColors.partBorder),
              Builder(
                builder: (context) => IdeHover(
                  message: l10n.aiModelTooltip(
                    actionsModelName(l10n, ModelProviders.current) ??
                        l10n.aiModelNone,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final anchor = anchorOf(context);
                      if (anchor == null) return;
                      unawaited(pickActionsModel(context, anchor));
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(3, 0, 6, 0),
                      child: Icon(
                        Codicons.chevronDown,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.status, required this.hints});

  /// "Saved", a moment after ⌘S.
  final String? status;
  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    final faint = TextStyle(color: AppColors.textFaint, fontSize: 11.5);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // Too narrow, the hints give way, the last first.
      child: GiveWayRow(
        children: [
          GiveWay.fill(
            Text(
              status ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: faint,
            ),
          ),
          for (final (key, label) in hints)
            GiveWay(
              priority: 0,
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key,
                      maxLines: 1,
                      style: faint.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 4),
                    Text(label, maxLines: 1, style: faint),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
