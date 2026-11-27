import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_code_editor.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_tail_button.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workbench/fake_files.dart';

class _LogFiles with ReadWriteOnlyFiles implements IdeFileService {
  _LogFiles(this.contents);

  final Map<String, String> contents;
  int readCalls = 0;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async {
    readCalls++;
    final text = contents[path];
    if (text == null) throw IdeFileNotFoundException(path);
    return text;
  }

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    contents[path] = text;
  }
}

final _root = testRoot;
final _logPath = inRoot('server.log');
final _otherPath = inRoot('notes.txt');

String _logLines(int count) =>
    List.generate(count, (i) => '2026-11-27 09:00:${i.toString().padLeft(2, '0')} INFO line ${i + 1}').join('\n');

Widget _localizedApp(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

EditorSurfaceView _view(WidgetTester tester) =>
    tester.state(find.byType(EditorSurface)) as EditorSurfaceView;

/// Sends a mouse wheel scroll delta over the [EditorSurface].
Future<void> _wheelScroll(WidgetTester tester, double dy) async {
  final center = tester.getCenter(find.byType(EditorSurface));
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  tester.binding.handlePointerEvent(pointer.hover(center));
  tester.binding.handlePointerEvent(pointer.scroll(Offset(0, dy)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  group('IdeWorkspace tail mode', () {
    test('toggles tailing, enforces readOnly, and blocks dirty/non-file docs', () async {
      final files = _LogFiles({_logPath: 'line 1\nline 2'});
      final workspace = IdeWorkspace(
        _root,
        files: files,
        watch: (_) => const Stream.empty(),
        tailPollInterval: const Duration(milliseconds: 50),
      );
      addTearDown(workspace.dispose);

      await workspace.open(_logPath);
      final doc = workspace.active!;
      expect(doc.canTail, isTrue);
      expect(doc.tailing, isFalse);
      expect(doc.readOnly, isFalse);

      // Dirty documents cannot enter tail mode.
      workspace.edit(_logPath, 'unsaved edit');
      expect(doc.dirty, isTrue);
      workspace.setTailing(doc, true);
      expect(doc.tailing, isFalse);

      // Save, then tail works and sets readOnly.
      await workspace.save(doc);
      expect(doc.dirty, isFalse);
      workspace.toggleTailing(doc);
      expect(doc.tailing, isTrue);
      expect(doc.readOnly, isTrue);

      // Workspace programmatic edits are ignored while tailing (read-only).
      final beforeEdit = doc.text;
      workspace.edit(_logPath, 'blocked edit');
      workspace.applyEdits(_logPath, [
        EditorDocumentEdit(Range(1, 1, 1, 2), 'X'),
      ]);
      expect(doc.text, beforeEdit);
      expect(doc.dirty, isFalse);

      // Toggling off restores editability.
      workspace.toggleTailing(doc);
      expect(doc.tailing, isFalse);
      expect(doc.readOnly, isFalse);

      // Untitled documents cannot be tailed.
      final untitled = workspace.newUntitled();
      expect(untitled.canTail, isFalse);
      workspace.setTailing(untitled, true);
      expect(untitled.tailing, isFalse);
    });

    test('polls tailed files even without directory watch events', () async {
      final files = _LogFiles({_logPath: 'start'});
      final workspace = IdeWorkspace(
        _root,
        files: files,
        watch: (_) => const Stream.empty(),
        tailPollInterval: const Duration(milliseconds: 40),
      );
      addTearDown(workspace.dispose);

      await workspace.open(_logPath);
      final doc = workspace.active!;
      workspace.setTailing(doc, true);

      files.contents[_logPath] = 'start\nappended line';
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(doc.text, 'start\nappended line');
      expect(doc.dirty, isFalse);

      // Stopping tail stops polling.
      workspace.setTailing(doc, false);
      final readsAfterStop = files.readCalls;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(files.readCalls, readsAfterStop);
    });

    test('throttles rapid directory watch bursts without starving tailed reloads', () async {
      final files = _LogFiles({_logPath: 'v0'});
      final watch = StreamController<void>.broadcast();
      addTearDown(watch.close);
      final workspace = IdeWorkspace(
        _root,
        files: files,
        watch: (_) => watch.stream,
        tailPollInterval: const Duration(hours: 1),
      );
      addTearDown(workspace.dispose);

      await workspace.open(_logPath);
      final doc = workspace.active!;
      workspace.setTailing(doc, true);
      await Future<void>.delayed(Duration.zero);

      // Emit watch events every 40ms (faster than the 100ms debounce window).
      for (var i = 1; i <= 5; i++) {
        files.contents[_logPath] = 'v$i';
        watch.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(doc.text, 'v5');
    });
  });

  group('IDE TabBar & IdeEditor tail UI', () {
    testWidgets('clicking eye icon tails, auto-scrolls, pauses on scroll-up, and resumes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final files = _LogFiles({
        _logPath: _logLines(120),
        _otherPath: 'hello',
      });
      final watch = StreamController<void>.broadcast();
      addTearDown(watch.close);
      final workspace = IdeWorkspace(
        _root,
        files: files,
        watch: (_) => watch.stream,
        tailPollInterval: const Duration(hours: 1),
      );
      addTearDown(workspace.dispose);
      await workspace.open(_logPath);

      await tester.pumpWidget(
        _localizedApp(
          ListenableBuilder(
            listenable: workspace,
            builder: (context, _) {
              final active = workspace.active!;
              return Column(
                children: [
                  IdeTabBar(
                    documents: workspace.documents,
                    active: active,
                    root: _root,
                    onSelect: (doc) => workspace.select(doc.key),
                    onClose: workspace.close,
                    onAction: (_, _) {},
                    onToggleTail: workspace.toggleTailing,
                  ),
                  Expanded(
                    child: IdeEditor(
                      workspace: workspace,
                      active: active,
                      nativeEditorEnabled: true,
                      onError: (e) => fail('Unexpected error: $e'),
                      onLspStatus: (_) {},
                      onPositionChanged: (_) {},
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Initially at top, not tailing; tab bar stays clean with no eye button.
      expect(_view(tester).visibleLineRange!.first, 1);
      expect(_view(tester).isAtBottom(), isFalse);
      expect(find.byType(IdeTailActionButton), findsNothing);
      expect(find.byType(IdeTailJumpButton), findsNothing);

      // Open the `...` More Actions menu and enable Tail.
      await tester.tap(find.byIcon(Codicons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tail File (Follow Changes)'));
      await tester.pumpAndSettle();

      expect(workspace.active!.tailing, isTrue);
      expect(workspace.active!.readOnly, isTrue);
      expect(_view(tester).isAtBottom(), isTrue);
      expect(_view(tester).visibleLineRange!.last, 120);
      // While active, the 1-click stop eye button shows in the tab bar actions.
      expect(find.byType(IdeTailActionButton), findsOneWidget);
      expect(find.byIcon(Codicons.eye), findsOneWidget);

      // Append new log lines and reload -> viewport auto-scrolls to new bottom.
      files.contents[_logPath] = _logLines(150);
      await workspace.reload([_logPath]);
      await tester.pump();
      await tester.pump();

      expect(_view(tester).isAtBottom(), isTrue);
      expect(_view(tester).visibleLineRange!.last, 150);
      expect(find.byType(IdeTailJumpButton), findsNothing);

      // Scroll up manually -> pauses auto-scroll and shows the jump button.
      await _wheelScroll(tester, -400);
      await tester.pump();
      expect(_view(tester).isAtBottom(), isFalse);
      final pausedTop = _view(tester).scrollOffset.dy;
      expect(find.byType(IdeTailJumpButton), findsOneWidget);

      // New lines arrive while paused -> text updates, scroll stays put!
      files.contents[_logPath] = _logLines(180);
      await workspace.reload([_logPath]);
      await tester.pump();
      await tester.pump();

      expect(workspace.active!.model.snapshot.lineCount, 180);
      expect(_view(tester).scrollOffset.dy, closeTo(pausedTop, 1.0));
      expect(find.byType(IdeTailJumpButton), findsOneWidget);

      // Click the floating jump-to-bottom button -> jumps & resumes tailing.
      await tester.tap(find.byType(IdeTailJumpButton));
      await tester.pump();
      await tester.pump();

      expect(_view(tester).isAtBottom(), isTrue);
      expect(_view(tester).visibleLineRange!.last, 180);
      expect(find.byType(IdeTailJumpButton), findsNothing);

      // Subsequent append auto-scrolls again.
      files.contents[_logPath] = _logLines(200);
      await workspace.reload([_logPath]);
      await tester.pump();
      await tester.pump();
      expect(_view(tester).visibleLineRange!.last, 200);

      // Trying to edit while tailing shows an inline tooltip at the caret.
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      final textBeforeKey = workspace.active!.text;
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(workspace.active!.text, textBeforeKey);
      expect(find.byType(IdeEditorCaretTooltip), findsOneWidget);
      expect(
        find.text('Read-only while tailing (tail -f). Stop tailing to edit.'),
        findsOneWidget,
      );

      // Escape dismisses the inline tooltip.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(IdeEditorCaretTooltip), findsNothing);

      // Click the active eye button to stop tailing -> tab bar is clean again.
      await tester.tap(find.byType(IdeTailActionButton));
      await tester.pump();
      expect(workspace.active!.tailing, isFalse);
      expect(workspace.active!.readOnly, isFalse);
      expect(find.byType(IdeTailActionButton), findsNothing);
      expect(find.byIcon(Codicons.eye), findsNothing);
    });
  });

  group('Side panel FilePreview tail mode', () {
    testWidgets('clicking eye icon tails log file and resumes after scroll-up', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final files = _LogFiles({_logPath: _logLines(100)});
      final watch = StreamController<void>.broadcast();
      addTearDown(watch.close);

      await tester.pumpWidget(
        _localizedApp(
          FilePreview(
            request: FileOpenRequest(_logPath),
            files: files,
            root: _root,
            watchDirectory: (_) => watch.stream,
            tailPollInterval: const Duration(hours: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(IdeCodeEditor), findsOneWidget);
      expect(find.byType(IdeTailActionButton), findsOneWidget);
      expect(_view(tester).visibleLineRange!.first, 1);

      // Click eye icon to start tailing.
      await tester.tap(find.byType(IdeTailActionButton));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<IdeCodeEditor>(find.byType(IdeCodeEditor)).readOnly,
        isTrue,
      );
      expect(_view(tester).isAtBottom(), isTrue);
      expect(_view(tester).visibleLineRange!.last, 100);

      // Append lines and notify directory watcher.
      files.contents[_logPath] = _logLines(130);
      watch.add(null);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.pump();

      expect(_view(tester).isAtBottom(), isTrue);
      expect(_view(tester).visibleLineRange!.last, 130);

      // Scroll up manually -> pauses and shows jump button.
      await _wheelScroll(tester, -400);
      await tester.pump();
      expect(_view(tester).isAtBottom(), isFalse);
      expect(find.byType(IdeTailJumpButton), findsOneWidget);

      // Click jump button -> returns to bottom and resumes.
      await tester.tap(find.byType(IdeTailJumpButton));
      await tester.pump();
      await tester.pump();
      expect(_view(tester).isAtBottom(), isTrue);
      expect(find.byType(IdeTailJumpButton), findsNothing);

      // Trying to edit while tailing shows the caret tooltip without editing.
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.byType(IdeEditorCaretTooltip), findsOneWidget);

      // Click eye icon again -> stops tailing, hides tooltip, restores editability.
      await tester.tap(find.byType(IdeTailActionButton));
      await tester.pump();
      expect(find.byType(IdeEditorCaretTooltip), findsNothing);
      expect(
        tester.widget<IdeCodeEditor>(find.byType(IdeCodeEditor)).readOnly,
        isFalse,
      );
    });
  });
}
