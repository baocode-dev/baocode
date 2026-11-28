import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bots/bot_tools.dart';
import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../ide/git/git_checkout.dart' show ideSanitizeBranchName;
import '../ide/git/git_service.dart';
import '../kernel/agent_kernel.dart' show KernelChoiceKind;
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../kernel/kernel_types.dart';
import '../remote/project_host.dart';
import '../remote/remote_services.dart' show remoteGitService;
import '../remote/ssh_host.dart' show SshHost;
import 'agent_work_path.dart';
import 'chat_branch_bar.dart' show ideNewWorktreePath;
import 'workspace.dart';

/// Whether a project's agents may see the user's other conversations and
/// write to them (#934): the `chat.sessionTools` setting, off unless set.
/// Read as an agent starts: one started before has the tools as it had.
abstract final class SessionToolsSetting {
  static const settingKey = 'chat.sessionTools';

  /// Written when off; on, the setting is left out.
  static const off = false;

  /// On unless set to false.
  static bool enabled(Object? setting) => setting != false;

  /// The setting as it is now; main() points it at settings.json.
  static bool Function() current = () => true;
}

/// The bots, as the session tools see them: a bot looking after the user's
/// agents has the tools as a project's agent does, but for what it is told
/// of those it hands work to, which its own rules decide.
abstract interface class SessionToolsBots {
  /// The name of the bot working in [cwd]; null for none.
  String? botNameAt(String cwd);

  /// The bot in [cwd] handed [thread] work: told of it as its rules say.
  void handed(String cwd, AgentThread thread);

  /// Those the bot in [cwd] handed work to.
  Set<AgentThread> handedBy(String cwd);

  /// What the bot in [cwd] is told of one it handed work to, for the
  /// tools' answers.
  String toldOf(String cwd);
}

/// The tools an agent coordinating others has (`mcp__baocode__session_*`),
/// with [SessionToolsSetting] on: the user's conversations listed, read
/// (without waking them), started, written to (one with no process
/// resumed as it was, one at work given it in its queue), stopped and
/// waited on, and the files each edited listed. Each the agent started or
/// wrote to reports back to it by itself ([_Reports]). The bots that look
/// after the user's agents have them too ([SessionToolsBots]).
abstract final class SessionTools {
  static const names = [
    'session_list',
    'session_read',
    'session_new',
    'session_send',
    'session_models',
    'session_wait',
    'session_stop',
    'session_rename',
    'session_changes',
  ];

  /// What the agent is told of them, as the server's instructions.
  static const _feature = 'sessions';

  static const _instructions =
      "Coordinating the user's other agent conversations, when they ask "
      'you to (session_* tools): session_new starts one on a task, in a '
      'project of theirs (worktree: on a branch of its own, for work beside '
      'others in one repository); session_send hands one more work. Each '
      'you start or write to reports back by itself, in a message to you, '
      'once it is done, fails or waits on the user, with its whole reply: '
      'hand out the work, go on with your own, and take up each report as '
      'it comes rather than waiting (session_wait only when there is '
      'nothing else to do). Only the user answers what one waits on them '
      'for: tell them. session_changes lists the files one edited, to '
      'check its work; session_rename updates a conversation\'s title '
      'without waking or interrupting it; session_models, the models one '
      'can be on, as the user picks them.';

  /// What was sent lately, by whom to whom: the same task not sent twice.
  static final Map<(String?, String), (String, DateTime)> _sent = {};

  static const _resendAfter = Duration(minutes: 10);

  /// A reply read whole: long enough for an agent's report.
  static const _whole = 20000;

  static _Reports? _reports;

  static SessionToolsBots? _bots;

  static void register(Workspace workspace, {SessionToolsBots? bots}) {
    _reports?.dispose();
    _reports = _Reports(workspace);
    _bots = bots;
    for (final tool in _tools(workspace)) {
      ClaudeSdkTools.register(tool);
    }
    ClaudeSdkTools.instructFor(
      _feature,
      (cwd) => _offeredIn(workspace, cwd) ? _instructions : null,
    );
  }

  static void unregister() {
    for (final name in names) {
      ClaudeSdkTools.unregister(name);
    }
    ClaudeSdkTools.instruct(_feature, null);
    _reports?.dispose();
    _reports = null;
    _bots = null;
    _sent.clear();
  }

  /// A project's agent's with the setting on; a bot's whatever it says
  /// (its abilities decide, [ClaudeSdkTools.gate]).
  static bool _offeredIn(Workspace workspace, String cwd) =>
      _botAt(cwd) != null ||
      SessionToolsSetting.current() && !workspace.isAppFolder(cwd);

  static String? _botAt(String cwd) => _bots?.botNameAt(cwd);

  /// What the agent in [cwd] is told of one it handed work to.
  static String _toldOf(String cwd) => _botAt(cwd) == null
      ? 'It reports back to you by itself: go on meanwhile.'
      : _bots!.toldOf(cwd);

