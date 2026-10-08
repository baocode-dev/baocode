import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import 'project_workspace.dart';

String? workspacesRoot() => DataDirectory.current.workspacesDir;

void writeWorkspaceDirectory(ProjectWorkspace workspace) {
  try {
    final directory = Directory(workspace.path)..createSync(recursive: true);
    // Its name is the file's: one file, renamed with the workspace.
    final name = '${_fileName(workspace.name)}.code-workspace';
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is File &&
          entity.path.endsWith('.code-workspace') &&
          p.basename(entity.path) != name) {
        entity.deleteSync();
      }
    }
    File(p.join(directory.path, name)).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'folders': [
          for (final folder in workspace.folders) {'path': folder},
        ],
      })}\n',
    );
  } on FileSystemException {
    // Listed all the same; made again when next changed.
  }
}

/// [name] as a file's name: what no file system takes, replaced.
String _fileName(String name) {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-').trim();
  return safe.isEmpty || safe.startsWith('.') ? 'workspace' : safe;
}
