import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drop.dart';
import '../ide/ide_dialog.dart';
import '../ide/ide_quick_input.dart';
import '../ide/ide_workspace.dart';
import '../l10n/l10n.dart';
import '../platform/local_paths.dart'
    if (dart.library.io) '../platform/local_paths_io.dart'
    as local;
import '../theme/codicons.dart';
import '../workspace/main_window.dart';
import '../workspace/preference_store.dart';
import '../workspace/quit_confirmation.dart';
import '../workspace/window_controls.dart';
import '../workspace/workspace.dart';
import 'code_args.dart';
import 'window_frame.dart';
import 'window_host.dart';
import 'window_settings.dart';

/// The kinds of window: the chat's, the app's main one (there is one);
/// the IDE's, one per folder (or none: its welcome); and an agent's, its
/// conversation alone (Explorer's Open with BaoCode, a new one each time).
enum AppWindowKind { chat, ide, agent }

/// What a window's workbench does for [AppWindows]: it is the one to open
/// files in it, show an agent there, and answer for what it has unsaved.
abstract interface class WindowDelegate {
  /// Where the window's dialogs show; null once it is gone.
  BuildContext? get windowContext;

  /// The IDE's workspace the window shows (that of its folder); none in the
  /// chat's window.
  IdeWorkspace? get ideSpace;

  /// Opens [files] in editors, each at its line and column.
  Future<void> openFiles(List<CodeTarget> files);

  /// Shows [thread]: as the tab of the IDE's chat, or in the chat's panes.
  void showAgent(AgentThread thread);

  /// The IDE's [folder] (its welcome, for none) in this window: what the
  /// chat's window does without windows of the IDE's own.
  void showIdeFolder(String? folder);

  /// Its documents not saved, their editors' last keys in.
  Future<List<IdeDocument>> unsavedDocuments();

  /// Saves [documents] (an untitled one asks where); whether all were.
  Future<bool> saveDocuments(List<IdeDocument> documents);

  /// Whether its terminals run: a shell alive, or ([childProcesses]) one
  /// running a command.
  bool terminalsRunning({required bool childProcesses});

  /// Shows [pick] over the window (Switch Window…).
  void showQuickPick(IdeQuickPick pick);

  /// Runs [command] (of the File menu, the IDE's) in the window.
  void runCommand(String command);
}

/// One of the app's windows.
class AppWindow {
  AppWindow._(this.kind, this.viewId, this._folder, {this.frame, this.thread});

  final AppWindowKind kind;

  /// Its view, which the engine draws it in.
  final int viewId;

  bool get isChat => kind == AppWindowKind.chat;
  bool get isIde => kind == AppWindowKind.ide;
  bool get isAgent => kind == AppWindowKind.agent;

  /// The agent an agent's window shows.
  final AgentThread? thread;

  /// The folder an IDE window shows; null for its welcome (and the chat's).
  String? get folder => _folder;
  String? _folder;

  /// Changes with its folder: what the window shows is built anew.
  int get generation => _generation;
  int _generation = 0;

  /// Where it is, as it last reported.
  WindowFrame? frame;

  /// Whether it has unsaved files.
  bool get edited => _edited;
  bool _edited = false;

  /// Whether it shows: the chat's may be closed, which hides it.
  bool get shown => _shown;
  bool _shown = true;

  WindowDelegate? get delegate => _delegate;
  WindowDelegate? _delegate;
  Completer<WindowDelegate> _ready = Completer();

  /// Its workbench, once built.
  Future<WindowDelegate?> get ready {
    if (_delegate case final delegate?) return SynchronousFuture(delegate);
    return _ready.future
        .then<WindowDelegate?>((d) => d)
        .timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  /// The workbench built in it takes it over.
  void attach(WindowDelegate delegate) {
    _delegate = delegate;
    if (!_ready.isCompleted) _ready.complete(delegate);
  }

  /// It is gone (its folder replaced, the window closed).
  void detach(WindowDelegate delegate) {
    if (!identical(_delegate, delegate)) return;
    _delegate = null;
    if (_ready.isCompleted) _ready = Completer();
  }

  void _setFolder(String? folder) {
    _folder = folder;
    _generation++;
    _edited = false;
  }

  /// Its name, as menus list it.
  String label(AppLocalizations l10n) => switch ((kind, _folder)) {
    (AppWindowKind.chat, _) => l10n.windowChatTitle,
    (AppWindowKind.agent, _) => thread!.localizedTitle(l10n),
    (_, final folder?) => _folderName(folder),
    (_, null) => l10n.windowWelcomeTitle,
  };

  /// The title the system shows: `folder — BaoCode`.
  String title(AppLocalizations l10n) => '${label(l10n)} — BaoCode';

  static String _folderName(String folder) {
    final name = p.basename(folder);
    return name.isEmpty ? folder : name;
  }

  @override
  String toString() =>
      'AppWindow(${kind.name} $viewId${_folder == null ? '' : ' $_folder'})';
}

/// One window kept between runs: an IDE's folder (null: its welcome) and
/// where it was, or the chat's place among them.
class _KeptWindow {
  const _KeptWindow({this.folder, this.frame, this.chat = false});

  final String? folder;
  final WindowFrame? frame;
  final bool chat;

  Map<String, Object?> toJson() =>
      chat ? {'chat': true} : {'folder': folder, 'frame': ?frame?.toJson()};

  static _KeptWindow? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['chat'] == true) return const _KeptWindow(chat: true);
    return _KeptWindow(
      folder: json['folder'] as String?,
      frame: WindowFrame.fromJson(json['frame']),
    );
  }
}

