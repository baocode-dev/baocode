import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/icons/project_icon_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ProjectIconScanner.rank', () {
    test('finds the logo at the root first', () {
      final best = ProjectIconScanner.rank([
        'assets/logo.png',
        'logo.svg',
        'src/main.dart',
      ]);
      expect(best.map((c) => c.path), ['logo.svg', 'assets/logo.png']);
    });

    test('ranks favicon and appicons after logos', () {
      final best = ProjectIconScanner.rank([
        'favicon.ico',
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png',
        'assets/icon.png',
        'public/logo-256.png',
      ]);
      expect(best.first.path, 'public/logo-256.png');
      expect(best.map((c) => c.path), contains('favicon.ico'));
      expect(
        best.map((c) => c.path),
        contains('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
            'AppIcon-512@2x.png'),
      );
    });

    test('density variants of one name count once, a couple per directory', () {
      final best = ProjectIconScanner.rank([
        // The same icon per density, in a folder each: one.
        'res/mipmap-hdpi/ic_launcher.png',
        'res/mipmap-xhdpi/ic_launcher.png',
        'res/mipmap-xxhdpi/ic_launcher.png',
        'res/mipmap-xxxhdpi/ic_launcher.png',
        // The same icon per size, in one folder: a couple.
        'ios/AppIcon.appiconset/AppIcon-83.5@2x.png',
        'ios/AppIcon.appiconset/AppIcon-1024.png',
        'ios/AppIcon.appiconset/AppIcon-40@2x.png',
      ]);
      expect(best.where((c) => c.path.contains('mipmap')).length, 1);
      expect(
        best.where((c) => c.path.contains('appiconset')).length,
        2,
      );
    });

    test('answers with at most maxCandidates', () {
      final best = ProjectIconScanner.rank([
        for (var i = 0; i < 10; i++) 'dir$i/logo$i.png',
      ]);
      expect(best.length, ProjectIconScanner.maxCandidates);
    });

    test('ignores pictures not named like an icon', () {
      expect(ProjectIconScanner.rank(['photo.png', 'banner.jpg']), isEmpty);
    });

    test('scores shallower deeper than deeper', () {
      final best = ProjectIconScanner.rank([
        'a/b/logo.png',
        'logo.png',
      ]);
      expect(best.first.path, 'logo.png');
    });
  });

  group('ProjectIconScanner.scan', () {
    test('walks a folder, skipping what is not looked into', () async {
      final root = await Directory.systemTemp.createTemp('icons');
      addTearDown(() => root.delete(recursive: true));
      Future<void> put(String relative) => File(
        p.join(root.path, relative),
      ).create(recursive: true);
      await put('logo.png');
      await put('assets/icon.png');
      await put('node_modules/pkg/logo.png');
      await put('src/main.dart');
      await put('docs/logo.png');
      await put('deep/a/b/c/d/logo.png');
      final found = await ProjectIconScanner.scan(root.path);
      final relative = [
        for (final path in found) p.relative(path, from: root.path),
      ];
      expect(relative, ['logo.png', p.join('assets', 'icon.png')]);
    });

    test('answers none for a missing folder', () async {
      expect(
        await ProjectIconScanner.scan('/no/such/folder'),
        isEmpty,
      );
    });
  });
}
