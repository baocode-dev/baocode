// The perf app: BaoCodeApp, whole (the sidebar, the chat, the IDE), on
// agents that answer as a scenario says (perf_transport.dart), driven by
// input as the engine delivers it (perf_input.dart), measured as it goes
// (perf_probe.dart). Run in profile mode by tool/perf/run.dart, which
// builds it once, runs each scenario in a process of its own and compares
// the figures with a baseline; see tool/perf/README.md.
//
// Its settings come from the environment (or --dart-define, for
// `flutter run`):
// - BAOCODE_PERF_SCENARIOS: names or prefixes, comma-separated
//   ("chat.stream,ide."); all by default.
// - BAOCODE_PERF_OUT: the file the results go to, as JSON; else stdout.
// - BAOCODE_PERF_TRACE: a folder for each phase's timeline (slower);
//   BAOCODE_PERF_TRACE_DETAIL, with layouts and paints in it.
// - BAOCODE_PERF_SHOTS: a folder for a picture of the window after each
//   phase.
// - BAOCODE_PERF_REPO: the repository, for the TypeScript file the IDE
//   opens (else a generated one).
// - BAOCODE_PERF_SIZE: the window's size the app is laid out in,
//   "1024x760" (the main window's default) unless set.
//
// It keeps nothing: its data folder and project are temporary.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ViewFocusState;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:baocode/diagnostics/app_event_watch.dart';
import 'package:baocode/diagnostics/frame_watch.dart';
import 'package:baocode/diagnostics/hang_watch.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:baocode/ide/lsp/packs/language_packs.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/main.dart' show BaoCodeApp;
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/platform/memory_budget.dart';
import 'package:baocode/stash/stash_controller.dart';
import 'package:baocode/stash/stash_disk.dart';
import 'package:baocode/stash/stash_store.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/workspace.dart';

import 'perf_content.dart';
import 'perf_input.dart';
import 'perf_memory.dart';
import 'perf_probe.dart';
import 'perf_scenarios.dart';
import 'perf_trace.dart';
import 'perf_transport.dart';

const _defines = {
  'BAOCODE_PERF_SCENARIOS': String.fromEnvironment('BAOCODE_PERF_SCENARIOS'),
  'BAOCODE_PERF_OUT': String.fromEnvironment('BAOCODE_PERF_OUT'),
  'BAOCODE_PERF_TRACE': String.fromEnvironment('BAOCODE_PERF_TRACE'),
  'BAOCODE_PERF_TRACE_DETAIL': String.fromEnvironment(
    'BAOCODE_PERF_TRACE_DETAIL',
  ),
  'BAOCODE_PERF_SHOTS': String.fromEnvironment('BAOCODE_PERF_SHOTS'),
  'BAOCODE_PERF_REPO': String.fromEnvironment('BAOCODE_PERF_REPO'),
  'BAOCODE_PERF_SIZE': String.fromEnvironment('BAOCODE_PERF_SIZE'),
  'BAOCODE_PERF_SKIA_CACHE_MB': String.fromEnvironment(
    'BAOCODE_PERF_SKIA_CACHE_MB',
  ),
};

String? _setting(String name) => switch (Platform.environment[name]) {
  final value? when value.isNotEmpty => value,
  _ => _defines[name]!.isEmpty ? null : _defines[name],
};

Future<void> main() async {
  _PerfBinding();
  _isolateFromTheDesktop();
  // A run that hangs ends: the runner reads no result, and says so.
  Timer(const Duration(minutes: 15), () {
    PerfContext.log('timed out');
    exit(3);
  });
  try {
    await _run();
  } catch (error, stack) {
    PerfContext.log('failed: $error\n$stack');
    exit(1);
  }
  exit(0);
}

