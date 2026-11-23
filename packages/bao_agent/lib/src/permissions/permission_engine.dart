import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine/session.dart';
import '../tools/tool.dart';
import '../util/windows_paths.dart';
import 'decision.dart';
import 'rules.dart';
import 'shell_command.dart';

/// Decides whether a tool call may run, as Claude Code does: deny rules
/// first, then ask rules, then the tool's own view (paths, commands), then
/// the mode, then allow rules; what is left is asked.
class PermissionEngine {
  PermissionEngine(this.session);

  final AgentSession session;

  List<PermissionRule>? _rules;
  Object? _rulesOf;

  /// Every rule, from every source.
  List<PermissionRule> get rules {
    final sourced = session.settings.rules;
    // Read again only when the settings changed.
    final key = Object.hashAll(
      sourced.map((r) => '${r.source}${r.behavior}${r.rule}'),
    );
    if (_rules != null && _rulesOf == key) return _rules!;
    _rulesOf = key;
    return _rules = [for (final rule in sourced) PermissionRule.parse(rule)];
  }

  PermissionRule? _wholeTool(String toolName, String behavior) => rules
      .where((r) => r.behavior == behavior && r.wholeTool && r.isFor(toolName))
      .firstOrNull;

  Iterable<PermissionRule> _content(String ruleTool, String behavior) =>
      rules.where(
        (r) => r.behavior == behavior && !r.wholeTool && r.tool == ruleTool,
      );

  /// The decision for [input] to [tool], before the mode's say on what
  /// would be asked (see [AgentLoop]).
  Future<PermissionDecision> check(
    Tool tool,
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final mode = context.run.permissionMode;
    if (_wholeTool(tool.name, 'deny') case final rule?) {
      return PermissionDeny(
        'Permission to use ${tool.name} has been denied by the rule '
        '${rule.text}.',
        reasonType: 'rule',
      );
    }
    final askRule = _wholeTool(tool.name, 'ask');
    final own = await tool.checkPermissions(input, context);
    if (own is PermissionDeny) return own;
    if (askRule != null) {
      return PermissionAsk(
        matchedAskRule: askRule.text,
        reasonType: 'rule',
        suggestions: own is PermissionAsk ? own.suggestions : const [],
      );
    }
    if (own is PermissionAsk &&
        (own.matchedAskRule != null ||
            own.requiresUserInteraction ||
            own.reasonType == 'safetyCheck')) {
      return own;
    }
    if (mode == 'bypassPermissions') {
      return PermissionAllow(updatedInput: _updated(own), reason: 'mode');
    }
    if (own is PermissionAllow) return own;
    if (_wholeTool(tool.name, 'allow') != null) {
      return const PermissionAllow(reason: 'rule');
    }
    if (own is PermissionAsk) return own;
    final suggestions = switch (own) {
      PermissionPassthrough(:final suggestions) when suggestions.isNotEmpty =>
        suggestions,
      _ => [
        addRulesSuggestion([tool.name]),
      ],
    };
    return PermissionAsk(suggestions: suggestions);
  }

  static Map<String, Object?>? _updated(PermissionDecision decision) =>
      decision is PermissionAllow ? decision.updatedInput : null;

  // --- Paths ---------------------------------------------------------------------

  /// [path] made absolute, from [cwd]. On Windows, `/c/x` (as the shell
  /// writes it) is `C:/x`.
  String absolute(String path, String cwd) {
    var expanded = session.paths.expandHome(path);
    if (p.style == p.Style.windows) expanded = windowsDrivePath(expanded);
    return p.normalize(
      p.isAbsolute(expanded) ? expanded : p.join(cwd, expanded),
    );
  }

  /// Whether [path] (absolute) is in one of the folders the agent works in.
  bool inWorkingDirectories(String path) => session.workingDirectories.any(
    (dir) => p.equals(dir, path) || p.isWithin(dir, path),
  );

  PermissionRule? _pathRule(
    Set<String> tools,
    String behavior,
    String path,
    String cwd,
  ) {
    for (final rule in rules) {
      if (rule.behavior != behavior || rule.content == null) continue;
      if (!tools.contains(rule.tool)) continue;
      if (pathRuleMatches(
        rule.content!,
        path: path,
        cwd: session.cwd,
        home: session.paths.home,
        root: rule.root,
      )) {
        return rule;
      }
    }
    return null;
  }

