import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'composer_files.dart';

/// [child], to drag [files] from onto the composer (the IDE's explorer
/// rows, its tabs…), as files are dragged in from other apps.
class FileDraggable extends StatelessWidget {
  const FileDraggable({super.key, required this.files, required this.child});

  final List<ComposerFile> files;
  final Widget child;

  @override
  Widget build(BuildContext context) => Draggable<FileDragData>(
    data: FileDragData(files),
    // The composer places what is let go at the pointer.
    dragAnchorStrategy: pointerDragAnchorStrategy,
    feedback: _Feedback(files),
    child: child,
  );
}

/// What follows the pointer: a tag of the first file, beside it.
class _Feedback extends StatelessWidget {
  const _Feedback(this.files);

  final List<ComposerFile> files;

  @override
  Widget build(BuildContext context) {
    final first = files.first;
    return Transform.translate(
      offset: const Offset(14, 6),
      child: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: .9,
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 2, 6, 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: themeColors['chat.requestBorder']),
              boxShadow: [
                BoxShadow(
                  color: themeColors['widget.shadow'],
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (first.directory)
                  FolderIcon(first.name, size: 14)
                else
                  FileIcon(first.name, size: 15),
                const SizedBox(width: 5),
                Text(
                  files.length == 1
                      ? first.name
                      : '${first.name} +${files.length - 1}',
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
