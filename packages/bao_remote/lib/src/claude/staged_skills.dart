import 'dart:typed_data';

import '../protocol.dart';

/// One file of a local user skill staged on a remote host for Claude Code.
class StagedSkillFile {
  const StagedSkillFile({
    required this.path,
    required this.bytes,
    this.executable = false,
  });

  factory StagedSkillFile.fromJson(Map<String, Object?> json) =>
      StagedSkillFile(
        path: json['path'] as String? ?? '',
        bytes: decodeBytes(json['data']),
        executable: json['executable'] == true,
      );

  /// Relative POSIX path inside the skill folder (e.g. `SKILL.md`,
  /// `scripts/check.sh`).
  final String path;
  final Uint8List bytes;
  final bool executable;

  Map<String, Object?> toJson() => {
    'path': path,
    'data': encodeBytes(bytes),
    if (executable) 'executable': true,
  };
}

/// One local user skill (its folder name, declared name and files) to
/// project into a temporary `--add-dir` on a remote host.
class StagedSkill {
  const StagedSkill({
    required this.directory,
    required this.name,
    required this.files,
  });

  factory StagedSkill.fromJson(Map<String, Object?> json) => StagedSkill(
    directory: json['directory'] as String? ?? '',
    name: json['name'] as String? ?? '',
    files: [
      for (final file in json['files'] as List? ?? const [])
        if (file is Map) StagedSkillFile.fromJson(file.cast<String, Object?>()),
    ],
  );

  /// The folder basename under `<config>/skills/`.
  final String directory;

  /// The skill's frontmatter `name`, or [directory] when unset.
  final String name;

  final List<StagedSkillFile> files;

  Map<String, Object?> toJson() => {
    'directory': directory,
    'name': name,
    'files': [for (final file in files) file.toJson()],
  };
}
