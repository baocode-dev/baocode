import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface_controller.dart';
import 'package:monad/ide/ide_commands.dart';
import 'package:monad/ide/ide_editor.dart';
import 'package:monad/ide/ide_workbench.dart';
import 'package:monad/ide/ide_workspace.dart';
import 'package:monad/ide/lsp_ui/editor_language_session.dart';
import 'package:monad/ide/lsp_ui/lsp_convert.dart';

import '../workbench/fake_files.dart';
import 'fake_language_features.dart';

/// A native-editor workbench over [files] with [languages], [open] opened
/// (the last one active) and the editor focused.
Future<IdeWorkspace> pumpLanguageWorkbench(
  WidgetTester tester,
  Map<String, String> files,
  FakeLanguageFeatures languages, {
  List<String> open = const [],
  Set<String> ignoredRecommendations = const {},
  ValueChanged<String>? onIgnoreRecommendation,
}) async {
  final workspace = await pumpWorkbench(
    tester,
    files,
    open: open,
    nativeEditor: true,
    languages: languages,
    ignoredRecommendations: ignoredRecommendations,
    onIgnoreRecommendation: onIgnoreRecommendation,
  );
  addTearDown(languages.dispose);
  await tester.pump();
  if (open.isNotEmpty) {
    editorState(tester).focus();
    await tester.pump();
  }
  return workspace;
}

IdeEditorState editorState(WidgetTester tester) =>
    tester.state<IdeEditorState>(find.byType(IdeEditor));

IdeWorkbenchState workbenchState(WidgetTester tester) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

EditorSurfaceController surfaceController(WidgetTester tester) =>
    tester.widget<EditorSurface>(find.byType(EditorSurface)).controller;

EditorLanguageSession languageSession(WidgetTester tester) =>
    editorState(tester).languageSession!;

EditorSurfaceView surfaceView(WidgetTester tester) =>
    tester.state(find.byType(EditorSurface)) as EditorSurfaceView;

/// The global position of the middle of the character at [offset].
Offset globalAt(WidgetTester tester, int offset) {
  final view = surfaceView(tester);
  final rect = view.rangeRectAt(offset, offset + 1)!;
  return tester.getTopLeft(find.byType(EditorSurface)) + rect.center;
}

/// Lets debounces and async answers run.
Future<void> settle(
  WidgetTester tester, [
  Duration time = Duration.zero,
]) async {
  await tester.pump(time);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Places the caret at [offset] in the active editor.
Future<void> caretAt(WidgetTester tester, int offset) async {
  surfaceController(tester).select(offset, offset);
  await settle(tester);
}

/// The offset of the first [needle] (after [from]) in the active document.
int offsetOf(WidgetTester tester, String needle, {int from = 0}) {
  final text = surfaceController(tester).value.text;
  final at = text.indexOf(needle, from);
  expect(at, greaterThanOrEqualTo(0), reason: '"$needle" not in "$text"');
  return at;
}

void runCommand(WidgetTester tester, String id) {
  final command = workbenchState(tester).commands
      .firstWhere((command) => command.id == id);
  expect(command.enabled, isTrue, reason: '$id is disabled');
  command.run();
}

/// Presses [key] with the primary modifier (Ctrl off macOS) and others.
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool primary = false,
  bool shift = false,
  bool alt = false,
}) async {
  final mod = ideUsesMacKeys
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  if (primary) await tester.sendKeyDownEvent(mod);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (primary) await tester.sendKeyUpEvent(mod);
  await settle(tester);
}

String uriOf(String relative) => lspUriOfPath(inRoot(relative));
