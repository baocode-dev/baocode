import 'dart:async';

import 'package:baocode/base/give_way_row.dart';
import 'package:baocode/chat/chat_session.dart' show ComposerMessage;
import 'package:baocode/forge/forge_accounts.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/forge/forge_api.dart' show ForgeState;
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/stash/stash_controller.dart';
import 'package:baocode/stash/stash_disk.dart';
import 'package:baocode/stash/stash_host.dart';
import 'package:baocode/stash/stash_note.dart';
import 'package:baocode/stash/stash_store.dart';
import 'package:baocode/stash/stash_thread_view.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../forge/forge_test.dart' show FakeForgeHttp;

void main() {
  testWidgets('a conversation\'s row shows the stash it carries out, which '
      'a click on it, or its menu, opens', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = StashStore(MemoryStashDisk());
    final workspace = Workspace.mock();
    final controller = StashController(
      store: store,
      workspace: workspace,
      host: StashHost(channel: const MethodChannel('test/stash-sidebar')),
    );
    addTearDown(controller.dispose);
    final thread = workspace.threads.first;
    thread.session.send(const ComposerMessage(text: 'Retry the uploads'));
    for (var i = 0; i < 50 && thread.id == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final session = thread.id!;
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));

    // The disk in memory: done in microtasks, in the test's own time.
    final note = await store.create(body: 'Uploads fail on 503');
    final opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Sidebar(
              workspace: workspace,
              onCollapse: () {},
              stashes: sidebarStashes(controller, opened.add),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('#${note.id}'), findsNothing);

    // Linked: its row says so at once.
    unawaited(
      store.update(note.id, (note) {
        note.threads.add(
          StashThreadLink(session: session, project: thread.project.path),
        );
      }, touch: false),
    );
    await tester.pump();
    final tag = find.text('#${note.id}');
    expect(tag, findsOneWidget);
    await tester.tap(tag);
    expect(opened, [note.id]);

    await tester.tap(find.text(thread.title), buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open Stash #${note.id}'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, [note.id, note.id]);
  });

  testWidgets('the pull request a conversation opened for its stash shows '
      'on its row, in its state; a click opens it', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = StashStore(MemoryStashDisk());
    final workspace = Workspace.mock();
    final controller = StashController(
      store: store,
      workspace: workspace,
      host: StashHost(channel: const MethodChannel('test/stash-sidebar')),
      accounts: ForgeAccounts(
        http: FakeForgeHttp(),
        secrets: MemorySecretStore(),
      ),
    );
    addTearDown(controller.dispose);
    final thread = workspace.threads.first;
    thread.session.send(const ComposerMessage(text: 'Retry the uploads'));
    for (var i = 0; i < 50 && thread.id == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final session = thread.id!;
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));

    const pull = 'https://github.com/o/r/pull/7';
    final note = await store.create(body: 'Uploads fail on 503');
    await store.update(note.id, (note) {
      note.threads.add(
        StashThreadLink(session: session, project: thread.project.path),
      );
      note.issues.add(
        StashIssueLink(
          url: pull,
          title: 'Retry uploads',
          state: 'merged',
          session: session,
        ),
      );
    }, touch: false);
    final shown = sidebarStashes(controller, (_) {});
    expect(shown.pulls(session), [
      (
        url: pull,
        tag: 'o/r#7',
        title: 'Retry uploads',
        state: ForgeState.merged,
      ),
    ]);
    expect(shown.pulls('another'), isEmpty);

    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Sidebar(
              workspace: workspace,
              onCollapse: () {},
              stashes: SidebarStashes(
                changes: shown.changes,
                of: shown.of,
                open: (_) {},
                pulls: shown.pulls,
                openPull: opened.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final tag = find.text('#7');
    expect(tag, findsOneWidget);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(of: tag, matching: find.byType(Row)).first,
        matching: find.byType(Icon),
      ),
    );
    expect(icon.icon, Codicons.gitMerge);
    await tester.tap(tag);
    expect(opened, [pull]);
  });

  testWidgets('in a narrow sidebar, what is beside a row\'s title gives way '
      'before it is cut, nothing pushed out of the row (#146)', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = StashStore(MemoryStashDisk());
    final workspace = Workspace.mock();
    final controller = StashController(
      store: store,
      workspace: workspace,
      host: StashHost(channel: const MethodChannel('test/stash-sidebar')),
      accounts: ForgeAccounts(
        http: FakeForgeHttp(),
        secrets: MemorySecretStore(),
      ),
    );
    addTearDown(controller.dispose);
    final thread = workspace.threads.first;
    thread.session.send(const ComposerMessage(text: 'Retry the uploads'));
    for (var i = 0; i < 50 && thread.id == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final session = thread.id!;
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));

    final first = await store.create(body: 'Uploads fail on 503');
    final second = await store.create(body: 'Retry them');
    for (final note in [first, second]) {
      await store.update(note.id, (note) {
        note.threads.add(
          StashThreadLink(session: session, project: thread.project.path),
        );
        note.issues.add(
          StashIssueLink(
            url: 'https://github.com/o/r/pull/1${note.id}',
            title: 'Retry uploads',
            state: 'open',
            session: session,
          ),
        );
      }, touch: false);
    }
    final shown = sidebarStashes(controller, (_) {});
    var width = 400.0;
    late StateSetter resize;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              resize = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: Sidebar(
                    workspace: workspace,
                    onCollapse: () {},
                    stashes: shown,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final row = find.ancestor(
      of: find.text(thread.title),
      matching: find.byType(GiveWayRow),
    );
    // Two of each: `#1 +1`, `#12 +1`.
    final stashTag = find.textContaining(RegExp(r'^#\d \+1$'));
    final pullTag = find.textContaining(RegExp(r'^#1\d \+1$'));
    final time = find.descendant(
      of: row,
      matching: find.text(
        relativeTime(thread.updatedAt, DateTime.now(), englishLocalizations),
      ),
    );
    expect(stashTag, findsOneWidget);
    expect(pullTag, findsOneWidget);
    expect(time, findsOneWidget);

    void fits() {
      final bounds = tester.getRect(row);
      for (final element
          in find
              .descendant(of: row, matching: find.byType(RichText))
              .evaluate()) {
        final rect = tester.getRect(
          find.byElementPredicate((e) => e == element),
        );
        expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
      }
      expect(
        tester.getSize(find.text(thread.title)).width,
        greaterThanOrEqualTo(80),
      );
    }

    fits();
    // Narrower: the time first, then the pull request's tag; the stash's
    // stays longest.
    resize(() => width = 300);
    await tester.pump();
    fits();
    expect(time, findsNothing);
    expect(pullTag, findsOneWidget);
    resize(() => width = 220);
    await tester.pump();
    fits();
    expect(pullTag, findsNothing);
    expect(stashTag, findsOneWidget);
  });

  testWidgets('with the Stash shown, the conversation picked before it is '
      'no longer shown picked', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = Workspace.mock();
    final thread = workspace.threads.first;
    var stashing = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Sidebar(
                  workspace: workspace,
                  onCollapse: () {},
                  onStash: () {},
                  stashing: stashing,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    bool picked(String label) => tester
        .widgetList<Semantics>(
          find.ancestor(of: find.text(label), matching: find.byType(Semantics)),
        )
        .any((semantics) => semantics.properties.selected ?? false);

    await tester.tap(find.text(thread.title));
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked(thread.title), isTrue);

    rebuild(() => stashing = true);
    await tester.pump();
    expect(picked(thread.title), isFalse);
    expect(picked('Stash'), isTrue);
  });
}
