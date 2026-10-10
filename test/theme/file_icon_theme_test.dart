// File icon themes of extensions (`contributes.iconThemes`, goal 九.2: an
// icon theme from Open VSX): how a file or folder finds its icon, and the
// explorer's icons drawn from the theme in use.

import 'dart:convert';
import 'dart:io';

import 'package:baocode/theme/file_icon_theme.dart';
import 'package:baocode/theme/material_file_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory extension;

  setUp(() {
    extension = Directory.systemTemp.createTempSync('icon-theme');
    Directory(p.join(extension.path, 'icons')).createSync();
    for (final name in [
      'file',
      'folder',
      'open',
      'ts',
      'test',
      'json',
      'pkg',
      'src',
      'py',
      'root',
      'light-ts',
    ]) {
      File(p.join(extension.path, 'icons', '$name.svg')).writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
        '<rect width="16" height="16"/></svg>',
      );
    }
    File(p.join(extension.path, 'theme.json')).writeAsStringSync(
      jsonEncode({
        'iconDefinitions': {
          for (final name in [
            'file',
            'folder',
            'open',
            'ts',
            'test',
            'json',
            'pkg',
            'src',
            'py',
            'root',
            'light-ts',
          ])
            '_$name': {'iconPath': './icons/$name.svg'},
        },
        'file': '_file',
        'folder': '_folder',
        'folderExpanded': '_open',
        'rootFolder': '_root',
        'fileExtensions': {'ts': '_ts', 'test.ts': '_test'},
        'fileNames': {'package.json': '_pkg', '.vscode/settings.json': '_json'},
        'folderNames': {'src': '_src'},
        'languageIds': {'python': '_py'},
        'light': {
          'fileExtensions': {'ts': '_light-ts'},
        },
      }),
    );
  });

  tearDown(() => extension.deleteSync(recursive: true));

  String icon(FileIconDefinition? definition) =>
      p.basenameWithoutExtension(definition!.iconPath!);

  test('a file by its name, its longest extension, its language, then any '
      'file\'s; a folder by its name', () async {
    final theme = await FileIconThemeData.load(
      'acme-icons',
      p.join(extension.path, 'theme.json'),
    );
    expect(icon(theme.fileIcon('/w/package.json')), 'pkg');
    expect(icon(theme.fileIcon('/w/.vscode/settings.json')), 'json');
    expect(icon(theme.fileIcon('/w/a.test.ts')), 'test');
    expect(icon(theme.fileIcon('/w/a.ts')), 'ts');
    expect(icon(theme.fileIcon('/w/a.ts', light: true)), 'light-ts');
    expect(icon(theme.fileIcon('/w/run', languageId: 'python')), 'py');
    expect(icon(theme.fileIcon('/w/README')), 'file');
    expect(icon(theme.folderIcon('/w/src')), 'src');
    expect(icon(theme.folderIcon('/w/lib')), 'folder');
    expect(icon(theme.folderIcon('/w/lib', expanded: true)), 'open');
    expect(icon(theme.folderIcon('/w', root: true)), 'root');
  });

  test('an expanded folder without an icon of its own has the collapsed '
      'one, as upstream (the JetBrains theme)', () async {
    final path = p.join(extension.path, 'folders.json');
    File(path).writeAsStringSync(
      jsonEncode({
        'iconDefinitions': {
          '_folder': {'iconPath': './icons/folder.svg'},
          '_root': {'iconPath': './icons/root.svg'},
          '_open': {'iconPath': './icons/open.svg'},
        },
        'folder': '_folder',
        'light': {'rootFolder': '_root'},
      }),
    );
    final theme = await FileIconThemeData.load('folders', path);
    expect(icon(theme.folderIcon('/w/lib', expanded: true)), 'folder');
    expect(icon(theme.folderIcon('/w', root: true, expanded: true)), 'folder');
    // `rootFolder || folder` in each section, the light one's first.
    expect(
      icon(theme.folderIcon('/w', root: true, expanded: true, light: true)),
      'root',
    );
    expect(icon(theme.folderIcon('/w/lib', light: true)), 'folder');
  });

  testWidgets('the theme in use draws the explorer\'s icons; the bundled '
      'one again without', (tester) async {
    final service = FileIconThemeService.instance = FileIconThemeService();
    await tester.runAsync(() async {
      await service.setExtensionThemes([
        (
          extensionId: 'acme.icons',
          location: extension.path,
          theme: {'id': 'acme-icons', 'label': 'Acme', 'path': './theme.json'},
        ),
      ]);
      await service.select('acme-icons');
    });
    expect(service.active?.id, 'acme-icons');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [FileIcon('/w/a.ts'), FolderIcon('/w/src')]),
      ),
    );
    expect(find.byType(FileIconThemeIcon), findsNWidgets(2));
    expect(find.byType(SvgPicture), findsNWidgets(2));

    await tester.runAsync(() => service.select(null));
    await tester.pump();
    expect(find.byType(FileIconThemeIcon), findsNothing);
  });
}
