// Runs the perf app's scenarios and reports on them: builds the app in
// profile mode, runs each scenario in a process of its own, a few times
// (round after round, so that the machine's drift spreads over all), and
// gives each figure's median, beside a baseline's if there is one.
//
//   dart run tool/perf/run.dart                   all scenarios, 3 rounds
//   dart run tool/perf/run.dart chat. ide.typing  those named, or prefixed
//   dart run tool/perf/run.dart --save-baseline   ...kept to compare with
//   dart run tool/perf/run.dart --check           fails on a regression,
//                                                 or memory over budget
//   dart run tool/perf/run.dart --trace ide.typing   timelines, for Perfetto
//
// See tool/perf/README.md for what each figure means.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _usage = '''
Usage: dart run tool/perf/run.dart [options] [scenario or prefix...]

  --repeat N          rounds of each scenario (default 3)
  --no-build          run the app built last
  --out DIR           where the results go (default build/perf/<time>)
  --baseline FILE     compare with (default build/perf/baseline.json)
  --save-baseline     keep this run's medians as the baseline
  --check             exit 1 when a figure regressed, or memory went over
                      the budget (a scenario's error or failed check always
                      does)
  --threshold PCT     how much worse counts as a regression (default 10)
  --memory-budget MB  the most memory (physical footprint) a scenario may
                      take (default 500)
  --trace             a timeline of each phase (one round; slower)
  --trace-detail      ...with every layout and paint in it too
  --shots             a picture of the window after each phase
  --size WxH          the size the app is laid out in (default 1024x760)
  --record FILE       where record.hands keeps the hand it records
  --hands FILE        the recording follow.replay plays back
  --list              the scenarios, and exit