  /// May the file or folder at [path] be read.
  PermissionDecision checkRead(String path, String cwd) {
    final target = absolute(path, cwd);
    if (_pathRule(const {'Read', 'Edit'}, 'deny', target, cwd)
        case final rule?) {
      return PermissionDeny(
        'Permission to read $target has been denied by the rule ${rule.text}.',
        reasonType: 'rule',
      );
    }
    if (_pathRule(const {'Read'}, 'ask', target, cwd) case final rule?) {
      return PermissionAsk(matchedAskRule: rule.text, reasonType: 'rule');
    }
    if (inWorkingDirectories(target) || session.internalReadable(target)) {
      return const PermissionAllow(reason: 'workingDir');
    }
    if (_pathRule(const {'Read', 'Edit'}, 'allow', target, cwd) != null) {
      return const PermissionAllow(reason: 'rule');
    }
    final folder = _folderOf(target);
    return PermissionAsk(
      reasonType: 'workingDir',
      blockedPath: target,
      message: '$target is outside the folders this session works in.',
      suggestions: [
        addDirectoriesSuggestion([folder]),
        addRulesSuggestion([
          folderRule('Read', folder),
        ], destination: 'session'),
      ],
    );
  }

  /// May the file at [path] be changed.
  PermissionDecision checkEdit(String path, String cwd, String mode) {
    final target = absolute(path, cwd);
    if (_pathRule(const {'Edit'}, 'deny', target, cwd) case final rule?) {
      return PermissionDeny(
        'Permission to edit $target has been denied by the rule ${rule.text}.',
        reasonType: 'rule',
      );
    }
    if (_pathRule(const {'Edit'}, 'ask', target, cwd) case final rule?) {
      return PermissionAsk(matchedAskRule: rule.text, reasonType: 'rule');
    }
    if (session.internalWritable(target)) {
      return const PermissionAllow(reason: 'internal');
    }
    final inside = inWorkingDirectories(target);
    if (isProtectedPath(target)) {
      return PermissionAsk(
        reasonType: 'safetyCheck',
        message:
            '$target is a sensitive file (it changes how the agent, the '
            'shell or git behave): editing it needs the user\'s yes.',
        suggestions: [if (inside) setModeSuggestion('acceptEdits')],
      );
    }
    if (_pathRule(const {'Edit'}, 'allow', target, cwd) != null) {
      return const PermissionAllow(reason: 'rule');
    }
    if (inside && (mode == 'acceptEdits' || mode == 'bypassPermissions')) {
      return const PermissionAllow(reason: 'mode');
    }
    if (!inside) {
      final folder = _folderOf(target);
      return PermissionAsk(
        reasonType: 'workingDir',
        blockedPath: target,
        message: '$target is outside the folders this session works in.',
        suggestions: [
          addDirectoriesSuggestion([folder]),
          addRulesSuggestion([
            folderRule('Edit', folder),
          ], destination: 'session'),
        ],
      );
    }
    return PermissionAsk(suggestions: [setModeSuggestion('acceptEdits')]);
  }

  String _folderOf(String target) => _folderFor(target);

  /// Whether [path] is one whose change could change how the agent or the
  /// user's tools behave: settings, hooks, git's own files, shell
  /// profiles. Asked about even when edits are accepted.
  bool isProtectedPath(String path) {
    final parts = p.split(p.normalize(path));
    final name = parts.last;
    const protectedNames = {
      '.bashrc',
      '.bash_profile',
      '.zshrc',
      '.zprofile',
      '.zshenv',
      '.profile',
      '.gitconfig',
      '.gitmodules',
      '.mcp.json',
      '.claude.json',
      '.npmrc',
      '.ripgreprc',
    };
    if (protectedNames.contains(name)) return true;
    for (var i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (part == '.git' ||
          part == '.vscode' ||
          part == '.idea' ||
          part == '.husky') {
        return true;
      }
      if (part == '.claude') {
        // What the agent keeps there as a matter of course (worktrees,
        // plans, its own commands and agents) is not.
        final next = i + 1 < parts.length - 1 ? parts[i + 1] : null;
        if (next == 'worktrees' || next == 'plans') return false;
        return name.startsWith('settings') || next == 'hooks' || next == null;
      }
    }
    return false;
  }

  // --- Commands --------------------------------------------------------------------

