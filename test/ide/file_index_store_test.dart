import 'dart:async';
import 'dart:io';

import 'package:baocode/ide/file_index_store.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_quick_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileIndexEntry _entry(String relative, [int folder = 0]) =>
    (relative: relative, folder: folder, absolute: null);

/// [index]'s best for [filter], waited for when found off the UI isolate.
Future<List<IdeFileHit>> _bestFor(
  IdeFileIndex index,
  String filter, {
  int limit = 20,
}) async {
  if (index.bestFor(filter, limit: limit) case final best?) return best;
  final found = Completer<void>();
  void done() => found.isCompleted ? null : found.complete();
  index.addListener(done);
  await found.future;
  index.removeListener(done);
  return index.bestFor(filter, limit: limit)!;
}

void main() {
  group('FileIndexStore', () {
    test('keeps the paths sorted and gives the first for no filter', () {
      final store = FileIndexStore([
        _entry('src/b.dart'),
        _entry('README.md'),
        _entry('src/a.dart'),
      ]);
      expect(store.length, 3);
      expect(store.find('', 2).map((e) => e.relative), [
        'README.md',
        'src/a.dart',
      ]);
    });

    test('finds the best first, the name over the folder, any case', () {
      final store = FileIndexStore([
        _entry('bms/src/api/contract.js'),
        _entry('bms/src/pages/customer/contractList.vue'),
        _entry('douyin/work/apk/assets/common_feed_interact.json'),
        _entry('mt_project/model/contract.php'),
        _entry('mt_project/customer/Contract.php'),
        _entry('mt_project/contract/readme.md'),
      ]);
      final found = store.find('contract', 10).map((e) => e.relative);
      expect(found.take(2), [
        'bms/src/api/contract.js',
        'mt_project/model/contract.php',
      ]);
      expect(
        found,
        containsAll([
          'mt_project/customer/Contract.php',
          'bms/src/pages/customer/contractList.vue',
          'mt_project/contract/readme.md',
        ]),
      );
      expect(store.find('CONTRACT.PHP', 10).first.relative, isNotNull);
      // At most as many as asked, the best of them.
      expect(store.find('contract', 1).single.relative, found.first);
    });

    test('a filter typed on matches as one typed at once', () {
      final paths = [
        for (var i = 0; i < 300; i++) 'pkg$i/lib/file_$i.dart',
        'lib/phone.dart',
        'lib/phonebook.dart',
      ];
      final narrowed = FileIndexStore([for (final p in paths) _entry(p)]);
      final fresh = FileIndexStore([for (final p in paths) _entry(p)]);
      for (final filter in ['p', 'ph', 'pho', 'phone']) {
        narrowed.find(filter, 50);
      }
      expect(
        narrowed.find('phoneb', 50).map((e) => e.relative),
        fresh.find('phoneb', 50).map((e) => e.relative),
      );
      // Taken back: all the paths again.
      expect(
        narrowed.find('file_29', 5).first.relative,
        'pkg29/lib/file_29.dart',
      );
    });

    test('keeps paths other than ASCII, and finds them', () {
      final store = FileIndexStore([
        _entry('文档/合同.php'),
        _entry('docs/résumé.md'),
        _entry('a.txt'),
      ]);
      expect(store.find('合同', 5).single.relative, '文档/合同.php');
      expect(store.find('résumé', 5).single.relative, 'docs/résumé.md');
      expect(store.find('rsm', 5).single.relative, 'docs/résumé.md');
      expect(store.entries.map((e) => e.relative), [
        'a.txt',
        'docs/résumé.md',
        '文档/合同.php',
      ]);
    });

    test('finds folders by their names', () {
      final store = FileIndexStore([
        _entry('app/pages/order/list.vue', 1),
        _entry('app/pages/order/confirm.vue', 1),
        _entry('lib/order.dart'),
      ]);
      final found = store.findFolders('order', 5, 1000);
      expect(found.map((f) => (f.entry.relative, f.entry.folder)), [
        ('app/pages/order', 1),
      ]);
    });
  });

  group('IdeFileIndex', () {
    test('a large listing is matched off the UI isolate, every file of it '
        'found however many come before (#771)', () async {
      final paths = [
        for (var i = 0; i < 60000; i++) '/p/douyin/work/apk/assets/res_$i.json',
        '/p/bms/src/api/contract.js',
        '/p/mt_project/model/contract.php',
      ];
      final index = IdeFileIndex(
        IdeFileService('/p'),
        '/p',
        pathContext: p.posix,
        lister: (_, _) async => IdeFileListing(paths),
      );
      addTearDown(index.dispose);
      await index.refresh();
      expect(index.count, paths.length);
      expect(index.truncated, isFalse);

      final found = await _bestFor(index, 'contract');
      expect(found, [
        (
          path: '/p/bms/src/api/contract.js',
          relative: 'bms/src/api/contract.js',
        ),
        (
          path: '/p/mt_project/model/contract.php',
          relative: 'mt_project/model/contract.php',
        ),
      ]);
      expect(
        (await index.find('model/contract', limit: 5)).single.path,
        '/p/mt_project/model/contract.php',
      );
      expect(
        (await index.findFolders(
          'model',
          limit: 5,
          minScore: 1000,
        )).map((f) => f.folder),
        [(path: '/p/mt_project/model', relative: 'mt_project/model')],
      );
      // The first files listed for no filter, at once.
      expect(
        index.bestFor('', limit: 1)!.single.relative,
        'bms/src/api/contract.js',
      );
    });

    test('says when a listing was cut short', () async {
      final index = IdeFileIndex(
        IdeFileService('/p'),
        '/p',
        pathContext: p.posix,
        lister: (_, _) async =>
            IdeFileListing(['/p/a.dart', '/p/b.dart'], truncated: true),
      );
      addTearDown(index.dispose);
      await index.refresh();
      final picks = fileQuickPicks(
        'a.',
        index: index,
        recent: const [],
        onOpen: (_, _, _) {},
      );
      expect(picks.map((pick) => pick.label), [
        'a.dart',
        'Only the first 2 files are searched: this project has more',
      ]);
    });

    test('a local project is listed off the UI isolate, kept there when '
        'large, here when not', () async {
      final dir = await Directory.systemTemp.createTemp('baocode-file-index-');
      addTearDown(() => dir.delete(recursive: true));
      final root = dir.path;
      Future<void> write(String relative) async {
        final file = File(p.joinAll([root, ...relative.split('/')]));
        await file.parent.create(recursive: true);
        await file.writeAsString('');
      }

      await write('bms/src/api/contract.js');
      await write('mt_project/model/contract.php');
      final small = IdeFileIndex(IdeFileService(root), root);
      addTearDown(small.dispose);
      await small.refresh();
      // Matched here: at once.
      expect(small.bestFor('contract.php', limit: 5)!.single, (
        path: p.join(root, 'mt_project', 'model', 'contract.php'),
        relative: 'mt_project/model/contract.php',
      ));

      final assets = Directory(p.join(root, 'douyin', 'assets'));
      await assets.create(recursive: true);
      await Future.wait([
        for (var i = 0; i <= IdeFileIndex.backgroundAbove; i++)
          File(p.join(assets.path, 'res_$i.json')).writeAsString(''),
      ]);
      final large = IdeFileIndex(IdeFileService(root), root);
      addTearDown(large.dispose);
      await large.refresh();
      expect(large.count, IdeFileIndex.backgroundAbove + 3);
      // Found there: once found.
      expect(large.bestFor('contract.php', limit: 5), isNull);
      expect(large.searching, isTrue);
      expect((await _bestFor(large, 'contract.php', limit: 5)).single, (
        path: p.join(root, 'mt_project', 'model', 'contract.php'),
        relative: 'mt_project/model/contract.php',
      ));
    });
  });
}
