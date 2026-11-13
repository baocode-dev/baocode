@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/composer/remote_drops.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../ide/workbench/fake_files.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode_drops_');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  String local(String relative, [String text = 'x']) {
    final file = File(p.join(temp.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    return file.path;
  }

  test('a big file goes up a stretch at a time, how far told', () async {
    final host = _RangeTree();
    final big = File(p.join(temp.path, 'big.bin'))
      ..writeAsBytesSync(List.generate(1200000, (i) => i % 251));
    final told = <int>[];
    final copies = await RemoteDrops.copy(host, [
      ComposerFile(big.path),
    ], onFile: (read, size) => told.add(read));
    final copy = copies.single.path;
    expect(host.bytes[copy], big.readAsBytesSync());
    expect(host.appended, 2);
    expect(told, [524288, 1048576, 1200000]);
  });

  test('given up partway, the file it was on is gone from the host', () async {
    final host = _RangeTree();
    final big = File(p.join(temp.path, 'big.bin'))
      ..writeAsBytesSync(List.filled(1200000, 1));
    final cancel = Completer<void>();
    await expectLater(
      RemoteDrops.copy(
        host,
        [ComposerFile(big.path)],
        onFile: (read, size) {
          if (!cancel.isCompleted) cancel.complete();
        },
        cancel: cancel.future,
      ),
      throwsA(isA<TransferCancelledException>()),
    );
    expect(host.contents.keys.where((path) => path.endsWith('big.bin')), []);
  });

  test('copies files and folders to a folder of their own on the host, '
      'the same name from two folders numbered', () async {
    final host = TreeFiles({});
    final a = local('one/a.txt', 'first');
    final other = local('two/a.txt', 'second');
    local('dir/b.txt', 'b');
    final copies = await RemoteDrops.copy(host, [
      ComposerFile(a),
      ComposerFile(other),
      ComposerFile(p.join(temp.path, 'dir'), directory: true),
    ], now: DateTime.fromMicrosecondsSinceEpoch(36 * 36));
    const into = '${RemoteDrops.folder}/100';
    expect(copies, [
      const ComposerFile('$into/a.txt'),
      const ComposerFile('$into/a 2.txt'),
      const ComposerFile('$into/dir', directory: true),
    ]);
    expect(String.fromCharCodes(host.bytes['$into/a.txt']!), 'first');
    expect(String.fromCharCodes(host.bytes['$into/a 2.txt']!), 'second');
    expect(String.fromCharCodes(host.bytes['$into/dir/b.txt']!), 'b');

    // Again: the folder there already, another of their own in it.
    final again = await RemoteDrops.copy(host, [
      ComposerFile(a),
    ], now: DateTime.fromMicrosecondsSinceEpoch(37 * 36));
    expect(again.single.path, startsWith('${RemoteDrops.folder}/'));
    expect(host.bytes[again.single.path], isNotNull);
  });

  group('the composer', () {
    Future<ChatComposerState> pump(
      WidgetTester tester, {
      required String cwd,
      TreeFiles? host,
    }) async {
      final session = ChatSession(
        historyCount: 0,
        kernelContext: KernelContext(cwd: cwd),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposer(session: session, hostFiles: host),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.state<ChatComposerState>(find.byType(ChatComposer));
    }

    List<String> tags(WidgetTester tester) => [
      for (final piece in composerPieces(
        tester
            .widget<MarkdownEditor>(find.byType(MarkdownEditor))
            .controller
            .text,
      ))
        if (piece
            case ComposerEmbed(type: ComposerTokenEmbed.type) && final tag)
          tag.plainText,
    ];

    testWidgets("of a remote project tags copies on the host of this "
        "machine's files let go on it", (tester) async {
      final host = TreeFiles({});
      final state = await pump(
        tester,
        cwd: 'ssh://box/home/me/app',
        host: host,
      );
      final file = local('notes.md');
      await tester.runAsync(() async {
        state.fileDrop(Offset.zero, [ComposerFile(file)]);
        // The copy reads and writes for real.
        for (var i = 0; i < 20 && host.bytes.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      final copied = host.bytes.keys.single;
      expect(copied, startsWith('${RemoteDrops.folder}/'));
      expect(copied, endsWith('/notes.md'));
      expect(tags(tester), ['@$copied']);
    });

    testWidgets("of a local project tags this machine's files as they are", (
      tester,
    ) async {
      final state = await pump(tester, cwd: p.join(temp.path, 'app'));
      final file = local('elsewhere/notes.md');
      state.fileDrop(Offset.zero, [ComposerFile(file)]);
      await tester.pump();
      expect(tags(tester), ['@$file']);
    });
  });
}

/// A host's files written a stretch at a time.
class _RangeTree extends TreeFiles implements IdeRangeFiles {
  _RangeTree() : super({});

  int appended = 0;

  @override
  Future<void> appendBytes(String path, int offset, Uint8List data) async {
    expect(bytes[path]!.length, offset);
    appended++;
    bytes[path] = Uint8List.fromList([...bytes[path]!, ...data]);
  }

  @override
  Future<({Uint8List bytes, int size})> readRange(
    String path,
    int offset,
    int length, {
    Future<void>? cancel,
  }) => throw UnimplementedError();

  @override
  Future<int> sizeOf(List<String> paths, {int? limit}) =>
      throw UnimplementedError();
}
