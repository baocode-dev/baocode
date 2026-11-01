// The chat's terminals in two places, the panel under the conversation and
// the side panel's page (see workspace/terminal_deck.dart): a terminal shows
// live in both, one place its view, the other mirroring it until pressed.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart' show CommandStatus;
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/terminal/terminal_hosts.dart';
import 'package:baocode/ide/terminal/terminal_panel.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:baocode/ide/terminal/terminal_tasks.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/terminal_deck.dart';

import '../ide/terminal/fake_pty.dart';
import '../ide/terminal/fake_terminal.dart';

/// Background commands for a deck: what was stopped and cleared.
class _Tasks extends ChangeNotifier implements TerminalTasks {
  _Tasks(this.tasks);

  @override
  List<KernelTask> tasks;
  final List<String> stopped = [];

  @override
  String? commandOf(KernelTask task) =>
      task.id == 'build' ? 'npm run build' : null;

  @override
  void stop(KernelTask task) => stopped.add(task.id);

  @override
  void clear(Iterable<KernelTask> ended) {
    final gone = {for (final task in ended) task.id};
    tasks = [
      for (final task in tasks)
        if (!gone.contains(task.id)) task,
    ];
    notifyListeners();
  }

  @override
  String get root => '/p';
}

/// Reads the commands' output.
class _Output implements IdeFileService {
  @override
  Future<String> read(String path, {bool force = false}) async =>
      'output of $path';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a terminal shows live in both places: the one pressed has '
      'its keyboard and size, the other mirrors it', (tester) async {
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(<FakePty>[]),
    );
    addTearDown(terminals.dispose);
    final hosts = TerminalHosts();
    addTearDown(hosts.dispose);
    final shell = terminals.create();

