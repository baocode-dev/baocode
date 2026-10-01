import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';

/// The file's Material Icon Theme icon, followed by the file name.
class FileLabel extends StatelessWidget {
  const FileLabel(this.fileName, {super.key, this.fontSize = 12.5});

  final String fileName;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FileIcon(fileName, size: fontSize + 3),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.text, fontSize: fontSize),
          ),
        ),
      ],
    );
  }
}
