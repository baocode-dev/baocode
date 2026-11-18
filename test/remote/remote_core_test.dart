import 'package:bao_remote/claude.dart';
import 'package:bao_remote/client.dart';
import 'package:baocode/remote/remote_claude.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter_test/flutter_test.dart';

class _Process implements RemoteProcess {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What runs Claude Code on a remote host, as its server saved in the app
/// says: the CLI where the host has one, else BaoCode's own core.
void main() {
  final previous = SshHosts.instance;
  late SshHosts hosts;
  setUp(() {
    hosts = SshHosts.instance = SshHosts()
      ..savedServers = () => {
        'auto': const SshServer(hostName: 'a.example'),
        'builtin': const SshServer(
          hostName: 'b.example',
          core: SshCore.builtin,
        ),
        'cli': const SshServer(hostName: 'c.example', core: SshCore.cli),
      };
  });
  tearDown(() => SshHosts.instance = previous);

  /// The cores [host] was started with, the CLI's missing when not
  /// [installed]; what came of it.
  Future<(List<String?>, Object?)> start(
    String host, {
    required bool model,
    required bool installed,
    bool install = false,
  }) async {
    final tried = <String?>[];
    Object? outcome;
    try {
      outcome = await startRemoteCore(
        hosts[host],
        model: model,
        install: install,
        start: (core) async {
          tried.add(core);
          if (core == null && !installed) {
            throw const ClaudeNotInstalled('No Claude Code here');
          }
          return _Process();
        },
      );
    } on Object catch (error) {
      outcome = error;
    }
    return (tried, outcome);
  }

  test('automatic: the CLI the host has; else, on an upstream, the '
      'built-in core', () async {
    expect((await start('auto', model: true, installed: true)).$1, [null]);
    final (tried, outcome) = await start('auto', model: true, installed: false);
    expect(tried, [null, 'builtin']);
    expect(outcome, isA<RemoteProcess>());
  });

  test("automatic, on Claude Code's own model: the CLI the host has; else "
      'a model asked for, nothing installed', () async {
    expect((await start('auto', model: false, installed: true)).$1, [null]);
    final (tried, outcome) = await start(
      'auto',
      model: false,
      installed: false,
      install: true,
    );
    expect(tried, [null]);
    expect(outcome, isA<ClaudeNoModel>());
  });

  test('a host not saved in the app: automatic', () async {
    expect(remoteCoreOf('me@elsewhere'), SshCore.auto);
    expect((await start('me@elsewhere', model: true, installed: false)).$1, [
      null,
      'builtin',
    ]);
  });

  test(
    'built-in: never the CLI; without an upstream, a model asked for',
    () async {
      expect((await start('builtin', model: true, installed: true)).$1, [
        'builtin',
      ]);
      final (tried, outcome) = await start(
        'builtin',
        model: false,
        installed: true,
      );
      expect(tried, isEmpty);
      expect(outcome, isA<ClaudeNoModel>());
    },
  );

  test('the CLI: never the built-in core', () async {
    final (tried, outcome) = await start('cli', model: true, installed: false);
    expect(tried, [null]);
    expect(outcome, isA<ClaudeNotInstalled>());
  });

  test('saved with it, read back', () {
    const server = SshServer(hostName: 'x', core: SshCore.cli);
    expect(server.toJson()['core'], 'cli');
    expect(SshServer.fromJson(server.toJson()), server);
    expect(const SshServer(hostName: 'x').toJson().containsKey('core'), false);
    expect(
      SshServer.fromJson({'hostName': 'x', 'core': '?'})!.core,
      SshCore.auto,
    );
  });
}
