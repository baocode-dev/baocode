import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/json.dart';
import 'frontmatter.dart';
import 'paths.dart';
import 'settings.dart';

/// A plugin switched on: where it is installed and what it brings.
class Plugin {
  const Plugin({
    required this.id,
    required this.name,
    required this.root,
    required this.manifest,
  });

  /// `name@marketplace`.
  final String id;
  final String name;
  final String root;
  final Map<String, Object?> manifest;

  /// [text] with `${CLAUDE_PLUGIN_ROOT}` spelled out.
  String expand(String text) => text.replaceAll(r'${CLAUDE_PLUGIN_ROOT}', root);

  /// The folders a kind of thing it brings is in: the manifest's, else the
  /// usual one.
  List<String> folders(String key, String fallback) {
    final given = manifest[key];
    final list = switch (given) {
      final String path => [path],
      final List<Object?> paths => paths.whereType<String>().toList(),
      _ => const <String>[],
    };
    return [
      p.join(root, fallback),
      for (final path in list) p.normalize(p.join(root, path)),
    ];
  }

  /// Its MCP servers, as `.mcp.json` has them.
  Map<String, Object?> get mcpServers {
    final given = manifest['mcpServers'];
    Map<String, Object?> servers = {};
    if (given is Map) {
      servers = given.cast<String, Object?>();
    } else {
      final path = given is String
          ? p.join(root, given)
          : p.join(root, '.mcp.json');
      final json = AgentSettings.readJson(path);
      servers = asMap(json['mcpServers']).isNotEmpty
          ? asMap(json['mcpServers'])
          : json;
    }
    return {
      for (final MapEntry(:key, :value) in servers.entries)
        if (value is Map) key: _expandAll(value.cast<String, Object?>()),
    };
  }

  /// Its hooks, as settings have them.
  Map<String, Object?> get hooks {
    final given = manifest['hooks'];
    if (given is Map) return asMap(_expandAll(given.cast<String, Object?>()));
    final path = given is String
        ? p.join(root, given)
        : p.join(root, 'hooks', 'hooks.json');
    final json = AgentSettings.readJson(path);
    final hooks = asMap(json['hooks']).isNotEmpty ? asMap(json['hooks']) : json;
    return asMap(_expandAll(hooks));
  }

  Object? _expandAll(Object? value) => switch (value) {
    final String text => expand(text),
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries)
        '$key': _expandAll(value),
    },
    final List<Object?> list => [for (final item in list) _expandAll(item)],
    _ => value,
  };
}

