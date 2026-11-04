import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/chat/chat_models.dart' show FileChange;
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/review_store.dart';
import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_agent_edits.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelContext;
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../ide/workbench/fake_files.dart';

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

/// A review of one file, held against [base], recording what the side
/// panel asks of it.
class _Review extends ChangeReview {
  _Review(String root, this.file, this.base, {this.others = const []})
    : super(_NoStore(), root: root);

  final String file;
  String base;

  /// Other files with a change pending, after [file].
  final List<String> others;
  int _version = 0;
  final kept = <String>[];
  final keptFiles = <String>[];
  final settled = <String>[];

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
  Future<void> keep(Iterable<String> paths) async => keptFiles.addAll(paths);

  @override
  Future<String> Function()? original(String path) =>
      path == file ? () async => base : null;

  @override
  Future<void> keepPart(String path, String base) async {
    kept.add(base);
    this.base = base;
    _version++;
    notifyListeners();
  }

  @override
  Future<void> settle(Iterable<String> paths) async {
    settled.addAll(paths);
  }
}

final _root = p.join(p.separator, 'side-panel-agent-project');
final _file = p.join(_root, 'a.txt');

void main() {
  late _Files files;
  late _Review review;

  Future<void> pump(
    WidgetTester tester, {
    required String now,
    FileOpenRequest? request,
    List<String>? opened,
  }) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    files = _Files({_file: now});
    final chat = ChatSession(
      kernel: MockKernels.claudeCode,
      kernelContext: KernelContext(cwd: _root),
      historyCount: 0,
      openReview: (root, {session}) async => review,
    );
    addTearDown(chat.dispose);
    chat.attach();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // As the side panel builds it: anew as the review changes.
          body: ListenableBuilder(
            listenable: chat,
            builder: (context, _) => ListenableBuilder(
              listenable: chat.changeReview ?? chat,
              builder: (context, _) => FilePreview(
                request: request ?? FileOpenRequest(_file),
                files: files,
                root: _root,
                agentEdit: IdeAgentEdit.inSession(chat, _file),
                onOpenAgentChange: opened?.add,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  EditorSurfaceController controller(WidgetTester tester) =>
      tester.widget<EditorSurface>(find.byType(EditorSurface)).controller;

  String text(WidgetTester tester) => controller(tester).value.text;
  int caret(WidgetTester tester) =>
      controller(tester).value.selection.extentOffset;

  testWidgets('an agent change shows in the file with Undo and Keep, and '
      'its bar over it', (tester) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(tester, now: 'one\n2\n3\n4\nfive\n');
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    expect(surface.viewZones, hasLength(2));
    expect(find.text('Keep'), findsNWidgets(2));
    expect(find.text('Undo'), findsNWidgets(2));
    expect(find.text('Keep file'), findsOneWidget);
    expect(find.text('Undo file'), findsOneWidget);

    // Kept, the caret goes on to the next part.
    await tester.tap(find.text('Keep').first);
    await settle(tester);
    expect(review.kept, ['one\n2\n3\n4\n5\n']);
    expect(caret(tester), text(tester).indexOf('five'));
    expect(find.text('1/1'), findsOneWidget);

    // Undone: in the text, saved, and looked at again.
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(text(tester), 'one\n2\n3\n4\n5\n');
    expect(files.contents[_file], 'one\n2\n3\n4\n5\n');
    expect(review.settled, [_file]);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('opened for its change, the file is scrolled to the part '
      'asked for, the bar stepping through them', (tester) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(
      tester,
      now: 'one\n2\n3\n4\nfive\n',
      request: FileOpenRequest(_file, agentChange: true),
    );
    final now = text(tester);
    expect(caret(tester), now.indexOf('one'));
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byIcon(Codicons.arrowDown));
    await settle(tester);
    expect(caret(tester), now.indexOf('five'));
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.byIcon(Codicons.arrowUp));
    await settle(tester);
    expect(caret(tester), now.indexOf('one'));
  });

  testWidgets('opened for its change at a line, at that part', (tester) async {
    review = _Review(_root, _file, '1\n2\n3\n4\n5\n');
    await pump(
      tester,
      now: 'one\n2\n3\n4\nfive\n',
      request: FileOpenRequest(
        _file,
        agentChange: true,
        range: const FileLineRange(5),
      ),
    );
    expect(caret(tester), text(tester).indexOf('five'));
  });

  testWidgets('the file done, the next with a change pending opens', (
    tester,
  ) async {
    final b = p.join(_root, 'b.txt');
    final c = p.join(_root, 'c.txt');
    review = _Review(_root, _file, '1\n2\n', others: [b, c]);
    final opened = <String>[];
    await pump(tester, now: 'one\n2\n', opened: opened);

    // Its only part kept.
    await tester.tap(find.text('Keep'));
    await settle(tester);
    expect(review.kept, ['one\n2\n']);
    expect(opened, [b]);
  });

  testWidgets('kept from the bar, the next file opens; none after the '
      'last', (tester) async {
    final b = p.join(_root, 'b.txt');
    review = _Review(_root, _file, '1\n2\n', others: [b]);
    final opened = <String>[];
    await pump(tester, now: 'one\n2\n', opened: opened);
    await tester.tap(find.text('Keep file'));
    await settle(tester);
    expect(review.keptFiles, [_file]);
    expect(opened, [b]);

    review = _Review(_root, _file, '1\n2\n');
    opened.clear();
    await pump(tester, now: 'one\n2\n', opened: opened);
    await tester.tap(find.text('Keep file'));
    await settle(tester);
    expect(opened, isEmpty);
  });

  testWidgets('no change pending: no bar, no parts', (tester) async {
    review = _Review(_root, p.join(_root, 'other.txt'), '');
    await pump(tester, now: 'one\n');
    expect(find.text('Keep file'), findsNothing);
    expect(find.text('Keep'), findsNothing);
  });

  testWidgets('the text is searched as in the IDE: Ctrl+F, Enter, Escape', (
    tester,
  ) async {
    review = _Review(_root, p.join(_root, 'other.txt'), '');
    await pump(tester, now: 'alpha\nbeta\nalpha\n');
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'alpha');
    await tester.pump();
    final decorations = tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .decorations;
    expect(decorations, hasLength(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final first = controller(tester).value.selection;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final second = controller(tester).value.selection;
    expect({first.start, second.start}, {0, 'alpha\nbeta\n'.length});

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsNothing);
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
