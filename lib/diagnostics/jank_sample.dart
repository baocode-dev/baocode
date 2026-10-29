import 'dart:io';

import 'package:bao_sampler/bao_sampler.dart';
import 'package:path/path.dart' as p;

/// Starts [executable] with [arguments], on its own: nothing waits for it.
typedef StartDetached = Future<void> Function(
  String executable,
  List<String> arguments,
);

Future<void> _startDetached(String executable, List<String> arguments) =>
    Process.start(executable, arguments, mode: ProcessStartMode.detached);

/// Samples the app for [seconds] into the file at [path], written once
/// done (nothing waits for that): whether it started.
typedef TakeSample = Future<bool> Function(String path, int seconds);

/// How this platform samples the app; null where it does not.
///
/// - macOS: its `/usr/bin/sample` run on the app (every thread; its main
///   thread is the one Dart runs on, beside it `io.flutter.raster`). The
///   Dart code's frames read `??? (in App) load address … + 0x…`.
/// - Windows and Linux: the app's UI thread sampled from within
///   (package:bao_sampler, every 20 ms); the Dart code's frames read
///   `app.so+0x…` or `libapp.so+0x…`.
///
/// `dart run tool/symbolize_jank_sample.dart` names them with the build's
/// symbols (CI's `symbols-<platform>` artifact).
TakeSample? platformSample({StartDetached? start, int? pid, String? os}) =>
    switch (os ?? Platform.operatingSystem) {
      'macos' => (path, seconds) async {
        await (start ?? _startDetached)('/usr/bin/sample', [
          '${pid ?? _ownPid()}',
          '$seconds',
          '-file',
          path,
        ]);
        return true;
      },
      'windows' || 'linux' when StackSampler.available => (
        path,
        seconds,
      ) async => StackSampler.start(path, duration: Duration(seconds: seconds)),
      _ => null,
    };

int _ownPid() => pid;

/// What the app was doing while its frames were slow one after another
/// (see JankWindow): [platformSample] for [seconds], into
/// `hangs/jank-<YYYYMMDD-HHMMSS>-<pid>.txt` of the logs [folder], which a
/// diagnostics upload sends as it does a hang report.
///
/// Not more than one each [gap] nor [most] in a run, and only the [kept]
/// newest stay: it slows the app a little more while it samples.
class JankSampler {
  /// [take] is how (default [platformSample]); null where the platform
  /// samples not.
  JankSampler(
    this.folder, {
    this.seconds = 3,
    this.gap = const Duration(minutes: 10),
    this.most = 3,
    this.kept = 5,
    DateTime Function()? clock,
    TakeSample? Function()? take,
    int? pid,
  }) : _clock = clock ?? DateTime.now,
       _take = (take ?? platformSample)(),
       _pid = pid ?? _ownPid();

  /// The logs folder (`DataDirectory.logsDir`).
  final String folder;
  final int seconds;
  final Duration gap;
  final int most;
  final int kept;

  final DateTime Function() _clock;
  final TakeSample? _take;
  final int _pid;

  int _taken = 0;
  DateTime? _last;

  /// Samples the app, unless it was just done or no more is to be: the
  /// file's name under [folder] (`hangs/jank-….txt`), written once the
  /// sample is done; else null.
  Future<String?> sample() async {
    final take = _take;
    if (take == null || _taken >= most) return null;
    final now = _clock();
    if (_last case final last? when now.difference(last) < gap) return null;
    _taken++;
    _last = now;
    final hangs = Directory(p.join(folder, 'hangs'));
    try {
      hangs.createSync(recursive: true);
      _prune(hangs);
      String two(int n) => '$n'.padLeft(2, '0');
      final name =
          'jank-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}-$_pid.txt';
      if (!await take(p.join(hangs.path, name), seconds)) return null;
      return 'hangs/$name';
    } on Object {
      return null;
    }
  }

  /// Leaves room for one more: the oldest go past [kept].
  void _prune(Directory hangs) {
    final samples = [
      for (final entity in hangs.listSync(followLinks: false))
        if (entity is File &&
            p.basename(entity.path).startsWith('jank-') &&
            entity.path.endsWith('.txt'))
          entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
    for (final old in samples.skip(kept - 1)) {
      try {
        old.deleteSync();
      } on FileSystemException {
        // Gone already.
      }
    }
  }
}
