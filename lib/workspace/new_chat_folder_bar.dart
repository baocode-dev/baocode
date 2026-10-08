// Over a new chat's input: where it is to work. A menu of the projects
// (none, the Desktop, first; multi-folder workspaces under their own
// heading, with Create Workspace…; those on SSH hosts under theirs, with
// Open Remote Project…) and a button to pick a folder in the system's file
// manager.

import 'package:flutter/material.dart';

import '../chat/composer/composer_picker.dart';
import '../chat/widgets/hover_builder.dart';
import '../icons/project_icon_view.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../remote/remote_location.dart';
import '../platform/desktop_dir.dart'
    if (dart.library.io) '../platform/desktop_dir_io.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'window_controls.dart';
import 'workspace.dart';
import 'workspace_dialog.dart';

class NewChatFolderBar extends StatelessWidget {
  const NewChatFolderBar({
    super.key,
    required this.workspace,
    required this.thread,
    this.openRemote,
  });

  final Workspace workspace;

  /// The new agent, nothing sent to it yet.
  final AgentThread thread;

  /// Open Remote Project…: walks the user to a folder on an SSH host, then
  /// gives its location to the function given. None, none offered.
  final void Function(ValueChanged<String> onOpen)? openRemote;

  /// The menu's row for Open Remote Project….
  static const _openRemoteId = 'baocode.remote.openFolder';

  /// The menu's row for Create Workspace….
  static const _createWorkspaceId = 'baocode.workspace.create';

  /// The projects the menu lists of this machine, and of SSH hosts, the
  /// most recent first: the rest are reached by picking their folder.
  static const _listed = 8;

  /// The folder of a chat in no project; replaceable under test.
  @visibleForTesting
  static String? Function() desktop = () => desktopDirectory;

  /// Picks a folder; replaceable under test.
  @visibleForTesting
  static Future<String?> Function() pickDirectory =
      WindowControls.pickDirectory;

  void _moveTo(String path) => workspace.moveNew(thread, path);

  Future<void> _pick() async {
    final path = await pickDirectory();
    if (path != null) workspace.moveNew(thread, path);
  }

  /// Asks for a new workspace (the folder the agent was to work in, in it
  /// to begin with), and has the agent work there.
  Future<void> _createWorkspace(BuildContext context, String? desktop) async {
    final current = thread.project;
    final made = await showWorkspaceDialog(
      context,
      workspace: workspace,
      folders: [
        if (current.host == null &&
            current.path != desktop &&
            workspace.workspaceOf(current) == null)
          current.path,
      ],
    );
    if (made != null) _moveTo(made.path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final desktop = NewChatFolderBar.desktop();
    final current = thread.project;
    final noFolder = desktop == null
        ? null
        : KernelOption(
            desktop,
            l10n.newChatNoFolder,
            Codicons.deviceDesktop,
            l10n.newChatNoFolderDetail,
          );
    final remoteGroup = KernelOptionGroup('remote', l10n.newChatRemoteGroup);
    final workspaceGroup = KernelOptionGroup(
      'workspaces',
      l10n.newChatWorkspaceGroup,
    );
    KernelOption option(Project project) => KernelOption(
      project.path,
      project.name,
      workspace.workspaceOf(project) != null
          ? Codicons.folderLibrary
          : project.host == null
          ? Codicons.folder
          : Codicons.remote,
      switch ((project.host, workspace.workspaceOf(project))) {
        (_, final multi?) => l10n.newChatWorkspaceDetail(
          multi.folders.length,
          multi.folders.map(RemoteLocation.nameOf).join(', '),
        ),
        (final host?, _) => '$host:${project.root}',
        (null, _) => project.path,
      },
      group: workspace.workspaceOf(project) != null
          ? workspaceGroup
          : project.host == null
          ? null
          : remoteGroup,
      iconBuilder: switch (workspace.iconOf(project)) {
        null => null,
        // Takes the room of a glyph of [size]; a picture spills over it a
        // little, as large as the glyph looks.
        final icon => (size, color) => SizedBox.square(
          dimension: size,
          child: OverflowBox(
            maxWidth: size + 3,
            maxHeight: size + 3,
            child: ProjectIconView(
              icon: icon,
              library: workspace.icons,
              size: size + 3,
              color: color,
            ),
          ),
        ),
      },
    );
    final projects = [
      for (final project in workspace.sidebarProjects)
        if (project.path != desktop) project,
    ];
    bool isWorkspace(Project project) => workspace.workspaceOf(project) != null;
    final local = [
      ...projects
          .where((project) => project.host == null && !isWorkspace(project))
          .take(_listed),
    ];
    final workspaces = [...projects.where(isWorkspace).take(_listed)];
    final remote = [
      ...projects.where((project) => project.host != null).take(_listed),
    ];
    if (current.path != desktop &&
        !workspace.isHidden(current) &&
        !local.contains(current) &&
        !workspaces.contains(current) &&
        !remote.contains(current)) {
      (isWorkspace(current)
              ? workspaces
              : current.host == null
              ? local
              : remote)
          .add(current);
    }
    final canCreate = workspace.workspaceDirectories.root != null;
    final options = [
      ?noFolder,
      for (final project in local) option(project),
      for (final project in workspaces) option(project),
      if (canCreate)
        KernelOption(
          NewChatFolderBar._createWorkspaceId,
          l10n.newChatCreateWorkspace,
          Codicons.add,
          l10n.newChatCreateWorkspaceDetail,
          group: workspaceGroup,
        ),
      for (final project in remote) option(project),
      if (openRemote != null)
        KernelOption(
          NewChatFolderBar._openRemoteId,
          l10n.cmdOpenRemoteFolder,
          Codicons.plug,
          l10n.newChatOpenRemoteDetail,
          group: remoteGroup,
        ),
    ];
    final selected = current.path == desktop ? noFolder! : option(current);
    final fileManager = AppPlatform.isWindows
        ? l10n.workspaceFileExplorer
        : l10n.workspaceFinder;
    return Row(
      children: [
        Flexible(
          child: ComposerPicker(
            options: options,
            selected: selected,
            title: l10n.newChatWorkingFolder,
            menuWidth: 290,
            onSelected: (option) => switch (option.id) {
              NewChatFolderBar._openRemoteId => openRemote?.call(_moveTo),
              NewChatFolderBar._createWorkspaceId => _createWorkspace(
                context,
                desktop,
              ),
              final path => _moveTo(path),
            },
          ),
        ),
        if (WindowControls.canPickDirectory) ...[
          const SizedBox(width: 2),
          _Button(
            icon: Codicons.folderOpened,
            label: l10n.newChatOpenFrom(fileManager),
            onTap: _pick,
          ),
        ],
      ],
    );
  }
}

/// A toolbar item, as the pickers beside it are.
class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: hovered
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
