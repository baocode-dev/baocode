// The perf app's own CPU time and memory, as the system counts them.
//
// Memory is the physical footprint, what Activity Monitor shows as an
// app's memory and what the system holds against it: on macOS it includes
// what the GPU holds for it (Metal textures, IOSurfaces), which the
// resident size does not. Its parts come from `footprint`: the graphics
// (GPU), malloc's (the engine, Skia, fonts) and VM_ALLOCATE's (mostly the
// Dart heap). Elsewhere the footprint is the resident size, without parts.

import 'dart:ffi';
import 'dart:io';

typedef _RusageNative = Int32 Function(Int32, Int32, Pointer<Uint64>);
typedef _Rusage = int Function(int, int, Pointer<Uint64>);

/// macOS's `proc_pid_rusage(RUSAGE_INFO_V2)`, into a buffer of its own.
class _Darwin {
  _Darwin() {
    final process = DynamicLibrary.process();
    final malloc = process
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('malloc');
    _buffer = malloc(512).cast<Uint64>();
    _rusage = process.lookupFunction<_RusageNative, _Rusage>('proc_pid_rusage');
    final timebase = malloc(8).cast<Uint32>();
    process.lookupFunction<
      Int32 Function(Pointer<Uint32>),
      int Function(Pointer<Uint32>)
    >('mach_timebase_info')(timebase);
    _nanosPerTick = timebase[0] / timebase[1];
  }

  late final Pointer<Uint64> _buffer;
  late final _Rusage _rusage;
  late final double _nanosPerTick;

  // rusage_info_v2, in 64-bit words: the uuid (2), user time, system time
  // (in mach ticks), idle and interrupt wakeups, pageins, wired, resident,
  // physical footprint.
  bool _read() => _rusage(pid, 2, _buffer) == 0;

  double? cpuMs() =>
      _read() ? (_buffer[2] + _buffer[3]) * _nanosPerTick / 1e6 : null;

  int? footprint() => _read() ? _buffer[9] : null;
}

abstract final class PerfProcess {
  static final _Darwin? _darwin = Platform.isMacOS ? _Darwin() : null;

  /// The CPU time it has used, all threads, in milliseconds; null where
  /// it is not known.
  static double? cpuMs() {
    if (_darwin case final darwin?) return darwin.cpuMs();
    if (Platform.isLinux) {
      try {
        final fields = File('/proc/self/stat')
            .readAsStringSync()
            .split(') ')
            .last
            .split(' ');
        // utime and stime, in clock ticks (100 a second).
        return (int.parse(fields[11]) + int.parse(fields[12])) * 10.0;
      } on Object {
        return null;
      }
    }
    return null;
  }

  /// The GPU time the system has counted, in nanoseconds: for this
  /// process, and for WindowServer, which composites its window with the
  /// others (on a HiDPI screen, at its full pixels). From the GPU driver's
  /// clients in the I/O registry, as Activity Monitor's GPU column; macOS
  /// on Apple's GPUs only, null elsewhere.
  static ({int own, int windowServer})? gpuNs() {
    if (!Platform.isMacOS) return null;
    try {
      final result = Process.runSync('ioreg', [
        '-l',
        '-w0',
        '-r',
        '-c',
        'AGXDeviceUserClient',
      ]);
      final creator = RegExp(r'"IOUserClientCreator" = "pid (\d+), ([^"]*)"');
      final time = RegExp(r'"accumulatedGPUTime"=(\d+)');
      var own = 0, windowServer = 0, found = false;
      for (final client in (result.stdout as String).split(
        '+-o AGXDeviceUserClient',
      )) {
        final by = creator.firstMatch(client);
        if (by == null) continue;
        final ns = [
          for (final match in time.allMatches(client)) int.parse(match[1]!),
        ].fold(0, (a, b) => a + b);
        if (int.parse(by[1]!) == pid) {
          own += ns;
          found = true;
        } else if (by[2] == 'WindowServer') {
          windowServer += ns;
        }
      }
      return found ? (own: own, windowServer: windowServer) : null;
    } on Object {
      return null;
    }
  }

  /// Its physical footprint, in bytes (see above).
  static int footprint() => _darwin?.footprint() ?? ProcessInfo.currentRss;

  /// The footprint's parts, in bytes, by `footprint` (macOS); null
  /// elsewhere or when it fails.
  static Future<Map<String, int>?> parts() async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await Process.run('footprint', [
        '-p',
        '$pid',
        '-f',
        'bytes',
      ]);
      var gpu = 0, malloc = 0, vm = 0;
      final line = RegExp(r'^\s*(\d+) B\s+\d+ B\s+\d+ B\s+\d+\s+(.+)$');
      final all = <(int, String)>[];
      for (final text in (result.stdout as String).split('\n')) {
        final match = line.firstMatch(text);
        if (match == null) continue;
        final dirty = int.parse(match[1]!);
        final category = match[2]!;
        all.add((dirty, category));
        if (category.contains('graphics') ||
            category.startsWith('IOSurface') ||
            category.startsWith('IOAccelerator')) {
          gpu += dirty;
        } else if (category.startsWith('MALLOC')) {
          malloc += dirty;
        } else if (category.startsWith('untagged (VM_ALLOCATE)')) {
          vm += dirty;
        }
      }
      // BAOCODE_PERF_FOOTPRINT set: every category, for finding what to
      // make smaller.
      if (Platform.environment.containsKey('BAOCODE_PERF_FOOTPRINT')) {
        all.sort((a, b) => b.$1.compareTo(a.$1));
        stderr.writeln(
          'BAOCODE_PERF_LOG footprint: ${[for (final (bytes, name) in all.take(14)) '$name ${(bytes / 1048576).toStringAsFixed(1)}MB'].join(', ')}',
        );
      }
      return {'gpu': gpu, 'malloc': malloc, 'vmAllocate': vm};
    } on Object {
      return null;
    }
  }
}
