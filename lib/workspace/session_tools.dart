import 'dart:async';

import '../bots/bot_tools.dart';
import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../kernel/claude_code/claude_sdk_tools.dart';
import 'workspace.dart';

/// Whether a project's agents may see the user's other conversations and
/// write to them (#934): the `chat.sessionTools` setting, off unless set.
/// Read as an agent starts: one started before has the tools as it had.
abstract final class SessionToolsSetting {
  static const settingKey = 'chat.sessionTools';

  static bool enabled(Object? setting) => setting == true;

  /// The setting as it is now; main() points it at settings.json.
  static bool Function() current = () => false;
}

/// The tools an agent coordinating others has (`mcp__baocode__session_*`),
/// with [SessionToolsSetting] on: the user's conversations listed, read
/// (without waking them) and written to (one with no process resumed as
/// it was, one at work given it in its queue), and waited on. What the
/// phones' assistant does with its bot_* tools, for a project's agents.
abstract final class SessionTools {
  static const names = [
    'session_list',
    'session_read',
    'session_send',
    'session_wait',
  ];

  /// What was sent lately, by whom to whom: the same task not sent twice.
  static final Map<(String?, String), (String, DateTime)> _sent = {};

  static const _resendAfter = Duration(minutes: 10);

  static void register(Workspace workspace) {
    for (final tool in _tools(workspace)) {
      ClaudeSdkTools.register(tool);
    }
  }

  static void unregister() {
    for (final name in names) {
      ClaudeSdkTools.unregister(name);
    }
    _sent.clear();
  }

