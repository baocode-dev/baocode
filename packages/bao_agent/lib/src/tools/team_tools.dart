import '../engine/session.dart';
import '../permissions/decision.dart';
import '../util/json.dart';
import 'agent_tool.dart';
import 'tool.dart';

/// Sends a message to another agent of the session: a subagent (at work,
/// or done and taken up again), or the main conversation.
class SendMessageTool extends Tool {
  const SendMessageTool();

  @override
  String get name => 'SendMessage';

  @override
  String get description => '''Sends a message to another agent of this session.

```json
{"to": "a3f9c2d1", "summary": "next step", "message": "Now look at the tests too."}
```

`to` is one of:
- an agent's ID, as the Agent tool gave it, or as ListAgents lists it;
- `"main"`: the main conversation (for an agent working in the background).

What you write as text is not seen by other agents: to tell one something, call this tool. Messages to you come by themselves; there is no inbox to look in.

- An agent at work takes your message up between its tool calls.
- An agent that is done goes back to work on it, with all it had, in the background; you are told when it is done again. This is how to have an agent go on rather than start a new one.
- Its first line is what is shown of it at first: make that line say what the message is about, not a greeting.
- Do not ask another agent to do what was refused or blocked here: route that back to the user.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'to': {
        'type': 'string',
        'description':
            'Who it is for: an agent\'s ID (from the Agent tool or '
            'ListAgents), or "main"',
        'allOf': [
          {'pattern': r'^[^\n\r]*$'},
          {'pattern': r'^[\s\S]{0,300}$'},
        ],
      },
      'summary': {
        'type': 'string',
        'maxLength': 200,
        'description':
            'A label of 5 to 10 words for your own record of it (not sent: '
            'the other agent sees the message\'s first line). Cut at 200 '
            'characters',
      },
      'message': {
        'type': 'string',
        'default': '',
        'description':
            'The message, as plain text. Make its first line a sentence that '
            'says what it is about: it is what is shown of it at first',
      },
    },
    'required': ['to', 'message'],
    'additionalProperties': false,
  };

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
    final to = '${input['to'] ?? ''}'.trim();
    final message = '${input['message'] ?? ''}';
    final from = context.run.agentId ?? 'main';
    if (message.trim().isEmpty) {
      return ToolOutput.error('The message is empty.');
    }
    if (to == from) return ToolOutput.error('That is you.');
    if (to == 'main') {
      if (context.run.isMain) {
        return ToolOutput.error('You are the main conversation.');
      }
      session.deliverToMain(from, message);
      return ToolOutput(
        'Message sent to the main conversation.',
        result: {'success': true, 'to': 'main'},
      );
    }
    final job = find(session, to);
    if (job == null) {
      final ids = session.subagents.keys.join(', ');
      return ToolOutput.error(
        'No agent "$to" in this session.'
        '${ids.isEmpty ? '' : ' The agents there are: $ids.'}',
      );
    }
    final task = job.send(message, from);
    if (task != null) {
      return AgentTool.launched(job, task, resumed: true);
    }
    return ToolOutput(
      'Message sent to ${job.agentId}: it takes it up between its tool calls.',
      result: {'success': true, 'to': job.agentId},
    );
  }

  /// The subagent [to] names: by its ID, else by its description when
  /// only one has it.
  static SubagentJob? find(AgentSession session, String to) {
    if (session.subagents[to] case final job?) return job;
    final named = [
      for (final job in session.subagents.values)
        if (job.description.toLowerCase() == to.toLowerCase()) job,
    ];
    return named.length == 1 ? named.single : null;
  }
}

/// Lists the agents a message can be sent to.
class ListAgentsTool extends Tool {
  const ListAgentsTool();

  @override
  String get name => 'ListAgents';

  @override
  String get description =>
      'Lists the agents of this session you can send a message to with '
      'SendMessage: the subagents started in it, at work or done, and the '
      'main conversation (for an agent). Each line leads with the name to '
      'send to.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

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
    final self = context.run.agentId;
    final rows = <Map<String, Object?>>[
      if (self != null)
        {'name': 'main', 'kind': 'main conversation', 'status': 'active'},
      for (final job in context.session.subagents.values)
        if (job.agentId != self)
          {
            'name': job.agentId,
            'kind': 'subagent',
            'agentType': job.agent.name,
            'description': job.description,
            'status': job.running ? 'busy' : job.status,
          },
    ];
    if (rows.isEmpty) {
      return const ToolOutput(
        'There are no other agents in this session.',
        result: {'agents': []},
      );
    }
    return ToolOutput(
      [
        for (final row in rows)
          row['kind'] == 'main conversation'
              ? '- main: the main conversation'
              : '- ${row['name']}: ${row['description']} '
                    '(${row['agentType']}, ${row['status']})',
      ].join('\n'),
      result: {'agents': rows},
    );
  }

  @override
  bool isEnabled(AgentSession session) => true;
}

/// Reports the findings of a code review as a list the host can show.
class ReportFindingsTool extends Tool {
  const ReportFindingsTool();

  @override
  String get name => 'ReportFindings';

  @override
  String get description =>
      'Reports the findings of a code review as a typed list, for the host '
      'to show. Use it only when the review\'s instructions say to report '
      'with it; otherwise report as they say. Call it once, with the '
      'findings that held up, the most serious first (an empty list when '
      'none did), and do not also write them out as text. When reporting '
      'again after fixes (only if the instructions ask for it), set each '
      'finding\'s `outcome` to what was done about it.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'level': {
        'type': 'string',
        'enum': ['low', 'medium', 'high', 'xhigh', 'max'],
        'description': 'The effort the review was done at',
      },
      'findings': {
        'type': 'array',
        'maxItems': 32,
        'description':
            'The findings that held up, the most serious first; empty if '
            'none did',
        'items': {
          'type': 'object',
          'properties': {
            'file': {
              'type': 'string',
              'description': 'The file it is in, relative to the repository',
            },
            'line': {
              'type': 'integer',
              'minimum': -9007199254740991,
              'maximum': 9007199254740991,
              'description': 'The line it is at, counting from 1',
            },
            'summary': {
              'type': 'string',
              'description': 'What is wrong, in one sentence',
            },
            'short_summary': {
              'type': 'string',
              'maxLength': 60,
              'description':
                  'The same in at most 60 characters, for a narrow view: '
                  'the claim alone',
            },
            'failure_scenario': {
              'type': 'string',
              'description':
                  'The inputs or state that make it go wrong, and how',
            },
            'category': {
              'type': 'string',
              'maxLength': 40,
              'description':
                  'What sort of problem, as a short lowercase slug with '
                  'dashes: "logic-error", "perf", "missing-test", "reuse"…',
            },
            'verdict': {
              'type': 'string',
              'enum': ['CONFIRMED', 'PLAUSIBLE'],
              'description':
                  'What checking it found, when it was checked; left out '
                  'otherwise',
            },
            'outcome': {
              'type': 'string',
              'enum': ['fixed', 'skipped', 'no_change_needed'],
              'description':
                  'Only when reporting again after fixes: what was done '
                  'about it',
            },
          },
          'required': ['file', 'summary', 'failure_scenario'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['findings'],
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

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
    final findings = asList(input['findings']);
    return ToolOutput(
      findings.isEmpty
          ? 'Reported: no findings.'
          : 'Reported ${findings.length} finding'
                '${findings.length == 1 ? '' : 's'}.',
      result: {'level': ?input['level'], 'findings': findings},
    );
  }
}