/// The plugins installed and switched on (`enabledPlugins`).
List<Plugin> loadPlugins(AgentPaths paths, AgentSettings settings) {
  final enabled = settings.enabledPlugins;
  if (enabled.isEmpty) return const [];
  final installed = AgentSettings.readJson(
    p.join(paths.pluginsDir, 'installed_plugins.json'),
  );
  final plugins = <Plugin>[];
  for (final MapEntry(key: id, value: raw) in asMap(
    installed['plugins'],
  ).entries) {
    if (enabled[id] != true) continue;
    // Version 2 keeps a list of installs; the first (the user's) is taken.
    final install = switch (raw) {
      final List<Object?> list when list.isNotEmpty => asMap(list.first),
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    final root = asString(install['installPath']);
    if (root == null || !Directory(root).existsSync()) continue;
    var manifest = AgentSettings.readJson(
      p.join(root, '.claude-plugin', 'plugin.json'),
    );
    if (manifest.isEmpty) {
      manifest = AgentSettings.readJson(p.join(root, 'plugin.json'));
    }
    plugins.add(
      Plugin(
        id: id,
        name: asString(manifest['name']) ?? id.split('@').first,
        root: root,
        manifest: manifest,
      ),
    );
  }
  return plugins;
}

/// A command the user can run by `/name` (a markdown file of commands), or
/// a skill (a folder with a SKILL.md) the model can use too.
class PromptCommand {
  const PromptCommand({
    required this.name,
    required this.description,
    required this.body,
    required this.path,
    required this.source,
    this.isSkill = false,
    this.argumentHint,
    this.allowedTools = const [],
    this.model,
    this.modelInvocable = true,
    this.userInvocable = true,
    this.whenToUse,
    this.plugin,
    this.origin,
    this.aliases = const [],
  });

  /// As it is run: `review`, `cloudflare:workers`.
  final String name;
  final String description;

  /// What it asks, `$ARGUMENTS` where what it is given goes.
  final String body;
  final String path;

  /// `user`, `project`, `plugin`.
  final String source;
  final bool isSkill;
  final String? argumentHint;

  /// The tools it may use without asking while it runs.
  final List<String> allowedTools;
  final String? model;

  /// Whether the model may use it (the Skill tool).
  final bool modelInvocable;

  /// Whether the user can run it by name.
  final bool userInvocable;
  final String? whenToUse;
  final Plugin? plugin;

  /// Where it comes from, as the user is shown it (`project`, `user`, a
  /// plugin's name); null for the agent's own.
  final String? origin;

  /// Other names it runs by.
  final List<String> aliases;

  /// The folder it is in (a skill's own).
  String get baseDir => p.dirname(path);

  /// [body] as the model is given it: a skill on disk says where it is.
  String withBaseDir(String body) => isSkill && source != 'bundled'
      ? 'Base directory for this skill: $baseDir\n\n$body'
      : body;

  /// [body] with [arguments] put in: `$ARGUMENTS` for all of them, `$1`…
  /// for each; at the end when it names none.
  String expand(String arguments) {
    var text = body;
    if (plugin case final plugin?) text = plugin.expand(text);
    text = text
        .replaceAll(r'${CLAUDE_SKILL_DIR}', baseDir)
        .replaceAll(r'${CLAUDE_SESSION_ID}', '');
    final words = _splitArguments(arguments);
    final hadPlaceholder =
        text.contains(r'$ARGUMENTS') || RegExp(r'\$\d').hasMatch(text);
    text = text.replaceAllMapped(RegExp(r'\$ARGUMENTS\[(\d+)\]'), (m) {
      final i = int.parse(m[1]!);
      return i < words.length ? words[i] : '';
    });
    text = text.replaceAll(r'$ARGUMENTS', arguments);
    text = text.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
      final i = int.parse(m[1]!) - 1;
      return i >= 0 && i < words.length ? words[i] : '';
    });
    if (!hadPlaceholder && arguments.trim().isNotEmpty) {
      text = '$text\n\nARGUMENTS: $arguments';
    }
    return text;
  }

  static List<String> _splitArguments(String text) {
    final out = <String>[];
    final pattern = RegExp(
      r'"([^"]*)"|'
      "'([^']*)'"
      r'|(\S+)',
    );
    for (final match in pattern.allMatches(text)) {
      out.add(match[1] ?? match[2] ?? match[3]!);
    }
    return out;
  }

  /// As the `initialize` answer lists it.
  Map<String, Object?> toCommandJson() => {
    'name': name,
    'description': origin == null ? description : '$description ($origin)',
    'argumentHint': argumentHint ?? '',
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (source == 'bundled') 'builtin': true,
  };
}

/// The commands and skills of the user, the project and the plugins.
List<PromptCommand> loadPromptCommands({
  required AgentPaths paths,
  required String cwd,
  required List<Plugin> plugins,
  List<String> additional = const [],
}) {
  final found = <String, PromptCommand>{};
  void add(PromptCommand command) =>
      found.putIfAbsent(command.name, () => command);

  // The project's first: they win over the user's of the same name.
  final projectDirs = <String>[];
  for (var dir = p.normalize(cwd); ; dir = p.dirname(dir)) {
    projectDirs.add(p.join(dir, '.claude'));
    if (p.dirname(dir) == dir || p.equals(dir, paths.home)) break;
  }
  for (final dir in [
    ...projectDirs,
    for (final d in additional) p.join(d, '.claude'),
  ]) {
    if (p.equals(dir, paths.configDir)) continue;
    _skills(p.join(dir, 'skills'), 'project', null).forEach(add);
    _commands(p.join(dir, 'commands'), 'project', null).forEach(add);
  }
  _skills(p.join(paths.configDir, 'skills'), 'user', null).forEach(add);
  _commands(p.join(paths.configDir, 'commands'), 'user', null).forEach(add);
  for (final plugin in plugins) {
    for (final dir in plugin.folders('skills', 'skills')) {
      _skills(dir, 'plugin', plugin).forEach(add);
    }
    for (final dir in plugin.folders('commands', 'commands')) {
      _commands(dir, 'plugin', plugin).forEach(add);
    }
  }
  return found.values.toList();
}

List<PromptCommand> _commands(String folder, String source, Plugin? plugin) {
  final dir = Directory(folder);
  if (!dir.existsSync()) return const [];
  final out = <PromptCommand>[];
  final files =
      dir
          .listSync(recursive: true, followLinks: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    final front = Frontmatter.parse(text);
    final relative = p.relative(file.path, from: folder);
    final base = p.basenameWithoutExtension(file.path);
    final namespace = p.dirname(relative);
    final name = plugin == null ? base : '${plugin.name}:$base';
    final where = [
      switch (source) {
        'project' => 'project',
        'user' => 'user',
        _ => plugin?.name ?? source,
      },
      if (namespace != '.') namespace.replaceAll(p.separator, ':'),
    ].join(':');
    final description =
        front.string('description') ?? _firstLine(front.body) ?? name;
    out.add(
      PromptCommand(
        name: name,
        description: description,
        origin: where,
        body: front.body,
        path: file.path,
        source: source,
        argumentHint: front.string('argument-hint'),
        allowedTools: front.list('allowed-tools') ?? const [],
        model: front.string('model'),
        modelInvocable:
            !(front.flag('disable-model-invocation') ?? false) &&
            front.string('description') != null,
        plugin: plugin,
      ),
    );
  }
  return out;
}

