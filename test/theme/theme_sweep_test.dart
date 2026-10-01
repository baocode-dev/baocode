import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart'
    show textMateWorkerLauncher;
import 'package:baocode/ide/ide_modern_ui.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/ide/terminal/terminal_colors.dart';
import 'package:baocode/main.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/workspace.dart';

import '../ide/workbench/fake_files.dart';

/// The bundled themes, read from the assets on disk.
Future<List<ColorThemeData>> _themes() async {
  Future<String> read(String path) async =>
      File('$textMateAssetRoot/$path').readAsStringSync();
  final manifest = await TextMateManifest.load(read);
  return [
    for (final contribution in manifest.themes)
      await (() async {
        final theme = ColorThemeData.fromExtensionTheme(
          contribution,
          contribution.assetPath,
          extensionId: contribution.extensionId,
        );
        await theme.ensureLoaded(read);
        return theme;
      })(),
  ];
}

/// Where to write what each theme paints, to look at (e.g.
/// `BAOCODE_THEME_SNAPSHOTS=/tmp/themes flutter test test/theme/`).
final _snapshots = Platform.environment['BAOCODE_THEME_SNAPSHOTS'];

Future<void> _snapshot(WidgetTester tester, String name) async {
  final directory = _snapshots;
  if (directory == null) return;
  final element = tester.binding.rootElement!;
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  late List<ColorThemeData> themes;
  setUpAll(() async => themes = await _themes());

  // Every theme sets or leaves out different colors (high contrast ones
  // add borders): the workbench and the chat paint with each.
  testWidgets('every bundled theme paints the workbench and the chat', (
    tester,
  ) async {
    expect(themes, hasLength(17));
    // Monarch highlights: a TextMate worker would outlive each editor here.
    final launcher = textMateWorkerLauncher;
    textMateWorkerLauncher = () async => null;
    addTearDown(() => textMateWorkerLauncher = launcher);
    final terminal = terminalColorTheme.value;
    addTearDown(() => terminalColorTheme.value = terminal);
    for (final theme in themes) {
      final service = WorkbenchThemeService.instance
        ..restore(setting: theme.settingsId, data: theme.toStorage());
      expect(service.colorThemeId, theme.settingsId);
      final name = theme.settingsId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      // As BaoCodeApp does, which the workbench here is outside of.
      terminalColorTheme.value = TerminalColorTheme.resolve(
        service.colors.get,
        type: service.colors.type,
      );

      await pumpWorkbench(
        tester,
        {
          'lib/main.dart': 'void main() {\n  print(1);\n}\n',
          'README.md': '# Title\n',
        },
        open: ['lib/main.dart'],
        nativeEditor: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: theme.settingsId);
      // The panel on TERMINAL, with two tabs: panelPart.ts paints it with
      // `panel.background`, never the shell's.
      await chord(tester, LogicalKeyboardKey.backquote, control: true);
      await chord(
        tester,
        LogicalKeyboardKey.backquote,
        control: true,
        shift: true,
      );
      expect(tester.takeException(), isNull, reason: theme.settingsId);
      final panel = tester.widget<IdeCard>(
        find.ancestor(
          of: find.byType(IdeBottomPanel),
          matching: find.byType(IdeCard),
        ),
      );
      expect(
        panel.color,
        service.colors['panel.background'],
        reason: theme.settingsId,
      );
      await chord(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
      expect(tester.takeException(), isNull, reason: theme.settingsId);
      await _snapshot(tester, 'ide_$name');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: theme.settingsId);
      await _snapshot(tester, 'chat_$name');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });
}
