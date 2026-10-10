// 九.6 over real SSH: a Linux host in Docker (test/fixtures/extensions/sshd)
// reached by the system's `ssh` with a throwaway key (the user's ~/.ssh is
// not read: its own config, key and known_hosts), the BaoCode server put
// there by SshLauncher. The host cannot reach the runtime's downloads (a
// mirror on this machine's loopback), so the runtime is downloaded here and
// sent over SSH; its VS Code server runs there. TypeScript, Python and Node
// debugging on the host; VSCodeVim (`ui`) here, editing the host's file.
//
// Needs Docker (Linux on this machine's architecture), the image built
// from the fixture (built here when missing), and the server builds
// (dart run tool/build_remote_server.dart --out /tmp/exthost-dl/server-build).
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_remote/client.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/extensions/extension_host_service_io.dart';
import 'package:baocode/extensions/runtime/extension_runtime_service.dart';
import 'package:baocode/ide/language/language_types.dart';
import 'package:baocode/remote/remote_binaries.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'debug_driver.dart';
import 'open_vsx_workspace.dart';

const _dist = '/tmp/exthost-dl/dist';
const _servers = '/tmp/exthost-dl/server-build';
const _image = 'baocode-exthost-sshd:test';
const _project = '/home/dev/proj';

String? _docker() {
  try {
    final info = Process.runSync('docker', ['info', '--format', '{{.OSType}}']);
    if (info.exitCode != 0) return 'Docker is not running';
    return null;
  } on ProcessException {
    return 'No docker';
  }
}

Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  String? stdin,
}) async {
  final process = await Process.start(executable, arguments);
  if (stdin != null) process.stdin.write(stdin);
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  final result = ProcessResult(process.pid, code, await out, await err);
  if (code != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')}: ${result.stderr}${result.stdout}',
    );
  }
  return result;
}

/// The container, and how to reach it.
final class _Box {
  _Box(this.container, this.target, this.ssh);

  final String container;

  /// `dev@127.0.0.1:<port>`.
  final String target;

  /// `ssh` with the throwaway key and known_hosts.
  final String ssh;

  /// Runs [script] there as `dev`.
  Future<String> sh(String script, {String? stdin}) async =>
      (await _run('docker', [
            'exec',
            '-i',
            '-u',
            'dev',
            container,
            'sh',
            '-c',
            script,
          ], stdin: stdin)).stdout
          as String;

  /// The project there, with [files].
  Future<void> project(Map<String, String> files) async {
    await sh('rm -rf $_project && mkdir -p $_project');
    for (final MapEntry(:key, :value) in files.entries) {
      await sh(
        'mkdir -p "\$(dirname "$_project/$key")" && cat > "$_project/$key"',
        stdin: value,
      );
    }
  }

  static Future<_Box> start(Directory scratch) async {
    final images = await _run('docker', ['images', '-q', _image]);
    if ((images.stdout as String).trim().isEmpty) {
      await _run('docker', [
        'build',
        '-t',
        _image,
        'test/fixtures/extensions/sshd',
      ]);
    }
    final key = p.join(scratch.path, 'id_ed25519');
    await _run('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', key]);
    final container =
        ((await _run('docker', [
                  'run',
                  '-d',
                  '--rm',
                  '-p',
                  '127.0.0.1::22',
                  _image,
                ])).stdout
                as String)
            .trim();
    await _run('docker', [
      'exec',
      '-i',
      container,
      'sh',
      '-c',
      'cat > /home/dev/.ssh/authorized_keys && '
          'chown dev:dev /home/dev/.ssh/authorized_keys && '
          'chmod 600 /home/dev/.ssh/authorized_keys',
    ], stdin: File('$key.pub').readAsStringSync());
    final port = RegExp(r':(\d+)\s*$')
        .firstMatch(
          ((await _run('docker', ['port', container, '22'])).stdout as String)
              .trim()
              .split('\n')
              .first,
        )!
        .group(1)!;
    // The system's ssh, told to read nothing of the user's.
    final ssh = p.join(scratch.path, 'ssh');
    File(ssh).writeAsStringSync('''
#!/bin/sh
exec /usr/bin/ssh -F /dev/null -i "$key" -o IdentitiesOnly=yes \\
  -o UserKnownHostsFile="${p.join(scratch.path, 'known_hosts')}" \\
  -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR "\$@"
''');
    await _run('chmod', ['+x', ssh]);
    // sshd up.
    for (var i = 0; ; i++) {
      final probe = await Process.run(ssh, [
        '-p',
        port,
        'dev@127.0.0.1',
        'true',
      ]);
      if (probe.exitCode == 0) break;
      if (i == 50) throw StateError('sshd: ${probe.stderr}');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return _Box(container, 'dev@127.0.0.1:$port', ssh);
  }

