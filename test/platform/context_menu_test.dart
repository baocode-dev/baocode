import 'dart:convert';
import 'dart:io';

import 'package:baocode/platform/context_menu.dart';
import 'package:baocode/platform/context_menu_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Open with BaoCode in the system's context menu, with the commands it
/// runs answered here: `pluginkit` for the Finder extension, PowerShell
/// for Explorer's registry keys.
void main() {
  const labels = (agent: 'Open with BaoCode', ide: 'Open with Fast Ide');

  group('macOS (the Finder extension)', () {
    late Directory root;
    late String extension;
    late List<List<String>> ran;
    late String listed;
    late int electionExit;

    setUp(() {
      root = Directory.systemTemp.createTempSync('baocode-finder');
      extension = p.join(root.path, 'FinderExtension.appex');
      Directory(extension).createSync();
      ran = [];
      listed = '';
      electionExit = 0;
    });
    tearDown(() => root.deleteSync(recursive: true));

    MacContextMenu menu() => MacContextMenu(
      extensionPath: extension,
      run: (executable, arguments, {environment}) async {
        ran.add([executable, ...arguments]);
        if (arguments.first == '-m') return ProcessResult(0, 0, listed, '');
        if (arguments.first == '-e') {
          return ProcessResult(0, electionExit, '', 'no matches');
        }
        return ProcessResult(0, 0, '', '');
      },
    );

    test('on when pluginkit lists it with a +; off otherwise', () async {
      listed = '     dev.baocode.desktop.FinderExtension(1.0.0)\n';
      expect(await menu().status(), ContextMenuStatus.off);
      listed = '-    dev.baocode.desktop.FinderExtension(1.0.0)\n';
      expect(await menu().status(), ContextMenuStatus.off);
      listed =
          '     dev.baocode.desktop.FinderExtension(1.0.0)\n'
          '+    dev.baocode.desktop.FinderExtension(1.0.0)\n';
      expect(await menu().status(), ContextMenuStatus.on);
      expect(ran.last, [
        'pluginkit',
        '-m',
        '-i',
        'dev.baocode.desktop.FinderExtension',
      ]);
    });

    test(
      'turned on: this copy registered, then elected; off: ignored',
      () async {
        await menu().install(labels);
        expect(ran, [
          ['pluginkit', '-a', extension],
          [
            'pluginkit',
            '-e',
            'use',
            '-i',
            'dev.baocode.desktop.FinderExtension',
          ],
        ]);
        ran.clear();
        await menu().uninstall();
        expect(ran, [
          [
            'pluginkit',
            '-e',
            'ignore',
            '-i',
            'dev.baocode.desktop.FinderExtension',
          ],
        ]);
      },
    );

    test('a refusal is told, with what pluginkit said', () async {
      electionExit = 1;
      await expectLater(
        menu().install(labels),
        throwsA(
          isA<ContextMenuException>().having(
            (error) => error.message,
            'message',
            'Could not turn on the Finder extension. no matches',
          ),
        ),
      );
    });

    test('a build without the extension has none to turn on', () async {
      Directory(extension).deleteSync();
      expect(await menu().status(), ContextMenuStatus.unsupported);
      await expectLater(
        menu().install(labels),
        throwsA(isA<ContextMenuException>()),
      );
      expect(ran, isEmpty);
    });

    test('System Settings opens at the extensions', () async {
      await menu().openSystemSettings();
      expect(ran.single, [
        'open',
        'x-apple.systempreferences:com.apple.ExtensionsPreferences',
      ]);
    });
  });

  group('Windows (Explorer\'s registry keys)', () {
    const exe = r'C:\Program Files\BaoCode\baocode.exe';
    late List<Map<String, String>?> environments;
    late String where;

    WindowsContextMenu menu() => WindowsContextMenu(
      executable: exe,
      run: (executable, arguments, {environment}) async {
        expect(executable, 'powershell.exe');
        environments.add(environment);
        // The status script is the one without values.
        return ProcessResult(0, 0, environment == null ? where : '', '');
      },
    );

    setUp(() {
      environments = [];
      where = '0 0';
    });

    test('the installer\'s keys, for the user: a file\'s takes it, a '
        'folder\'s and its background\'s the folder', () {
      final entries = menu().entries(labels);
      expect(entries.map((entry) => entry.key), [
        r'Software\Classes\*\shell\BaoCode',
        r'Software\Classes\*\shell\BaoCodeFastIde',
        r'Software\Classes\Directory\shell\BaoCode',
        r'Software\Classes\Directory\shell\BaoCodeFastIde',
        r'Software\Classes\Directory\Background\shell\BaoCode',
        r'Software\Classes\Directory\Background\shell\BaoCodeFastIde',
      ]);
      expect(entries[0].label, 'Open with BaoCode');
      expect(entries[0].command, '"$exe" --baocode-agent "%1"');
      expect(entries[1].label, 'Open with Fast Ide');
      expect(entries[1].command, '"$exe" --baocode-cli "%1" -n "%1"');
      expect(entries[4].command, '"$exe" --baocode-agent "%V"');
      expect(entries[5].command, '"$exe" --baocode-cli "%V" -n "%V"');
    });

    test('on when the user\'s hive or the machine\'s has it', () async {
      expect(await menu().status(), ContextMenuStatus.off);
      where = '1 0';
      expect(await menu().status(), ContextMenuStatus.on);
      where = '0 1';
      expect(await menu().status(), ContextMenuStatus.on);
    });

    test('turned on, the keys go to PowerShell as values, not code', () async {
      await menu().install(labels);
      final environment = environments.single!;
      expect(environment['BAOCODE_ICON'], '"$exe"');
      final written = jsonDecode(environment['BAOCODE_MENU']!) as List;
      expect(written, hasLength(6));
      expect(written.first, {
        'key': r'Software\Classes\*\shell\BaoCode',
        'label': 'Open with BaoCode',
        'command': '"$exe" --baocode-agent "%1"',
      });
    });

    test('turned off, the user\'s keys go; the machine\'s, which only the '
        'installer removes, are told of', () async {
      await menu().uninstall();
      final removed =
          jsonDecode(environments.first!['BAOCODE_MENU']!) as List<Object?>;
      expect(removed, contains(r'Software\Classes\Directory\shell\BaoCode'));
      expect(removed, hasLength(6));

      where = '0 1';
      await expectLater(
        menu().uninstall(),
        throwsA(isA<ContextMenuException>()),
      );
    });
  });

  test('the platform\'s stands in for one under test', () async {
    final fake = _FakeInstaller();
    ContextMenu.debugInstaller = fake;
    addTearDown(() => ContextMenu.debugInstaller = null);
    expect(ContextMenu.supported, isTrue);
    expect(await ContextMenu.status(), ContextMenuStatus.off);
    await ContextMenu.install(labels);
    expect(await ContextMenu.status(), ContextMenuStatus.on);
    expect(fake.labels, labels);
    expect(ContextMenu.openSystemSettings, isNull);
  });
}

class _FakeInstaller implements ContextMenuInstaller {
  ContextMenuStatus _status = ContextMenuStatus.off;
  ContextMenuLabels? labels;

  @override
  Future<ContextMenuStatus> status() async => _status;

  @override
  Future<void> install(ContextMenuLabels labels) async {
    this.labels = labels;
    _status = ContextMenuStatus.on;
  }

  @override
  Future<void> uninstall() async => _status = ContextMenuStatus.off;

  @override
  Future<void> Function()? get openSystemSettings => null;
}