Future<void> _run() async {
  final temp = Directory.systemTemp.createTempSync('baocode-perf-');
  final wanted = _setting('BAOCODE_PERF_SCENARIOS')
      ?.split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final scenarios = [
    for (final scenario in perfScenarios)
      if (wanted == null ||
          wanted.any(
            (w) =>
                scenario.name == w ||
                (w.endsWith('.') && scenario.name.startsWith(w)),
          ))
        scenario,
  ];
  if (scenarios.isEmpty) throw ArgumentError('no scenario is named $wanted');

  _setUpApp(temp.path);
  // The semantics tree on throughout, as an accessibility client reading
  // the window would have it.
  if (Platform.environment['BAOCODE_PERF_SEMANTICS'] != null) {
    SemanticsBinding.instance.ensureSemantics();
  }
  final project = _makeProject('${temp.path}/project');
  final size = _size();
  PerfProbe.instance.install();
  final input = PerfInput();
  final traceDir = _setting('BAOCODE_PERF_TRACE');
  final trace = traceDir == null
      ? null
      : await PerfTrace.connect(
          traceDir,
          detail: _setting('BAOCODE_PERF_TRACE_DETAIL') != null,
        );
  await WorkbenchThemeService.instance.initialize();
  await _bringWindowFront();

  final results = <String, Object>{};
  for (final scenario in scenarios) {
    results[scenario.name] = await _runScenario(
      scenario,
      project: project,
      input: input,
      size: size,
      trace: trace,
    );
  }

  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  final report = {
    'app': {
      'mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'platform': Platform.operatingSystem,
      'os': Platform.operatingSystemVersion,
      'cpus': Platform.numberOfProcessors,
      'dart': Platform.version.split(' ').first,
      'refreshRate': PerfProbe.instance.refreshRate.round(),
      'devicePixelRatio': view?.devicePixelRatio,
      'window': view == null
          ? null
          : [
              (view.physicalSize.width / view.devicePixelRatio).round(),
              (view.physicalSize.height / view.devicePixelRatio).round(),
            ],
      'laidOutIn': view == null
          ? null
          : [
              min(
                size.width,
                view.physicalSize.width / view.devicePixelRatio,
              ).round(),
              min(
                size.height,
                view.physicalSize.height / view.devicePixelRatio,
              ).round(),
            ],
      'clockShared': PerfProbe.instance.clockShared,
      'tracing': trace != null,
      'at': DateTime.now().toUtc().toIso8601String(),
    },
    'scenarios': results,
  };
  final json = const JsonEncoder.withIndent('  ').convert(report);
  if (_setting('BAOCODE_PERF_OUT') case final out?) {
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(json);
    stdout.writeln('BAOCODE_PERF_RESULT $out');
  } else {
    stdout.writeln('BAOCODE_PERF_RESULT $json');
  }
  try {
    temp.deleteSync(recursive: true);
  } on FileSystemException {
    // A worker still has a file open: the system's temp folder is cleaned.
  }
}

/// The app's binding, but for what it would do to the machine beyond its
/// window's content, which is the installed app's as much as its own (the
/// same bundle, the same defaults): the window's size and appearance kept
/// as they are, the clipboard (what is copied is kept in
/// [PerfContext.copied], for the scenarios to check), the recent files,
/// the trash. What else it was kept from doing is logged.
class _PerfBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      _KeptMessenger(super.createBinaryMessenger());
}

class _KeptMessenger implements BinaryMessenger {
  _KeptMessenger(this._messenger);

  final BinaryMessenger _messenger;

  static const _kept = {
    'baocode/window': {
      'growWindow',
      'setAlwaysOnTop',
      'setAppearance',
      'setRecentItems',
      'trashItem',
      'windowRoom',
      'writePasteboardFiles',
      'writePasteboardImage',
    },
    'flutter/platform': {'Clipboard.setData'},
  };

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (_kept[channel] case final methods? when message != null) {
      final codec = channel == 'flutter/platform'
          ? const JSONMethodCodec()
          : const StandardMethodCodec();
      final call = codec.decodeMethodCall(message);
      if (methods.contains(call.method)) {
        switch (call.method) {
          // Room to grow as far as a pane dropped needs: the app is laid
          // out in its own size whatever the window's.
          case 'windowRoom':
            return Future.value(
              codec.encodeSuccessEnvelope({'width': 4000.0, 'height': 4000.0}),
            );
          case 'growWindow':
            PerfContext.windowGrowths++;
          case 'Clipboard.setData':
            PerfContext.copied = (call.arguments as Map?)?['text'] as String?;
            return Future.value(codec.encodeSuccessEnvelope(null));
        }
        PerfContext.log('kept from ${call.method}(${call.arguments})');
        return Future.value(codec.encodeSuccessEnvelope(null));
      }
    }
    return _messenger.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _messenger.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      _messenger.handlePlatformMessage(channel, data, callback);
}

