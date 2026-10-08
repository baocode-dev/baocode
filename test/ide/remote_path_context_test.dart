import 'dart:async';

import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_quick_open.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'workbench/fake_files.dart' show ReadWriteOnlyFiles;

class _HostFiles with ReadWriteOnlyFiles implements IdeFileService {
  _HostFiles(this.paths, this.contents);

  final p.Context paths;
  final Map<String, String> contents;
  final List<String> listed = [];
  final List<String> readPaths = [];
  final List<String> created = [];
  final List<String> written = [];

  @override
  Future<List<IdeFile>> list(String directory) async {
    listed.add(directory);
    final entries = <String, IdeFile>{};
    for (final path in contents.keys) {
      if (!paths.isWithin(directory, path)) continue;
      final name = paths.split(paths.relative(path, from: directory)).first;
      final child = paths.join(directory, name);
      entries[child] = IdeFile(child, name, isDirectory: child != path);
    }
    return entries.values.toList();
  }

  @override
  Future<String> read(String path, {bool force = false}) async {
    readPaths.add(path);
    return contents[path] ?? (throw IdeFileNotFoundException(path));
  }

  @override
  Future<void> create(String path, {bool directory = false}) async {
    created.add(path);
    if (contents.containsKey(path)) throw IdeFileExistsException(path);
    contents[path] = '';
  }

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    written.add(path);
    if (expectedText != null && contents[path] != expectedText) {
      throw IdeFileConflictException(path);
    }
    contents[path] = text;
  }
}

void main() {
  const root = '/media/drive/workspace/hjh';
  const first = '$root/lib/a.dart';
  const second = '$root/lib/b.dart';

  test('remote explorer lists, watches and reveals POSIX paths', () async {
    final files = _HostFiles(p.posix, {first: 'a', second: 'b'});
    final watched = <String>[];
    final explorer = IdeExplorerController(
      root: root,
      files: files,
      paths: p.posix,
      watch: (directory) {
        watched.add(directory);
        return const Stream.empty();
      },
    );
    addTearDown(explorer.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(files.listed, [root]);
    expect(watched, [root]);
    expect(explorer.rows.single.path, '$root/lib');

    await explorer.reveal(first);
    expect(files.listed, contains('$root/lib'));
    expect(watched, contains('$root/lib'));
    expect(explorer.selected, first);
    expect(explorer.rows.map((row) => row.path), contains(first));
  });

  test('workspace file operations keep remote POSIX paths', () async {
    final files = _HostFiles(p.posix, {first: 'a', second: 'b'});
    final watched = <String>[];
    final workspace = IdeWorkspace(
      root,
      files: files,
      paths: p.posix,
      watch: (directory) {
        watched.add(directory);
        return const Stream.empty();
      },
    );
    addTearDown(workspace.dispose);

    await workspace.open('lib/a.dart');
    expect(files.readPaths, [first]);
    expect(watched, ['$root/lib']);
    expect(workspace.active!.path, first);

    const range = LspRange(LspPosition(0, 0), LspPosition(0, 1));
    await workspace.openAt(first, range);
    expect(workspace.takeReveal(), range);
    await workspace.restore(['lib/b.dart']);
    expect(files.readPaths, [first, second]);
    expect(workspace.relativePath(first), 'lib/a.dart');

    await workspace.openDiff(
      first,
      label: 'Working Tree',
      original: () async => 'old',
    );
    await workspace.openRevision(first, label: 'HEAD', read: () async => 'old');
    expect(
      workspace.documents.every((doc) => doc.path.startsWith('$root/')),
      isTrue,
    );

    workspace.moved('$root/lib', '$root/src');
    expect(workspace.documentsIn('$root/src'), hasLength(4));
    expect(workspace.documentsIn('$root/lib'), isEmpty);
    expect(watched, contains('$root/src'));

    final saved = await workspace.saveTo(
      workspace.newUntitled(),
      'src/new.dart',
    );
    expect(saved!.path, '$root/src/new.dart');
    expect(files.created, ['$root/src/new.dart']);
    expect(files.written, ['$root/src/new.dart']);
  });

  test('path context is honored independently of the client OS', () async {
    const winRoot = r'C:\remote\project';
    const winFile = r'C:\remote\project\src\main.dart';
    final files = _HostFiles(p.windows, {winFile: 'main'});
    final explorer = IdeExplorerController(
      root: winRoot,
      files: files,
      paths: p.windows,
      watch: (_) => const Stream.empty(),
    );
    addTearDown(explorer.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(explorer.rows.single.path, r'C:\remote\project\src');
    await explorer.reveal(winFile);
    expect(explorer.selected, winFile);

    final workspace = IdeWorkspace(winRoot, files: files, paths: p.windows);
    addTearDown(workspace.dispose);
    await workspace.open(r'src\main.dart');
    expect(workspace.active!.path, winFile);
    expect(workspace.relativePath(winFile), 'src/main.dart');
    final editors = editorQuickPicks(
      '',
      editors: workspace.documents,
      root: winRoot,
      paths: p.windows,
      onOpen: (_, {required inBackground}) {},
    );
    expect(editors.single.description, 'src');
  });

  test('quick open and side-panel tree use the host path context', () async {
    final files = _HostFiles(p.posix, {first: 'a'});
    final index = IdeFileIndex(files, root, pathContext: p.posix);
    addTearDown(index.dispose);
    expect(index.relativeOf(first), 'lib/a.dart');
    index.roots = [root];
    expect(index.relativeOf(first), 'hjh/lib/a.dart');

    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final explorer = panel.explorerOf(
      root,
      files,
      paths: p.posix,
      watch: (_) => const Stream.empty(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(explorer.root, root);
    expect(explorer.paths.style, p.Style.posix);
    panel.setRoots(root, [root]);
    expect(explorer.roots, [root]);
  });
}
