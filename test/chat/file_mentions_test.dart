import 'package:baocode/chat/composer/composer_mock_data.dart';
import 'package:baocode/chat/composer/file_mentions.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_quick_open.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../ide/workbench/fake_files.dart';

void main() {
  final paths = p.Context(style: p.Style.posix);
  const workspace = '/ws';
  const app = '/code/app';
  const lib = '/code/lib';

  final files = TreeFiles({
    '$app/pages/order/fridge-confirm.vue': '',
    '$app/pages/order/list.vue': '',
    '$lib/src/fridge.dart': '',
    '/home/me/notes/todo.md': '',
    '/home/me/notes/.hidden': '',
    '/home/me/Notebook.txt': '',
  });

  FileMentions mentions({List<String>? roots, String root = app}) {
    final index = IdeFileIndex(
      files,
      root,
      roots: roots,
      pathContext: paths,
      lister: (files, folder) async => IdeFileListing(
        [
          for (final path in (files as TreeFiles).contents.keys)
            if (paths.isWithin(folder, path)) path,
        ]..sort(),
      ),
    );
    addTearDown(index.dispose);
    return FileMentions(
      files: files,
      paths: paths,
      index: index,
      home: '/home/me',
    );
  }

  test('finds a workspace folder\'s files the kernel does not see', () async {
    final found = await mentions(roots: [app, lib])
        .suggest('fridge-confirm', root: workspace, kernel: (_) async => []);
    expect(found.first.label, 'fridge-confirm.vue');
    expect(found.first.detail, 'app/pages/order');
    // Outside the conversation's directory: by its absolute path.
    expect(found.first.value, '$app/pages/order/fridge-confirm.vue');
  });

  test('an @ alone offers a workspace\'s folders', () async {
    final found = await mentions(roots: [app, lib])
        .suggest('', root: workspace);
    expect(found.map((s) => (s.kind, s.label, s.value)), [
      (SuggestionKind.folder, 'app', app),
      (SuggestionKind.folder, 'lib', lib),
    ]);
  });

  test('refers to a file in the conversation\'s directory from it', () async {
    final mention = mentions();
    await mention.index.refresh();
    final found = await mention.suggest(
      'list.vue',
      root: app,
      kernel: (_) async => [const FileSuggestion('pages/')],
    );
    expect(found.map((s) => s.value), ['pages/order/list.vue', 'pages']);
    expect(found.last.kind, SuggestionKind.folder);
  });

  test('keeps the kernel\'s files not listed, once', () async {
    final mention = mentions();
    await mention.index.refresh();
    final found = await mention.suggest(
      'fridge',
      root: app,
      kernel: (_) async => [
        const FileSuggestion('pages/order/fridge-confirm.vue'),
        const FileSuggestion('build/fridge.js'),
      ],
    );
    expect(found.map((s) => s.value), [
      'pages/order/fridge-confirm.vue',
      'build/fridge.js',
    ]);
  });

  test('while first listed, the kernel\'s alone', () async {
    final found = await mentions().suggest(
      'fridge',
      root: app,
      kernel: (_) async => [const FileSuggestion('build/fridge.js')],
    );
    expect(found.map((s) => s.value), ['build/fridge.js']);
  });

  test('a kernel that fails still leaves the listing\'s', () async {
    final found = await mentions().suggest(
      'confirm',
      root: app,
      kernel: (_) async => throw StateError('compacting'),
    );
    expect(found.single.label, 'fridge-confirm.vue');
  });

  test('completes a path from a root, anywhere', () async {
    final found = await mentions().suggest('/home/me/no', root: app);
    expect(found.map((s) => s.label), ['notes', 'Notebook.txt']);
    expect(found.first.kind, SuggestionKind.folder);
    expect(found.first.value, '/home/me/notes');
    expect(found.first.detail, '/home/me');
  });

  test('completes from the home folder, hidden files when asked', () async {
    final mention = mentions();
    expect((await mention.suggest('~/notes/', root: app)).map((s) => s.value), [
      '/home/me/notes/todo.md',
    ]);
    expect(
      (await mention.suggest('~/notes/.h', root: app)).map((s) => s.value),
      ['/home/me/notes/.hidden'],
    );
  });
}
