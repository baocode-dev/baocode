import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../theme/codicons.dart';
import '../theme/cursor_theme.dart';
import '../theme/material_file_icons.dart';
import 'file_service.dart';
import 'ide_hover.dart';

/// One visible row of the explorer tree.
@immutable
class IdeExplorerRow {
  const IdeExplorerRow({
    required this.path,
    required this.name,
    required this.depth,
    required this.isDirectory,
    this.expanded = false,
    this.message,
  });

  final String path;
  final String name;
  final int depth;
  final bool isDirectory;
  final bool expanded;

  /// A non-selectable note under a folder (e.g. a read error) instead of an
  /// entry.
  final String? message;
}

/// The explorer's tree state, kept by the workbench so the expansion survives
/// switching side views and other parts (tabs, breadcrumbs) can reveal paths.
///
/// Entry paths are joined onto [root] from their names, so they match the
/// workspace's document paths even when [root] contains symlinks.
class IdeExplorerController extends ChangeNotifier {
  IdeExplorerController({required this.files, required String root})
    : root = p.normalize(root) {
    unawaited(_load(this.root));
  }

  final IdeFileService files;
  final String root;
  final Map<String, List<IdeFile>> _children = {};
  final Map<String, Object> _errors = {};
  final Set<String> _expanded = {};
  final Map<String, Future<void>> _loads = {};
  List<IdeExplorerRow>? _rows;
  String? _selected;
  int _revealRequest = 0;
  bool _disposed = false;

  /// The selected row's path, if any.
  String? get selected => _selected;

  /// Increments whenever the selection should be scrolled into view.
  int get revealRequest => _revealRequest;

  bool isExpanded(String path) => _expanded.contains(path);

  /// Rows in display order: expanded folders followed by their children.
  List<IdeExplorerRow> get rows => _rows ??= _buildRows();

  List<IdeExplorerRow> _buildRows() {
    final rows = <IdeExplorerRow>[];
    void add(String directory, int depth) {
      if (_errors[directory] case final error?) {
        rows.add(
          IdeExplorerRow(
            path: '$directory${p.separator}',
            name: '',
            depth: depth,
            isDirectory: false,
            message: 'Cannot read folder: $error',
          ),
        );
        return;
      }
      for (final entry in _children[directory] ?? const <IdeFile>[]) {
        final path = p.join(directory, entry.name);
        final expanded = entry.isDirectory && _expanded.contains(path);
        rows.add(
          IdeExplorerRow(
            path: path,
            name: entry.name,
            depth: depth,
            isDirectory: entry.isDirectory,
            expanded: expanded,
          ),
        );
        if (expanded) add(path, depth + 1);
      }
    }

    add(root, 0);
    return rows;
  }

  void _changed() {
    if (_disposed) return;
    _rows = null;
    notifyListeners();
  }

  Future<void> _load(String directory, {bool force = false}) {
    if (!force && _children.containsKey(directory)) return Future.value();
    return _loads[directory] ??= () async {
      try {
        final entries = await files.list(directory);
        _children[directory] = entries;
        _errors.remove(directory);
      } catch (error) {
        _errors[directory] = error;
      } finally {
        _loads.remove(directory);
        _changed();
      }
    }();
  }

  Future<void> expand(String directory) async {
    if (_expanded.add(directory)) _changed();
    await _load(directory);
  }

  void collapse(String directory) {
    if (_expanded.remove(directory)) _changed();
  }

  Future<void> toggle(String directory) => _expanded.contains(directory)
      ? Future.sync(() => collapse(directory))
      : expand(directory);

  /// Collapses every folder.
  void collapseAll() {
    if (_expanded.isEmpty) return;
    _expanded.clear();
    if (_selected case final selected?
        when !rows.any((r) => r.path == selected)) {
      _selected = null;
    }
    _changed();
  }

  void select(String? path, {bool reveal = false}) {
    if (_selected == path && !reveal) return;
    _selected = path;
    if (reveal) _revealRequest++;
    _changed();
  }

  /// Expands the folders above [path], then selects and scrolls to it.
  Future<void> reveal(String path) async {
    final target = p.normalize(path);
    if (target == root || !p.isWithin(root, target)) return;
    final parts = p.split(p.relative(target, from: root));
    var directory = root;
    await _load(directory);
    for (final part in parts.take(parts.length - 1)) {
      directory = p.join(directory, part);
      if (_expanded.add(directory)) _changed();
      await _load(directory);
      if (_disposed) return;
    }
    select(target, reveal: true);
  }

