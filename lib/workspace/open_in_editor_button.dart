import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../sidebar/sidebar_menu.dart';
import '../theme/cursor_theme.dart';
import 'editor_launcher.dart';
import 'workspace.dart';

/// Split button for the title bar: opens [project] in the preferred editor;
/// its chevron picks another one (which becomes the preferred), or copies
/// the path.
class OpenInEditorButton extends StatelessWidget {
  const OpenInEditorButton({
    super.key,
    required this.workspace,
    required this.project,
  });

  final Workspace workspace;
  final Project project;

  void _open(Editor editor) {
    workspace.preferredEditor = editor;
    openInEditor(editor, project.path);
  }

  @override
  Widget build(BuildContext context) {
    final editor = workspace.preferredEditor;
    return SidebarMenu(
      width: 200,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      items: () => [
        for (final option in Editor.availableEditors)
          SidebarMenuItem(
            option.platformLabel,
            icon: option.icon,
            checked: option == workspace.preferredEditor,
            onSelected: () => _open(option),
          ),
        SidebarMenuItem(
          'Copy path',
          icon: Icons.content_copy_rounded,
          onSelected: () =>
              Clipboard.setData(ClipboardData(text: project.path)),
        ),
      ],
      builder: (context, menu) => Container(
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: CursorColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              semanticsLabel: 'Open in ${editor.platformLabel}',
              onTap: () => _open(editor),
              padding: const EdgeInsets.only(left: 7, right: 7),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(editor.icon, size: 13, color: CursorColors.textMuted),
                  const SizedBox(width: 5),
                  Text(
                    editor.platformLabel,
                    style: const TextStyle(
                      color: CursorColors.text,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: CursorColors.border),
            _Segment(
              semanticsLabel: 'Choose editor',
              active: menu.isOpen,
              onTap: menu.open,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(5),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: CursorColors.textMuted,
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
    this.active = false,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
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
              color: hovered || active
                  ? CursorColors.hover
                  : Colors.transparent,
              borderRadius: borderRadius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
