import 'dart:ui' show AppExitResponse, Rect;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/window/code_args.dart';
import 'package:baocode/window/window_frame.dart';
import 'package:baocode/window/window_settings.dart';
import 'package:baocode/workspace/main_window.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

import 'fake_window_host.dart';

const _screen = ScreenArea('main', Rect.fromLTWH(0, 25, 1440, 875));

/// The app's windows over a fake system; each window's workbench a
/// [FakeDelegate], there as soon as the window is.
class _Harness {
  _Harness(
    WidgetTester tester, {
    bool available = true,
    Map<String, Object?>? kept,
    this.mainWindow = MainWindow.chat,
    bool quitsWithLastWindow = false,
    this.tray = false,
    this.requestFiles = const {},
  }) : host = FakeWindowHost(tester.view, available: available),
       store = MemoryPreferenceStore(kept),
       workspace = Workspace.mock(),
       directories = const {'/w/a', '/w/b', '/w/c'} {
    windows = AppWindows(
      host: host,
      workspace: workspace,
      l10n: () => englishLocalizations,
      store: store,
      settings: () => settings,
      mainWindow: () => mainWindow,
      updateSetting: (key, value) => written.add((key, value)),
      isDirectory: (path) async => directories.contains(path),
      takeFile: (path) async => requestFiles[path],
      hasTray: () => tray,
      quit: () async {
        quits++;
        return quitResponse;
      },
      nextFrame: () async {},
      quitsWithLastWindow: quitsWithLastWindow,
    );
    windows.chat.attach(chatDelegate);
    // A window's workbench comes with it (and again with a folder in its
    // place).
    windows.addListener(() {
      for (final window in windows.ideWindows) {
        if (window.delegate == null) {
          final delegate = FakeDelegate(context: context);
          delegates[window.viewId] = delegate;
          window.attach(delegate);
        }
      }
    });
  }

  final FakeWindowHost host;
  final MemoryPreferenceStore store;
  final Workspace workspace;
  late final AppWindows windows;
  final Set<String> directories;
  final Map<String, String> requestFiles;
  MainWindow mainWindow;
  WindowSettings settings = const WindowSettings();

  /// The settings written back to settings.json.
  final List<(String, Object?)> written = [];
  bool tray;
  int quits = 0;
  AppExitResponse quitResponse = AppExitResponse.exit;

  /// Where dialogs show (see [showDialogs]).
  BuildContext? context;
  late final FakeDelegate chatDelegate = FakeDelegate(context: context);
  final Map<int, FakeDelegate> delegates = {};

  AppWindow window(String? folder) =>
      windows.ideWindows.firstWhere((window) => window.folder == folder);

  FakeDelegate delegateOf(String? folder) => delegates[window(folder).viewId]!;

  List<String?> get folders => [
    for (final window in windows.ideWindows) window.folder,
  ];

  /// The folders of the windows, the one in front first (`chat` for the
  /// chat's).
  List<String?> get order => [
    for (final window in windows.windows)
      window.isChat ? 'chat' : window.folder,
  ];

  Future<void> start() async {
    await windows.start();
  }

  /// A navigator for the dialogs to show in, as each window has one.
  Future<void> showDialogs(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            this.context = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    chatDelegate.context = context;
    for (final delegate in delegates.values) {
      delegate.context = context;
    }
  }
}

IdeDocument _doc(String path) => IdeDocument(path, 'text');

