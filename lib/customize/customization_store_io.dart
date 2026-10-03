import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import '../platform/local_paths_io.dart';
import 'customizations.dart';

/// Claude Code's customizations on disk: the user's under its config
/// folder (`~/.claude` unless moved), a project's under `<project>/.claude`
/// and the project's root (CLAUDE.md, `.mcp.json`).
class CustomizationStore {
  CustomizationStore({this.configDir, this.homeDir});

  /// Claude Code's config folder; by default as its kernel finds it (see
  /// [ClaudeEnvironment.configDir]).
  final String? configDir;

  /// The user's home, where `~/.claude.json` is when the config folder is
  /// the default one.
  final String? homeDir;

  /// Whether there are files to read and write here (not on the web).
  bool get supported => true;

  Future<String> config() async =>
      configDir ?? await ClaudeEnvironment.configDir();

  /// Where the CLI keeps its state and the user's MCP servers: beside the
  /// default config folder, inside one moved elsewhere.
  Future<String> _claudeJson() async {
    final config = await this.config();
    final home = homeDir ?? homeDirectory;
    if (home != null && p.equals(config, p.join(home, '.claude'))) {
      return p.join(home, '.claude.json');
    }
    return p.join(config, '.claude.json');
  }

  /// Those of [kind], the user's and [project]'s (none of a project's when
  /// null), by scope then name.
  Future<List<Customization>> list(
    CustomizationKind kind, {
    String? project,
  }) async {
    final config = await this.config();
    final dotClaude = project == null ? null : p.join(project, '.claude');
    final items = switch (kind) {
      CustomizationKind.skills => [
        ..._skills(CustomizationScope.user, p.join(config, 'skills')),
        if (dotClaude != null)
          ..._skills(CustomizationScope.project, p.join(dotClaude, 'skills')),
      ],
      CustomizationKind.subagents => [
        ..._markdown(kind, CustomizationScope.user, p.join(config, 'agents')),
        if (dotClaude != null)
          ..._markdown(
            kind,
            CustomizationScope.project,
            p.join(dotClaude, 'agents'),
          ),
      ],
      CustomizationKind.commands => [
        ..._markdown(kind, CustomizationScope.user, p.join(config, 'commands')),
        if (dotClaude != null)
          ..._markdown(
            kind,
            CustomizationScope.project,
            p.join(dotClaude, 'commands'),
          ),
      ],
      CustomizationKind.rules => _rules(config, project),
      CustomizationKind.mcps => await _servers(project),
      CustomizationKind.hooks => _hooks(config, project),
      CustomizationKind.plugins => _plugins(config, project),
    };
    // A copy: what a kind has none of may be a const list.
    return [...items]..sort((a, b) {
      final scope = a.scope.index.compareTo(b.scope.index);
      return scope != 0
          ? scope
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<String> read(String path) => File(path).readAsString();

  Future<bool> exists(String path) => File(path).exists();

  Future<void> write(String path, String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  /// Makes a new one of [kind] named [name] from its template: the user's,
  /// or [project]'s. Returns its file; throws a [FileSystemException] when
  /// one by that name is there already.
  Future<String> create(
    CustomizationKind kind,
    CustomizationScope scope,
    String name, {
    String? project,
  }) async {
    if (!kind.creatable || !customizationName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name');
    }
    final base = scope == CustomizationScope.user
        ? await config()
        : p.join(project!, '.claude');
    final path = switch (kind) {
      CustomizationKind.skills => p.join(base, 'skills', name, 'SKILL.md'),
      CustomizationKind.subagents => p.join(base, 'agents', '$name.md'),
      CustomizationKind.commands => p.join(base, 'commands', '$name.md'),
      _ => p.join(base, 'rules', '$name.md'),
    };
    final taken = kind == CustomizationKind.skills
        ? Directory(p.dirname(path)).existsSync()
        : File(path).existsSync();
    if (taken) throw FileSystemException('Already exists', path);
    await write(path, template(kind, name));
    return path;
  }

  /// The file [kind] is kept in for [scope], to be edited whole (see
  /// [CustomizationKind.configuredIn]): a project's `.mcp.json`, a settings
  /// file for hooks. Null where there is none (or no [project]).
  Future<String?> configFile(
    CustomizationKind kind,
    CustomizationScope scope, {
    String? project,
  }) async {
    if (!kind.configuredIn(scope)) return null;
    if (kind == CustomizationKind.mcps) {
      return project == null ? null : p.join(project, '.mcp.json');
    }
    for (final (own, path) in _settingsFiles(await config(), project)) {
      if (own == scope) return path;
    }
    return null;
  }

  /// Removes [item]'s file, or its folder (a skill's).
  Future<void> delete(Customization item) async {
    final path = item.removePath;
    if (path == null) return;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }

  // --- Reading ---------------------------------------------------------------

  static String? _readOrNull(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return null;
    }
  }

  static Map<String, Object?>? _json(String path) {
    final text = _readOrNull(path);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  static const _pretty = JsonEncoder.withIndent('  ');

  /// Each folder of [root] with a SKILL.md.
  /// Those synced from claude.ai: `synced/<bucket>/<skill>/` of the
  /// user's skills, which the next sync writes over.
  static const _synced = 'synced';

  static List<Customization> _skills(CustomizationScope scope, String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return const [];
    List<Directory> folders(Directory dir) => [
      for (final child
          in dir.listSync(followLinks: true).whereType<Directory>())
        if (!p.basename(child.path).startsWith('.')) child,
    ];
    final skills = <Customization>[];
    for (final folder in folders(dir)) {
      if (scope == CustomizationScope.user &&
          p.basename(folder.path) == _synced) {
        for (final bucket in folders(folder)) {
          for (final synced in folders(bucket)) {
            skills.addAll([?_skill(CustomizationScope.synced, synced.path)]);
          }
        }
      } else {
        skills.addAll([?_skill(scope, folder.path)]);
      }
    }
    return skills;
  }

  /// The skill in [folder], if it has a SKILL.md; one synced is shown, not
  /// edited or deleted here.
  static Customization? _skill(CustomizationScope scope, String folder) {
    final path = p.join(folder, 'SKILL.md');
    final text = _readOrNull(path);
    if (text == null) return null;
    final synced = scope == CustomizationScope.synced;
    return Customization(
      kind: CustomizationKind.skills,
      scope: scope,
      name: switch (parseFrontMatter(text)['name']) {
        final name? when name.isNotEmpty => name,
        _ => p.basename(folder),
      },
      description: describeMarkdown(text),
      path: path,
      editable: !synced,
      removePath: synced ? null : folder,
    );
  }

  /// The markdown files under [root], its folders' too.
  static List<Customization> _markdown(
    CustomizationKind kind,
    CustomizationScope scope,
    String root,
  ) {
    final dir = Directory(root);
    if (!dir.existsSync()) return const [];
    return [
      for (final file
          in dir.listSync(recursive: true, followLinks: true).whereType<File>())
        if (file.path.endsWith('.md'))
          if (_readOrNull(file.path) case final text?)
            Customization(
              kind: kind,
              scope: scope,
              name: _markdownName(kind, file.path, text),
              description: describeMarkdown(text),
              path: file.path,
              removePath: file.path,
            ),
    ];
  }

  /// A subagent's own name, else its file's; a command as it is typed.
  static String _markdownName(
    CustomizationKind kind,
    String path,
    String text,
  ) {
    final file = p.basenameWithoutExtension(path);
    if (kind == CustomizationKind.commands) return '/$file';
    return switch (parseFrontMatter(text)['name']) {
      final name? when name.isNotEmpty => name,
      _ => file,
    };
  }

  /// The memory files Claude Code reads: CLAUDE.md, the user's and the
  /// project's, CLAUDE.local.md, and each file of a `rules/` folder.
  static List<Customization> _rules(String config, String? project) {
    Customization? memory(CustomizationScope scope, String path, String base) {
      final text = _readOrNull(path);
      if (text == null) return null;
      return Customization(
        kind: CustomizationKind.rules,
        scope: scope,
        name: p.relative(path, from: base),
        description: describeMarkdown(text),
        path: path,
      );
    }

    List<Customization> folder(
      CustomizationScope scope,
      String root,
      String base,
    ) => [
      for (final rule in _markdown(CustomizationKind.rules, scope, root))
        Customization(
          kind: rule.kind,
          scope: rule.scope,
          name: p.relative(rule.path, from: base),
          description: rule.description,
          path: rule.path,
          removePath: rule.removePath,
        ),
    ];

    return [
      ?memory(CustomizationScope.user, p.join(config, 'CLAUDE.md'), config),
      ...folder(CustomizationScope.user, p.join(config, 'rules'), config),
      if (project != null) ...[
        ?memory(
          CustomizationScope.project,
          p.join(project, 'CLAUDE.md'),
          project,
        ),
        ?memory(
          CustomizationScope.project,
          p.join(project, '.claude', 'CLAUDE.md'),
          project,
        ),
        ...folder(
          CustomizationScope.project,
          p.join(project, '.claude', 'rules'),
          project,
        ),
        ?memory(
          CustomizationScope.local,
          p.join(project, 'CLAUDE.local.md'),
          project,
        ),
      ],
    ];
  }

  /// The MCP servers: the user's and the project's private ones, in
  /// `~/.claude.json` (which the CLI rewrites: shown, not edited), the
  /// project's shared ones in its `.mcp.json`, and the claude.ai
  /// connectors the CLI has reached through the user's account (which it
  /// keeps the names of alone).
  Future<List<Customization>> _servers(String? project) async {
    final claudeJson = await _claudeJson();
    final state = _json(claudeJson);
    List<Customization> servers(
      CustomizationScope scope,
      Object? entries,
      String path, {
      required bool editable,
    }) => [
      if (entries is Map<String, Object?>)
        for (final MapEntry(key: name, value: server) in entries.entries)
          Customization(
            kind: CustomizationKind.mcps,
            scope: scope,
            name: name,
            description: _describeServer(server),
            path: path,
            editable: editable,
            detail: _pretty.convert({name: server}),
          ),
    ];

    final projects = state?['projects'];
    final mcpJson = project == null ? null : p.join(project, '.mcp.json');
    return [
      ...servers(
        CustomizationScope.user,
        state?['mcpServers'],
        claudeJson,
        editable: false,
      ),
      if (state?['claudeAiMcpEverConnected'] case final List<Object?> names)
        for (final name in names.whereType<String>().toSet())
          Customization(
            kind: CustomizationKind.mcps,
            scope: CustomizationScope.synced,
            name: name,
            description: 'claude.ai',
            path: claudeJson,
            editable: false,
            detail: _pretty.convert({
              name: {'source': 'claude.ai'},
            }),
          ),
      if (project != null && projects is Map<String, Object?>)
        ...servers(
          CustomizationScope.local,
          (projects[project] as Map<String, Object?>?)?['mcpServers'],
          claudeJson,
          editable: false,
        ),
      if (mcpJson != null)
        ...servers(
          CustomizationScope.project,
          _json(mcpJson)?['mcpServers'],
          mcpJson,
          editable: true,
        ),
    ];
  }

  /// `command args…`, or the URL a remote server is at.
  static String _describeServer(Object? server) {
    if (server is! Map<String, Object?>) return '';
    if (server['url'] case final String url) {
      return switch (server['type']) {
        final String type => '$type · $url',
        _ => url,
      };
    }
    return [
      if (server['command'] case final String command) command,
      if (server['args'] case final List<Object?> args)
        for (final arg in args) '$arg',
    ].join(' ');
  }

  /// The settings files: the user's, the project's and its local one.
  static List<(CustomizationScope, String)> _settingsFiles(
    String config,
    String? project,
  ) => [
    (CustomizationScope.user, p.join(config, 'settings.json')),
    if (project != null) ...[
      (CustomizationScope.project, p.join(project, '.claude', 'settings.json')),
      (
        CustomizationScope.local,
        p.join(project, '.claude', 'settings.local.json'),
      ),
    ],
  ];

  /// Each hook of the settings files, by event and matcher; its file is
  /// edited whole.
  static List<Customization> _hooks(String config, String? project) => [
    for (final (scope, path) in _settingsFiles(config, project))
      if (_json(path)?['hooks'] case final Map<String, Object?> events)
        for (final MapEntry(key: event, value: groups) in events.entries)
          if (groups is List<Object?>)
            for (final group in groups.whereType<Map<String, Object?>>())
              for (final hook
                  in (group['hooks'] as List<Object?>? ?? const [])
                      .whereType<Map<String, Object?>>())
                Customization(
                  kind: CustomizationKind.hooks,
                  scope: scope,
                  name: switch (group['matcher']) {
                    final String matcher when matcher.isNotEmpty =>
                      '$event · $matcher',
                    _ => event,
                  },
                  description: switch (hook['command'] ?? hook['prompt']) {
                    final String command => command,
                    _ => '${hook['type'] ?? ''}',
                  },
                  path: path,
                ),
  ];

  /// The plugins installed (`plugins/installed_plugins.json`), and whether
  /// the settings enable each.
  static List<Customization> _plugins(String config, String? project) {
    final installed = _json(
      p.join(config, 'plugins', 'installed_plugins.json'),
    );
    final plugins = installed?['plugins'];
    if (plugins is! Map<String, Object?>) return const [];
    final enabled = <String, bool>{};
    for (final (_, path) in _settingsFiles(config, project)) {
      if (_json(path)?['enabledPlugins'] case final Map<String, Object?> map) {
        for (final MapEntry(:key, :value) in map.entries) {
          if (value is bool) enabled[key] = value;
        }
      }
    }
    return [
      for (final MapEntry(key: id, value: entry) in plugins.entries)
        if (switch (entry) {
              // Version 2 lists each install; version 1 has the one.
              final List<Object?> installs =>
                installs.whereType<Map<String, Object?>>().firstOrNull,
              final Map<String, Object?> install => install,
              _ => null,
            }
            case final install?)
          _plugin(id, install, enabled[id] ?? false),
    ];
  }

  static Customization _plugin(
    String id,
    Map<String, Object?> install,
    bool enabled,
  ) {
    final root = install['installPath'] as String?;
    final manifestPath = root == null
        ? null
        : p.join(root, '.claude-plugin', 'plugin.json');
    final manifest = manifestPath == null ? null : _json(manifestPath);
    final at = id.indexOf('@');
    return Customization(
      kind: CustomizationKind.plugins,
      scope: CustomizationScope.plugin,
      name: at < 0 ? id : id.substring(0, at),
      description: switch (manifest?['description']) {
        final String description => description,
        _ => [
          if (at >= 0) id.substring(at + 1),
          if (install['version'] case final String version) version,
        ].join(' · '),
      },
      path: manifestPath ?? root ?? id,
      editable: false,
      detail: _pretty.convert({
        id: {...install, 'enabled': enabled},
      }),
      enabled: enabled,
    );
  }
}
