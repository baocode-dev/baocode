import 'dart:async';

import 'package:bao_remote/claude.dart' show ClaudeHistoryPage;
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/models/model_provider.dart' show ModelProvider, modelRef;
import 'package:baocode/models/model_providers.dart' show ModelProviders;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements ClaudeCodeTransport {
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  final List<Map<String, Object?>> written = [];
  bool closed = false;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void push(Map<String, Object?> message) => _out.add(message);

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (message['type'] != 'control_request') return;
    final subtype = (message['request'] as Map)['subtype'] as String;
    final payload = switch (subtype) {
      'initialize' => <String, Object?>{
        'commands': const <Object?>[],
        'models': const [
          {
            'value': 'sonnet',
            'displayName': 'Sonnet',
            'description': 'Claude Sonnet',
          },
        ],
        'current_permission_mode': 'default',
      },
      'rewind_conversation' => const <String, Object?>{'rewound': true},
      _ => const <String, Object?>{},
    };
    push({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': message['request_id'],
        'response': payload,
      },
    });
  }

  void finishTurn({required String messageId, required String reply}) {
    push({
      'type': 'assistant',
      'uuid': 'a-$messageId',
      'message': {
        'id': messageId,
        'role': 'assistant',
        'model': messageId.startsWith('msg_agy_')
            ? 'gemini-4-neon'
            : 'claude-sonnet-4-6',
        'content': [
          {'type': 'text', 'text': reply},
        ],
      },
    });
    push({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'duration_ms': 100,
    });
  }

  @override
  void close() => closed = true;

  @override
  Future<void> get exited async {}
}

Map<String, Object?> _userEntry(String uuid, String text, {String? timestamp}) =>
    {
      'type': 'user',
      'uuid': uuid,
      'timestamp': timestamp ?? '2026-11-28T10:00:00Z',
      'message': {'role': 'user', 'content': text},
    };

