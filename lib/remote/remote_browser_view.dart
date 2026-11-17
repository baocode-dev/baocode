// The remote browser's window (see remote_browser.dart): a dialog as the
// app's others, over the window dimmed. Its places at the left; at the top
// the way back, forward and up, where it is as a path to click back along
// (or, clicked beside it, to type), and the filter; the entries; at the
// foot a new folder, what Open takes, Cancel and Open.

import 'dart:async';
import 'dart:math' as math;

import 'package:bao_remote/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../base/smooth_scroll.dart';
import '../ide/ide_button.dart';
import '../ide/ide_commands.dart' show ideUsesMacKeys;
import '../ide/ide_hover.dart';
import '../ide/ide_input.dart';
import '../ide/ide_menu.dart';
import '../ide/ide_motion.dart';
import '../ide/ide_spinning.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart' show AppColors;
import '../theme/codicons.dart';
import '../theme/finder_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/islands.dart';
import '../workspace/window_controls.dart';
import 'remote_browser.dart';
import 'remote_status.dart' show sshErrorText;

/// Shows the browser for [request]: the path picked, or null. [hostLabel]
/// is the host's name in the title; [locations], the folders it was in
/// there lately, told [onLocations] as it closes; [view], what it shows,
/// told [onView] as it changes.
Future<String?> showRemoteBrowser(
  BuildContext context,
  RemoteBrowseRequest request, {
  required String hostLabel,
  List<String> locations = const [],
  ValueChanged<List<String>>? onLocations,
  RemoteBrowserView view = const RemoteBrowserView(),
  ValueChanged<RemoteBrowserView>? onView,
}) => showGeneralDialog<String>(
  context: context,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: IdeMotion.livelyOf(context)
      ? IdeMotion.enterDuration
      : Duration.zero,
  transitionBuilder: IdeMotion.livelyOf(context)
      ? (context, animation, _, child) => IdeMotion.enter(animation, child)
      : null,
  pageBuilder: (context, _, _) => RemoteBrowserDialog(
    request: request,
    hostLabel: hostLabel,
    locations: locations,
    onLocations: onLocations,
    view: view,
    onView: onView,
  ),
);

class RemoteBrowserDialog extends StatefulWidget {
  const RemoteBrowserDialog({
    super.key,
    required this.request,
    required this.hostLabel,
    this.locations = const [],
    this.onLocations,
    this.view = const RemoteBrowserView(),
    this.onView,
  });

  final RemoteBrowseRequest request;
  final String hostLabel;

  /// The folders it was in there lately (see [RemoteBrowserModel.locations]),
  /// at the left; told [onLocations] as it closes, the one it was in and
  /// the one picked first.
  final List<String> locations;
  final ValueChanged<List<String>>? onLocations;
  final RemoteBrowserView view;
  final ValueChanged<RemoteBrowserView>? onView;

  /// The list of entries (or drives).
  static const entriesKey = ValueKey('remoteBrowserEntries');

  /// A row's height in the list.
  static const rowHeight = 28.0;

  @override
  State<RemoteBrowserDialog> createState() => _RemoteBrowserDialogState();
}

class _RemoteBrowserDialogState extends State<RemoteBrowserDialog> {
  late final RemoteBrowserModel _model = RemoteBrowserModel(
    widget.request,
    view: widget.view,
    locations: widget.locations,
  );
  final _filter = TextEditingController();
  final _filterFocus = FocusNode();
  final _scroll = SmoothScrollController();

  /// Typing a path in place of the crumbs, and why the last could not be
  /// gone to.
  TextEditingController? _path;
  String? _pathError;

  /// Naming a new folder at the top of the list, and why it was not made.
  TextEditingController? _newFolder;
  String? _newFolderError;