/// Only the scenarios' input counts, and the app stays in front as far as
/// it can tell: the user's mouse over the window would hover, show
/// tooltips, scroll; another app in front would take the focus off the
/// editor (FocusManager suspends it while the app is inactive), so that
/// keys typed go nowhere. That it happened is kept, and the phase it
/// happened in marked: the window may have been covered too, and drawn
/// nothing.
void _isolateFromTheDesktop() {
  final binding = WidgetsBinding.instance;
  PerfContext.desktopPointers = binding.platformDispatcher.onPointerDataPacket;
  binding.platformDispatcher.onPointerDataPacket = (_) {};
  SystemChannels.lifecycle.setMessageHandler((message) async {
    if (message == AppLifecycleState.resumed.toString()) {
      _resume();
    } else {
      PerfProbe.instance.disturb('the app was ${message?.split('.').last}');
    }
    return null;
  });
  binding.platformDispatcher.onViewFocusChange = (event) {
    if (event.state == ViewFocusState.focused) {
      binding.handleViewFocusChanged(event);
    } else {
      PerfProbe.instance.disturb('the window lost focus');
    }
  };
  _resume();
}

void _resume() =>
    // ignore: invalid_use_of_protected_member
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

/// The app's globals as main() sets them, but for a data folder of its
/// own and the perf agents. Settings, which would fetch the upstreams
/// listed, never shows.
void _setUpApp(String temp) {
  // As the app's main() has them; BAOCODE_PERF_SKIA_CACHE_MB tries another.
  if (int.tryParse(_setting('BAOCODE_PERF_SKIA_CACHE_MB') ?? '')
      case final mb?) {
    MemoryBudget.skiaCacheBytes = mb << 20;
  }
  MemoryBudget.apply();
  DataDirectory.current = DataDirectory('$temp/data');
  // Its watchers too, their cost measured with the rest: the event log
  // in BAOCODE_PERF_EVENTS, to read, and slow from BAOCODE_PERF_SLOW_MS.
  EventLog.current = EventLog(
    Platform.environment['BAOCODE_PERF_EVENTS'] ??
        DataDirectory.current.logsDir,
  );
  // The macOS app's hang watchdog writes there too (hang.ui); the Windows
  // app keeps the folder it is told for the real app, so is not.
  if (Platform.isMacOS) {
    unawaited(shareLogsFolder(EventLog.current!.directory));
  }
  AppEventWatch.start();
  FrameWatch.start(
    slow: Duration(
      milliseconds:
          int.tryParse(Platform.environment['BAOCODE_PERF_SLOW_MS'] ?? '') ??
          250,
    ),
  );
  KernelRegistry.use([perfClaudeCode]);
  ClaudeCore.current = () => ClaudeCore.cli;
  MonacoLanguageAssets.defaultPacks = () => LanguagePackRegistry.instance;
  WorkbenchThemeService.instance.restore();
}

/// The project the agents work in and the IDE opens: real TypeScript
/// where the repository is known, generated code otherwise.
PerfProject _makeProject(String root) {
  final project = PerfProject(root);
  final content = PerfContent(7);
  Directory('$root/src').createSync(recursive: true);
  final sample = switch (_setting('BAOCODE_PERF_REPO')) {
    final repo? => File(
      '$repo/packages/bao_editor/test/fixtures/textmate/samples/bench/textModel.ts',
    ),
    null => null,
  };
  final typescript = sample != null && sample.existsSync()
      ? sample.readAsStringSync()
      : content.code('typescript', 3000);
  void write(String path, String text) {
    File(path).writeAsStringSync(text);
    project.lengths[path] = text.length;
  }

  write(project.bigFile, List.filled(3, typescript).join('\n'));
  for (final (i, path) in project.files.indexed) {
    write(path, content.code('dart', 300 + i * 40));
  }
  Directory('$root/src/huge').createSync();
  write(project.hugeFile, List.filled(30, typescript).join('\n'));
  final lines = typescript.split('\n');
  write(
    project.longLinesFile,
    [
      for (var i = 0; i < 600; i++)
        [for (var j = 0; j < 60; j++) lines[(i * 60 + j) % lines.length].trim()]
            .join(' '),
    ].join('\n'),
  );
  Directory('$root/src/many').createSync();
  for (final (i, path) in project.manyFiles.indexed) {
    write(
      path,
      [for (var j = 0; j < 1200; j++) lines[(i * 211 + j) % lines.length]]
          .join('\n'),
    );
  }
  File('$root/README.md').writeAsStringSync(content.reply(6000));
  return project;
}

