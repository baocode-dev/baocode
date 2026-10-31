import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/open_editor.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

void main() {
  group('the file open in the editor', () {
    final snapshot = DocumentSnapshot('one\ntwo\nthree\nfour\n');

    test('is where its cursor is, and the lines and code it selects', () {
      expect(
        OpenEditor.at('/p/a.conf', snapshot, null),
        OpenEditor('/p/a.conf'),
      );
      expect(
        OpenEditor.at(
          '/p/a',
          snapshot,
          const TextSelection.collapsed(offset: 5),
        ),
        const OpenEditor('/p/a', line: 2),
      );
      // Lines 2 and 3 selected whole, up to the start of line 4.
      expect(
        OpenEditor.at(
          '/p/a',
          snapshot,
          const TextSelection(baseOffset: 4, extentOffset: 14),
        ),
        const OpenEditor(
          '/p/a',
          line: 4,
          selectedLines: (2, 3),
          selectedText: 'two\nthree\n',
        ),
      );
    });

    test('is told as a system reminder', () {
      expect(
        const OpenEditor('/p/a', line: 4).note,
        '<system-reminder>The user has /p/a open in the editor, the cursor '
        'on line 4. This may or may not be related to the current task.'
        '</system-reminder>',
      );
      expect(
        const OpenEditor(
          '/p/a',
          line: 3,
          selectedLines: (2, 3),
          selectedText: 'two\nthree',
        ).note,
        '<system-reminder>The user selected lines 2-3 of /p/a in the '
        'editor:\ntwo\nthree\n\nThis may or may not be related to the '
        'current task.</system-reminder>',
      );
      expect(
        const OpenEditor(
          '/p/a',
          selectedLines: (2, 2),
          selectedText: 'two',
        ).note,
        contains('The user selected line 2 of /p/a in the editor:\ntwo\n'),
      );
      // A long selection, cut short.
      final long = OpenEditor(
        '/p/a',
        selectedLines: (1, 900),
        selectedText: 'x' * (OpenEditor.maxSelectedText + 25),
      ).note;
      expect(long, contains('x' * OpenEditor.maxSelectedText));
      expect(long, isNot(contains('x' * (OpenEditor.maxSelectedText + 1))));
      expect(long, contains('[25 more characters selected, not shown'));
      expect(
        const OpenEditor('/p/a').note,
        contains('/p/a open in the editor.'),
      );
    });
  });

  testWidgets('the agent is told of the file open as it changes', (
    tester,
  ) async {
    final cli = FakeCli();
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
    );
    addTearDown(session.dispose);

    OpenEditor? open;
    Future<List<String>> send(String text) async {
      session.send(ComposerMessage(text: text), editor: () => open);
      await tester.pump(const Duration(milliseconds: 100));
      final content = cli.users.last['message']! as Map;
      // Done, for the next to be given the CLI at once.
      cli.push({'type': 'result', 'subtype': 'success', 'is_error': false});
      await tester.pump(const Duration(milliseconds: 100));
      return [
        for (final block in content['content']! as List)
          (block as Map)['text']! as String,
      ];
    }

    // No file open, none ever was: nothing to tell.
    expect(await send('hi'), ['hi']);
    open = const OpenEditor('/p/a.conf', line: 3);
    expect(await send('this one'), [open.note, 'this one']);
    // Told already.
    expect(await send('and?'), ['and?']);
    open = const OpenEditor('/p/a.conf', line: 9);
    expect(await send('here'), [open.note, 'here']);
    // A command is told by the last block: the note goes before it.
    open = const OpenEditor('/p/a.conf', line: 12);
    expect(await send('/compact'), [open.note, '/compact']);
    open = null;
    expect(await send('now'), [OpenEditor.closedNote, 'now']);
    expect(await send('still'), ['still']);
    // Sent from where there is no editor: nothing said of one.
    session.send(const ComposerMessage(text: 'elsewhere'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cli.users.last['message'], {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'elsewhere'},
      ],
    });
  });
}
