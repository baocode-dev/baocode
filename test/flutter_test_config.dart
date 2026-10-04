import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_editor/textmate/textmate_worker.dart';
import 'package:baocode/ide/lsp/packs/language_packs.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/platform/context_menu.dart';
import 'package:baocode/platform/shell_command.dart';
import 'package:baocode/theme/workbench_theme.dart';

import 'semantics_tree.dart';

/// Every test runs on the scripted kernels: none starts a real CLI; and
/// fails if its semantics updates would break the desktop engines'
/// accessibility tree. Editors tokenize TextMate grammars in the test's
/// isolate, on its fake clock. Each test reads assets afresh: the bundle
/// caches futures, which answer in the zone of the test that made them.
/// Each test starts in the default color theme, restored as the app
/// restores a kept theme, without reading assets. The `code` command and
/// the context menu are stand-ins, never installed: none looks at the
/// machine's own.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  checkDesktopSemantics();
  KernelRegistry.use(MockKernels.all);
  textMateWorkerLauncher = () async => TextMateInProcessWorker.create();
  MonacoLanguageAssets.defaultPacks = () => LanguagePackRegistry.instance;
  final defaultTheme = await _defaultColorTheme();
  setUp(() {
    rootBundle.clear();
    ShellCommand.debugInstaller = _NoShellCommand();
    ContextMenu.debugInstaller = _NoContextMenu();
    WorkbenchThemeService.instance = WorkbenchThemeService()
      ..restore(
        setting: ThemeSettingDefaults.colorThemeDark,
        data: defaultTheme,
      );
  });
  await testMain();
}

class _NoShellCommand implements ShellCommandInstaller {
  @override
  String get location => '/usr/local/bin/code';

  @override
  Future<ShellCommandStatus> status() async => ShellCommandStatus.notInstalled;

  @override
  Future<void> install({bool overwrite = false}) async {}

  @override
  Future<void> uninstall() async {}
}

class _NoContextMenu implements ContextMenuInstaller {
  @override
  Future<ContextMenuStatus> status() async => ContextMenuStatus.off;

  @override
  Future<void> install(ContextMenuLabels labels) async {}

  @override
  Future<void> uninstall() async {}

  @override
  Future<void> Function()? get openSystemSettings => null;
}

/// The default theme's storage data, read from the assets on disk.
Future<String> _defaultColorTheme() async {
  Future<String> read(String path) async =>
      File('$textMateAssetRoot/$path').readAsStringSync();
  final manifest = await TextMateManifest.load(read);
  final contribution = manifest.themeById(ThemeSettingDefaults.colorThemeDark)!;
  final theme = ColorThemeData.fromExtensionTheme(
    contribution,
    contribution.assetPath,
    extensionId: contribution.extensionId,
  );
  await theme.ensureLoaded(read);
  return theme.toStorage();
}
