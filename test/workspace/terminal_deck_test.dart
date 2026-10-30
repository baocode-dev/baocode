// The chat's terminals in two places, the panel under the conversation and
// the side panel's page (see workspace/terminal_deck.dart): a terminal shows
// live in both, one place its view, the other mirroring it until pressed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_hosts.dart';
import 'package:baocode/ide/terminal/terminal_panel.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/terminal_deck.dart';

import '../ide/terminal/fake_pty.dart';
import '../ide/terminal/fake_terminal.dart';

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
}
