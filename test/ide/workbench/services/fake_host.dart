import 'package:flutter/widgets.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/views.dart';

/// What a service asks of the window, recorded.
class FakeWorkbenchHost implements WorkbenchHost {
  final List<String> calls = [];
  IdeSideView shown = IdeSideView.explorer;
  final List<IdeQuickInputModel> models = [];

  @override
  BuildContext? context;

  @override
  bool get editorBusy => false;

  @override
  Future<void> flushEditor() async {}

  @override
  void focusEditor() => calls.add('focusEditor');

  @override
  void focusSoon() => calls.add('focusSoon');

  @override
  bool executeCommand(String id, [Object? args]) {
    calls.add('executeCommand $id $args');
    return true;
  }

  @override
  Future<void> openEditorWith(
    Future<void> Function() open, {
    bool focusEditor = false,
  }) async {
    calls.add('openEditorWith focus=$focusEditor');
    await open();
  }

  @override
  Future<void> openFile(
    String path, {
    int? line,
    int? column,
    LspRange? range,
    bool focusEditor = false,
  }) async =>
      calls.add(line == null ? 'openFile $path' : 'openFile $path:$line');

  @override
  Future<void> openInDefaultApp(String path) async =>
      calls.add('openInDefaultApp $path');

  @override
  void revealLine(int line, [int column = 1]) =>
      calls.add('revealLine $line:$column');

  @override
  void revealRange(
    LspRange range, {
    bool select = false,
    bool center = false,
  }) => calls.add('revealRange ${range.start.line}');

  @override
  void focusPanel() => calls.add('focusPanel');

  @override
  Future<void> openLocation(
    IdeLocation location, {
    bool select = false,
    bool record = true,
    VoidCallback? afterReveal,
  }) async {
    calls.add('openLocation ${location.path}');
    afterReveal?.call();
  }

  @override
  void report(Object error) => calls.add('report $error');

  @override
  Future<void> selectEditor(IdeDocument doc) async =>
      calls.add('selectEditor ${doc.name}');

  @override
  void showQuickModel(IdeQuickInputModel model) => models.add(model);

  @override
  IdeSideView get view => shown;

  @override
  void showView(IdeSideView view) => shown = view;
}