List<PromptCommand> _skills(String folder, String source, Plugin? plugin) {
  final dir = Directory(folder);
  if (!dir.existsSync()) return const [];
  final out = <PromptCommand>[];
  final entries =
      dir.listSync(followLinks: true).whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final skillDir in entries) {
    final file = File(p.join(skillDir.path, 'SKILL.md'));
    if (!file.existsSync()) continue;
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue;
    }
    final front = Frontmatter.parse(text);
    final base = front.string('name') ?? p.basename(skillDir.path);
    final name = plugin == null ? base : '${plugin.name}:$base';
    out.add(
      PromptCommand(
        name: name,
        description:
            front.string('description') ?? _firstLine(front.body) ?? name,
        body: front.body,
        path: file.path,
        source: source,
        isSkill: true,
        origin: plugin?.name ?? source,
        argumentHint: front.string('argument-hint'),
        allowedTools: front.list('allowed-tools') ?? const [],
        model: front.string('model'),
        modelInvocable: !(front.flag('disable-model-invocation') ?? false),
        userInvocable: front.flag('user-invocable') ?? true,
        whenToUse: front.string('when_to_use') ?? front.string('when-to-use'),
        plugin: plugin,
      ),
    );
  }
  return out;
}

String? _firstLine(String body) {
  for (final line in const LineSplitter().convert(body)) {
    final text = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    if (text.isNotEmpty) {
      return text.length > 100 ? '${text.substring(0, 100)}…' : text;
    }
  }
  return null;
}

/// A kind of subagent: what it is for, its instructions, its tools and
/// model.
class AgentDefinition {
  const AgentDefinition({
    required this.name,
    required this.description,
    required this.prompt,
    required this.source,
    this.tools,
    this.disallowedTools = const [],
    this.model,
    this.permissionMode,
    this.color,
    this.skills = const [],
    this.effort,
    this.isolation,
  });

  /// `subagent_type`.
  final String name;

  /// When to use it, for the model choosing one.
  final String description;

  /// Its system prompt.
  final String prompt;

  /// `built-in`, `user`, `project`, `plugin`.
  final String source;

  /// The tools it has; all (but the Agent tool) when null.
  final List<String>? tools;
  final List<String> disallowedTools;

  /// `sonnet`, `opus`, `haiku`, `inherit`, or a model's id.
  final String? model;
  final String? permissionMode;
  final String? color;
  final List<String> skills;

  /// How hard it thinks, unless the call says.
  final String? effort;

  /// `worktree`: it works in a git worktree of its own.
  final String? isolation;

  /// Its tools, as the model is told them.
  String get toolsLabel {
    final tools = this.tools;
    if (tools != null) return tools.join(', ');
    return disallowedTools.isEmpty
        ? '*'
        : 'All tools except ${disallowedTools.join(', ')}';
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'model': ?model,
  };
}

/// What a read-only agent may not use.
const _readOnlyDenied = [
  'Agent',
  'ExitPlanMode',
  'Edit',
  'Write',
  'NotebookEdit',
];

