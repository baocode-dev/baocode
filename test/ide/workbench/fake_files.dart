import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/extensions/ide_extensions.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:path/path.dart' as p;

import '../terminal/fake_pty.dart';
import '../terminal/fake_terminal.dart';

/// An in-memory project: files by absolute path; folders are implied, or
/// [folders] when empty.
class TreeFiles implements IdeFileService {
  TreeFiles(this.contents);

  final Map<String, String> contents;
  final Set<String> folders = {};

  /// The files [writeBytes] made, whose [contents] mark them binary.
  final Map<String, Uint8List> bytes = {};
  int listCalls = 0;

  bool _exists(String path) =>
      contents.containsKey(path) ||
      folders.contains(path) ||
      contents.keys.any((file) => p.isWithin(path, file));

  @override
  Future<List<IdeFile>> list(String directory) async {
    listCalls++;
    final children = <String, bool>{};
    for (final path in [...contents.keys, ...folders]) {
      if (!p.isWithin(directory, path)) continue;
      final first = p.split(p.relative(path, from: directory)).first;
      final child = p.join(directory, first);
      children[child] = child != path || folders.contains(path);
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

  @override
  Future<void> create(String path, {bool directory = false}) async {
    if (_exists(path)) throw IdeFileExistsException(path);
    if (directory) {
      folders.add(path);
    } else {
      contents[path] = '';
    }
  }

  /// [path] and everything under it, moved by [move] (null drops it).
  void _moveTree(
    String path,
    String? Function(String) move, {
    bool keep = false,
  }) {
    for (final file in [...contents.keys]) {
      if (file == path || p.isWithin(path, file)) {
        final text = keep ? contents[file]! : contents.remove(file)!;
        if (move(file) case final target?) contents[target] = text;
      }
    }
    for (final folder in [...folders]) {
      if (folder == path || p.isWithin(path, folder)) {
        if (!keep) folders.remove(folder);
        if (move(folder) case final target?) folders.add(target);
      }
    }
  }

  String _under(String from, String to, String path) =>
      path == from ? to : p.join(to, p.relative(path, from: from));

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    if (_exists(path)) throw IdeFileExistsException(path);
    contents[path] = '\x00';
    this.bytes[path] = bytes;
  }

  @override
  Future<void> rename(String from, String to) async {
    if (!_exists(from)) throw IdeFileNotFoundException(from);
    if (_exists(to)) throw IdeFileExistsException(to);
    _moveTree(from, (path) => _under(from, to, path));
  }

  @override
  Future<void> copy(String from, String to) async {
    if (!_exists(from)) throw IdeFileNotFoundException(from);
    if (_exists(to)) throw IdeFileExistsException(to);
    _moveTree(from, (path) => _under(from, to, path), keep: true);
  }

  @override
  Future<void> delete(String path) async {
    if (!_exists(path)) throw IdeFileNotFoundException(path);
    _moveTree(path, (_) => null);
  }
}

/// File operations for fakes that only read and write.
mixin ReadWriteOnlyFiles implements IdeFileService {
  @override
  Future<void> create(String path, {bool directory = false}) =>
      throw UnsupportedError('create');

  @override
  Future<void> rename(String from, String to) =>
      throw UnsupportedError('rename');

  @override
  Future<void> copy(String from, String to) => throw UnsupportedError('copy');

  @override
  Future<void> delete(String path) => throw UnsupportedError('delete');

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      throw UnsupportedError('writeBytes');
}

final testRoot = p.join(p.separator, 'project');
String inRoot(String relative) => p.joinAll([testRoot, ...relative.split('/')]);

const chatKey = Key('test-chat');

/// Pumps an [IdeWorkbench] over [files] (relative paths), opening [open].
/// Its terminals run on fakes ([startPty], [FakePty.starter]), and there
/// are none unless [terminals] (as on the web).
Future<IdeWorkspace> pumpWorkbench(
  WidgetTester tester,
  Map<String, String> files, {
  List<String> open = const [],
  Size size = const Size(1400, 800),
  bool nativeEditor = false,
  LanguageFeatures? languages,
  Set<String> ignoredRecommendations = const {},
  ValueChanged<String>? onIgnoreRecommendation,
  IdeGitRepository? git,
  IdeTextSearch? textSearch,
  IdeExtensions? extensions,
  IdeCommitMessageModel? commitMessage,
  ValueChanged<bool>? onPinnedChanged,
  PtyStarter? startPty,
  bool terminals = true,
  IdeColorThemeController? colorThemes,
  VoidCallback? onBack,
  Widget chat = const SizedBox.expand(key: chatKey),
  UserSettings? settings,
  Map<String, Object?>? viewState,
  ValueChanged<Map<String, Object?>>? onViewState,
  List<String>? roots,
  IdeGitRepository? Function(String root)? gitOf,
  VoidCallback? onAddFolder,
  ValueChanged<String>? onRemoveFolder,
  Project? project,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final workspace = IdeWorkspace(
    testRoot,
    files: TreeFiles({
      for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
    }),
    languages: languages,
    git: git,
    // A multi-folder workspace's: its folders (in the project).
    roots: [for (final root in roots ?? const <String>[]) inRoot(root)],
    gitOf: roots == null ? null : (root) => gitOf?.call(root),
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
        project: project ?? Project.at(testRoot),
        onAddFolder: onAddFolder,
        onRemoveFolder: onRemoveFolder,
        visible: true,
        chat: chat,
        onBack: onBack ?? () {},
        ignoredRecommendations: ignoredRecommendations,
        onIgnoreRecommendation: onIgnoreRecommendation,
        textSearch: textSearch ?? ideSearchText,
        extensions: extensions,
        // Never the real Claude Code under test.
        commitMessage: commitMessage ?? _noModel,
        onPinnedChanged: onPinnedChanged,
        colorThemes: colorThemes,
        settings: settings,
        viewState: viewState,
        onViewState: onViewState,
        // Never a real shell under test.
        terminalBackend: TerminalBackend(
          launch: fakeTerminalLaunch,
          start: startPty ?? FakePty.starter([]),
          detectProfiles: fakeTerminalProfiles,
          settings: settings,
          // Links name the fake files (and their folders), not the disk's.
          linkStat: (path) async =>
              files.containsKey(
                p.relative(path, from: testRoot).replaceAll(r'\', '/'),
              )
              ? false
              : files.keys.any((file) => p.isWithin(path, inRoot(file)))
              ? true
              : null,
          supported: terminals,
        ),
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

Future<String> _noModel(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
}) async => throw StateError('No commit message model in this test');