  static List<ClaudeSdkTool> _tools(Workspace workspace) {
    bool offeredIn(String cwd) => _offeredIn(workspace, cwd);

    /// The conversations listed, but the one asking.
    List<AgentThread> chats(ClaudeSdkCall call) => [
      for (final thread in workspace.threads)
        if (!thread.archived &&
            !workspace.isAppFolder(thread.project.path) &&
            workspace.listsInSidebar(thread) &&
            !_isCaller(thread, call))
          thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    AgentThread chat(Object? id, ClaudeSdkCall call) {
      for (final thread in workspace.threads) {
        if (thread.id != id && BotTools.idOf(thread) != id) continue;
        if (_isCaller(thread, call)) {
          throw ArgumentError('That is this conversation.');
        }
        if (workspace.isAppFolder(thread.project.path)) break;
        return thread;
      }
      throw StateError('No session $id. List them with session_list.');
    }

    /// Those the agent asking started or wrote to.
    Set<AgentThread> mine(ClaudeSdkCall call) => _botAt(call.cwd) == null
        ? _reports?.mine[call.sessionId] ?? const {}
        : _bots!.handedBy(call.cwd);

    /// The project [name] names (its name or folder); the asking agent's
    /// own for none, a project's agent's.
    Project projectNamed(Object? name, ClaudeSdkCall call) {
      final listed = [
        for (final project in workspace.sidebarProjects)
          if (!workspace.isAppFolder(project.path)) project,
      ];
      String theirs() =>
          'Theirs: ${listed.map((project) => '${project.name} (${project.path})').join(', ')}';
      if (name is! String || name.trim().isEmpty) {
        final own =
            _callerOf(workspace, call)?.project ??
            workspace.projectAt(call.cwd);
        if (workspace.isAppFolder(own.path)) {
          throw ArgumentError('Name its project. ${theirs()}');
        }
        return own;
      }
      final named = name.trim();
      return listed.where((project) => project.path == named).firstOrNull ??
          listed.where((project) => project.name == named).firstOrNull ??
          (throw ArgumentError('No project "$named". ${theirs()}'));
    }

    String titled(Map<String, Object?> input, String? _) =>
        '${input['session'] ?? ''}';

    ClaudeSdkTool tool(
      String name,
      String description,
      Map<String, Object?> properties,
      Future<Object> Function(Map<String, Object?> input, ClaudeSdkCall call)
      run, {
      List<String> required = const [],
      String Function(Map<String, Object?> input, String? output)? summary,
    }) => ClaudeSdkTool(
      name: name,
      description: description,
      inputSchema: {
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
      },
      run: run,
      kind: ToolKind.other,
      summary: summary,
      offeredIn: offeredIn,
    );

    const sessionId = {
      'type': 'string',
      'description': "The conversation's id, as session_list gives it.",
    };

    return [
      tool(
        'session_list',
        "Lists the user's other agent conversations in BaoCode, latest "
            'first: id | project | title | status (waiting = on the user; '
            'running; failed; idle) | when it last moved | its model, and '
            '"yours" for one you started or wrote to. Those with no process now are '
            'listed too. Only for when the user has you coordinate other '
            'conversations: do not look through them unasked.',
        {
          'project': {
            'type': 'string',
            'description': "Only this project's (its name or folder).",
          },
          'status': {
            'type': 'string',
            'enum': ['all', 'waiting', 'running', 'failed', 'idle'],
          },
          'query': {
            'type': 'string',
            'description': 'Only those whose title has this in it.',
          },
          'mine': {
            'type': 'boolean',
            'description': 'Only those you started or wrote to.',
          },
          'limit': {'type': 'integer', 'description': 'At most; 20 if none.'},
        },
        (input, call) async {
          final project = input['project'] as String?;
          final status = input['status'] as String? ?? 'all';
          final query = (input['query'] as String?)?.toLowerCase();
          final yours = mine(call);
          final onlyMine = input['mine'] == true;
          final limit = ((input['limit'] as num?)?.toInt() ?? 20).clamp(1, 100);
          final lines = [
            for (final thread in chats(call))
              if ((project == null ||
                      thread.project.name == project ||
                      thread.project.path == project) &&
                  (status == 'all' || BotTools.statusOf(thread) == status) &&
                  (query == null ||
                      thread.title.toLowerCase().contains(query)) &&
                  (!onlyMine || yours.contains(thread)))
                '${idOf(thread)} | ${thread.project.name} | '
                    '${thread.title} | ${BotTools.statusOf(thread)} | '
                    '${BotTools.ago(thread.updatedAt)}'
                    '${switch (_modelOf(thread)) {
                      final model? => ' | $model',
                      null => '',
                    }}'
                    '${yours.contains(thread) ? ' | yours' : ''}',
          ];
          return lines.isEmpty ? 'None.' : lines.take(limit).join('\n');
        },
      ),
      tool(
        'session_read',
        "Where another conversation stands: its status, what waits in its "
            'queue, what it waits on the user for, and its last items (the '
            "user's messages, its replies, its steps in short). Reading does "
            'not wake it.',
        {
          'session': sessionId,
          'count': {
            'type': 'integer',
            'description': 'How many of its last items; 12 if none.',
          },
          'skip': {
            'type': 'integer',
            'description':
                'How many of its last items to pass over first: to read '
                'further back.',
          },
          'full': {
            'type': 'boolean',
            'description':
                'Messages and replies whole, not clipped at 600 characters.',
          },
        },
        (input, call) async {
          final thread = chat(input['session'], call);
          final session = await _opened(thread);
          final count = ((input['count'] as num?)?.toInt() ?? 12).clamp(1, 60);
          var skip = ((input['skip'] as num?)?.toInt() ?? 0).clamp(0, 100000);
          final max = input['full'] == true ? _whole : 600;
          final lines = <String>[];
          for (
            var i = session.itemCount - 1;
            i >= 0 && lines.length < count;
            i--
          ) {
            if (BotTools.lineOf(session.itemAt(i), max: max) case final line?) {
              if (skip > 0) {
                skip--;
              } else {
                lines.add(line);
              }
            }
          }
          return [
            '"${thread.title}" in ${thread.project.name} '
                '(${thread.project.path}): ${BotTools.statusOf(thread)}, '
                'last moved ${BotTools.ago(thread.updatedAt)}'
                '${switch (_modelOf(thread)) {
                  final model? => ', on $model',
                  null => '',
                }}.',
            if (_waitsFor(session) case final asked?)
              '$asked Only the user can answer it.',
            for (final (_, message) in session.queued)
              'Queued: ${message.text.trim()}',
            ...lines.reversed,
          ].join('\n');
        },
        required: ['session'],
        summary: titled,
      ),
      tool(
        'session_new',
        'Starts a new conversation on a task, its first message [text] as '
            "from the user: in a project of theirs (this one's if none), "
            'with their approvals as yours are, on the model given '
            "(session_models lists them) or else the user's default for new "
            'conversations. It reports back to you by '
            'itself once it is done, fails or waits on the user. Only for '
            'work the user has you hand out.',
        {
          'text': {'type': 'string', 'description': 'The task, in full.'},
          'project': {
            'type': 'string',
            'description': 'Its project: its name or folder.',
          },
          'title': {
            'type': 'string',
            'description': 'Its title in the list; made from the task if none.',
          },
          'model': {
            'type': 'string',
            'description':
                "Its model's id, as session_models lists them; the user's "
                'default for new conversations if none. Pick one only for '
                'a reason (the user asked, or the task is light or hard).',
          },
          'worktree': {
            'type': 'string',
            'description':
                'A new branch to work on, in a worktree of its own beside '
                "the repository's folder: for work beside others in one "
                'repository.',
          },
        },
        (input, call) async {
          final text = (input['text'] as String? ?? '').trim();
          if (text.isEmpty) throw ArgumentError('text is empty');
          final project = projectNamed(input['project'], call);
          final caller = _callerOf(workspace, call);
          // Checked before anything is made.
          final model = switch (input['model']) {
            final String name when name.trim().isNotEmpty => _modelNamed(
              caller?.session.models?.options ?? const [],
              name.trim(),
            ),
            _ => null,
          };
          final worktree = switch (input['worktree']) {
            final String branch when branch.trim().isNotEmpty =>
              await _newWorktree(workspace, project, branch.trim()),
            _ => null,
          };
          final thread = workspace.startAgent(project);
          final session = thread.session;
          if (model != null) {
            _select(session.models, model.id);
          }
          // A bot's leave (all, with no one at the computer) not passed on:
          // the user's default for new conversations.
          if (_botAt(call.cwd) == null) {
            if (caller?.session.selected(KernelChoiceKind.permission)
                case final permission?) {
              _select(session.permissions, permission);
            }
            if (caller != null && !workspace.isAppFolder(caller.project.path)) {
              workspace.attachChild(thread, caller);
            }
          }
          if (input['title'] case final String title
              when title.trim().isNotEmpty) {
            workspace.rename(thread, title.trim());
          }
          _hand(workspace, call, thread, switch (worktree) {
            (:final path, :final branch) =>
              'Work in $path (branch $branch, a worktree made for this '
                  'task): read and edit the files and run the commands '
                  'there.\n\n$text',
            null => text,
          });
          return [
            'Started: ${idOf(thread)} in ${project.name}'
                '${switch (_modelOf(thread)) {
                  final model? => ', on $model',
                  null => '',
                }}.',
            if (worktree case (:final path, :final branch))
              'It works in $path, on the new branch $branch.',
            _toldOf(call.cwd),
          ].join(' ');
        },
        required: ['text'],
        summary: (input, _) => '${input['title'] ?? input['project'] ?? ''}',
      ),
      tool(
        'session_send',
        'Gives another conversation a message, as from the user: it goes '
            'on in its own folder, context and permissions. One with no '
            'process now is resumed; one at work gets it in its queue, its '
            'turn not cut short. It reports back to you by itself once it '
            'is done, fails or waits on the user. Not given while it waits '
            'on the user (they decide that), nor the same message twice. '
            'With [model], it goes on on that model (as the user would pick '
            'it). Only what the user has you hand on.',
        {
          'session': sessionId,
          'text': {'type': 'string'},
          'model': {
            'type': 'string',
            'description':
                'The model it goes on on, its id as session_models lists '
                'them; the one it is on if none.',
          },
        },
        (input, call) async {
          final thread = chat(input['session'], call);
          final text = (input['text'] as String? ?? '').trim();
          if (text.isEmpty) throw ArgumentError('text is empty');
          final session = await _opened(thread);
          if (_waitsFor(session) case final asked?) {
            return 'Not delivered: it waits on the user. $asked Only they '
                'can answer it: tell them.';
          }
          final target = idOf(thread);
          final key = (call.sessionId, target);
          final now = DateTime.now();
          if (_sent[key] case (final last, final at)
              when last == text && now.difference(at) < _resendAfter) {
            return 'Not delivered: the same message was sent to it '
                '${BotTools.ago(at)}.';
          }
          if (!session.canSend) {
            return 'Not delivered: it is at work and takes no message '
                'until its turn ends. Try again then (session_wait).';
          }
          final working = session.isStreaming;
          if (input['model'] case final String name
              when name.trim().isNotEmpty) {
            final model = _modelNamed(
              session.models?.options ?? const [],
              name.trim(),
            );
            if (working && session.switchRestarts(model.id)) {
              return 'Not delivered: it is at work, and ${model.id} would '
                  'restart it on another upstream. Try again once its turn '
                  'ends (session_wait).';
            }
            _select(session.models, model.id);
          }
          _hand(workspace, call, thread, text);
          _sent[key] = (text, now);
          return working
              ? 'Queued: it is at work, and takes this up once its turn '
                    'ends. ${_toldOf(call.cwd)}'
              : 'Sent: it is on it. ${_toldOf(call.cwd)}';
        },
        required: ['session', 'text'],
        summary: titled,
      ),
      tool(
        'session_models',
        'The models a conversation can be on, as the user picks them in '
            'BaoCode (by upstream): id | name, and which new conversations '
            'start on and which you are on. For session_new and '
            "session_send's model.",
        const {},
        (input, call) async {
          final caller = _callerOf(workspace, call);
          final options =
              caller?.session.models?.options ?? const <KernelOption>[];
          if (options.isEmpty) return 'No models known yet.';
          final mine = caller?.session.selected(KernelChoiceKind.model);
          final fresh = workspace.newAgentModel;
          final lines = <String>[];
          String? group;
          for (final option in options) {
            final heading = option.group?.label;
            if (heading != null && heading != group) {
              group = heading;
              lines.add('$heading:');
            }
            lines.add(
              '${heading == null ? '' : '  '}${option.id} | ${option.label}'
              '${option.id == fresh ? ' | new conversations start on it' : ''}'
              '${option.id == mine ? ' | you are on it' : ''}',
            );
          }
          return lines.join('\n');
        },
      ),
      tool(
        'session_wait',
        'Waits for other conversations to stop working (done, failed, or '
            'waiting on the user), up to so many seconds: the first of them '
            'to stop says where it stands, with its whole reply. Those you '
            'started or wrote to report back by themselves: wait only when '
            'you have nothing else to do.',
        {
          'session': sessionId,
          'sessions': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Or several, by their ids: the first to stop says.',
          },
          'seconds': {
            'type': 'integer',
            'description': 'At most this long: 10 to 600; 300 if none.',
          },
        },
        (input, call) async {
          final ids = {
            if (input['session'] case final String id) id,
            if (input['sessions'] case final List<Object?> ids)
              ...ids.whereType<String>(),
          };
          if (ids.isEmpty) throw ArgumentError('No session to wait for.');
          final threads = [for (final id in ids) chat(id, call)];
          final seconds = ((input['seconds'] as num?)?.toInt() ?? 300).clamp(
            10,
            600,
          );
          final until = DateTime.now().add(Duration(seconds: seconds));
          var cancelled = false;
          unawaited(call.cancelled?.then((_) => cancelled = true));
          List<AgentThread> stopped() => [
            for (final thread in threads)
              if (!_working(_stateOf(thread))) thread,
          ];
          Future<void> wait() async {
            while (!cancelled &&
                stopped().isEmpty &&
                DateTime.now().isBefore(until)) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          }

          await (_reports?.waiting(call.sessionId, {...threads}, wait) ??
              wait());
          final done = stopped();
          final working = [
            for (final thread in threads)
              if (!done.contains(thread)) idOf(thread),
          ];
          if (done.isEmpty) {
            return 'Still working after $seconds seconds: '
                '${working.join(', ')}.';
          }
          return [
            for (final thread in done) _standing(thread, await _opened(thread)),
            if (working.isNotEmpty) 'Still working: ${working.join(', ')}.',
          ].join('\n\n');
        },
        summary: (input, _) =>
            '${input['session'] ?? (input['sessions'] as List?)?.join(', ') ?? ''}',
      ),
      tool(
        'session_stop',
        'Stops the turn another conversation is working on, as the user '
            "would: for work you handed it that went wrong, or as the user "
            'asks. What waits in its queue is taken up next.',
        {'session': sessionId},
        (input, call) async {
          final thread = chat(input['session'], call);
          if (!thread.isOpen || !thread.session.isStreaming) {
            return 'It is not working on anything.';
          }
          // Stopped by the one who would be told of it.
          if (call.sessionId case final by?) _reports?.unfollow(by, thread);
          thread.session.stop();
          return thread.session.queued.isEmpty
              ? 'Stopped.'
              : 'Stopped: it takes up what waits in its queue next.';
        },
        required: ['session'],
        summary: titled,
      ),
      tool(
        'session_rename',
        'Renames another conversation in BaoCode without waking, interrupting, '
            'or queuing a message for it (works whether it is running or '
            'idle). The new title is persisted and shown in the list and '
            'reports immediately.',
        {
          'session': sessionId,
          'title': {
            'type': 'string',
            'description': 'The new title for the conversation.',
          },
        },
        (input, call) async {
          final thread = chat(input['session'], call);
          final title = (input['title'] as String? ?? '').trim();
          if (title.isEmpty) throw ArgumentError('title is empty');
          final previous = thread.title;
          workspace.rename(thread, title);
          return previous == thread.title
              ? 'Already named "${thread.title}".'
              : 'Renamed ${idOf(thread)} from "$previous" to "${thread.title}".';
        },
        required: ['session', 'title'],
        summary: (input, _) => '${input['title'] ?? input['session'] ?? ''}',
      ),
      tool(
        'session_changes',
        'The files another conversation edited, with the lines added and '
            'removed of those the user has not kept or undone yet, and '
            'where it last worked (a worktree, say): to check its work. '
            'Reading does not wake it.',
        {'session': sessionId},
        (input, call) async {
          final thread = chat(input['session'], call);
          final session = await _opened(thread);
          final pending = {
            for (final change in session.fileChanges) change.path: change,
          };
          final edited = <String>{
            for (var i = 0; i < session.itemCount; i++)
              if (session.itemAt(i)
                  case ToolCallItem(kind: ToolKind.edit, :final path?)
                  when path.isNotEmpty)
                path,
            ...pending.keys,
          };
          final at = agentWorkPathOf(session);
          return [
            if (edited.isEmpty)
              'It edited no files.'
            else ...[
              'The files it edited:',
              for (final path in edited)
                switch (pending[path]) {
                  final change? => '$path +${change.added} -${change.removed}',
                  null => path,
                },
            ],
            if (at != null && !at.startsWith(thread.project.root))
              'It last worked at $at.',
          ].join('\n');
        },
        required: ['session'],
        summary: titled,
      ),
    ];
  }

  /// [text] to [thread] from the agent asking: as another agent's message,
  /// shown as such, with what the agent there should know of it. The one
  /// asking is told when it is done ([_Reports]).
  static void _hand(
    Workspace workspace,
    ClaudeSdkCall call,
    AgentThread thread,
    String text,
  ) {
    final bot = _botAt(call.cwd);
    final from = _callerOf(workspace, call);
    if (bot != null) {
      _bots!.handed(call.cwd, thread);
    } else if (call.sessionId case final by?) {
      _reports?.follow(by, thread);
    }
    thread.session.send(
      ComposerMessage(
        text: thread.kernel.id == 'claude-code'
            ? agentMessage(
                bot ?? from?.title ?? 'Another conversation',
                text,
                session: from == null || bot != null ? null : idOf(from),
              )
            : text,
      ),
      notes: [
        if (bot != null)
          '<system-reminder>This message comes from $bot, the user\'s '
              'bot looking after their agents for them on their phone: take '
              'it up as their request. Your reply, once your turn ends, '
              'reaches it by itself: no need to write to it.'
              '</system-reminder>'
        else
          '<system-reminder>This message comes from another of the user\'s '
              'agent conversations'
              '${from == null ? '' : ' ("${from.title}" in ${from.project.name}, session ${idOf(from)})'}'
              ', which the user has coordinating their conversations: take it '
              'up as their request. Your reply, once your turn ends, goes back '
              'to it by itself: no need to write to it.</system-reminder>',
      ],
    );
  }

  /// [text] as a message from another agent, [from] it: shown as its card.
  @visibleForTesting
  static String agentMessage(String from, String text, {String? session}) =>
      '<agent-message from="${from.replaceAll('"', "'")}"'
      '${session == null ? '' : ' session="${session.replaceAll('"', '')}"'}>'
      '$text</agent-message>';

  /// The model [thread] is on, for the agent: its name and id.
  static String? _modelOf(AgentThread thread) => switch (modelOf(thread)) {
    (:final id, :final label) => label == id ? id : '$label ($id)',
    null => null,
  };

  /// The model [thread] is on: its id, and its name as the user sees it;
  /// null for one not open, or a kernel without models.
  static ({String id, String label})? modelOf(AgentThread thread) {
    if (!thread.isOpen) return null;
    final choice = thread.session.models;
    if (choice == null) return null;
    final option = choice.selected;
    return (id: option.id, label: option.label);
  }

  /// [thread]'s id for these tools: its session's once it has one (kept
  /// from run to run), else the one it goes by until then.
  static String idOf(AgentThread thread) => thread.id ?? BotTools.idOf(thread);

  /// The conversation [id] names ([idOf], or the one it went by before its
  /// session started); null for none.
  static AgentThread? threadOf(Workspace workspace, String id) {
    for (final thread in workspace.threads) {
      if (thread.id == id || BotTools.idOf(thread) == id) return thread;
    }
    return null;
  }

  /// The conversations [session] handed work to (session_new,
  /// session_send) or heard from, in the order it first did: as its steps
  /// and messages say, from run to run.
  static List<AgentThread> handedFrom(
    ChatSession session,
    Workspace workspace,
  ) {
    final ids = <String>{};
    for (var i = 0; i < session.itemCount; i++) {
      switch (session.itemAt(i)) {
        case ToolCallItem(tool: 'session_new', :final output?):
          if (_started.firstMatch(output)?[1] case final id?) ids.add(id);
        case ToolCallItem(tool: 'session_send', :final input):
          if (input['session'] case final String id) ids.add(id);
        case UserMessageItem(fromSession: final id?):
          ids.add(id);
        default:
      }
    }
    final threads = <AgentThread>[];
    for (final id in ids) {
      if (threadOf(workspace, id) case final thread?
          when !threads.contains(thread)) {
        threads.add(thread);
      }
    }
    return threads;
  }

  static final _started = RegExp(r'^Started: (\S+)');

  static KernelOption _modelNamed(List<KernelOption> options, String name) {
    final wanted = name.toLowerCase();
    return options.where((o) => o.id.toLowerCase() == wanted).firstOrNull ??
        options.where((o) => o.label.toLowerCase() == wanted).firstOrNull ??
        (throw ArgumentError(
          'No model "$name". The models: '
          '${options.map((o) => '${o.id} (${o.label})').join(', ')}',
        ));
  }

  /// [id] picked of [choice], where it is one of its options.
  static void _select(KernelChoice? choice, String id) {
    if (choice == null || choice.selected.id == id) return;
    if (choice.options.where((o) => o.id == id).firstOrNull
        case final option?) {
      choice.onSelected(option);
    }
  }

  /// A worktree of [project]'s repository on a new [branch], beside its
  /// folder, as the branch bar's New Worktree… makes them.
  static Future<({String path, String branch})> _newWorktree(
    Workspace workspace,
    Project project,
    String branch,
  ) async {
    final name = ideSanitizeBranchName(branch);
    if (name.isEmpty) throw ArgumentError('"$branch" is no branch name.');
    if (workspace.multiRootAt(project.path) != null) {
      throw StateError(
        '${project.name} is a workspace of several folders: no worktree for '
        'it. Start it there and have it make one where it should.',
      );
    }
    final host = ProjectHost.of(project.path);
    final git = switch (host) {
      final SshHost host => remoteGitService(host, project.root),
      _ => IdeGitService(project.root),
    };
    final worktrees = await git.worktrees();
    final main =
        worktrees.where((worktree) => worktree.main).firstOrNull?.path ??
        project.root;
    final path = ideNewWorktreePath(
      main,
      name,
      taken: [for (final worktree in worktrees) worktree.path],
      paths: host.paths,
    );
    await git.addWorktree(path, newBranch: name);
    return (path: path, branch: name);
  }

  /// [thread]'s conversation, its history read.
  static Future<ChatSession> _opened(AgentThread thread) async {
    final session = thread.session;
    for (var i = 0; i < 50 && session.loadingHistory; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return session;
  }

  static _State _stateOf(AgentThread thread) {
    if (!thread.isOpen) return _State.done;
    return switch (thread.status) {
      ThreadStatus.needsInput => _State.waiting,
      ThreadStatus.running => _State.running,
      // Taken up next.
      _ when thread.session.queued.isNotEmpty => _State.running,
      _ when BotTools.statusOf(thread) == 'failed' => _State.failed,
      _ => _State.done,
    };
  }

  static bool _working(_State state) =>
      state == _State.sent || state == _State.running;

  /// Where [thread] stands, for the agent that handed it work: with its
  /// whole reply once it stopped.
  static String _standing(AgentThread thread, ChatSession session) {
    final name = '${idOf(thread)} ("${thread.title}")';
    String reply() => switch (session.lastTurnReply) {
      final reply? => '\nIts reply:\n\n${_clip(reply, _whole)}',
      null => '\nIt said nothing since it was last written to.',
    };
    return switch (_stateOf(thread)) {
      _State.sent || _State.running => '$name is still working.',
      _State.waiting =>
        '$name waits on the user. ${_waitsFor(session) ?? ''} Only they '
            'can answer it: tell them.',
      _State.failed =>
        '$name stopped on an error: ${_error(session) ?? 'unknown'}.'
            '${reply()}',
      _State.done => '$name is done.${reply()}',
    };
  }

  /// [thread]'s report back, once it stopped: [text] as the user reads it
  /// in the card (its reply whole, or what it asks them), [note] for the
  /// agent, how it stands.
  static ({String text, String note}) _report(
    AgentThread thread,
    ChatSession session,
  ) {
    final name = '${idOf(thread)} ("${thread.title}")';
    final reply = switch (session.lastTurnReply) {
      final reply? => _clip(reply, _whole),
      null => null,
    };
    return switch (_stateOf(thread)) {
      _State.waiting => (
        text: _asked(session) ?? thread.title,
        note:
            '$name waits on the user. ${_waitsFor(session) ?? ''} Only they '
            'can answer it: tell them, rather than waiting.',
      ),
      _State.failed => (
        text: [_error(session) ?? 'Error', ?reply].join('\n\n'),
        note:
            '$name stopped on an error: the message has it, and what it said '
            'before.',
      ),
      _ => (
        text: reply ?? '…',
        note: reply == null
            ? '$name is done, and said nothing.'
            : '$name is done: the message is its whole reply.',
      ),
    };
  }

  /// What [session] asks the user, as they would read it: its questions
  /// and their options, the command it asks leave for, its plan's title;
  /// null for nothing.
  static String? _asked(ChatSession session) {
    switch (session.pendingInteraction) {
      case QuestionRequest(:final questions):
        return [
          for (final question in questions)
            [
              question.prompt,
              for (final option in question.options) '- ${option.label}',
            ].join('\n'),
        ].join('\n\n');
      case ApprovalRequest(:final toolName, :final preview, :final title):
        return switch (preview) {
          CommandPreview(:final command) => '`$toolName`\n\n```\n$command\n```',
          DiffPreview(:final path) => '`$toolName` $path',
          TextPreview(:final text) => '`$toolName`\n\n${_clip(text, 600)}',
          null => title.isEmpty ? '`$toolName`' : title,
        };
      case null:
    }
    if (session.canStartPlan) {
      final plan = session.awaitingPlan!;
      return plan.title ?? plan.path;
    }
    return null;
  }

  /// What [session] waits on the user for, in a line or so; null for
  /// nothing.
  static String? _waitsFor(ChatSession session) {
    switch (session.pendingInteraction) {
      case QuestionRequest(:final questions):
        return 'It asks them: ${[for (final question in questions) '${question.prompt}${question.options.isEmpty ? '' : ' (${question.options.map((o) => o.label).join(' / ')})'}'].join(' ')}';
      case ApprovalRequest(:final toolName, :final preview, :final reason):
        final what = switch (preview) {
          CommandPreview(:final command) => command,
          DiffPreview(:final path) => path,
          TextPreview(:final text) => text,
          null => null,
        };
        return 'It asks leave to use $toolName'
            '${what == null ? '' : ': ${_clip(what, 400)}'}'
            '${reason == null ? '' : ' ($reason)'}.';
      case null:
    }
    if (session.canStartPlan) {
      final plan = session.awaitingPlan!;
      return 'Its plan${plan.title == null ? '' : ' "${plan.title}"'} '
          '(${plan.path}) awaits them to start it.';
    }
    return null;
  }

  static String? _error(ChatSession session) {
    for (var i = session.itemCount - 1; i >= 0; i--) {
      switch (session.itemAt(i)) {
        case NoticeItem(kind: NoticeKind.error, :final text):
          return _clip(text.split('\n').first, 400);
        case UserMessageItem() || AssistantTextItem():
          return null;
        default:
      }
    }
    return null;
  }

  static String _clip(String text, int max) {
    final trimmed = text.trim();
    return trimmed.length > max ? '${trimmed.substring(0, max)}…' : trimmed;
  }

  static bool _isCaller(AgentThread thread, ClaudeSdkCall call) =>
      call.sessionId != null && thread.id == call.sessionId;

  static AgentThread? _callerOf(Workspace workspace, ClaudeSdkCall call) =>
      _threadWithId(workspace, call.sessionId);

  static AgentThread? _threadWithId(Workspace workspace, String? id) {
    if (id == null) return null;
    for (final thread in workspace.threads) {
      if (thread.id == id) return thread;
    }
    return null;
  }
}

