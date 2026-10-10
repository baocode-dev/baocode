import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/extensions/window/codicon_label.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/icon_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory folder;
  late IconRegistry registry;
  late List<String> loaded;
  final kept = IconRegistry.instance;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('icons');
    Directory(p.join(folder.path, 'dist')).createSync();
    File(p.join(folder.path, 'dist', 'glicons.woff2')).writeAsBytesSync([1]);
    loaded = [];
    registry = IconRegistry()
      ..loadFont = (family, Uint8List bytes) async => loaded.add(family);
    IconRegistry.instance = registry;
  });
  tearDown(() {
    IconRegistry.instance = kept;
    folder.deleteSync(recursive: true);
  });

  ExtensionIconContribution gitLens(Map<String, Object?> icons) =>
      (extensionId: 'eamodio.gitlens', location: folder.path, icons: icons);

  Map<String, Object?> glyph(String character) => {
    'description': 'An icon.',
    'default': {'fontPath': 'dist/glicons.woff2', 'fontCharacter': character},
  };

  test(
    'extensions\' icons are in their fonts, by their font id; a default '
    'naming another icon is that one; they go with their extension',
    () async {
      var notified = 0;
      registry.addListener(() => notified++);
      registry.setExtensionIcons([
        gitLens({
          'gitlens-graph': glyph(r'\f102'),
          'gitlens-launchpad': glyph('\u{f11a}'),
          'gitlens-unplug': {
            'description': 'Not linked.',
            'default': 'debug-disconnect',
          },
          'gitlens-alias': {
            'description': 'Another.',
            'default': 'gitlens-graph',
          },
        }),
      ]);
      expect(
        registry.lookup('gitlens-graph'),
        const ExtensionGlyph(0xf102, 'eamodio.gitlens/dist/glicons.woff2'),
      );
      expect(
        registry.lookup('gitlens-launchpad'),
        const ExtensionGlyph(0xf11a, 'eamodio.gitlens/dist/glicons.woff2'),
      );
      expect(registry.lookup('gitlens-unplug'), Codicons.debugDisconnect);
      expect(
        registry.lookup('gitlens-alias'),
        registry.lookup('gitlens-graph'),
      );
      expect(registry.lookup('add'), Codicons.add);
      // The font loads once, and its icons repaint when it has.
      await pumpEventQueue();
      expect(loaded, ['eamodio.gitlens/dist/glicons.woff2']);
      expect(notified, 2);

      // The same contributions again change nothing.
      registry.setExtensionIcons([
        gitLens({
          'gitlens-graph': glyph(r'\f102'),
          'gitlens-launchpad': glyph('\u{f11a}'),
          'gitlens-unplug': {
            'description': 'Not linked.',
            'default': 'debug-disconnect',
          },
          'gitlens-alias': {
            'description': 'Another.',
            'default': 'gitlens-graph',
          },
        }),
      ]);
      expect(notified, 2);
      registry.setExtensionIcons(const []);
      expect(registry.contains('gitlens-graph'), isFalse);
      expect(registry.contains('gitlens-alias'), isFalse);
    },
  );

  test('invalid entries are skipped, as upstream rejects them', () async {
    File(p.join(folder.path, 'icons.otf')).writeAsBytesSync([1]);
    registry.setExtensionIcons([
      gitLens({'good-one': glyph('a'), 'bad': glyph('b')}),
      (
        extensionId: 'acme.icons',
        location: folder.path,
        icons: {
          'no-description': {'default': 'add'},
        },
      ),
      (
        extensionId: 'acme.otf',
        location: folder.path,
        icons: {
          'otf-icon': {
            'description': 'Wrong format.',
            'default': {'fontPath': 'icons.otf', 'fontCharacter': 'a'},
          },
        },
      ),
      (
        extensionId: 'acme.outside',
        location: p.join(folder.path, 'dist'),
        icons: {
          'outside-icon': {
            'description': 'Outside its folder.',
            'default': {'fontPath': '../icons.otf', 'fontCharacter': 'a'},
          },
        },
      ),
    ]);
    expect(registry.contains('good-one'), isTrue);
    // An id needs a dash.
    expect(registry.contains('bad'), isFalse);
    expect(registry.contains('no-description'), isFalse);
    expect(registry.contains('otf-icon'), isFalse);
    expect(registry.contains('outside-icon'), isFalse);
  });

  testWidgets('a status bar item and a label show an extension\'s icon in '
      'its font, not its name', (tester) async {
    registry.setExtensionIcons([
      gitLens({'gitlens-graph': glyph(r'\f102')}),
    ]);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            const IdeStatusBar(
              left: [IdeStatusBarItem(r'$(gitlens-graph) Graph')],
              right: [],
            ),
            ExtensionLabel.parse(r'$(gitlens-graph) $(nope-icon) Launchpad')
                .build(fontSize: 12, color: const Color(0xffffffff)),
          ],
        ),
      ),
    );
    expect(find.textContaining('gitlens-graph'), findsNothing);
    final glyphs = tester
        .widgetList<RichText>(find.byType(RichText))
        .where(
          (text) =>
              text.text.style?.fontFamily ==
              'eamodio.gitlens/dist/glicons.woff2',
        );
    expect(glyphs, hasLength(2));
    expect(glyphs.first.text.toPlainText(), '\u{f102}');
    // An unknown one is a generic icon, as in a label upstream.
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Codicons.circleOutline,
      ),
      findsOneWidget,
    );
  });
}