Map<String, Object?> _assistantEntry(
  String uuid,
  String messageId,
  String text, {
  String model = 'claude-sonnet-4-6',
  String? kernelId,
  String? timestamp,
}) => {
  'type': 'assistant',
  'uuid': uuid,
  'kernelId': ?kernelId,
  'timestamp': timestamp ?? '2026-11-28T10:00:02Z',
  'message': {
    'id': messageId,
    'role': 'assistant',
    'model': model,
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

List<String> _summary(Transcript transcript) => [
  for (var i = 0; i < transcript.length; i++)
    switch (transcript.itemAt(i)) {
      UserMessageItem(:final text) => 'user:$text',
      AssistantTextItem(:final text) => 'assistant:$text',
      KernelSwitchItem(
        :final fromKernel,
        :final toKernel,
        :final fromName,
        :final toName,
      ) =>
        'switch:$fromKernel${fromName == null ? '' : '($fromName)'}'
            '->$toKernel${toName == null ? '' : '($toName)'}',
      NoticeItem(:final kind, :final text) => 'notice:${kind.name}:$text',
      _ => '',
    },
].where((s) => s.isNotEmpty).toList();

void main() {
  final descriptor = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: 'Test kernel',
    create: (_) => throw UnimplementedError(),
  );

  ModelProviders providersWithAgy() => ModelProviders.memory(
    providers: [
      ModelProvider.fromJson({
        'id': 'ag',
        'name': 'Antigravity',
        'protocol': 'antigravity-cli',
        'models': [
          {'id': 'gemini-4-neon'},
        ],
      })!,
    ],
  );

  final agyModel = modelRef('ag', 'gemini-4-neon');

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('emits forward and reverse kernel switches on live turns only after '
      'prior conversation', () async {
    final transports = <_FakeTransport>[];
    final launches = <ClaudeLaunch>[];
    final providers = providersWithAgy();
    final transcript = Transcript();
    final kernel = ClaudeCodeKernel(
      descriptor,
      const KernelContext(cwd: '/tmp/project'),
      providers: providers,
      start: (launch) async {
        launches.add(launch);
        final transport = _FakeTransport();
        transports.add(transport);
        return transport;
      },
    );
    addTearDown(kernel.dispose);
    kernel.events.listen(transcript.apply);

    // First turn on Claude Code: no switch block.
    kernel.send(const KernelTurn(id: 'u1', text: 'hello claude'));
    await settle();
    expect(launches.single.agy, isFalse);
    transports.last.finishTurn(messageId: 'msg_01', reply: 'hi from claude');
    await settle();
    expect(_summary(transcript), [
      'user:hello claude',
      'assistant:hi from claude',
    ]);

    // Second turn still on Claude Code: no switch block.
    kernel.send(const KernelTurn(id: 'u2', text: 'still claude'));
    await settle();
    transports.last.finishTurn(messageId: 'msg_02', reply: 'still here');
    await settle();
    expect(
      _summary(transcript).where((s) => s.startsWith('switch:')),
      isEmpty,
    );

    // Switch model to Antigravity ACP: no block until next message is sent.
    kernel.model.select(agyModel);
    await settle();
    expect(
      _summary(transcript).where((s) => s.startsWith('switch:')),
      isEmpty,
    );

    // Send on Antigravity ACP: forward switch appears right before u3.
    kernel.send(const KernelTurn(id: 'u3', text: 'over to agy'));
    await settle();
    expect(launches.last.agy, isTrue);
    transports.last.finishTurn(
      messageId: 'msg_agy_12345678_1_1',
      reply: 'hi from agy',
    );
    await settle();
    expect(_summary(transcript), [
      'user:hello claude',
      'assistant:hi from claude',
      'user:still claude',
      'assistant:still here',
      'switch:claude-code->antigravity-acp',
      'user:over to agy',
      'assistant:hi from agy',
    ]);

    // Switch back to Claude Code and send: reverse switch appears before u4.
    kernel.model.select('sonnet');
    kernel.send(const KernelTurn(id: 'u4', text: 'back to claude'));
    await settle();
    expect(launches.last.agy, isFalse);
    transports.last.finishTurn(messageId: 'msg_03', reply: 'welcome back');
    await settle();
    expect(_summary(transcript), [
      'user:hello claude',
      'assistant:hi from claude',
      'user:still claude',
      'assistant:still here',
      'switch:claude-code->antigravity-acp',
      'user:over to agy',
      'assistant:hi from agy',
      'switch:antigravity-acp->claude-code',
      'user:back to claude',
      'assistant:welcome back',
    ]);
  });

  test('new conversation starting directly on Antigravity shows no switch', () async {
    final providers = providersWithAgy();
    final transcript = Transcript();
    final kernel = ClaudeCodeKernel(
      descriptor,
      KernelContext(
        cwd: '/tmp/project',
        settings: {KernelChoiceKind.model.name: agyModel},
      ),
      providers: providers,
      start: (_) async => _FakeTransport(),
    );
    addTearDown(kernel.dispose);
    kernel.events.listen(transcript.apply);

    kernel.send(const KernelTurn(id: 'u1', text: 'start on agy'));
    await settle();
    expect(_summary(transcript), ['user:start on agy']);
  });

  test('replays bidirectional switches from session history and continues '
      'accurately on live turns', () async {
    final providers = providersWithAgy();
    final transcript = Transcript();
    final transports = <_FakeTransport>[];
    final session = SessionRecord(
      id: 'sess-1',
      title: 'Handoff',
      updatedAt: DateTime(2026, 11, 28),
      cwd: '/tmp/project',
      path: '/tmp/sess-1.jsonl',
    );
    final kernel = ClaudeCodeKernel(
      descriptor,
      KernelContext(cwd: '/tmp/project', resume: session),
      providers: providers,
      readHistory: (_) async => [
        _userEntry('u1', 'first'),
        _assistantEntry('a1', 'msg_01', 'claude reply'),
        _userEntry('u2', 'second'),
        _assistantEntry(
          'a2',
          'msg_agy_12345678_1_1',
          'agy reply 1',
          model: 'gemini-4-neon',
        ),
        _userEntry('u3', 'third'),
        _assistantEntry(
          'a3',
          'msg_agy_12345678_2_1',
          'agy reply 2',
          model: 'gemini-4-neon',
        ),
      ],
      start: (_) async {
        final t = _FakeTransport();
        transports.add(t);
        return t;
      },
    );
    addTearDown(kernel.dispose);
    kernel.events.listen(transcript.apply);
    await settle();

    expect(_summary(transcript), [
      'user:first',
      'assistant:claude reply',
      'switch:claude-code->antigravity-acp',
      'user:second',
      'assistant:agy reply 1',
      'user:third',
      'assistant:agy reply 2',
    ]);

    // Session ended on Antigravity; sending on Claude Code emits reverse switch.
    kernel.send(const KernelTurn(id: 'u4', text: 'fourth on claude'));
    await settle();
    transports.last.finishTurn(messageId: 'msg_04', reply: 'claude back');
    await settle();
    expect(_summary(transcript), [
      'user:first',
      'assistant:claude reply',
      'switch:claude-code->antigravity-acp',
      'user:second',
      'assistant:agy reply 1',
      'user:third',
      'assistant:agy reply 2',
      'switch:antigravity-acp->claude-code',
      'user:fourth on claude',
      'assistant:claude back',
    ]);
  });

  test('loadEarlier inserts a kernel switch across page boundaries', () async {
    final providers = providersWithAgy();
    final transcript = Transcript();
    final session = SessionRecord(
      id: 'sess-paged',
      title: 'Paged',
      updatedAt: DateTime(2026, 11, 28),
      cwd: '/tmp/project',
      path: '/tmp/sess-paged.jsonl',
    );
    final kernel = ClaudeCodeKernel(
      descriptor,
      KernelContext(cwd: '/tmp/project', resume: session),
      providers: providers,
      readHistoryPage: (_, {required turns, before}) async {
        if (before == null) {
          return ClaudeHistoryPage([
            _userEntry('u2', 'on agy'),
            _assistantEntry(
              'a2',
              'msg_agy_12345678_1_1',
              'agy reply',
              model: 'gemini-4-neon',
            ),
          ], earlier: 'u2');
        }
        return ClaudeHistoryPage([
          _userEntry('u1', 'on claude'),
          _assistantEntry('a1', 'msg_01', 'claude reply'),
        ]);
      },
      start: (_) async => _FakeTransport(),
    );
    addTearDown(kernel.dispose);
    kernel.events.listen(transcript.apply);
    await settle();

    // Before loading earlier page, no switch is shown above u2.
    expect(_summary(transcript), ['user:on agy', 'assistant:agy reply']);

    await kernel.loadEarlier();
    await settle();

    // After loading earlier page (Claude), the boundary switch appears before u2.
    expect(_summary(transcript), [
      'user:on claude',
      'assistant:claude reply',
      'switch:claude-code->antigravity-acp',
      'user:on agy',
      'assistant:agy reply',
    ]);
  });

  test('rewinding a switched turn removes its switch and restores prior kernel',
      () async {
    final providers = providersWithAgy();
    final transcript = Transcript();
    final transports = <_FakeTransport>[];
    final kernel = ClaudeCodeKernel(
      descriptor,
      const KernelContext(cwd: '/tmp/project'),
      providers: providers,
      start: (_) async {
        final t = _FakeTransport();
        transports.add(t);
        return t;
      },
    );
    addTearDown(kernel.dispose);
    kernel.events.listen(transcript.apply);

    kernel.send(const KernelTurn(id: 'u1', text: 'first'));
    await settle();
    transports.last.finishTurn(messageId: 'msg_01', reply: 'reply 1');
    await settle();

    kernel.model.select(agyModel);
    kernel.send(const KernelTurn(id: 'u2', text: 'second'));
    await settle();
    transports.last.finishTurn(
      messageId: 'msg_agy_12345678_1_1',
      reply: 'reply 2',
    );
    await settle();

    expect(_summary(transcript), [
      'user:first',
      'assistant:reply 1',
      'switch:claude-code->antigravity-acp',
      'user:second',
      'assistant:reply 2',
    ]);

    final ok = await kernel.rewind(itemId: 'u2', index: 3, turns: 1);
    expect(ok, isTrue);
    await settle();
    expect(_summary(transcript), ['user:first', 'assistant:reply 1']);

    // Resending on Claude Code after rewind emits no redundant switch.
    kernel.model.select('sonnet');
    kernel.send(const KernelTurn(id: 'u2b', text: 'edited on claude'));
    await settle();
    transports.last.finishTurn(messageId: 'msg_02', reply: 'claude again');
    await settle();
    expect(_summary(transcript), [
      'user:first',
      'assistant:reply 1',
      'user:edited on claude',
      'assistant:claude again',
    ]);
  });

  test('supports explicit kernelId and system kernel_switch entries for future '
      'kernels', () {
    final transcript = Transcript();
    var seq = 0;
    final translator = ClaudeTranslator(
      emit: transcript.apply,
      nextSeq: () => ++seq,
    )..replaying = true;

    final entries = <Map<String, Object?>>[
      _userEntry('u1', 'from claude'),
      _assistantEntry('a1', 'msg_01', 'claude answer'),
      _userEntry('u2', 'to codex'),
      _assistantEntry('a2', 'msg_codex_1', 'codex answer', kernelId: 'codex'),
      {
        'type': 'system',
        'subtype': 'kernel_switch',
        'uuid': 'sw-explicit',
        'from': 'codex',
        'to': 'future-acp',
        'from_name': 'Codex',
        'to_name': 'Future ACP',
        'prompt_uuid': 'u3',
      },
      _userEntry('u3', 'to future'),
      _assistantEntry(
        'a3',
        'msg_future_1',
        'future answer',
        kernelId: 'future-acp',
      ),
    ];

    translator.prepareReplayKernels(entries);
    for (final line in entries) {
      translator.translate(line);
    }
    translator.endReplay();

    expect(_summary(transcript), [
      'user:from claude',
      'assistant:claude answer',
      'switch:claude-code->codex',
      'user:to codex',
      'assistant:codex answer',
      'switch:codex(Codex)->future-acp(Future ACP)',
      'user:to future',
      'assistant:future answer',
    ]);
  });
}
