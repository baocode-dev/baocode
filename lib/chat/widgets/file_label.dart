import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

/// File icon tinted by extension, followed by the file name.
class FileLabel extends StatelessWidget {
  const FileLabel(this.fileName, {super.key, this.fontSize = 12.5});

  final String fileName;
  final double fontSize;

  static Color tint(String fileName) {
    final extension = fileName.split('.').last;
    return switch (extension) {
      'dart' => const Color(0xFF4FC3F7),
      'yaml' || 'yml' => const Color(0xFFE57373),
      'json' => const Color(0xFFFFD54F),
      'md' => const Color(0xFF90A4AE),
      _ => CursorColors.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.description_outlined,
          size: fontSize + 1,
          color: tint(fileName),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: CursorColors.text, fontSize: fontSize),
          ),
        ),
      ],
    );
  }
}
