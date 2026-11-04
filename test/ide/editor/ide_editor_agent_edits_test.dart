import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/chat/chat_models.dart' show FileChange;
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/review_store.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_agent_edits.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelContext;
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../workbench/fake_files.dart';

class _Files with ReadWriteOnlyFiles implements IdeFileService {
  _Files(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async =>
      contents[path] = text;
}

class _NoStore implements ReviewStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A review of one file, held against [base], recording what the editor
/// asks of it.
class _Review extends ChangeReview {
  _Review(String root, this.file, this.base, {this.others = const []})
    : super(_NoStore(), root: root);

  final String file;
  String base;

  /// Other files with a change pending, after [file].
  final List<String> others;
  int _version = 0;
  final kept = <String>[];
  final settled = <String>[];

  /// What keeping and settling wait on, as the store does.
  Completer<void>? hold;

  @override
  List<FileChange> get changes => [
    for (final path in [file, ...others])
      FileChange(path: path, added: 1, removed: 1),
  ];

  @override
  String? baseOf(String path) => path == file
      ? 'v$_version'
      : others.contains(path)
      ? 'v0'
      : null;

  @override
  Future<String> Function()? original(String path) =>
      path == file ? () async => base : null;

  @override
  Future<void> keepPart(String path, String base) async {
    await hold?.future;
    kept.add(base);
    this.base = base;
    _version++;
    notifyListeners();
  }

  @override
  Future<void> settle(Iterable<String> paths) async {
    await hold?.future;
    settled.addAll(paths);
  }
}

final _root = p.join(p.separator, 'agent-edits-project');
final _file = p.join(_root, 'a.txt');

void main() {
  late _Files files;
  late _Review review;

  Future<void> pump(WidgetTester tester, {required String now}) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    files = _Files({_file: now});
    final workspace = IdeWorkspace(_root, files: files);
    addTearDown(workspace.dispose);
    await workspace.open(_file);
    final chat = ChatSession(
      kernel: MockKernels.claudeCode,
      kernelContext: KernelContext(cwd: _root),
      historyCount: 0,
      openReview: (root, {session}) async => review,
    );
    addTearDown(chat.dispose);
    // As a view showing the conversation does: the review opens.
    chat.attach();
    final edits = IdeAgentEdits()..sessions = [chat];
    addTearDown(edits.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // As over the IDE's tabs.
              ListenableBuilder(
                listenable: edits,
                builder: (context, _) => switch (edits.of(_file)) {
                  final edit? => IdeAgentEditActions(
                    edit: edit,
                    hunks: edits.hunksOf(_file),
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
              Expanded(
                child: IdeEditor(
                  workspace: workspace,
                  active: workspace.active!,
                  nativeEditorEnabled: true,
                  onError: (error) => fail('$error'),
                  onLspStatus: (_) {},
                  onPositionChanged: (_) {},
                  agentEdits: edits,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await settle(tester);
  }

  int caret(WidgetTester tester) => tester
      .widget<EditorSurface>(find.byType(EditorSurface))
      .controller
      .value
      .selection
      .extentOffset;

  String text(WidgetTester tester) => tester
      .widget<EditorSurface>(find.byType(EditorSurface))
      .controller
      .value
      .text;

  testWidgets('shows each change in the file with Undo and Keep', (
    tester,
  ) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(tester, now: 'one\n2\n3\n4\nfive\n');
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    // The deleted lines above the changes.
    expect(surface.viewZones, hasLength(2));
    expect(find.text('Keep'), findsNWidgets(2));
    expect(find.text('Undo'), findsNWidgets(2));

    // The first kept: the file is held against it, and shows the other.
    await tester.tap(find.text('Keep').first);
    await settle(tester);
    expect(review.kept, ['one\n2\n3\n4\n5\n']);
    expect(find.text('Keep'), findsOneWidget);

    // The other undone: in the text, saved, and looked at again.
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(text(tester), 'one\n2\n3\n4\n5\n');
    expect(files.contents[_file], 'one\n2\n3\n4\n5\n');
    expect(review.settled, [_file]);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('shows Keep and Undo done before the review has them', (
    tester,
  ) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(tester, now: 'one\n2\n3\n4\nfive\n');
    final hold = review.hold = Completer<void>();

    await tester.tap(find.text('Keep').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Keep'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump();
    expect(text(tester), 'one\n2\n3\n4\n5\n');
    expect(find.text('Undo'), findsNothing);
    expect(review.kept, isEmpty);

    hold.complete();
    await settle(tester);
    expect(review.kept, ['one\n2\n3\n4\n5\n']);
    expect(review.settled, [_file]);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('after a part is kept or undone, the caret goes to the next', (
    tester,
  ) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n6\n7\n');
    await pump(tester, now: 'one\n2\n3\nfour\n5\n6\nseven\n');
    expect(find.text('Keep'), findsNWidgets(3));

    await tester.tap(find.text('Keep').first);
    await settle(tester);
    expect(caret(tester), text(tester).indexOf('four'));
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.text('Undo').first);
    await settle(tester);
    expect(text(tester), 'one\n2\n3\n4\n5\n6\nseven\n');
    expect(caret(tester), text(tester).indexOf('seven'));
    expect(find.text('1/1'), findsOneWidget);
  });

  testWidgets('the bar over the editor steps through the parts', (
    tester,
  ) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(tester, now: 'one\n2\n3\n4\nfive\n');
    final now = text(tester);
    await tester.tap(find.byIcon(Codicons.arrowDown));
    await settle(tester);
    expect(caret(tester), now.indexOf('one'));
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byIcon(Codicons.arrowDown));
    await settle(tester);
    expect(caret(tester), now.indexOf('five'));
    expect(find.text('2/2'), findsOneWidget);

    // Past the last, the first again; before the first, the last.
    await tester.tap(find.byIcon(Codicons.arrowDown));
    await settle(tester);
    expect(caret(tester), now.indexOf('one'));
    await tester.tap(find.byIcon(Codicons.arrowUp));
    await settle(tester);
    expect(caret(tester), now.indexOf('five'));
  });

  testWidgets('the first part is scrolled to when asked for', (tester) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(tester, now: '1\n2\nthree\n4\n5\n');
    expect(caret(tester), isNot(text(tester).indexOf('three')));
    final edits = tester.widget<IdeEditor>(find.byType(IdeEditor)).agentEdits!;
    edits.hunksOf(_file).reveal();
    await settle(tester);
    expect(caret(tester), text(tester).indexOf('three'));
  });

  testWidgets('the file done, the IDE opens the next with a change pending', (
    tester,
  ) async {
    final other = p.join(_root, 'b.txt');
    review = _Review(_root, _file, '1\n2\n', others: [other]);
    await pump(tester, now: 'one\n2\n');
    final edits = tester.widget<IdeEditor>(find.byType(IdeEditor)).agentEdits!;
    final opened = <String>[];
    edits.open = opened.add;

    await tester.tap(find.text('Keep'));
    await settle(tester);
    expect(opened, [other]);
  });

  testWidgets('shows nothing in a file with no change pending', (tester) async {
    review = _Review(_root, p.join(_root, 'other.txt'), '');
    await pump(tester, now: 'one\n');
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    expect(surface.viewZones, isEmpty);
    expect(find.text('Keep'), findsNothing);
  });
}

/// Lets the review open, the texts be read and the diff be computed.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  // The diff, computed again after an edit.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  await tester.pump();
}
