// 九.6: a remote project's extensions, its host reached as an SSH host is
// (the BaoCode server's protocol, in memory: this machine plays the host).
// The runtime is installed there from the downloads (a local mirror of the
// real archives) and its VS Code server started there; the user's
// extensions installed here that run there are installed there; each
// extension runs by its `extensionKind`: TypeScript and the debuggers on
// the host, VSCodeVim (`ui`) here, editing the host's file. Python and
// Node debugging through the host.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/extensions/extension_host_service_io.dart';
import 'package:baocode/extensions/runtime/extension_runtime_service.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../remote/remote_harness.dart';
import 'debug_driver.dart';
import 'open_vsx_workspace.dart';

/// The real archives, as the acceptance tests keep them.
const _dist = '/tmp/exthost-dl/dist';

/// The host's data folder, kept between runs (its runtime installs once).
const _hostData = '/tmp/exthost-dl/memory-host';

/// A mirror of [_dist] on this machine.
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

/// An SSH host in memory, its downloads the mirror's.
Future<(SshHost, ExtensionRuntimeService)> _host(String name) async {
  HttpOverrides.global = null;
  final manifest = ExtHostRuntimeManifest.parse(
    File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
  ).withBaseUrl(await _mirror());
  final local = await Directory.systemTemp.createTemp('remote-runtime');
  addTearDown(() => local.delete(recursive: true));
  final runtime = ExtensionRuntimeService(
    loadManifest: () async => jsonEncode(manifest.toJson()),
    directory: local.path,
  );
  Directory(_hostData).createSync(recursive: true);
  final hosts = SshHosts(connect: MemoryConnector(_hostData).call);
  addTearDown(hosts.closeAll);
  return (hosts[name], runtime);
}

/// Each running extension's id, lowercase.
Set<String> _ids(ExtensionHostService host) => {
  for (final e in host.extensions.value)
    '${(e['identifier'] as Map)['value']}'.toLowerCase(),
};

/// A development extension answering `<command>` with where it runs.
String _probe(String parent, String command, List<String> kinds) {
  final folder = p.join(parent, command);
  File(p.join(folder, 'package.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'name': command.replaceAll('.', '-'),
        'publisher': 'baocode-test',
        'version': '0.0.1',
        'engines': {'vscode': '^1.90.0'},
        'main': './extension.js',
        'extensionKind': kinds,
        'activationEvents': ['onCommand:$command'],
        'contributes': {
          'commands': [
            {'command': command, 'title': command},
          ],
        },
      }),
    );
  File(p.join(folder, 'extension.js')).writeAsStringSync('''
const vscode = require('vscode');
exports.activate = (context) => {
  context.subscriptions.push(vscode.commands.registerCommand('$command', () => ({
    remoteName: vscode.env.remoteName ?? null,
    folder: vscode.workspace.workspaceFolders?.[0]?.uri.toString() ?? null,
    document: vscode.workspace.textDocuments
      .map((d) => d.uri.toString())
      .find((uri) => uri.endsWith('a.ts')) ?? null,
  })));
};
''');
  return folder;
}

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

