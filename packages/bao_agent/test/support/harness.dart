import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:path/path.dart' as p;

import 'fake_model.dart';

export 'fake_model.dart';

/// A session under test: a project folder and a config folder of its own,
/// the engine on a [FakeModel], and the messages it sent.
class Harness {
  Harness._(this.root, this.cwd, this.config, this.model);

  /// A session in a fresh project ([files] written in it).
  static Future<Harness> start({
    List<Reply>? script,
    Responder? errands,
    Map<String, String> files = const {},
    Map<String, Object?> settings = const {},
    Map<String, Object?> flagSettings = const {},
    String? permissionMode,
    String? resume,
    Harness? from,
    bool promptSuggestions = false,
    Map<String, String> environment = const {},
    List<String> directories = const [],
    String? model,
    List<String> sdkServers = const [],
    String? effort,
    String? thinkingDisplay,
    bool strictMcpConfig = false,
    bool firstParty = true,
  }) async {
    final root =
        from?.root ??
        Directory.systemTemp
            .createTempSync('bao_agent_')
            .resolveSymbolicLinksSync();
    final cwd = p.join(root, 'project');
    final config = p.join(root, 'config');
    Directory(cwd).createSync(recursive: true);
    Directory(config).createSync(recursive: true);
    for (final MapEntry(key: path, value: content) in files.entries) {
      final file = File(p.join(cwd, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }
    if (settings.isNotEmpty) {
      File(p.join(config, 'settings.json')).writeAsStringSync(_json(settings));
    }
    final fake = FakeModel(script, errands)..firstParty = firstParty;
    final harness = Harness._(root, cwd, config, fake);
    harness.engine = AgentEngine(
      EngineOptions(
        cwd: cwd,
        resume: resume,
        permissionMode: permissionMode,
        flagSettings: flagSettings,
        promptSuggestions: promptSuggestions,
        directories: directories,
        model: model,
        sdkServers: sdkServers,
        effort: effort,
        thinkingDisplay: thinkingDisplay,
        strictMcpConfig: strictMcpConfig,
        environment: {
          'HOME': root,
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'ANTHROPIC_API_KEY': 'test-key',
          'CLAUDE_CONFIG_DIR': config,
          ...environment,
        },
        configDir: config,
      ),
      send: harness._receive,
      clientFactory: (_) => fake,
    );
    return harness;
  }

  static String _json(Map<String, Object?> value) {
    return const JsonEncoderWithIndent().convert(value);
  }

  final String root;
  final String cwd;
  final String config;
  final FakeModel model;
  late final AgentEngine engine;

  /// Everything the engine sent, in order.
  final List<Map<String, Object?>> sent = [];
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();

  /// How `can_use_tool` is answered; allowed when unset.
  Future<Map<String, Object?>> Function(Map<String, Object?> request)?
  onPermission;

  /// How other requests of the engine (`elicitation`, `mcp_message`) are
  /// answered.
  Future<Map<String, Object?>> Function(Map<String, Object?> request)?
  onRequest;

  /// The permission requests the engine made.
  final List<Map<String, Object?>> permissionRequests = [];

  Stream<Map<String, Object?>> get messages => _out.stream;

  void _receive(Map<String, Object?> message) {
    if (_out.isClosed) return;
    sent.add(message);
    _out.add(message);
    if (message['type'] == 'control_request') {
      final request = (message['request'] as Map).cast<String, Object?>();
      final id = message['request_id'];
      unawaited(() async {
        Map<String, Object?> response;
        try {
          if (request['subtype'] == 'can_use_tool') {
            permissionRequests.add(request);
            response =
                await (onPermission?.call(request) ??
                    Future.value({
                      'behavior': 'allow',
                      'updatedInput': request['input'],
                    }));
          } else {
            response =
                await (onRequest?.call(request) ??
                    Future.value(const <String, Object?>{}));
          }
        } on Object catch (error) {
          engine.receive({
            'type': 'control_response',
            'response': {
              'subtype': 'error',
              'request_id': id,
              'error': '$error',
            },
          });
          return;
        }
        engine.receive({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': id,
            'response': response,
          },
        });
      }());
    }
  }

  int _requests = 0;

  /// Sends a control request and waits for its answer (throws on error).
  Future<Map<String, Object?>> request(
    String subtype, [
    Map<String, Object?> fields = const {},
  ]) async {
    final id = 'req_${++_requests}';
    final answer = messages.firstWhere(
      (m) =>
          m['type'] == 'control_response' &&
          (m['response'] as Map)['request_id'] == id,
    );
    engine.receive({
      'type': 'control_request',
      'request_id': id,
      'request': {'subtype': subtype, ...fields},
    });
    final response =
        ((await answer.timeout(const Duration(seconds: 30)))['response'] as Map)
            .cast<String, Object?>();
    if (response['subtype'] == 'error') {
      throw StateError('${response['error']}');
    }
    return (response['response'] as Map? ?? const {}).cast<String, Object?>();
  }

  int _sentMessages = 0;

  /// Sends [text] (and [blocks]) as a user message; returns its uuid.
  String send(
    String text, {
    List<Map<String, Object?>> blocks = const [],
    String priority = 'later',
    String? uuid,
  }) {
    final id = uuid ?? 'user-${++_sentMessages}';
    engine.receive({
      'type': 'user',
      'uuid': id,
      'session_id': '',
      'parent_tool_use_id': null,
      'priority': priority,
      'message': {
        'role': 'user',
        'content': [
          ...blocks,
          if (text.isNotEmpty) {'type': 'text', 'text': text},
        ],
      },
    });
    return id;
  }

  /// Sends [text] and waits for its turn to end: the messages of the turn,
  /// its result last.
  Future<List<Map<String, Object?>>> turn(
    String text, {
    List<Map<String, Object?>> blocks = const [],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final start = sent.length;
    final idle = nextIdle();
    send(text, blocks: blocks);
    await idle.timeout(timeout);
    return sent.sublist(start);
  }

  /// Completes when the engine next says it is idle.
  Future<void> nextIdle() => messages.firstWhere(
    (m) =>
        m['type'] == 'system' &&
        m['subtype'] == 'session_state_changed' &&
        m['state'] == 'idle',
  );

  /// The result of the last turn.
  Map<String, Object?> get lastResult =>
      sent.lastWhere((m) => m['type'] == 'result');

  /// The messages of [type] (and [subtype]).
  List<Map<String, Object?>> of(String type, [String? subtype]) => [
    for (final m in sent)
      if (m['type'] == type && (subtype == null || m['subtype'] == subtype)) m,
  ];

  /// The tool results sent to the host, in the order of their calls
  /// (calls run together end in any order).
  List<Map<String, Object?>> get toolResults {
    final results = [
      for (final m in of('user'))
        for (final block
            in (m['message'] as Map)['content'] is List
                ? (m['message'] as Map)['content'] as List
                : const [])
          if (block is Map && block['type'] == 'tool_result')
            {
              ...block.cast<String, Object?>(),
              'tool_use_result': m['tool_use_result'],
            },
    ];
    final calls = [
      for (final m in of('assistant'))
        for (final block in (m['message'] as Map)['content'] as List)
          if (block is Map && block['type'] == 'tool_use') '${block['id']}',
    ];
    return [
      for (final id in calls) ...results.where((r) => r['tool_use_id'] == id),
      ...results.where((r) => !calls.contains(r['tool_use_id'])),
    ];
  }

  /// The session's file.
  String get sessionFile {
    final projects = Directory(p.join(config, 'projects'));
    return projects
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere(
          (f) => f.path.endsWith('.jsonl') && !f.path.contains('subagents'),
        )
        .path;
  }

  String file(String path) => File(p.join(cwd, path)).readAsStringSync();

  Future<void> dispose() async {
    await engine.close();
    await _out.close();
    try {
      Directory(root).deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the system to clean.
    }
  }
}

class JsonEncoderWithIndent {
  const JsonEncoderWithIndent();

  String convert(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}
