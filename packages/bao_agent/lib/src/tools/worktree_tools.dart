import '../engine/worktrees.dart';
import '../hooks/hooks.dart';
import '../permissions/decision.dart';
import '../util/json.dart';
import 'tool.dart';

/// Moves the agent into a git worktree: a new one, or one there is.
class EnterWorktreeTool extends Tool {
  const EnterWorktreeTool();

  @override
  String get name => 'EnterWorktree';

  @override
  String get description => '''Makes a git worktree and moves this session into it, to work on a copy of the repository apart from the one checked out.

Use it only when told to work in a worktree: by the user ("make a worktree", "work in a worktree"), or by the project's instructions (CLAUDE.md, memory). Not to make or switch a branch (git does that), and not just because there is a bug to fix or a feature to build.

- It needs a git repository, and no worktree entered already for `name` (to switch to another one there is, give `path`).
- A new worktree goes in `.claude/worktrees/<name>`, on a branch of its own. Where it branches from is up to the `worktree.baseRef` setting: the remote's default branch unless set (`fresh`), this checkout's HEAD for `head`, or any ref given.
- The session's working directory becomes the worktree. ExitWorktree leaves it again, keeping it or removing it.
- `path` enters a worktree there is already (in `git worktree list` of this repository) instead of making one; ExitWorktree will not remove one entered this way.
- With neither, a name is made up.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'name': {
        'type': 'string',
        'description':
            'A name for a new worktree: "/"-separated parts of letters, '
            'digits, dots, underscores and dashes, 64 characters at most. '
            'Made up when left out. Not with `path`',
      },
      'path': {
        'type': 'string',
        'description':
            'A worktree there is already, to move into instead of making '
            'one: it must be in `git worktree list` of this repository (or '
            'of one inside the folder the session started in). Not with '
            '`name`',
      },
    },
    'additionalProperties': false,
  };

  @override
  bool get changesMode => true;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final name = asText(input['name']);
    final path = asText(input['path']);
    if (name != null && path != null) {
      return 'Give either name or path, not both.';
    }
    if (name != null) return Worktrees.checkName(name);
    if (path == null && context.session.worktree != null) {
      return 'The session is in a worktree already: leave it with '
          'ExitWorktree first, or give a path to switch to another.';
    }
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final session = context.session;
    final env = session.commandEnvironment;
    final path = asText(input['path']);
    final Worktree worktree;
    try {
      if (path != null) {
        worktree = await Worktrees.existing(context.cwd, path, env);
      } else {
        if (session.worktree != null) {
          return ToolOutput.error(
            'The session is in a worktree already: leave it with '
            'ExitWorktree first.',
          );
        }
        worktree = await Worktrees.create(
          context.cwd,
          env,
          name: asText(input['name']),
          baseRef: Worktrees.baseRefSetting(session.settings['worktree']),
        );
        if (session.hooks.has(HookEvent.worktreeCreate)) {
          await session.hooks.run(HookEvent.worktreeCreate, {
            'name': worktree.path.split('/').last,
            ...Worktrees.toJson(worktree),
          }, cancel: context.cancel);
        }
      }
    } on WorktreeError catch (error) {
      return ToolOutput.error(error.message);
    }
    session.enterWorktree(worktree, context.run);
    return ToolOutput(
      'Working in the worktree ${worktree.path}'
      '${worktree.branch == null ? '' : ' (branch ${worktree.branch})'} '
      'now. Commands run there, and relative paths start there. Leave it '
      'with ExitWorktree when the user asks.',
      result: Worktrees.toJson(worktree),
    );
  }
}

/// Leaves the worktree EnterWorktree moved the session into.
class ExitWorktreeTool extends Tool {
  const ExitWorktreeTool();

  @override
  String get name => 'ExitWorktree';

  @override
  String get description => '''Leaves the worktree EnterWorktree moved this session into, and goes back to the folder it was in before.

It acts only on a worktree entered with EnterWorktree in this session: not on one made by hand with `git worktree add`, nor one from an earlier session. Outside such a worktree it does nothing, and says so.

Call it when the user asks to leave the worktree ("go back", "exit the worktree"), not of your own accord.

- `action: "keep"` leaves the worktree and its branch on disk, for the user to come back to, or to keep work not merged.
- `action: "remove"` deletes the worktree and its branch, for work done or given up. With files changed and not committed, or commits not on the branch it started from, it refuses unless `discard_changes` is true: then tell the user what would be lost, and ask before calling again with it.
- Once out, EnterWorktree can make a new one.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['keep', 'remove'],
        'description':
            '"keep" leaves the worktree and its branch on disk; "remove" '
            'deletes both',
      },
      'discard_changes': {
        'type': 'boolean',
        'description':
            'Needed true to remove a worktree with files changed and not '
            'committed, or commits not on the branch it started from; it '
            'refuses and lists them otherwise',
      },
    },
    'required': ['action'],
    'additionalProperties': false,
  };

  @override
  bool get changesMode => true;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final session = context.session;
    final worktree = session.worktree;
    if (worktree == null) {
      return const ToolOutput(
        'The session is not in a worktree entered with EnterWorktree: '
        'nothing was done.',
        result: {'action': 'none'},
      );
    }
    final env = session.commandEnvironment;
    final remove = input['action'] == 'remove';
    if (remove && !worktree.made) {
      return ToolOutput.error(
        'This worktree was there before the session entered it, so it is '
        'not removed here: leave it with action "keep".',
      );
    }
    if (remove && input['discard_changes'] != true) {
      final (:files, :commits) = await Worktrees.changes(worktree, env);
      if (files.isNotEmpty || commits.isNotEmpty) {
        return ToolOutput.error(
          [
            'The worktree holds work that removing it would lose:',
            if (files.isNotEmpty) ...[
              'Files changed and not committed:',
              ...files.map((f) => '  $f'),
            ],
            if (commits.isNotEmpty) ...[
              'Commits not on the branch it started from:',
              ...commits.map((c) => '  $c'),
            ],
            'Ask the user before removing it with discard_changes true, or '
                'keep it.',
          ].join('\n'),
        );
      }
    }
    final back = session.leaveWorktree(context.run);
    if (remove) {
      try {
        await Worktrees.remove(worktree, env);
      } on WorktreeError catch (error) {
        return ToolOutput.error(
          'Back in $back, but the worktree could not be removed: $error',
        );
      }
      if (session.hooks.has(HookEvent.worktreeRemove)) {
        await session.hooks.run(
          HookEvent.worktreeRemove,
          Worktrees.toJson(worktree),
          cancel: context.cancel,
        );
      }
    }
    return ToolOutput(
      remove
          ? 'Removed the worktree ${worktree.path}'
                '${worktree.branch == null ? '' : ' and its branch ${worktree.branch}'}; '
                'back in $back.'
          : 'Left the worktree ${worktree.path} on disk'
                '${worktree.branch == null ? '' : ' (branch ${worktree.branch})'}; '
                'back in $back.',
      result: {'action': remove ? 'remove' : 'keep', 'cwd': back},
    );
  }
}