bool _onPath(String command) {
  try {
    return Process.runSync('which', [command]).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skip = openVsxSkip() != false
      ? openVsxSkip()
      : Directory(_dist).existsSync()
      ? false
      : 'No runtime archives in $_dist';

  test(
    '九.6: over SSH, TypeScript runs on the host and VSCodeVim (ui) here, '
    'editing the host\'s file',
    () async {
      final (host, runtime) = await _host('memory-host');
      final probes = await Directory.systemTemp.createTemp('remote-probes');
      addTearDown(() => probes.delete(recursive: true));
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['vscodevim.vim'],
        files: {'a.ts': _source, 'tsconfig.json': '{}', 'a.txt': 'alpha\n'},
        remote: host,
        runtime: runtime,
        development: [_probe(probes.path, 'probe.remote', ['workspace'])],
      );
      final extensions = w.extensions;
      expect(extensions.hosts, hasLength(2));
      final there = extensions.hosts.first;
      final here = extensions.hosts.last;

      // The VS Code server runs on the host, from the runtime installed
      // there.
      expect(
        Directory(p.join(_hostData, 'exthost', 'runtimes')).listSync(),
        isNotEmpty,
      );

      // Where each extension runs: TypeScript, Emmet and the probe there,
      // Vim (`ui` by the product) and GitHub's sign-in (`ui`) here.
      expect(_ids(there), contains('vscode.typescript-language-features'));
      expect(_ids(there), contains('baocode-test.probe-remote'));
      expect(_ids(there), isNot(contains('vscodevim.vim')));
      expect(_ids(here), contains('vscodevim.vim'));
      expect(_ids(here), isNot(contains('vscode.typescript-language-features')));
      expect(_ids(here), contains('vscode.github-authentication'));
      expect(_ids(there), isNot(contains('vscode.github-authentication')));
      expect(_ids(there), contains('vscode.emmet'));
      // Vim is not installed on the host: it does not run there.
      final installedThere = await extensions.remote!.extensions.management
          .getInstalled();
      expect(
        [for (final e in installedThere) e.id.toLowerCase()],
        isNot(contains('vscodevim.vim')),
      );

      // The ui extension here: its own probe, loaded into this machine's
      // host.
      here.developmentLocations = [
        VsUri.file(_probe(probes.path, 'probe.local', ['ui'])),
      ];
      await here.manager.restart();

      // TypeScript on the host: diagnostics, completions and hover of the
      // host's file.
      final file = await w.open('a.ts');
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

      // Each host sees the project as upstream's would: the host's own
      // files there (and it is remote), the remote authority's here.
      final remote = (await extensions.commands.executeCommand(
        'probe.remote',
      ))! as Map;
      expect(remote['remoteName'], 'ssh-remote');
      expect(remote['folder'], VsUri.file(w.project).toString());
      expect(remote['document'], VsUri.file(file).toString());
      final local = (await extensions.commands.executeCommand(
        'probe.local',
      ))! as Map;
      final authority = 'ssh-remote+memory-host';
      expect(
        local['folder'],
        VsUri.file(w.project)
            .replace(scheme: 'vscode-remote', authority: authority)
            .toString(),
      );
      expect(
        local['document'],
        VsUri.file(file)
            .replace(scheme: 'vscode-remote', authority: authority)
            .toString(),
      );

      // Vim here edits the host's file.
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
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: skip,
  );

  final python = pythonExecutable();
  test(
    '九.6: over SSH, Python (debugpy, installed on the host): breakpoints, '
    'variables, stepping, console',
    () async {
      final (host, runtime) = await _host('memory-host');
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['ms-python.python'],
        files: {'main.py': _python},
        settings: {'python.defaultInterpreterPath': python},
        remote: host,
        runtime: runtime,
      );
      final there = w.extensions.hosts.first;
      // Installed there as they are installed here (the dependency after
      // the extension).
      await eventually(
        'the Python extensions there',
        () => _ids(there).containsAll(['ms-python.python', 'ms-python.debugpy'])
            ? true
            : null,
      ).catchError((Object e) => fail('$e\n${w.report()}'));
      expect(_ids(w.extensions.hosts.last), isNot(contains('ms-python.python')));
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('main.py'));
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: bpLine(_python, 'loop'), condition: 'i == 1'),
      ]);
      await d.start({
        'type': 'debugpy',
        'request': 'launch',
        'name': 'Python: main',
        'program': w.path('main.py'),
        'cwd': w.project,
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
    timeout: const Timeout(Duration(minutes: 15)),
    skip: skip == false && python == null ? 'No python3' : skip,
  );

  test(
    '九.6: over SSH, Node (the host\'s js-debug): breakpoints, variables, '
    'stepping, console',
    () async {
      final (host, runtime) = await _host('memory-host');
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [],
        files: {'main.js': _node},
        remote: host,
        runtime: runtime,
      );
      expect(_ids(w.extensions.hosts.first), contains('ms-vscode.js-debug'));
      expect(
        _ids(w.extensions.hosts.last),
        isNot(contains('ms-vscode.js-debug')),
      );
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('main.js'));
      await d.service.addBreakpoints(source, [
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
    timeout: const Timeout(Duration(minutes: 15)),
    skip: skip == false && !_onPath('node') ? 'No node' : skip,
  );
}
