// An agent and a project deleted from the sidebar, the note with Undo at
// the bottom, rendered offscreen with real fonts. Written to $SHOTS (a
// folder); skipped without it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/main.dart';
import 'package:baocode/settings/app_locale.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sidebar_test.dart' show inSidebar, pickFromMenu;

final _out = Platform.environment['SHOTS'];

Future<void> _fonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    Future<void> load(List<String> families, String path) async {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      for (final family in families) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    }

    await load([
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      '.AppleSystemUIFont',
      'FlutterTest',
      'Ahem',
    ], '/System/Library/Fonts/Hiragino Sans GB.ttc');
    await load(['Menlo'], '/System/Library/Fonts/Menlo.ttc');
    await load(
      ['MaterialIcons'],
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    final codicon = FontLoader('codicon')
      ..addFont(rootBundle.load('assets/codicons/codicon.ttf'));
    await codicon.load();
  });
}

Future<void> _shoot(WidgetTester tester, String name) async {
  // The note's way in.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final view = tester.binding.renderViews.first;
  await tester.runAsync(() async {
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: 2,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('deleted from the sidebar, Undo at the bottom', (tester) async {
    await _fonts(tester);
    CodeFont.families.value = ['Menlo', 'Roboto'];
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = Workspace.mock();
    await tester.pumpWidget(
      BaoCodeApp(
        workspace: workspace,
        appLocale: AppLocale(storage: MemoryLocaleStorage('zh-cn')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      inSidebar(find.textContaining('Rate limit per API key')),
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'desktop-delete-agent');
    await tester.pump(Workspace.deleteDelay);
    await tester.pump(const Duration(milliseconds: 300));

    await pickFromMenu(tester, 'baocode', '从列表移除');
    await _shoot(tester, 'desktop-remove-project');
    await tester.pump(Workspace.deleteDelay);
    await tester.pump(const Duration(milliseconds: 300));
  }, skip: _out == null);
}