    Widget deck(String place) => Expanded(
      key: ValueKey(place),
      child: TerminalDeck(
        place: place,
        hosts: hosts,
        terminals: terminals,
        shown: shell,
        onShow: (_) {},
        onNew: () => null,
      ),
    );
    Future<void> pump(List<String> places) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Material(child: Row(children: [for (final p in places) deck(p)])),
      ),
    );
    Finder viewIn(String place) => find.descendant(
      of: find.byKey(ValueKey(place)),
      matching: find.byType(TerminalView),
    );
    bool mirrors(String place) =>
        tester.widget<TerminalView>(viewIn(place)).mirror;

    await pump(['panel', 'side']);
    expect(mirrors('panel'), isFalse);
    expect(mirrors('side'), isTrue);
    expect(hosts.hostOf(shell), 'panel');

    // Pressed, the mirror becomes its view, focused; the panel mirrors it.
    await tester.tap(viewIn('side'));
    await tester.pump();
    await tester.pump();
    expect(hosts.hostOf(shell), 'side');
    expect(mirrors('side'), isFalse);
    expect(mirrors('panel'), isTrue);
    expect(shell.focusNode.hasFocus, isTrue);

    // The side panel's page closed: the panel has it again.
    await pump(['panel']);
    await tester.pump();
    expect(mirrors('panel'), isFalse);
    expect(hosts.hostOf(shell), 'panel');
  });

  testWidgets('a terminal\'s tab dragged past another goes there', (
    tester,
  ) async {
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(<FakePty>[]),
    );
    addTearDown(terminals.dispose);
    final hosts = TerminalHosts();
    addTearDown(hosts.dispose);
    final a = terminals.create();
    final b = terminals.create();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Material(
          child: TerminalDeck(
            place: 'panel',
            hosts: hosts,
            terminals: terminals,
            shown: a,
            onShow: (_) {},
            onNew: () => null,
          ),
        ),
      ),
    );
    // The tab, not the terminal under it (keyed the same).
    final tab = find.byKey(ObjectKey(a)).first;
    final gesture = await tester.startGesture(tester.getCenter(tab));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(tester.getSize(tab).width / 5, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(terminals.instances, [b, a]);
    expect(terminals.active, b);
  });

  testWidgets('the IDE\'s panel shares them: hidden, it mirrors the '
      'terminal, the chat\'s place having it; shown alone, it has it', (
    tester,
  ) async {
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(<FakePty>[]),
    );
    addTearDown(terminals.dispose);
    final hosts = TerminalHosts();
    addTearDown(hosts.dispose);
    final shell = terminals.create();
    final ide = Object();

    Widget panel({required bool shown}) => Expanded(
      key: const ValueKey('ide'),
      child: TerminalPanel(
        terminals: terminals,
        onNew: () {},
        hosts: hosts,
        place: ide,
        shown: shown,
      ),
    );
    Future<void> pump(List<Widget> children) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Material(child: Row(children: children)),
      ),
    );
    bool mirrors(String key) => tester
        .widget<TerminalView>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TerminalView),
          ),
        )
        .mirror;

    // The IDE hidden (kept built), built first: the chat's deck has it.
    await pump([
      panel(shown: false),
      Expanded(
        key: const ValueKey('chat'),
        child: TerminalDeck(
          place: 'chat',
          hosts: hosts,
          terminals: terminals,
          shown: shell,
          onShow: (_) {},
          onNew: () => null,
        ),
      ),
    ]);
    expect(mirrors('ide'), isTrue);
    expect(mirrors('chat'), isFalse);
    expect(hosts.hostOf(shell), 'chat');

    // The IDE shown, the chat's gone: the IDE has it.
    await pump([panel(shown: true)]);
    await tester.pump();
    expect(mirrors('ide'), isFalse);
    expect(hosts.hostOf(shell), ide);
  });

  Future<void> rightClick(WidgetTester tester, Finder tab) async {
    await tester.tap(tab, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  testWidgets('a terminal\'s tab menu: New Terminal, Rename, Clear, and '
      'the kills', (tester) async {
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(<FakePty>[]),
    );
    addTearDown(terminals.dispose);
    final hosts = TerminalHosts();
    addTearDown(hosts.dispose);
    final a = terminals.create();
    terminals.create();
    var made = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Material(
          child: TerminalDeck(
            place: 'panel',
            hosts: hosts,
            terminals: terminals,
            shown: a,
            onShow: (_) {},
            onNew: () {
              made++;
              return null;
            },
          ),
        ),
      ),
    );
    final tab = find.byKey(ObjectKey(a)).first;
    await rightClick(tester, tab);
    for (final item in [
      'New Terminal',
      'Rename...',
      'Clear',
      'Kill Terminal',
      'Kill Other Terminals',
      'Kill All Terminals',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('New Terminal'));
    await tester.pumpAndSettle();
    expect(made, 1);

    await rightClick(tester, tab);
    await tester.tap(find.text('Kill Other Terminals'));
    await tester.pumpAndSettle();
    expect(terminals.instances, [a]);
  });

  testWidgets('the background commands\' tab menu: stop, run again in a '
      'terminal, copy, clear', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final started = <FakePty>[];
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(started),
    );
    addTearDown(terminals.dispose);
    final hosts = TerminalHosts();
    addTearDown(hosts.dispose);
    KernelTask task(String id, CommandStatus status) => KernelTask(
      id: id,
      description: id,
      kind: KernelTaskKind.command,
      status: status,
      startedAt: DateTime(2026),
      outputFile: '/tmp/$id.output',
    );
    final tasks = _Tasks([
      task('lint', CommandStatus.succeeded),
      task('build', CommandStatus.running),
    ]);
    Object? shown;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => TerminalDeck(
              place: 'panel',
              hosts: hosts,
              terminals: terminals,
              shown: shown,
              onShow: (id) => setState(() => shown = id),
              onNew: terminals.create,
              tasks: tasks,
              files: _Output(),
            ),
          ),
        ),
      ),
    );
    // The one running shows in the tab.
    final tab = find.text('build');
    await rightClick(tester, tab);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Stop All Running Tasks'), findsNothing);
    expect(find.text('Clear'), findsNothing, reason: 'it runs');
    expect(find.text('Clear All Ended Tasks'), findsOneWidget);
    await tester.tap(find.text('Copy Command'));
    await tester.pumpAndSettle();
    await rightClick(tester, tab);
    await tester.tap(find.text('Copy Output'));
    await tester.pumpAndSettle();
    expect(copied, ['npm run build', 'output of /tmp/build.output']);

    await rightClick(tester, tab);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(tasks.stopped, ['build']);

    await rightClick(tester, tab);
    await tester.tap(find.text('Run in New Terminal'));
    await tester.pumpAndSettle();
    expect(terminals.instances, hasLength(1));
    expect(shown, terminals.instances.single);
    expect(started.single.written, contains('npm run build\r'));

    await rightClick(tester, find.text('build'));
    await tester.tap(find.text('Clear All Ended Tasks'));
    await tester.pumpAndSettle();
    expect([for (final task in tasks.tasks) task.id], ['build']);
  });
}