Size _size() {
  final match = RegExp(r'^(\d+)x(\d+)$')
      .firstMatch(_setting('BAOCODE_PERF_SIZE') ?? '');
  return match == null
      ? const Size(1024, 760)
      : Size(double.parse(match[1]!), double.parse(match[2]!));
}

/// A window out of sight gets no frames: the main window, in front.
Future<void> _bringWindowFront() async {
  if (!Platform.isMacOS) return;
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  try {
    await const MethodChannel('baocode/windows')
        .invokeMethod('focus', view?.viewId ?? 0);
  } on Object catch (error) {
    PerfContext.log('could not bring the window to the front: $error');
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<Map<String, Object>> _runScenario(
  PerfScenario scenario, {
  required PerfProject project,
  required PerfInput input,
  required Size size,
  required PerfTrace? trace,
}) async {
  PerfContext.log('scenario ${scenario.name}');
  final workspace = Workspace(
    projects: [Project('perf-project', project.root)],
    kernels: [perfClaudeCode],
  );
  workspace.create(project: workspace.projects.first);
  // The stashes, as the app has them (in memory here): not started, which
  // would take the system-wide shortcut from the installed app.
  final stashes = StashStore(MemoryStashDisk());
  final content = PerfContent(11);
  for (var i = 0; i < 24; i++) {
    await stashes.create(
      body: '# ${content.identifier()} $i\n\n${content.reply(1200)}',
    );
  }
  final stash = StashController.current = StashController(
    store: stashes,
    workspace: workspace,
  );
  // The footprint at its highest over the whole scenario, its setting up
  // too: what the user's machine must have for it.
  var peak = PerfProcess.footprint();
  final sampling = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final footprint = PerfProcess.footprint();
    if (footprint > peak) peak = footprint;
  });
  final shotKey = GlobalKey();
  runApp(
    _PerfFrame(
      size: size,
      shotKey: shotKey,
      child: BaoCodeApp(key: UniqueKey(), workspace: workspace),
    ),
  );
  final context = PerfContext(
    scenario: scenario.name,
    workspace: workspace,
    project: project,
    input: input,
    trace: trace,
    shots: _setting('BAOCODE_PERF_SHOTS'),
    shotKey: shotKey,
  );
  final result = <String, Object>{'description': scenario.description};
  try {
    await context.settle(const Duration(milliseconds: 1500));
    await scenario.run(context);
  } catch (error, stack) {
    PerfContext.log('${scenario.name} failed: $error\n$stack');
    result['error'] = '$error';
  }
  sampling.cancel();
  result['phases'] = context.results;
  result['memoryPeakMb'] = (peak / 1048576).round();
  if (context.failedChecks.isNotEmpty) {
    result['failedChecks'] = context.failedChecks;
  }
  runApp(const SizedBox.shrink());
  await context.settle(const Duration(milliseconds: 300));
  StashController.current = null;
  stash.dispose();
  workspace.dispose();
  return result;
}

/// Lays the app out in [size] (or the window, if smaller), whatever the
/// window's: the same work on every machine, without resizing the
/// window, whose frame the installed app keeps in the same defaults.
class _PerfFrame extends StatelessWidget {
  const _PerfFrame({
    required this.size,
    required this.shotKey,
    required this.child,
  });

  final Size size;
  final GlobalKey shotKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQueryData.fromView(View.of(context));
    final laidOut = Size(
      min(size.width, media.size.width),
      min(size.height, media.size.height),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: laidOut,
        child: ClipRect(
          child: RepaintBoundary(
            key: shotKey,
            child: MediaQuery(
              data: media.copyWith(size: laidOut),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