  /// Re-reads the root and every expanded folder, keeping the expansion.
  Future<void> refresh() async {
    final directories = [root, ..._expanded];
    await Future.wait([
      for (final directory in directories) _load(directory, force: true),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The file tree: chevrons, file icons, indent guides, selection that follows
/// the active editor, and keyboard navigation while focused.
class IdeExplorer extends StatefulWidget {
  const IdeExplorer({
    super.key,
    required this.controller,
    required this.title,
    required this.onOpen,
    this.focusNode,
  });

  final IdeExplorerController controller;

  /// The project name, shown as the tree's section header.
  final String title;

  /// Opens a file; [focusEditor] when opened from the keyboard.
  final void Function(String path, bool focusEditor) onOpen;
  final FocusNode? focusNode;

  static const rowHeight = 22.0;
  static const indent = 12.0;

  @override
  State<IdeExplorer> createState() => _IdeExplorerState();
}

class _IdeExplorerState extends State<IdeExplorer> {
  final ScrollController _scroll = ScrollController();
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode(debugLabel: 'explorer'));
  int _revealed = 0;

  IdeExplorerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _focusNode.addListener(_focusChanged);
    _revealed = _controller.revealRequest;
    if (_controller.selected != null) _scheduleReveal();
  }

  @override
  void didUpdateWidget(IdeExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _focusNode.removeListener(_focusChanged);
    _ownFocusNode?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_controller.revealRequest != _revealed) {
      _revealed = _controller.revealRequest;
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _controller.rows.indexWhere(
        (row) => row.path == _controller.selected,
      );
      if (index < 0) return;
      const height = IdeExplorer.rowHeight;
      final position = _scroll.position;
      final top = index * height;
      if (top < position.pixels) {
        _scroll.jumpTo(top);
      } else if (top + height > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (top + height - position.viewportDimension).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _activate(IdeExplorerRow row, {required bool keyboard}) {
    if (row.message != null) return;
    _controller.select(row.path);
    if (row.isDirectory) {
      unawaited(_controller.toggle(row.path));
    } else {
      widget.onOpen(row.path, keyboard);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rows = [
      for (final row in _controller.rows)
        if (row.message == null) row,
    ];
    if (rows.isEmpty) return KeyEventResult.ignored;
    final index = rows.indexWhere((row) => row.path == _controller.selected);
    final current = index < 0 ? null : rows[index];
    void selectAt(int i) => _controller.select(
      rows[i.clamp(0, rows.length - 1)].path,
      reveal: true,
    );

    if (key == LogicalKeyboardKey.arrowDown) {
      selectAt(index < 0 ? 0 : index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      selectAt(index < 0 ? 0 : index - 1);
    } else if (key == LogicalKeyboardKey.home) {
      selectAt(0);
    } else if (key == LogicalKeyboardKey.end) {
      selectAt(rows.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.pageUp) {
      final page = _scroll.hasClients
          ? (_scroll.position.viewportDimension ~/ IdeExplorer.rowHeight) - 1
          : 10;
      selectAt(
        (index < 0 ? 0 : index) +
            (key == LogicalKeyboardKey.pageDown ? page : -page),
      );
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (current == null) {
        selectAt(0);
      } else if (current.isDirectory && !current.expanded) {
        unawaited(_controller.expand(current.path));
      } else if (current.isDirectory &&
          index + 1 < rows.length &&
          rows[index + 1].depth > current.depth) {
        selectAt(index + 1);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (current == null) {
        selectAt(0);
      } else if (current.isDirectory && current.expanded) {
        _controller.collapse(current.path);
      } else {
        final parent = p.dirname(current.path);
        if (parent != _controller.root) {
          _controller.select(parent, reveal: true);
        }
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (current != null) _activate(current, keyboard: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _controller.rows;
    final focused = _focusNode.hasFocus;
    return ColoredBox(
      color: CursorColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 35,
            child: Padding(
              padding: const EdgeInsets.only(left: 18, right: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'EXPLORER',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: .4,
                        color: CursorColors.textMuted,
                      ),
                    ),
                  ),
                  _HeaderAction(
                    icon: Codicons.refresh,
                    tooltip: 'Refresh Explorer',
                    onTap: () => unawaited(_controller.refresh()),
                  ),
                  _HeaderAction(
                    icon: Codicons.collapseAll,
                    tooltip: 'Collapse Folders in Explorer',
                    onTap: _controller.collapseAll,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
            child: Text(
              widget.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
                color: CursorColors.text,
              ),
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _focusNode.requestFocus,
                child: ListView.builder(
                  controller: _scroll,
                  itemExtent: IdeExplorer.rowHeight,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _ExplorerRowView(
                      key: ValueKey(row.path),
                      row: row,
                      selected: row.path == _controller.selected,
                      focused: focused,
                      onTap: () {
                        _focusNode.requestFocus();
                        _activate(row, keyboard: false);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IdeActionButton(icon: icon, tooltip: tooltip, onPressed: onTap);
  }
}

class _ExplorerRowView extends StatefulWidget {
  const _ExplorerRowView({
    super.key,
    required this.row,
    required this.selected,
    required this.focused,
    required this.onTap,
  });

  final IdeExplorerRow row;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  @override
  State<_ExplorerRowView> createState() => _ExplorerRowViewState();
}

class _ExplorerRowViewState extends State<_ExplorerRowView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final left = 8 + row.depth * IdeExplorer.indent;
    final guides = CustomPaint(
      painter: _IndentGuidesPainter(row.depth),
      child: const SizedBox.expand(),
    );
    if (row.message case final message?) {
      return Stack(
        children: [
          Positioned.fill(child: guides),
          Padding(
            padding: EdgeInsets.only(left: left + 20, right: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CursorColors.removed,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final selected = widget.selected;
    final focused = widget.focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? (focused ? const Color(0x334C9DFF) : const Color(0x1FFFFFFF))
                : _hover
                ? CursorColors.hover
                : Colors.transparent,
            border: Border.all(
              color: selected && focused
                  ? CursorColors.accent
                  : Colors.transparent,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: guides),
              Padding(
                padding: EdgeInsets.only(left: left, right: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: row.isDirectory
                          ? Icon(
                              row.expanded
                                  ? Codicons.chevronDown
                                  : Codicons.chevronRight,
                              size: 16,
                              color: CursorColors.text,
                            )
                          : null,
                    ),
                    const SizedBox(width: 2),
                    if (row.isDirectory)
                      FolderIcon(row.path, size: 16, expanded: row.expanded)
                    else
                      FileIcon(row.path, size: 16),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: selected
                              ? CursorColors.textPrimary
                              : CursorColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IndentGuidesPainter extends CustomPainter {
  const _IndentGuidesPainter(this.depth);

  final int depth;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth == 0) return;
    final paint = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..strokeWidth = 1;
    for (var level = 0; level < depth; level++) {
      final x = 8 + level * IdeExplorer.indent + 8.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_IndentGuidesPainter oldDelegate) =>
      oldDelegate.depth != depth;
}
