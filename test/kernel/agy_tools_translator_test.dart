import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/swarm/swarm_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _toolUse(
  String id,
  String name,
  Map<String, Object?> input, {
  String? parentToolUseId,
}) => {
  'type': 'assistant',
  'parent_tool_use_id': ?parentToolUseId,
  'message': {
    'id': 'msg-$id',
    'content': [
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
    ],
  },
};

Map<String, Object?> _toolResult(
  String id,
  String content, {
  bool isError = false,
  String? parentToolUseId,
}) => {
  'type': 'user',
  'parent_tool_use_id': ?parentToolUseId,
  'message': {
    'content': [
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': content,
        'is_error': isError,
      },
    ],
  },
};

void main() {
  late Transcript transcript;
  late ClaudeTranslator translator;

  setUp(() {
    transcript = Transcript();
    var seq = 0;
    translator = ClaudeTranslator(
      emit: transcript.apply,
      nextSeq: () => ++seq,
    );
  });

  List<ChatItem> items() => [
    for (var i = 0; i < transcript.length; i++) transcript.itemAt(i),
  ];

  group('ManageTask', () {
    test('renders list action running and succeeded', () {
      translator.translate(
        _toolUse('mt-1', 'ManageTask', {'action': 'list'}),
      );
      var item = items().single as ToolCallItem;
      expect(item.kind, ToolKind.command);
      expect(item.label, 'Listing background tasks');
      expect(item.target, '');
      expect(item.status, ToolStatus.running);

      translator.translate(_toolResult('mt-1', 'task-1: running'));
      item = items().single as ToolCallItem;
      expect(item.label, 'Listed background tasks');
      expect(item.status, ToolStatus.succeeded);
      expect(item.output, 'task-1: running');
    });

    test('renders send_input action with task_id and input excerpt', () {
      translator.translate(
        _toolUse('mt-2', 'ManageTask', {
          'action': 'send_input',
          'task_id': 'bg-42',
          'input': 'yes\ncontinue',
        }),
      );
      var item = items().single as ToolCallItem;
      expect(item.kind, ToolKind.command);
      expect(item.label, 'Sending input to task');
      expect(item.target, 'bg-42 · yes continue');
      expect(item.status, ToolStatus.running);

      translator.translate(_toolResult('mt-2', 'Delivered'));
      item = items().single as ToolCallItem;
      expect(item.label, 'Sent input to task');
      expect(item.target, 'bg-42 · yes continue');
      expect(item.status, ToolStatus.succeeded);
      expect(item.output, 'Delivered');
    });
  });

  group('Schedule', () {
    test('renders cron with optional daemon badge and prompt output', () {
      translator.translate(
        _toolUse('sc-1', 'Schedule', {
          'cron': '*/5 * * * *',
          'is_daemon': true,
          'prompt': 'Check build health',
        }),
      );
      var item = items().single as ToolCallItem;
      expect(item.kind, ToolKind.other);
      expect(item.label, 'Scheduling cron');
      expect(item.target, '*/5 * * * * · daemon');
      expect(item.status, ToolStatus.running);
      expect(item.output, 'Check build health');

      translator.translate(_toolResult('sc-1', 'Scheduled #7'));
      item = items().single as ToolCallItem;
      expect(item.label, 'Scheduled cron');
      expect(item.target, '*/5 * * * * · daemon');
      expect(item.status, ToolStatus.succeeded);
      expect(item.output, 'Check build health');
    });

    test('renders timer durations and surfaces error output on failure', () {
      translator.translate(
        _toolUse('sc-2', 'Schedule', {
          'duration_seconds': 30,
          'prompt': 'Wake up soon',
        }),
      );
      var item = items().last as ToolCallItem;
      expect(item.kind, ToolKind.other);
      expect(item.label, 'Setting timer');
      expect(item.target, '30s');
      expect(item.output, 'Wake up soon');

      translator.translate(
        _toolResult('sc-2', 'Timer limit reached', isError: true),
      );
      item = items().last as ToolCallItem;
      expect(item.label, 'Set timer');
      expect(item.status, ToolStatus.failed);
      expect(item.output, 'Timer limit reached');

      translator.translate(
        _toolUse('sc-3', 'Schedule', {
          'duration_seconds': 120,
          'prompt': 'Check deployment',
        }),
      );
      translator.translate(_toolResult('sc-3', 'ok'));
      final twoMin = items().last as ToolCallItem;
      expect(twoMin.label, 'Set timer');
      expect(twoMin.target, '2m');
      expect(twoMin.output, 'Check deployment');
    });
  });

  group('ManageSubagents', () {
    test('renders list, kill (single and multiple), and kill_all actions', () {
      translator.translate(
        _toolUse('ms-1', 'ManageSubagents', {'action': 'list'}),
      );
      var item = items().last as ToolCallItem;
      expect(item.kind, ToolKind.agent);
      expect(item.label, 'Listing subagents');
      translator.translate(_toolResult('ms-1', '2 active'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Listed subagents');
      expect(item.output, '2 active');

      translator.translate(
        _toolUse('ms-2', 'ManageSubagents', {
          'action': 'kill',
          'conversation_ids': ['conv-abc'],
        }),
      );
      item = items().last as ToolCallItem;
      expect(item.kind, ToolKind.agent);
      expect(item.label, 'Stopping subagent');
      expect(item.target, 'conv-abc');
      translator.translate(_toolResult('ms-2', 'Stopped'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Stopped subagent');
      expect(item.target, 'conv-abc');

      translator.translate(
        _toolUse('ms-3', 'ManageSubagents', {
          'action': 'kill',
          'conversation_ids': ['conv-1', 'conv-2', 'conv-3'],
        }),
      );
      translator.translate(_toolResult('ms-3', 'Stopped 3'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Stopped subagent');
      expect(item.target, '3 subagents');

      translator.translate(
        _toolUse('ms-4', 'ManageSubagents', {'action': 'kill_all'}),
      );
      item = items().last as ToolCallItem;
      expect(item.label, 'Stopping all subagents');
      translator.translate(_toolResult('ms-4', 'All stopped'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Stopped all subagents');
      expect(item.target, '');
    });
  });

  group('DefineSubagent', () {
    test('renders name, description on success, and error output on failure', () {
      translator.translate(
        _toolUse('ds-1', 'DefineSubagent', {
          'name': 'security-reviewer',
          'description': 'Audits auth boundaries and token handling',
        }),
      );
      var item = items().single as ToolCallItem;
      expect(item.kind, ToolKind.agent);
      expect(item.label, 'Defining subagent');
      expect(item.target, 'security-reviewer');
      expect(item.output, 'Audits auth boundaries and token handling');

      translator.translate(_toolResult('ds-1', 'Registered'));
      item = items().single as ToolCallItem;
      expect(item.label, 'Defined subagent');
      expect(item.target, 'security-reviewer');
      expect(item.status, ToolStatus.succeeded);
      expect(item.output, 'Audits auth boundaries and token handling');

      translator.translate(
        _toolUse('ds-2', 'DefineSubagent', {
          'name': 'bad-agent',
          'description': 'Invalid schema',
        }),
      );
      translator.translate(
        _toolResult('ds-2', 'Duplicate subagent name', isError: true),
      );
      final failed = items().last as ToolCallItem;
      expect(failed.label, 'Defined subagent');
      expect(failed.status, ToolStatus.failed);
      expect(failed.output, 'Duplicate subagent name');
    });
  });

  group('McpResource', () {
    test('renders read (uri and server fallback) and list actions', () {
      translator.translate(
        _toolUse('mcp-1', 'McpResource', {
          'action': 'read',
          'server': 'docs',
          'uri': 'docs://api/v2/auth',
        }),
      );
      var item = items().last as ToolCallItem;
      expect(item.kind, ToolKind.read);
      expect(item.label, 'Reading MCP resource');
      expect(item.target, 'docs://api/v2/auth');
      translator.translate(_toolResult('mcp-1', '# Auth API'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Read MCP resource');
      expect(item.output, '# Auth API');

      translator.translate(
        _toolUse('mcp-2', 'McpResource', {
          'action': 'read',
          'server': 'postgres',
        }),
      );
      translator.translate(_toolResult('mcp-2', 'schema'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Read MCP resource');
      expect(item.target, 'postgres');

      translator.translate(
        _toolUse('mcp-3', 'McpResource', {
          'action': 'list',
          'server': 'linear',
        }),
      );
      item = items().last as ToolCallItem;
      expect(item.kind, ToolKind.read);
      expect(item.label, 'Listing MCP resources');
      expect(item.target, 'linear');
      translator.translate(_toolResult('mcp-3', 'linear://issues'));
      item = items().last as ToolCallItem;
      expect(item.label, 'Listed MCP resources');
      expect(item.target, 'linear');
      expect(item.output, 'linear://issues');
    });
  });

  group('Workflow card', () {
    test('renders Workflow tool use as native workflow AgentItem card', () {
      translator.translate(
        _toolUse('wf-1', 'Workflow', {
          'name': 'Parallel module audit',
          'script': 'parallel([agent("a"), agent("b")])',
          'cwd': '/tmp/repo',
        }),
      );
      var card = items().single as AgentItem;
      expect(card.id, 'wf-1');
      expect(card.agentType, ClaudeTranslator.workflowAgentType);
      expect(card.description, 'Parallel module audit');
      expect(card.prompt, 'parallel([agent("a"), agent("b")])');
      expect(card.background, isTrue);
      expect(card.status, CommandStatus.running);

      translator.translate(
        _toolResult('wf-1', 'SyntaxError in workflow script', isError: true),
      );
      card = items().single as AgentItem;
      expect(card.status, CommandStatus.failed);
      expect(card.result, 'SyntaxError in workflow script');
    });
  });

  group('applySubagentTranscript', () {
    test('populates thinking, read_file, and run_command steps and metrics', () {
      translator.translate(
        _toolUse('ag-1', 'Agent', {
          'description': 'Inspect kernel translator',
          'subagent_type': 'Explore',
          'prompt': 'Check tool mappings',
        }),
      );

      // Existing non-substep child should be preserved across transcript refreshes.
      translator.translate(
        _toolUse(
          'child-native',
          'Grep',
          {'pattern': 'Swarm'},
          parentToolUseId: 'ag-1',
        ),
      );

      translator.applySubagentTranscript('ag-1', const [
        SwarmWorkerStep(
          index: 1,
          kind: 'thought',
          title: 'Thinking',
          detail: 'Let me inspect the translator first.',
          inputTokens: 500,
          outputTokens: 120,
        ),
        SwarmWorkerStep(
          index: 2,
          kind: 'tool',
          toolName: 'read_file',
          title: 'Read claude_code_translator.dart',
          target: 'claude_code_translator.dart',
          path: '/repo/lib/kernel/claude_code/claude_code_translator.dart',
          range: 'L1-200',
          detail: '200 lines read',
          inputTokens: 800,
          outputTokens: 90,
        ),
        SwarmWorkerStep(
          index: 3,
          kind: 'tool',
          toolName: 'run_command',
          title: 'Run analyzer',
          target: 'dart analyze',
          detail: 'No issues found!',
          inputTokens: 400,
          outputTokens: 50,
        ),
      ]);

      final card = items().single as AgentItem;
      expect(card.toolUses, 2);
      expect(card.tokens, 500 + 120 + 800 + 90 + 400 + 50);
      expect(card.children, hasLength(4));

      // Preserved native child + 3 transcript steps.
      final grep = card.children[0] as ToolCallItem;
      expect(grep.kind, ToolKind.grep);
      expect(grep.target, 'Swarm');

      final thought = card.children[1] as ThinkingItem;
      expect(thought.text, 'Let me inspect the translator first.');
      expect(thought.seconds, 0);

      final read = card.children[2] as ToolCallItem;
      expect(read.kind, ToolKind.read);
      expect(read.target, 'claude_code_translator.dart');
      expect(
        read.path,
        '/repo/lib/kernel/claude_code/claude_code_translator.dart',
      );
      expect(read.detail, 'L1-200');
      expect(read.output, '200 lines read');

      final terminal = card.children[3] as TerminalItem;
      expect(terminal.command, 'dart analyze');
      expect(terminal.description, 'Run analyzer');
      expect(terminal.output, 'No issues found!');
      expect(terminal.status, CommandStatus.succeeded);

      // Empty steps or unknown toolUseId are ignored without wiping children.
      translator.applySubagentTranscript('ag-1', const []);
      translator.applySubagentTranscript('unknown-id', const [
        SwarmWorkerStep(index: 1, kind: 'reply', title: 'hi'),
      ]);
      final unchanged = items().single as AgentItem;
      expect(unchanged.children, hasLength(4));
      expect(unchanged.toolUses, 2);
      expect(unchanged.tokens, 1960);

      // Refreshing replaces prior substep:* entries cleanly while keeping native children.
      translator.applySubagentTranscript('ag-1', const [
        SwarmWorkerStep(
          index: 10,
          kind: 'reply',
          title: 'Summary',
          detail: 'All checks look clean.',
        ),
      ]);
      final refreshed = items().single as AgentItem;
      expect(refreshed.children, hasLength(2));
      expect(refreshed.children[0], isA<ToolCallItem>());
      expect(
        (refreshed.children[1] as AssistantTextItem).raw,
        'All checks look clean.',
      );
      // toolUses/tokens remain unchanged when new steps report 0 tool uses / 0 tokens.
      expect(refreshed.toolUses, 2);
      expect(refreshed.tokens, 1960);
    });
  });
}
