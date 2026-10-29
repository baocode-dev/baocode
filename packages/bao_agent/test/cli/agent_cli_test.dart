// The engine run as `claude -p` is: its command line read, a session on
// stdin and stdout, one prompt answered.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:bao_agent/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// What is written to it, as text.
class _Sink {
  final StreamController<List<int>> _bytes = StreamController();
  late final IOSink sink = IOSink(_bytes.sink);
  final StringBuffer text = StringBuffer();
  final StreamController<String> lines = StreamController.broadcast();

  _Sink() {
    _bytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          text.writeln(line);
          lines.add(line);
        });
  }
}

void main() {
  late Directory root;
  late String cwd;
  late Map<String, String> environment;

  setUp(() {
    root = Directory.systemTemp.createTempSync('agent_cli_');
    cwd = p.join(root.resolveSymbolicLinksSync(), 'project');
    Directory(cwd).createSync();
    environment = {
      'HOME': root.path,
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'CLAUDE_CONFIG_DIR': p.join(root.path, 'config'),
    };
  });

  tearDown(() => root.deleteSync(recursive: true));

  AgentCommandLine parse(List<String> arguments) =>
      AgentCommandLine.parse(arguments, cwd: cwd, environment: environment);

  group('its command line', () {
    test('as BaoCode starts a session', () {
      final settings = File(p.join(root.path, 'flag.json'))
        ..writeAsStringSync(
          jsonEncode({
            'env': {'ANTHROPIC_API_KEY': 'sk-file'},
            'permissions': {
              'allow': ['Read(//data/**)'],
            },
          }),
        );
      final line = parse([
        '-p',
        '--input-format',
        'stream-json',
        '--output-format',
        'stream-json',
        '--verbose',
        '--include-partial-messages',
        '--replay-user-messages',
        '--permission-prompt-tool',
        'stdio',
        '--thinking-display',
        'summarized',
        '--prompt-suggestions',
        '--permission-mode',
        'acceptEdits',
        '--model',
        'opus',
        '--effort',
        'high',
        '--autocompact',
        '150000',
        '--resume',
        'abc',
        '--add-dir',
        '/data',
        '--add-dir',
        '/more',
        '--settings',
        settings.path,
        '--settings',
        '{"permissions": {"deny": ["Bash(rm:*)"]}}',
        '--no-session-persistence',
        '--mcp-config',
        jsonEncode({
          'mcpServers': {
            'baocode': {'type': 'sdk', 'name': 'baocode'},
            'docs': {'command': 'docs-server'},
          },
        }),
        '--allowedTools',
        'mcp__baocode',
        '--append-system-prompt',
        'Cite code so.',
      ]);
      expect(line.inputFormat, 'stream-json');
      expect(line.outputFormat, 'stream-json');
      final options = line.options;
      expect(options.cwd, cwd);
      // Someone to ask: the tools that ask are offered.
      expect(options.canAsk, isTrue);
      expect(parse(['-p']).options.canAsk, isFalse);
      expect(options.promptSuggestions, isTrue);
      expect(options.permissionMode, 'acceptEdits');
      expect(options.model, 'opus');
      expect(options.effort, 'high');
      expect(options.autocompact, 150000);
      expect(options.resume, 'abc');
      expect(options.directories, ['/data', '/more']);
      expect(options.persist, isFalse);
      expect(options.sdkServers, ['baocode']);
      expect(options.appendSystemPrompt, 'Cite code so.');
      expect(options.environment, environment);
      expect(options.flagSettings, {
        'env': {'ANTHROPIC_API_KEY': 'sk-file'},
        'permissions': {
          'allow': ['Read(//data/**)', 'mcp__baocode'],
          'deny': ['Bash(rm:*)'],
        },
        'mcpServers': {
          'docs': {'command': 'docs-server'},
        },
      });
    });

    test('as it asks one question', () {
      final line = parse([
        '-p',
        '--model',
        'haiku',
        '--max-turns',
        '3',
        '--output-format',
        'json',
        '--no-session-persistence',
        '--strict-mcp-config',
        '--disable-slash-commands',
        '--tools',
        'Read,Grep',
        'Glob',
        '--system-prompt',
        'Be brief.',
      ]);
      expect(line.inputFormat, 'text');
      expect(line.outputFormat, 'json');
      expect(line.options.tools, ['Read', 'Grep', 'Glob']);
      expect(line.options.maxTurns, 3);
      expect(line.options.strictMcpConfig, isTrue);
      expect(line.options.slashCommands, isFalse);
      expect(line.options.systemPrompt, 'Be brief.');
      // None: the next option ends the list.
      expect(parse(['--tools', '', '--model', 'x']).options.tools, isEmpty);
      expect(
        parse(['--dangerously-skip-permissions']).options.permissionMode,
        'bypassPermissions',
      );
      expect(parse(['--session-id', 'id1']).options.sessionId, 'id1');
    });

    test('what it does not take', () {
      expect(() => parse(['--bogus']), throwsFormatException);
      expect(() => parse(['--model']), throwsFormatException);
      final list = File(p.join(root.path, 'list.json'))
        ..writeAsStringSync('[1]');
      expect(() => parse(['--settings', list.path]), throwsFormatException);
    });
  });

  group('run', () {
    late FakeApi api;

    setUp(() async {
      api = await FakeApi.start(
        errands: (request) => jsonEncode(request.body).contains('title')
            ? Reply.text('A title')
            : null,
      );
      environment
        ..['ANTHROPIC_API_KEY'] = 'sk-cli'
        ..['ANTHROPIC_BASE_URL'] = api.baseUrl;
    });

    tearDown(() => api.close());

    test('a session: messages in, messages out, a line each', () async {
      api.model.script.addAll([
        Reply.tool('Write', {
          'file_path': p.join(cwd, 'a.txt'),
          'content': 'hi\n',
        }),
        Reply.text('wrote it'),
      ]);
      final input = StreamController<List<int>>();
      final output = _Sink();
      final errors = _Sink();
      void send(Map<String, Object?> message) =>
          input.add(utf8.encode('${jsonEncode(message)}\n'));
      final messages = output.lines.stream.map(
        (line) => (jsonDecode(line) as Map).cast<String, Object?>(),
      );
      final initialized = messages.firstWhere(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map)['request_id'] == 'init',
      );
      final result = messages.firstWhere((m) => m['type'] == 'result');
      final run = runAgentCommandLine(
        [
          '-p',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--permission-mode',
          'acceptEdits',
        ],
        input: input.stream,
        output: output.sink,
        errors: errors.sink,
        cwd: cwd,
        environment: environment,
      );
      send({
        'type': 'control_request',
        'request_id': 'init',
        'request': {'subtype': 'initialize'},
      });
      await initialized;
      input.add(utf8.encode('not json\n\n'));
      send({
        'type': 'user',
        'message': {'role': 'user', 'content': 'write a.txt'},
      });
      final done = await result.timeout(const Duration(seconds: 20));
      expect(done['result'], 'wrote it');
      expect(File(p.join(cwd, 'a.txt')).readAsStringSync(), 'hi\n');
      expect(api.headers.first['x-api-key'], 'sk-cli');
      // Its input ended: it ends.
      await input.close();
      expect(await run.timeout(const Duration(seconds: 20)), 0);
      expect(errors.text.toString(), contains('Not a message: not json'));
    });

    Future<(int, String, String)> ask(String prompt, List<String> args) async {
      final output = _Sink();
      final errors = _Sink();
      final code = await runAgentCommandLine(
        ['-p', '--no-session-persistence', ...args],
        input: Stream.value(utf8.encode(prompt)),
        output: output.sink,
        errors: errors.sink,
        cwd: cwd,
        environment: environment,
      ).timeout(const Duration(seconds: 20));
      await Future<void>.delayed(Duration.zero);
      return (code, '${output.text}', '${errors.text}');
    }

    test('one prompt: the answer as text, as JSON, as messages', () async {
      api.model.script.add(Reply.text('Four.'));
      var (code, out, _) = await ask('2+2?', []);
      expect((code, out.trim()), (0, 'Four.'));

      api.model.script.add(Reply.text('Five.'));
      (code, out, _) = await ask('2+3?', ['--output-format', 'json']);
      final result = jsonDecode(out) as Map;
      expect((code, result['type'], result['result']), (0, 'result', 'Five.'));

      api.model.script.add(Reply.text('Six.'));
      (code, out, _) = await ask('3+3?', ['--output-format', 'stream-json']);
      final types = [
        for (final line in const LineSplitter().convert(out))
          (jsonDecode(line) as Map)['type'],
      ];
      expect(types, containsAll(['system', 'assistant', 'result']));
      expect(types.last, 'result');
    });

    test('nothing asked, an unknown option: told, not run', () async {
      var (code, _, err) = await ask('  ', []);
      expect((code, err.trim()), (2, 'No prompt given on stdin.'));
      (code, _, err) = await ask('hi', ['--nonsense']);
      expect(code, 2);
      expect(err, contains('Unknown option: --nonsense'));
    });

    test('a model that cannot be reached: an error, exit 1', () async {
      environment.remove('ANTHROPIC_API_KEY');
      final (code, out, _) = await ask('hi', ['--output-format', 'json']);
      expect(code, 1);
      expect(out, contains('ANTHROPIC_API_KEY'));
    });
  });
}
