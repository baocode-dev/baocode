import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_keys.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../ide/ide_hover.dart';
import '../keybindings/chat_keybindings.dart';
import '../l10n/l10n.dart';
import '../sidebar/sidebar_menu.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'editor_launcher.dart';
import 'workspace.dart';

/// Split button for the title bar: opens [project] in the preferred editor
/// (the Fast Ide layout, or an app); its chevron switches which editor that
/// is (without opening it, and remembered), or copies the path.
class OpenInEditorButton extends StatelessWidget {
  const OpenInEditorButton({
    super.key,
    required this.workspace,
    required this.project,
  });

  final Workspace workspace;
  final Project project;

  /// Opens a project in an editor; replaceable under test.
  @visibleForTesting
  static Future<bool> Function(Editor editor, String path) launch =
      openInEditor;

  void _open(Editor editor) {
    // A remote project's files are not this machine's: only the IDE's own
    // opens them.
    if (editor == Editor.fastIde || project.host != null) {
      // The project in the IDE, with the current agent's chat there.
      if (workspace.current case final thread? when thread.project == project) {
        workspace.openInIde(thread);
      } else {
        workspace
          ..openIdeFolder(project.path)
          ..layout = WorkspaceLayout.ide;
      }
    } else {
      launch(editor, project.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = workspace.preferredEditor;
    final open = context.l10n.workspaceOpenIn(
      editor.localizedPlatformLabel(context.l10n),
    );
    return SidebarMenu(
      width: 200,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      items: () => [
        for (final option in Editor.availableEditors)
          SidebarMenuItem(
            option.localizedPlatformLabel(context.l10n),
            icon: option.icon,
            checked: option == workspace.preferredEditor,
            onSelected: () => workspace.preferredEditor = option,
          ),
        SidebarMenuItem(
          context.l10n.workspaceCopyPath,
          icon: Icons.content_copy_rounded,
          onSelected: () =>
              Clipboard.setData(ClipboardData(text: project.path)),
        ),
      ],
      builder: (context, menu) => Container(
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.partBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              semanticsLabel: open,
              // The Fast Ide's with the keys of Open in Fast Ide, which
              // does the same; an app's has none.
              tooltip: editor == Editor.fastIde
                  ? ChatKeys.titleWithKey(
                      open,
                      ChatCommandIds.openIde,
                      ChatKeys.chatLayout,
                    )
                  : open,
              onTap: () => _open(editor),
              padding: const EdgeInsets.only(left: 7, right: 7),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(editor.icon, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text(
                    editor.localizedPlatformLabel(context.l10n),
                    style: TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: AppColors.partBorder),
            _Segment(
              semanticsLabel: context.l10n.workspaceChooseEditor,
              active: menu.isOpen,
              onTap: menu.open,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(5),
              ),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.semanticsLabel,
    required this.onTap,
    required this.padding,
    required this.borderRadius,
    required this.child,
    this.tooltip,
    this.active = false,
  });

  final String semanticsLabel;

  /// Its hover's text: [semanticsLabel] by default.
  final String? tooltip;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IdeHover(
      message: tooltip ?? semanticsLabel,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: Container(
              padding: padding,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? themeColors['toolbar.activeBackground']
                    : hovered
                    ? themeColors['toolbar.hoverBackground']
                    : Colors.transparent,
                borderRadius: borderRadius,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
