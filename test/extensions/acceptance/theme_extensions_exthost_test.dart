// 九.2: a color theme (Dracula) and a file icon theme (vscode-icons) from
// Open VSX, installed in a fresh data folder: listed with the bundled
// ones, applied from their files (the theme's colors and token rules, the
// icon theme's icons for the project's files), and listed again by a
// restarted app before any extension host runs.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/theme/file_icon_theme.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';
import 'open_vsx_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '九.2: a color theme and a file icon theme from Open VSX',
    () async {
      final colors = WorkbenchThemeService.instance;
      final icons = FileIconThemeService.instance;
      WorkbenchThemeService.instance = WorkbenchThemeService();
      FileIconThemeService.instance = FileIconThemeService();
      addTearDown(() {
        WorkbenchThemeService.instance = colors;
        FileIconThemeService.instance = icons;
      });
      final themes = WorkbenchThemeService.instance;
      await themes.initialize();
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [
          'dracula-theme.theme-dracula',
          'vscode-icons-team.vscode-icons',
        ],
        files: {
          'main.py': 'print(1)\n',
          'package.json': '{}\n',
          'src/app.ts': 'export {};\n',
        },
      );
      // As the app does with settings.json.
      w.app.followIconThemeSetting();
      // The color theme: listed, then applied from its file.
      final listed = await eventually('Dracula listed', () {
        final ids = [for (final t in themes.colorThemes) t.id];
        return ids.contains('Dracula Theme') ? ids : null;
      });
      expect(listed, contains('Dark Modern'));
      await themes.setColorTheme('Dracula Theme');
      expect(themes.colorThemeId, 'Dracula Theme');
      final theme = themes.colorTheme;
      expect(theme.isLoaded, isTrue);
      expect(theme.colors['editor.background']?.toLowerCase(), '#282a36');
      expect(
        jsonEncode(theme.themeTokenColors),
        contains('comment'),
        reason: 'its TextMate rules',
      );

      // The icon theme: the project's files get its icons.
      final iconThemes = FileIconThemeService.instance;
      await eventually('vscode-icons listed', () {
        return iconThemes.themes.any((t) => t.id == 'vscode-icons')
            ? true
            : null;
      });
      // Its welcome, which its activation waits on (as upstream's does):
      // its Activate sets it as the icon theme.
      await w.answer('vscode-icons', 'Activate');
      await w.activated('vscode-icons-team.vscode-icons');
      final active = await eventually('vscode-icons in use', () {
        return iconThemes.setting == 'vscode-icons' ? iconThemes.active : null;
      });
      expect(w.app.userSettings.values['workbench.iconTheme'], 'vscode-icons');
      // As the file tree's icons ask: with the file's language (its
      // Python and TypeScript icons are by language).
      final languageOf = iconThemes.languageIdOf!;
      String iconOf(String file) => active
          .fileIcon(w.path(file), languageId: languageOf(w.path(file)))!
          .iconPath!;
      // From the installed extension's folder.
      final installed = p.join(w.root, 'data', 'extensions');
      for (final file in ['main.py', 'package.json', 'src/app.ts']) {
        final icon = iconOf(file);
        expect(
          p.split(p.relative(icon, from: installed)).first,
          startsWith('vscode-icons-team.vscode-icons-'),
          reason: file,
        );
        expect(File(icon).existsSync(), isTrue, reason: file);
      }
      expect(p.basename(iconOf('main.py')), contains('python'));
      expect(p.basename(iconOf('package.json')), contains('npm'));
      expect(p.basename(iconOf('src/app.ts')), contains('typescript'));
      final folder = active.folderIcon(w.path('src'))!.iconPath!;
      expect(p.basename(folder), contains('src'));
      expect(w.unsupported, isEmpty, reason: w.report());

      // A second app on the same data folder and settings, as after a
      // restart: the installed themes are listed, and vscode-icons used,
      // before any extension host runs.
      WorkbenchThemeService.instance = WorkbenchThemeService();
      FileIconThemeService.instance = FileIconThemeService();
      await WorkbenchThemeService.instance.initialize();
      final restarted = ExtensionsApp(
        userSettings: AcceptanceSettings({...w.app.userSettings.values}),
        dataDirectory: p.join(w.root, 'data'),
        loadRuntime: () => ExtHostRuntime.load(exthostRuntimeDir()!),
        coreConfiguration: () async => CoreConfiguration.fromJson(
          (jsonDecode(
            File('assets/exthost/core_configuration.json').readAsStringSync(),
          ) as Map).cast(),
          platform: CoreConfiguration.currentPlatform,
        ),
        gallery: OpenVsxClient(cacheDir: openVsxCacheDir()),
      );
      addTearDown(restarted.dispose);
      // In main()'s order.
      final applied = restarted.applyInstalledThemes();
      restarted.followIconThemeSetting();
      await applied;
      expect(
        [for (final t in WorkbenchThemeService.instance.colorThemes) t.id],
        contains('Dracula Theme'),
      );
      expect(
        [for (final t in FileIconThemeService.instance.themes) t.id],
        contains('vscode-icons'),
      );
      await eventually('vscode-icons in use again', () {
        final icons = FileIconThemeService.instance;
        return icons.active?.fileIcon(w.path('package.json'))?.iconPath;
      });
      expect(w.extensions.host!.manager.state, ExtensionHostState.running);
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: openVsxSkip(),
  );
}