''';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    print(_usage);
    exit(64);
  }
  final repo = File.fromUri(Platform.script).parent.parent.parent.path;
  final scenarios = _scenarios(repo);
  if (options.list) {
    for (final (name, description) in scenarios) {
      print('${name.padRight(28)} $description');
    }
    return;
  }
  final chosen = [
    for (final (name, _) in scenarios)
      if (options.names.isEmpty ||
          options.names.any(
            (n) => n == name || (n.endsWith('.') && name.startsWith(n)),
          ))
        name,
  ];
  if (chosen.isEmpty) {
    stderr.writeln(
      'No scenario is named ${options.names.join(', ')}; --list lists them.',
    );
    exit(64);
  }

  if (options.build && !await _build(repo)) exit(1);
  final app = _appPath(repo);
  if (!File(app).existsSync()) {
    stderr.writeln('No perf app at $app: run without --no-build.');
    exit(1);
  }

  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-')
      .substring(0, 19);
  final out = options.out ?? '$repo/build/perf/$stamp';
  Directory('$out/runs').createSync(recursive: true);
  final repeat = options.trace ? 1 : options.repeat;
  final runs = <String, List<Map<String, Object?>>>{};
  Map<String, Object?>? appInfo;
  final failures = <String>[];
  for (var round = 1; round <= repeat; round++) {
    for (final name in chosen) {
      stdout.write('[$round/$repeat] $name ... ');
      final watch = Stopwatch()..start();
      final result = await _runOnce(
        app,
        repo: repo,
        scenario: name,
        out: '$out/runs/$name.$round.json',
        trace: options.trace ? '$out/traces' : null,
        traceDetail: options.traceDetail,
        shots: options.shots ? '$out/shots' : null,
        size: options.size,
        record: options.record,
        hands: options.hands,
      );
      final seconds = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      if (result == null) {
        print('failed (${seconds}s)');
        failures.add('$name (round $round)');
        continue;
      }
      appInfo ??= {
        ...?result['app'] as Map<String, Object?>?,
        // The engine says which it draws with (Info.plist picks Skia on
        // macOS); not something Dart can ask.
        'renderer': ?_renderer('$out/runs/$name.$round.log'),
      };
      final scenario =
          (result['scenarios'] as Map)[name] as Map<String, Object?>;
      if (scenario['error'] case final error?) {
        print('error: $error (${seconds}s)');
        failures.add('$name (round $round): $error');
        continue;
      }
      final disturbed = {
        for (final phase in (scenario['phases'] as Map).values)
          ...?((phase as Map)['disturbed'] as List?)?.cast<String>(),
      };
      final checks = (scenario['failedChecks'] as List?)?.cast<String>();
      print(
        [
          '${seconds}s',
          '${scenario['memoryPeakMb']}MB',
          if (disturbed.isNotEmpty) 'disturbed: ${disturbed.join(', ')}',
          if (checks != null) '${checks.length} checks failed',
        ].join(', '),
      );
      for (final check in checks ?? const <String>[]) {
        print('    ✗ $check');
        failures.add('$name (round $round): $check');
      }
      (runs[name] ??= []).add({...scenario, 'disturbed': disturbed.isNotEmpty});
    }
  }

  final summary = {
    'app': appInfo,
    'rounds': repeat,
    'scenarios': {
      for (final MapEntry(key: name, value: results) in runs.entries)
        name: _summarize(results),
    },
  };
  File('$out/summary.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));

  final baselinePath = options.baseline ?? '$repo/build/perf/baseline.json';
  final baseline = !options.saveBaseline && File(baselinePath).existsSync()
      ? jsonDecode(File(baselinePath).readAsStringSync())
            as Map<String, Object?>
      : null;
  final report = _Report(
    summary,
    baseline,
    threshold: options.threshold / 100,
    memoryBudget: options.memoryBudget,
  );
  print('');
  print(report.table());
  final built = options.trace ? _whatWasBuilt('$out/traces') : '';
  if (built.isNotEmpty) print(built);
  File('$out/report.md').writeAsStringSync(
    built.isEmpty
        ? report.markdown()
        : '${report.markdown()}\n```\n$built```\n',
  );
  if (options.saveBaseline) {
    File(baselinePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    print('Baseline kept: $baselinePath');
  } else if (baseline != null) {
    print(
      'Compared with $baselinePath (${(baseline['app'] as Map?)?['at'] ?? '?'}).',
    );
  }
  print('Results: $out');
  if (options.trace) {
    print('Timelines (open in https://ui.perfetto.dev): $out/traces');
  }
  if (failures.isNotEmpty) {
    print('\nFailed:\n  ${failures.join('\n  ')}');
  }
  if (failures.isNotEmpty ||
      (options.check &&
          (report.regressions.isNotEmpty || report.overBudget.isNotEmpty))) {
    exit(1);
  }
}

class _Options {
  _Options();

  final names = <String>[];
  int repeat = 3;
  bool build = true;
  String? out;
  String? baseline;
  bool saveBaseline = false;
  bool check = false;
  double threshold = 10;
  int memoryBudget = 500;
  bool trace = false;
  bool traceDetail = false;
  bool shots = false;
  bool list = false;
  String? size;
  String? record;
  String? hands;

  static _Options? parse(List<String> arguments) {
    final options = _Options();
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      String value() => i + 1 < arguments.length
          ? arguments[++i]
          : throw const FormatException();
      try {
        switch (argument) {
          case '--repeat':
            options.repeat = int.parse(value());
          case '--no-build':
            options.build = false;
          case '--out':
            options.out = value();
          case '--baseline':
            options.baseline = value();
          case '--save-baseline':
            options.saveBaseline = true;
          case '--check':
            options.check = true;
          case '--threshold':
            options.threshold = double.parse(value());
          case '--memory-budget':
            options.memoryBudget = int.parse(value());
          case '--trace':
            options.trace = true;
          case '--trace-detail':
            options.trace = options.traceDetail = true;
          case '--shots':
            options.shots = true;
          case '--size':
            options.size = value();
          case '--record':
            options.record = File(value()).absolute.path;
          case '--hands':
            options.hands = File(value()).absolute.path;
          case '--list':
            options.list = true;
          case '-h' || '--help':
            return null;
          default:
            if (argument.startsWith('-')) return null;
            options.names.add(argument);
        }
      } on FormatException {
        return null;
      }
    }
    return options;
  }
}

/// The scenarios' names and descriptions, as perf_scenarios.dart,
/// perf_stress.dart and perf_interaction.dart list them (read here, which
/// runs without Flutter).
List<(String, String)> _scenarios(String repo) {
  final source = [
    for (final file in [
      'perf_scenarios.dart',
      'perf_stress.dart',
      'perf_interaction.dart',
      'perf_hands.dart',
    ])
      File('$repo/tool/perf/$file').readAsStringSync(),
  ].join('\n');
  return [
    for (final match in RegExp(
      r"PerfScenario\(\s*'([^']+)',\s*((?:'(?:[^'\\]|\\.)*'\s*)+)",
    ).allMatches(source))
      (
        match[1]!,
        RegExp(r"'((?:[^'\\]|\\.)*)'")
            .allMatches(match[2]!)
            .map((m) => m[1]!.replaceAll(r"\'", "'"))
            .join(),
      ),
  ];
}

Future<bool> _build(String repo) async {
  final platform = Platform.operatingSystem;
  print('Building the perf app (flutter build $platform --profile)...');
  final process = await Process.start(
    'flutter',
    ['build', platform, '--profile', '-t', 'tool/perf/perf_app.dart'],
    workingDirectory: repo,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode == 0;
}

String _appPath(String repo) {
  if (Platform.isMacOS) {
    return '$repo/build/macos/Build/Products/Profile/BaoCode.app/Contents/MacOS/BaoCode';
  }
  if (Platform.isWindows) {
    return '$repo\\build\\windows\\x64\\runner\\Profile\\baocode.exe';
  }
  return '$repo/build/linux/${_linuxArch()}/profile/bundle/baocode';
}

/// The environment macOS gives the app as it is opened (its Info.plist's
/// LSEnvironment), which running its executable here does not.
Map<String, String> _launchEnvironment(String app) {
  if (!Platform.isMacOS) return const {};
  final plist = File(app).parent.parent.uri.resolve('Info.plist').toFilePath();
  final result = Process.runSync('plutil', [
    '-extract',
    'LSEnvironment',
    'json',
    '-o',
    '-',
    plist,
  ]);
  if (result.exitCode != 0) return const {};
  return (jsonDecode(result.stdout as String) as Map).cast<String, String>();
}

String _linuxArch() {
  final machine = Process.runSync('uname', ['-m']).stdout.toString().trim();
  return machine == 'aarch64' || machine == 'arm64' ? 'arm64' : 'x64';
}

/// Runs [scenario] once; what the app wrote, or null when it did not.
Future<Map<String, Object?>?> _runOnce(
  String app, {
  required String repo,
  required String scenario,
  required String out,
  String? trace,
  bool traceDetail = false,
  String? shots,
  String? size,
  String? record,
  String? hands,
}) async {
  final log = File('${out.substring(0, out.length - 5)}.log').openWrite();
  final process = await Process.start(
    app,
    const [],
    environment: {
      ..._launchEnvironment(app),
      'BAOCODE_PERF_SCENARIOS': scenario,
      'BAOCODE_PERF_OUT': out,
      'BAOCODE_PERF_REPO': repo,
      'BAOCODE_PERF_TRACE': ?trace,
      if (traceDetail) 'BAOCODE_PERF_TRACE_DETAIL': '1',
      // The whole phase, not the last moments a ring buffer keeps (the
      // engine reads its switches from here outside release builds).
      if (trace != null) ...{
        'FLUTTER_ENGINE_SWITCHES': '1',
        'FLUTTER_ENGINE_SWITCH_1': 'endless-trace-buffer',
      },
      'BAOCODE_PERF_SHOTS': ?shots,
      'BAOCODE_PERF_SIZE': ?size,
      'BAOCODE_PERF_RECORD': ?record,
      'BAOCODE_PERF_HANDS': ?hands,
    },
  );
  process.stdout.listen(log.add);
  process.stderr.listen(log.add);
  final code = await process.exitCode.timeout(
    const Duration(minutes: 16),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  await log.close();
  final file = File(out);
  if (code != 0 || !file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

String? _renderer(String log) {
  final file = File(log);
  if (!file.existsSync()) return null;
  final text = file.readAsStringSync();
  return switch (RegExp(r'Using the (\w+) rendering backend \(([^)]+)\)')
      .firstMatch(text)) {
    final m? => '${m[1]} (${m[2]})',
    null when text.contains('Impeller') => 'Impeller',
    // The Windows engine says which only of Impeller.
    null when Platform.isWindows => 'Skia',
    null => null,
  };
}

/// [results]' medians: of the runs nothing disturbed (the app put out of
/// sight, say), if there are any.
Map<String, Object?> _summarize(List<Map<String, Object?>> results) {
  final undisturbed = [
    for (final r in results)
      if (r['disturbed'] != true) r,
  ];
  final counted = undisturbed.isEmpty ? results : undisturbed;
  return {
    'description': results.first['description'],
    'runs': counted.length,
    if (undisturbed.isEmpty) 'disturbed': true,
    'phases': _medians([
      for (final r in counted) r['phases'] as Map<String, Object?>,
    ]),
    // The highest of the runs': what the machine must have for it.
    'memoryPeakMb': [
      for (final r in counted)
        if (r['memoryPeakMb'] case final num mb) mb,
    ].fold<num>(0, (a, b) => a > b ? a : b),
    if ({
          for (final r in results)
            ...?(r['failedChecks'] as List?)?.cast<String>(),
        }
        case final checks when checks.isNotEmpty)
      'failedChecks': checks.toList(),
  };
}

/// Each number's median over [runs], the rest as the first run has it.
Map<String, Object?> _medians(List<Map<String, Object?>> runs) {
  Object? merge(List<Object?> values) {
    final first = values.first;
    if (first is Map) {
      return {
        for (final key in first.keys)
          key as String: merge([for (final v in values) (v as Map?)?[key]]),
      };
    }
    if (first is num) {
      final numbers = [
        for (final v in values)
          if (v is num) v.toDouble(),
      ]..sort();
      final median = numbers.length.isOdd
          ? numbers[numbers.length ~/ 2]
          : (numbers[numbers.length ~/ 2 - 1] + numbers[numbers.length ~/ 2]) /
                2;
      return (median * 100).roundToDouble() / 100;
    }
    return first;
  }

  return merge(runs) as Map<String, Object?>;
}

/// A figure the report shows and compares: where it is in a phase's
/// results, and how much worse it may get before that counts (below it,
/// noise).
typedef _Figure = ({String label, String path, double floor});

const List<_Figure> _figures = [
  (label: 'build p50', path: 'frames.buildMs.p50', floor: 0.3),
  (label: 'build p90', path: 'frames.buildMs.p90', floor: 0.5),
  (label: 'build p99', path: 'frames.buildMs.p99', floor: 1),
  (label: 'raster p90', path: 'frames.rasterMs.p90', floor: 0.5),
  (label: 'janky', path: 'frames.janky', floor: 2),
  (label: 'stalled ms', path: 'uiIsolate.stalledMs', floor: 20),
  (label: 'late p99', path: 'uiIsolate.lateMs.p99', floor: 2),
  (label: 'delta→frame p90', path: 'toSceneMs.delta.p90', floor: 2),
  (label: 'key→frame p90', path: 'toSceneMs.key.p90', floor: 2),
  (label: 'key→pixels p90', path: 'toRasterMs.key.p90', floor: 2),
  (label: 'scroll→frame p90', path: 'toSceneMs.scroll.p90', floor: 2),
  (label: 'action→frame p90', path: 'toSceneMs.action.p90', floor: 4),
  (label: 'drag→frame p90', path: 'toSceneMs.drag.p90', floor: 2),
  (label: 'cpu %', path: 'cpu.pctOfCore', floor: 5),
  (label: 'frames/s', path: 'frames.perSecond', floor: 5),
  (label: 'gpu %', path: 'gpu.pct', floor: 1),
  (label: 'WindowServer gpu %', path: 'gpu.windowServerPct', floor: 3),
  (label: 'mem peak MB', path: 'memoryMb.peak', floor: 20),
  (label: 'gpu MB', path: 'memoryMb.gpu', floor: 20),
  (label: 'colored ms', path: 'coloredMs', floor: 30),
  (label: 'switch p50', path: 'switchMs.p50', floor: 3),
];

num? _at(Object? value, String path) {
  for (final key in path.split('.')) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value is num ? value : null;
}

class _Report {
  _Report(
    this.summary,
    this.baseline, {
    required this.threshold,
    required this.memoryBudget,
  }) {
    final scenarios = summary['scenarios'] as Map<String, Object?>? ?? const {};
    for (final MapEntry(key: scenario, value: s) in scenarios.entries) {
      if ((s as Map)['memoryPeakMb'] case final num mb when mb > memoryBudget) {
        overBudget.add('$scenario: ${mb.round()}MB');
      }
      for (final check in (s['failedChecks'] as List?) ?? const []) {
        failedChecks.add('$scenario: $check');
      }
    }
    for (final (scenario, phase, results) in _phases(summary)) {
      // Nothing to show (no input, no text streamed, no frames the
      // scenario asked for), and still drawing more than the shared
      // clock's 30 a second: something moves at every vsync.
      final perSecond = _at(results, 'frames.perSecond');
      if (perSecond != null &&
          perSecond > restlessFrames &&
          results['toSceneMs'] == null &&
          results['forcedFrames'] != true) {
        restless.add(
          '$scenario.$phase: ${perSecond.round()} frames a second, with '
          'nothing to show for them',
        );
      }
      final base = baseline == null ? null : _phase(baseline!, scenario, phase);
      for (final figure in _figures) {
        final now = _at(results, figure.path);
        final then = base == null ? null : _at(base, figure.path);
        if (now == null || then == null) continue;
        final worse = now - then;
        if (worse > figure.floor && worse > then.abs() * threshold) {
          regressions.add('$scenario.$phase ${figure.label}: $then → $now');
        } else if (-worse > figure.floor && -worse > then.abs() * threshold) {
          improvements.add('$scenario.$phase ${figure.label}: $then → $now');
        }
      }
    }
  }

  final Map<String, Object?> summary;
  final Map<String, Object?>? baseline;
  final double threshold;

  /// The most memory a scenario may take, in MB: the app's, always.
  final int memoryBudget;
  final regressions = <String>[];
  final overBudget = <String>[];
  final failedChecks = <String>[];
  final improvements = <String>[];

  /// Phases drawing with nothing to show for it (see [restlessFrames]).
  final restless = <String>[];

  /// Frames a second a phase with nothing to show may draw: the shared
  /// clock's 30 (see StepClock), and some.
  static const restlessFrames = 40;

  static Iterable<(String, String, Map<String, Object?>)> _phases(
    Map<String, Object?> summary,
  ) sync* {
    final scenarios = summary['scenarios'] as Map<String, Object?>? ?? const {};
    for (final MapEntry(key: scenario, value: s) in scenarios.entries) {
      final phases = (s as Map)['phases'] as Map? ?? const {};
      for (final MapEntry(key: phase, value: results) in phases.entries) {
        yield (
          scenario,
          phase as String,
          (results as Map).cast<String, Object?>(),
        );
      }
    }
  }

  static Map<String, Object?>? _phase(
    Map<String, Object?> summary,
    String scenario,
    String phase,
  ) =>
      ((((summary['scenarios'] as Map?)?[scenario] as Map?)?['phases']
                  as Map?)?[phase]
              as Map?)
          ?.cast<String, Object?>();

  /// The figures each phase has, with the baseline's change beside them.
  List<(String, List<(String, String)>)> _rows() => [
    for (final (scenario, phase, results) in _phases(summary))
      (
        // Every run of it disturbed: its figures are not to be trusted.
        ((summary['scenarios'] as Map)[scenario] as Map)['disturbed'] == true
            ? '$scenario.$phase (disturbed)'
            : '$scenario.$phase',
        [
          for (final figure in _figures)
            if (_at(results, figure.path) case final now?)
              (
                figure.label,
                _cell(
                  now,
                  baseline == null
                      ? null
                      : _at(_phase(baseline!, scenario, phase), figure.path),
                  figure,
                ),
              ),
        ],
      ),
  ];

  String _cell(num now, num? then, _Figure figure) {
    final text = _format(now);
    if (then == null) return text;
    final change = now - then;
    if (change.abs() <= figure.floor ||
        (then != 0 && change.abs() <= then.abs() * threshold)) {
      return '$text (=)';
    }
    final pct = then == 0
        ? ''
        : ' ${change > 0 ? '+' : ''}${(change / then * 100).round()}%';
    return '$text (${change > 0 ? '▲' : '▼'}$pct)';
  }

  static String _format(num value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(value.abs() < 10 ? 2 : 1);

  String table() {
    final out = StringBuffer();
    final app = summary['app'] as Map?;
    if (app != null) {
      out.writeln(
        '${app['platform']} ${app['mode']}, ${app['renderer'] ?? '?'}, ${app['refreshRate']}Hz (budget '
        '${(1000 / (app['refreshRate'] as num)).toStringAsFixed(1)}ms), '
        'laid out in ${(app['laidOutIn'] as List?)?.join('×')} @${app['devicePixelRatio']}x, '
        'median of ${summary['rounds']}',
      );
    }
    for (final (name, cells) in _rows()) {
      out.writeln('\n$name');
      for (final (label, value) in cells) {
        out.writeln('  ${label.padRight(18)} $value');
      }
    }
    if (failedChecks.isNotEmpty) {
      out.writeln('\nFailed checks:\n  ${failedChecks.join('\n  ')}');
    }
    if (overBudget.isNotEmpty) {
      out.writeln(
        '\nOver the ${memoryBudget}MB memory budget:\n  ${overBudget.join('\n  ')}',
      );
    }
    if (restless.isNotEmpty) {
      out.writeln(
        '\nDrawing with nothing to show (--trace says what):\n  '
        '${restless.join('\n  ')}',
      );
    }
    if (regressions.isNotEmpty) {
      out.writeln('\nRegressed:\n  ${regressions.join('\n  ')}');
    }
    if (improvements.isNotEmpty) {
      out.writeln('\nImproved:\n  ${improvements.join('\n  ')}');
    }
    return out.toString();
  }

  String markdown() {
    final out = StringBuffer('# BaoCode perf\n\n');
    final app = summary['app'] as Map?;
    if (app != null) {
      out.writeln(
        '${app['platform']} ${app['mode']} · ${app['renderer'] ?? '?'} · ${app['os']} · ${app['cpus']} cores · '
        '${app['refreshRate']}Hz · ${(app['laidOutIn'] as List?)?.join('×')} '
        '@${app['devicePixelRatio']}x · median of ${summary['rounds']} '
        '· ${app['at']}\n',
      );
    }
    final labels = [for (final f in _figures) f.label];
    final rows = _rows();
    final used = [
      for (final label in labels)
        if (rows.any((r) => r.$2.any((c) => c.$1 == label))) label,
    ];
    out
      ..writeln('| phase | ${used.join(' | ')} |')
      ..writeln('|---|${List.filled(used.length, '---:').join('|')}|');
    for (final (name, cells) in rows) {
      final byLabel = {for (final (l, v) in cells) l: v};
      out.writeln(
        '| $name | ${[for (final l in used) byLabel[l] ?? ''].join(' | ')} |',
      );
    }
    if (failedChecks.isNotEmpty) {
      out.writeln(
        '\n**Failed checks**\n\n${failedChecks.map((r) => '- $r').join('\n')}',
      );
    }
    if (overBudget.isNotEmpty) {
      out.writeln(
        '\n**Over the ${memoryBudget}MB memory budget**\n\n'
        '${overBudget.map((r) => '- $r').join('\n')}',
      );
    }
    if (restless.isNotEmpty) {
      out.writeln(
        '\n**Drawing with nothing to show**\n\n'
        '${restless.map((r) => '- $r').join('\n')}',
      );
    }
    if (regressions.isNotEmpty) {
      out.writeln(
        '\n**Regressed**\n\n${regressions.map((r) => '- $r').join('\n')}',
      );
    }
    if (improvements.isNotEmpty) {
      out.writeln(
        '\n**Improved**\n\n${improvements.map((r) => '- $r').join('\n')}',
      );
    }
    return out.toString();
  }
}

/// For each phase's timeline in [directory], what was built anew frame by
/// frame: the outermost of the app's widgets built in each frame (each a
/// widget something changed, or under one), and in how many frames. What
/// asks for frames heads the list: a frame a vsync and a widget in nearly
/// all of them is something moving at every vsync.
String _whatWasBuilt(String directory) {
  final out = StringBuffer();
  final files =
      Directory(directory).existsSync()
            ? Directory(directory).listSync().whereType<File>().toList()
            : <File>[]
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    if (!file.path.endsWith('.json')) continue;
    final events =
        ((jsonDecode(file.readAsStringSync()) as Map)['traceEvents'] as List)
            .cast<Map<String, Object?>>();
    // The UI thread: the one that builds.
    final builds = <Object?, int>{};
    for (final e in events) {
      if (e['name'] == 'BUILD') builds[e['tid']] = (builds[e['tid']] ?? 0) + 1;
    }
    if (builds.isEmpty) continue;
    final ui = builds.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final spans =
        [
          for (final e in events)
            if (e['tid'] == ui && (e['ph'] == 'B' || e['ph'] == 'E')) e,
        ]..sort((a, b) {
          final at = (a['ts'] as num).compareTo(b['ts'] as num);
          return at != 0
              ? at
              : (a['ph'] == 'B' ? 0 : 1) - (b['ph'] == 'B' ? 0 : 1);
        });
    final frames = events
        .where((e) => e['name'] == 'Animator::BeginFrame' && e['ph'] != 'E')
        .length;
    final inFrames = <String, int>{};
    final stack = <String>[];
    int? build;
    // A frame's, over all its builds (a layout may build too).
    final roots = <String>{};
    void counted() {
      for (final root in roots) {
        inFrames[root] = (inFrames[root] ?? 0) + 1;
      }
      roots.clear();
    }

    for (final e in spans) {
      final name = e['name'] as String? ?? '?';
      if (e['ph'] == 'B') {
        if (name == 'Animator::BeginFrame') {
          counted();
        } else if (name == 'BUILD') {
          build = stack.length;
        } else if (build != null && stack.length == build + 1) {
          roots.add(name);
        }
        stack.add(name);
      } else if (stack.isNotEmpty && stack.removeLast() == 'BUILD') {
        build = null;
      }
    }
    counted();
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    out.writeln('$name: $frames frames, built anew in them:');
    final top = inFrames.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final MapEntry(:key, :value) in top.take(8)) {
      out.writeln('  ${value.toString().padLeft(6)}  $key');
    }
  }
  return out.toString();
}
