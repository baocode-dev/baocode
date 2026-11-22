import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A kernel that counts the times it was got ready.
class _Kernel implements AgentKernel {
  _Kernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;

  int prepared = 0;

  @override
  Stream<KernelEvent> get events => const Stream.empty();

  @override
  void prepare() => prepared++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('the kernel picked in a conversation shown gets ready at once', () {
    final made = <String, _Kernel>{};
    KernelDescriptor kind(String id) {
      late final KernelDescriptor descriptor;
      return descriptor = KernelDescriptor(
        id: id,
        label: id,
        icon: Icons.abc,
        description: '',
        create: (context) => made[id] = _Kernel(descriptor),
      );
    }

    final kernels = [kind('one'), kind('two'), kind('three')];
    final session = ChatSession(
      kernel: kernels.first,
      kernels: kernels,
      kernelContext: const KernelContext(cwd: '/p'),
      historyCount: 0,
    );
    // Not shown: only made.
    session.setKernel(kernels[1]);
    expect(made['two']!.prepared, 0);

    session.attach();
    session.setKernel(kernels[2]);
    // Its models (and all it tells as it starts) to show before a message.
    expect(made['three']!.prepared, 1);
  });
}
