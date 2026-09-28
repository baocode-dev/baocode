import 'dart:async';

import 'package:monad/kernel/kernel_registry.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';

/// Every test runs on the scripted kernels: none starts a real CLI.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  KernelRegistry.use(MockKernels.all);
  await testMain();
}