/// The app's windows, VS Code's way: the chat's, its main one, and one per
/// folder the IDE opens (or none), in one engine, each a view of it. The
/// agents, their sessions, the settings, the theme and the language are
/// the same in all; each window has its own navigator, dialogs and focus.
///
/// Where the system cannot open more windows (the web, a host without the
/// `baocode/windows` channel), or `window.ideWindows` says so, the IDE
/// shows in the main window, as it did before: [multi] is false and the
/// IDE's entries go to its workbench. The setting changed, the IDE moves
/// at once (see [settingsChanged]).
class AppWindows extends ChangeNotifier implements WindowHostEvents {
  AppWindows({
    required this.host,
    required this.workspace,
    required this._l10n,
    this._store,
    WindowSettings Function()? settings,
    MainWindow Function()? mainWindow,
    this._updateSetting,
    Future<bool> Function(String path)? isDirectory,
    Future<String?> Function(String path)? takeFile,
    bool Function()? hasTray,
    Future<AppExitResponse> Function()? quit,
    Future<void> Function()? nextFrame,
    bool? quitsWithLastWindow,
  }) : _settings = settings ?? (() => const WindowSettings()),
       _mainWindow = mainWindow ?? (() => MainWindow.fallback),
       _isDirectory = isDirectory ?? local.isDirectory,
       _takeFile = takeFile ?? local.takeFile,
       _hasTray = hasTray ?? (() => false),
       _quitOverride = quit,
       _nextFrame = nextFrame ?? (() => WidgetsBinding.instance.endOfFrame),
       _quitsWithLastWindow =
           quitsWithLastWindow ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    chat = AppWindow._(AppWindowKind.chat, host.mainViewId, null);
    _mru.add(chat);
  }

  /// `windows.json` in the data folder's state/, beside state.json.
  static const fileName = 'windows.json';
  static const _version = 1;

  final WindowHost host;
  final Workspace workspace;
  final AppLocalizations Function() _l10n;
  final PreferenceStore? _store;
  final WindowSettings Function() _settings;
  final MainWindow Function() _mainWindow;

  /// Writes a setting to settings.json (a switch of `window.ideWindows`
  /// cancelled is written back).
  final void Function(String key, Object? value)? _updateSetting;
  final Future<bool> Function(String path) _isDirectory;
  final Future<String?> Function(String path) _takeFile;
  final bool Function() _hasTray;
  final Future<AppExitResponse> Function()? _quitOverride;

  Future<AppExitResponse> _quit() => (_quitOverride ?? _exit)();

  /// The quit under way: the windows' closing all ask once (the taskbar's
  /// Close all windows closes each, and the last of them quits).
  Future<AppExitResponse>? _exiting;

  /// Quits the app, asked first (see main.dart's onExitRequested). On
  /// Windows the engine's way (exitApplication) ends the message loop with
  /// the windows still up, and the app hangs taking Flutter down outside
  /// it: the app is asked here, its IDE windows closed (see
  /// [closeForQuit]), and its main window closed in the loop (see
  /// app_windows.h' kQuitMessage).
  Future<AppExitResponse> _exit() {
    final binding = ServicesBinding.instance;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return binding.exitApplication(AppExitType.cancelable);
    }
    return _exiting ??= () async {
      try {
        final response = await binding.handleRequestAppExit();
        if (response == AppExitResponse.exit) {
          await closeForQuit();
          await host.quit();
        }
        return response;
      } finally {
        _exiting = null;
      }
    }();
  }

  /// Whether the app is going: what is kept for the next launch stays as
  /// it was before (see [closeForQuit]).
  bool _quitting = false;

  /// The IDE's windows (and the agents') closed as the app goes
  /// (Windows'), as [requestClose] closes one: their widgets first, then
  /// their views. Left to the main window's going, a view the engine still
  /// draws goes in the middle of it, and the engine, waiting for it to be
  /// let go of, hangs the app. They are kept for the next launch as they
  /// were.
  @visibleForTesting
  Future<void> closeForQuit() async {
    if (_ide.isEmpty && _agents.isEmpty) return;
    _quitting = true;
    final closing = [..._ide, ..._agents];
    _ide.clear();
    _agents.clear();
    notifyListeners();
    await _nextFrame();
    for (final window in closing) {
      WindowControls.stopListening(window.viewId);
      FileDrops.stopListening(window.viewId);
      await host.close(window.viewId);
    }
  }

  final Future<void> Function() _nextFrame;

  /// Windows': the app quits as its last window closes (the tray aside).
  /// macOS' stays, the Dock's icon opening the chat's window again.
  final bool _quitsWithLastWindow;

  /// The chat's window: the main one, always there (hidden when closed).
  late final AppWindow chat;

  /// Whether the system opens the app's windows for it: the chat's is
  /// then one of them, which the app closes, hides and brings in front.
  bool get started => _started;
  bool _started = false;

  /// Whether the IDE opens windows of its own (`window.ideWindows`); else
  /// it shows in the main one.
  bool get multi => _started && _separate;
  bool _separate = true;

  /// All of them, the one in front first.
  List<AppWindow> get windows => List.unmodifiable(_mru);
  final List<AppWindow> _mru = [];

  /// The IDE's, in the order they opened (as menus list them).
  List<AppWindow> get ideWindows => List.unmodifiable(_ide);
  final List<AppWindow> _ide = [];

  /// The agents', in the order they opened.
  List<AppWindow> get agentWindows => List.unmodifiable(_agents);
  final List<AppWindow> _agents = [];

  AppWindow? windowOf(int viewId) =>
      _mru.where((window) => window.viewId == viewId).firstOrNull;

  /// The IDE's window of [folder], if one is open.
  AppWindow? windowFor(String folder) {
    final key = _key(folder);
    return _ide
        .where((w) => w.folder != null && _key(w.folder!) == key)
        .firstOrNull;
  }

  /// The window in front: the keyboard's, where dialogs about the app ask.
  AppWindow get active =>
      _mru.where((window) => window.shown).firstOrNull ?? chat;

  /// The IDE's window last in front.
  AppWindow? get recentIde => _mru.where((window) => window.isIde).firstOrNull;

  static String _key(String path) => p.canonicalize(path);

  /// The window of [folder] that has [path] in it (the deepest folder).
  AppWindow? _containing(String path) {
    AppWindow? best;
    for (final window in _ide) {
      final folder = window.folder;
      if (folder == null) continue;
      if (!p.equals(folder, path) && !p.isWithin(folder, path)) continue;
      if (best == null || best.folder!.length < folder.length) best = window;
    }
    return best;
  }

  // --- Start -----------------------------------------------------------------

  /// Asks the system whether windows can be opened; from then on the IDE's
  /// entries (Open in Fast Ide, the sidebar's…) open them.
  Future<bool> start() async {
    _started = await host.start(this);
    _separate = _settings().ideWindows == IdeWindows.separate;
    if (multi) {
      workspace.ideWindows = _routeIde;
      _syncWorkspace();
    }
    return _started;
  }

  ({List<_KeptWindow> windows, bool chatShown})? _launch;

  /// Whether the chat's window shows at launch, decided before the app
  /// shows (see [prepareLaunch]).
  bool get chatShownAtLaunch => _launch?.chatShown ?? true;

  /// Reads what to open at launch, before the first frame: whether the
  /// chat's window shows (the system knows it before the app runs: told
  /// here for the next launch, and for this one where it is not too
  /// late) and which IDE windows open again ([restore] opens them).
  ///
  /// The app opens to the chat or to the IDE, never both:
  /// `workbench.mainWindow` says which, by default where it was left (the
  /// window in front at the last quit). To the chat, its window alone; to
  /// the IDE, the IDE's windows `window.restoreWindows` says (or an empty
  /// one), the chat's hidden. The IDE's folder that showed in the main
  /// window (the first run with windows, or `window.ideWindows` changed
  /// meanwhile) opens in a window of its own.
  ///
  /// With the IDE in the main window, only it shows; the IDE's window last
  /// in front, if any were left, gives it its folder.
  ///
  /// Started for a [request] (Explorer's Open with BaoCode or Fast Ide, the
  /// `code` command), it opens to that alone, at once, in a window of its
  /// own: the agent's (see [openAgent]), else what the request opens;
  /// nothing of the last run, the chat's window hidden.
  Future<void> prepareLaunch({
    LaunchRequest request = LaunchRequest.none,
  }) async {
    if (!_started) return;
    if (request == LaunchRequest.agent ||
        (_separate && request == LaunchRequest.ide)) {
      _wasInIde = request == LaunchRequest.ide;
      _launch = (windows: const [_KeptWindow(chat: true)], chatShown: false);
      chat._shown = false;
      _syncWorkspace();
      // Read for this launch as well: after Dart starts, on Windows.
      await host.setMainShownAtLaunch(false);
      _mainShownNext = false;
      return;
    }
    final kept = await _store?.read() ?? const <String, Object?>{};
    if (!_separate) return _prepareMainOnly(kept);
    final old = workspace.takeSingleWindowIde();
    final versioned = kept['version'] != null;
    final ide = switch (_mainWindow()) {
      MainWindow.chat => false,
      MainWindow.ide => true,
      MainWindow.last =>
        versioned
            ? (kept['leftIn'] ??
                      (kept['chatShown'] == false ? 'ide' : 'chat')) ==
                  'ide'
            : old.shown,
    };
    final windows = <_KeptWindow>[];
    if (ide) {
      if (versioned) {
        final restore = _settings().restoreWindows;
        for (final json in kept['windows'] as List<Object?>? ?? const []) {
          final window = _KeptWindow.fromJson(json);
          if (window == null || window.chat) continue;
          final folder = window.folder;
          final keep = switch (restore) {
            RestoreWindows.all => true,
            RestoreWindows.folders => folder != null,
            RestoreWindows.one => windows.isEmpty,
            RestoreWindows.none => false,
          };
          if (!keep) continue;
          // A folder gone (deleted, a drive unplugged) is not opened.
          if (folder != null && !await _isDirectory(folder)) continue;
          windows.add(window);
        }
      }
      if (old.folder case final folder?
          when (old.shown || !versioned) &&
              !windows.any((w) => w.folder == folder) &&
              await _isDirectory(folder)) {
        windows.insert(0, _KeptWindow(folder: folder));
      }
      // Never no window at all.
      if (windows.isEmpty) windows.add(const _KeptWindow());
    }
    windows.add(const _KeptWindow(chat: true));
    final chatShown = !ide;
    _wasInIde = ide;
    _launch = (windows: windows, chatShown: chatShown);
    chat._shown = chatShown;
    _syncWorkspace();
    await host.setMainShownAtLaunch(chatShown);
    _mainShownNext = chatShown;
  }

  Future<void> _prepareMainOnly(Map<String, Object?> kept) async {
    final front = [
      for (final json in kept['windows'] as List<Object?>? ?? const [])
        ?_KeptWindow.fromJson(json),
    ].where((w) => !w.chat && w.folder != null).firstOrNull;
    if (front?.folder case final folder?
        when workspace.ideFolder == null && await _isDirectory(folder)) {
      workspace.openIdeFolder(folder);
    }
    _launch = (windows: const [_KeptWindow(chat: true)], chatShown: true);
    await host.setMainShownAtLaunch(true);
    _mainShownNext = true;
  }

  /// Opens the windows [prepareLaunch] read, back to front, each where it
  /// was (moved back onto a screen, if that one is gone); the one in front
  /// at the last quit is again.
  Future<void> restore() async {
    final launch = _launch;
    if (launch == null || !_started) return;
    _launch = null;
    await _serial(() async {
      if (!launch.chatShown) await host.hide(chat.viewId);
      final screens = await host.screens();
      for (final kept in launch.windows.reversed) {
        if (kept.chat) {
          if (launch.chatShown) _focus(chat);
          continue;
        }
        await _create(kept.folder, frame: kept.frame?.fit(screens));
      }
      final front = _mru.where((w) => w.shown).firstOrNull;
      if (front != null) _focus(front);
    });
    _save();
  }

  // --- Opening ---------------------------------------------------------------

  /// One opening at a time: a second waits for the window the first opens.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// The Workspace's IDE entries (Open in Fast Ide, the sidebar's, a
  /// changed file clicked): [folder]'s window, [thread] its chat's tab.
  void _routeIde(String? folder, AgentThread? thread) =>
      unawaited(showFolder(folder, thread: thread));

  /// The IDE's window of [folder], opened if it is not, in front; with
  /// [thread] the tab of its chat and [files] in editors. Without a
  /// folder, the IDE's window last in front (an empty one, if there is
  /// none, or with [newWindow]).
  Future<AppWindow?> showFolder(
    String? folder, {
    AgentThread? thread,
    List<CodeTarget> files = const [],
    bool newWindow = false,
  }) {
    if (!multi) return _showInMain(folder, thread: thread, files: files);
    return _serial(() async {
      var window = folder == null
          ? (newWindow ? null : recentIde)
          : windowFor(folder);
      if (window == null) {
        window = await _create(folder);
      } else {
        _focus(window);
        if (folder != null) workspace.noteIdeFolder(folder);
      }
      if (window == null) return null;
      if (thread != null || files.isNotEmpty) {
        final delegate = await window.ready;
        if (thread != null) delegate?.showAgent(thread);
        if (files.isNotEmpty) await delegate?.openFiles(files);
      }
      return window;
    });
  }

  /// Without windows of its own, the IDE shows in the main one (in front,
  /// shown again if it was closed).
  Future<AppWindow?> _showInMain(
    String? folder, {
    AgentThread? thread,
    List<CodeTarget> files = const [],
  }) async {
    if (_started) _focus(chat);
    final delegate = await chat.ready;
    if (delegate == null) return null;
    if (thread != null) {
      workspace.openInIde(thread);
    } else {
      delegate.showIdeFolder(folder);
    }
    if (files.isNotEmpty) await delegate.openFiles(files);
    return chat;
  }

  /// New Window: an empty one. With the IDE in the main window, its empty
  /// window there (the folder it had stays among the recent).
  Future<AppWindow?> newWindow() {
    if (!multi) {
      workspace.closeIdeFolder();
      return _showInMain(null);
    }
    return showFolder(null, newWindow: true);
  }

  /// Opens a window of the IDE's for [folder] (its welcome, for none): at
  /// the size `window.newWindowDimensions` says, shown once it is drawn.
  Future<AppWindow?> _create(String? folder, {WindowFrame? frame}) async {
    if (folder != null) workspace.noteIdeFolder(folder);
    final l10n = _l10n();
    final window = AppWindow._(AppWindowKind.ide, -1, folder);
    final viewId = await host.create(
      frame: frame ?? await _newFrame(),
      title: window.title(l10n),
    );
    if (viewId == null) return null;
    if (await host.waitForView(viewId) == null) {
      await host.close(viewId);
      return null;
    }
    final created = AppWindow._(
      AppWindowKind.ide,
      viewId,
      folder,
      frame: frame,
    );
    _ide.add(created);
    _mru.insert(0, created);
    _changed();
    // Shown once it has something to show.
    await _nextFrame();
    _focus(created);
    unawaited(host.setTitle(viewId, created.title(l10n), path: folder));
    return created;
  }

  /// Where a new window goes: `default`, where the system puts one;
  /// `inherit`, the size of the one in front, below and right of it;
  /// `maximized` and `fullscreen` so.
  Future<WindowFrame?> _newFrame() async {
    final dimensions = _settings().newWindowDimensions;
    if (dimensions == NewWindowDimensions.defaultSize) return null;
    final front = active;
    final frame = await host.frame(front.viewId) ?? front.frame;
    if (frame == null) return null;
    final screens = await host.screens();
    return switch (dimensions) {
      NewWindowDimensions.inherit => frame.cascade(screens),
      NewWindowDimensions.maximized => frame.copyWith(
        maximized: true,
        fullscreen: false,
      ),
      NewWindowDimensions.fullscreen => frame.copyWith(fullscreen: true),
      NewWindowDimensions.defaultSize => null,
    };
  }

  /// [window] in front, the keyboard's.
  void focus(AppWindow window) {
    if (!_started) return;
    _focus(window);
    _save();
  }

  void _focus(AppWindow window) {
    _toFront(window);
    unawaited(host.focus(window.viewId));
  }

  void _toFront(AppWindow window) {
    final wasShown = window.shown;
    window._shown = true;
    WindowControls.activeViewId = window.viewId;
    if (identical(_mru.firstOrNull, window) && wasShown) return;
    _mru
      ..remove(window)
      ..insert(0, window);
    _changed();
  }

  /// Shows the chat's window again (Show Chat Window; the Dock's icon).
  void showChat() {
    if (!_started) return;
    focus(chat);
  }

  /// Opens [files]: each in the window whose folder has it, else in [from]
  /// (where they were dropped), else the IDE's window last in front, else a
  /// new one; with [newWindow], all in a new one, with [reuse], in the one
  /// last in front.
  Future<void> openFiles(
    List<CodeTarget> files, {
    bool newWindow = false,
    bool reuse = false,
    AppWindow? from,
  }) async {
    if (files.isEmpty) return;
    if (!multi) {
      await _showInMain(null, files: files);
      return;
    }
    if (newWindow) {
      await showFolder(null, files: files, newWindow: true);
      return;
    }
    final groups = <AppWindow?, List<CodeTarget>>{};
    for (final file in files) {
      final window = reuse
          ? recentIde
          : _containing(file.path) ?? from ?? recentIde;
      (groups[window] ??= []).add(file);
    }
    for (final MapEntry(key: window, value: targets) in groups.entries) {
      if (window == null) {
        await showFolder(null, files: targets, newWindow: true);
        continue;
      }
      await _serial(() async {
        if (window.folder == null && !_ide.contains(window)) return;
        _focus(window);
        for (final target in targets) {
          workspace.addRecentFile(target.path);
        }
        final delegate = await window.ready;
        await delegate?.openFiles(targets);
      });
    }
  }

  /// What the `code` command asks (see [CodeArgs]).
  Future<void> handleCode(CodeArgs args) async {
    final folders = <CodeTarget>[], files = <CodeTarget>[];
    for (final target in args.paths) {
      (await _isDirectory(target.path) ? folders : files).add(target);
    }
    if (folders.isEmpty && files.isEmpty) {
      if (!multi) {
        await _showInMain(null);
        return;
      }
      await showFolder(null, newWindow: args.newWindow);
      return;
    }
    for (final folder in folders) {
      final reuse = args.reuseWindow ? recentIde : null;
      if (reuse != null && windowFor(folder.path) == null) {
        await replaceFolder(reuse, folder.path);
      } else {
        await showFolder(folder.path);
      }
    }
    await openFiles(
      files,
      newWindow: args.newWindow && folders.isEmpty,
      reuse: args.reuseWindow,
    );
  }

  /// What the system asks to open: a request of the `code` command (on
  /// Windows, its arguments; on macOS, the file its script left), Open
  /// with BaoCode's ([openAgent]), or paths (Finder's Open With, the Dock's
  /// icon, the File menu's Open Recent), as `code` would open them.
  Future<void> openRequested(List<String> paths) async {
    if (paths.firstOrNull == CodeArgs.agentRequestMarker) {
      await openAgent(paths.sublist(1));
      return;
    }
    if (CodeArgs.isRequest(paths)) {
      await handleCode(CodeArgs.fromRequest(paths));
      return;
    }
    final plain = <String>[];
    for (final path in paths) {
      if (!path.endsWith(CodeArgs.requestFileSuffix)) {
        plain.add(path);
        continue;
      }
      final request = await _takeFile(path);
      if (request != null) await handleCode(CodeArgs.fromRequestFile(request));
    }
    if (plain.isEmpty) return;
    await handleCode(
      CodeArgs(paths: [for (final path in plain) CodeTarget(path)]),
    );
  }

  /// How wide an agent's window opens (see [openAgent]): the
  /// conversation alone.
  static const agentWidth = 520.0;

  /// Explorer's Open with BaoCode: a new agent, ready to type to, in a new
  /// window of its own each time ([agentWidth] wide; without windows, in
  /// the chat's). A folder is its project (opened as one if it was not); a
  /// file goes in the composer as if pasted, the agent in the project it is
  /// in, else in its folder.
  Future<AgentThread?> openAgent(List<String> paths) async {
    String? folder;
    final files = <ComposerFile>[];
    for (final path in paths) {
      final directory = await _isDirectory(path);
      if (directory && folder == null) {
        folder = path;
      } else {
        files.add(ComposerFile(path, directory: directory));
      }
    }
    if (folder == null && files.isEmpty) return null;
    folder ??= _projectOf(files.first.path) ?? p.dirname(files.first.path);
    if (!_started) {
      final thread = await workspace.openFolder(folder);
      thread.session.draft.insertFiles(files);
      workspace.layout = WorkspaceLayout.chat;
      (await chat.ready)?.showAgent(thread);
      return thread;
    }
    final thread = workspace.newWindowAgent(folder);
    thread.session.draft.insertFiles(files);
    final window = await _serial(() => _createAgent(thread));
    if (window == null) workspace.closeWindowAgent(thread);
    return window == null ? null : thread;
  }

  /// Opens a window of [thread]'s own, [agentWidth] wide.
  Future<AppWindow?> _createAgent(AgentThread thread) async {
    final l10n = _l10n();
    final pending = AppWindow._(AppWindowKind.agent, -1, null, thread: thread);
    final viewId = await host.create(
      title: pending.title(l10n),
      width: agentWidth,
    );
    if (viewId == null) return null;
    if (await host.waitForView(viewId) == null) {
      await host.close(viewId);
      return null;
    }
    final created = AppWindow._(
      AppWindowKind.agent,
      viewId,
      null,
      thread: thread,
    );
    _agents.add(created);
    _mru.insert(0, created);
    _titles[created] = pending.title(l10n);
    _watchAgents();
    _changed();
    // Shown once it has something to show.
    await _nextFrame();
    _focus(created);
    return created;
  }

  /// The agents' windows' titles, as last set: an agent titled after its
  /// first message (or renamed), its window's title follows.
  final Map<AppWindow, String> _titles = {};
  bool _watching = false;

  void _watchAgents() {
    if (_watching) return;
    _watching = true;
    workspace.addListener(_agentsChanged);
  }

  void _agentsChanged() {
    if (!_started) return;
    final l10n = _l10n();
    var retitled = false;
    for (final window in [..._agents]) {
      // Deleted (or dropped) meanwhile: its window goes.
      if (!workspace.threads.contains(window.thread)) {
        unawaited(_remove(window));
        continue;
      }
      final title = window.title(l10n);
      if (_titles[window] == title) continue;
      _titles[window] = title;
      unawaited(host.setTitle(window.viewId, title));
      retitled = true;
    }
    _titles.removeWhere((window, _) => !_agents.contains(window));
    if (retitled) _syncMenus();
  }

  @override
  void dispose() {
    if (_watching) workspace.removeListener(_agentsChanged);
    super.dispose();
  }

  /// The project [path] is in (the deepest), if any.
  String? _projectOf(String path) {
    String? best;
    for (final project in workspace.projects) {
      if (!p.isWithin(project.path, path)) continue;
      if (best == null || best.length < project.path.length) {
        best = project.path;
      }
    }
    return best;
  }

  /// Files dragged from Finder or Explorer onto [viewId]'s window, where no
  /// part of it took them: a folder opens its window, files as the `code`
  /// command opens them (in the window they were dropped on, unless one
  /// has their folder).
  bool dropped(int viewId, List<ComposerFile> files) {
    if (files.isEmpty) return false;
    final window = windowOf(viewId);
    unawaited(() async {
      for (final folder in files.where((file) => file.directory)) {
        await showFolder(folder.path);
      }
      await openFiles([
        for (final file in files)
          if (!file.directory) CodeTarget(file.path),
      ], from: window != null && window.isIde ? window : null);
    }());
    return true;
  }

  /// Open Folder… in [window]: [folder] in its place (its unsaved files
  /// asked about first); a window that has it already comes in front.
  /// None: Close Folder, its welcome.
  Future<void> replaceFolder(AppWindow window, String? folder) async {
    if (!multi || !window.isIde) {
      await showFolder(folder);
      return;
    }
    if (folder != null) {
      if (windowFor(folder) case final open?) {
        if (!identical(open, window)) focus(open);
        return;
      }
    }
    if (folder == null && window.folder == null) return;
    if (!await _confirmUnsaved([window])) return;
    if (folder != null) workspace.noteIdeFolder(folder);
    if (window.delegate case final delegate?) window.detach(delegate);
    window._setFolder(folder);
    _focus(window);
    unawaited(
      host.setTitle(window.viewId, window.title(_l10n()), path: folder),
    );
    unawaited(host.setEdited(window.viewId, false));
    _changed();
    _save();
  }

  // --- Closing and quitting ----------------------------------------------------

  final Set<AppWindow> _closing = {};

  /// Closes [window] as its close button, Close Window or ⌘W do
  /// ([byKeyboard] for a shortcut), asking first as the settings say: the
  /// chat's hides; an agent's goes (the agent goes on, in the sidebar); an
  /// IDE's asks about its unsaved files and its running terminals, and
  /// goes with its editors, terminals and language servers. Whether it
  /// closed.
  Future<bool> requestClose(AppWindow window, {bool byKeyboard = false}) async {
    if (!_started) return false;
    if (window.isChat) {
      await _hideChat();
      return true;
    }
    if (window.isAgent) {
      if (!_agents.contains(window)) return false;
      await _remove(window);
      return true;
    }
    if (!_ide.contains(window) || !_closing.add(window)) return false;
    try {
      final settings = _settings();
      final delegate = window.delegate;
      final context = delegate?.windowContext;
      if (context != null && context.mounted) {
        if (settings.confirmBeforeClose.asks(byKeyboard: byKeyboard)) {
          _focus(window);
          final l10n = context.l10n;
          final choice = await showIdeDialog(
            context,
            message: l10n.windowConfirmClose,
            buttons: [l10n.cmdCloseWindow],
            type: IdeDialogType.question,
          );
          if (choice != 0) return false;
        }
        if (!await _confirmUnsaved([window])) return false;
        final confirm = settings.terminalConfirmOnExit;
        if (confirm != TerminalConfirmOnExit.never &&
            delegate!.terminalsRunning(
              childProcesses:
                  confirm == TerminalConfirmOnExit.hasChildProcesses,
            ) &&
            context.mounted) {
          _focus(window);
          final l10n = context.l10n;
          final choice = await showIdeDialog(
            context,
            message: l10n.windowTerminateTerminals,
            buttons: [l10n.windowTerminate],
          );
          if (choice != 0) return false;
        }
      }
      await _remove(window);
      return true;
    } finally {
      _closing.remove(window);
    }
  }

  Future<void> _remove(AppWindow window) async {
    _ide.remove(window);
    _agents.remove(window);
    _mru.remove(window);
    _changed();
    // Its view's widgets go first, then the view.
    await _nextFrame();
    WindowControls.stopListening(window.viewId);
    FileDrops.stopListening(window.viewId);
    await host.close(window.viewId);
    if (window.thread case final thread?) workspace.closeWindowAgent(thread);
    _save();
    if (_mru.firstWhereOrNull((w) => w.shown) case final front?) {
      WindowControls.activeViewId = front.viewId;
    }
    await _quitIfNoneShows();
  }

  Future<void> _hideChat() async {
    chat._shown = false;
    _mru
      ..remove(chat)
      ..add(chat);
    _changed();
    await host.hide(chat.viewId);
    _save();
    final front = active;
    if (front.shown) {
      WindowControls.activeViewId = front.viewId;
      if (!front.isChat) unawaited(host.focus(front.viewId));
    }
    await _quitIfNoneShows();
  }

  /// On Windows, the app goes with its last window, unless the tray keeps
  /// it; quitting cancelled, the chat's window shows again.
  Future<void> _quitIfNoneShows() async {
    if (!_quitsWithLastWindow || _hasTray()) return;
    if (_mru.any((w) => w.shown)) return;
    if (await _quit() == AppExitResponse.cancel) showChat();
  }

  /// Saves, or not, the unsaved files of [windows], asked once for all of
  /// them in the window in front; whether to go on (not cancelled, all
  /// saved that were to be).
  Future<bool> _confirmUnsaved(List<AppWindow> windows) async {
    final unsaved = <(WindowDelegate, List<IdeDocument>)>[];
    for (final window in windows) {
      final delegate = window.delegate;
      if (delegate == null) continue;
      final documents = await delegate.unsavedDocuments();
      if (documents.isNotEmpty) unsaved.add((delegate, documents));
    }
    if (unsaved.isEmpty) return true;
    final asker = windows.length == 1 ? windows.single : active;
    final context = (asker.delegate ?? unsaved.first.$1).windowContext;
    if (context == null || !context.mounted) return true;
    if (_started) _focus(asker);
    final l10n = context.l10n;
    final documents = [for (final (_, docs) in unsaved) ...docs];
    final choice = await showIdeDialog(
      context,
      message: documents.length == 1
          ? l10n.wbConfirmSave(documents.single.name)
          : l10n.windowSaveChanges(documents.length),
      detail: documents.length == 1
          ? l10n.explorerChangesLost
          : [
              for (final doc in documents) doc.name,
              '',
              l10n.explorerChangesLost,
            ].join('\n'),
      buttons: [
        documents.length == 1 ? l10n.commonSave : l10n.windowSaveAll,
        l10n.commonDontSave,
      ],
    );
    switch (choice) {
      case 0:
        for (final (delegate, docs) in unsaved) {
          if (!await delegate.saveDocuments(docs)) return false;
        }
        return true;
      case 1:
        return true;
      default:
        return false;
    }
  }

  /// Before the app quits (⌘Q, the tray's Quit, logging out): the unsaved
  /// files of all windows asked about at once, then (as before windows)
  /// whether to quit with agents or terminals at work; asked in the window
  /// in front, shown for it (the app may be in the tray). With nothing at
  /// work, the Quit (the tray's, the last window's close button) is enough.
  Future<bool> confirmQuit() async {
    final windows = [..._ide, chat];
    if (!await _confirmUnsaved(windows)) return false;
    final working =
        workspace.threads.any(
          (thread) =>
              !thread.archived &&
              (thread.status == ThreadStatus.running ||
                  thread.status == ThreadStatus.needsInput),
        ) ||
        windows.any(
          (window) =>
              window.delegate?.terminalsRunning(childProcesses: true) ?? false,
        );
    if (!working) return true;
    final asker = active.delegate?.windowContext != null ? active : chat;
    final context = asker.delegate?.windowContext;
    if (context == null || !context.mounted) return true;
    if (_started) _focus(asker);
    return QuitConfirmation.confirm(context);
  }

  // --- The system's events -----------------------------------------------------

  @override
  void windowCloseRequested(int viewId) {
    if (windowOf(viewId) case final window?) {
      unawaited(requestClose(window));
    }
  }

  @override
  void windowFocused(int viewId) {
    final window = windowOf(viewId);
    if (window == null) return;
    final wasShown = window.shown;
    _toFront(window);
    if (!wasShown) _syncWorkspace();
    _save();
  }

  @override
  void windowFrameChanged(int viewId, WindowFrame frame) {
    final window = windowOf(viewId);
    if (window == null || window.frame == frame) return;
    window.frame = frame;
    _save();
  }

  @override
  void newWindowRequested() => unawaited(newWindow());

  @override
  void quitRequested() => unawaited(_quit());

  /// The app's icon clicked with none of its windows shown: the IDE's
  /// window last in front (a new one, if none is open) when the app opens
  /// to the IDE, else the chat's.
  @override
  void reopenRequested() {
    if (multi && _mainWindow() == MainWindow.ide) {
      if (recentIde case final window?) {
        focus(window);
      } else {
        unawaited(newWindow());
      }
      return;
    }
    showChat();
  }

  // --- The IDE's windows, or none -------------------------------------------

  /// The setting asked for last that was declined (unsaved files kept the
  /// IDE where it was): not asked again until it changes.
  bool? _declined;
  bool _switching = false;

  /// settings.json changed: what shows at the next launch, and the IDE
  /// moved to windows of its own or into the main window, as
  /// `window.ideWindows` now says.
  void settingsChanged() {
    syncMainShownAtLaunch();
    if (!_started || _switching) return;
    final separate = _settings().ideWindows == IdeWindows.separate;
    if (separate == _separate) {
      _declined = null;
      return;
    }
    if (separate == _declined) return;
    _switching = true;
    unawaited(
      (separate ? _toSeparate() : _toMainWindow()).whenComplete(
        () => _switching = false,
      ),
    );
  }

  /// The main window's IDE moves to a window of its own (if it showed), its
  /// unsaved files asked about first: the main window's editors,
  /// terminals and language servers go.
  Future<void> _toSeparate() async {
    if (!await _confirmUnsaved([chat])) return _decline(true);
    _separate = true;
    final old = workspace.takeSingleWindowIde();
    workspace.ideWindows = _routeIde;
    _changed();
    _save();
    if (old.shown) await showFolder(old.folder);
  }

  /// The IDE's windows close (their unsaved files asked about first); the
  /// main window shows the folder of the one last in front, as the IDE if
  /// one was in front.
  Future<void> _toMainWindow() async {
    final windows = List.of(_ide);
    if (!await _confirmUnsaved(windows)) return _decline(false);
    final front = recentIde;
    final ideInFront = front != null && identical(active, front);
    if (ideInFront || !chat.shown) _focus(chat);
    // Their views' widgets go first, then the views; then the main window
    // takes the IDE.
    _ide.removeWhere(windows.contains);
    _mru.removeWhere(windows.contains);
    _changed();
    await _nextFrame();
    for (final window in windows) {
      WindowControls.stopListening(window.viewId);
      FileDrops.stopListening(window.viewId);
      await host.close(window.viewId);
    }
    _separate = false;
    workspace.ideWindows = null;
    if (front?.folder case final folder?) workspace.openIdeFolder(folder);
    if (ideInFront) workspace.layout = WorkspaceLayout.ide;
    _changed();
    _save();
  }

  /// Unsaved files kept the IDE where it is: the setting is written back.
  void _decline(bool separate) {
    _declined = separate;
    _updateSetting?.call(
      WindowSettings.ideWindowsKey,
      _separate ? null : IdeWindows.mainWindow.name,
    );
  }

  // --- Agents ------------------------------------------------------------------

  /// An agent a notification (or the tray's menu) picked: in its own
  /// window, if it has one; in the IDE's window it is a tab of, that tab
  /// shown; else in the chat's window.
  void showAgent(AgentThread thread) {
    if (_agents.firstWhereOrNull((w) => w.thread == thread) case final own?) {
      focus(own);
      return;
    }
    if (!multi) {
      if (_started) _focus(chat);
      chat.delegate?.showAgent(thread);
      return;
    }
    final folder = thread.project.path;
    final window = windowFor(folder);
    if (window != null && workspace.ideChats(folder).contains(thread)) {
      workspace.openIdeChat(folder, thread);
      _focus(window);
      unawaited(window.ready.then((delegate) => delegate?.showAgent(thread)));
      return;
    }
    _focus(chat);
    unawaited(chat.ready.then((delegate) => delegate?.showAgent(thread)));
  }

  // --- Titles and menus --------------------------------------------------------

  /// [window] has unsaved files, or no longer: the dot in its close button
  /// (macOS), and in the menus' lists.
  void setEdited(AppWindow window, bool edited) {
    if (window._edited == edited) return;
    window._edited = edited;
    if (!_started) return;
    unawaited(host.setEdited(window.viewId, edited));
    _syncMenus();
  }

  /// The titles and menus again, in the app's language (it changed).
  void relabel() {
    if (!_started) return;
    final l10n = _l10n();
    for (final window in _mru) {
      unawaited(
        host.setTitle(window.viewId, window.title(l10n), path: window.folder),
      );
    }
    _menus = null;
    _syncMenus();
  }

  /// Switch Window…: the windows (the chat's among them, shown or not),
  /// the one in front last first, picked over [from].
  void switchWindow(AppWindow from) {
    final delegate = from.delegate;
    if (delegate == null || !multi) return;
    final l10n = _l10n();
    final items = [
      for (final window in [
        ..._mru.where((w) => w.shown),
        ..._mru.where((w) => !w.shown),
      ])
        IdeQuickPickItem(
          label: window.label(l10n),
          description: [
            if (identical(window, from)) l10n.windowCurrent,
            ?window.folder,
          ].join('  '),
          icon: Icon(
            window.isChat
                ? Codicons.commentDiscussion
                : window.isAgent
                ? Codicons.comment
                : window.folder == null
                ? Codicons.emptyWindow
                : Codicons.folder,
          ),
          onAccept: () => focus(window),
        ),
    ];
    delegate.showQuickPick(
      IdeQuickPick(
        items: items,
        placeholder: l10n.windowSwitchPlaceholder,
        matchOnDescription: true,
        sortByLabel: false,
        activeItems: [items.length > 1 ? items[1] : items.first],
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }

  List<WindowMenuEntry>? _menus;

  void _syncMenus() {
    if (!_started) return;
    final l10n = _l10n();
    final menus = [
      for (final window in [chat, ..._ide, ..._agents])
        WindowMenuEntry(
          viewId: window.viewId,
          title: window.label(l10n),
          edited: window.edited,
        ),
    ];
    if (listEquals(menus, _menus)) return;
    _menus = menus;
    unawaited(
      host.setWindowList(
        menus,
        labels: {
          'newWindow': l10n.cmdNewWindow,
          'showChat': l10n.cmdShowChatWindow,
          'cycle': l10n.windowCycle,
          'windows': l10n.windowMenuWindows,
        },
      ),
    );
  }

  // --- Keeping them ------------------------------------------------------------

  /// What the workspace counts as shown: the chat's panes while its window
  /// shows, the tabs of the IDE's windows, and the agents' windows'.
  void _syncWorkspace() {
    workspace.showAgentWindows([for (final window in _agents) ?window.thread]);
    if (!multi) return;
    workspace.showWindows(
      folders: [for (final window in _ide) ?window.folder],
      chat: chat.shown,
    );
  }

  void _changed() {
    _syncWorkspace();
    _syncMenus();
    notifyListeners();
  }

  bool? _mainShownNext;
  Future<void> _writing = Future.value();

  /// Keeps the windows for the next launch (`windows.json`), the one in
  /// front first, and tells the system whether the chat's shows then.
  void _save() {
    if (!_started || _launch != null || _quitting) return;
    final store = _store;
    final data = <String, Object?>{
      'version': _version,
      'windows': [
        // An agent's window is not opened again.
        for (final window in _mru.where((w) => !w.isAgent))
          (window.isChat
                  ? const _KeptWindow(chat: true)
                  : _KeptWindow(folder: window.folder, frame: window.frame))
              .toJson(),
      ],
      'chatShown': chat.shown,
      'leftIn': _leftInIde ? 'ide' : 'chat',
    };
    if (store != null) {
      _writing = _writing
          .then((_) => store.write(data))
          .catchError((Object error) => debugPrint('windows.json: $error'));
    }
    syncMainShownAtLaunch();
  }

  /// Whether the app is left in the IDE: an IDE's window in front of
  /// those that show (the agents' aside). With none showing (the last
  /// closed, as on Windows it quits the app), where it was before.
  bool get _leftInIde {
    if (_mru.firstWhereOrNull((w) => w.shown && !w.isAgent) case final front?) {
      _wasInIde = front.isIde;
    }
    return _wasInIde;
  }

  bool _wasInIde = false;

  /// Whether the chat's window shows at the next launch, as the system is
  /// to know before the app runs: also when `workbench.mainWindow` changes.
  /// Always, with the IDE in it.
  void syncMainShownAtLaunch() {
    if (!_started) return;
    final shown =
        !_separate ||
        switch (_mainWindow()) {
          MainWindow.chat => true,
          MainWindow.ide => false,
          MainWindow.last => !_leftInIde,
        };
    if (shown == _mainShownNext) return;
    _mainShownNext = shown;
    unawaited(host.setMainShownAtLaunch(shown));
  }

  /// Waits for what is being written.
  @visibleForTesting
  Future<void> get saved => _writing;
}

extension<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) => where(test).firstOrNull;
}
