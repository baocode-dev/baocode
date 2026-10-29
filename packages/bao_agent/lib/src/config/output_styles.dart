import 'dart:io';

import 'package:path/path.dart' as p;

import 'frontmatter.dart';
import 'paths.dart';

/// A way of answering the user chooses (`outputStyle`): what the system
/// prompt is told of it.
class OutputStyle {
  const OutputStyle({
    required this.name,
    required this.description,
    required this.prompt,
    this.source = 'built-in',
    this.keepCodingInstructions = true,
  });

  final String name;
  final String description;

  /// Added to the system prompt.
  final String prompt;

  /// `built-in`, `user`, `project`.
  final String source;

  /// Whether the agent's own instructions for coding stay in the system
  /// prompt beside it.
  final bool keepCodingInstructions;

  static const defaultName = 'default';

  /// The styles everyone has, besides the default (none).
  static const builtIn = [
    OutputStyle(
      name: 'Proactive',
      description: 'Goes ahead on its own, and asks only when it must',
      prompt:
          'The user wants you to get on with it. Where the next step is '
          'clear and safe, take it rather than asking whether to: make the '
          'reasonable choice, say in a line what you chose, and carry on. '
          'Keep questions for what only the user can decide, or what would '
          'be hard to undo. Once a task is done, do the obvious follow-ups '
          'that belong to it (the test it needs, the caller it breaks) '
          'without being asked.',
    ),
    OutputStyle(
      name: 'Concise',
      description: 'Answers as briefly as it can',
      prompt:
          'Keep every answer as short as it can be and still be right. Lead '
          'with the answer or the result; leave out preambles, summaries of '
          'what you are about to do, and recaps of what you did. A line or '
          'two is often enough. Use lists and headings only where they '
          'shorten things. Say more only when the user asks for it, or when '
          'leaving it out would mislead them.',
    ),
    OutputStyle(
      name: 'Explanatory',
      description: 'Explains its choices and the codebase as it works',
      prompt:
          'As you do the task, teach the user about it: why you chose to '
          'build it the way you did, and the patterns of their codebase you '
          'come across, in short "★ Insight" notes before and after the '
          'code you write. Keep the notes to what is particular to this '
          'code, not general programming lore.',
    ),
    OutputStyle(
      name: 'Learning',
      description: 'Leaves pieces of the work for the user to write, to learn',
      prompt:
          'The user wants to learn by doing. Say why you do what you do, '
          'and leave small pieces of code that matter (5 to 10 lines: a '
          'decision, a piece of logic, not boilerplate) for them to write: '
          'mark each place with a TODO(human) comment, say what it is to '
          'do and what to weigh, and wait for them to fill it in before you '
          'go on. Add "★ Insight" notes on what is particular to their '
          'codebase as you go.',
    ),
  ];

  /// The user's styles folder.
  static String userDir(AgentPaths paths) =>
      p.join(paths.configDir, 'output-styles');

  /// The styles there are: the built-in ones, then the user's, then the
  /// project's (a later one of a name over an earlier).
  static List<OutputStyle> load(AgentPaths paths, String cwd) {
    final found = <String, OutputStyle>{
      for (final style in builtIn) style.name: style,
    };
    void read(String folder, String source) {
      final dir = Directory(folder);
      if (!dir.existsSync()) return;
      final files =
          dir
              .listSync()
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
        final name =
            front.string('name') ?? p.basenameWithoutExtension(file.path);
        found[name] = OutputStyle(
          name: name,
          description: front.string('description') ?? '',
          prompt: front.body.trim(),
          source: source,
          keepCodingInstructions:
              front.flag('keep-coding-instructions') ?? false,
        );
      }
    }

    read(userDir(paths), 'user');
    read(p.join(cwd, '.claude', 'output-styles'), 'project');
    return found.values.toList();
  }

  /// The style named [name] among [styles] (in any case); null for the
  /// default, or one there is not.
  static OutputStyle? find(List<OutputStyle> styles, String? name) {
    if (name == null || name.isEmpty) return null;
    if (name.toLowerCase() == defaultName) return null;
    for (final style in styles) {
      if (style.name.toLowerCase() == name.toLowerCase()) return style;
    }
    return null;
  }
}
