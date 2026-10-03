import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/window/code_args.dart';
import 'package:baocode/window/window_frame.dart';
import 'package:baocode/window/window_host.dart';
import 'package:baocode/workspace/workspace.dart';

/// A view of its own beside the test's, as the engine adds one per window
/// (flutter/test/widgets/multi_view_testing.dart).
class FakeView extends TestFlutterView {
  FakeView(FlutterView view, {required this.viewId})
    : super(
        view: view,
        platformDispatcher: view.platformDispatcher as TestPlatformDispatcher,
        display: view.display as TestDisplay,
      );

  @override
  final int viewId;

  @override
  void render(Scene scene, {Size? size}) {}

  @override
  void updateSemantics(SemanticsUpdate update) {}
}

/// The system's windows, as `baocode/windows` would answer: what was asked
/// is kept to look at.
class FakeWindowHost extends WindowHost {
  FakeWindowHost(this.implicit, {this.available = true});

  /// The test's view: the main window's.
  final FlutterView implicit;
  final bool available;

  WindowHostEvents? events;
  final Map<int, FakeView> views = {};
  int _next = 1;

  /// What was asked, in order: `create 1`, `focus 0`, `hide 0`…
  final List<String> log = [];
  final List<({int viewId, WindowFrame? frame, String title})> created = [];
  final Map<int, String> titles = {};
  final Map<int, bool> edited = {};
  final Map<int, WindowFrame> frames = {};
  List<ScreenArea> screenAreas = const [];
  List<WindowMenuEntry> menu = const [];
  Map<String, String> menuLabels = const {};
  bool? mainShownAtLaunch;

  @override
  Future<bool> start(WindowHostEvents events) async {
    this.events = events;
    return available;
  }

  @override
  FlutterView? viewOf(int viewId) =>
      viewId == mainViewId ? implicit : views[viewId];

  @override
  Future<int?> create({WindowFrame? frame, required String title}) async {
    final id = _next++;
    views[id] = FakeView(implicit, viewId: id);
    created.add((viewId: id, frame: frame, title: title));
    if (frame != null) frames[id] = frame;
    log.add('create $id');
    return id;
  }

  @override
  Future<FlutterView?> waitForView(int viewId) async => viewOf(viewId);

  @override
  Future<void> close(int viewId) async {
    views.remove(viewId);
    log.add('close $viewId');
  }

  @override
  Future<void> focus(int viewId) async => log.add('focus $viewId');

  @override
  Future<void> hide(int viewId) async => log.add('hide $viewId');

  @override
  Future<void> setMainShownAtLaunch(bool shown) async =>
      mainShownAtLaunch = shown;

  @override
  Future<void> quit() async => log.add('quit');

  @override
  Future<void> setTitle(int viewId, String title, {String? path}) async =>
      titles[viewId] = title;

  @override
  Future<void> setEdited(int viewId, bool edited) async =>
      this.edited[viewId] = edited;

  @override
  Future<WindowFrame?> frame(int viewId) async => frames[viewId];

  @override
  Future<void> setWidth(int viewId, double width) async =>
      log.add('setWidth $viewId ${width.round()}');

  @override
  Future<List<ScreenArea>> screens() async => screenAreas;

  @override
  Future<void> setWindowList(
    List<WindowMenuEntry> windows, {
    required Map<String, String> labels,
  }) async {
    menu = windows;
    menuLabels = labels;
  }

  /// The last focused, of those asked.
  int? get focused => log
      .where((entry) => entry.startsWith('focus '))
      .map((entry) => int.parse(entry.substring(6)))
      .lastOrNull;
}

/// A window's workbench, doing nothing but noting what it was asked.
class FakeDelegate implements WindowDelegate {
  FakeDelegate({this.context});

  BuildContext? context;
  final List<List<CodeTarget>> opened = [];
  final List<AgentThread> agents = [];
  final List<String?> folders = [];
  List<IdeDocument> unsaved = [];
  final List<IdeDocument> saved = [];
  bool terminals = false;
  IdeQuickPick? pick;
  final List<String> commands = [];

  @override
  BuildContext? get windowContext => context;

  @override
  IdeWorkspace? get ideSpace => null;

  @override
  Future<void> openFiles(List<CodeTarget> files) async => opened.add(files);

  @override
  void showAgent(AgentThread thread) => agents.add(thread);

  @override
  void showIdeFolder(String? folder) => folders.add(folder);

  @override
  Future<List<IdeDocument>> unsavedDocuments() async => unsaved;

  @override
  Future<bool> saveDocuments(List<IdeDocument> documents) async {
    saved.addAll(documents);
    unsaved = [];
    return true;
  }

  @override
  bool terminalsRunning({required bool childProcesses}) => terminals;

  @override
  void showQuickPick(IdeQuickPick pick) => this.pick = pick;

  @override
  void runCommand(String command) => commands.add(command);
}