  /// The last row clicked, and when: a second click soon after on it is a
  /// double click (without the wait a double-tap recognizer puts on each).
  String? _lastClicked;
  DateTime _lastClickedAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    // After this frame: connecting tells the hosts' listeners (the status
    // bar's), which may not be marked while this one builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_model.connect());
    });
  }

  @override
  void dispose() {
    _model
      ..removeListener(_changed)
      ..dispose();
    _filter.dispose();
    _filterFocus.dispose();
    _scroll.dispose();
    _path?.dispose();
    _newFolder?.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // The filter cleared as it walked on.
    if (_filter.text != _model.filter) _filter.text = _model.filter;
    setState(() {});
  }

  void _close([String? path]) {
    // Where it was, then what was picked (a file's folder): the latest
    // locations.
    if (_model.directory case final directory?) _model.remember(directory);
    if (path != null) {
      _model.remember(widget.request.files ? _model.paths.dirname(path) : path);
    }
    widget.onLocations?.call(_model.locations);
    Navigator.of(context).pop(path);
  }

  void _accept() {
    final target = _model.target;
    if (target != null) _close(target);
  }

  /// A row opened (a double click, Enter in a file's browse, ⌘↓): a folder
  /// or a drive walked into, a file picked.
  void _activate(String key) {
    if (_model.directory == null) {
      unawaited(_model.open(key));
      return;
    }
    final entry = _model.entries.where((e) => e.name == key).firstOrNull;
    if (entry == null) return;
    if (entry.isDirectory) {
      unawaited(_model.open(_model.pathOf(key)));
    } else if (widget.request.files) {
      _close(_model.pathOf(key));
    }
  }

  /// Enter: Open, but in a file's browse a folder selected is walked into.
  void _submit() {
    final entry = _model.selectedEntry;
    if (widget.request.files &&
        (_model.directory == null && _model.selected != null ||
            entry != null && entry.isDirectory)) {
      _activate(_model.selected!);
      return;
    }
    _accept();
  }

  void _clicked(String key) {
    final now = DateTime.now();
    final double =
        _lastClicked == key &&
        now.difference(_lastClickedAt) < const Duration(milliseconds: 450);
    _lastClicked = double ? null : key;
    _lastClickedAt = now;
    _model.select(key);
    _filterFocus.requestFocus();
    if (double) _activate(key);
  }

  void _move(int by) {
    _model.moveSelection(by);
    _reveal();
  }

  /// Scrolls the row selected into view.
  void _reveal() {
    final index = _model.selectedIndex;
    if (index < 0 || !_scroll.hasClients) return;
    final extra = _newFolder == null ? 0.0 : RemoteBrowserDialog.rowHeight;
    final top =
        index * RemoteBrowserDialog.rowHeight + extra + Islands.listInset;
    final bottom = top + RemoteBrowserDialog.rowHeight;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _editPath() {
    if (_model.phase != RemoteBrowserPhase.ready) return;
    setState(() {
      _path = TextEditingController(text: _model.directory ?? '')
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: (_model.directory ?? '').length,
        );
      _pathError = null;
    });
  }

  void _stopEditingPath() {
    final path = _path;
    if (path == null) return;
    setState(() {
      _path = null;
      _pathError = null;
    });
    // Disposed once the field holding it is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => path.dispose());
    _filterFocus.requestFocus();
  }

  Future<void> _goToTyped(String text) async {
    if (text.trim().isEmpty) return _stopEditingPath();
    final missing = await _model.goTo(text);
    if (!mounted) return;
    if (missing != null) {
      setState(() => _pathError = context.l10n.remoteBrowserNotFound(missing));
      return;
    }
    _stopEditingPath();
    // A file typed in a file's browse: taken.
    final entry = _model.selectedEntry;
    if (widget.request.files && entry != null && !entry.isDirectory) {
      _close(_model.pathOf(entry.name));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  bool get _canMakeFolder => _model.directory != null && _newFolder == null;

  void _startNewFolder() {
    if (_model.directory == null) return;
    final name = _model.freeName(context.l10n.remoteBrowserNewFolder);
    setState(() {
      _newFolder = TextEditingController(text: name)
        ..selection = TextSelection(baseOffset: 0, extentOffset: name.length);
      _newFolderError = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _stopNewFolder() {
    final controller = _newFolder;
    if (controller == null) return;
    setState(() {
      _newFolder = null;
      _newFolderError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    _filterFocus.requestFocus();
  }

  Future<void> _makeFolder(String name) async {
    name = name.trim();
    if (name.isEmpty) return _stopNewFolder();
    try {
      await _model.makeFolder(name);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _newFolderError = context.l10n.remoteBrowserMakeFailed('$error'),
      );
      return;
    }
    if (!mounted) return;
    _stopNewFolder();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _escape() {
    if (_newFolder != null) return _stopNewFolder();
    if (_path != null) return _stopEditingPath();
    if (_model.filter.isNotEmpty) {
      _model.filter = '';
      return;
    }
    _close();
  }

  Future<void> _showViewMenu(Rect anchor) => showIdeMenu(
    context,
    anchor: anchor,
    alignRight: true,
    entries: [
      IdeMenuAction(
        context.l10n.remoteBrowserShowHidden,
        checked: _model.view.hidden,
        onSelected: () =>
            _setView(_model.view.copyWith(hidden: !_model.view.hidden)),
      ),
      if (_model.isWindows)
        IdeMenuAction(
          context.l10n.remoteBrowserShowSystem,
          checked: _model.view.system,
          enabled: _model.view.hidden,
          onSelected: () =>
              _setView(_model.view.copyWith(system: !_model.view.system)),
        ),
    ],
  );

  void _setView(RemoteBrowserView view) {
    _model.view = view;
    widget.onView?.call(view);
  }

  Future<void> _runFailureAction(RemoteBrowseAction action) async {
    if (action.closes) {
      _close();
      await action.run();
      return;
    }
    if (await action.run() && mounted) await _model.connect();
  }

  bool get _apple => ideUsesMacKeys;

  /// The keys the filter takes before its text does: the rows moved
  /// through, walked into and up from, back and forward.
  Map<ShortcutActivator, VoidCallback> get _keys => {
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
    const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(10),
    const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(-10),
    SingleActivator(
      LogicalKeyboardKey.arrowDown,
      meta: _apple,
      alt: !_apple,
    ): () {
      if (_model.selected case final key?) _activate(key);
    },
    SingleActivator(
      LogicalKeyboardKey.arrowUp,
      meta: _apple,
      alt: !_apple,
    ): () =>
        unawaited(_model.up()),
    SingleActivator(
      LogicalKeyboardKey.bracketLeft,
      meta: _apple,
      control: !_apple,
    ): () =>
        unawaited(_model.back()),
    SingleActivator(
      LogicalKeyboardKey.bracketRight,
      meta: _apple,
      control: !_apple,
    ): () =>
        unawaited(_model.forward()),
    SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      alt: !_apple,
      meta: _apple,
    ): () =>
        unawaited(_model.back()),
    SingleActivator(
      LogicalKeyboardKey.arrowRight,
      alt: !_apple,
      meta: _apple,
    ): () =>
        unawaited(_model.forward()),
    // Finder's Go to Folder, and a browser's address bar.
    SingleActivator(
      LogicalKeyboardKey.keyG,
      meta: _apple,
      control: !_apple,
      shift: true,
    ): _editPath,
    SingleActivator(LogicalKeyboardKey.keyL, meta: _apple, control: !_apple):
        _editPath,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shadow = themeColors.get('widget.shadow');
    final size = MediaQuery.sizeOf(context);
    final width = math.min(880.0, size.width - 48);
    final height = math.min(
      580.0,
      size.height - math.max(48, (WindowControls.headerInset + 8) / .3),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        ..._keys,
      },
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.3),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: widget.request.files
                ? l10n.remoteBrowserFileTitle(widget.hostLabel)
                : l10n.remoteBrowserFolderTitle(widget.hostLabel),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: width,
                height: math.max(320, height),
                clipBehavior: Clip.antiAlias,
                // The window's color, the entries on a card of the editor's,
                // apart by a gap rather than a line: an island's, its
                // corners round the card's at the gap.
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: Islands.border),
                  borderRadius: BorderRadius.circular(
                    Islands.radius + Islands.gap,
                  ),
                  boxShadow: [
                    const BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                    if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
                  ],
                ),
                // The sidebar the window's height, as a Mac's open panel's;
                // the toolbar, the card and the foot beside it, their edges
                // in line.
                child: Padding(
                  padding: const EdgeInsets.only(right: Islands.gap),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sidebar(l10n),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _toolbar(l10n),
                            Expanded(
                              child: _card(switch (_model.phase) {
                                RemoteBrowserPhase.connecting => _Status(
                                  icon: const IdeSpinning(
                                    Icon(Codicons.loading, size: 20),
                                  ),
                                  message: l10n.remoteConnecting(
                                    widget.hostLabel,
                                  ),
                                ),
                                RemoteBrowserPhase.failed => _failure(l10n),
                                RemoteBrowserPhase.ready => _list(l10n),
                              }),
                            ),
                            _footer(l10n),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [child] on the card, of the editor's color.
  Widget _card(Widget child) => Island(color: AppColors.code, child: child);

  Widget _failure(AppLocalizations l10n) {
    final (message, detail) = sshErrorText(_model.connectError, l10n);
    return _Status(
      icon: Icon(
        Codicons.error,
        size: 20,
        color: themeColors['errorForeground'],
      ),
      message: message ?? l10n.remoteConnectFailed(widget.hostLabel),
      detail: detail?.split('\n').last,
      actions: [
        if (!_model.failureActions.any((action) => !action.closes))
          IdeButton(
            label: l10n.remoteRetry,
            icon: Codicons.refresh,
            radius: Islands.controlRadius,
            padding: _buttonPadding,
            onPressed: () => unawaited(_model.connect()),
          ),
        for (final action in _model.failureActions)
          IdeButton(
            label: action.label,
            icon: action.icon,
            secondary: true,
            radius: Islands.controlRadius,
            padding: _buttonPadding,
            onPressed: () => unawaited(_runFailureAction(action)),
          ),
      ],
    );
  }

  /// Home, the drives, and the folders it was in there lately.
  Widget _sidebar(AppLocalizations l10n) {
    final directory = _model.directory;
    final roots = _model.roots;
    final home = _model.home;
    final ready = _model.phase == RemoteBrowserPhase.ready;
    // Not again what is a place already: home, a drive.
    final places = {home, for (final root in roots) root.path};
    final recent = _model.locations
        .where((path) => !places.contains(path))
        .take(10)
        .toList();
    // On the window's color, as the agents' window's sidebar; what it is
    // for at its top, beside the toolbar, in place of a title bar.
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            host: widget.hostLabel,
            action: widget.request.files
                ? l10n.remoteBrowserFileAction
                : l10n.remoteBrowserFolderAction,
            height: _toolbarHeight,
          ),
          if (ready)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                children: [
                  _SectionLabel(l10n.remoteBrowserPlaces),
                  if (home.isNotEmpty)
                    _Place(
                      icon: const FinderFolderIcon(size: 18, home: true),
                      label: l10n.remoteBrowserHome,
                      tooltip: home,
                      selected: directory == home,
                      onTap: () => unawaited(_model.open(home)),
                    ),
                  if (_model.isWindows)
                    _Place(
                      icon: const FinderComputerIcon(size: 18),
                      label: l10n.remoteBrowserThisPc,
                      selected: directory == null,
                      onTap: () => unawaited(_model.open(null)),
                    ),
                  for (final root in roots)
                    _Place(
                      icon: FinderDiskIcon(size: 18, kind: root.kind),
                      label: _rootLabel(root, l10n).name,
                      suffix: _rootLabel(root, l10n).suffix,
                      selected: directory == root.path,
                      onTap: () => unawaited(_model.open(root.path)),
                    ),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _SectionLabel(l10n.remoteBrowserRecent),
                    for (final path in recent)
                      _Place(
                        icon: const FinderFolderIcon(size: 18),
                        label: _model.paths.basename(path).isEmpty
                            ? path
                            : _model.paths.basename(path),
                        tooltip: path,
                        selected: directory == path,
                        onTap: () => unawaited(_model.goTo(path)),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Back, forward, up; where it is; refresh, the view, the filter. No
  /// close: Cancel at the foot, and Esc.
  Widget _toolbar(AppLocalizations l10n) {
    // About the card, so over it on the window's color.
    return Container(
      height: _toolbarHeight,
      padding: const EdgeInsets.only(top: 8, bottom: Islands.gap),
      child: Row(
        children: _model.phase != RemoteBrowserPhase.ready
            ? const []
            : [
                IdeActionButton(
                  icon: Codicons.arrowLeft,
                  tooltip: l10n.remoteBrowserBack,
                  onPressed: _model.canGoBack
                      ? () => unawaited(_model.back())
                      : null,
                ),
                IdeActionButton(
                  icon: Codicons.arrowRight,
                  tooltip: l10n.remoteBrowserForward,
                  onPressed: _model.canGoForward
                      ? () => unawaited(_model.forward())
                      : null,
                ),
                IdeActionButton(
                  icon: Codicons.arrowUp,
                  tooltip: l10n.remoteParentFolder,
                  onPressed: _model.canGoUp
                      ? () => unawaited(_model.up())
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _path == null ? _crumbs(l10n) : _pathField(l10n),
                ),
                const SizedBox(width: 6),
                IdeActionButton(
                  icon: Codicons.refresh,
                  tooltip: l10n.remoteBrowserRefresh,
                  onPressed: () => unawaited(_model.refresh()),
                ),
                Builder(
                  builder: (context) => IdeActionButton(
                    icon: _model.view.hidden
                        ? Codicons.eye
                        : Codicons.eyeClosed,
                    tooltip: l10n.remoteBrowserView,
                    onPressed: () {
                      final box = context.findRenderObject();
                      if (box is! RenderBox) return;
                      unawaited(
                        _showViewMenu(
                          box.localToGlobal(Offset.zero) & box.size,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 170,
                  child: IdeInputBox(
                    controller: _filter,
                    focusNode: _filterFocus,
                    autofocus: true,
                    placeholder: l10n.remoteBrowserFilter,
                    semanticsLabel: l10n.remoteBrowserFilter,
                    radius: Islands.controlRadius,
                    padding: _controlPadding,
                    onChanged: (value) {
                      _model.filter = value;
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                    },
                    onSubmitted: (_) {
                      _submit();
                      _filterFocus.requestFocus();
                    },
                    shortcuts: _keys,
                  ),
                ),
              ],
      ),
    );
  }

  /// Where it is, a crumb a level: clicked, gone back to; clicked beside,
  /// typed instead.
  Widget _crumbs(AppLocalizations l10n) {
    final directory = _model.directory;
    final paths = _model.paths;
    final crumbs = <(String label, String? path, Widget? icon)>[];
    if (_model.isWindows) {
      crumbs.add((
        l10n.remoteBrowserThisPc,
        null,
        const FinderComputerIcon(size: 16),
      ));
    }
    if (directory != null) {
      final root = paths.rootPrefix(directory);
      var at = root;
      crumbs.add((
        _model.isWindows ? root.replaceAll(RegExp(r'[\\/]$'), '') : root,
        root,
        _model.isWindows ? null : const FinderDiskIcon(size: 16),
      ));
      for (final part in paths.split(directory).skip(1)) {
        at = paths.join(at, part);
        crumbs.add((part, at, null));
      }
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editPath,
        child: Container(
          height: Islands.controlHeight,
          decoration: BoxDecoration(
            color: IdeInputColors.background,
            border: Border.all(color: IdeInputColors.border),
            borderRadius: BorderRadius.circular(Islands.controlRadius),
          ),
          // Scrolled to its end when long, at its start when short.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.max(0, constraints.maxWidth - 8),
                ),
                child: Row(
                  children: [
                    for (final (i, (label, path, icon)) in crumbs.indexed) ...[
                      if (i > 0)
                        Icon(
                          Codicons.chevronRight,
                          size: 14,
                          color: themeColors['descriptionForeground'],
                        ),
                      _Crumb(
                        label: label,
                        icon: icon,
                        current: i == crumbs.length - 1,
                        onTap: () => unawaited(_model.open(path)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pathField(AppLocalizations l10n) => Focus(
    onFocusChange: (focused) {
      if (!focused && _pathError == null) _stopEditingPath();
    },
    child: IdeInputBox(
      controller: _path!,
      autofocus: true,
      placeholder: l10n.remoteBrowserPathPlaceholder,
      semanticsLabel: l10n.remoteBrowserEditPath,
      radius: Islands.controlRadius,
      padding: _controlPadding,
      validation: _pathError == null ? null : IdeInputValidation(_pathError!),
      floatingValidation: true,
      onChanged: (_) {
        if (_pathError != null) setState(() => _pathError = null);
      },
      onSubmitted: (text) => unawaited(_goToTyped(text)),
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): _stopEditingPath,
      },
    ),
  );

  Widget _list(AppLocalizations l10n) {
    final directory = _model.directory;
    if (_model.readError case final error?) {
      return _Status(
        icon: Icon(
          Codicons.error,
          size: 20,
          color: themeColors['errorForeground'],
        ),
        message: l10n.remoteListFailed(directory ?? ''),
        detail: '$error',
        actions: [
          IdeButton(
            label: l10n.remoteRetry,
            icon: Codicons.refresh,
            secondary: true,
            onPressed: () => unawaited(_model.refresh()),
          ),
        ],
      );
    }
    if (_model.readingShown) {
      return _Status(
        icon: const IdeSpinning(Icon(Codicons.loading, size: 20)),
        message: l10n.remoteReadingFolder(directory ?? ''),
      );
    }
    final rows = <Widget>[];
    if (_newFolder case final controller?) {
      rows.add(
        _NewFolderRow(
          controller: controller,
          error: _newFolderError,
          onSubmitted: (name) => unawaited(_makeFolder(name)),
          onCancel: _stopNewFolder,
          onChanged: () {
            if (_newFolderError != null) setState(() => _newFolderError = null);
          },
        ),
      );
    }
    if (directory == null) {
      for (final root in _model.visibleRoots) {
        rows.add(
          _EntryRow(
            icon: FinderDiskIcon(size: 18, kind: root.kind),
            name: switch (_rootLabel(root, l10n)) {
              (:final name, suffix: final suffix?) => '$name $suffix',
              (:final name, suffix: null) => name,
            },
            selected: _model.selected == root.path,
            onTap: () => _clicked(root.path),
          ),
        );
      }
    } else {
      for (final entry in _model.visible) {
        rows.add(
          _EntryRow(
            icon: entry.isDirectory
                ? const FinderFolderIcon(size: 18)
                : FinderFileIcon(entry.name, size: 18),
            name: entry.name,
            dimmed: entry.hidden,
            selected: _model.selected == entry.name,
            onTap: () => _clicked(entry.name),
          ),
        );
      }
    }
    if (rows.isEmpty && !_model.reading) {
      final hidden = directory == null ? 0 : _model.hiddenCount;
      return _Status(
        message: _model.filter.isNotEmpty
            ? l10n.remoteBrowserNoMatch(_model.filter)
            : hidden > 0
            ? l10n.remoteBrowserHiddenCount(hidden)
            : widget.request.files
            ? l10n.remoteBrowserEmpty
            : l10n.remoteBrowserNoFolders,
        actions: [
          if (_model.filter.isEmpty && hidden > 0)
            IdeButton(
              label: l10n.remoteBrowserShowHiddenNow,
              secondary: true,
              onPressed: () =>
                  _setView(_model.view.copyWith(hidden: true, system: true)),
            ),
        ],
      );
    }
    return GestureDetector(
      // A click below the rows: none selected, as Finder's.
      behavior: HitTestBehavior.translucent,
      onTap: () => _model.select(null),
      child: ListView.builder(
        key: RemoteBrowserDialog.entriesKey,
        controller: _scroll,
        padding: const EdgeInsets.all(Islands.listInset),
        itemExtent: RemoteBrowserDialog.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[index],
      ),
    );
  }

  /// A new folder, what Open takes, Cancel and Open.
  Widget _footer(AppLocalizations l10n) {
    final colors = themeColors;
    final ready = _model.phase == RemoteBrowserPhase.ready;
    final target = _model.target;
    // Under the card, on the window's color, its edges the card's.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Islands.gap + 2),
      child: Row(
        children: [
          if (!widget.request.files && ready) ...[
            IdeButton(
              label: l10n.remoteBrowserNewFolder,
              leading: Opacity(
                opacity: _canMakeFolder ? 1 : 0.5,
                child: const FinderFolderIcon(add: true),
              ),
              secondary: true,
              radius: Islands.controlRadius,
              padding: _buttonPadding,
              onPressed: _canMakeFolder ? _startNewFolder : null,
            ),
            const SizedBox(width: 14),
          ],
          // What Open takes, by its icon as in the list.
          if (target != null) ...[
            if (widget.request.files)
              FinderFileIcon(target, size: 16)
            else
              const FinderFolderIcon(size: 16),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: _FitText(
              target ?? '',
              middle: true,
              style: TextStyle(
                fontSize: 12,
                color: colors['descriptionForeground'],
              ),
            ),
          ),
          const SizedBox(width: 12),
          IdeButton(
            label: l10n.commonCancel,
            secondary: true,
            radius: Islands.controlRadius,
            padding: _buttonPadding,
            onPressed: _close,
          ),
          const SizedBox(width: 8),
          IdeButton(
            label: l10n.remoteBrowserOpen,
            radius: Islands.controlRadius,
            padding: _buttonPadding,
            onPressed: target == null ? null : _accept,
          ),
        ],
      ),
    );
  }
}

/// The toolbar's height, and the sidebar's heading's beside it.
const _toolbarHeight = 8 + Islands.controlHeight + Islands.gap;

/// An input's padding inside, for [Islands.controlHeight]: its 18 px line
/// and border in 30.
const _controlPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 5);

/// A button's, as high: 16 px of label in 30.
const _buttonPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 7);

/// A drive as Explorer names it (`Windows (C:)`, `Local Disk (D:)`); the
/// root elsewhere, and a Mac's volumes by their names. Its letter apart
/// ([suffix]), kept when a long name is cut.
({String name, String? suffix}) _rootLabel(
  BrowseRoot root,
  AppLocalizations l10n,
) {
  final path = root.path;
  final drive = RegExp(r'^([A-Za-z]:)[\\/]?$').firstMatch(path)?[1];
  if (drive == null) {
    if (root.label.isNotEmpty) return (name: root.label, suffix: null);
    return path == '/'
        ? (name: l10n.remoteBrowserRoot, suffix: '(/)')
        : (name: path, suffix: null);
  }
  if (root.label.isNotEmpty) return (name: root.label, suffix: '($drive)');
  return (
    name: root.kind == BrowseRootKind.fixed
        ? l10n.remoteBrowserLocalDisk(drive)
        : drive,
    suffix: null,
  );
}

/// [text] on one line, cut to fit: at its end (a [suffix] after it kept
/// whole), or in its middle when [middle] (a path's start and its last
/// folders kept). Cut, the whole of it on hover; [hover] instead, if
/// given, whether cut or not.
class _FitText extends StatelessWidget {
  const _FitText(
    this.text, {
    required this.style,
    this.suffix,
    this.middle = false,
    this.hover,
  });

  final String text;
  final String? suffix;
  final TextStyle style;
  final bool middle;
  final String? hover;

  String get _whole => suffix == null ? text : '$text $suffix';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final style = DefaultTextStyle.of(context).style.merge(this.style);
      bool fits(String value) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: direction,
          textScaler: scale,
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width <= constraints.maxWidth;
      }

      final cut = constraints.hasBoundedWidth && !fits(_whole);
      Widget child;
      if (!cut) {
        child = Text(_whole, maxLines: 1, style: this.style);
      } else if (middle) {
        child = Text(
          _middleCut(fits),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: this.style,
        );
      } else {
        child = Row(
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: this.style,
              ),
            ),
            if (suffix case final suffix?)
              Text(' $suffix', maxLines: 1, style: this.style),
          ],
        );
      }
      final tip = hover ?? (cut ? _whole : null);
      return tip == null ? child : IdeHover(message: tip, child: child);
    },
  );

  /// The most of [text] that [fits], its middle given up for `…`: two
  /// fifths of what is kept from its start, the rest from its end.
  String _middleCut(bool Function(String) fits) {
    String kept(int count) {
      final head = (count * 2 / 5).floor();
      return '${text.substring(0, head)}…'
          '${text.substring(text.length - (count - head))}';
    }

    var low = 0, high = text.length - 1;
    while (low < high) {
      final count = (low + high + 1) ~/ 2;
      if (fits(kept(count))) {
        low = count;
      } else {
        high = count - 1;
      }
    }
    return kept(low);
  }
}

/// What the browser is for, atop its sidebar: the host, and Open Folder
/// or Open File under it.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.host,
    required this.action,
    required this.height,
  });

  final String host;
  final String action;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.fromLTRB(18, 8, 8, Islands.gap),
    alignment: Alignment.centerLeft,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FitText(
          host,
          style: TextStyle(
            fontSize: 13,
            height: 16 / 13,
            fontWeight: FontWeight.w600,
            color: themeColors['editorWidget.foreground'],
          ),
        ),
        Text(
          action,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 14 / 11,
            color: themeColors['descriptionForeground'],
          ),
        ),
      ],
    ),
  );
}

