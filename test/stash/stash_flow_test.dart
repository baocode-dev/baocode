import 'dart:async';

import 'package:baocode/base/give_way_row.dart';
import 'package:baocode/stash/stash_note_editor.dart';
import 'package:baocode/stash/stash_ai.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/chat_models.dart' show oneLineExcerpt;
import 'package:baocode/chat/chat_session.dart' show ComposerMessage;
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/stash/stash_actions.dart';
import 'package:baocode/stash/stash_controller.dart';
import 'package:baocode/stash/stash_disk.dart';
import 'package:baocode/stash/stash_host.dart';
import 'package:baocode/stash/stash_note.dart';
import 'package:baocode/stash/stash_panel_view.dart';
import 'package:baocode/stash/stash_settings.dart';
import 'package:baocode/stash/stash_store.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/platform/app_platform.dart';
import 'package:baocode/theme/material_file_icons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/pin_window_button.dart';
import 'package:baocode/workspace/workspace.dart';

import '../window/fake_window_host.dart';

/// The system's windows, with the stash's panel.
class _StashWindowHost extends FakeWindowHost {
  _StashWindowHost(super.implicit);

  @override
  Future<int?> createStash() async {
    const id = 99;
    views[id] = FakeView(implicit, viewId: id);
    log.add('createStash');
    return id;
  }

  @override
  Future<void> showStash() async => log.add('showStash');

  @override
  Future<void> hideStash() async => log.add('hideStash');
}

