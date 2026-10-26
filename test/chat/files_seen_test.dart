import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';

/// A kernel whose events the test sends.
class _Kernel implements AgentKernel {
  _Kernel(this.descriptor, this.events);

  @override
  final KernelDescriptor descriptor;

  @override
  final Stream<KernelEvent> events;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A session in /p fed [events], as they come.
ChatSession _session(Stream<KernelEvent> events) {
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'test',
    label: 'Test',
    icon: Icons.abc,
    description: '',
    create: (context) => _Kernel(descriptor, events),
  );
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    kernelContext: const KernelContext(cwd: '/p'),
    historyCount: 0,
  );
  addTearDown(session.dispose);
  return session;
}

void main() {
  test('filesSeen is the same list while no file is new', () {
    final live = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(live.close);
    final session = _session(live.stream);
    live.add(
      const ItemUpserted(
        1,
        'read',
        ToolCallItem(kind: ToolKind.read, target: 'a', path: 'a.dart'),
      ),
    );
    live.add(const ItemUpserted(2, 'say', AssistantTextItem('a')));
    final files = session.filesSeen;
    expect(files, ['/p/a.dart']);
    live.add(const ItemUpserted(3, 'say', AssistantTextItem('ab')));
    live.add(
      const ItemUpserted(
        4,
        'again',
        ToolCallItem(kind: ToolKind.read, target: 'a', path: '/p/a.dart'),
      ),
    );
    expect(session.filesSeen, same(files));
    live.add(
      const FileEdited(5, FileChange(path: 'b.dart', added: 1, removed: 0)),
    );
    expect(session.filesSeen, ['/p/a.dart', '/p/b.dart']);
  });

  test("each change pending with its turn and what the turn was asked", () {
    final live = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(live.close);
    final session = _session(live.stream);
    live.add(
      const ItemUpserted(
        1,
        't1',
        UserMessageItem(text: 'Fix the login\nplease'),
      ),
    );
    live.add(
      const FileEdited(
        2,
        FileChange(path: 'a.dart', added: 1, removed: 0),
        turnId: 't1',
      ),
    );
    expect(session.turnEdits, [
      (turn: 't1', request: 'Fix the login\nplease', path: '/p/a.dart'),
    ]);
  });
}
