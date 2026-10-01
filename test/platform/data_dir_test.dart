@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/platform/data_dir.dart';
import 'package:path/path.dart' as p;

/// Where the data folder is found: `MONAD_DATA_DIR`, else the pointer in
/// `~/.monad`, else the platform's place. Every home is a temporary one.
void main() {
  late Directory home;
  late Map<String, String> environment;

  setUp(() {
    home = Directory.systemTemp.createTempSync('monad-home');
    environment = {'HOME': home.path};
  });
  tearDown(() {
    // Undo a read-only folder's mode, so it can go.
    for (final entity in home.listSync(recursive: true)) {
      if (entity is Directory) Process.runSync('chmod', ['755', entity.path]);
    }
    home.deleteSync(recursive: true);
  });

  File pointer() =>
      File(p.join(home.path, '.monad', 'config-dir.json'))
        ..parent.createSync(recursive: true);

  Directory folder(String name) =>
      Directory(p.join(home.path, name))..createSync(recursive: true);

  DataDirectoryResolution resolve() =>
      resolveDataDirectory(environment: environment, home: home.path);

  test('the platform default without a variable or pointer', () {
    final resolution = resolve();
    expect(resolution.ok, isTrue);
    expect(resolution.source, DataDirectorySource.defaultLocation);
    expect(resolution.path, DataDirectory.defaultPath(environment));
    expect(
      resolution.path,
      startsWith(home.path),
      reason: 'under the home it was given',
    );
    expect(
      resolution.pointerFile,
      p.join(home.path, '.monad', 'config-dir.json'),
    );
  });

  test('the pointer, then the variable, win', () {
    final pointed = folder('Pointed');
    final variable = folder('Variable');
    pointer().writeAsStringSync('{"dataDir": "${pointed.path}"}');
    expect(
      (resolve().path, resolve().source),
      (pointed.path, DataDirectorySource.pointer),
    );

    environment['MONAD_DATA_DIR'] = variable.path;
    expect(
      (resolve().path, resolve().source),
      (variable.path, DataDirectorySource.environment),
    );
    expect(resolve().directory.path, variable.path);
  });

  test('~ is the home, in the pointer and the variable', () {
    folder('Data/monad');
    pointer().writeAsStringSync('{"dataDir": "~/Data/monad"}');
    expect(resolve().path, p.join(home.path, 'Data', 'monad'));
    environment['MONAD_DATA_DIR'] = '~';
    expect(resolve().path, home.path);
    expect(expandDataDirectory(r'~\x', '/h'), p.join('/h', 'x'));
    expect(expandDataDirectory('/a/~', '/h'), '/a/~');
  });

  test('a pointer without dataDir (only the folder moved from) is the '
      'default', () {
    pointer().writeAsStringSync('{"previousDataDir": "/old"}');
    expect(resolve().source, DataDirectorySource.defaultLocation);
    expect(resolve().ok, isTrue);
  });

  test('an invalid pointer is reported, and left as it is', () {
    for (final text in [
      'not json',
      '[]',
      '{"dataDir": 3}',
      '{"dataDir": "relative/path"}',
    ]) {
      pointer().writeAsStringSync(text);
      final resolution = resolve();
      expect(resolution.ok, isFalse, reason: text);
      expect(resolution.problem, DataDirectoryProblem.invalidPointer);
      expect(resolution.error, contains('config-dir.json'));
      expect(resolution.path, resolution.defaultPath);
      expect(pointer().readAsStringSync(), text);
    }
  });

  test('a folder that is missing or read-only is reported, not replaced '
      'by the default', () {
    final gone = p.join(home.path, 'Volumes', 'D', 'Monad');
    pointer().writeAsStringSync('{"dataDir": "$gone"}');
    var resolution = resolve();
    expect(resolution.ok, isFalse);
    expect(resolution.problem, DataDirectoryProblem.missing);
    expect(resolution.path, gone);
    expect(resolution.source, DataDirectorySource.pointer);
    expect(Directory(gone).existsSync(), isFalse, reason: 'not made');

    final file = File(p.join(home.path, 'file'))..writeAsStringSync('');
    environment['MONAD_DATA_DIR'] = file.path;
    expect(resolve().problem, DataDirectoryProblem.missing);

    final readOnly = folder('ReadOnly');
    Process.runSync('chmod', ['555', readOnly.path]);
    environment['MONAD_DATA_DIR'] = readOnly.path;
    resolution = resolve();
    expect(resolution.problem, DataDirectoryProblem.notWritable);
    expect(resolution.source, DataDirectorySource.environment);
  });

  test('the layout', () {
    const dir = DataDirectory('/data');
    expect(dir.settingsFile, '/data/User/settings.json');
    expect(dir.keybindingsFile, '/data/User/keybindings.json');
    expect(dir.lspSettingsFile, '/data/User/lsp.json');
    expect(dir.argvFile, '/data/argv.json');
    expect(dir.keymapsDir, '/data/keymaps');
    expect(dir.stateFile, '/data/state/state.json');
    expect(dir.storageFile, '/data/state/storage.json');
    expect(
      dir.processRegistryFile('claude'),
      '/data/state/claude-processes.json',
    );
    expect(dir.serversDir, '/data/servers');
    expect(dir.languagePacksDir, '/data/language-packs');
  });

  test('under test, the current one is never the user\'s', () {
    expect(
      DataDirectory.current.path,
      isNot(DataDirectory.defaultPath(Platform.environment)),
    );
    expect(DataDirectory.current.path, startsWith(Directory.systemTemp.path));
  });

  test('the pointer is written whole, and removed when empty', () async {
    final file = pointer();
    await const DataDirectoryPointer(
      dataDir: '/new',
      previousDataDir: '/old',
    ).write(file);
    final read = DataDirectoryPointer.read(file)!;
    expect((read.dataDir, read.previousDataDir), ('/new', '/old'));
    expect(file.parent.listSync(), hasLength(1), reason: 'nothing aside');
    await const DataDirectoryPointer().write(file);
    expect(file.existsSync(), isFalse);
  });
}
