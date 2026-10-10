// ignore_for_file: avoid_print
// Manual probe: starts a reh, connects, starts an extension host with the
// hello fixture and logs every request it makes. Not a test.
//
// dart run tool/probe.dart <reh-dir> <ids.json> <fixture-ext-dir>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';

Future<void> main(List<String> argv) async {
  final reh = argv[0];
  final ids = (jsonDecode(File(argv[1]).readAsStringSync()) as Map).map(
    (k, v) => MapEntry(int.parse(k as String), v as String),
  );
  final byName = {for (final e in ids.entries) e.value: e.key};
  final fixture = argv[2];
  final tmp = Directory.systemTemp.createTempSync('exthost-probe');
  File('${tmp.path}/token').writeAsStringSync('tok123');
  final product =
      jsonDecode(File('$reh/product.json').readAsStringSync()) as Map;
  final server = await Process.start('$reh/node', [
    '$reh/out/server-main.js',
    '--host',
    '127.0.0.1',
    '--port',
    '0',
    '--connection-token-file',
    '${tmp.path}/token',
    '--server-data-dir',
    '${tmp.path}/sd',
    '--extensions-dir',
    '${tmp.path}/ext',
    '--accept-server-license-terms',
  ]);
  final port = Completer<int>();
  server.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) {
        if (!l.startsWith('[')) stdout.writeln('[server] $l');
        final m = RegExp(
          r'Extension host agent listening on (\d+)',
        ).firstMatch(l);
        if (m != null && !port.isCompleted) port.complete(int.parse(m[1]!));
      });
  server.stderr
      .transform(utf8.decoder)
      .listen((l) => stderr.write('[server!] $l'));
  final address = ServerAddress(
    host: '127.0.0.1',
    port: await port.future,
    connectionToken: 'tok123',
    commit: product['commit'] as String,
  );

  final mgmt = await connectToServer(address, ConnectionType.management);
  print('management up: ${mgmt.firstMessage}');
  final ipc = IpcClient(ProtocolMessagePassing(mgmt.protocol), {
    'remoteAuthority': 'baocode',
    'clientId': 'probe',
  });
  final env =
      await ipc.getChannel('remoteextensionsenvironment').call(
            'getEnvironmentData',
            {'remoteAuthority': 'baocode'},
          )
          as Map;
  print('env keys: ${env.keys}; pid ${env['pid']} appRoot ${env['appRoot']}');
  final scanned =
      await ipc.getChannel('remoteExtensionsScanner').call('scanExtensions', [
            'en',
            null,
            [],
            [
              VsUri.file(
                fixture,
              ).replace(scheme: 'vscode-remote', authority: 'baocode').toJson(),
            ],
            null,
          ])
          as List;
  print(
    'scanned ${scanned.length}: ${scanned.map((e) => (e as Map)['identifier']).toList()}',
  );

  Object? local(Object? v) {
    if (v is Map) {
      if (v[r'$mid'] == 1 && v['scheme'] == 'vscode-remote') {
        return {...v.cast<String, Object?>(), 'scheme': 'file', 'authority': ''}
          ..remove('external')
          ..remove('fsPath');
      }
      return v.map((k, e) => MapEntry(k, local(e)));
    }
    if (v is List) return v.map(local).toList();
    return v;
  }

  final extensions = local(scanned) as List;
  final envLocal = local(env) as Map;

  final eh = await connectToServer(
    address,
    ConnectionType.extensionHost,
    args: {'language': 'en', 'env': <String, String>{}},
  );
  print('ext host up: ${eh.firstMessage}');
  final ready = Completer<void>();
  final initialized = Completer<void>();
  eh.protocol.onMessage.listener = (msg) {
    if (msg.length == 1 && msg[0] == 2) {
      ready.complete();
    } else if (msg.length == 1 && msg[0] == 1) {
      // Synchronously: what follows is RPC, buffered until it listens.
      eh.protocol.onMessage.listener = null;
      initialized.complete();
    } else {
      print('handshake: unexpected ${msg.length} bytes');
    }
  };
  await ready.future.timeout(const Duration(seconds: 30));
  print('ready');
  final allIds = [for (final e in extensions) (e as Map)['identifier']];
  final init = {
    'commit': product['commit'],
    'version': product['version'],
    'quality': product['quality'],
    'parentPid': 0,
    'environment': {
      'isExtensionDevelopmentDebug': false,
      'appRoot': envLocal['appRoot'],
      'appName': 'BaoCode',
      'appHost': 'desktop',
      'appUriScheme': 'baocode',
      'isExtensionTelemetryLoggingOnly': false,
      'appLanguage': 'en',
      'globalStorageHome': envLocal['globalStorageHome'],
      'workspaceStorageHome': envLocal['workspaceStorageHome'],
    },
    'workspace': {'id': 'probe', 'name': 'probe', 'configuration': null},
    'remote': {'isRemote': false, 'authority': null, 'connectionData': null},
    'consoleForward': {'includeStack': false, 'logNative': false},
    'extensions': {
      'versionId': 1,
      'allExtensions': extensions,
      'activationEvents': <String, Object?>{},
      'myExtensions': allIds,
    },
    'telemetryInfo': {
      'sessionId': 's',
      'machineId': 'm',
      'sqmId': '',
      'devDeviceId': 'm',
      'firstSessionDate': DateTime.now().toIso8601String(),
    },
    'logLevel': 2,
    'loggers': [],
    'logsLocation': envLocal['extensionHostLogsPath'],
    'autoStart': true,
    'uiKind': 1,
  };
  eh.protocol.send(utf8.encode(jsonEncode(init)));
  await initialized.future.timeout(const Duration(seconds: 30));
  print('initialized');
  final counts = <String, int>{};
  final rpc = RpcProtocol(
    ProtocolMessagePassing(eh.protocol),
    actorNames: ids,
    logger: (incoming, req, what, data) {
      if (incoming && what.startsWith('receiveRequest')) {
        counts[what] = (counts[what] ?? 0) + 1;
        final s = jsonEncode(data, toEncodable: (o) => '$o');
        print('<- $what ${s.length > 300 ? s.substring(0, 300) : s}');
      }
    },
  );
  for (final id in ids.keys) {
    if (ids[id]!.startsWith('MainThread')) {
      rpc.set(id, _Echo(ids[id]!));
    }
  }
  final extSvc = byName['ExtHostExtensionService']!;
  final empty = {'contents': {}, 'keys': [], 'overrides': []};
  unawaited(rpc.call(byName['ExtHostConfiguration']!, r'$initializeConfiguration', [
    {'defaults': empty, 'policy': empty, 'application': empty, 'userLocal': empty,
     'userRemote': empty, 'workspace': empty, 'folders': [], 'configurationScopes': []},
  ]));
  unawaited(rpc.call(byName['ExtHostWorkspace']!, r'$initializeWorkspace', [
    {'id': 'probe', 'name': 'probe', 'configuration': null, 'folders': [
      {'uri': VsUri.file(tmp.path), 'name': 'probe', 'index': 0},
    ]},
    true,
  ]));
  await Future<void>.delayed(const Duration(seconds: 2));
  print(
    'activate *: ${await rpc.call(extSvc, r'$activateByEvent', ['*', 0])}',
  );
  print(
    'activate onStartupFinished: ${await rpc.call(extSvc, r'$activateByEvent', ['onStartupFinished', 0])}',
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final cmds = byName['ExtHostCommands']!;
  final r = await rpc.call(cmds, r'$executeContributedCommand', [
    'hello.say',
    ['Dart'],
  ]);
  print('command result: $r');
  print('--- requests by method ---');
  counts.forEach((k, v) => print('$v  $k'));
  await eh.protocol.close();
  await mgmt.protocol.close();
  server.kill();
  exit(0);
}

final class _Echo implements RpcActor {
  _Echo(this.name);
  final String name;
  @override
  FutureOr<Object?> invoke(String method, List<Object?> args) {
    if (name == 'MainThreadMessageService' && method == r'$showMessage') {
      final commands = args[3] as List;
      return commands.isEmpty ? null : (commands.first as Map)['handle'];
    }
    if (name == 'MainThreadWindow' && method == r'$getInitialState') {
      return {'isFocused': true, 'isActive': true};
    }
    if (name == 'MainThreadCommands' && method == r'$getCommands') {
      return <String>[];
    }
    return null;
  }
}
