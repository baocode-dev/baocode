import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_remote/client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import '../customize/customizations.dart' show parseFrontMatter;
import '../kernel/claude_code/claude_environment.dart';
import '../stash/stash_skill.dart';

/// Whether local user-level skills (`~/.claude/skills`) are projected into a
/// temporary directory on remote SSH/WSL hosts for remote kernels: the
/// `remote.shareUserSkills` setting, on unless turned off.
abstract final class RemoteSkillsSetting {
  static const settingKey = 'remote.shareUserSkills';

  /// Written when off; on, the setting is left out.
  static const off = false;

  /// On unless set to false.
  static bool enabled(Object? setting) => setting != false;

  /// The setting as it is now; main() points it at settings.json.
  static bool Function() current = () => true;
}

/// Collects local user-level skills and projects them onto a remote host's
/// temporary runtime directory so both Claude Code CLI and BaoCode's built-in
/// core can load them via `--add-dir` without modifying `~/.claude/skills/`
/// on the remote host.
abstract final class RemoteSkills {
  /// Size limits so staging stays lightweight (especially on RAM-backed
  /// `/dev/shm` or `XDG_RUNTIME_DIR`).
  static const maxFileBytes = 1024 * 1024;
  static const maxSkillBytes = 2 * 1024 * 1024;
  static const maxTotalBytes = 8 * 1024 * 1024;

  /// Directories and files skipped when collecting a skill folder.
  static const ignoredEntries = {
    '.git',
    'node_modules',
    '.DS_Store',
    '__pycache__',
    '.venv',
    'venv',
    'build',
    '.dart_tool',
    'Thumbs.db',
  };

  /// Collects shareable local user-level skills from `<configDir>/skills/`
  /// (defaulting to [ClaudeEnvironment.configDir]) together with a
  /// deterministic content hash.
  static Future<({String hash, List<StagedSkill> skills})> collectLocal({
    String? configDir,
  }) async {
    final config = configDir ?? await ClaudeEnvironment.configDir();
    if (config.isEmpty) return const (hash: '', skills: <StagedSkill>[]);
    final root = Directory(p.join(config, 'skills'));
    if (!root.existsSync()) return const (hash: '', skills: <StagedSkill>[]);

    List<FileSystemEntity> entries;
    try {
      entries = root.listSync(followLinks: false);
    } on FileSystemException {
      return const (hash: '', skills: <StagedSkill>[]);
    }
    entries.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    final skills = <StagedSkill>[];
    var totalBytes = 0;

    for (final entry in entries) {
      final dirName = p.basename(entry.path);
      if (dirName.isEmpty || ignoredEntries.contains(dirName)) continue;
      final isDir =
          entry is Directory ||
          (entry is Link && FileSystemEntity.isDirectorySync(entry.path));
      if (!isDir) continue;

      final skillDir = Directory(entry.path);
      final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
      if (!skillFile.existsSync()) continue;

      final Uint8List skillBytes;
      try {
        final stat = skillFile.statSync();
        if (stat.size > maxFileBytes) continue;
        skillBytes = await skillFile.readAsBytes();
      } on FileSystemException {
        continue;
      }

      final skillText = utf8.decode(skillBytes, allowMalformed: true);
      // BaoCode's Stash skill hardcodes local machine paths that do not exist
      // on the remote host.
      if (dirName == StashSkill.name && skillText.contains(StashSkill.marker)) {
        continue;
      }

      final front = parseFrontMatter(skillText);
      final declared = front['name']?.trim();
      final skillName = declared != null && declared.isNotEmpty
          ? declared
          : dirName;

      final files = <StagedSkillFile>[];
      final visitedDirs = <String>{};
      var skillBytesCount = 0;
      try {
        visitedDirs.add(skillDir.resolveSymbolicLinksSync());
      } on FileSystemException {
        // Unresolvable root link: skip.
        continue;
      }

      await _walkSkill(
        dir: skillDir,
        prefix: '',
        visitedDirs: visitedDirs,
        files: files,
        budgetRemaining: () =>
            (maxSkillBytes - skillBytesCount).clamp(0, maxSkillBytes),
        onAdded: (size) => skillBytesCount += size,
      );

      if (!files.any((f) => f.path == 'SKILL.md')) continue;
      if (totalBytes + skillBytesCount > maxTotalBytes) continue;

      files.sort((a, b) => a.path.compareTo(b.path));
      totalBytes += skillBytesCount;
      skills.add(StagedSkill(directory: dirName, name: skillName, files: files));
    }

    if (skills.isEmpty) return const (hash: '', skills: <StagedSkill>[]);
    return (hash: _hashSkills(skills), skills: skills);
  }

