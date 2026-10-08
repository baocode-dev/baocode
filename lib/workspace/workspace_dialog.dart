// Creating a multi-folder workspace, or changing one: its name and its
// folders, added from the projects listed or picked in the file manager.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../icons/project_icon_view.dart';
import '../ide/ide_button.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_input.dart';
import '../ide/ide_menu.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'project_workspace.dart';
import 'window_controls.dart';
import 'workspace.dart';

/// Asks for a new workspace's name and folders ([folders] in it to begin
/// with), or [editing]'s new ones; completes with the workspace made or
/// changed, or null when dismissed.
Future<ProjectWorkspace?> showWorkspaceDialog(
  BuildContext context, {
  required Workspace workspace,
  ProjectWorkspace? editing,
  List<String> folders = const [],
}) => showGeneralDialog<ProjectWorkspace>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) =>
      WorkspaceDialog(workspace: workspace, editing: editing, folders: folders),
);

class WorkspaceDialog extends StatefulWidget {
  const WorkspaceDialog({
    super.key,
    required this.workspace,
    this.editing,
    this.folders = const [],
  });

  final Workspace workspace;

  /// The workspace changed; null to make one.
  final ProjectWorkspace? editing;

  /// The folders a new one starts with.
  final List<String> folders;

  /// Picks a folder; replaceable under test.
  @visibleForTesting
  static Future<String?> Function() pickDirectory =
      WindowControls.pickDirectory;

  /// Whether a folder can be picked in the file manager; replaceable under
  /// test.
  @visibleForTesting
  static bool Function() canPickDirectory = () =>
      WindowControls.canPickDirectory;

