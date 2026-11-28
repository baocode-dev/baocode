import 'package:bao_remote/acp.dart' as acp;

import 'agy_runtime_stub.dart'
    if (dart.library.io) 'agy_runtime_io.dart'
    as platform;

export 'package:bao_remote/acp.dart'
    show AgyModel, AgyUnavailable, agyEfforts, agyHello, parseAgyModels;

/// Google's Antigravity CLI (`agy`) as BaoCode runs it: extends the pure-Dart
/// [acp.AgyRuntime] interface with this machine's [local] singleton.
abstract interface class AgyRuntime implements acp.AgyRuntime {
  /// This machine's.
  static AgyRuntime get local => _local ??= platform.localAgyRuntime();
  static AgyRuntime? _local;

  /// Uses [runtime] in place of this machine's, e.g. a fake under test.
  static set local(AgyRuntime runtime) => _local = runtime;
}

/// The local Antigravity `brain/` directory, where native swarm state lives;
/// null on platforms without a local runtime.
String? agyLocalBrainDir() => platform.localAgyBrainDir();
