// What the debug service needs from the IDE around it: the workspace,
// settings, editors, tasks, commands, quick input and notifications.
//
// Upstream injects a dozen services into `DebugService`, `DebugSession`,
// `ConfigurationManager` and the configuration resolver; here one host
// object stands for all of them, and every member has a harmless default
// so tests and the glue override only what they have.

import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../common/debug_utils.dart';
import '../common/repl_model.dart';
import '../session/debug_session.dart';

/// `TaskRunResult`.
enum TaskRunResult { failure, success }

/// The `debug.*` settings the debug service reads (`IDebugConfiguration`).
final class DebugSettings {
  const DebugSettings({
    this.openDebug = 'openOnDebugBreak',
    this.internalConsoleOptions = 'openOnFirstSessionStart',
    this.focusEditorOnBreak = true,
    this.autoExpandLazyVariables = 'auto',
    this.repl = const ReplSettings(),
    this.showSubSessionsInToolBar = false,
    this.allowBreakpointsEverywhere = false,
    this.saveBeforeStart = 'allEditorsInActiveGroup',
    this.inlineValues = 'auto',
    this.toolBarLocation = 'floating',
    this.showInStatusBar = 'onFirstSessionStart',
    this.closeReadonlyTabsOnEnd = false,
    this.confirmOnExit = 'never',
  });

  factory DebugSettings.fromJson(Json? json) {
    final j = json ?? const {};
    final console = j.obj('console') ?? const {};
    final lazy = j['autoExpandLazyVariables'];
    return DebugSettings(
      openDebug: j.str('openDebug') ?? 'openOnDebugBreak',
      internalConsoleOptions: j.str('internalConsoleOptions') ?? 'openOnFirstSessionStart',
      focusEditorOnBreak: j['focusEditorOnBreak'] != false,
      autoExpandLazyVariables: lazy is bool ? (lazy ? 'on' : 'off') : (lazy as String?) ?? 'auto',
      repl: ReplSettings(
        collapseIdenticalLines: console['collapseIdenticalLines'] != false,
        maximumLines: console.integer('maximumLines') ?? 10000,
      ),
      showSubSessionsInToolBar: j.flag('showSubSessionsInToolBar'),
      allowBreakpointsEverywhere: j.flag('allowBreakpointsEverywhere'),
      saveBeforeStart: j.str('saveBeforeStart') ?? 'allEditorsInActiveGroup',
      inlineValues: switch (j['inlineValues']) {
        true => 'on',
        false => 'off',
        final String s => s,
        _ => 'auto',
      },
      toolBarLocation: j.str('toolBarLocation') ?? 'floating',
      showInStatusBar: j.str('showInStatusBar') ?? 'onFirstSessionStart',
      closeReadonlyTabsOnEnd: j.flag('closeReadonlyTabsOnEnd'),
      confirmOnExit: j.str('confirmOnExit') ?? 'never',
    );
  }

  final String openDebug;
  final String internalConsoleOptions;
  final bool focusEditorOnBreak;

  /// `on`, `off` or `auto` (on with a screen reader).
  final String autoExpandLazyVariables;
  final ReplSettings repl;
  final bool showSubSessionsInToolBar;
  final bool allowBreakpointsEverywhere;
  final String saveBeforeStart;
  final String inlineValues;
  final String toolBarLocation;
  final String showInStatusBar;
  final bool closeReadonlyTabsOnEnd;
  final String confirmOnExit;
}

/// The active text editor, for `${file}`, `${lineNumber}`,
/// `${selectedText}` and for guessing a debugger.
final class DebugActiveEditor {
  const DebugActiveEditor({
    required this.uri,
    this.languageId,
    this.lineNumber,
    this.column,
    this.selectedText,
  });

  final VsUri uri;
  final String? languageId;
  final int? lineNumber;
  final int? column;
  final String? selectedText;
}

/// One choice of [DebugServiceHost.pick].
final class DebugPickItem<T> {
  const DebugPickItem(this.label, this.value, {this.description, this.separatorBefore});

  final String label;
  final String? description;
  final T value;

  /// A separator, with this label, goes above the item.
  final String? separatorBefore;
}

/// The IDE, as the debug service sees it.
class DebugServiceHost {
  String get productName => 'BaoCode';

