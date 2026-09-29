import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/file_service.dart';
import 'package:monad/ide/ide_workbench.dart';
import 'package:monad/ide/ide_workspace.dart';
import 'package:monad/ide/lsp/language_features.dart';
import 'package:monad/workspace/workspace.dart';
import 'package:path/path.dart' as p;

/// An in-memory project: files by absolute path; folders are implied.
class TreeFiles implements IdeFileService {
  TreeFiles(this.contents);

  final Map<String, String> contents;
  int listCalls = 0;

  @override
  Future<List<IdeFile>> list(String directory) async {
    listCalls++;
    final children = <String, bool>{};
    for (final path in contents.keys) {
      if (!p.isWithin(directory, path)) continue;
      final first = p.split(p.relative(path, from: directory)).first;
      final child = p.join(directory, first);
      children[child] = child != path;
    }
    final entries = [
      for (final MapEntry(key: path, value: isDirectory) in children.entries)
        IdeFile(path, p.basename(path), isDirectory: isDirectory),
    ];
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  @override
  Future<String> read(String path, {bool force = false}) async {
    final text = contents[path];
    if (text == null) throw IdeFileNotFoundException(path);
    // A NUL marks a binary file, as the real service finds them.
    if (!force && text.contains('\x00')) throw IdeBinaryFileException(path);
    return text;
  }

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    if (contents[path] != expectedText) throw IdeFileConflictException(path);
    contents[path] = text;
  }
}

final testRoot = p.join(p.separator, 'project');
String inRoot(String relative) => p.joinAll([testRoot, ...relative.split('/')]);

const chatKey = Key('test-chat');

/// Pumps an [IdeWorkbench] over [files] (relative paths), opening [open].
Future<IdeWorkspace> pumpWorkbench(
  WidgetTester tester,
  Map<String, String> files, {
  List<String> open = const [],
  Size size = const Size(1400, 800),
  bool nativeEditor = false,
  LanguageFeatures? languages,
  Set<String> ignoredRecommendations = const {},
  ValueChanged<String>? onIgnoreRecommendation,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final workspace = IdeWorkspace(
    testRoot,
    files: TreeFiles({
      for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
    }),
    languages: languages,
  );
  addTearDown(() {
    workspace.dispose();
    tester.view.reset();
  });
  for (final path in open) {
    await workspace.open(inRoot(path));
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: IdeWorkbench(
        nativeEditorEnabled: nativeEditor,
        workspace: workspace,
        project: Project.at(testRoot),
        visible: true,
        chat: const SizedBox.expand(key: chatKey),
        onBack: () {},
        ignoredRecommendations: ignoredRecommendations,
        onIgnoreRecommendation: onIgnoreRecommendation,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return workspace;
}

/// Presses [key] with Control (the primary modifier off macOS) and others.
Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}
