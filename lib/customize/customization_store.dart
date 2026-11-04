import 'dart:convert';

import 'package:bao_remote/files.dart'
    show IdeFileExistsException, IdeFileNotFoundException;
import 'package:path/path.dart' as p;

import 'customization_disk.dart';
import 'customizations.dart';

/// Claude Code's customizations on a [CustomizationDisk] (this machine's,
/// or a remote host's): the user's under its config folder (`~/.claude`
/// unless moved), a project's under `<project>/.claude` and the project's
/// root (CLAUDE.md, `.mcp.json`).
class CustomizationStore {
  CustomizationStore({this.configDir, this.homeDir, CustomizationDisk? disk})
    : _disk = disk ?? CustomizationDisk.local;

  /// Claude Code's config folder; by default as the disk's finds it.
  final String? configDir;

  /// The user's home, where `~/.claude.json` is when the config folder is
  /// the default one; by default the disk's.
  final String? homeDir;

  final CustomizationDisk? _disk;

  CustomizationDisk get _files =>
      _disk ?? (throw UnsupportedError('No files on the web'));

  p.Context get _paths => _files.paths;

  /// Whether there are files to read and write here (not on the web).
  bool get supported => _disk != null;

  /// Whether the files are this machine's (not a remote host's): shown in
  /// its file manager, opened in its IDE.
  bool get isLocal => _disk?.isLocal ?? true;

  /// How paths are spelled where the files are.
  p.Context get paths => _disk == null ? p.context : _paths;

  Future<String> config() async => configDir ?? await _files.configDir();

  /// Where the CLI keeps its state and the user's MCP servers: beside the
  /// default config folder, inside one moved elsewhere.
  Future<String> _claudeJson() async {
    final config = await this.config();
    final home = homeDir ?? await _files.homeDir();
    if (home != null && _paths.equals(config, _paths.join(home, '.claude'))) {
      return _paths.join(home, '.claude.json');
    }
    return _paths.join(config, '.claude.json');
  }

