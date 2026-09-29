import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/cursor_theme.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'editor/monaco/vs/editor/common/core/position.dart';
import 'ide_editor.dart';
import 'ide_explorer.dart';
import 'ide_tools_panel.dart';
import 'ide_workspace.dart';

/// The IDE shell is kept mounted when the user returns to the conversation.
class IdeWorkbench extends StatefulWidget {
  const IdeWorkbench({
    super.key,
    required this.workspace,
    required this.project,
    required this.visible,
    required this.chat,
    required this.onBack,
    this.editorBuilder,
  });

  final IdeWorkspace workspace;
  final Project project;
  final bool visible;
  final Widget chat;
  final VoidCallback onBack;

  /// Optional editor override for widget tests.
  final Widget Function(BuildContext, IdeWorkspace)? editorBuilder;

  @override
  State<IdeWorkbench> createState() => IdeWorkbenchState();
}

class IdeWorkbenchState extends State<IdeWorkbench> {
  final _editorKey = GlobalKey<IdeEditorState>();
  double _chatWidth = 420;
  bool _sidebarShown = true;
  int _view = 0;
  String? _error;
  String _lspStatus = 'Language services';
  Position _caretPosition = const Position(1, 1);
  int _statusColumn = 1;
  bool _openedEditor = false;
  bool _busy = false;

  void _report(Object error) {
    if (mounted) setState(() => _error = error.toString());
  }

