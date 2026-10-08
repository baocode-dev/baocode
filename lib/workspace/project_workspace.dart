import 'package:path/path.dart' as p;

import 'project_workspace_dir_stub.dart'
    if (dart.library.io) 'project_workspace_dir_io.dart'
    as platform;

/// A project of several folders, as VS Code's multi-root workspace: agents
/// started in it work across all of them, and the IDE shows each as a root
/// of its explorer and a repository of its Source Control.
///
/// It has a folder of its own in the data directory ([path]), which names
/// it as a project's path names a folder (the sidebar, what is kept, the
/// sessions Claude Code keeps there) and is where its agents start: their
/// [folders] are given to them besides. Only folders of this machine.
class ProjectWorkspace {
  const ProjectWorkspace({
    required this.id,
    required this.name,
    required this.path,
    this.folders = const [],
  });

  final String id;
  final String name;

  /// Its own folder: `<data dir>/workspaces/<id>`.
  final String path;

  /// The folders in it, in the order the user added them.
  final List<String> folders;

  ProjectWorkspace copyWith({String? name, List<String>? folders}) =>
      ProjectWorkspace(
        id: id,
        name: name ?? this.name,
        path: path,
        folders: folders ?? this.folders,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'folders': folders,
  };

  /// The workspace kept as [json]; its folder in [root] (the data
  /// directory moves, the id stays), else where it was kept.
  static ProjectWorkspace? fromJson(Object? json, {String? root}) =>
      switch (json) {
        {
          'id': final String id,
          'name': final String name,
          'path': final String path,
          'folders': final List<Object?> folders,
        } =>
          ProjectWorkspace(
            id: id,
            name: name,
            path: root == null ? path : p.join(root, id),
            folders: folders.whereType<String>().toList(),
          ),
        _ => null,
      };

  /// What the agent is told of it, after Claude Code's own prompt: that
  /// its work is in [folders], not the empty folder it starts in.
  String get systemPrompt {
    final listed = [
      for (final folder in folders) '- ${p.basename(folder)}: $folder',
    ].join('\n');
    return '''
<workspace>
You are working in the multi-folder workspace "$name". The user's files are in these folders (each also given to you with --add-dir), not in your working directory, which is only the workspace's own folder:
$listed

When the user refers to a file, a folder or "the project", look in these folders. Use absolute paths, or paths starting with one of these folders, for files in them. Run commands that act on one folder (git, builds, tests) in that folder.
</workspace>''';
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectWorkspace &&
      other.id == id &&
      other.name == name &&
      other.path == path &&
      _sameFolders(other.folders, folders);

  @override
  int get hashCode => Object.hash(id, name, path, Object.hashAll(folders));

  static bool _sameFolders(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Where workspaces' own folders are made, and what is written in them;
/// replaceable under test.
class ProjectWorkspaceDirectories {
  const ProjectWorkspaceDirectories();

  /// The folder that holds each workspace's own; null where there is none
  /// (the web).
  String? get root => platform.workspacesRoot();

  /// Makes [workspace]'s folder, with a `.code-workspace` file listing its
  /// folders (for VS Code and others to open it as such). Best effort: a
  /// workspace whose folder could not be made still lists.
  void write(ProjectWorkspace workspace) =>
      platform.writeWorkspaceDirectory(workspace);
}