  /// Those of [kind], the user's and [project]'s (none of a project's when
  /// null), by scope then name.
  Future<List<Customization>> list(
    CustomizationKind kind, {
    String? project,
  }) async {
    if (!supported) return const [];
    final config = await this.config();
    final dotClaude = project == null ? null : _paths.join(project, '.claude');
    final items = switch (kind) {
      CustomizationKind.skills => [
        ...await _skills(
          CustomizationScope.user,
          _paths.join(config, 'skills'),
        ),
        if (dotClaude != null)
          ...await _skills(
            CustomizationScope.project,
            _paths.join(dotClaude, 'skills'),
          ),
      ],
      CustomizationKind.subagents => [
        ...await _markdown(
          kind,
          CustomizationScope.user,
          _paths.join(config, 'agents'),
        ),
        if (dotClaude != null)
          ...await _markdown(
            kind,
            CustomizationScope.project,
            _paths.join(dotClaude, 'agents'),
          ),
      ],
      CustomizationKind.commands => [
        ...await _markdown(
          kind,
          CustomizationScope.user,
          _paths.join(config, 'commands'),
        ),
        if (dotClaude != null)
          ...await _markdown(
            kind,
            CustomizationScope.project,
            _paths.join(dotClaude, 'commands'),
          ),
      ],
      CustomizationKind.rules => await _rules(config, project),
      CustomizationKind.mcps => await _servers(project),
      CustomizationKind.hooks => await _hooks(config, project),
      CustomizationKind.plugins => await _plugins(config, project),
    };
    // A copy: what a kind has none of may be a const list.
    return [...items]..sort((a, b) {
      final scope = a.scope.index.compareTo(b.scope.index);
      return scope != 0
          ? scope
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  /// The file of the `/command` [name] as Claude Code lists it: a skill's
  /// SKILL.md or a command's markdown, the user's, [project]'s or a
  /// plugin's (`plugin:name`); null for none (one built in).
  Future<String?> commandFile(String name, {String? project}) async {
    if (!supported) return null;
    final colon = name.indexOf(':');
    if (colon > 0) {
      return _pluginCommandFile(
        name.substring(0, colon),
        name.substring(colon + 1),
      );
    }
    for (final skill in await list(
      CustomizationKind.skills,
      project: project,
    )) {
      if (skill.name == name ||
          _paths.basename(_paths.dirname(skill.path)) == name) {
        return skill.path;
      }
    }
    for (final command in await list(
      CustomizationKind.commands,
      project: project,
    )) {
      if (command.name == '/$name') return command.path;
    }
    return null;
  }

  /// Plugin [plugin]'s skill or command [name], where it is installed.
  Future<String?> _pluginCommandFile(String plugin, String name) async {
    final installed = await _json(
      _paths.join(await config(), 'plugins', 'installed_plugins.json'),
    );
    if (installed?['plugins'] case final Map<String, Object?> plugins) {
      for (final MapEntry(key: id, value: entry) in plugins.entries) {
        final at = id.indexOf('@');
        if ((at < 0 ? id : id.substring(0, at)) != plugin) continue;
        final install = switch (entry) {
          final List<Object?> installs =>
            installs.whereType<Map<String, Object?>>().firstOrNull,
          final Map<String, Object?> install => install,
          _ => null,
        };
        if (install?['installPath'] case final String root) {
          for (final path in [
            _paths.join(root, 'skills', name, 'SKILL.md'),
            _paths.join(root, 'commands', '$name.md'),
          ]) {
            if (await _files.read(path) != null) return path;
          }
        }
      }
    }
    return null;
  }

  Future<String> read(String path) async =>
      await _files.read(path) ?? (throw IdeFileNotFoundException(path));

  Future<bool> exists(String path) async =>
      await _files.isDirectory(path) == false;

  Future<void> write(String path, String text) => _files.write(path, text);

  /// Makes a new one of [kind] named [name] from its template: the user's,
  /// or [project]'s. Returns its file; throws an [IdeFileExistsException]
  /// when one by that name is there already.
  Future<String> create(
    CustomizationKind kind,
    CustomizationScope scope,
    String name, {
    String? project,
  }) async {
    if (!kind.creatable || !isCustomizationName(name)) {
      throw ArgumentError.value(name, 'name');
    }
    final base = scope == CustomizationScope.user
        ? await config()
        : _paths.join(project!, '.claude');
    final path = switch (kind) {
      CustomizationKind.skills => _paths.join(base, 'skills', name, 'SKILL.md'),
      CustomizationKind.subagents => _paths.join(base, 'agents', '$name.md'),
      CustomizationKind.commands => _paths.join(base, 'commands', '$name.md'),
      _ => _paths.join(base, 'rules', '$name.md'),
    };
    final taken = kind == CustomizationKind.skills
        ? await _files.isDirectory(_paths.dirname(path)) != null
        : await _files.isDirectory(path) != null;
    if (taken) throw IdeFileExistsException(path);
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
    if (!kind.configuredIn(scope) || !supported) return null;
    if (kind == CustomizationKind.mcps) {
      return project == null ? null : _paths.join(project, '.mcp.json');
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
    await _files.delete(path);
  }

  // --- Reading ---------------------------------------------------------------

  Future<Map<String, Object?>?> _json(String path) async {
    final text = await _files.read(path);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  static const _pretty = JsonEncoder.withIndent('  ');

  /// Those synced from claude.ai: `synced/<bucket>/<skill>/` of the
  /// user's skills, which the next sync writes over.
  static const _synced = 'synced';

  /// Each folder of [root] with a SKILL.md.
  Future<List<Customization>> _skills(
    CustomizationScope scope,
    String root,
  ) async {
    Future<List<String>> folders(String dir) async => [
      for (final child in await _files.children(dir))
        if (child.directory && !_paths.basename(child.path).startsWith('.'))
          child.path,
    ];
    final skills = <Customization>[];
    for (final folder in await folders(root)) {
      if (scope == CustomizationScope.user &&
          _paths.basename(folder) == _synced) {
        for (final bucket in await folders(folder)) {
          for (final synced in await folders(bucket)) {
            skills.addAll([?await _skill(CustomizationScope.synced, synced)]);
          }
        }
      } else {
        skills.addAll([?await _skill(scope, folder)]);
      }
    }
    return skills;
  }

  /// The skill in [folder], if it has a SKILL.md; one synced is shown, not
  /// edited or deleted here.
  Future<Customization?> _skill(CustomizationScope scope, String folder) async {
    final path = _paths.join(folder, 'SKILL.md');
    final text = await _files.read(path);
    if (text == null) return null;
    final synced = scope == CustomizationScope.synced;
    return Customization(
      kind: CustomizationKind.skills,
      scope: scope,
      name: switch (parseFrontMatter(text)['name']) {
        final name? when name.isNotEmpty => name,
        _ => _paths.basename(folder),
      },
      description: describeMarkdown(text),
      path: path,
      editable: !synced,
      removePath: synced ? null : folder,
    );
  }

  /// How deep [_markdown] goes: links may loop.
  static const _deepest = 8;

  /// The markdown files under [root], its folders' too.
  Future<List<Customization>> _markdown(
    CustomizationKind kind,
    CustomizationScope scope,
    String root,
  ) async {
    final found = <Customization>[];
    Future<void> walk(String dir, int depth) async {
      for (final child in await _files.children(dir)) {
        if (child.directory) {
          if (depth < _deepest) await walk(child.path, depth + 1);
        } else if (child.path.endsWith('.md')) {
          if (await _files.read(child.path) case final text?) {
            found.add(
              Customization(
                kind: kind,
                scope: scope,
                name: _markdownName(kind, child.path, text),
                description: describeMarkdown(text),
                path: child.path,
                removePath: child.path,
              ),
            );
          }
        }
      }
    }

    await walk(root, 0);
    return found;
  }

  /// A subagent's own name, else its file's; a command as it is typed.
  String _markdownName(CustomizationKind kind, String path, String text) {
    final file = _paths.basenameWithoutExtension(path);
    if (kind == CustomizationKind.commands) return '/$file';
    return switch (parseFrontMatter(text)['name']) {
      final name? when name.isNotEmpty => name,
      _ => file,
    };
  }

  /// The memory files Claude Code reads: CLAUDE.md, the user's and the
  /// project's, CLAUDE.local.md, and each file of a `rules/` folder.
  Future<List<Customization>> _rules(String config, String? project) async {
    Future<Customization?> memory(
      CustomizationScope scope,
      String path,
      String base,
    ) async {
      final text = await _files.read(path);
      if (text == null) return null;
      return Customization(
        kind: CustomizationKind.rules,
        scope: scope,
        name: _paths.relative(path, from: base),
        description: describeMarkdown(text),
        path: path,
      );
    }

    Future<List<Customization>> folder(
      CustomizationScope scope,
      String root,
      String base,
    ) async => [
      for (final rule in await _markdown(CustomizationKind.rules, scope, root))
        Customization(
          kind: rule.kind,
          scope: rule.scope,
          name: _paths.relative(rule.path, from: base),
          description: rule.description,
          path: rule.path,
          removePath: rule.removePath,
        ),
    ];

    return [
      ?await memory(
        CustomizationScope.user,
        _paths.join(config, 'CLAUDE.md'),
        config,
      ),
      ...await folder(
        CustomizationScope.user,
        _paths.join(config, 'rules'),
        config,
      ),
      if (project != null) ...[
        ?await memory(
          CustomizationScope.project,
          _paths.join(project, 'CLAUDE.md'),
          project,
        ),
        ?await memory(
          CustomizationScope.project,
          _paths.join(project, '.claude', 'CLAUDE.md'),
          project,
        ),
        ...await folder(
          CustomizationScope.project,
          _paths.join(project, '.claude', 'rules'),
          project,
        ),
        ?await memory(
          CustomizationScope.local,
          _paths.join(project, 'CLAUDE.local.md'),
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
    final state = await _json(claudeJson);
    final projects = state?['projects'];
    // What `/mcp` turned off in the project: the user's and its private
    // ones by name, its `.mcp.json`'s apart.
    final own = switch (projects) {
      final Map<String, Object?> projects when project != null =>
        projects[project],
      _ => null,
    };
    Set<String> names(String key) => switch (own) {
      final Map<String, Object?> own when own[key] is List<Object?> =>
        (own[key] as List<Object?>).whereType<String>().toSet(),
      _ => const {},
    };
    final disabled = names('disabledMcpServers');
    final disabledShared = names('disabledMcpjsonServers');
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
            server: server is Map<String, Object?> ? server : null,
            enabled:
                (scope == CustomizationScope.project
                        ? disabledShared
                        : disabled)
                    .contains(name)
                ? false
                : null,
          ),
    ];

    final mcpJson = project == null ? null : _paths.join(project, '.mcp.json');
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
          (await _json(mcpJson))?['mcpServers'],
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
  List<(CustomizationScope, String)> _settingsFiles(
    String config,
    String? project,
  ) => [
    (CustomizationScope.user, _paths.join(config, 'settings.json')),
    if (project != null) ...[
      (
        CustomizationScope.project,
        _paths.join(project, '.claude', 'settings.json'),
      ),
      (
        CustomizationScope.local,
        _paths.join(project, '.claude', 'settings.local.json'),
      ),
    ],
  ];

  /// Each hook of the settings files, by event and matcher; its file is
  /// edited whole.
  Future<List<Customization>> _hooks(String config, String? project) async => [
    for (final (scope, path) in _settingsFiles(config, project))
      if ((await _json(path))?['hooks'] case final Map<String, Object?> events)
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
  Future<List<Customization>> _plugins(String config, String? project) async {
    final installed = await _json(
      _paths.join(config, 'plugins', 'installed_plugins.json'),
    );
    final plugins = installed?['plugins'];
    if (plugins is! Map<String, Object?>) return const [];
    final enabled = <String, bool>{};
    for (final (_, path) in _settingsFiles(config, project)) {
      if ((await _json(path))?['enabledPlugins']
          case final Map<String, Object?> map) {
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
          await _plugin(id, install, enabled[id] ?? false),
    ];
  }

  Future<Customization> _plugin(
    String id,
    Map<String, Object?> install,
    bool enabled,
  ) async {
    final root = install['installPath'] as String?;
    final manifestPath = root == null
        ? null
        : _paths.join(root, '.claude-plugin', 'plugin.json');
    final manifest = manifestPath == null ? null : await _json(manifestPath);
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
