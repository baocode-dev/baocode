// Run as a desktop app, not with flutter test. See README.md.
// Uses the production app, catalog, editor and real Dart language server.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp/catalog/standard_lsp.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/main.dart' show BaoCodeApp;
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/app_locale.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../perf/perf_input.dart';

const _main =
    "import 'greeter.dart';\n\nvoid main() {\n"
    "  final message = greet('BaoCode');\n  print(message);\n}\n";
const _greeter = "String greet(String name) {\n  return 'Hello, \$name!';\n}\n";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = Platform.environment['BAOCODE_E2E_OUT'];
  final dart = Platform.environment['BAOCODE_E2E_DART'];
  if (directory == null || dart == null || !File(dart).existsSync()) {
    stderr.writeln(
      'Set BAOCODE_E2E_OUT and BAOCODE_E2E_DART (the SDK binary).',
    );
    exit(2);
  }
  final created = Directory(directory)..createSync(recursive: true);
  final out = Directory(created.resolveSymbolicLinksSync());
  final root = p.join(out.path, 'project');
  final data = p.join(out.path, 'data');
  DataDirectory.current = DataDirectory(data);
  Directory(p.join(root, 'lib')).createSync(recursive: true);
  File(p.join(root, 'pubspec.yaml')).writeAsStringSync(
    'name: code_navigation_e2e\nenvironment:\n  sdk: ^3.0.0\n',
  );
  final mainPath = p.join(root, 'lib', 'main.dart');
  final definitionPath = p.join(root, 'lib', 'greeter.dart');
  File(mainPath).writeAsStringSync(_main);
  File(definitionPath).writeAsStringSync(_greeter);

  // Hold initialization until after F12, making the startup race repeatable.
  // The wrapper speaks no LSP; it execs the actual SDK language server.
  final release = File(p.join(out.path, 'release-language-server'));
  if (release.existsSync()) release.deleteSync();
  final launcher = File(p.join(out.path, 'dart-language-server'))
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'while [ ! -f "\$BAOCODE_E2E_RELEASE" ]; do sleep 0.05; done\n'
      'exec "\$BAOCODE_E2E_DART" "\$@"\n',
    );
  final chmod = await Process.run('chmod', ['700', launcher.path]);
  if (chmod.exitCode != 0) throw StateError('chmod: ${chmod.stderr}');
  final settings = File(DataDirectory.current.lspSettingsFile);
  settings.parent.createSync(recursive: true);
  settings.writeAsStringSync(
    jsonEncode({
      'servers': {
        'dart': {
          'command': launcher.path,
          'args': ['language-server', '--protocol=lsp'],
          'environment': {
            'BAOCODE_E2E_DART': dart,
            'BAOCODE_E2E_RELEASE': release.path,
          },
        },
      },
    }),
  );

  final errors = <String>[];
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    presentError?.call(details);
  };
  final timeout = Timer(const Duration(minutes: 3), () {
    stderr.writeln('Code navigation desktop E2E timed out.');
    exit(1);
  });
  final boundary = GlobalKey();
  final input = PerfInput();
  final results = <Map<String, Object?>>[];
  final navigationMessages = <String>[];
  final managers = <LspManager>[];
  final workspace = Workspace(projects: [Project('navigation-e2e', root)])
    ..keepIdeView(root, {'chat': false})
    ..openIdeFolder(root)
    ..layout = WorkspaceLayout.ide;
  var failed = false;
  try {
    WorkbenchThemeService.instance.restore();
    await WorkbenchThemeService.instance.initialize();
    runApp(
      RepaintBoundary(
        key: boundary,
        child: BaoCodeApp(
          workspace: workspace,
          appLocale: AppLocale(storage: MemoryLocaleStorage(AppLocale.english)),
          languagesFor: (folder) {
            final manager = standardLspManager(folder);
            managers.add(manager);
            return manager;
          },
        ),
      ),
    );
    await _until(() => _find<IdeWorkbench>() != null, 'Fast IDE window');
    await const MethodChannel('baocode/windows').invokeMethod(
      'focus',
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    );
    final workbench = _find<IdeWorkbench>()! as StatefulElement;
    final state = workbench.state as IdeWorkbenchState;
    final ide = (workbench.widget as IdeWorkbench).workspace;
    await state.openFile(mainPath);
    await _until(
      () =>
          _find<EditorSurface>() != null &&
          managers.isNotEmpty &&
          managers.first
              .statusFor(mainPath)
              .any((s) => s.state == LanguageServerState.starting),
      'Dart server starting',
    );
    await _settle();

    final session =
        (_find<IdeEditor>()! as StatefulElement).state as IdeEditorState;
    session.languageSession!.addListener(() {
      final message = session.languageSession?.message?.text;
      if (message != null && !navigationMessages.contains(message)) {
        navigationMessages.add(message);
        stdout.writeln('Navigation message: $message');
      }
    });
    final call = _main.indexOf('greet(') + 1;
    await input.click(_pointAt(call));
    _check(
      !managers.first.supports(mainPath, LanguageRequest.definition),
      'Startup case must run before the server is ready',
    );
    await _shot(boundary, p.join(out.path, '01-before-f12.png'));
    stdout.writeln(
      'F12 focus: ${FocusManager.instance.primaryFocus?.debugLabel}',
    );
    input.press(LogicalKeyboardKey.f12, physical: PhysicalKeyboardKey.f12);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    release.writeAsStringSync('start\n');
    await _until(
      () =>
          ide.active?.path == definitionPath &&
          _surface.controller.value.selection.extentOffset == 7,
      'F12 to open greeter.dart at line 1, column 8',
    );
    await _settle();
    results.add(_position('f12-during-startup', definitionPath));
    await _shot(boundary, p.join(out.path, '02-f12-definition.png'));

    // File setup uses the workbench's normal open entrypoint. Navigation
    // itself is always dispatched through the focused keyboard or pointer.
    await state.openFile(mainPath);
    await _settle();
    await input.click(_pointAt(call));
    _modifier(true);
    try {
      await input.click(_pointAt(call));
    } finally {
      _modifier(false);
    }
    await _until(
      () =>
          ide.active?.path == definitionPath &&
          _surface.controller.value.selection.extentOffset == 7,
      'Cmd+click to open greeter.dart at line 1, column 8',
    );
    await _settle();
    results.add(_position('cmd-click-definition', definitionPath));
    await _shot(boundary, p.join(out.path, '03-cmd-click-definition.png'));

    await state.openFile(mainPath);
    await _settle();
    await input.click(_pointAt(call));
    input.press(
      LogicalKeyboardKey.f12,
      physical: PhysicalKeyboardKey.f12,
      shift: true,
    );
    await _until(
      () =>
          (_find<IdeBottomPanel>()?.widget as IdeBottomPanel?)?.tab ==
          IdePanelTab.references,
      'Shift+F12 references panel',
    );
    await _settle();
    final references = (_find<IdeBottomPanel>()!.widget as IdeBottomPanel)
        .references!
        .locations;
    _check(
      references.any((location) => location.path == mainPath) &&
          references.any((location) => location.path == definitionPath),
      'References must include the call and declaration in both files',
    );
    results.add({
      'scenario': 'shift-f12-references',
      'passed': true,
      'locations': [for (final location in references) '$location'],
    });
    await _shot(boundary, p.join(out.path, '04-references.png'));
    final row = _find<Text>(
      where: (text) =>
          text.textSpan?.toPlainText().contains('Ln 1, Col 8') ?? false,
    );
    _check(row != null, 'The declaration reference row must be visible');
    final rowBox = row!.findRenderObject()! as RenderBox;
    await input.click(rowBox.localToGlobal(rowBox.size.center(Offset.zero)));
    await _until(
      () =>
          ide.active?.path == definitionPath &&
          _surface.controller.value.selection.start == 7 &&
          _surface.controller.value.selection.end == 12,
      'reference row to open and select the declaration',
    );
    await _settle();
    results.add({
      'scenario': 'reference-row-opens-definition',
      'passed': true,
      'path': definitionPath,
      'selection': [7, 12],
      'line': 1,
      'column': 8,
    });
    await _shot(boundary, p.join(out.path, '05-reference-definition.png'));
    _check(errors.isEmpty, 'Flutter errors: ${errors.join('; ')}');
  } catch (error, stack) {
    failed = true;
    stderr.writeln('$error\n$stack');
    final probe = managers.isEmpty
        ? const <LspLocation>[]
        : await managers.first.definition(mainPath, const LspPosition(3, 20));
    final editor = _find<IdeEditor>() as StatefulElement?;
    results.add({
      'passed': false,
      'error': '$error',
      'stack': '$stack',
      'focus': FocusManager.instance.primaryFocus?.debugLabel,
      'definitionProbeAfterFailure': [
        for (final location in probe) '${location.uri}${location.revealRange}',
      ],
      'navigationMessages': navigationMessages,
      'selection': _find<EditorSurface>() == null
          ? null
          : '${_surface.controller.value.selection}',
      'navigationMessage':
          (editor?.state as IdeEditorState?)?.languageSession?.message?.text,
      'servers': [
        for (final manager in managers)
          for (final status in manager.statusFor(mainPath))
            {
              'id': status.serverId,
              'state': status.state.name,
              'message': status.message,
            },
      ],
    });
    try {
      await _shot(boundary, p.join(out.path, 'failure.png'));
    } catch (_) {}
  } finally {
    File(p.join(out.path, 'result.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'passed': !failed,
        'platform': Platform.operatingSystem,
        'dart': dart,
        'project': root,
        'scenarios': results,
        'flutterErrors': errors,
      }),
    );
    timeout.cancel();
    release.writeAsStringSync('stop\n');
    for (final manager in managers) {
      await manager.shutdown();
    }
    stdout.writeln('BAOCODE_E2E_RESULT ${p.join(out.path, 'result.json')}');
  }
  exit(failed ? 1 : 0);
}

