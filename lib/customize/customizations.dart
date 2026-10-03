// What Claude Code is customized with, as the Customize page lists it:
// skills, subagents, slash commands, rules (CLAUDE.md and `rules/`), MCP
// servers, hooks and plugins, each the user's own (under its config folder)
// or a project's (under `<project>/.claude/`). See customization_store.dart
// for where each is read from.

/// The kinds the page has a chip for, in its order.
enum CustomizationKind {
  plugins,
  mcps,
  skills,
  subagents,
  rules,
  commands,
  hooks;

  /// Kept as markdown files of their own, made from a template ([template])
  /// and edited as text.
  bool get creatable => switch (this) {
    skills || subagents || commands || rules => true,
    plugins || mcps || hooks => false,
  };

  /// Kept in a JSON file of [scope]'s meant to be edited by hand, among
  /// other settings: a project's `.mcp.json`, a settings file's hooks.
  bool configuredIn(CustomizationScope scope) => switch (this) {
    mcps => scope == CustomizationScope.project,
    hooks =>
      scope == CustomizationScope.user ||
          scope == CustomizationScope.project ||
          scope == CustomizationScope.local,
    _ => false,
  };

  /// What such a file starts as, where there is none yet.
  String get configTemplate => switch (this) {
    mcps => '{\n  "mcpServers": {}\n}\n',
    hooks => '{\n  "hooks": {}\n}\n',
    _ => '',
  };
}

/// Whose a customization is: the user's (every project's), synced to the
/// user from claude.ai, a project's (shared, in its repository), the
/// user's for a project alone (local, not shared), or a plugin's.
enum CustomizationScope { user, synced, project, local, plugin }

/// One skill, subagent, command, rule, server, hook or plugin.
class Customization {
  const Customization({
    required this.kind,
    required this.scope,
    required this.name,
    required this.path,
    this.description = '',
    this.editable = true,
    this.removePath,
    this.detail,
    this.enabled,
  });

  final CustomizationKind kind;
  final CustomizationScope scope;
  final String name;

  /// One line of what it is for: a markdown file's `description`, a
  /// server's command, a hook's.
  final String description;

  /// The file it is in: edited as text where [editable].
  final String path;

  /// Its file is its own, or one meant to be edited by hand (a project's
  /// `.mcp.json`, a settings file's hooks); not a file the CLI rewrites
  /// (`~/.claude.json`) or a plugin's.
  final bool editable;

  /// What deleting it removes: a skill's folder, a markdown file; null
  /// where it cannot be deleted here (a server or hook among others).
  final String? removePath;

  /// Shown in place of its file where that is not [editable]: e.g. a
  /// server's entry in `~/.claude.json`, as JSON. Where it is, what its
  /// file starts as if not there yet (a settings file opened for hooks).
  final String? detail;

  /// A plugin's: whether settings enable it.
  final bool? enabled;
}

/// The front matter of a markdown file (`---` lines around `key: value`
/// pairs), as far as names and descriptions go: one-line values, quoted or
/// not, and block scalars (`>`, `|`), folded into one line.
Map<String, String> parseFrontMatter(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return const {};
  final fields = <String, String>{};
  String? blockKey;
  final block = <String>[];
  void endBlock() {
    if (blockKey case final key?) fields[key] = block.join(' ').trim();
    blockKey = null;
    block.clear();
  }

  final pair = RegExp(r'^([A-Za-z0-9_-]+):\s*(.*)$');
  for (final line in lines.skip(1)) {
    if (line.trim() == '---') break;
    if (blockKey != null) {
      if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
        if (line.trim().isNotEmpty) block.add(line.trim());
        continue;
      }
      endBlock();
    }
    final match = pair.firstMatch(line);
    if (match == null) continue;
    final key = match.group(1)!;
    final value = match.group(2)!.trim();
    if (RegExp(r'^[>|][+-]?$').hasMatch(value)) {
      blockKey = key;
      continue;
    }
    fields[key] = _unquote(value);
  }
  endBlock();
  return fields;
}

String _unquote(String value) {
  if (value.length >= 2) {
    final first = value[0];
    if ((first == '"' || first == "'") && value.endsWith(first)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

/// The markdown after the front matter, if any.
String bodyOf(String text) {
  final normalized = text.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---')) return normalized;
  final end = normalized.indexOf('\n---', 3);
  if (end < 0) return normalized;
  final after = normalized.indexOf('\n', end + 4);
  return after < 0 ? '' : normalized.substring(after + 1);
}

/// What a markdown file says it is for: its `description`, else the first
/// line of its text that is not a heading.
String describeMarkdown(String text) {
  if (parseFrontMatter(text)['description'] case final description?
      when description.isNotEmpty) {
    return description;
  }
  for (final line in bodyOf(text).split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    return trimmed;
  }
  return '';
}

/// A name a new skill, subagent, command or rule can take: its file's or
/// folder's name too.
final RegExp customizationName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');

/// What a new one of [kind] named [name] starts as.
String template(CustomizationKind kind, String name) => switch (kind) {
  CustomizationKind.skills =>
    '---\n'
        'name: $name\n'
        'description: What this skill does, and when Claude should use it.\n'
        '---\n'
        '\n'
        '# $name\n'
        '\n'
        'Instructions Claude follows when it uses this skill.\n',
  CustomizationKind.subagents =>
    '---\n'
        'name: $name\n'
        'description: When Claude should hand a task to this subagent.\n'
        '---\n'
        '\n'
        'You are a subagent that…\n',
  CustomizationKind.commands =>
    '---\n'
        'description: What /$name does.\n'
        '---\n'
        '\n'
        'The prompt /$name sends. \$ARGUMENTS stands for what follows it.\n',
  CustomizationKind.rules => '# $name\n\n- A rule Claude keeps to.\n',
  CustomizationKind.plugins ||
  CustomizationKind.mcps ||
  CustomizationKind.hooks => '',
};