/// How a conversation handed work stands, as its reports go.
enum _State { sent, running, waiting, done, failed }

/// The reports back: each conversation an agent started or wrote to tells
/// it, in a message of its own, once it is done or fails (once, until
/// written to again) or waits on the user; not while the agent waits on
/// it (session_wait), which says so itself. Kept for this run.
class _Reports {
  _Reports(this.workspace) {
    workspace.addListener(_changed);
  }

  final Workspace workspace;

  /// Those each agent started or wrote to, by its session's id.
  final Map<String, Set<AgentThread>> mine = {};

  /// Who is told of each conversation (their sessions' ids), and how it
  /// stood when last looked at.
  final Map<AgentThread, Set<String>> _told = Map.identity();
  final Map<AgentThread, _State> _was = Map.identity();

  /// What agents wait on (session_wait): who, and on which.
  final List<(String, Set<AgentThread>)> _waits = [];

  /// Reports not given yet (the agent to tell waits on the user, say):
  /// who to, from which conversation, and what (see [SessionTools._report]).
  final List<(String, AgentThread, ({String text, String note}))> _undelivered =
      [];

  void follow(String by, AgentThread thread) {
    (mine[by] ??= {}).add(thread);
    (_told[thread] ??= {}).add(by);
    _was[thread] = _State.sent;
  }

