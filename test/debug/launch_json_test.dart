// launch.json: reading JSONC, selection, platform overrides, compounds,
// creating the file from a debugger's initial configurations, appending
// and editing configurations while keeping comments.

import 'package:baocode/base/cancellation.dart' show CancellationTokenSource;
import 'package:baocode/base/uri.dart' show VsUri;
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_configuration_manager.dart';
import 'package:baocode/debug/service/debug_host.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_debug_adapter.dart';

final _launchUri = VsUri.file('/work/app/.vscode/launch.json').toString();

const _launchJson = '''{
  // Use IntelliSense to learn about possible attributes.
  "version": "0.2.0",
  "configurations": [
    {
      "type": "fake",
      "request": "launch",
      "name": "Launch",
      "program": "\${workspaceFolder}/main.js", // the entry
      "osx": {"program": "\${workspaceFolder}/mac.js"},
      "presentation": {"group": "b", "order": 2},
    },
    {"type": "fake", "request": "attach", "name": "Attach", "port": 9229, "presentation": {"group": "a"}},
    {"type": "fake", "request": "launch", "name": "Hidden", "presentation": {"hidden": true}},
    {"type": "fake", "request": "launch", "name": "Launch"},
  ],
  "compounds": [
    {"name": "All", "configurations": ["Launch", "Attach"]},
    {"name": "Empty", "configurations": []},
  ],
  "inputs": [
    {"id": "port", "type": "promptString", "description": "Port?"},
  ],
}
''';