  /// May [command] run, from [cwd].
  PermissionDecision checkBash(String command, String cwd, String mode) {
    final parsed = ShellCommand.parse(command);
    final parts = parsed.commands.isEmpty ? [command.trim()] : parsed.commands;
    bool matches(PermissionRule rule, String text) =>
        bashRuleMatches(rule.content!, text);
    // A deny or ask rule matching the whole line, or any part of it.
    for (final behavior in const ['deny', 'ask']) {
      for (final rule in _content('Bash', behavior)) {
        if (matches(rule, command) ||
            parts.any((part) => matches(rule, part))) {
          return behavior == 'deny'
              ? PermissionDeny(
                  'Permission to run this command has been denied by the '
                  'rule ${rule.text}.',
                  reasonType: 'rule',
                )
              : PermissionAsk(matchedAskRule: rule.text, reasonType: 'rule');
        }
      }
    }
    final home = session.paths.home;
    if (parsed.words.any((words) => isDangerousWords(words, home: home))) {
      return const PermissionAsk(
        reasonType: 'safetyCheck',
        classifierApprovable: false,
        message:
            'This command can destroy data that cannot be recovered, or '
            'runs with elevated rights.',
      );
    }
    if (_content('Bash', 'allow').any((rule) => matches(rule, command)) &&
        !parsed.hasSubstitution) {
      return const PermissionAllow(reason: 'rule');
    }
    if (parsed.unbalanced) {
      return PermissionAsk(
        message: 'The command could not be parsed.',
        suggestions: const [],
      );
    }
    final unapproved = <String>[];
    String? outside;
    for (final (i, part) in parts.indexed) {
      final words = i < parsed.words.length
          ? parsed.words[i]
          : const <String>[];
      if (_content('Bash', 'allow').any((rule) => matches(rule, part)) &&
          !parsed.hasSubstitution) {
        continue;
      }
      if (!parsed.hasSubstitution &&
          parsed.redirectsOnlyToNull &&
          isReadOnlyWords(words)) {
        final path = _outsidePath(words, cwd);
        if (path == null) continue;
        outside = path;
      } else if ((mode == 'acceptEdits' || mode == 'bypassPermissions') &&
          !parsed.hasSubstitution &&
          words.isNotEmpty &&
          fileSystemPrograms.contains(words.first) &&
          _outsidePath(words, cwd) == null &&
          parsed.redirects.every((target) => _inside(target, cwd))) {
        continue;
      }
      unapproved.add(part);
    }
    if (unapproved.isEmpty && outside == null) {
      return const PermissionAllow(reason: 'readOnly');
    }
    if (unapproved.isEmpty && outside != null) {
      return PermissionAsk(
        reasonType: 'workingDir',
        blockedPath: outside,
        message: '$outside is outside the folders this session works in.',
        suggestions: [
          addDirectoriesSuggestion([_folderFor(outside)]),
        ],
      );
    }
    final prefixes = <String>{
      for (final part in unapproved) ShellCommand.prefix(part),
    }.where((prefix) => prefix.isNotEmpty).take(5).toList();
    return PermissionAsk(
      suggestions: [
        if (prefixes.isNotEmpty)
          addRulesSuggestion([
            for (final prefix in prefixes)
              // A line too odd to make a prefix of: the line itself.
              parsed.hasSubstitution || prefix.contains('\n')
                  ? 'Bash($command)'
                  : 'Bash($prefix:*)',
          ]),
      ],
    );
  }

  bool _inside(String target, String cwd) {
    if (target == '/dev/null') return true;
    return inWorkingDirectories(absolute(target, cwd));
  }

  String _folderFor(String path) =>
      Directory(path).existsSync() ? path : p.dirname(path);

  /// The first path among [words]' arguments outside the working folders
  /// and not allowed by a rule.
  String? _outsidePath(List<String> words, String cwd) {
    for (final word in words.skip(1)) {
      if (word.startsWith('-') || word.contains('://')) continue;
      final looksLikePath =
          word.startsWith('/') ||
          word.startsWith('~') ||
          word.startsWith('..') ||
          word.contains('/../');
      if (!looksLikePath) continue;
      final path = absolute(word, cwd);
      if (path == '/dev/null') continue;
      if (inWorkingDirectories(path) || session.internalReadable(path)) {
        continue;
      }
      if (_pathRule(const {'Read', 'Edit'}, 'allow', path, cwd) != null) {
        continue;
      }
      return path;
    }
    return null;
  }

  // --- Other tools -----------------------------------------------------------------

  /// The decision the content rules for [ruleTool] make about [value]
  /// (a URL's domain, a subagent's type, a skill's name); passthrough when
  /// none matches.
  PermissionDecision checkContent(
    String ruleTool,
    String value, {
    bool Function(String content, String value)? match,
    List<Map<String, Object?>> suggestions = const [],
  }) {
    final test = match ?? plainRuleMatches;
    for (final behavior in const ['deny', 'ask', 'allow']) {
      for (final rule in _content(ruleTool, behavior)) {
        if (!test(rule.content!, value)) continue;
        return switch (behavior) {
          'deny' => PermissionDeny(
            'Permission to use $ruleTool has been denied by the rule '
            '${rule.text}.',
            reasonType: 'rule',
          ),
          'ask' => PermissionAsk(matchedAskRule: rule.text, reasonType: 'rule'),
          _ => const PermissionAllow(reason: 'rule'),
        };
      }
    }
    return PermissionPassthrough(suggestions: suggestions);
  }
}
