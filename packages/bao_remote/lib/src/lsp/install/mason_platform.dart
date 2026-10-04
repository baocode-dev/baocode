/// The machine a mason package is installed for, and the mason-registry
/// target names (`darwin_arm64`, `linux_x64_gnu`, `unix`, …) that fit it.
class MasonPlatform {
  const MasonPlatform(this.os, this.arch, {this.libc});

  /// `darwin`, `linux` or `win`.
  final String os;

  /// `x64`, `arm64`, `x86` or `arm` (mason's names).
  final String arch;

  /// `gnu` or `musl` on Linux; null elsewhere (or unknown: taken as gnu).
  final String? libc;

  bool get isWindows => os == 'win';

  /// Targets that fit exactly, most specific first: `linux_x64_gnu`,
  /// `linux_x64`, `linux`, `unix`.
  List<String> get targets => [
    if (os == 'linux') '${os}_${arch}_${libc ?? 'gnu'}',
    '${os}_$arch',
    os,
    if (os != 'win') 'unix',
  ];

  /// Targets that run here too, tried after [targets]: statically linked
  /// musl builds on glibc Linux, x64 builds under Rosetta on Apple silicon
  /// and under emulation on Windows on Arm.
  List<String> get fallbackTargets => [
    if (os == 'linux' && libc != 'musl') '${os}_${arch}_musl',
    if (os == 'darwin' && arch == 'arm64') 'darwin_x64',
    if (os == 'win' && arch == 'arm64') 'win_x64',
  ];

  /// Whether a registry `target` (a name or a list; absent: any) fits,
  /// counting [fallbackTargets] when [fallback].
  bool matches(Object? target, {bool fallback = false}) {
    if (target == null) return true;
    final names = target is List ? target : [target];
    final fitting = fallback ? [...targets, ...fallbackTargets] : targets;
    return names.any(fitting.contains);
  }

  /// The first of [entries] (registry `asset`/`download`/`build` entries,
  /// a list or one object) whose `target` fits, trying exact targets in
  /// order before the fallbacks; null when none does.
  Map<String, Object?>? select(Object? entries) {
    final list = [
      for (final entry in entries is List ? entries : [entries])
        if (entry is Map) entry.cast<String, Object?>(),
    ];
    for (final target in [...targets, ...fallbackTargets]) {
      for (final entry in list) {
        final names = switch (entry['target']) {
          null => null,
          final List<Object?> list => list,
          final Object single => [single],
        };
        if (names == null || names.contains(target)) return entry;
      }
    }
    return null;
  }

  @override
  String toString() => targets.first;
}