Element? _find<T extends Widget>({bool Function(T widget)? where}) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget case final T widget when where?.call(widget) ?? true) {
      found = element;
    } else {
      element.visitChildren(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

EditorSurface get _surface => _find<EditorSurface>()!.widget as EditorSurface;

Offset _pointAt(int offset) {
  final element = _find<EditorSurface>()! as StatefulElement;
  final rect = (element.state as EditorSurfaceView).rangeRectAt(
    offset,
    offset + 1,
  );
  if (rect == null) throw StateError('Code at $offset is not visible');
  return (element.findRenderObject()! as RenderBox).localToGlobal(rect.center);
}

void _modifier(bool down) {
  final event = down
      ? KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.metaLeft,
          logicalKey: LogicalKeyboardKey.metaLeft,
          timeStamp: Duration.zero,
        )
      : KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.metaLeft,
          logicalKey: LogicalKeyboardKey.metaLeft,
          timeStamp: Duration.zero,
        );
  HardwareKeyboard.instance.handleKeyEvent(event);
  // The same focus dispatch used by the existing desktop perf input driver.
  // ignore: deprecated_member_use
  ServicesBinding.instance.keyEventManager.keyMessageHandler?.call(
    // ignore: deprecated_member_use
    KeyMessage([event], null),
  );
}

Map<String, Object?> _position(String scenario, String expectedPath) {
  final offset = _surface.controller.value.selection.extentOffset;
  final position = _surface.controller.document.snapshot.positionAtOffset(
    offset,
  );
  _check(
    position.lineNumber == 1 && position.column == 8,
    '$scenario landed at $position instead of 1:8',
  );
  return {
    'scenario': scenario,
    'passed': true,
    'path': expectedPath,
    'offset': offset,
    'line': position.lineNumber,
    'column': position.column,
  };
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _until(bool Function() ready, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(description);
    }
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> _shot(GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('No screenshot bytes');
  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
}
