import 'dart:async';

import 'package:monad/kernel/kernel_registry.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';

import 'semantics_tree.dart';

/// Every test runs on the scripted kernels: none starts a real CLI; and
/// fails if its semantics updates would break the desktop engines'
/// accessibility tree.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  checkDesktopSemantics();
  KernelRegistry.use(MockKernels.all);
  await testMain();
}
