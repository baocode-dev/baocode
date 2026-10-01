import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drag.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';
import 'ide_hover.dart';
import 'ide_menu.dart';
import 'ide_workspace.dart';

/// The actions of a tab's context menu.
enum IdeTabAction {
  close,
  closeOthers,
  closeToTheRight,
  closeSaved,
  closeAll,
  copyPath,
  copyRelativePath,
  revealInFileManager,
  openInDefaultApp,
  revealInExplorer,
}

/// For each of [paths], the parent folders that tell it apart from other open
/// files of the same name (null when its name is unique), as VS Code labels
/// duplicate editor tabs. Paths under [root] are described relative to it.
/// The tabs' titles are [names] where given, else the paths' names.
List<String?> ideTabDescriptions(
  List<String> paths,
  String root, {
  List<String>? names,
}) {
  List<String> parents(String path) {
    final directory = p.dirname(path);
    if (p.equals(directory, root)) return [p.basename(root)];
    if (p.isWithin(root, directory)) {
      return p.split(p.relative(directory, from: root));
    }
    return p.split(directory);
  }

  final byName = <String, List<int>>{};
  for (var i = 0; i < paths.length; i++) {
    byName.putIfAbsent(names?[i] ?? p.basename(paths[i]), () => []).add(i);
  }
  final descriptions = List<String?>.filled(paths.length, null);
  for (final group in byName.values) {
    if (group.length < 2) continue;
    final segments = {for (final i in group) i: parents(paths[i])};
    final longest = segments.values.fold<int>(
      0,
      (max, list) => list.length > max ? list.length : max,
    );
    for (var depth = 1; depth <= longest; depth++) {
      String suffix(int i) {
        final list = segments[i]!;
        final start = list.length - depth < 0 ? 0 : list.length - depth;
        final tail = list.sublist(start).join('/');
        return start > 0 ? '…/$tail' : tail;
      }

      final labels = {for (final i in group) i: suffix(i)};
      if (labels.values.toSet().length == group.length || depth == longest) {
        for (final i in group) {
          descriptions[i] = labels[i];
        }
        break;
      }
    }
  }
  return descriptions;
}

/// VS Code-style editor tabs: icon, name, dirty dot / close button, context
/// menu, middle-click close, and scrolling that keeps the active tab visible.
/// In the color theme's `tab.*` colors of an active group
/// (workbench/browser/parts/editor/multiEditorTabsControl.ts and
/// media/multieditortabscontrol.css).
class IdeTabBar extends StatefulWidget {
  const IdeTabBar({
    super.key,
    required this.documents,
    required this.active,
    required this.root,
    required this.onSelect,
    required this.onClose,
    required this.onAction,
  });

  final List<IdeDocument> documents;
  final IdeDocument? active;
  final String root;
  final ValueChanged<IdeDocument> onSelect;
  final ValueChanged<IdeDocument> onClose;
  final void Function(IdeDocument doc, IdeTabAction action) onAction;

  static const height = 35.0;

  @override
  State<IdeTabBar> createState() => _IdeTabBarState();
}