  void unfollow(String by, AgentThread thread) {
    final told = _told[thread];
    if (told == null) return;
    told.remove(by);
    if (told.isEmpty) _forget(thread);
  }

  /// [wait] run with [by] waiting on [threads]: what it says is not told
  /// again.
  Future<void> waiting(
    String? by,
    Set<AgentThread> threads,
    Future<void> Function() wait,
  ) async {
    if (by == null) return wait();
    final entry = (by, threads);
    _waits.add(entry);
    try {
      await wait();
    } finally {
      _waits.remove(entry);
    }
  }

  void _forget(AgentThread thread) {
    _told.remove(thread);
    _was.remove(thread);
  }

  void _changed() {
    // Turned off: no conversation hears of another any more, those
    // followed forgotten (their tools are refused as well).
    if (!SessionToolsSetting.current()) {
      if (_told.isNotEmpty || _undelivered.isNotEmpty || mine.isNotEmpty) {
        _told.clear();
        _was.clear();
        _undelivered.clear();
        mine.clear();
      }
      return;
    }
    if (_told.isNotEmpty) _look();
    if (_undelivered.isNotEmpty) scheduleMicrotask(_deliver);
  }

  void _look() {
    final threads = workspace.threads.toSet();
    for (final MapEntry(key: thread, value: told) in [..._told.entries]) {
      if (!threads.contains(thread) || thread.archived) {
        _forget(thread);
        continue;
      }
      final now = SessionTools._stateOf(thread);
      final was = _was[thread];
      _was[thread] = now;
      if (now == was) continue;
      final tell = switch (now) {
        _State.waiting => true,
        _State.done ||
        _State.failed => was == _State.running || was == _State.waiting,
        _ => false,
      };
      if (!tell) continue;
      final report = SessionTools._report(thread, thread.session);
      for (final by in [...told]) {
        // Told it once: until written to again; but what it waits on the
        // user for, it goes on from.
        if (now != _State.waiting) told.remove(by);
        final waited = _waits.any(
          (wait) => wait.$1 == by && wait.$2.contains(thread),
        );
        if (!waited) _undelivered.add((by, thread, report));
      }
      if (told.isEmpty) _forget(thread);
    }
  }

  void _deliver() {
    for (final report in [..._undelivered]) {
      final (to, from, (:text, :note)) = report;
      final agent = SessionTools._threadWithId(workspace, to);
      if (agent == null || agent.archived) {
        _undelivered.remove(report);
        continue;
      }
      final session = agent.session;
      // Not as an answer to what it waits on the user for.
      if (session.loadingHistory ||
          session.pendingInteraction != null ||
          session.canStartPlan ||
          !session.canSend) {
        continue;
      }
      _undelivered.remove(report);
      session.send(
        ComposerMessage(
          text: SessionTools.agentMessage(
            from.title,
            text,
            session: SessionTools.idOf(from),
          ),
        ),
        notes: [
          '<system-reminder>A report from a conversation you handed work '
              'to (session_new or session_send), sent by the app, not by the '
              'user: $note Go on with the coordinating as it needs, and tell '
              'the user what they should know.</system-reminder>',
        ],
      );
    }
  }

  void dispose() => workspace.removeListener(_changed);
}