void main() {
  late MemoryStashDisk disk;
  late StashStore store;
  late Workspace workspace;
  late _StashWindowHost host;
  late AppWindows windows;
  late StashController controller;

  const stashChannel = MethodChannel('test/stash');
  final hotkeys = <Object?>[];

  Future<void> setUpFlow(WidgetTester tester) async {
    hotkeys.clear();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      stashChannel,
      (call) async {
        if (call.method == 'setHotkey') hotkeys.add(call.arguments);
        return call.method == 'setHotkey' ? true : null;
      },
    );
    disk = MemoryStashDisk();
    store = StashStore(disk);
    workspace = Workspace.mock();
    host = _StashWindowHost(tester.view);
    windows = AppWindows(
      host: host,
      workspace: workspace,
      l10n: () => englishLocalizations,
      nextFrame: () async {},
    );
    await windows.start();
    controller = StashController(
      store: store,
      workspace: workspace,
      windows: windows,
      host: StashHost(channel: stashChannel),
    );
  }

  testWidgets('the shortcut shows the panel with a new stash, made at once, '
      'and hides it', (tester) async {
    await setUpFlow(tester);

    // From another app: nothing of it is kept.
    controller.pressed(StashCapture.none);
    await tester.pump();
    expect(host.log, containsAllInOrder(['createStash', 'showStash']));
    expect(controller.shown, isTrue);
    final id = controller.editing!;
    final note = store.byId(id)!;
    expect(note.source.isEmpty, isTrue);
    expect(note.project, isNull);
    await store.update(id, (note) => note.body = 'remember the cache bug');

    // The shortcut again, the panel in front: hidden, what was written kept.
    controller.pressed(const StashCapture(inApp: true, panelInFront: true));
    await tester.pump();
    expect(host.log.last, 'hideStash');
    expect(controller.shown, isFalse);
    expect(store.byId(id)!.body, 'remember the cache bug');

    // Shown again: another stash.
    controller.pressed(StashCapture.none);
    await tester.pump();
    expect(controller.editing, isNot(id));

    // Another app clicked meanwhile: the shortcut brings the panel back,
    // with the same stash.
    final again = controller.editing;
    final shows = host.log.where((entry) => entry == 'showStash').length;
    controller.pressed(const StashCapture(panelInFront: false));
    await tester.pump();
    expect(controller.shown, isTrue);
    expect(controller.editing, again);
    expect(
      host.log.where((entry) => entry == 'showStash'),
      hasLength(shows + 1),
    );

    await controller.hide();
    expect(store.notes.where((note) => !note.isBlank), hasLength(1));
    controller.dispose();
  });

  testWidgets('a stash left blank stays, the draft gone on with', (
    tester,
  ) async {
    await setUpFlow(tester);
    await controller.present();
    final first = controller.editing!;
    await controller.hide();
    expect(store.notes.map((note) => note.id), [first]);
    // Shown again: the same draft, no other made.
    await controller.present();
    expect(controller.editing, first);
    await controller.startNew();
    expect(controller.editing, first);

    // Written in, "New" makes one more; another picked, the blank one
    // stays a draft, and "New" goes back to it.
    await store.update(first, (note) => note.body = 'kept');
    await controller.startNew();
    final draft = controller.editing!;
    expect(draft, first + 1);
    await controller.edit(first);
    expect(store.byId(draft), isNotNull);
    await controller.startNew();
    expect(controller.editing, draft);
    expect(store.notes, hasLength(2));

    // One written and emptied is no draft: the shortcut does not go on
    // with it.
    await store.update(draft, (note) => note.body = 'soon gone');
    await store.update(draft, (note) => note.body = '');
    await controller.hide();
    await controller.present();
    expect(controller.editing, isNot(draft));
    expect(store.byId(controller.editing!)!.isDraft, isTrue);
    controller.dispose();
  });

  testWidgets('Clarify in the panel\'s bar: in the background, its answer '
      'in the text; failed, why on hover and again on a click', (tester) async {
    await setUpFlow(tester);
    final previous = ModelProviders.current;
    addTearDown(() => ModelProviders.current = previous);
    await (ModelProviders.current = ModelProviders.memory()).setActionsModel(
      ModelProviders.followAuxiliary,
    );
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final note = await store.create(body: 'btn hidden');
    await controller.edit(note.id);
    final answer = Completer<String>();
    controller.clarifier = (controller, id, text, {cancellation}) =>
        answer.future;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Material(
          child: StashPanelView(controller: controller, viewId: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = englishLocalizations;

    await tester.tap(find.text(l10n.stashExpand));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.clarifying(note.id), isTrue);
    expect(find.text(l10n.stashCancelClarify), findsOneWidget);
    await tester.tap(find.text(l10n.stashCancelClarify));
    await tester.pumpAndSettle();
    expect(controller.clarifying(note.id), isFalse);
    expect(find.text(l10n.stashExpand), findsOneWidget);
    answer.complete('Old reply');
    await tester.pumpAndSettle();
    expect(StashNoteEditorState.showing(note.id)!.markdown, 'btn hidden');
    expect(controller.clarifyFailure(note.id), isNull);

    final retry = Completer<String>();
    controller.clarifier = (controller, id, text, {cancellation}) =>
        retry.future;
    await tester.tap(find.text(l10n.stashExpand));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.clarifying(note.id), isTrue);
    retry.complete('The button is hidden.');
    await tester.pumpAndSettle();
    expect(controller.clarifying(note.id), isFalse);
    expect(
      StashNoteEditorState.showing(note.id)!.markdown,
      startsWith('The button is hidden.'),
    );

    var asked = 0;
    controller.clarifier = (controller, id, text, {cancellation}) async {
      asked++;
      throw const StashAiException('Not signed in');
    };
    await tester.tap(find.text(l10n.stashExpand));
    await tester.pumpAndSettle();
    expect(find.text(l10n.stashClarifyFailedShort), findsOneWidget);
    await tester.tap(find.text(l10n.stashClarifyFailedShort));
    await tester.pumpAndSettle();
    expect(asked, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    controller.dispose();
  });

  testWidgets('in a narrow panel the bar\'s pills give way to their icons, '
      'the pin and close button kept in it (#146)', (tester) async {
    await setUpFlow(tester);
    tester.view.physicalSize = const Size(560, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final note = await store.create(body: 'the bar runs out of the panel');
    await controller.edit(note.id);
    controller.showAll = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Material(
          child: StashPanelView(controller: controller, viewId: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = englishLocalizations;
    // The top bar's, not the footer's.
    final bar = find.byType(GiveWayRow).first;
    Finder inBar(Finder finder) => find.descendant(of: bar, matching: finder);
    final close = find
        .ancestor(
          of: inBar(find.byIcon(Codicons.close)),
          matching: find.byType(GestureDetector),
        )
        .first;

    // The list of all beside it: the stash 340 wide.
    expect(tester.getRect(close).right, lessThanOrEqualTo(560 - 8));
    expect(
      tester.getRect(find.byType(PinWindowButton)).right,
      lessThan(tester.getRect(close).left),
    );
    expect(inBar(find.text(l10n.stashAll)), findsNothing);
    expect(inBar(find.text(l10n.stashExpand)), findsNothing);
    expect(inBar(find.byIcon(Codicons.sparkle)), findsOneWidget);
    expect(inBar(find.text('#${note.id}')), findsOneWidget);

    // Wide, their words again.
    tester.view.physicalSize = const Size(1200, 600);
    await tester.pumpAndSettle();
    expect(inBar(find.text(l10n.stashAll)), findsOneWidget);
    expect(inBar(find.text(l10n.stashNewButton)), findsOneWidget);
    expect(inBar(find.text(l10n.stashExpand)), findsOneWidget);
    expect(inBar(find.text(l10n.stashNoProject)), findsOneWidget);
    expect(tester.getRect(close).right, 1200 - 8);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    controller.dispose();
  });

  testWidgets('the panel is not kept on top unless its pin is on', (
    tester,
  ) async {
    await setUpFlow(tester);
    const window = MethodChannel('baocode/window.7');
    final onTop = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (
      call,
    ) async {
      if (call.method == 'setAlwaysOnTop') onTop.add(call.arguments);
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Material(
          child: StashPanelView(controller: controller, viewId: 7),
        ),
      ),
    );
    await tester.pump();
    expect(onTop, [false]);

    await tester.tap(find.byType(PinWindowButton));
    await tester.pump();
    expect(controller.pinned, isTrue);
    expect(onTop, [false, true]);
    await tester.tap(find.byType(PinWindowButton));
    await tester.pump();
    expect(onTop, [false, true, false]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the list of all: icons and numbers, picked with the keys, '
      'selected with Cmd, dragged into an order, deleted', (tester) async {
    await setUpFlow(tester);
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final first = await store.create(body: 'first');
    final second = await store.create(body: 'second');
    final third = await store.create(body: 'third [doc.pdf](/tmp/doc.pdf)');
    await controller.edit(third.id);
    controller.showAll = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Material(
          child: StashPanelView(controller: controller, viewId: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder row(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(IdeListRow));
    expect(row('first'), findsOneWidget);
    expect(
      find.descendant(
        of: row('third doc.pdf'),
        matching: find.byType(FileIcon),
      ),
      findsOneWidget,
    );
    // Its number shows on hover only.
    final number = find.descendant(
      of: row('first'),
      matching: find.text('#${first.id}'),
    );
    expect(number, findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(row('first')));
    await tester.pump();
    expect(number, findsOneWidget);
    await mouse.removePointer();
    await tester.pump();

    // Clicked: shown, the keyboard left in the list; down goes on.
    await tester.tap(row('second'));
    await tester.pumpAndSettle();
    expect(controller.editing, second.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.editing, first.id);

    // Cmd (Ctrl) adds one; dragged below the last, both go there.
    final command = AppPlatform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(command);
    await tester.tap(row('third doc.pdf'));
    await tester.sendKeyUpEvent(command);
    await tester.pumpAndSettle();
    expect(tester.widget<IdeListRow>(row('third doc.pdf')).selected, isTrue);
    final bottom = tester.getBottomLeft(row('first'));
    final drag = await tester.startGesture(tester.getCenter(row('first')));
    await drag.moveBy(const Offset(0, 20));
    await tester.pump();
    await drag.moveTo(bottom + const Offset(40, 4));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(controller.sort, StashSort.manual);
    expect(
      [for (final note in store.sorted(store.notes, StashSort.manual)) note.id],
      [second.id, third.id, first.id],
    );

    // Renamed in its row with the explorer's key.
    await tester.sendKeyEvent(
      KeybindingService.instance.platform.name == 'mac'
          ? LogicalKeyboardKey.enter
          : LogicalKeyboardKey.f2,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.byId(first.id)!.title, 'renamed');
    expect(row('renamed'), findsOneWidget);

    // Deleted with the keys, after asking: the one above shown.
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(store.byId(first.id), isNull);
    expect(store.byId(third.id), isNull);
    expect(controller.editing, second.id);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    controller.dispose();
  });

  testWidgets('the panel closed by the system hides as asked', (tester) async {
    await setUpFlow(tester);
    windows.stashCloseRequested = () => controller.hide();
    await controller.present();
    windows.windowCloseRequested(99);
    await tester.pump();
    expect(host.log.last, 'hideStash');
    controller.dispose();
  });

  testWidgets('a conversation a message names a stash in is linked to it, '
      'and keeps what its agent last said', (tester) async {
    await setUpFlow(tester);
    await controller.start();
    // No shortcut taken unasked.
    expect(hotkeys, ['']);
    expect(controller.hotkeyTaken, isNull);
    final note = await store.create(body: 'Retry uploads on 503');
    final thread = workspace.threads.first;

    thread.session.send(ComposerMessage(text: 'Do [Stash #${note.id}] please'));
    await tester.pump();
    expect(thread.id, isNotNull);
    final linked = store.byId(note.id)!;
    expect(linked.status, StashStatus.implementing);
    expect(linked.threads.single.session, thread.id);
    expect(linked.threads.single.project, thread.project.path);
    expect(controller.threads.threadOf(linked.threads.single), thread);

    // Its turn over, what its agent said last goes with the link (and to
    // its file, for the cards while it is not open).
    for (var i = 0; i < 200 && thread.session.lastReply == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final reply = thread.session.lastReply;
    expect(reply, isNotNull);
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));
    final said = store.byId(note.id)!.threads.single;
    expect(said.said, oneLineExcerpt(reply!, max: 240));
    expect(said.title, thread.title);
    expect(said.at, isNotNull);
    expect(StashNote.decode(note.id, store.byId(note.id)!.encode()).threads, [
      said,
    ]);

    // Done stays done, named again.
    await store.update(note.id, (note) => note.status = StashStatus.done);
    thread.session.send(ComposerMessage(text: 'And [Stash #${note.id}]'));
    await tester.pump();
    expect(store.byId(note.id)!.status, StashStatus.done);
    expect(store.byId(note.id)!.threads, hasLength(1));
    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));

    // Dragged or mentioned into a message, it goes as a reference.
    final reference = stashReferenceOf(store, store.byId(note.id)!);
    expect(reference.reference, '[Stash #${note.id}]');
    final split = splitCodeAppendix(
      'do ${reference.reference}${codeAppendix([reference])}',
    );
    expect(split.references.values.single, isA<StashReference>());

    // Start's delayed panel, made: nothing left pending.
    await tester.pump(const Duration(seconds: 3));
    controller.dispose();
  });
}
