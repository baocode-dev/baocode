// 第十节 验证方式 2: the workbench rendered off screen (flutter_tester, no
// window) over real extension hosts running real extensions, each picture
// written to build/exthost-screens/ (BAOCODE_EXTHOST_SCREENS elsewhere) to
// be looked at one by one. What each shows is also asserted here.
//
// The workbench is pumped on the test's fake clock; the extension hosts run
// in real time, given to them between frames ([_settle]).
@Tags(['exthost'])
@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/theme/codicons.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/runtime/extension_runtime_service.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';
import 'debug_driver.dart';
import 'open_vsx_workspace.dart';

final _screens =
    Platform.environment['BAOCODE_EXTHOST_SCREENS'] ?? 'build/exthost-screens';

const _size = Size(1440, 900);

final _boundary = GlobalKey();

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final root = Platform.environment['FLUTTER_ROOT'];
    for (final (family, path) in [
      ('ScreenMono', '/System/Library/Fonts/Monaco.ttf'),
      if (root != null)
        (
          'Roboto',
          '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ),
      (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
    ]) {
      if (!File(path).existsSync()) continue;
      await (FontLoader(
        family,
      )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  final families = CodeFont.families.value;
  CodeFont.families.value = ['ScreenMono'];
  addTearDown(() => CodeFont.families.value = families);
  tester.view.physicalSize = _size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// [home] in the app's MaterialApp.
Widget _app(Widget home) => RepaintBoundary(
  key: _boundary,
  // The system material under the window.
  child: ColoredBox(
    color: const Color(0xff1e1e1e),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ),
);

/// The workbench over [w], as the app shows a project.
Future<void> _pumpWorkbench(WidgetTester tester, OpenVsxWorkspace w) async {
  await tester.pumpWidget(
    _app(
      IdeWorkbench(
        workspace: w.workspace,
        project: Project.at(w.project),
        visible: true,
        chat: const SizedBox(),
        onBack: () {},
        extensions: w.extensions,
        nativeEditorEnabled: true,
      ),
    ),
  );
  // The explorer's folders read.
  for (var i = 0; i < 5; i++) {
    await _settle(tester);
  }
}

/// Gives the extension hosts [time] in real time, then draws frames.
Future<void> _settle(
  WidgetTester tester, [
  Duration time = const Duration(milliseconds: 300),
]) async {
  await tester.runAsync(() => Future<void>.delayed(time));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Settles until [ready] holds.
Future<void> _until(
  WidgetTester tester,
  String what,
  bool Function() ready, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final end = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(end)) {
      // What it showed instead, to see why.
      await _capture(tester, 'timed_out');
      throw TimeoutException('No $what after $timeout');
    }
    await _settle(tester);
  }
}

/// Writes the workbench as it is to `<screens>/<name>.png`.
Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final render =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(p.join(_screens, '$name.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

Future<OpenVsxWorkspace> _workspace(
  WidgetTester tester, {
  List<String> extensionIds = const [],
  Map<String, String> files = const {},
  Map<String, Object?> settings = const {},
  List<String> development = const [],
  void Function(String project)? prepare,
}) async => (await tester.runAsync(
  () => OpenVsxWorkspace.create(
    extensionIds: extensionIds,
    files: files,
    settings: settings,
    development: development,
    prepare: prepare,
  ),
))!;

/// As the app closes a project: the workbench, then its extensions.
Future<void> _close(WidgetTester tester, OpenVsxWorkspace w) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(w.close);
  // Open VSX connections the views opened in fake time idle out (15s).
  await tester.pump(const Duration(seconds: 16));
}

IdeEditorState _editor(WidgetTester tester) =>
    tester.state<IdeEditorState>(find.byType(IdeEditor));

IdeWorkbenchState _workbench(WidgetTester tester) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

/// Runs the workbench's command [id], as its menus and keys do.
Future<void> _command(WidgetTester tester, String id) async {
  final command = _workbench(tester).commandsById[id];
  expect(command, isNotNull, reason: 'no command $id');
  command!.run();
  await _settle(tester);
}

bool _shows(String text) =>
    find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

/// The texts put after lines of the active editor (GitLens' blame, Error
/// Lens' messages).
List<String> _afterTexts(OpenVsxWorkspace w) {
  final view = w.workspace.editorViews.active;
  if (view == null) return const [];
  return [
    for (final d in view.features.decorations.decorations.items)
      if (d.after?.text case final text? when text.trim().isNotEmpty) text,
  ];
}

const _distance = """
interface Point {
  x: number;
  y: number;
}

/** The straight-line distance between [a] and [b]. */
function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

const start: Point = { x: 0, y: 0 };
const total = distance(start, { x: 3, y: 4 });
console.lo
""";

const _greet = """
// TODO: localize the greeting
export function greet(name: string): string {
  return "hi " + name;
}

// The recieved answer.
export const answer: number = "forty-two";
""";

const _python = """
def add(a, b):
    total = a + b
    return total


def main():
    values = []
    for i in range(5):
        values.append(add(i, 10))
    print("sum", sum(values))


main()
""";

/// [project] as a Git repository with one commit of everything in it, by
/// someone other than its user.
void _commit(String project) {
  void git(List<String> args) {
    final result = Process.runSync(
      'git',
      args,
      workingDirectory: project,
      environment: const {
        'GIT_AUTHOR_NAME': 'Accept Author',
        'GIT_AUTHOR_EMAIL': 'accept@example.com',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')}: ${result.stderr}');
    }
  }

  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.name', 'The User']);
  git(['config', 'user.email', 'user@example.com']);
  git(['config', 'commit.gpgsign', 'false']);
  git(['add', '.']);
  git(['commit', '-q', '-m', 'Add the greeting']);
}

/// The runtime's ripgrep (Todo Tree does not find upstream 1.135's).
String _ripgrep() {
  final arch = Process.runSync('uname', ['-m']).stdout.toString().trim();
  return '${exthostRuntimeDir()}/node_modules/@vscode/ripgrep-universal/bin/'
      'darwin-${arch == 'x86_64' ? 'x64' : 'arm64'}/rg';
}

/// Serves [file] at `/<name>`: [fraction] of it, then nothing until
/// closed (a download in progress).
Future<HttpServer> _stallingMirror(
  File file,
  String name,
  double fraction,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final length = file.lengthSync();
  server.listen((request) async {
    if (request.uri.path != '/$name') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response
      ..contentLength = length
      ..headers.contentType = ContentType.binary;
    await request.response.addStream(
      file.openRead(0, (length * fraction).round()),
    );
    await request.response.flush();
  });
  return server;
}

void main() {
  // The binding answers every HttpClient request with a 400: these
  // download for real.
  HttpOverrides.global = null;
  final skip = exthostRuntimeDir() == null;
  const timeout = Timeout(Duration(minutes: 10));

  testWidgets(
    'the runtime downloading in a fresh data folder',
    (tester) async {
      await _loadFonts(tester);
      final manifest = ExtHostRuntimeManifest.parse(
        File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
      );
      final asset = manifest[currentExtHostPlatform()!]!;
      final archive = File(p.join('/tmp/exthost-dl/dist', asset.file));
      if (!archive.existsSync()) {
        markTestSkipped('No ${archive.path}: run fresh_runtime_ts first');
        return;
      }
      final root = Directory.systemTemp
          .createTempSync('exthost-screens')
          .resolveSymbolicLinksSync();
      final project = p.join(root, 'proj');
      File(p.join(project, 'src/distance.ts'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_distance);
      File(p.join(project, 'tsconfig.json')).writeAsStringSync('{}');
      final mirror = (await tester.runAsync(
        () => _stallingMirror(archive, asset.file, 0.41),
      ))!;
      final data = p.join(root, 'data');
      // Made in real time, as everything the extension hosts answer.
      late ExtensionRuntimeService runtime;
      late ExtensionsApp app;
      late WorkspaceExtensions extensions;
      late IdeWorkspace workspace;
      Future<void>? starting;
      await tester.runAsync(() async {
        runtime = ExtensionRuntimeService(
          loadManifest: () async =>
              File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
          directory: p.join(data, 'exthost'),
          installer: (manifest, directory) => ExtHostRuntimeInstaller(
            manifest: manifest,
            directory: directory,
            environment: {
              ExtHostRuntimeInstaller.baseUrlVariable:
                  'http://127.0.0.1:${mirror.port}',
            },
            attempts: 1,
          ),
        );
        app = ExtensionsApp(
          userSettings: AcceptanceSettings({}),
          runtime: runtime,
          dataDirectory: data,
          coreConfiguration: () async => CoreConfiguration.fromJson(
            (jsonDecode(
              File('assets/exthost/core_configuration.json').readAsStringSync(),
            ) as Map).cast(),
            platform: CoreConfiguration.currentPlatform,
          ),
        );
        extensions = app.workspace(project);
        workspace = IdeWorkspace(
          project,
          languages: extensions.languages,
          extensionLanguageId: extensions.languageIdFor,
        );
        await extensions.attach(workspace, start: false);
        await extensions.trust!.setWorkspaceTrust(true);
        await workspace.open(p.join(project, 'src/distance.ts'));
        // Opening the project starts the host, which waits for the
        // runtime.
        starting = extensions.startHost().then((_) {}, onError: (_) {});
      });
      final previous = ExtensionRuntimeService.instance;
      ExtensionRuntimeService.instance = runtime;
      addTearDown(() => ExtensionRuntimeService.instance = previous);
      await tester.pumpWidget(
        _app(
          IdeWorkbench(
            workspace: workspace,
            project: Project.at(project),
            visible: true,
            chat: const SizedBox(),
            onBack: () {},
            extensions: extensions,
            nativeEditorEnabled: true,
          ),
        ),
      );
      await _until(
        tester,
        'the download half-way',
        () => switch (runtime.state) {
          ExtensionRuntimeDownloading(:final received, :final total) =>
            received >= total * 0.4,
          _ => false,
        },
      );
      await _settle(tester);
      expect(_shows('Downloading extension runtime 4'), isTrue);
      await _capture(tester, 'runtime_downloading_workbench');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await mirror.close(force: true);
        await starting;
        extensions.dispose();
        workspace.dispose();
        await app.dispose();
        try {
          Directory(root).deleteSync(recursive: true);
        } on FileSystemException {
          // A server still writing its logs.
        }
      });
    },
    skip: skip,
    timeout: timeout,
  );

  testWidgets(
    'TypeScript completion and hover',
    (tester) async {
      await _loadFonts(tester);
      final w = await _workspace(
        tester,
        files: {'tsconfig.json': '{}', 'src/distance.ts': _distance},
      );
      await tester.runAsync(() => w.open('src/distance.ts'));
      await _pumpWorkbench(tester, w);
      // The tab, the breadcrumbs and the explorer's row.
      await _until(
        tester,
        'the file in the explorer',
        () => find.text('distance.ts').evaluate().length >= 3,
        timeout: const Duration(seconds: 30),
      );
      final file = w.path('src/distance.ts');
      await _until(
        tester,
        'diagnostics',
        () => w.extensions.languages.diagnosticsFor(file).isNotEmpty,
      );

      // Completion after `console.lo` (⌃Space).
      await _editor(tester).revealLine(13, 11);
      await _settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _until(
        tester,
        'the suggestions',
        () => find.text('log').evaluate().isNotEmpty,
      );
      await _settle(tester);
      await _capture(tester, 'ts_completion');

      // Hover on the call of `distance`.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _editor(tester).revealLine(12, 16);
      await _settle(tester);
      _editor(tester).showHoverAtCaret();
      await _until(tester, 'the hover', () => _shows('straight-line distance'));
      await _settle(tester);
      await _capture(tester, 'ts_hover');
      await _close(tester, w);
    },
    skip: skip,
    timeout: timeout,
  );

  testWidgets(
    'the Extensions view, GitLens blame with Error Lens, and Todo Tree',
    (tester) async {
      await _loadFonts(tester);
      final w = await _workspace(
        tester,
        extensionIds: const [
          'eamodio.gitlens',
          'usernamehw.errorlens',
          'streetsidesoftware.code-spell-checker',
          'Gruntfuggly.todo-tree',
        ],
        files: {
          'tsconfig.json': '{}',
          'src/greet.ts': _greet,
          'src/report.py': '# FIXME: handle empty input\nprint(1)\n',
        },
        settings: {
          'gitlens.advanced.skipOnboarding': true,
          'todo-tree.ripgrep.ripgrep': _ripgrep(),
          // Its tree starts collapsed: the files, not their TODOs.
          'todo-tree.tree.expanded': true,
          'todo-tree.highlights.defaultHighlight': {
            'foreground': '#000000',
            'background': '#ffff00',
          },
        },
        prepare: _commit,
      );
      await tester.runAsync(() async {
        await w.open('src/greet.ts');
        for (final id in [
          'eamodio.gitlens',
          'usernamehw.errorlens',
          'streetsidesoftware.code-spell-checker',
          'Gruntfuggly.todo-tree',
        ]) {
          await w.activated(id);
        }
      });
      await _pumpWorkbench(tester, w);

      // The Extensions view: what was installed from Open VSX.
      await _command(tester, 'workbench.view.extensions');
      await _until(
        tester,
        'the installed extensions',
        () =>
            _shows('GitLens') &&
            _shows('Error Lens') &&
            _shows('Todo Tree') &&
            _shows('Code Spell Checker'),
      );
      await _settle(tester);
      await _capture(tester, 'extensions_view');

      // GitLens' blame of the line with the caret; Error Lens' messages
      // of Code Spell Checker and TypeScript.
      await _command(tester, 'workbench.view.explorer');
      await _editor(tester).revealLine(4, 3);
      await _until(tester, 'the blame and the Error Lens messages', () {
        final texts = _afterTexts(w).join('\n');
        return texts.contains('Accept Author') &&
            texts.contains('recieved') &&
            texts.contains("'string'");
      }, timeout: const Duration(minutes: 3));
      await _settle(tester, const Duration(seconds: 1));
      await _capture(tester, 'gitlens_errorlens');

      // Todo Tree's view and its highlight.
      await _command(tester, 'workbench.view.extension.todo-tree-container');
      await _until(
        tester,
        'the TODOs',
        () => _shows('localize the greeting') && _shows('handle empty input'),
      );
      await _settle(tester, const Duration(seconds: 1));
      await _capture(tester, 'todo_tree');
      await _close(tester, w);
    },
    skip: skip,
    timeout: timeout,
  );

  final python = pythonExecutable();
  testWidgets(
    'Python stopped at a breakpoint',
    (tester) async {
      await _loadFonts(tester);
      final w = await _workspace(
        tester,
        extensionIds: const ['ms-python.python'],
        files: {'main.py': _python},
        settings: {'python.defaultInterpreterPath': python},
      );
      await tester.runAsync(() => w.open('main.py'));
      await _pumpWorkbench(tester, w);
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('main.py'));
      await tester.runAsync(() async {
        await d.service.addBreakpoints(source, [
          BreakpointData(lineNumber: 3, hitCondition: '3'),
        ]);
        await d.start({
          'type': 'debugpy',
          'request': 'launch',
          'name': 'Python: main',
          'program': w.path('main.py'),
          'cwd': w.project,
          'console': 'internalConsole',
          'justMyCode': true,
        });
        final frame = await d.stopped(3, function: 'add');
        await d.watch(frame, 'a * b');
        await d.evaluate(frame, 'values if False else total');
      });
      await _command(tester, 'workbench.view.debug');
      await _until(
        tester,
        'the paused session in the views',
        () =>
            _shows('main.py') &&
            find.text('add').evaluate().isNotEmpty &&
            _shows('a * b') &&
            // The first scope's variables.
            _shows('total: 12'),
      );
      await _settle(tester, const Duration(seconds: 1));
      await _capture(tester, 'debug_breakpoint_hit');
      await tester.runAsync(() async {
        await d.service.stopSession(null);
        await d.ended();
      });
      await _close(tester, w);
    },
    skip: skip || python == null,
    timeout: timeout,
  );

  testWidgets(
    'Webview degradation',
    (tester) async {
      await _loadFonts(tester);
      final w = await _workspace(
        tester,
        files: {'notes.txt': 'A Webview view and a Webview panel.\n'},
        development: const ['test/fixtures/extensions/degradation-fixture'],
      );
      await tester.runAsync(() async {
        await w.open('notes.txt');
        await w.activated('baocode-test.degradation-fixture');
      });
      await _pumpWorkbench(tester, w);
      await _command(tester, 'workbench.view.extension.degradation');
      // Not awaited in real time alone: the workbench's frames (fake time)
      // carry part of the way.
      unawaited(
        w.extensions.commands.executeCommand('degradation.panel', []),
      );
      await _until(
        tester,
        'the placeholder and the notice',
        () => _shows('This view needs a Webview') && _shows('Fixture Panel'),
      );
      await _settle(tester);
      await _capture(tester, 'webview_degradation');
      await _close(tester, w);
    },
    skip: skip,
    timeout: timeout,
  );
}