  static Future<void> _walkSkill({
    required Directory dir,
    required String prefix,
    required Set<String> visitedDirs,
    required List<StagedSkillFile> files,
    required int Function() budgetRemaining,
    required void Function(int size) onAdded,
  }) async {
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    children.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (final child in children) {
      final name = p.basename(child.path);
      if (name.isEmpty || ignoredEntries.contains(name)) continue;
      final relPath = prefix.isEmpty ? name : '$prefix/$name';

      final FileSystemEntityType type;
      try {
        type = FileSystemEntity.typeSync(child.path, followLinks: true);
      } on FileSystemException {
        continue;
      }

      if (type == FileSystemEntityType.directory) {
        final String resolved;
        try {
          resolved = Directory(child.path).resolveSymbolicLinksSync();
        } on FileSystemException {
          continue;
        }
        if (!visitedDirs.add(resolved)) continue;
        await _walkSkill(
          dir: Directory(child.path),
          prefix: relPath,
          visitedDirs: visitedDirs,
          files: files,
          budgetRemaining: budgetRemaining,
          onAdded: onAdded,
        );
      } else if (type == FileSystemEntityType.file) {
        final file = File(child.path);
        try {
          final stat = file.statSync();
          if (stat.size > maxFileBytes || stat.size > budgetRemaining()) {
            continue;
          }
          final bytes = await file.readAsBytes();
          if (bytes.length > maxFileBytes || bytes.length > budgetRemaining()) {
            continue;
          }
          final executable = !Platform.isWindows && (stat.mode & 0x49) != 0;
          files.add(
            StagedSkillFile(
              path: relPath,
              bytes: bytes,
              executable: executable,
            ),
          );
          onAdded(bytes.length);
        } on FileSystemException {
          continue;
        }
      }
    }
  }

  static String _hashSkills(List<StagedSkill> skills) {
    final buffer = BytesBuilder(copy: false);
    void writeText(String s) {
      final encoded = utf8.encode(s);
      buffer
        ..add(encoded)
        ..addByte(0);
    }

    for (final skill in skills) {
      writeText('S:${skill.directory}:${skill.name}');
      for (final file in skill.files) {
        writeText('F:${file.path}:${file.executable ? 1 : 0}');
        buffer
          ..add(file.bytes)
          ..addByte(0);
      }
    }
    return sha256.convert(buffer.takeBytes()).toString();
  }

  /// Stages local user-level skills onto [client] if [RemoteSkillsSetting] is
  /// enabled, returning the temporary `--add-dir` root path on the remote host
  /// (or null when disabled, empty, all overridden by remote skills, or on
  /// non-fatal failure).
  static Future<String?> stageFor(
    RemoteClient client, {
    String? configDir,
  }) async {
    if (!RemoteSkillsSetting.current()) return null;
    try {
      final bundle = await collectLocal(configDir: configDir);
      if (bundle.skills.isEmpty) return null;
      final check = await client.stageClaudeSkills(hash: bundle.hash);
      if (!check.missing) return check.root;
      final staged = await client.stageClaudeSkills(
        hash: bundle.hash,
        skills: bundle.skills,
      );
      return staged.root;
    } on RpcClosed {
      rethrow;
    } on Object catch (error) {
      debugPrint('Remote user skills not staged: $error');
      return null;
    }
  }
}
