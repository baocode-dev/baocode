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
import 'save_copy.dart';
import 'tab_strip_scroll.dart';

/// The actions of a tab's context menu.
enum IdeTabAction {
  close,
  closeOthers,
  closeToTheRight,
  closeSaved,
  closeAll,
  copyPath,
  copyRelativePath,
  saveAs,
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
    this.local = true,
    this.markdownPreview,
    this.onMarkdownPreview,
  });

  final List<IdeDocument> documents;

  /// Whether the files are this machine's: a remote project's are neither
  /// shown in the file manager nor opened in another app.
  final bool local;
  final IdeDocument? active;
  final String root;
  final ValueChanged<IdeDocument> onSelect;
  final ValueChanged<IdeDocument> onClose;
  final void Function(IdeDocument doc, IdeTabAction action) onAction;

  /// Whether the active tab, a markdown file's, shows its preview (true)
  /// or its source (false); null for other tabs, which have no switch.
  final bool? markdownPreview;

  /// Shows the active markdown file's preview (true) or source (false).
  final ValueChanged<bool>? onMarkdownPreview;

  static const height = IdeTabStrip.height;

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
          // The editor's Save As; a picture's or binary file's is copied.
          // Not a revision's.
          if (canSaveFileCopy && doc.readRevision == null && doc.label == null)
            item(
              IdeTabAction.saveAs,
              l10n.cmdSaveAs,
              command: 'workbench.action.files.saveAs',
            ),
          // Not a revision's tab, whose file may be gone.
          if (widget.local &&
              WindowControls.canRevealInFileManager &&
              doc.readRevision == null)
            item(
              IdeTabAction.revealInFileManager,
              l10n.revealInFileManager,
              command: 'revealFileInOS',
            ),
          if (widget.local &&
              WindowControls.canOpenInDefaultApp &&
              doc.readRevision == null)
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
    return IdeTabStrip(
      child: Row(
        children: [
          Expanded(
            child: TabStripScroll(
              controller: _scroll,
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
          if ((widget.markdownPreview, widget.onMarkdownPreview) case (
            final preview?,
            final onChanged?,
          ))
            _MarkdownSwitch(preview: preview, onChanged: onChanged),
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

/// A markdown tab's Preview | Markdown switch.
class _MarkdownSwitch extends StatelessWidget {
  const _MarkdownSwitch({required this.preview, required this.onChanged});

  final bool preview;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget option(String label, bool value) {
      final selected = preview == value;
      return Semantics(
        button: true,
        selected: selected,
        child: MouseRegion(
          cursor: selected ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: selected ? null : () => onChanged(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? themeColors['toolbar.activeBackground']
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? themeColors['foreground']
                      : themeColors['descriptionForeground'],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(l10n.markdownShowPreview, true),
          const SizedBox(width: 2),
          option(l10n.markdownShowSource, false),
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

/// An editor's tab: [IdeEditorTab] with its file's icon and name, a dot
/// while it has unsaved changes.
class _Tab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IdeEditorTab(
      icon: FileIcon(doc.path, size: 16),
      label: doc.deleted ? l10n.tabDeleted(doc.title) : doc.title,
      description: description,
      // Upstream strikes a deleted file's label through.
      labelStyle: doc.deleted
          ? const TextStyle(decoration: TextDecoration.lineThrough)
          : null,
      active: active,
      mark: doc.dirty
          ? (color) => Center(
              child: Container(
                key: const ValueKey('dirty'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            )
          : null,
      // Close Editor's keys, on the active tab's only: they close that one
      // (a deviation: upstream's `redrawTabAction`,
      // multiEditorTabsControl.ts, has them on every tab's).
      closeTooltip: active
          ? KeybindingService.instance.titleWithKeybinding(
              l10n.tabCloseNamed(doc.title),
              'workbench.action.closeActiveEditor',
            )
          : l10n.tabCloseNamed(doc.title),
      onSelect: onSelect,
      onClose: onClose,
      onMenu: onMenu,
    );
  }
}

/// A strip of [IdeEditorTab]s, [height] high: `editorGroupHeader.*`, its
/// `tabsBorder` along the bottom where the theme has one (the tabs draw
/// it over themselves, so the active one's `tab.activeBorder` is on top,
/// as upstream's `.tabs-border-bottom::after`).
class IdeTabStrip extends StatelessWidget {
  const IdeTabStrip({super.key, required this.child, this.line});

  final Widget child;

  /// The line under the tabs where the theme has none ([border]).
  final Color? line;

  static const height = 35.0;

  /// `editorGroupHeader.tabsBorder`, none by default.
  static Color? get border => themeColors.get('editorGroupHeader.tabsBorder');

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    // Not a Container: its border would inset the tabs.
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: themeColors['editorGroupHeader.tabsBackground'],
        border: switch (border ?? line) {
          final color? => Border(bottom: BorderSide(color: color)),
          null => null,
        },
      ),
      child: child,
    ),
  );
}

/// A tab as the editor's (multiEditorTabsControl.ts, in the theme's
/// `tab.*` colors): [icon], [label] and its [description], [trailing],
/// then a close button while it is hovered, or active without a [mark];
/// else [mark] in its place. The IDE's chat tabs and the side panel's are
/// these too.
class IdeEditorTab extends StatefulWidget {
  const IdeEditorTab({
    super.key,
    required this.icon,
    required this.active,
    required this.onSelect,
    this.label,
    this.description,
    this.labelStyle,
    this.trailing,
    this.mark,
    this.closeTooltip,
    this.onClose,
    this.onMenu,
    this.tooltip,
    this.minWidth = 80,
    this.borderTop = true,
  });

  /// In 16px, in the tab's color unless it has its own.
  final Widget icon;
  final bool active;
  final VoidCallback onSelect;

  /// None: the icon alone.
  final String? label;
  final String? description;

  /// Over the label's (a deleted file's strike, a change's color).
  final TextStyle? labelStyle;

  /// After the label: a count, a change's letter.
  final Widget? trailing;

  /// Where the close button goes while the pointer is not over the tab, in
  /// the tab's color: an editor's dirty dot.
  final Widget Function(Color color)? mark;
  final String? closeTooltip;

  /// None: it does not close, and has no close button.
  final VoidCallback? onClose;

  /// A right click at its global position.
  final ValueChanged<Offset>? onMenu;

  /// On hover; what screen readers say too.
  final String? tooltip;
  final double minWidth;

  /// Whether the active one has `tab.activeBorderTop` above it.
  final bool borderTop;

  /// Its padding at the left, and at the right without a close button.
  static const padding = 10.0;
  static const iconSize = 16.0;
  static const gap = 6.0;
  static const labelStyleBase = TextStyle(fontSize: 12.5);

  @override
  State<IdeEditorTab> createState() => _IdeEditorTabState();
}

class _IdeEditorTabState extends State<IdeEditorTab> {
  bool _hover = false;
  bool _closeHover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final mark = widget.mark;
    final onClose = widget.onClose;
    final showClose = _hover || (active && mark == null);
    final colors = themeColors;
    // The active tab is selected: hovering it changes nothing.
    final hovered = _hover && !active;
    final foreground = active
        ? colors['tab.activeForeground']
        : (hovered ? colors.get('tab.hoverForeground') : null) ??
              colors['tab.inactiveForeground'];
    // The strip's line, over every tab; the active one's own over it.
    final bottom =
        (active ? colors.get('tab.activeBorder') : null) ?? IdeTabStrip.border;
    final right = colors.get('tab.border') ?? colors.get('contrastBorder');
    // `activeContrastBorder`: high contrast themes outline the active tab
    // and a hovered one (5px inside it, and dashed on hover, upstream).
    final outline = active || _hover
        ? colors.get('contrastActiveBorder')
        : null;
    final label = widget.label;
    Widget tab = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0) onClose?.call();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          onSecondaryTapUp: switch (widget.onMenu) {
            final onMenu? => (details) => onMenu(details.globalPosition),
            null => null,
          },
          child: Container(
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              maxWidth: 260,
            ),
            padding: EdgeInsets.only(
              left: IdeEditorTab.padding,
              right: onClose == null ? IdeEditorTab.padding : 5,
            ),
            decoration: BoxDecoration(
              // The active tab in the editor's own color (by default),
              // merging with it.
              color: active
                  ? colors['tab.activeBackground']
                  : (hovered ? colors.get('tab.hoverBackground') : null) ??
                        colors['tab.inactiveBackground'],
              border: Border(
                top: BorderSide(
                  color:
                      (active && widget.borderTop
                          ? colors.get('tab.activeBorderTop')
                          : null) ??
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
                IconTheme.merge(
                  data: IconThemeData(
                    size: IdeEditorTab.iconSize,
                    color: foreground,
                  ),
                  child: SizedBox.square(
                    dimension: IdeEditorTab.iconSize,
                    child: Center(child: widget.icon),
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(width: IdeEditorTab.gap),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: label,
                        style: widget.labelStyle,
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
                      style: IdeEditorTab.labelStyleBase.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
                if (widget.trailing case final trailing?) ...[
                  const SizedBox(width: IdeEditorTab.gap),
                  trailing,
                ],
                if (onClose != null) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: showClose
                        ? MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) => setState(() => _closeHover = true),
                            onExit: (_) => setState(() => _closeHover = false),
                            child: IdeHover(
                              message: widget.closeTooltip,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onClose,
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
                        : mark?.call(foreground),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip case final tooltip?) {
      tab = IdeHover(message: tooltip, child: tab);
    }
    return Semantics(
      button: true,
      selected: active,
      label: widget.tooltip,
      child: tab,
    );
  }
}
