import 'dart:io';

import 'package:path/path.dart' as p;

import '../claude/claude_environment.dart';
import '../claude/claude_settings_file.dart';
import '../claude/staged_skills.dart';

/// Projects the app's local user-level skills into a private, temporary
/// directory on the remote host (in RAM where `/dev/shm` or
/// `XDG_RUNTIME_DIR` is available, matching [ClaudeSettingsFile]) so both
/// Claude Code CLI and BaoCode's built-in core load them via `--add-dir`
/// without touching `~/.claude/skills/` on disk.
///
/// Any skill whose folder name or declared frontmatter `name` already exists
/// in the remote host's own user skills directory is skipped so host-specific
/// customizations always win.
///
/// Previously staged directories for this server session stay alive until
/// [dispose] (connection shutdown) so already-running agent processes never
/// lose their `--add-dir` when local skills change.
class ServerSkills {
  ServerSkills({
    Future<String> Function()? configDir,
    this.parent,
  }) : _configDir = configDir ?? ClaudeEnvironment.configDir;

  final Future<String> Function() _configDir;
  final Directory Function()? parent;

  final List<Directory> _created = [];
  String? _currentKey;
  Directory? _currentDir;
  bool _currentEmpty = false;

  /// Handles `claude/stageSkills`:
  /// - `{hash}` (no `skills` key): checks whether the server already holds an
  ///   up-to-date staged directory for [hash] and the current remote user
  ///   skills. Answers `{root}` when cached, or `{missing: true}` when the
  ///   client should upload the skills.
  /// - `{hash, skills}`: materializes the non-conflicting skills into a fresh
  ///   temporary root containing `.claude/skills/<dir>/...` and answers
  ///   `{root}` (or `{root: null}` when nothing was staged).
  Future<Map<String, Object?>> stage(Map<String, Object?> args) async {
    final hash = args['hash'] as String? ?? '';
    final remoteNames = await _remoteSkillNames();
    final key = _effectiveKey(hash, remoteNames);

    if (!args.containsKey('skills') || args['skills'] == null) {
      if (_currentKey == key) {
        if (_currentEmpty) return const {'root': null};
        final dir = _currentDir;
        if (dir != null && dir.existsSync()) return {'root': dir.path};
      }
      return const {'missing': true};
    }

    final rawSkills = args['skills'] as List? ?? const [];
    final skills = <StagedSkill>[];
    final seenDirs = <String>{};
    for (final entry in rawSkills) {
      if (entry is! Map) continue;
      final skill = StagedSkill.fromJson(entry.cast<String, Object?>());
      if (!_isSafeSegment(skill.directory)) continue;
      if (seenDirs.contains(skill.directory)) continue;
      if (remoteNames.contains(skill.directory) ||
          (skill.name.isNotEmpty && remoteNames.contains(skill.name))) {
        continue;
      }
      final hasSkillMd = skill.files.any((f) => f.path == 'SKILL.md');
      if (!hasSkillMd) continue;
      seenDirs.add(skill.directory);
      skills.add(skill);
    }

    if (skills.isEmpty) {
      _currentKey = key;
      _currentDir = null;
      _currentEmpty = true;
      return const {'root': null};
    }

    final root = _createTempRoot();
    _created.add(root);
    final executables = <String>[];
    try {
      final skillsBase = p.join(root.path, '.claude', 'skills');
      for (final skill in skills) {
        final skillRoot = p.join(skillsBase, skill.directory);
        for (final file in skill.files) {
          final segments = _safeRelativeSegments(file.path);
          if (segments == null) continue;
          final target = File(p.joinAll([skillRoot, ...segments]));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(file.bytes, flush: true);
          if (file.executable && !Platform.isWindows) {
            executables.add(target.path);
          }
        }
      }
      if (executables.isNotEmpty) {
        try {
          await Process.run('chmod', ['+x', ...executables]);
        } on Object {
          // Best effort: scripts can still be invoked via an interpreter.
        }
      }
    } on Object {
      _created.remove(root);
      await _deleteQuietly(root);
      rethrow;
    }

    _currentKey = key;
    _currentDir = root;
    _currentEmpty = false;
    return {'root': root.path};
  }

  /// Removes every temporary skills root created during this server's life.
  Future<void> dispose() async {
    final dirs = [..._created];
    _created.clear();
    _currentKey = null;
    _currentDir = null;
    _currentEmpty = false;
    for (final dir in dirs) {
      await _deleteQuietly(dir);
    }
  }

  Directory _createTempRoot() {
    final preferred = parent?.call() ?? ClaudeSettingsFile.parent;
    if (preferred != null) {
      try {
        return preferred.createTempSync('baocode-skills-');
      } on FileSystemException {
        // Fall back to system temp (e.g. /dev/shm unavailable or full).
      }
    }
    final fallback = Directory(Directory.systemTemp.resolveSymbolicLinksSync());
    return fallback.createTempSync('baocode-skills-');
  }

  Future<Set<String>> _remoteSkillNames() async {
    final String config;
    try {
      config = await _configDir();
    } on Object {
      return const {};
    }
    if (config.isEmpty) return const {};
    final dir = Directory(p.join(config, 'skills'));
    if (!dir.existsSync()) return const {};
    final names = <String>{};
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: true);
    } on FileSystemException {
      return const {};
    }
    for (final entry in entries) {
      final isDir =
          entry is Directory ||
          (entry is Link && FileSystemEntity.isDirectorySync(entry.path));
      if (!isDir) continue;
      final folderName = p.basename(entry.path);
      final skillFile = File(p.join(entry.path, 'SKILL.md'));
      if (!skillFile.existsSync()) continue;
      names.add(folderName);
      try {
        final declared = _frontmatterName(skillFile.readAsStringSync());
        if (declared != null && declared.isNotEmpty) names.add(declared);
      } on FileSystemException {
        // Folder name alone still prevents shadowing.
      }
    }
    return names;
  }

  static String _effectiveKey(String hash, Set<String> remoteNames) {
    if (remoteNames.isEmpty) return hash;
    final sorted = remoteNames.toList()..sort();
    return '$hash|${sorted.join('\n')}';
  }

  static bool _isSafeSegment(String segment) =>
      segment.isNotEmpty &&
      segment != '.' &&
      segment != '..' &&
      !segment.contains('/') &&
      !segment.contains(r'\') &&
      !segment.contains('\x00') &&
      !segment.contains(':');

  static List<String>? _safeRelativeSegments(String relPath) {
    if (relPath.isEmpty ||
        relPath.startsWith('/') ||
        relPath.contains(r'\') ||
        relPath.contains('\x00')) {
      return null;
    }
    final segments = relPath.split('/');
    for (final segment in segments) {
      if (!_isSafeSegment(segment)) return null;
    }
    return segments;
  }

  static String? _frontmatterName(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return null;
    final pattern = RegExp(r'^name:\s*(.+)$');
    for (final line in lines.skip(1)) {
      if (line.trim() == '---') break;
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2) {
        final first = value[0];
        if ((first == '"' || first == "'") && value.endsWith(first)) {
          value = value.substring(1, value.length - 1);
        }
      }
      return value.isEmpty ? null : value;
    }
    return null;
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Gone already.
    }
  }
}
