// Over a new chat's input: where it is to work. A menu of the projects
// (none, the Desktop, first) and a button to pick a folder in the system's
// file manager.

import 'package:flutter/material.dart';

import '../chat/composer/composer_picker.dart';
import '../chat/widgets/hover_builder.dart';
import '../icons/project_icon_view.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../platform/desktop_dir.dart'
    if (dart.library.io) '../platform/desktop_dir_io.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'window_controls.dart';
import 'workspace.dart';

class NewChatFolderBar extends StatelessWidget {
  const NewChatFolderBar({
    super.key,
    required this.workspace,
    required this.thread,
  });

  final Workspace workspace;

  /// The new agent, nothing sent to it yet.
  final AgentThread thread;

  /// The projects the menu lists, the most recent first: the rest are
  /// reached by picking their folder.
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
    KernelOption option(Project project) => KernelOption(
      project.path,
      project.name,
      Codicons.folder,
      project.path,
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
      for (final project in workspace.projects)
        if (project.path != desktop) project,
    ];
    final listed = projects.take(_listed).toList();
    if (current.path != desktop && !listed.contains(current)) {
      listed.add(current);
    }
    final options = [?noFolder, for (final project in listed) option(project)];
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
            onSelected: (option) => _moveTo(option.id),
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
