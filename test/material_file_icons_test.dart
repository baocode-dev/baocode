import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/theme/material_file_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final icons = MaterialFileIcons.instance;
  setUpAll(() => icons.load(rootBundle));

  test('files resolve by name, then by their longest extension', () {
    expect(icons.fileIcon('lib/main.dart'), 'dart');
    expect(icons.fileIcon('/p/pubspec.yaml'), 'yaml');
    expect(icons.fileIcon('package.json'), 'nodejs');
    expect(icons.fileIcon('src/app.test.ts'), 'test-ts');
    expect(icons.fileIcon('src/app.ts'), 'typescript');
    expect(icons.fileIcon('README.md'), 'readme');
    expect(icons.fileIcon('notes.md'), 'markdown');
    expect(icons.fileIcon(r'C:\p\Dockerfile'), 'docker');
    // A leading dot is part of the name, not an extension.
    expect(icons.fileIcon('.gitignore'), 'git');
    expect(icons.fileIcon('no_extension'), 'file');
    expect(icons.fileIcon('archive.unknownext'), 'file');
    // Names given with a folder match the end of the path.
    expect(icons.fileIcon('/p/.config/stylelintrc'), 'stylelint');
  });

  test('folders resolve by name, open or closed', () {
    expect(icons.folderIcon('/p/lib'), 'folder-lib');
    expect(icons.folderIcon('/p/lib', expanded: true), 'folder-lib-open');
    expect(icons.folderIcon('/p/test/'), 'folder-test');
    expect(icons.folderIcon('/p/whatever'), 'folder');
    expect(icons.folderIcon('/p/whatever', expanded: true), 'folder-open');
    expect(icons.folderIcon('/p', root: true), 'folder-root');
  });

  test('every mapped icon is bundled and parses as SVG', () async {
    final manifest = jsonDecode(
      File('assets/material_icons/manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final ids = <String>{
      for (final key in [
        'file',
        'folder',
        'folderExpanded',
        'rootFolder',
        'rootFolderExpanded',
      ])
        manifest[key]! as String,
      for (final key in [
        'fileNames',
        'fileExtensions',
        'folderNames',
        'folderNamesExpanded',
      ])
        ...(manifest[key]! as Map<String, Object?>).values.cast<String>(),
    };
    expect(ids.length, greaterThan(1000));
    for (final id in ids) {
      final svg = File('assets/material_icons/icons/$id.svg')
          .readAsStringSync();
      final bytes = await SvgStringLoader(svg).loadBytes(null);
      expect(bytes.lengthInBytes, greaterThan(0), reason: id);
    }
  });

  testWidgets('icons keep their size while loading and show once loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            FileIcon('main.dart', size: 16),
            FolderIcon('lib', size: 16, expanded: true),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(FileIcon)), const Size(16, 16));
    final pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    expect(
      pictures.map(
        (picture) => (picture.bytesLoader as SvgAssetLoader).assetName,
      ),
      [
        'assets/material_icons/icons/dart.svg',
        'assets/material_icons/icons/folder-lib-open.svg',
      ],
    );
  });

  testWidgets('icon loaders can be sent to the isolate decoding the SVG', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FileIcon('main.dart', size: 16),
      ),
    );
    final loader =
        tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
            as SvgAssetLoader;
    // flutter_svg's `compute` closure captures the loader; release builds
    // fail to send one that holds an asset bundle.
    final name = await tester.runAsync(
      () => Isolate.run(() => loader.assetName),
    );
    expect(name, 'assets/material_icons/icons/dart.svg');
  });
}
