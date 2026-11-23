import 'extensions.dart';
import 'memory.dart';
import 'paths.dart';
import 'settings.dart';

/// What an agent other than this one, working on a session of [cwd]'s (the
/// Antigravity CLI's), is told of the user's setup, as this agent would
/// have it: the instructions (CLAUDE.md files and rules) in full, and the
/// skills by name, what each is for, and its file, for it to read when
/// one fits. Null when there is none of either.
///
/// [flagSettings] are the session's own (its `skillOverrides`); the
/// instructions of the [additional] folders are read when
/// [readAdditional].
String? foreignAgentBrief({
  required Map<String, String> environment,
  required String cwd,
  List<String> additional = const [],
  bool readAdditional = false,
  Map<String, Object?> flagSettings = const {},
}) {
  final paths = AgentPaths.from(environment);
  final settings = AgentSettings(paths: paths, cwd: cwd, flag: flagSettings);
  final memory = MemoryLoader(paths).load(
    cwd,
    additional: additional,
    readAdditional: readAdditional,
  );
  final overrides = settings.skillOverrides;
  final skills = [
    for (final command in loadPromptCommands(
      paths: paths,
      cwd: cwd,
      plugins: loadPlugins(paths, settings),
      additional: additional,
    ))
      if (command.isSkill &&
          command.modelInvocable &&
          command.source != 'bundled' &&
          overrides[command.name] != 'off' &&
          overrides[command.name] != 'user-invocable-only')
        command,
  ];
  final parts = [
    if (memory.where((file) => !file.conditional).toList() case final files
        when files.isNotEmpty)
      [
        "# The user's instructions",
        "The user's and the project's instructions follow (CLAUDE.md files "
            'and rules). Follow them as written: where they differ from how '
            'you would work otherwise, they win.',
        for (final file in files)
          '## ${file.path} (${file.description})\n\n${file.content}',
      ].join('\n\n'),
    if (skills.isNotEmpty)
      [
        '# Skills',
        'Skills are instructions for kinds of tasks, each in a SKILL.md file. '
            'Before taking on a task, see whether one fits it: if one does, '
            'read its file first and follow it. A "/<name>" the user writes '
            'is the skill of that name.',
        for (final skill in skills)
          '- ${skill.name}: ${skill.description}'
              '${skill.whenToUse == null ? '' : ' - ${skill.whenToUse}'}'
              ' (${skill.path})',
      ].join('\n'),
  ];
  return parts.isEmpty ? null : parts.join('\n\n');
}
