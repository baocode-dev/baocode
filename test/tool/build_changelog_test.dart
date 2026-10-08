import 'dart:io';

import 'package:baocode/update/version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_changelog.dart';
import '../../tool/draft_release_notes.dart';

void main() {
  group('build_changelog', () {
    test('the pages in site/ are what release-notes/ makes', () {
      final pages = changelogPages(readReleaseNotes(Directory.current));
      for (final MapEntry(key: path, value: html) in pages.entries) {
        expect(
          File(path).readAsStringSync(),
          html,
          reason: '$path: run dart run tool/build_changelog.dart',
        );
      }
    });

    test('newest first, each at #v<version>, English where none', () {
      final pages = changelogPages({
        AppVersion.parse('1.2.0'): {'en': '- Two', 'zh': '- 二'},
        AppVersion.parse('1.10.0'): {'en': 'New\n- Ten'},
      });
      final en = pages['site/changelog.html']!;
      final zh = pages['site/zh/changelog.html']!;
      expect(en.indexOf('id="v1.10.0"'), lessThan(en.indexOf('id="v1.2.0"')));
      expect(en, contains('<li>Two</li>'));
      expect(en, contains('<p>New</p>'));
      expect(zh, contains('<li>二</li>'));
      expect(zh, contains('<li>Ten</li>'));
      expect(zh, contains('<html lang="zh-CN">'));
    });
  });

  group('draft_release_notes', () {
    test(
      'feat, perf and fix under their headings; not the site, CI or docs',
      () {
        final sections = draftSections([
          'feat(chat): Pin a message',
          'fix: Keep the scroll position',
          'perf(ide): Open large files faster',
          'feat(site): A new page',
          'fix(ci): Retry the upload',
          'docs: How to release',
          'Merge branch main',
        ]);
        expect(
          draftText(sections, {
            NoteSection.added: 'New',
            NoteSection.improved: 'Improved',
            NoteSection.fixed: 'Fixed',
          }),
          'New\n- Pin a message\n\n'
          'Improved\n- Open large files faster\n\n'
          'Fixed\n- Keep the scroll position\n',
        );
      },
    );
  });
}