/// The subagents everyone has.
const builtInAgents = <AgentDefinition>[
  AgentDefinition(
    name: 'general-purpose',
    description:
        'For any task of many steps: looking into a hard question, finding '
        'code, or doing work across several files. Also for a search you are '
        'not sure to get right in the first few tries.',
    source: 'built-in',
    prompt:
        'You are an agent that a coding agent has handed a task to. Do it '
        'with the tools you have: what was asked, no less and no more. When '
        'it is done, your last message is your report, full enough that it '
        'need not be redone.\n\n'
        'How to go about it:\n'
        '- To find things, search the codebase through Bash (grep or find, '
        'rg where it is installed); Read when you know the file.\n'
        '- Start wide and narrow down. If one way of looking finds nothing, '
        'try another: other places, other spellings of a name, files that go '
        'with the ones you found.\n'
        '- Make a file only when the task cannot be done without it; change '
        'the files that are there instead. No documentation or README files '
        'unless asked.\n'
        '- In the report, name the files that matter by absolute path, and '
        'quote the code that matters.\n'
        '- No emoji.',
  ),
  AgentDefinition(
    name: 'claude',
    description:
        'For whatever no other kind of agent fits: the agent to start when '
        'no kind is named.',
    source: 'built-in',
    prompt:
        'You are an agent that a coding agent has handed a task to. Do what '
        'was asked with the tools you have, as a careful engineer would: '
        'read before you change, change only what the task needs, and check '
        'that it works. When it is done, your last message is your report: '
        'what you did, what you found, and anything left open, with the '
        'files that matter named by absolute path. No emoji.',
  ),
  AgentDefinition(
    name: 'Explore',
    description:
        'A quick, read-only agent for searches that sweep many files: files '
        'by pattern ("lib/**/*_test.dart"), code by what it says ("where the '
        'session is saved"), which files use a name. It reads parts of '
        'files, so it finds code rather than reviewing or auditing it; use '
        'it when you need only what it concludes. Say how thorough it should '
        'be: "quick", "medium" or "very thorough" (many places, many '
        'spellings).',
    source: 'built-in',
    model: 'inherit',
    disallowedTools: _readOnlyDenied,
    prompt:
        'You search codebases for a coding agent: you find files, read '
        'them, and report what you found.\n\n'
        'You only look. Do not make, change, move, copy or delete any file, '
        'do not write files through redirects, and run no command that '
        'changes anything on the machine.\n\n'
        'How to go about it:\n'
        '- Through Bash: find for files by name, grep for what they contain '
        '(or rg, where it is installed). Read for a file you know.\n'
        '- Bash only for commands that change nothing: ls, grep, rg, find, '
        'git status, git log, git diff.\n'
        '- Run searches and reads that do not depend on each other at once, '
        'side by side in one reply.\n'
        '- Go as deep as you were asked to: a quick look, or every place and '
        'spelling.\n'
        '- Report what you found, clearly, with absolute paths. No emoji.',
  ),
  AgentDefinition(
    name: 'Plan',
    description:
        'Works out how to build something before it is built: looks through '
        'the code and gives back a plan, step by step, with the files that '
        'matter most and what each way of doing it costs.',
    source: 'built-in',
    model: 'inherit',
    disallowedTools: _readOnlyDenied,
    prompt:
        'You plan software changes for a coding agent: you look through the '
        'codebase and work out how the change should be made.\n\n'
        'You only look. Do not make, change or delete files, and run no '
        'command that changes anything on the machine.\n\n'
        '1. Make sure you understand what is wanted.\n'
        '2. Look through the code: the files you were pointed to, how the '
        'code is laid out now, the ways it already does such things (grep and '
        'find through Bash, Read), and the paths the change will run through.\n'
        '3. Work out the change: weigh the ways of doing it, keeping to how '
        'the code already works where that fits.\n'
        '4. Write the plan: the steps in order, what each depends on, and '
        'what may get in the way.\n\n'
        'End with a section headed "### Files that matter most": the 3 to 5 '
        'files the change turns on, each with a line on why.',
  ),
];

/// The subagents: the built-in ones, then the user's, the project's and
/// the plugins' (a later one of a name over an earlier).
List<AgentDefinition> loadAgents({
  required AgentPaths paths,
  required String cwd,
  required List<Plugin> plugins,
}) {
  final found = <String, AgentDefinition>{
    for (final agent in builtInAgents) agent.name: agent,
  };
  void readFolder(String folder, String source, [Plugin? plugin]) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return;
    final files =
        dir
            .listSync(recursive: true, followLinks: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.md'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      final front = Frontmatter.parse(text);
      final base =
          front.string('name') ?? p.basenameWithoutExtension(file.path);
      final name = plugin == null ? base : '${plugin.name}:$base';
      final description = front.string('description');
      if (description == null) continue;
      final tools = front.list('tools');
      found[name] = AgentDefinition(
        name: name,
        description: description,
        prompt: plugin?.expand(front.body.trim()) ?? front.body.trim(),
        source: source,
        tools: tools == null || tools.contains('*') ? null : tools,
        disallowedTools: front.list('disallowedTools') ?? const [],
        model: front.string('model'),
        permissionMode: front.string('permissionMode'),
        color: front.string('color'),
        skills: front.list('skills') ?? const [],
        effort: front.string('effort'),
        isolation: front.string('isolation'),
      );
    }
  }

  for (final plugin in plugins) {
    for (final dir in plugin.folders('agents', 'agents')) {
      readFolder(dir, 'plugin', plugin);
    }
  }
  readFolder(p.join(paths.configDir, 'agents'), 'user');
  readFolder(p.join(cwd, '.claude', 'agents'), 'project');
  return found.values.toList();
}