  static List<ClaudeSdkTool> _tools(Workspace workspace) {
    bool offeredIn(String cwd) =>
        SessionToolsSetting.current() && !workspace.isAppFolder(cwd);

    /// The conversations listed, but the one asking.
    List<AgentThread> chats(ClaudeSdkCall call) => [
      for (final thread in workspace.threads)
        if (!thread.archived &&
            !workspace.isAppFolder(thread.project.path) &&
            workspace.listsInSidebar(thread) &&
            !_isCaller(thread, call))
          thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    AgentThread chat(Map<String, Object?> input, ClaudeSdkCall call) {
      final id = input['session'];
      for (final thread in workspace.threads) {
        if (BotTools.idOf(thread) != id) continue;
        if (_isCaller(thread, call)) {
          throw ArgumentError('That is this conversation.');
        }
        if (workspace.isAppFolder(thread.project.path)) break;
        return thread;
      }
      throw StateError('No session $id. List them with session_list.');
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
            'running; failed; idle) | when it last moved. Those with no '
            'process now are listed too. Only for when the user has you '
            'coordinate other conversations: do not look through them '
            'unasked.',
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
          'limit': {'type': 'integer', 'description': 'At most; 20 if none.'},
        },
        (input, call) async {
          final project = input['project'] as String?;
          final status = input['status'] as String? ?? 'all';
          final query = (input['query'] as String?)?.toLowerCase();
          final limit = ((input['limit'] as num?)?.toInt() ?? 20).clamp(1, 100);
          final lines = [
            for (final thread in chats(call))
              if ((project == null ||
                      thread.project.name == project ||
                      thread.project.path == project) &&
                  (status == 'all' || BotTools.statusOf(thread) == status) &&
                  (query == null || thread.title.toLowerCase().contains(query)))
                '${BotTools.idOf(thread)} | ${thread.project.name} | '
                    '${thread.title} | ${BotTools.statusOf(thread)} | '
                    '${BotTools.ago(thread.updatedAt)}',
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
        },
        (input, call) async {
          final thread = chat(input, call);
          final session = thread.session;
          for (var i = 0; i < 50 && session.loadingHistory; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          final count = ((input['count'] as num?)?.toInt() ?? 12).clamp(1, 60);
          final lines = <String>[];
          for (
            var i = session.itemCount - 1;
            i >= 0 && lines.length < count;
            i--
          ) {
            if (BotTools.lineOf(session.itemAt(i)) case final line?) {
              lines.add(line);
            }
          }
          return [
            '"${thread.title}" in ${thread.project.name} '
                '(${thread.project.path}): ${BotTools.statusOf(thread)}, '
                'last moved ${BotTools.ago(thread.updatedAt)}.',
            if (session.pendingInteraction != null)
              'It waits on the user to answer it (a question, a permission '
                  'or a plan to start): only they can.',
            for (final (_, message) in session.queued)
              'Queued: ${message.text.trim()}',
            ...lines.reversed,
          ].join('\n');
        },
        required: ['session'],
        summary: titled,
      ),
      tool(
        'session_send',
        'Gives another conversation a message, as from the user: it goes '
            'on in its own folder, context and permissions. One with no '
            'process now is resumed; one at work gets it in its queue, its '
            'turn not cut short. Not given while it waits on the user (they '
            'decide that), nor the same message twice. Only what the user '
            'has you hand on.',
        {
          'session': sessionId,
          'text': {'type': 'string'},
        },
        (input, call) async {
          final thread = chat(input, call);
          final text = (input['text'] as String? ?? '').trim();
          if (text.isEmpty) throw ArgumentError('text is empty');
          final session = thread.session;
          for (var i = 0; i < 50 && session.loadingHistory; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (session.pendingInteraction != null) {
            return 'Not delivered: it waits on the user to answer it (a '
                'question, a permission or a plan). Tell the user.';
          }
          final target = BotTools.idOf(thread);
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
          final from = _callerOf(workspace, call);
          session.send(
            ComposerMessage(text: text),
            notes: [
              'This message comes from another agent conversation'
                  '${from == null ? '' : ' ("${from.title}" in ${from.project.name})'}, '
                  'which the user has coordinating their conversations.',
            ],
          );
          _sent[key] = (text, now);
          return working
              ? 'Queued: it is at work, and takes this up once its turn ends.'
              : 'Sent: it is on it.';
        },
        required: ['session', 'text'],
        summary: titled,
      ),
      tool(
        'session_wait',
        'Waits for another conversation to stop working (done, failed, or '
            'waiting on the user), up to so many seconds, rather than '
            'reading it again and again. Then says where it stands.',
        {
          'session': sessionId,
          'seconds': {
            'type': 'integer',
            'description': 'At most this long: 10 to 600; 300 if none.',
          },
        },
        (input, call) async {
          final thread = chat(input, call);
          final seconds = ((input['seconds'] as num?)?.toInt() ?? 300).clamp(
            10,
            600,
          );
          final until = DateTime.now().add(Duration(seconds: seconds));
          var cancelled = false;
          unawaited(call.cancelled?.then((_) => cancelled = true));
          while (!cancelled &&
              BotTools.statusOf(thread) == 'running' &&
              DateTime.now().isBefore(until)) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          final status = BotTools.statusOf(thread);
          String? last;
          if (thread.isOpen) {
            final session = thread.session;
            for (var i = session.itemCount - 1; i >= 0; i--) {
              if (session.itemAt(i) case final AssistantTextItem item
                  when item.text.trim().isNotEmpty) {
                last = BotTools.lineOf(item);
                break;
              }
            }
          }
          return [
            if (status == 'running')
              'Still working after $seconds seconds.'
            else
              'It is $status now.',
            ?last,
          ].join('\n');
        },
        required: ['session'],
        summary: titled,
      ),
    ];
  }

  static bool _isCaller(AgentThread thread, ClaudeSdkCall call) =>
      call.sessionId != null && thread.id == call.sessionId;

  static AgentThread? _callerOf(Workspace workspace, ClaudeSdkCall call) {
    for (final thread in workspace.threads) {
      if (_isCaller(thread, call)) return thread;
    }
    return null;
  }
}
