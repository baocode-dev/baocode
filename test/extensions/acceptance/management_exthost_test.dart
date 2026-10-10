// 九.3: managing extensions in a fresh data folder, as the Extensions view,
// the .vsix drop and the import dialog do it, with the real server and
// Open VSX: a .vsix dropped and installed (it activates in the running
// host), an import from VS Code and Cursor (Open VSX reinstall, a
// proprietary one's alternative, Cursor's own skipped, their settings),
// enable and disable (in the workspace and globally, with Restart
// Extensions for those that ran), an update, an uninstall; then the app
// starting again on the same data folder keeps all of it.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/import/extension_import.dart';
import 'package:baocode/extensions/ui/vsix_drop.dart';
import 'package:baocode/keybindings/vscode_import.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'open_vsx_workspace.dart';

const _errorLens = 'usernamehw.errorlens';
const _todoTree = 'Gruntfuggly.todo-tree';
const _basedPyright = 'detachhead.basedpyright';
const _dracula = 'dracula-theme.theme-dracula';

/// An extension folder as VS Code keeps it, contributing [settings].
void _extensionFolder(
  String folder,
  String id,
  String version, {
  List<String> settings = const [],
}) {
  final dot = id.indexOf('.');
  File(p.join(folder, 'package.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'name': id.substring(dot + 1),
        'publisher': id.substring(0, dot),
        'version': version,
        'engines': {'vscode': '^1.80.0'},
        'contributes': {
          'configuration': {
            'properties': {
              for (final key in settings) key: {'type': 'array'},
            },
          },
        },
      }),
    );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '九.3: drop, import, enable/disable, update, uninstall, and all of it '
    'after a restart',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [],
        files: {'notes.txt': 'TODO: check\n'},
      );
      final model = w.extensions.extensionsModel;
      final host = w.extensions.host!;
      String? running(String id) {
        for (final e in host.extensions.value) {
          final identifier = e['identifier'];
          if (identifier is Map &&
              '${identifier['value']}'.toLowerCase() == id.toLowerCase()) {
            return e['version'] as String?;
          }
        }
        return null;
      }

      // Drop: Error Lens's .vsix (as the sheet installs it once
      // confirmed). It activates in the running host (onStartupFinished).
      final vsix = p.join(openVsxCacheDir(), '$_errorLens-3.29.0.vsix');
      expect(await classifyExtensionDrop(vsix), ExtensionDropKind.vsix);
      final dropped = await w.extensions.management.install(vsix);
      expect(dropped.id.toLowerCase(), _errorLens);
      await eventually('Error Lens running', () => running(_errorLens));
      await w.activated(_errorLens);

      // Import from VS Code and Cursor.
      final home = p.join(w.root, 'home');
      final installs = VsCodeInstalls(
        home: home,
        environment: {'HOME': home},
        platform: KeybindingPlatform.mac,
      );
      final code = installs.extensionsDir(VsCodeProduct.code);
      final cursor = installs.extensionsDir(VsCodeProduct.cursor);
      _extensionFolder(
        '$code/gruntfuggly.todo-tree-0.0.200',
        _todoTree,
        '0.0.200',
        settings: ['todo-tree.general.tags'],
      );
      _extensionFolder(
        '$code/ms-python.vscode-pylance-2024.1.1',
        'ms-python.vscode-pylance',
        '2024.1.1',
      );
      _extensionFolder(
        '$cursor/anysphere.cursorpyright-1.0.0',
        'anysphere.cursorpyright',
        '1.0.0',
      );
      final codeUser = installs.userDir(VsCodeProduct.code);
      File(p.join(codeUser, 'settings.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"todo-tree.general.tags": ["FIXME", "TODO"], '
          '"editor.fontSize": 20}',
        );
      final planner = ExtensionImportPlanner(
        installs: installs,
        gallery: w.app.gallery,
      );
      expect(
        (await planner.detectProducts()).keys,
        containsAll([VsCodeProduct.code, VsCodeProduct.cursor]),
      );
      await model.refreshInstalled();
      final plan = await planner.plan([
        VsCodeProduct.code,
        VsCodeProduct.cursor,
      ], installed: model.installed!);
      ImportPlanItem item(String id) =>
          plan.items.firstWhere((i) => i.key == id.toLowerCase());
      expect(item(_todoTree).action, ImportAction.reinstall);
      expect(item('ms-python.vscode-pylance').action, ImportAction.proprietary);
      expect([
        for (final a in item('ms-python.vscode-pylance').alternatives) a.id,
      ], contains(_basedPyright));
      expect(item('anysphere.cursorpyright').action, ImportAction.skip);
      expect(
        item('anysphere.cursorpyright').skipReason,
        ImportSkipReason.editorSpecific,
      );
      final settingsPath = p.join(w.root, 'settings.json');
      final report =
          await ExtensionImporter(
            backend: w.extensions.management,
            gallery: w.app.gallery,
          ).run(
            plan,
            selected: {
              for (final i in plan.items)
                if (i.selectable) i.key,
            },
            settingsPath: settingsPath,
          );
      ImportOutcome outcome(String id) => report.entries
          .firstWhere((e) => e.id.toLowerCase() == id.toLowerCase())
          .outcome;
      expect(outcome(_todoTree), ImportOutcome.installed);
      expect(
        outcome('ms-python.vscode-pylance'),
        ImportOutcome.alternativeInstalled,
      );
      expect(outcome('anysphere.cursorpyright'), ImportOutcome.notImported);
      expect(
        [for (final s in report.settingsAdded) s.key],
        ['todo-tree.general.tags'],
      );
      expect(
        (parseJsonc(File(settingsPath).readAsStringSync()) as Map)
            .cast<String, Object?>()['todo-tree.general.tags'],
        ['FIXME', 'TODO'],
      );
      await eventually('Todo Tree running', () => running(_todoTree));
      await eventually('basedpyright running', () => running(_basedPyright));
      await w.activated(_todoTree);

      // Disabled in the workspace and globally after they ran: they run
      // on until Restart Extensions.
      await model.setEnabled(_errorLens, false, EnablementScope.workspace);
      await model.setEnabled(_todoTree, false, EnablementScope.global);
      await eventually(
        'Restart Extensions offered',
        () =>
            model.needsRestart(_errorLens) &&
                model.needsRestart(_todoTree.toLowerCase())
            ? true
            : null,
      );
      expect(running(_errorLens), isNotNull);
      await model.restartExtensions!();
      await eventually(
        'the disabled ones stopped',
        () => running(_errorLens) == null && running(_todoTree) == null
            ? true
            : null,
      );
      expect(model.needsRestart(_errorLens), isFalse);

      // An older Dracula, then its update; it never activates, so the
      // host takes the new version at once.
      await model.install(_dracula, version: '2.24.2');
      expect(
        await eventually('Dracula 2.24.2', () => running(_dracula)),
        '2.24.2',
      );
      await model.checkUpdates();
      expect(model.updates.keys, contains(_dracula));
      await model.update(_dracula);
      expect(model.installedFor(_dracula)?.version, '2.25.1');
      await eventually(
        'Dracula 2.25.1 running',
        () => running(_dracula) == '2.25.1' ? true : null,
      );

      // Uninstalled.
      await model.uninstall(_basedPyright);
      expect(model.installedFor(_basedPyright), isNull);
      await eventually(
        'basedpyright gone',
        () => running(_basedPyright) == null ? true : null,
      );

      // The app quits and starts again on the same data folder.
      await w.close();
      final again = await OpenVsxWorkspace.create(
        extensionIds: const [],
        reopen: w.root,
      );
      final installed = {
        for (final e in await again.extensions.management.getInstalled())
          if (e.kind == InstalledExtensionKind.user) e.key: e,
      };
      expect(
        installed.keys,
        unorderedEquals([_errorLens, _todoTree.toLowerCase(), _dracula]),
      );
      expect(installed[_errorLens]!.enabledInWorkspace, isFalse);
      expect(installed[_errorLens]!.enabledGlobally, isTrue);
      expect(installed[_todoTree.toLowerCase()]!.enabledGlobally, isFalse);
      expect(installed[_dracula]!.version, '2.25.1');
      final runs = {
        for (final e in again.extensions.host!.extensions.value)
          '${(e['identifier'] as Map)['value']}'.toLowerCase(): e['version'],
      };
      expect(runs[_dracula], '2.25.1');
      expect(runs.keys, isNot(contains(_errorLens)));
      expect(runs.keys, isNot(contains(_todoTree.toLowerCase())));
      expect(runs.keys, isNot(contains(_basedPyright)));
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: openVsxSkip(),
  );
}
