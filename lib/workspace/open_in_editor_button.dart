import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_keys.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../ide/ide_button.dart';
import '../ide/ide_hover.dart';
import '../keybindings/chat_keybindings.dart';
import '../l10n/l10n.dart';
import '../sidebar/sidebar_menu.dart';
import '../theme/codicons.dart';
import 'back_to_chat_button.dart';
import 'editor_launcher.dart';
import 'workspace.dart';

/// Split button for the title bar: opens [project] in the preferred editor
/// (the Fast Ide layout, or an app); its chevron switches which editor that
/// is (without opening it, and remembered), or copies the path. In the
/// colors of the IDE's [BackToChatButton], its counterpart there, and as
/// wide: the layout switches between them without a jump.
class OpenInEditorButton extends StatelessWidget {
  const OpenInEditorButton({
    super.key,
    required this.workspace,
    required this.project,
    this.agent,
    this.compact = false,
  });

  final Workspace workspace;
  final Project project;

  /// The agent whose chat the IDE opens with [project]; null: the focused
  /// one's, where it is this project's.
  final AgentThread? agent;

  /// The editor's icon alone: a pane's title bar among others, where the
  /// label does not fit beside them.
  final bool compact;

  /// Opens a project in an editor; replaceable under test.
  @visibleForTesting
  static Future<bool> Function(Editor editor, String path) launch =
      openInEditor;

  void _open(Editor editor) {
    // A remote project's files are not this machine's: only the IDE's own
    // opens them.
    if (editor == Editor.fastIde || project.host != null) {
      // The project in the IDE, with the agent's chat there.
      final thread =
          agent ??
          (workspace.current?.project == project ? workspace.current : null);
      if (thread != null) {
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
          icon: Codicons.copy,
          onSelected: () =>
              Clipboard.setData(ClipboardData(text: project.path)),
        ),
      ],
      builder: (context, menu) {
        final foreground = IdeButtonColors.foreground;
        final width = compact ? 0.0 : titleBarSwitchWidth(context);
        return Container(
          height: 22,
          constraints: BoxConstraints(minWidth: width),
          decoration: BoxDecoration(
            color: IdeButtonColors.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: IdeButtonColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                // The label's part fills what the chevron leaves.
                constraints: BoxConstraints(
                  minWidth: math.max(0, width - 2 - openInEditorChevronWidth),
                ),
                child: _Segment(
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
                  padding: EdgeInsets.only(
                    left: compact ? 6 : 8,
                    right: compact ? 4 : 6,
                  ),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(editor.icon, size: 16, color: foreground),
                      if (!compact) ...[
                        const SizedBox(width: 4),
                        Text(
                          editor.localizedPlatformLabel(context.l10n),
                          style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            height: 16 / 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // As IdeButton's split button has it.
              Container(
                width: 1,
                height: 14,
                color: foreground.withValues(alpha: 0.25),
              ),
              _Segment(
                semanticsLabel: context.l10n.workspaceChooseEditor,
                active: menu.isOpen,
                onTap: menu.open,
                padding: const EdgeInsets.only(left: 3, right: 4),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
                // As IdeButton's split button has it.
                child: Icon(Codicons.chevronDown, size: 14, color: foreground),
              ),
            ],
          ),
        );
      },
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
                color: active || hovered
                    ? IdeButtonColors.hoverBackground
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
