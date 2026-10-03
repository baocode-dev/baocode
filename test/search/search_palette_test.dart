import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
import 'package:baocode/search/conversation_search.dart';
import 'package:baocode/search/search_palette.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/workspace.dart';

/// Kept conversations that say what is searched for in one session.
class _FakeSearch implements ConversationSearch {
  _FakeSearch(this.sessionId, this.text);

  final String sessionId;
  final String text;
  int prepared = 0;

  @override
  Future<void> prepare() async => prepared++;

  @override
  Future<List<ConversationHit>> search(String query, {int limit = 50}) async =>
      [?findIn(sessionId, text, query)];
}

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

Future<Workspace> _pumpApp(
  WidgetTester tester, {
  ConversationSearch? conversations,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KeybindingService.instance = KeybindingService();
  addTearDown(() => KeybindingService.instance = KeybindingService());
  final workspace = Workspace.mock();
  await tester.pumpWidget(
    BaoCodeApp(workspace: workspace, conversations: conversations),
  );
  await tester.pump();
  return workspace;
}

Finder _inPalette(Finder finder) =>
    find.descendant(of: find.byType(SearchPalette), matching: finder);

Finder _rich(String text) =>
    _inPalette(find.textContaining(text, findRichText: true));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_inPalette(find.byType(TextField)), text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

void main() {
  testWidgets('⌘P opens it on everything: recent agents, then actions', (
    tester,
  ) async {
    final search = _FakeSearch('none', '');
    await _pumpApp(tester, conversations: search);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPalette), findsOneWidget);
    expect(search.prepared, 1);
    expect(_inPalette(find.text('Recent Agents')), findsOneWidget);
    expect(_inPalette(find.text('Actions')), findsWidgets);
    expect(_rich('New Chat'), findsOneWidget);
    expect(_rich('Open Settings'), findsOneWidget);
    expect(_inPalette(find.text('Change Filter')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPalette), findsNothing);
  }, variant: _mac);

  testWidgets('finds agents by what was said in them, and opens them', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);
    final thread = workspace.threads.firstWhere(
      (thread) => thread.title == 'Flaky integration test on CI',
    );
    final search = _FakeSearch(
      thread.id ?? '#${identityHashCode(thread)}',
      'We should retry the websocket handshake twice before failing.',
    );
    await tester.pumpWidget(
      BaoCodeApp(workspace: workspace, conversations: search),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(Sidebar), matching: find.text('Search')),
    );
    await tester.pumpAndSettle();
    await _type(tester, 'handshake');
    expect(_inPalette(find.text('In Conversations')), findsOneWidget);
    expect(_rich('websocket handshake twice'), findsOneWidget);
    // The agent above its snippet.
    expect(_rich('Flaky integration test on CI'), findsOneWidget);

    await tester.tap(_rich('websocket handshake twice'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPalette), findsNothing);
    expect(workspace.selected, same(thread));
  }, variant: _mac);

  testWidgets('filters change with ⌘[ and ⌘]; actions run from the list', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    // ⇧⌘P: everything, as ⌘P.
    expect(_inPalette(find.text('Recent Agents')), findsOneWidget);
    expect(_rich('Toggle Primary Side Bar'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    // Round to the last: Settings, its pages.
    expect(_rich('Keyboard Shortcuts'), findsOneWidget);
    expect(_rich('Toggle Primary Side Bar'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    // Agents: the recent ones, all of them.
    expect(_inPalette(find.text('Recent Agents')), findsOneWidget);
    expect(_rich('Toggle Primary Side Bar'), findsNothing);

    await tester.tap(_inPalette(find.text('Actions')).first);
    await tester.pump();
    await _type(tester, 'toggle primary side bar');
    expect(find.byType(Sidebar), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPalette), findsNothing);
    // Hidden: slid out, then not built.
    expect(
      tester.getTopLeft(find.byType(Sidebar)).dx,
      lessThan(0),
      reason: 'the sidebar slides out of the window',
    );
  }, variant: _mac);
}
