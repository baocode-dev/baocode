import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

void main() {
  setUp(() {
    final folder = Directory(DataDirectory.current.pastesDir);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  ChatSession start(FakeCli cli, {String? cwd}) {
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) =>
          ClaudeCodeKernel(descriptor, context, start: (_) async => cli),
    );
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      historyCount: 0,
      kernelContext: KernelContext(cwd: cwd),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// The text blocks written with the user's first message.
  List<String> texts(FakeCli cli) => [
    for (final block in (cli.users.first['message'] as Map)['content'] as List)
      if ((block as Map)['text'] case final String text) text,
  ];

  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 4, 5, 6]);

  test(
    'the agent is told where the images sent are, as files (#1129)',
    () async {
      final cli = FakeCli();
      final session = start(cli);
      session.send(
        ComposerMessage(
          text: 'Upload [Image #3] and this one',
          images: [
            ImageAttachment(bytes: png, mediaType: 'image/png', number: 3),
            ImageAttachment(bytes: jpeg, mediaType: 'image/jpeg'),
          ],
        ),
      );
      await pumpEventQueue();
      final note = texts(cli).singleWhere((text) => text.contains('saved as'));
      final paths = RegExp(
        r': (/\S+)$',
        multiLine: true,
      ).allMatches(note).map((match) => match[1]!).toList();
      expect(note, contains('[Image #3]: '));
      expect(note, contains('Image 2: '));
      expect(paths, hasLength(2));
      expect(paths.first, endsWith('.png'));
      expect(paths.last, endsWith('.jpg'));
      expect(File(paths.first).readAsBytesSync(), png);
      expect(File(paths.last).readAsBytesSync(), jpeg);
      expect(
        paths.every((path) => path.startsWith(DataDirectory.current.pastesDir)),
        isTrue,
      );
    },
  );

  test('none without images, nor for a remote project\'s agent', () async {
    final plain = FakeCli();
    start(plain).send(const ComposerMessage(text: 'hi'));
    await pumpEventQueue();
    expect(texts(plain).where((text) => text.contains('saved as')), isEmpty);

    final remote = FakeCli();
    start(remote, cwd: 'ssh://host/p').send(
      ComposerMessage(
        text: 'look',
        images: [ImageAttachment(bytes: png, mediaType: 'image/png')],
      ),
    );
    await pumpEventQueue();
    expect(texts(remote).where((text) => text.contains('saved as')), isEmpty);
  });
}
