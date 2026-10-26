import 'package:flutter/foundation.dart';

import '../../kernel/kernel_types.dart';

/// The background commands of the agent beside the IDE (its chat's), which
/// the TERMINAL tab lists with its terminals: each shows its output in the
/// terminal's place, as the chat window's side panel does.
abstract interface class TerminalTasks implements Listenable {
  /// Background commands, the finished ones too (for their output).
  List<KernelTask> get tasks;

  /// The command line [task] runs, where its tool call is known.
  String? commandOf(KernelTask task);

  void stop(KernelTask task);

  /// Takes those of [tasks] that have ended off [tasks].
  void clear(Iterable<KernelTask> tasks);

  /// The folder relative paths in the output are links into.
  String get root;
}
