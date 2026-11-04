@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'dart:ui' show Locale;

import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/remote/local_tools.dart';
import 'package:baocode/remote/port_forwards.dart';
import 'package:baocode/remote/remote_host_settings.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// The tools an agent on an SSH host has for the user's computer: offered
/// unless the host is turned off; a command run here asked of the
/// user each time (unless always allowed for the host); files copied both
/// ways; ports forwarded. Over a server in memory, whose "host" is this
/// machine too.
void main() {
  late Directory dir;
  late String project;
  late SshHosts hosts;
  late RemoteHostSettings settings;
  late PortForwards forwards;
  final previous = (
    SshHosts.instance,
    RemoteHostSettings.instance,
    PortForwards.instance,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-local-tools-');
    final made = Directory(p.join(dir.path, 'project'))..createSync();
    project = made.resolveSymbolicLinksSync();
    hosts = SshHosts.instance = SshHosts(
      connect: MemoryConnector(p.join(dir.path, 'data')).call,
    );
    settings = RemoteHostSettings.instance = RemoteHostSettings(
      file: p.join(dir.path, 'remote-hosts.json'),
    );
    forwards = PortForwards.instance = PortForwards(
      hosts: hosts,
      settings: settings,
      adbPort: null,
    );
    LocalTools.start(l10n: () => lookupAppLocalizations(const Locale('zh')));
  });

  tearDown(() async {
    for (final name in [
      LocalTools.run,
      LocalTools.push,
      LocalTools.pull,
      LocalTools.forward,
    ]) {
      ClaudeSdkTools.unregister(name);
    }
    ClaudeSdkTools.instruct(LocalTools.feature, null);
    forwards.dispose();
    await hosts.closeAll();
    SshHosts.instance = previous.$1;
    RemoteHostSettings.instance = previous.$2;
    PortForwards.instance = previous.$3;
    dir.deleteSync(recursive: true);
  });

  String cwd() => 'ssh://dev$project';

  Future<Map<String, Object?>> request(
    String method, {
    Map<String, Object?> params = const {},
    String? at,
    ClaudeSdkAsk? ask,
  }) async {
    final response = await ClaudeSdkTools.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params,
    }, ClaudeSdkCall(cwd: at ?? cwd(), ask: ask));
    return response['result']! as Map<String, Object?>;
  }

  Future<List<String>> listed({String? at}) async => [
    for (final tool in (await request('tools/list', at: at))['tools']! as List)
      (tool as Map)['name'] as String,
  ];

  Future<({String text, bool error})> call(
    String name,
    Map<String, Object?> arguments, {
    ClaudeSdkAsk? ask,
  }) async {
    final result = await request(
      'tools/call',
      params: {'name': name, 'arguments': arguments},
      ask: ask,
    );
    final content = result['content']! as List;
    return (
      text: (content.first as Map)['text'] as String,
      error: result['isError'] == true,
    );
  }

  test('offered to an SSH project unless its host is turned off, and told '
      'of then; turned off, told where to turn it on', () async {
    final local = [
      LocalTools.run,
      LocalTools.push,
      LocalTools.pull,
      LocalTools.forward,
    ];
    settings.setLocalAccess('dev', false);
    expect(await listed(), isNot(containsAll(local)));
    expect((await call(LocalTools.run, {'command': 'echo hi'})).error, isTrue);
    final off = await request('initialize');
    expect(off['instructions'], contains('Settings → SSH Servers'));
    expect(off['instructions'], isNot(contains('local_run')));
    expect(
      File(p.join(dir.path, 'remote-hosts.json')).readAsStringSync(),
      contains('"localAccess": false'),
    );
    settings.setLocalAccess('dev', true);
    // On as it was at first: nothing kept for it.
    expect(
      File(p.join(dir.path, 'remote-hosts.json')).readAsStringSync().trim(),
      '{}',
    );
    expect(await listed(), containsAll(local));
    expect(await listed(at: project), isNot(contains(LocalTools.run)));
    expect(
      await listed(at: 'ssh://wsl+Ubuntu/home'),
      isNot(contains(LocalTools.run)),
    );
    final initialize = await request('initialize');
    expect(initialize['instructions'], contains('local_run'));
    expect(
      (await request('initialize', at: project))['instructions'] ?? '',
      isNot(contains('local_run')),
    );
  });

  test('local_run asks each time, in any mode, saying it runs here; '
      'denied, nothing runs; always, not asked again for the host', () async {
    settings.setLocalAccess('dev', true);
    final marker = p.join(dir.path, 'ran');
    final asked = <ApprovalRequest>[];
    var answer = ApprovalDecision.deny;
    Future<ApprovalDecision?> ask(ApprovalRequest request) async {
      asked.add(request);
      return answer;
    }

    final denied = await call(LocalTools.run, {
      'command': 'touch "$marker"',
    }, ask: ask);
    expect(denied.error, isTrue);
    expect(File(marker).existsSync(), isFalse);
    expect(asked.single.title, '在本机执行');
    expect(asked.single.reason, contains('dev'));
    expect(asked.single.alwaysAllowLabel, '这台主机一直允许');
    expect(
      asked.single.preview,
      isA<CommandPreview>().having(
        (c) => c.command,
        'command',
        'touch "$marker"',
      ),
    );
    expect(
      ClaudeSdkTools.called('mcp__baocode__local_run')!.asksItself,
      isTrue,
    );

    answer = ApprovalDecision.allowOnce;
    final once = await call(LocalTools.run, {
      'command': 'echo "in \$PWD"; touch "$marker"; exit 3',
      'cwd': dir.path,
    }, ask: ask);
    expect(once.error, isFalse);
    expect(once.text, contains('Exit code: 3'));
    expect(once.text, contains('in ${dir.resolveSymbolicLinksSync()}'));
    expect(File(marker).existsSync(), isTrue);
    expect(asked, hasLength(2));
    expect(settings.runsWithoutAsking('dev'), isFalse);

    answer = ApprovalDecision.allowAlways;
    await call(LocalTools.run, {'command': 'true'}, ask: ask);
    expect(settings.runsWithoutAsking('dev'), isTrue);
    final unasked = await call(LocalTools.run, {
      'command': 'echo again',
    }, ask: ask);
    expect(unasked.text, contains('again'));
    expect(asked, hasLength(3));

    // Turned off: what was allowed goes with it.
    settings.setLocalAccess('dev', false);
    settings.setLocalAccess('dev', true);
    expect(settings.runsWithoutAsking('dev'), isFalse);

    // No one to ask (none can be): not run.
    final nobody = await call(LocalTools.run, {'command': 'echo x'});
    expect(nobody.error, isTrue);
  });

  test('a command that runs too long is stopped', () async {
    final text = await LocalTools.runHere(
      'echo start; sleep 30',
      cwd: dir.path,
      timeout: const Duration(seconds: 1),
    );
    expect(text, contains('timed out after 1s'));
    expect(text, contains('start'));
  });

  test('local_push and local_pull copy files and folders both ways', () async {
    settings.setLocalAccess('dev', true);
    final here = Directory(p.join(dir.path, 'here'))..createSync();
    File(p.join(here.path, 'a.txt')).writeAsStringSync('A');
    Directory(p.join(here.path, 'sub')).createSync();
    File(p.join(here.path, 'sub', 'b.txt')).writeAsStringSync('B');

    final pushed = await call(LocalTools.push, {'local_path': here.path});
    expect(pushed.error, isFalse, reason: pushed.text);
    expect(
      File(p.join(project, 'here', 'sub', 'b.txt')).readAsStringSync(),
      'B',
    );

    final file = await call(LocalTools.push, {
      'local_path': p.join(here.path, 'a.txt'),
      'remote_path': 'renamed.txt',
    });
    expect(file.error, isFalse, reason: file.text);
    expect(File(p.join(project, 'renamed.txt')).readAsStringSync(), 'A');

    final into = Directory(p.join(dir.path, 'pulled'))..createSync();
    final pulled = await call(LocalTools.pull, {
      'remote_path': 'here',
      'local_path': into.path,
    });
    expect(pulled.error, isFalse, reason: pulled.text);
    expect(
      File(p.join(into.path, 'here', 'sub', 'b.txt')).readAsStringSync(),
      'B',
    );
    // Again: beside it, not over it.
    await call(LocalTools.pull, {
      'remote_path': 'renamed.txt',
      'local_path': into.path,
    });
    await call(LocalTools.pull, {
      'remote_path': 'renamed.txt',
      'local_path': into.path,
    });
    expect(File(p.join(into.path, 'renamed (2).txt')).existsSync(), isTrue);

    final missing = await call(LocalTools.pull, {'remote_path': 'nope'});
    expect(missing.error, isTrue);
  });

  test('port_forward opens, lists and closes', () async {
    settings.setLocalAccess('dev', true);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final opened = await call(LocalTools.forward, {
      'action': 'open',
      'direction': 'remote_to_local',
      'port': server.port,
    });
    expect(opened.error, isFalse, reason: opened.text);
    expect(opened.text, contains('http://localhost:'));
    final list = await call(LocalTools.forward, {'action': 'list'});
    expect(list.text, contains('port ${server.port} of the host'));
    final closed = await call(LocalTools.forward, {
      'action': 'close',
      'port': server.port,
    });
    expect(closed.error, isFalse);
    expect(forwards.of('dev'), isEmpty);
  });
}
