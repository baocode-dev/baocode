// The menu widget: an `editor/title` contribution shown as icon buttons
// and an overflow menu, in the app's own menu widgets.
//
// BAOCODE_EXTHOST_SCREENS=<dir> writes the toolbar and its overflow menu to
// <dir>/menus.png (build/exthost-screens/ by convention).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/menus/menu_service.dart';
import 'package:baocode/extensions/menus/menu_widgets.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// An extension whose `editor/title` menu has both a `navigation` group and
/// others, as a formatter does.
final _description = <String, Object?>{
  'identifier': {'value': 'pub.tools'},
  'name': 'tools',
  'displayName': 'Tools',
  'extensionLocation': VsUri.file('/ext/pub.tools').toJson(),
  'contributes': {
    'commands': [
      {'command': 'tools.openPreview', 'title': 'Open Preview', 'icon': r'$(open-preview)'},
      {'command': 'tools.openPreviewToSide', 'title': 'Open Preview to the Side', 'icon': r'$(open-preview)'},
      {'command': 'tools.export', 'title': 'Export…'},
      {'command': 'tools.rename', 'title': 'Rename…'},
    ],
    'menus': {
      'editor/title': [
        {'command': 'tools.openPreview', 'group': 'navigation@1'},
        {'command': 'tools.openPreviewToSide', 'group': 'navigation@2'},
        {'command': 'tools.export', 'group': '1_modification@1'},
        {'command': 'tools.rename', 'group': '1_modification@2'},
      ],
    },
  },
};

void main() {
  testWidgets('renders an editor/title menu as buttons + overflow', (
    tester,
  ) async {
    final registry = ExtensionCommandRegistry()
      ..setExtensions([_description]);
    final menus = MenuService(registry);
    addTearDown(() {
      menus.dispose();
      registry.dispose();
    });
    final context = ContextKeyService().createOverlay({'resourceExtname': '.html'});
    final groups = menus.menuItems('editor/title', context);
    expect(groups.first.id, 'navigation');
    expect(groups.first.actions, hasLength(2));
    expect(groups[1].actions, hasLength(2));

    final screens = Platform.environment['BAOCODE_EXTHOST_SCREENS'];
    if (screens != null) {
      await tester.runAsync(() async {
        for (final (family, path) in [
          ('Snapshot', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
          (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
        ]) {
          if (!File(path).existsSync()) continue;
          await (FontLoader(family)
                ..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
              .load();
        }
      });
    }

    final key = GlobalKey();
    tester.view.physicalSize = const Size(560, 260);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // The panes' own styles name no family, so the app's theme does
          // (as [buildAppTheme] does not either: the window's text font
          // comes from the platform).
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: screens == null ? null : 'Snapshot',
          ),
          home: Material(
            color: themeColors['editorGroupHeader.tabsBackground'],
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IdeMenuActions(groups: groups),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Codicons.byName['open-preview']!), findsNWidgets(2));
    expect(find.byIcon(Codicons.more), findsOneWidget);

    // The overflow menu opens with the non-navigation groups.
    final button = find.byIcon(Codicons.more);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Rename…'), findsOneWidget);

    if (screens == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(screens, 'menus.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}