void main() {
  group('without windows of its own', () {
    testWidgets('the IDE shows in the main window; its entries go there', (
      tester,
    ) async {
      final harness = _Harness(tester, available: false);
      await harness.start();
      expect(harness.windows.multi, isFalse);
      expect(harness.workspace.ideWindows, isNull);

      await harness.windows.showFolder('/w/a');
      expect(harness.chatDelegate.folders, ['/w/a']);
      await harness.windows.handleCode(
        CodeArgs.parse(['-g', '/w/x.txt:4'], cwd: '/'),
      );
      expect(harness.chatDelegate.opened, [
        [const CodeTarget('/w/x.txt', line: 4)],
      ]);
      expect(harness.host.created, isEmpty);
    });
  });

  group('opening', () {
    testWidgets('a folder opens its window once; again, that one comes in '
        'front', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      expect(harness.windows.multi, isTrue);

      final a = await harness.windows.showFolder('/w/a');
      await harness.windows.showFolder('/w/b');
      expect(harness.folders, ['/w/a', '/w/b']);
      expect(harness.host.titles[a!.viewId], 'a — BaoCode');
      expect(harness.order, ['/w/b', '/w/a', 'chat']);

      expect(await harness.windows.showFolder('/w/a'), same(a));
      expect(harness.host.created, hasLength(2));
      expect(harness.order, ['/w/a', '/w/b', 'chat']);
      expect(harness.host.focused, a.viewId);
      // The Window menu, the Dock's and the tray's list them.
      expect(
        [for (final entry in harness.host.menu) entry.title],
        ['Chat', 'a', 'b'],
      );
    });

    testWidgets('Open in Fast Ide: the folder\'s window, the agent its tab', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.start();
      final thread = harness.workspace.threads.first;
      harness.workspace.openInIde(thread);
      await tester.pump();

      final window = harness.window(thread.project.path);
      expect(harness.delegates[window.viewId]!.agents, [thread]);
      expect(harness.workspace.ideChats(thread.project.path), contains(thread));
      // Its chat shows in the IDE's window, and in the chat's.
      expect(harness.workspace.isShown(thread), isTrue);

      harness.workspace.openInIde(thread);
      await tester.pump();
      expect(harness.host.created, hasLength(1));
    });

    testWidgets('New Window opens an empty one, its welcome', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      await harness.windows.newWindow();
      await harness.windows.newWindow();
      expect(harness.folders, [null, null]);
      expect(harness.host.created.first.title, 'Welcome — BaoCode');
    });

    testWidgets('window.newWindowDimensions: inherit, below and right of the '
        'one in front; maximized', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      harness.host.screenAreas = const [_screen];
      harness.host.frames[0] = const WindowFrame(
        Rect.fromLTWH(100, 100, 800, 600),
        screen: 'main',
      );
      harness.settings = const WindowSettings(
        newWindowDimensions: NewWindowDimensions.inherit,
      );
      await harness.windows.newWindow();
      expect(
        harness.host.created.last.frame,
        const WindowFrame(Rect.fromLTWH(130, 130, 800, 600), screen: 'main'),
      );

      harness.settings = const WindowSettings(
        newWindowDimensions: NewWindowDimensions.maximized,
      );
      await harness.windows.newWindow();
      expect(harness.host.created.last.frame!.maximized, isTrue);

      harness.settings = const WindowSettings();
      await harness.windows.newWindow();
      expect(harness.host.created.last.frame, isNull);
    });
  });

  group('the code command', () {
    Future<_Harness> started(WidgetTester tester) async {
      final harness = _Harness(tester);
      await harness.start();
      return harness;
    }

    Future<void> code(_Harness harness, List<String> args) =>
        harness.windows.handleCode(CodeArgs.parse(args, cwd: '/w'));

    testWidgets('code <folder>: its window, opened once', (tester) async {
      final harness = await started(tester);
      await code(harness, ['a']);
      await code(harness, ['b']);
      await code(harness, ['a']);
      expect(harness.folders, ['/w/a', '/w/b']);
      expect(harness.order.first, '/w/a');
    });

    testWidgets('code <file>: the window that has it, at the line', (
      tester,
    ) async {
      final harness = await started(tester);
      await code(harness, ['a']);
      await code(harness, ['b']);
      await code(harness, ['-g', 'a/lib/main.dart:3:4']);
      expect(harness.delegateOf('/w/a').opened, [
        [const CodeTarget('/w/a/lib/main.dart', line: 3, column: 4)],
      ]);
      expect(harness.order.first, '/w/a');
      expect(harness.workspace.recentFiles.first, '/w/a/lib/main.dart');
    });

    testWidgets('code <file> no window has: the one last in front; with none, '
        'a new one', (tester) async {
      final harness = await started(tester);
      await code(harness, ['/tmp/notes.txt']);
      expect(harness.folders, [null]);
      expect(harness.delegateOf(null).opened, [
        [const CodeTarget('/tmp/notes.txt')],
      ]);

      await code(harness, ['a']);
      await code(harness, ['/tmp/todo.txt']);
      expect(harness.delegateOf('/w/a').opened, [
        [const CodeTarget('/tmp/todo.txt')],
      ]);
      expect(harness.host.created, hasLength(2));
    });

    testWidgets('code -n <file>: a new window; code -n: an empty one', (
      tester,
    ) async {
      final harness = await started(tester);
      await code(harness, ['a']);
      await code(harness, ['-n', 'a/x.dart']);
      expect(harness.folders, ['/w/a', null]);
      expect(harness.delegateOf(null).opened, [
        [const CodeTarget('/w/a/x.dart')],
      ]);
      expect(harness.delegateOf('/w/a').opened, isEmpty);

      await code(harness, ['-n']);
      expect(harness.folders, ['/w/a', null, null]);
    });

    testWidgets('code -r <folder>: in the window last in front', (
      tester,
    ) async {
      final harness = await started(tester);
      await code(harness, ['a']);
      final window = harness.window('/w/a');
      await code(harness, ['-r', 'b']);
      expect(harness.folders, ['/w/b']);
      expect(window.folder, '/w/b');
      expect(harness.host.created, hasLength(1));
      expect(harness.host.titles[window.viewId], 'b — BaoCode');

      // A file, there too, though another window had it.
      await code(harness, ['c']);
      harness.windows.focus(window);
      await code(harness, ['-r', 'c/x.dart']);
      expect(harness.delegateOf('/w/b').opened, [
        [const CodeTarget('/w/c/x.dart')],
      ]);
    });

    testWidgets('code alone: the window last in front, or a new one', (
      tester,
    ) async {
      final harness = await started(tester);
      await code(harness, []);
      expect(harness.folders, [null]);
      await code(harness, ['a']);
      harness.windows.showChat();
      await code(harness, []);
      expect(harness.host.created, hasLength(2));
      expect(harness.order.first, '/w/a');
    });

    testWidgets('requests: the marker and arguments (Windows), the script\'s '
        'file (macOS), plain paths (the Dock, Finder)', (tester) async {
      final harness = _Harness(
        tester,
        requestFiles: {'/tmp/1.baocode-cli': '/w\n-g\nb/y.dart:9\n'},
      );
      await harness.start();
      await harness.windows.openRequested([CodeArgs.requestMarker, '/w', 'a']);
      expect(harness.folders, ['/w/a']);

      await harness.windows.openRequested(['/tmp/1.baocode-cli', '/w/c']);
      expect(harness.folders, ['/w/a', '/w/c']);
      // The request first: its file to the window last in front, a's.
      expect(harness.delegateOf('/w/a').opened, [
        [const CodeTarget('/w/b/y.dart', line: 9)],
      ]);
    });

    testWidgets('dropped on a window: a folder opens its own, a file opens '
        'there', (tester) async {
      final harness = await started(tester);
      await code(harness, ['a']);
      final a = harness.window('/w/a');
      expect(
        harness.windows.dropped(a.viewId, const [
          ComposerFile('/w/b', directory: true),
          ComposerFile('/tmp/z.txt'),
        ]),
        isTrue,
      );
      await tester.pump();
      expect(harness.folders, ['/w/a', '/w/b']);
      expect(harness.delegateOf('/w/a').opened, [
        [const CodeTarget('/tmp/z.txt')],
      ]);
    });
  });

  group('Open Folder in a window', () {
    testWidgets('replaces its folder; a folder open elsewhere comes in front '
        'instead', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.windows.showFolder('/w/b');
      final generation = a.generation;
      final before = harness.delegateOf('/w/a');

      await harness.windows.replaceFolder(a, '/w/c');
      expect(a.folder, '/w/c');
      expect(a.generation, generation + 1);
      expect(harness.delegates[a.viewId], isNot(same(before)));
      expect(harness.order.first, '/w/c');

      await harness.windows.replaceFolder(a, '/w/b');
      expect(a.folder, '/w/c');
      expect(harness.order.first, '/w/b');
      expect(harness.host.created, hasLength(2));
    });

    testWidgets('with unsaved files, asks first', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.showDialogs(tester);
      harness.delegateOf('/w/a').unsaved = [_doc('/w/a/x.dart')];

      var replacing = harness.windows.replaceFolder(a, '/w/b');
      await tester.pump();
      expect(
        find.text('Do you want to save the changes you made to x.dart?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await replacing;
      expect(a.folder, '/w/a');

      replacing = harness.windows.replaceFolder(a, '/w/b');
      await tester.pump();
      await tester.tap(find.text("Don't Save"));
      await tester.pump();
      await replacing;
      expect(a.folder, '/w/b');
    });
  });

  group('closing a window', () {
    testWidgets('unsaved files: Save saves, then it closes', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.showDialogs(tester);
      final doc = _doc('/w/a/x.dart');
      final delegate = harness.delegateOf('/w/a')..unsaved = [doc];

      final closing = harness.windows.requestClose(a);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(await closing, isTrue);
      expect(delegate.saved, [doc]);
      expect(harness.folders, isEmpty);
      expect(harness.host.log, contains('close ${a.viewId}'));
    });

    testWidgets('unsaved files: Cancel keeps it; Don\'t Save closes', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.showDialogs(tester);
      final delegate = harness.delegateOf('/w/a')
        ..unsaved = [_doc('/w/a/x.dart'), _doc('/w/a/y.dart')];

      var closing = harness.windows.requestClose(a);
      await tester.pump();
      expect(
        find.text('Do you want to save the changes to the following 2 files?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(await closing, isFalse);
      expect(harness.folders, ['/w/a']);

      closing = harness.windows.requestClose(a);
      await tester.pump();
      await tester.tap(find.text("Don't Save"));
      await tester.pump();
      expect(await closing, isTrue);
      expect(delegate.saved, isEmpty);
      expect(harness.folders, isEmpty);
    });

    testWidgets('running terminals ask, as terminal.integrated.confirmOnExit '
        'says', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.showDialogs(tester);
      harness.delegateOf('/w/a').terminals = true;

      // Not asked by default.
      harness.settings = const WindowSettings(
        terminalConfirmOnExit: TerminalConfirmOnExit.always,
      );
      final closing = harness.windows.requestClose(a);
      await tester.pump();
      expect(
        find.text(
          "Do you want to terminate the running processes in the window's "
          'terminals?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Terminate'));
      await tester.pump();
      expect(await closing, isTrue);

      final b = (await harness.windows.showFolder('/w/b'))!;
      harness.delegateOf('/w/b')
        ..terminals = true
        ..context = harness.context;
      harness.settings = const WindowSettings();
      expect(await harness.windows.requestClose(b), isTrue);
    });

    testWidgets('window.confirmBeforeClose keyboardOnly: asks when a shortcut '
        'closes it', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.showDialogs(tester);
      harness.settings = const WindowSettings(
        confirmBeforeClose: ConfirmBeforeClose.keyboardOnly,
      );
      final closing = harness.windows.requestClose(a, byKeyboard: true);
      await tester.pump();
      expect(
        find.text('Are you sure you want to close the window?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(await closing, isFalse);
      // Its close button does not ask.
      expect(await harness.windows.requestClose(a), isTrue);
    });

    testWidgets('the system\'s close (its button, Alt+F4) asks the same way', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      harness.host.events!.windowCloseRequested(a.viewId);
      await tester.pump();
      expect(harness.folders, isEmpty);
    });

    testWidgets('the chat\'s window hides; the one behind it comes in front', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      harness.windows.showChat();
      expect(await harness.windows.requestClose(harness.windows.chat), isTrue);
      expect(harness.windows.chat.shown, isFalse);
      expect(harness.host.log, contains('hide 0'));
      expect(harness.windows.active, same(a));
      expect(harness.workspace.ideWindows, isNotNull);

      // Show Chat Window brings it back.
      harness.windows.showChat();
      expect(harness.windows.chat.shown, isTrue);
      expect(harness.host.focused, 0);
    });

    testWidgets('Windows: the last window closed quits, unless the tray '
        'keeps the app', (tester) async {
      final harness = _Harness(tester, quitsWithLastWindow: true, tray: true);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.windows.requestClose(harness.windows.chat);
      await harness.windows.requestClose(a);
      expect(harness.quits, 0);

      harness.tray = false;
      final b = (await harness.windows.showFolder('/w/b'))!;
      await harness.windows.requestClose(harness.windows.chat);
      expect(harness.quits, 0);
      harness.quitResponse = AppExitResponse.cancel;
      await harness.windows.requestClose(b);
      expect(harness.quits, 1);
      // Not quit: the chat's window again.
      expect(harness.windows.chat.shown, isTrue);
    });

    testWidgets('macOS: the last window closed does not quit', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.windows.requestClose(harness.windows.chat);
      await harness.windows.requestClose(a);
      expect(harness.quits, 0);
    });
  });

  testWidgets('quitting asks about the unsaved files of all windows at once, '
      'then about the agents', (tester) async {
    final harness = _Harness(tester);
    await harness.start();
    await harness.windows.showFolder('/w/a');
    await harness.windows.showFolder('/w/b');
    await harness.showDialogs(tester);
    harness.delegateOf('/w/a').unsaved = [_doc('/w/a/x.dart')];
    harness.delegateOf('/w/b').unsaved = [_doc('/w/b/y.dart')];

    final quitting = harness.windows.confirmQuit();
    await tester.pump();
    expect(
      find.text('Do you want to save the changes to the following 2 files?'),
      findsOneWidget,
    );
    expect(find.textContaining('x.dart'), findsOneWidget);
    expect(find.textContaining('y.dart'), findsOneWidget);
    await tester.tap(find.text('Save All'));
    await tester.pump();
    expect(harness.delegateOf('/w/a').saved, hasLength(1));
    expect(harness.delegateOf('/w/b').saved, hasLength(1));
    // Asked in the window in front: b's.
    expect(harness.host.focused, harness.window('/w/b').viewId);

    expect(find.text('Quit BaoCode?'), findsOneWidget);
    await tester.tap(find.text('Quit'));
    await tester.pump();
    expect(await quitting, isTrue);
  });

  testWidgets('the tray\'s Quit quits as the app does', (tester) async {
    final harness = _Harness(tester, quitsWithLastWindow: true, tray: true);
    await harness.start();
    harness.host.events!.quitRequested();
    await tester.pump();
    expect(harness.quits, 1);
  });

  testWidgets('quitting, cancelled at the unsaved files, does not quit', (
    tester,
  ) async {
    final harness = _Harness(tester);
    await harness.start();
    await harness.windows.showFolder('/w/a');
    await harness.showDialogs(tester);
    harness.delegateOf('/w/a').unsaved = [_doc('/w/a/x.dart')];
    final quitting = harness.windows.confirmQuit();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(await quitting, isFalse);
    expect(find.text('Quit BaoCode?'), findsNothing);
  });

  group('restoring', () {
    Map<String, Object?> kept({bool chatShown = true}) => {
      'version': 1,
      'windows': [
        {
          'folder': '/w/a',
          // Where a screen no longer is.
          'frame': {
            'x': 3000,
            'y': 200,
            'width': 800,
            'height': 600,
            'screen': 'gone',
          },
        },
        {'chat': true},
        {'folder': null},
        {'folder': '/w/gone'},
        {'folder': '/w/b'},
      ],
      'chatShown': chatShown,
    };

    Future<_Harness> restored(
      WidgetTester tester, {
      RestoreWindows restore = RestoreWindows.all,
      MainWindow main = MainWindow.chat,
      bool chatShown = true,
    }) async {
      final harness = _Harness(
        tester,
        kept: kept(chatShown: chatShown),
        mainWindow: main,
      )..settings = WindowSettings(restoreWindows: restore);
      harness.host.screenAreas = const [_screen];
      await harness.start();
      await harness.windows.prepareLaunch();
      await harness.windows.restore();
      return harness;
    }

    testWidgets('all: the windows as they were, the one in front again; '
        'one off the screens moved back; a folder gone left out', (
      tester,
    ) async {
      final harness = await restored(tester);
      expect(harness.folders, ['/w/b', null, '/w/a']);
      expect(harness.order, ['/w/a', 'chat', null, '/w/b']);
      expect(harness.host.focused, harness.window('/w/a').viewId);
      final frame = harness.host.created.last.frame!;
      expect(frame.screen, 'main');
      expect(frame.bounds, const Rect.fromLTWH(640, 200, 800, 600));
      expect(harness.windows.chat.shown, isTrue);
      expect(harness.host.mainShownAtLaunch, isTrue);
    });

    testWidgets('folders: those with a folder', (tester) async {
      final harness = await restored(tester, restore: RestoreWindows.folders);
      expect(harness.folders, ['/w/b', '/w/a']);
    });

    testWidgets('one: the one in front', (tester) async {
      final harness = await restored(tester, restore: RestoreWindows.one);
      expect(harness.folders, ['/w/a']);
    });

    testWidgets('none: the chat alone', (tester) async {
      final harness = await restored(tester, restore: RestoreWindows.none);
      expect(harness.folders, isEmpty);
      expect(harness.windows.chat.shown, isTrue);
    });

    testWidgets('workbench.mainWindow last: the chat hidden if it was; none '
        'restored, an empty window', (tester) async {
      final harness = await restored(
        tester,
        restore: RestoreWindows.none,
        main: MainWindow.last,
        chatShown: false,
      );
      expect(harness.windows.chat.shown, isFalse);
      expect(harness.host.log.first, 'hide 0');
      expect(harness.folders, [null]);
      expect(harness.host.mainShownAtLaunch, isFalse);
    });

    testWidgets('kept as they move, open and close, the one in front first', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.start();
      final a = (await harness.windows.showFolder('/w/a'))!;
      await harness.windows.newWindow();
      const frame = WindowFrame(Rect.fromLTWH(1, 2, 300, 400), screen: 'm');
      harness.host.events!.windowFrameChanged(a.viewId, frame);
      harness.host.events!.windowFocused(a.viewId);
      await harness.windows.saved;
      expect(harness.store.preferences['windows'], [
        {'folder': '/w/a', 'frame': frame.toJson()},
        {'folder': null},
        {'chat': true},
      ]);
      expect(harness.store.preferences['chatShown'], isTrue);
    });
  });

  group('the first run with windows', () {
    Future<_Harness> migrated(
      WidgetTester tester, {
      required MainWindow main,
      required bool ideShown,
    }) async {
      final harness = _Harness(tester, mainWindow: main);
      // As the run before left it: the IDE in the main window.
      harness.workspace.openIdeFolder('/w/a');
      if (ideShown) harness.workspace.layout = WorkspaceLayout.ide;
      await harness.start();
      await harness.windows.prepareLaunch();
      await harness.windows.restore();
      return harness;
    }

    testWidgets('the IDE\'s folder opens its window; the chat shows, as '
        'mainWindow says', (tester) async {
      final harness = await migrated(
        tester,
        main: MainWindow.chat,
        ideShown: true,
      );
      expect(harness.folders, ['/w/a']);
      expect(harness.windows.chat.shown, isTrue);
      expect(harness.workspace.ideFolder, isNull);
      expect(harness.workspace.layout, WorkspaceLayout.chat);
    });

    testWidgets('mainWindow last, the IDE shown: its window alone', (
      tester,
    ) async {
      final harness = await migrated(
        tester,
        main: MainWindow.last,
        ideShown: true,
      );
      expect(harness.folders, ['/w/a']);
      expect(harness.windows.chat.shown, isFalse);
      expect(harness.host.mainShownAtLaunch, isFalse);
    });

    testWidgets('mainWindow ide, no folder: an empty window', (tester) async {
      final harness = _Harness(tester, mainWindow: MainWindow.ide);
      await harness.start();
      await harness.windows.prepareLaunch();
      await harness.windows.restore();
      expect(harness.folders, [null]);
      expect(harness.windows.chat.shown, isFalse);
    });
  });

  group('notifications', () {
    testWidgets('an agent that is a tab of an IDE window: that window, the '
        'tab shown', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final thread = harness.workspace.threads.first;
      harness.workspace.openInIde(thread);
      await tester.pump();
      await harness.windows.showFolder('/w/b');
      final window = harness.window(thread.project.path);
      final delegate = harness.delegates[window.viewId]!..agents.clear();

      harness.windows.showAgent(thread);
      await tester.pump();
      expect(harness.order.first, thread.project.path);
      expect(harness.host.focused, window.viewId);
      expect(delegate.agents, [thread]);
      expect(harness.chatDelegate.agents, isEmpty);
    });

    testWidgets('any other: the chat\'s window', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      final thread = harness.workspace.threads.first;
      await harness.windows.showFolder('/w/a');
      harness.windows.showAgent(thread);
      await tester.pump();
      expect(harness.order.first, 'chat');
      expect(harness.host.focused, 0);
      expect(harness.chatDelegate.agents, [thread]);
    });
  });

  testWidgets('Switch Window: all windows, the one in front first, the '
      'chat\'s among them; the one behind picked', (tester) async {
    final harness = _Harness(tester);
    await harness.start();
    await harness.windows.showFolder('/w/a');
    final b = (await harness.windows.showFolder('/w/b'))!;
    harness.windows.switchWindow(b);
    final pick = harness.delegateOf('/w/b').pick!;
    final items = pick.items.cast<IdeQuickPickItem>();
    expect([for (final item in items) item.label], ['b', 'a', 'Chat']);
    expect(items.first.description, 'Current  /w/b');
    expect(pick.activeItems!.single.label, 'a');

    pick.onDidAccept!(items.last);
    expect(harness.order.first, 'chat');
    expect(harness.host.focused, 0);
  });

  testWidgets('unsaved files mark the window (the dot in its close button) '
      'and the menus\' lists', (tester) async {
    final harness = _Harness(tester);
    await harness.start();
    final a = (await harness.windows.showFolder('/w/a'))!;
    harness.windows.setEdited(a, true);
    expect(harness.host.edited[a.viewId], isTrue);
    expect(harness.host.menu.last.edited, isTrue);
    harness.windows.setEdited(a, false);
    expect(harness.host.edited[a.viewId], isFalse);
  });

  group('window.ideWindows: the IDE in the main window', () {
    const inMain = WindowSettings(ideWindows: IdeWindows.mainWindow);

    testWidgets('its entries go to the main window; the chat\'s window is '
        'still the app\'s to show, hide and bring in front', (tester) async {
      final harness = _Harness(tester)..settings = inMain;
      await harness.start();
      expect(harness.windows.started, isTrue);
      expect(harness.windows.multi, isFalse);
      expect(harness.workspace.ideWindows, isNull);

      await harness.windows.showFolder('/w/a');
      expect(harness.chatDelegate.folders, ['/w/a']);
      expect(harness.host.created, isEmpty);
      expect(harness.host.focused, 0);
      await harness.windows.openFiles([const CodeTarget('/w/x.txt')]);
      expect(harness.chatDelegate.opened, [
        [const CodeTarget('/w/x.txt')],
      ]);

      // Its close button hides it; a notification brings it back.
      expect(await harness.windows.requestClose(harness.windows.chat), isTrue);
      expect(harness.host.log, contains('hide 0'));
      expect(harness.windows.chat.shown, isFalse);
      final thread = harness.workspace.threads.first;
      harness.windows.showAgent(thread);
      expect(harness.windows.chat.shown, isTrue);
      expect(harness.chatDelegate.agents, [thread]);
    });

    testWidgets('New Window (⇧⌘N): the IDE\'s empty window, in the main one', (
      tester,
    ) async {
      final harness = _Harness(tester)..settings = inMain;
      await harness.start();
      harness.workspace.openIdeFolder('/w/a');
      await harness.windows.newWindow();
      expect(harness.workspace.ideFolder, isNull);
      expect(harness.workspace.recentFolders.first, '/w/a');
      expect(harness.chatDelegate.folders, [null]);
      expect(harness.host.created, isEmpty);
    });

    testWidgets('at launch: the main window alone, shown, with the folder of '
        'the IDE\'s window last in front', (tester) async {
      final harness = _Harness(
        tester,
        mainWindow: MainWindow.ide,
        kept: {
          'version': 1,
          'windows': [
            {'folder': '/w/b'},
            {'chat': true},
            {'folder': '/w/a'},
          ],
          'chatShown': false,
        },
      )..settings = inMain;
      await harness.start();
      await harness.windows.prepareLaunch();
      await harness.windows.restore();
      expect(harness.host.created, isEmpty);
      expect(harness.windows.chat.shown, isTrue);
      expect(harness.host.mainShownAtLaunch, isTrue);
      expect(harness.workspace.ideFolder, '/w/b');
    });

    testWidgets('switched to: the IDE\'s windows close, the main window takes '
        'the folder of the one in front', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      await harness.windows.showFolder('/w/a');
      await harness.windows.showFolder('/w/b');
      final views = [for (final w in harness.windows.ideWindows) w.viewId];

      harness.settings = inMain;
      harness.windows.settingsChanged();
      await tester.pump();
      expect(harness.windows.multi, isFalse);
      expect(harness.windows.ideWindows, isEmpty);
      for (final view in views) {
        expect(harness.host.log, contains('close $view'));
      }
      expect(harness.workspace.ideWindows, isNull);
      expect(harness.workspace.ideFolder, '/w/b');
      expect(harness.workspace.layout, WorkspaceLayout.ide);
      expect(harness.host.focused, 0);
      expect(harness.host.mainShownAtLaunch, isTrue);
      expect(harness.written, isEmpty);
    });

    testWidgets('switched to, unsaved files cancelled: the windows stay, the '
        'setting is written back, not asked again', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      await harness.windows.showFolder('/w/a');
      await harness.showDialogs(tester);
      harness.delegateOf('/w/a').unsaved = [_doc('/w/a/x.dart')];

      harness.settings = inMain;
      harness.windows.settingsChanged();
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(harness.windows.multi, isTrue);
      expect(harness.folders, ['/w/a']);
      expect(harness.written, [(WindowSettings.ideWindowsKey, null)]);

      // Before the setting is back.
      harness.windows.settingsChanged();
      await tester.pump();
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('switched back: the main window\'s IDE, if it showed, opens '
        'a window of its own', (tester) async {
      final harness = _Harness(tester)..settings = inMain;
      await harness.start();
      harness.workspace.openIdeFolder('/w/a');
      harness.workspace.layout = WorkspaceLayout.ide;

      harness.settings = const WindowSettings();
      harness.windows.settingsChanged();
      await tester.pump();
      expect(harness.windows.multi, isTrue);
      expect(harness.workspace.ideWindows, isNotNull);
      expect(harness.folders, ['/w/a']);
      expect(harness.workspace.ideFolder, isNull);
      expect(harness.workspace.layout, WorkspaceLayout.chat);
    });
  });

  group('the app\'s icon clicked with no window shown', () {
    testWidgets('mainWindow ide: the IDE\'s window last in front, or a new '
        'one', (tester) async {
      final harness = _Harness(tester, mainWindow: MainWindow.ide);
      await harness.start();
      harness.host.events!.reopenRequested();
      await tester.pump();
      expect(harness.folders, [null]);
      expect(harness.windows.chat.shown, isTrue);

      final a = (await harness.windows.showFolder('/w/a'))!;
      harness.windows.focus(harness.windows.chat);
      harness.host.events!.reopenRequested();
      await tester.pump();
      expect(harness.host.created, hasLength(2));
      expect(harness.host.focused, a.viewId);
    });

    testWidgets('otherwise: the chat\'s window', (tester) async {
      final harness = _Harness(tester);
      await harness.start();
      await harness.windows.showFolder('/w/a');
      await harness.windows.requestClose(harness.windows.chat);
      harness.host.events!.reopenRequested();
      expect(harness.windows.chat.shown, isTrue);
      expect(harness.host.focused, 0);
      expect(harness.host.created, hasLength(1));
    });
  });
}