  Future<void> _open(String path, [int? line]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _editorKey.currentState?.flush();
      await widget.workspace.open(path);
      if (!mounted) return;
      setState(() {
        _openedEditor = true;
        _error = null;
      });
      if (line != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_editorKey.currentState?.revealLine(line));
        });
      }
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(IdeDocument doc) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _editorKey.currentState?.flush();
      widget.workspace.select(doc.path);
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(IdeDocument doc) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _editorKey.currentState?.flush();
      if (!mounted) return;
      if (doc.dirty) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Save changes to ${doc.name}?'),
            content: const Text(
              'Your changes will be lost if you discard them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (choice == 'save') await widget.workspace.save(doc);
      }
      await _editorKey.currentState?.closeDocument(doc);
      widget.workspace.close(doc);
    } catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    try {
      await _editorKey.currentState?.flush();
      if (mounted) widget.onBack();
    } catch (error) {
      _report(error);
    }
  }

  Widget _button(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool selected = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 19),
    color: selected ? CursorColors.textPrimary : CursorColors.textMuted,
    visualDensity: VisualDensity.compact,
  );

  Widget _activityBar() => Container(
    width: 44,
    decoration: const BoxDecoration(
      color: CursorColors.surface,
      border: Border(right: BorderSide(color: CursorColors.border)),
    ),
    child: Column(
      children: [
        for (final (i, icon, label) in [
          (0, Icons.file_copy_outlined, 'Explorer'),
          (1, Icons.search, 'Search files'),
          (2, Icons.account_tree_outlined, 'Source control'),
          (3, Icons.play_arrow_outlined, 'Run and debug'),
          (4, Icons.extension_outlined, 'Extensions'),
        ])
          _button(
            icon,
            label,
            () => setState(() {
              if (_view == i) {
                _sidebarShown = !_sidebarShown;
              } else {
                _view = i;
                _sidebarShown = true;
              }
            }),
            selected: _view == i && _sidebarShown,
          ),
        const Spacer(),
        _button(
          Icons.chat_bubble_outline,
          'Back to chat',
          () => unawaited(_back()),
        ),
      ],
    ),
  );

  Widget _sidePanel() => switch (_view) {
    0 => IdeExplorer(workspace: widget.workspace, onOpen: _open),
    1 || 2 => IdeToolsPanel(
      key: ValueKey((widget.workspace.root, _view)),
      root: widget.workspace.root,
      mode: _view == 1 ? IdeToolMode.search : IdeToolMode.sourceControl,
      onOpen: _open,
    ),
    _ => ColoredBox(
      color: CursorColors.sidebarSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _view == 3
              ? 'Run and debug\n\nDebugger integration is not available yet.'
              : 'Extensions\n\nNative Fast Ide does not load VS Code extensions.',
          style: const TextStyle(fontSize: 12, color: CursorColors.textMuted),
        ),
      ),
    ),
  };

  Widget _tabs() => Container(
    height: 33,
    color: CursorColors.surface,
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final doc in widget.workspace.documents)
                  Container(
                    decoration: BoxDecoration(
                      color: identical(doc, widget.workspace.active)
                          ? CursorColors.background
                          : CursorColors.surface,
                      border: Border(
                        top: BorderSide(
                          color: identical(doc, widget.workspace.active)
                              ? CursorColors.accent
                              : Colors.transparent,
                        ),
                        right: const BorderSide(color: CursorColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: _busy ? null : () => unawaited(_select(doc)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              '${doc.dirty ? '● ' : ''}${doc.name}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: CursorColors.text,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 26,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Close ${doc.name}',
                            icon: const Icon(Icons.close, size: 13),
                            onPressed: _busy
                                ? null
                                : () => unawaited(_close(doc)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        _button(
          Icons.save_outlined,
          'Save file (⌘S / Ctrl+S)',
          () => unawaited(_editorKey.currentState?.save()),
        ),
      ],
    ),
  );

  Widget _editorArea() {
    final active = widget.workspace.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabs(),
        Container(
          height: 25,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Text(
            active == null
                ? widget.project.name
                : p.relative(active.path, from: widget.workspace.root),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: CursorColors.textMuted),
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if ((_openedEditor || active != null) && active != null)
                widget.editorBuilder?.call(context, widget.workspace) ??
                    IdeEditor(
                      key: _editorKey,
                      workspace: widget.workspace,
                      active: active,
                      onError: _report,
                      onLspStatus: (status) {
                        if (mounted) setState(() => _lspStatus = status);
                      },
                      onPositionChanged: (selection) {
                        if (mounted &&
                            (!_caretPosition.equals(selection.position) ||
                                _statusColumn != selection.statusColumn)) {
                          setState(() {
                            _caretPosition = selection.position;
                            _statusColumn = selection.statusColumn;
                          });
                        }
                      },
                    ),
              if (active == null)
                const ColoredBox(
                  color: CursorColors.background,
                  child: Center(
                    child: Text(
                      'Open a file from the Explorer',
                      style: TextStyle(
                        color: CursorColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _split(double width, double height) {
    final narrow = width < 760;
    if (narrow) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _activityBar(),
                if (_sidebarShown)
                  SizedBox(
                    width: math.min(200, width * .36),
                    child: _sidePanel(),
                  ),
                Expanded(child: _editorArea()),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(height: height * .44, child: widget.chat),
        ],
      );
    }
    final chatWidth = _chatWidth.clamp(300.0, width * .48);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _activityBar(),
        if (_sidebarShown && width >= 1000)
          SizedBox(width: 220, child: _sidePanel()),
        Expanded(child: _editorArea()),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => setState(() {
              _chatWidth = (chatWidth - details.delta.dx).clamp(
                300.0,
                width * .48,
              );
            }),
            child: Container(
              width: 5,
              alignment: Alignment.centerLeft,
              child: Container(width: 1, color: CursorColors.border),
            ),
          ),
        ),
        SizedBox(width: chatWidth, child: widget.chat),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CursorColors.background,
      child: ListenableBuilder(
        listenable: widget.workspace,
        builder: (context, _) => Column(
          children: [
            if (!WindowControls.drawsHeader)
              SizedBox(
                height: CursorMetrics.titleBarHeight,
                child: Row(
                  children: [
                    SizedBox(width: CursorMetrics.trafficLightsWidth + 8),
                    const Text(
                      'Fast Ide',
                      style: TextStyle(
                        fontSize: 12,
                        color: CursorColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.project.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => unawaited(_back()),
                      icon: const Icon(Icons.chat_bubble_outline, size: 14),
                      label: const Text(
                        'Back to chat',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            if (_error != null)
              Container(
                color: CursorColors.surfaceRaised,
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CursorColors.removed,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _split(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
            Container(
              height: 24,
              decoration: const BoxDecoration(
                color: CursorColors.surface,
                border: Border(top: BorderSide(color: CursorColors.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => unawaited(
                        _editorKey.currentState?.retryLanguageServer(),
                      ),
                      child: Text(
                        _lspStatus,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: CursorColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Ln ${_caretPosition.lineNumber}, Col $_statusColumn   UTF-8',
                    style: const TextStyle(
                      fontSize: 11,
                      color: CursorColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