  @override
  State<WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends State<WorkspaceDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name,
  );
  late final List<String> _folders = [
    ...?widget.editing?.folders,
    if (widget.editing == null) ...widget.folders,
  ];
  final _addProject = GlobalKey();
  bool _tried = false;

  Workspace get _workspace => widget.workspace;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// What it is named when the user names it nothing: its folders'.
  String get _suggestedName {
    final names = [for (final folder in _folders.take(3)) p.basename(folder)];
    return names.isEmpty ? context.l10n.workspaceNameHint : names.join(', ');
  }

  /// The projects of this machine that may be added: folders, not other
  /// workspaces (nor this one).
  List<Project> get _projects => [
    for (final project in _workspace.sidebarProjects)
      if (project.host == null &&
          _workspace.workspaceOf(project) == null &&
          project.path != widget.editing?.path)
        project,
  ];

  void _toggle(String folder) => setState(() {
    if (!_folders.remove(folder)) _folders.add(folder);
  });

  Future<void> _pick() async {
    final folder = await WorkspaceDialog.pickDirectory();
    if (folder == null || !mounted) return;
    setState(() {
      if (!_folders.contains(folder)) _folders.add(folder);
    });
  }

  Future<void> _showProjects() async {
    final box = _addProject.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final projects = _projects;
    final names = <String, int>{};
    for (final project in projects) {
      names[project.name] = (names[project.name] ?? 0) + 1;
    }
    await showIdeMenu(
      context,
      anchor: anchor,
      entries: [
        if (projects.isEmpty)
          IdeMenuAction(context.l10n.workspaceNoProjects, enabled: false),
        for (final project in projects)
          IdeMenuAction(
            // Two of one name: told apart by where they are.
            names[project.name]! > 1
                ? '${project.name} — ${project.path}'
                : project.name,
            checked: _folders.contains(project.path),
            onSelected: () => _toggle(project.path),
          ),
      ],
    );
  }

  void _save() {
    if (_folders.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    final typed = _name.text.trim();
    final name = typed.isEmpty ? _suggestedName : typed;
    final editing = widget.editing;
    if (editing == null) {
      Navigator.pop(context, _workspace.createWorkspace(name, _folders));
      return;
    }
    _workspace.updateWorkspace(editing, name: name, folders: _folders);
    Navigator.pop(context, _workspace.workspaceAt(editing.path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final fileManager = AppPlatform.isWindows
        ? l10n.workspaceFileExplorer
        : l10n.workspaceFinder;
    return _DialogFrame(
      title: widget.editing == null
          ? l10n.workspaceCreateTitle
          : l10n.workspaceEditTitle,
      onSubmit: _save,
      actions: [
        IdeButton(
          label: widget.editing == null
              ? l10n.workspaceCreate
              : l10n.commonSave,
          onPressed: _save,
        ),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.workspaceName, style: _text(size: 12)),
            const SizedBox(height: 4),
            IdeInputBox(
              controller: _name,
              autofocus: true,
              placeholder: _suggestedName,
              semanticsLabel: l10n.workspaceName,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Text(l10n.workspaceFolders, style: _text(size: 12)),
            const SizedBox(height: 2),
            Text(l10n.workspaceFoldersDescription, style: _muted()),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _tried && _folders.isEmpty
                      ? colors['inputValidation.errorBorder']
                      : colors['input.border'],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(minHeight: 56),
              child: _folders.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _tried
                            ? l10n.workspaceNoFolders
                            : l10n.workspaceFoldersEmpty(fileManager),
                        textAlign: TextAlign.center,
                        style: _muted(),
                      ),
                    )
                  : Column(
                      children: [
                        for (final folder in _folders)
                          _FolderRow(
                            key: ValueKey(folder),
                            workspace: _workspace,
                            folder: folder,
                            onRemove: () => _toggle(folder),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                IdeButton(
                  key: _addProject,
                  icon: Codicons.add,
                  label: l10n.workspaceAddProject,
                  secondary: true,
                  onPressed: _showProjects,
                ),
                if (WorkspaceDialog.canPickDirectory())
                  IdeButton(
                    icon: Codicons.folderOpened,
                    label: l10n.workspaceAddFolder(fileManager),
                    secondary: true,
                    onPressed: _pick,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A folder of the workspace: its project's icon and name, where it is,
/// and an × to take it out.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.workspace,
    required this.folder,
    required this.onRemove,
  });

  final Workspace workspace;
  final String folder;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final project = workspace.projectAt(folder);
    final name = p.basename(folder);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      child: Row(
        children: [
          ProjectIconView(
            icon: workspace.iconOf(project),
            library: workspace.icons,
            size: 20,
            color: themeColors['descriptionForeground'],
            fallback: Codicons.folder,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: _text(), overflow: TextOverflow.ellipsis),
                Text(
                  folder,
                  style: _muted(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IdeActionButton(
            icon: Codicons.close,
            iconSize: 14,
            tooltip: context.l10n.workspaceRemoveFolder(name),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// [title] over [child], [actions] under it, as the IDE's dialogs look.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.child,
    required this.actions,
    required this.onSubmit,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  /// Enter, outside a field that takes it.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final border = colors.get('widget.border');
    final shadow = colors.get('widget.shadow');
    final size = MediaQuery.sizeOf(context);
    final width = math.max(420.0, math.min(520.0, size.width * .9));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.enter): onSubmit,
      },
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.5),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: size.height * .85),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  const BoxShadow(color: Color(0x26000000), blurRadius: 20),
                  if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 4),
                        child: Icon(
                          Codicons.folderLibrary,
                          size: 16,
                          color: colors['descriptionForeground'],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors['editorWidget.foreground'],
                            ),
                          ),
                        ),
                      ),
                      IdeActionButton(
                        icon: Codicons.close,
                        tooltip: context.l10n.dialogCloseDialog,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: child,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 8, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final (i, action) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          action,
                        ],
                      ],
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

TextStyle _text({Color? color, double size = 13}) => TextStyle(
  fontSize: size,
  height: 18 / 13,
  color: color ?? themeColors['editorWidget.foreground'],
);

TextStyle _muted() =>
    _text(color: themeColors['descriptionForeground'], size: 12);