void main() {
  test('reads JSONC, sorts by presentation, hides, deduplicates names', () async {
    final f = await createFakeDebugService(launchFiles: {_launchUri: _launchJson});
    final launch = f.service.configurationManager.getLaunches().first as FolderLaunch;
    expect(launch.errors, isEmpty);
    expect(launch.getConfigurationNames(), ['Attach', 'Launch', 'Launch (1)', 'All']);
    expect(launch.getConfigurationNames(ignoreCompoundsAndPresentation: true), [
      'Launch',
      'Attach',
      'Hidden',
      'Launch (1)',
    ]);
    // The macOS override applies.
    final config = launch.getConfiguration('Launch')!;
    expect(config['program'], r'${workspaceFolder}/mac.js');
    // As upstream, the platform keys stay until variables are resolved.
    expect(config.containsKey('osx'), isTrue);
    expect(config['__configurationTarget'], 6);
    expect(launch.getCompound('All')!['configurations'], ['Launch', 'Attach']);
    expect(launch.inputs!.single['id'], 'port');

    final all = f.service.configurationManager.getAllConfigurations();
    expect(all.map((e) => e.name), ['Attach', 'Launch', 'Launch (1)', 'All']);
    f.service.dispose();
  });

  test('selects the first, remembers the choice, follows file changes', () async {
    final f = await createFakeDebugService(launchFiles: {_launchUri: _launchJson});
    final manager = f.service.configurationManager;
    expect(manager.selectedConfiguration.name, 'Attach');
    await manager.selectConfiguration(manager.getLaunches().first, name: 'Launch');
    expect(manager.selectedConfiguration.name, 'Launch');
    expect((await manager.selectedConfiguration.getConfig())!['request'], 'launch');
    expect(f.service.storage.backend.get('debug.selectedconfigname'), 'Launch');

    // The file loses "Launch": the selection falls back.
    f.files.files[_launchUri] = '{"configurations": [{"type": "fake", "request": "launch", "name": "Only"}]}';
    await manager.reload();
    expect(manager.selectedConfiguration.name, 'Only');
    f.service.dispose();
  });

  test('openConfigFile creates launch.json from the initial configurations', () async {
    final f = await createFakeDebugService();
    final launch = f.service.configurationManager.getLaunches().first as FolderLaunch;
    expect(launch.getConfig(), isNull);
    final result = await launch.openConfigFile(type: 'fake');
    expect(result.created, isTrue);
    final text = f.files.files[_launchUri]!;
    expect(text, startsWith('{\n    // Use IntelliSense'));
    final parsed = parseJsonc(text)! as Map;
    expect(parsed['version'], '0.2.0');
    expect((parsed['configurations'] as List).single, {
      'type': 'fake',
      'request': 'launch',
      'name': 'Launch Program',
      'program': r'${file}',
    });
    expect(f.host.opened.single.$1.toString(), _launchUri);
    expect(f.service.configurationManager.selectedConfiguration.name, 'Launch Program');
    f.service.dispose();
  });

  test('providers add initial configurations; tabs when the editor uses them', () async {
    final f = await createFakeDebugService();
    f.host.settingValues['editor.insertSpaces'] = false;
    f.service.configurationManager.providers.register(
      DebugConfigurationProvider(
        type: 'fake',
        provideDebugConfigurations: (folder, token) async => [
          {'type': 'fake', 'request': 'attach', 'name': 'From provider', 'folder': folder?.path},
        ],
      ),
    );
    final launch = f.service.configurationManager.getLaunches().first;
    await launch.openConfigFile(type: 'fake');
    final text = f.files.files[_launchUri]!;
    expect(text, contains('\t"configurations": [\n\t\t{'));
    final configs = (parseJsonc(text)! as Map)['configurations'] as List;
    expect(configs.map((c) => (c as Map)['name']), ['Launch Program', 'From provider']);
    expect((configs.last as Map)['folder'], '/work/app');
    f.service.dispose();
  });

  test('without a type the debugger is picked', () async {
    final f = await createFakeDebugService();
    f.host.pickAnswers.add('Fake Debugger');
    final launch = f.service.configurationManager.getLaunches().first;
    final result = await launch.openConfigFile();
    expect(result.created, isTrue);
    f.service.dispose();

    final g = await createFakeDebugService();
    g.host.editor = DebugActiveEditor(uri: VsUri.file('/work/app/main.js'), languageId: 'javascript');
    // Interested in javascript: no picker.
    final guess = await g.service.registry.guessDebugger(false);
    expect(guess!.debugger.type, 'fake');
    g.service.dispose();
  });

  test('writeConfiguration appends and keeps comments; attributes edit in place', () async {
    final f = await createFakeDebugService(launchFiles: {_launchUri: _launchJson});
    final launch = f.service.configurationManager.getLaunches().first as FolderLaunch;
    await launch.writeConfiguration({'type': 'fake', 'request': 'launch', 'name': 'Added', '__configurationTarget': 6});
    var text = f.files.files[_launchUri]!;
    expect(text, contains('// Use IntelliSense to learn about possible attributes.'));
    expect(text, contains('// the entry'));
    expect(launch.getConfigurationNames(ignoreCompoundsAndPresentation: true).last, 'Added');
    expect(text, isNot(contains('__configurationTarget')));

    await launch.updateConfigurationAttribute('Attach', 'port', 9230);
    text = f.files.files[_launchUri]!;
    expect(text, contains('"port": 9230'));
    expect(text, contains('// the entry'));
    await launch.updateConfigurationAttribute('Attach', 'port', null);
    expect(launch.getConfiguration('Attach')!.containsKey('port'), isFalse);

    // An empty file, or none, gets the skeleton first.
    f.files.files.remove(_launchUri);
    await launch.writeConfiguration({'type': 'fake', 'request': 'launch', 'name': 'First'});
    expect((parseJsonc(f.files.files[_launchUri]!)! as Map)['version'], '0.2.0');
    expect(launch.getConfigurationNames(), ['First']);
    f.service.dispose();
  });

  test('resolve providers run by type, then *, again when the type changes', () async {
    final f = await createFakeDebugService();
    final manager = f.service.configurationManager;
    final calls = <String>[];
    manager.providers
      ..register(
        DebugConfigurationProvider(
          type: 'fake',
          resolveDebugConfiguration: (folder, config, token) async {
            calls.add('fake');
            return {...config, 'resolvedBy': 'fake'};
          },
        ),
      )
      ..register(
        DebugConfigurationProvider(
          type: '*',
          resolveDebugConfiguration: (folder, config, token) async {
            calls.add('*');
            return config;
          },
          resolveDebugConfigurationWithSubstitutedVariables: (folder, config, token) async {
            calls.add('*2');
            return config['abort'] == true ? null : config;
          },
        ),
      );
    final token = CancellationTokenSource().token;
    final resolved = await manager.resolveConfigurationByProviders(null, null, {'type': 'fake'}, token);
    expect((resolved! as Json)['resolvedBy'], 'fake');
    expect(calls, ['fake', '*']);
    expect(await manager.resolveDebugConfigurationWithSubstitutedVariables(null, 'fake', {'abort': true}, token), isNull);

    // A provider asking for launch.json.
    manager.providers.register(
      DebugConfigurationProvider(type: 'other', resolveDebugConfiguration: (_, _, _) async => openLaunchJson),
    );
    expect(
      await manager.resolveConfigurationByProviders(null, 'other', {'type': 'other'}, token),
      same(openLaunchJson),
    );
    f.service.dispose();
  });

  test('variables, commands and inputs resolve when a session starts', () async {
    final f = await createFakeDebugService(launchFiles: {_launchUri: _launchJson});
    f.host.commands['fake.pickProcess'] = (args) => '4711';
    f.host.inputAnswers.add('9333');
    f.host.settingValues['fake.port'] = 9222;
    final launch = f.service.configurationManager.getLaunches().first;
    expect(
      await f.service.startDebugging(launch, {
        'type': 'fake',
        'request': 'attach',
        'name': 'Vars',
        'processId': r'${command:PickProcess}',
        'port': r'${input:port}',
        'other': r'${config:fake.port}',
        'env': {'HOME': r'${env:HOME}', r'${env:PORT}': 'key'},
        'cwd': r'${workspaceFolder}',
        'base': r'${workspaceFolderBasename}',
      }),
      isTrue,
    );
    final args = f.factory.last.launchArgs!;
    expect(args['processId'], '4711');
    expect(args['port'], '9333');
    expect(args['other'], '9222');
    expect(args['env'], {'HOME': '/Users/me', '9229': 'key'});
    expect(args['cwd'], '/work/app');
    expect(args['base'], 'app');
    await f.service.stopSession(null);

    // A cancelled input stops the start without an error.
    final before = f.factory.adapters.length;
    expect(
      await f.service.startDebugging(launch, {'type': 'fake', 'request': 'attach', 'name': 'x', 'port': r'${input:port}'}),
      isFalse,
    );
    expect(f.factory.adapters.length, before);
    f.service.dispose();
  });
}