/// Something said in the middle (connecting, why not, nothing here), with
/// what may be done about it.
class _Status extends StatelessWidget {
  const _Status({
    required this.message,
    this.icon,
    this.detail,
    this.actions = const [],
  });

  final Widget? icon;
  final String message;
  final String? detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[icon, const SizedBox(height: 10)],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: themeColors['editorWidget.foreground'],
            ),
          ),
          if (detail case final detail?) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SelectableText(
                detail,
                textAlign: TextAlign.center,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 12,
                  color: themeColors['descriptionForeground'],
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: themeColors['descriptionForeground'],
      ),
    ),
  );
}

/// A place at the left: home, a drive, a folder opened lately.
class _Place extends StatefulWidget {
  const _Place({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.suffix,
    this.tooltip,
  });

  final Widget icon;
  final String label;

  /// After [label], kept when it is cut: a drive's letter.
  final String? suffix;

  /// On hover (a place's path); the whole label when cut, if not given.
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Place> createState() => _PlaceState();
}

class _PlaceState extends State<_Place> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Islands.segmentFill(
              selected: widget.selected,
              hovered: _hover,
            ),
            borderRadius: BorderRadius.circular(Islands.rowRadius),
          ),
          child: Row(
            children: [
              widget.icon,
              const SizedBox(width: 8),
              Expanded(
                child: _FitText(
                  widget.label,
                  suffix: widget.suffix,
                  hover: widget.tooltip,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors['sideBar.foreground'],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: row,
    );
  }
}

/// A level of where it is, in the path bar.
class _Crumb extends StatefulWidget {
  const _Crumb({
    required this.label,
    required this.current,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Widget? icon;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: _hover ? colors.get('toolbar.hoverBackground') : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon case final icon?) ...[
                  icon,
                  const SizedBox(width: 5),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.current ? FontWeight.w600 : null,
                    color: widget.current
                        ? IdeInputColors.foreground
                        : colors['descriptionForeground'],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A folder, a file or a drive in the list.
class _EntryRow extends StatefulWidget {
  const _EntryRow({
    required this.icon,
    required this.name,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
  });

  final Widget icon;
  final String name;
  final bool selected;

  /// A hidden one, shown as asked: faded, as Finder has them.
  final bool dimmed;
  final VoidCallback onTap;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.name,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? colors.get('list.activeSelectionBackground')
                  : _hover
                  ? colors.get('list.hoverBackground')
                  : null,
              borderRadius: BorderRadius.circular(Islands.rowRadius),
            ),
            child: Opacity(
              opacity: widget.dimmed ? 0.55 : 1,
              child: Row(
                children: [
                  widget.icon,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? colors.get('list.activeSelectionForeground') ??
                                  colors['foreground']
                            : colors['foreground'],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The new folder's name being typed, at the top of the list.
class _NewFolderRow extends StatelessWidget {
  const _NewFolderRow({
    required this.controller,
    required this.onSubmitted,
    required this.onCancel,
    required this.onChanged,
    this.error,
  });

  final TextEditingController controller;
  final String? error;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        const FinderFolderIcon(size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: IdeInputBox(
            controller: controller,
            autofocus: true,
            fontSize: 13,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            semanticsLabel: context.l10n.remoteBrowserNewFolder,
            validation: error == null ? null : IdeInputValidation(error!),
            floatingValidation: true,
            onChanged: (_) => onChanged(),
            onSubmitted: onSubmitted,
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.escape): onCancel,
            },
          ),
        ),
      ],
    ),
  );
}