class _IdeTabBarState extends State<IdeTabBar> {
  final ScrollController _scroll = ScrollController();
  final Map<IdeDocument, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(IdeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.active, widget.active) ||
        oldWidget.documents.length != widget.documents.length) {
      _scheduleReveal();
    }
    _keys.removeWhere((doc, _) => !widget.documents.contains(doc));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final active = widget.active;
      final context = active == null ? null : _keys[active]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final position = _scroll.position;
      _scroll.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  /// `MenuId.EditorTitleContext`: at [position] for a right click, or
  /// below [anchor] for the tab bar's More Actions.
  Future<void> _showMenu(IdeDocument doc, {Offset? position, Rect? anchor}) {
    final docs = widget.documents;
    final index = docs.indexOf(doc);
    final l10n = context.l10n;
    IdeMenuAction item(
      IdeTabAction action,
      String label, {
      String? command,
      bool enabled = true,
    }) => IdeMenuAction(
      label,
      // The keybinding of the command the action is (upstream's menu
      // items are commands).
      keybinding: command == null
          ? null
          : KeybindingService.instance.labelFor(command),
      enabled: enabled,
      onSelected: () {
        if (mounted) widget.onAction(doc, action);
      },
    );
    return showIdeMenu(
      context,
      position: position,
      anchor: anchor,
      alignRight: anchor != null,
      entries: ideMenuGroups([
        [
          item(
            IdeTabAction.close,
            l10n.tabClose,
            command: 'workbench.action.closeActiveEditor',
          ),
          item(
            IdeTabAction.closeOthers,
            l10n.tabCloseOthers,
            enabled: docs.length > 1,
          ),
          item(
            IdeTabAction.closeToTheRight,
            l10n.tabCloseToTheRight,
            enabled: index >= 0 && index < docs.length - 1,
          ),
          item(
            IdeTabAction.closeSaved,
            l10n.tabCloseSaved,
            enabled: docs.any((d) => !d.dirty),
          ),
          item(IdeTabAction.closeAll, l10n.tabCloseAll),
        ],
        [
          item(
            IdeTabAction.copyPath,
            l10n.tabCopyPath,
            command: 'copyFilePath',
          ),
          item(
            IdeTabAction.copyRelativePath,
            l10n.tabCopyRelativePath,
            command: 'copyRelativeFilePath',
          ),
        ],
        [
          // Not a revision's tab, whose file may be gone.
          if (WindowControls.canRevealInFileManager && doc.readRevision == null)
            item(
              IdeTabAction.revealInFileManager,
              l10n.revealInFileManager,
              command: 'revealFileInOS',
            ),
          if (WindowControls.canOpenInDefaultApp && doc.readRevision == null)
            item(IdeTabAction.openInDefaultApp, l10n.openInDefaultApp),
          item(IdeTabAction.revealInExplorer, l10n.tabRevealInExplorerView),
        ],
      ]),
    );
  }

  /// [tab], dragged onto the chat's composer, puts its file in; not a
  /// revision's tab, whose text is not the file's.
  Widget _draggable(IdeDocument doc, Widget tab) => doc.readRevision != null
      ? KeyedSubtree(key: ObjectKey(doc), child: tab)
      : FileDraggable(
          key: ObjectKey(doc),
          files: [ComposerFile(doc.path)],
          child: tab,
        );

  @override
  Widget build(BuildContext context) {
    final docs = widget.documents;
    final descriptions = ideTabDescriptions(
      [for (final doc in docs) doc.path],
      widget.root,
      names: [for (final doc in docs) doc.title],
    );
    return Container(
      height: IdeTabBar.height,
      color: themeColors['editorGroupHeader.tabsBackground'],
      child: Row(
        children: [
          Expanded(
            child: Listener(
              onPointerSignal: _wheel,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, doc) in docs.indexed)
                      _draggable(
                        doc,
                        _Tab(
                          key: _keys.putIfAbsent(doc, GlobalKey.new),
                          doc: doc,
                          description: descriptions[i],
                          active: identical(doc, widget.active),
                          onSelect: () => widget.onSelect(doc),
                          onClose: () => widget.onClose(doc),
                          onMenu: (position) =>
                              _showMenu(doc, position: position),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.active case final active?)
            Builder(
              builder: (context) => _TabBarAction(
                icon: Codicons.ellipsis,
                tooltip: context.l10n.tabMoreActions,
                onTap: () {
                  final box = context.findRenderObject()! as RenderBox;
                  _showMenu(
                    active,
                    anchor: box.localToGlobal(Offset.zero) & box.size,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TabBarAction extends StatelessWidget {
  const _TabBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IdeActionButton(icon: icon, tooltip: tooltip, onPressed: onTap),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    super.key,
    required this.doc,
    required this.description,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onMenu,
  });

  final IdeDocument doc;
  final String? description;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMenu;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;
  bool _closeHover = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final active = widget.active;
    final dirty = doc.dirty;
    final showClose = _hover || (active && !dirty);
    final colors = themeColors;
    // The active tab is selected: hovering it changes nothing.
    final hovered = _hover && !active;
    final foreground = active
        ? colors['tab.activeForeground']
        : (hovered ? colors.get('tab.hoverForeground') : null) ??
              colors['tab.inactiveForeground'];
    final bottom = active ? colors.get('tab.activeBorder') : null;
    final right = colors.get('tab.border') ?? colors.get('contrastBorder');
    // `activeContrastBorder`: high contrast themes outline the active tab
    // and a hovered one (5px inside it, and dashed on hover, upstream).
    final outline = active || _hover
        ? colors.get('contrastActiveBorder')
        : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0) widget.onClose();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
          child: Container(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 260),
            padding: const EdgeInsets.only(left: 10, right: 5),
            decoration: BoxDecoration(
              // The active tab wears the same selection color as the side
              // bar's rows and the chat tabs, rather than the theme's
              // `tab.activeBackground` (a deviation: upstream's active tab
              // is the editor's own color, so that it merges with it).
              color: active
                  ? colors['list.activeSelectionBackground']
                  : (hovered ? colors.get('tab.hoverBackground') : null) ??
                        colors['tab.inactiveBackground'],
              border: Border(
                top: BorderSide(
                  color:
                      (active ? colors.get('tab.activeBorderTop') : null) ??
                      Colors.transparent,
                ),
                right: BorderSide(color: right ?? Colors.transparent),
              ),
            ),
            // Over the tab, as upstream's are.
            foregroundDecoration: bottom == null && outline == null
                ? null
                : BoxDecoration(
                    border: outline != null
                        ? Border.all(color: outline)
                        : Border(bottom: BorderSide(color: bottom!)),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FileIcon(doc.path, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: doc.deleted
                          ? context.l10n.tabDeleted(doc.title)
                          : doc.title,
                      // Upstream strikes a deleted file's label through.
                      style: doc.deleted
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                      children: [
                        if (widget.description case final description?)
                          TextSpan(
                            text: '  $description',
                            // `.label-description`: 70% opaque.
                            style: TextStyle(
                              color: foreground.withValues(
                                alpha: foreground.a * .7,
                              ),
                              fontSize: 11,
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: foreground),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: showClose
                      ? MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _closeHover = true),
                          onExit: (_) => setState(() => _closeHover = false),
                          // Close Editor's keys, on the active tab's only:
                          // they close that one (a deviation: upstream's
                          // `redrawTabAction`, multiEditorTabsControl.ts,
                          // has them on every tab's).
                          child: IdeHover(
                            message: active
                                ? KeybindingService.instance
                                      .titleWithKeybinding(
                                        context.l10n.tabCloseNamed(doc.title),
                                        'workbench.action.closeActiveEditor',
                                      )
                                : context.l10n.tabCloseNamed(doc.title),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onClose,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _closeHover
                                      ? colors['toolbar.hoverBackground']
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                // The tab's color (`inherit`).
                                child: Icon(
                                  Codicons.close,
                                  size: 14,
                                  color: foreground,
                                ),
                              ),
                            ),
                          ),
                        )
                      : dirty
                      ? Center(
                          child: Container(
                            key: const ValueKey('dirty'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: foreground,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