  Future<void> stop() async {
    await Process.run('docker', ['rm', '-f', container]);
  }
}

/// A mirror of [_dist] on this machine's loopback: not the container's.
Future<String> _mirror() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final file = File(p.join(_dist, p.basename(request.uri.path)));
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.contentLength = file.lengthSync();
      await request.response.addStream(file.openRead());
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return 'http://127.0.0.1:${server.port}/';
}

Set<String> _ids(ExtensionHostService host) => {
  for (final e in host.extensions.value)
    '${(e['identifier'] as Map)['value']}'.toLowerCase(),
};

const _source = '''
function add(first: number, second: number): number {
  return first + second;
}
const total = add(1, 2);
const count: number = 'one';
console.lo
''';

const _python = '''
def add(a, b):
    total = a + b  # BP:add
    return total


def main():
    values = []
    for i in range(3):
        values.append(add(i, 10))  # BP:loop
    print("sum", sum(values))


main()
''';

const _node = '''
function add(a, b) {
  const total = a + b; // BP:add
  return total;
}

const values = [];
for (let i = 0; i < 3; i++) {
  values.push(add(i, 10)); // BP:loop
}
console.log('sum', values.reduce((x, y) => x + y, 0));
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Object skip = switch ((openVsxSkip(), _docker())) {
    (final String reason, _) => reason,
    (_, final String reason) => reason,
    _ when !Directory(_dist).existsSync() => 'No runtime archives in $_dist',
    _ when DirectoryServerBinaries.at(_servers) == null =>
      'No server builds in $_servers',
    _ => false,
  };

  late Directory scratch;
  late _Box box;
  late String downloads;

  setUpAll(() async {
    if (skip != false) return;
    scratch = await Directory.systemTemp.createTemp('ssh-docker');
    box = await _Box.start(scratch);
    downloads = p.join(scratch.path, 'runtime');
  });

  tearDownAll(() async {
    if (skip != false) return;
    await box.stop();
    await scratch.delete(recursive: true);
  });

  /// The container as an SSH host, reached for real.
  Future<(SshHost, ExtensionRuntimeService)> sshHost() async {
    HttpOverrides.global = null;
    final manifest = ExtHostRuntimeManifest.parse(
      File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
    ).withBaseUrl(await _mirror());
    final runtime = ExtensionRuntimeService(
      loadManifest: () async => jsonEncode(manifest.toJson()),
      directory: downloads,
    );
    final launcher = SshLauncher(
      ssh: box.ssh,
      binaries: DirectoryServerBinaries.at(_servers)!,
    );
    final hosts = SshHosts(connect: launcher.connect);
    addTearDown(hosts.closeAll);
    return (hosts[box.target], runtime);
  }

  test(
    '九.6: over real SSH to Linux, the runtime sent from here; TypeScript on '
    'the host, VSCodeVim here',
    () async {
      await box.project({
        'a.ts': _source,
        'tsconfig.json': '{}',
        'a.txt': 'alpha\n',
      });
      final (host, runtime) = await sshHost();
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['vscodevim.vim'],
        remote: host,
        remoteProject: _project,
        runtime: runtime,
      );
      expect(host.hello?.platform.os, 'linux');
      final extensions = w.extensions;
      final there = extensions.hosts.first;
      final here = extensions.hosts.last;

      // The host could not download it: downloaded here, then sent.
      expect(
        File(
          p.join(
            runtime.remoteDownloads,
            'baocode-exthost-linux-${_arch()}-1.135.06055.tar.gz',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(await box.sh('ls ~/.baocode-server/data/exthost/runtimes'), isNotEmpty);

      expect(_ids(there), contains('vscode.typescript-language-features'));
      expect(_ids(there), isNot(contains('vscodevim.vim')));
      expect(_ids(here), contains('vscodevim.vim'));

      final file = await w.open('a.ts');
      expect(file, '$_project/a.ts');
      final languages = extensions.languageRoot.language;
      final diagnostics = await eventually('diagnostics', () {
        final found = languages.diagnosticsFor(file);
        return found.isEmpty ? null : found;
      });
      expect(
        diagnostics.map((d) => d.message).join('\n'),
        contains("not assignable to type 'number'"),
      );
      final completions = await eventually('completions', () async {
        final list = await languages.completion(file, const LspPosition(5, 10));
        return list.items.isEmpty ? null : list;
      });
      expect(completions.items.map((i) => i.label), contains('log'));
      final hover = await eventually(
        'hover',
        () => languages.hover(file, const LspPosition(3, 7)),
      );
      expect(hover.markdown, contains('const total: number'));

      // Vim here edits the host's file; saved, it is there.
      final view = await w.show('a.txt');
      await w.activated('vscodevim.vim');
      await eventually(
        'Normal mode',
        () => extensions.contextKeys.getContextKeyValue('vim.mode') == 'Normal'
            ? true
            : null,
      );
      view.controller.setSelections([const TextSelection.collapsed(offset: 0)]);
      w.workspace.editorViews.changed(view);
      view.controller.type('x');
      await eventually(
        'the edit',
        () => view.document.text == 'lpha\n' ? true : null,
      );
      await w.workspace.save(view.document);
      expect(await box.sh('cat $_project/a.txt'), 'lpha\n');
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: skip,
  );

  test(
    '九.6: over real SSH to Linux, Python debugging on the host',
    () async {
      await box.project({'main.py': _python});
      final (host, runtime) = await sshHost();
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['ms-python.python'],
        settings: {'python.defaultInterpreterPath': '/usr/bin/python3'},
        remote: host,
        remoteProject: _project,
        runtime: runtime,
      );
      final there = w.extensions.hosts.first;
      try {
        await eventually(
          'the Python extensions there',
          () =>
              _ids(there).containsAll(['ms-python.python', 'ms-python.debugpy'])
              ? true
              : null,
        );
      } on Object catch (e) {
        fail('$e\n${w.report()}');
      }
      final d = DebugDriver(w);
      await d.service.addBreakpoints(VsUri.file('$_project/main.py'), [
        BreakpointData(
          lineNumber: bpLine(_python, 'loop'),
          condition: 'i == 1',
        ),
      ]);
      await d.start({
        'type': 'debugpy',
        'request': 'launch',
        'name': 'Python: main',
        'program': '$_project/main.py',
        'cwd': _project,
        'console': 'internalConsole',
      });
      var frame = await d.stopped(bpLine(_python, 'loop'), function: 'main');
      expect((await d.variables(frame))['i'], '1');
      expect(await d.watch(frame, 'i * 2'), '2');
      await d.thread.stepIn();
      frame = await d.stopped(bpLine(_python, 'add'), function: 'add');
      expect((await d.variables(frame))['a'], '1');
      await d.service.removeBreakpoints();
      await d.thread.continue_();
      await d.ended();
      expect(d.console(), contains('sum 33'));
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: skip,
  );

  test(
    '九.6: over real SSH to Linux, Node debugging on the host',
    () async {
      await box.project({'main.js': _node});
      final (host, runtime) = await sshHost();
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [],
        remote: host,
        remoteProject: _project,
        runtime: runtime,
      );
      expect(_ids(w.extensions.hosts.first), contains('ms-vscode.js-debug'));
      final d = DebugDriver(w);
      await d.service.addBreakpoints(VsUri.file('$_project/main.js'), [
        BreakpointData(lineNumber: bpLine(_node, 'add'), hitCondition: '2'),
      ]);
      await d.start({
        'type': 'node',
        'request': 'launch',
        'name': 'Node: main',
        'program': r'${workspaceFolder}/main.js',
        'cwd': r'${workspaceFolder}',
      });
      var frame = await d.stopped(bpLine(_node, 'add'), function: 'add');
      expect((await d.variables(frame, 'Local'))['a'], '1');
      expect(await d.evaluate(frame, 'a + b'), '11');
      await d.thread.stepOut();
      frame = await d.stopped(null, past: frame);
      await d.service.removeBreakpoints();
      await d.thread.continue_();
      await d.ended();
      expect(d.console(), contains('sum 33'));
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: skip,
  );
}

/// The container's architecture: this machine's.
String _arch() => switch (Abi.current()) {
  Abi.macosArm64 || Abi.linuxArm64 => 'arm64',
  _ => 'x64',
};
