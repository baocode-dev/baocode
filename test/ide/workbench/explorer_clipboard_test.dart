import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:bao_remote/search.dart' show IdeTextQuery;
import 'package:baocode/chat/composer/file_drop.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_notifications.dart';

import 'fake_files.dart';

/// The explorer with the system's clipboard: files copied in Finder or
/// Explorer paste in, what was cut or copied here pastes until other files
/// are copied there, and a tree with no workbench (the chat's side panel)
/// runs its keybindings itself.
void main() {
  const files = {'lib/a.dart': 'a', 'lib/util.dart': 'u', 'README.md': 'r'};
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  Finder row(String name) =>
      find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

  TreeFiles filesOf(WidgetTester tester) =>
      tester.widget<IdeExplorer>(find.byType(IdeExplorer)).controller.files
          as TreeFiles;

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  /// Frames and real time in turn, for what reads and writes files here
  /// (the menu's choice is made once it has closed).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
  }

  /// The system's clipboard: what it holds, as files.
  List<String> clipboard(WidgetTester tester) {
    final held = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('baocode/window');
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writePasteboardFiles':
          held
            ..clear()
            ..addAll((call.arguments as List).cast<String>());
          return true;
        case 'readPasteboardFiles':
          return [
            for (final path in held)
              {'path': path, 'directory': !p.basename(path).contains('.')},
          ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return held;
  }

  testWidgets('files copied in Finder or Explorer paste in as copies, from '
      'the menu and the keyboard', (tester) async {
    final held = clipboard(tester);
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    held.addAll([inRoot('README.md'), inRoot('lib/a.dart')]);

    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('lib/README.md')], 'r');
    expect(contents[inRoot('lib/a copy.dart')], 'a');

    // A file's folder, from the keyboard.
    await tester.tap(row('util.dart'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    expect(contents[inRoot('lib/README copy.md')], 'r');
    expect(contents[inRoot('lib/a copy 2.dart')], 'a');
  }, variant: windows);

  testWidgets('what was cut pastes while the system\'s clipboard holds what '
      'it did; files copied there since paste instead', (tester) async {
    final held = clipboard(tester);
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX, control: true);
    await tester.pumpAndSettle();
    // Copied in Finder since.
    held.add(inRoot('lib/util.dart'));

    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('lib/util copy.dart')], 'u');
    expect(contents[inRoot('README.md')], 'r');

    // Cut again, with that still there: the cut moves.
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX, control: true);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(contents.containsKey(inRoot('README.md')), isFalse);
    expect(contents[inRoot('lib/README.md')], 'r');
  }, variant: windows);

  testWidgets('Paste is disabled with nothing to paste', (tester) async {
    clipboard(tester);
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    // Still open: a disabled item does nothing.
    expect(find.text('Paste'), findsOneWidget);
    expect(filesOf(tester).contents, hasLength(files.length));
  }, variant: windows);

  testWidgets('a folder does not paste into itself', (tester) async {
    final held = clipboard(tester);
    final errors = <Object>[];
    await _pumpTree(tester, files, onError: errors.add);
    held.add(inRoot('lib'));
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(errors, ['File to paste is an ancestor of the destination folder']);
    expect(filesOf(tester).folders, isEmpty);
  }, variant: windows);

  testWidgets('with no workbench (the chat\'s side panel), the tree runs its '
      'own keybindings: copy, paste and the arrows', (tester) async {
    final held = clipboard(tester);
    await _pumpTree(tester, files);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyC, control: true);
    expect(held, [inRoot('README.md')]);
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('README copy.md')], 'r');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final controller = tester
        .widget<IdeExplorer>(find.byType(IdeExplorer))
        .controller;
    expect(controller.selected, inRoot('lib'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(row('util.dart'), findsOneWidget);

    // Cut and paste moves.
    await tester.tap(row('util.dart'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX, control: true);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    expect(contents[inRoot('util.dart')], 'u');
    expect(contents.containsKey(inRoot('lib/util.dart')), isFalse);
  }, variant: windows);

  testWidgets('a remote project\'s copies are downloaded onto the system\'s '
      'clipboard, how far shown; this machine\'s files pasted into it go up '
      'to its host', (tester) async {
    final local = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('explorer_paste'),
    ))!;
    addTearDown(() => local.deleteSync(recursive: true));
    final notes = File(p.join(local.path, 'notes.txt'));
    await tester.runAsync(() => notes.writeAsString('hi'));

    final held = clipboard(tester);
    final notifications = IdeNotifications();
    addTearDown(notifications.dispose);
    final host = _HostFiles({
      for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
    });
    final gate = host.gate = Completer<void>();
    await _pumpTree(
      tester,
      files,
      local: false,
      host: host,
      notifications: notifications,
    );
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await chord(tester, LogicalKeyboardKey.keyC, control: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    // Taking a moment: shown.
    expect(held, isEmpty);
    expect(
      notifications.notifications.single.message,
      'Downloading files... 0/1 0%',
    );
    gate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(notifications.notifications, isEmpty);
    expect(p.basename(held.single), 'README.md');
    expect(File(held.single).readAsStringSync(), 'r');

    held
      ..clear()
      ..add(notes.path);
    await tester.runAsync(() async {
      await chord(tester, LogicalKeyboardKey.keyV, control: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(host.bytes[inRoot('notes.txt')], 'hi'.codeUnits);
  }, variant: windows);

  testWidgets('Download...: a remote project\'s folder into one picked here, '
      'what is there by its name written over once agreed', (tester) async {
    final into = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('explorer_download'),
    ))!;
    addTearDown(() => into.deleteSync(recursive: true));
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('baocode/window');
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'pickDirectory' ? into.path : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _pumpTree(
      tester,
      files,
      local: false,
      host: _HostFiles({
        for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
      }),
    );
    Future<void> download() async {
      await rightClick(tester, row('lib'));
      await tester.tap(find.text('Download...'));
      await settle(tester);
    }

    await download();
    expect(File(p.join(into.path, 'lib', 'a.dart')).readAsStringSync(), 'a');
    expect(File(p.join(into.path, 'lib', 'util.dart')).readAsStringSync(), 'u');

    // Again: asked first.
    File(p.join(into.path, 'lib', 'a.dart')).writeAsStringSync('mine');
    await download();
    expect(find.textContaining('Replace them?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await settle(tester);
    expect(File(p.join(into.path, 'lib', 'a.dart')).readAsStringSync(), 'a');
  }, variant: windows);

  testWidgets('a remote project\'s file dragged out of the window is '
      'downloaded once out, then dragged on as the system drags files', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('baocode/window');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _pumpTree(
      tester,
      files,
      local: false,
      host: _HostFiles({
        for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
      }),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(row('README.md')),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    // Not this machine's yet: the window only watches.
    expect(calls.single.method, 'armFileDrag');
    expect(calls.single.arguments, {'paths': null});
    await tester.runAsync(() async {
      await FileDrops.handle(const MethodCall('dragOut', {'began': false}));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final drag = calls.singleWhere((call) => call.method == 'startFileDrag');
    final paths = ((drag.arguments as Map)['paths'] as List).cast<String>();
    expect(p.basename(paths.single), 'README.md');
    expect(File(paths.single).readAsStringSync(), 'r');
    await gesture.up();
    await tester.pumpAndSettle();
  }, variant: windows);

  testWidgets('a remote project\'s big copies stay the app\'s: nothing is '
      'downloaded, and they paste on the host', (tester) async {
    final held = clipboard(tester);
    final host = _RangeHostFiles({
      for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
    }, size: IdeExplorerState.clipboardDownloadLimit + 1);
    await _pumpTree(tester, files, local: false, host: host);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await chord(tester, LogicalKeyboardKey.keyC, control: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(host.ranges, 0);
    expect(held, isEmpty);

    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await chord(tester, LogicalKeyboardKey.keyV, control: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(host.contents[inRoot('lib/README.md')], 'r');
  }, variant: windows);

  testWidgets('a remote project\'s copy downloads a stretch at a time, and '
      'its notification gives it up', (tester) async {
    final held = clipboard(tester);
    final notifications = IdeNotifications();
    addTearDown(notifications.dispose);
    final host = _RangeHostFiles({
      for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
    }, size: 3);
    final gate = host.gate = Completer<void>();
    final errors = <Object>[];
    await _pumpTree(
      tester,
      files,
      local: false,
      host: host,
      notifications: notifications,
      onError: errors.add,
    );
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await chord(tester, LogicalKeyboardKey.keyC, control: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    final shown = notifications.notifications.single;
    expect(shown.primary.single.label, 'Cancel');
    shown.primary.single.run();
    // Given up while the stretch is on its way: it is not written.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(host.ranges, 1);
    expect(held, isEmpty);
    expect(errors, isEmpty);
    expect(notifications.notifications, isEmpty);
  }, variant: windows);

  test('copyLocalTo copies a folder with its contents, without links to '
      'folders', () async {
    final local = await Directory.systemTemp.createTemp('explorer_upload');
    addTearDown(() => local.delete(recursive: true));
    final folder = Directory(p.join(local.path, 'docs'));
    await Directory(p.join(folder.path, 'sub')).create(recursive: true);
    await File(p.join(folder.path, 'a.md')).writeAsString('a');
    await File(p.join(folder.path, 'sub', 'b.md')).writeAsString('b');
    await Link(p.join(folder.path, 'up')).create(local.path);

    final tree = TreeFiles({});
    await copyLocalTo(tree, folder.path, '/project/docs');
    expect(tree.folders, {'/project/docs', '/project/docs/sub'});
    expect(tree.bytes.keys, {'/project/docs/a.md', '/project/docs/sub/b.md'});
    expect(tree.bytes['/project/docs/sub/b.md'], 'b'.codeUnits);
  }, testOn: '!windows');
}

/// Pumps a bare [IdeExplorer] over [files], as the chat's side panel shows
/// one: no workbench runs its keybindings.
Future<void> _pumpTree(
  WidgetTester tester,
  Map<String, String> files, {
  bool local = true,
  TreeFiles? host,
  IdeNotifications? notifications,
  ValueChanged<Object>? onError,
}) async {
  final controller = IdeExplorerController(
    files:
        host ??
        TreeFiles({
          for (final MapEntry(:key, :value) in files.entries)
            inRoot(key): value,
        }),
    root: testRoot,
    watch: (_) => const Stream.empty(),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: IdeNotificationsScope(
          notifications: notifications ?? IdeNotifications(),
          child: IdeExplorer(
            controller: controller,
            local: local,
            onOpen: (_, _) {},
            onError: onError == null
                ? null
                : (error) => onError(error is String ? error : '$error'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A remote project's files, on its host: read as bytes once [gate] opens.
class _HostFiles extends TreeFiles implements IdeHostFiles {
  _HostFiles(super.contents);

  Completer<void>? gate;

  @override
  Future<Uint8List> readBytes(String path) async {
    await gate?.future;
    return bytes[path] ?? utf8.encode(contents[path]!);
  }

  @override
  Stream<void> watchDirectory(String directory) => const Stream.empty();

  @override
  Future<IdeFileListing> listProject(String root, {int limit = 50000}) =>
      throw UnimplementedError();

  @override
  Stream<Object> searchText(String root, IdeTextQuery query) =>
      throw UnimplementedError();
}

/// A remote host's files read a stretch at a time, each [size] bytes big
/// for what they take.
class _RangeHostFiles extends _HostFiles implements IdeRangeFiles {
  _RangeHostFiles(super.contents, {required this.size});

  final int size;
  int ranges = 0;

  @override
  Future<({Uint8List bytes, int size})> readRange(
    String path,
    int offset,
    int length, {
    Future<void>? cancel,
  }) async {
    ranges++;
    await gate?.future;
    final all = await readBytes(path);
    final end = (offset + length).clamp(0, all.length);
    return (bytes: all.sublist(offset.clamp(0, end), end), size: all.length);
  }

  @override
  Future<int> sizeOf(List<String> paths, {int? limit}) async =>
      paths.length * size;

  @override
  Future<void> appendBytes(String path, int offset, Uint8List data) async {
    bytes[path] = Uint8List.fromList([...bytes[path]!, ...data]);
  }
}