  String get locale => 'en';

  DebugTargetOs get targetOs => DebugTargetOs.macintosh;

  bool get isWindows => targetOs == DebugTargetOs.windows;

  List<DebugWorkspaceFolder> get workspaceFolders => const [];

  /// The folder containing [uri], if any.
  DebugWorkspaceFolder? workspaceFolderOf(VsUri uri) {
    final path = uri.path;
    DebugWorkspaceFolder? best;
    for (final folder in workspaceFolders) {
      if (folder.uri.scheme != uri.scheme) continue;
      final root = folder.uri.path.endsWith('/') ? folder.uri.path : '${folder.uri.path}/';
      if (path == folder.uri.path || path.startsWith(root)) {
        if (best == null || folder.uri.path.length > best.uri.path.length) best = folder;
      }
    }
    return best;
  }

  /// The `debug` settings.
  DebugSettings settings() => const DebugSettings();

  /// A setting's value (`${config:x}`), for [folder] when given.
  Object? configurationValue(String section, {VsUri? folder}) => null;

  /// The user settings' `launch` value (`UserLaunch`).
  Json? get userLaunchConfiguration => null;

  /// The process environment (`${env:X}`).
  Map<String, String> get environment => const {};

  String? get userHome => null;

  String? get execPath => null;

  String? get appRoot => null;

  /// The install folder of an extension (`${extensionInstallFolder:id}`).
  String? extensionInstallFolder(String extensionId) => null;

  DebugActiveEditor? get activeEditor => null;

  /// Whether [uri] has unsaved changes (its breakpoints show unverified).
  bool isDirty(VsUri uri) => false;

  /// The workspace folder last active (`IHistoryService`).
  VsUri? get lastActiveWorkspaceRoot => null;

  /// The language name for an id, for messages.
  String languageName(String languageId) => languageId;

  /// When clauses of debugger contributions; true when unknown.
  bool evaluateWhen(String when) => true;

  Future<bool> requestWorkspaceTrust(String message) async => true;

  /// Activates extensions for an activation event (`onDebug`,
  /// `onDebugResolve:node`, …).
  Future<void> activateByEvent(String event) async {}

  /// Saves dirty editors before a start (`saveAllBeforeDebugStart`).
  Future<void> saveAll() async {}

  /// Runs a `preLaunchTask`/`postDebugTask` (a label or a task object) in
  /// [root]; the host decides about errors (`debug.onTaskErrors`). Null
  /// [task] is success.
  Future<TaskRunResult> runTask(DebugWorkspaceFolder? root, Object? task, {bool checkErrors = true}) async =>
      TaskRunResult.success;

  /// Cancels running pre-launch tasks.
  void cancelTasks() {}

  /// Runs a command (`${command:x}`, `inputs` of type `command`).
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) async => null;

  /// A text input (`promptString`); null when cancelled.
  Future<String?> showInputBox({String? prompt, String? value, bool password = false}) async => null;

  /// A quick pick; null when cancelled.
  Future<T?> pick<T>(List<DebugPickItem<T>> items, {String? placeholder}) async => null;

  /// Opens [uri], with [selection] revealed.
  Future<void> openEditor(
    VsUri uri, {
    DebugRange? selection,
    bool preserveFocus = true,
    bool pinned = false,
    bool sideBySide = false,
  }) async {}

  /// A source that only the adapter has (`debug:` URIs): the glue opens it
  /// with the content from [DebugSession.loadSource].
  Future<void> openDebugSource(DebugSession session, VsUri uri, {DebugRange? selection, bool preserveFocus = true}) =>
      openEditor(uri, selection: selection, preserveFocus: preserveFocus);

  void showError(String message) {}

  void notify(String message, {String? source}) {}

  Future<bool> confirm(String message) async => true;

  /// A breakpoint was hit (`openOnDebugBreak`).
  void onBreak(DebugSession session, Thread thread) {}

  void openDebugView() {}

  void openRepl() {}

  /// `runInTerminal` when no adapter factory handles it.
  Future<int?> runInTerminal(Json args, String sessionId) async => null;

  /// Asks for a debug extension for a language (the marketplace).
  Future<void> installAdditionalDebuggers(String? query) async {}
}
