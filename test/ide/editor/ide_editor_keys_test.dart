// The IDE editor's keys with the app's keybindings: every key runs a
// command of upstream's keybinding table (the defaults, a keymap's, the
// user's), so removing or rebinding one changes what the key does.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_keybindings.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/language/language_types.dart';
import 'package:baocode/ide/lsp_ui/language_widgets.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:path/path.dart' as p;

import '../lsp_ui/fake_language_features.dart';

class _Files implements IdeFileService {
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

  @override
  Future<void> create(String path, {bool directory = false}) =>
      throw UnsupportedError('create');

  @override
  Future<void> rename(String from, String to) =>
      throw UnsupportedError('rename');

  @override
  Future<void> copy(String from, String to) => throw UnsupportedError('copy');

  @override
  Future<void> delete(String path) => throw UnsupportedError('delete');

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      throw UnsupportedError('writeBytes');
}

final _root = p.join(p.separator, 'editor-keys-project');
final _file = p.join(_root, 'a.dart');

/// An editor with the workbench's part of the keys, as [IdeWorkbench] has
/// it: its context, its commands (Find and Replace here, and the editor's
/// palette commands), and the keys that bubble up to it.
class _Bench {
  _Bench(this.tester);

  final WidgetTester tester;
  final key = GlobalKey<IdeEditorState>();
  final ran = <String>[];

  IdeEditorState get editor => key.currentState!;

  EditorSurfaceController get controller =>
      tester.widget<EditorSurface>(find.byType(EditorSurface)).controller;

  TextSelection get selection => controller.value.selection;

  String get text => controller.value.text;

  Object? context(String name) {
    final editor = key.currentState;
    final text = editor?.hasTextFocus ?? false;
    final field =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    return switch (name) {
      'ideMode' => true,
      'editorTextFocus' || 'editorFocus' => text,
      'textInputFocus' || 'inputFocus' => text || field,
      _ => editor?.contextKey(name),
    };
  }

  Map<String, VoidCallback> commands() => {
    'actions.find': editor.openFind,
    'editor.action.startFindReplaceAction': editor.openReplace,
    for (final command in editor.editorCommands)
      if (command.enabled) command.id: command.run,
  };

  KeybindingResolution _resolve(
    KeyEvent event,
    Map<String, VoidCallback> commands,
  ) => KeybindingService.instance.resolveEvent(
    event,
    context: context,
    canRun: (item) => commands.containsKey(item.command),
  );

  /// [IdeEditor.keyResolver].
  String? resolve(KeyEvent event) => switch (_resolve(event, commands())) {
    KeybindingFound(:final command) => command,
    MoreChordsNeeded() => editorChordPrefix,
    NoKeybinding() => null,
  };

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final byId = commands();
    if (_resolve(event, byId) case KeybindingFound(:final command)) {
      ran.add(command);
      byId[command]!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

Future<_Bench> _pump(
  WidgetTester tester,
  String text, {
  FakeLanguageFeatures? languages,
}) async {
  final workspace = IdeWorkspace(
    _root,
    files: _Files({_file: text}),
    languages: languages,
  );
  addTearDown(workspace.dispose);
  if (languages != null) addTearDown(languages.dispose);
  await workspace.open(_file);
  final bench = _Bench(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Focus(
          onKeyEvent: bench.onKey,
          child: IdeEditor(
            key: bench.key,
            workspace: workspace,
            active: workspace.active!,
            nativeEditorEnabled: true,
            onError: (error) => fail('$error'),
            onEditorStatus: (_) {},
            onPositionChanged: (_) {},
            keyResolver: bench.resolve,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  bench.editor.focus();
  await _settle(tester);
  return bench;
}

/// Lets debounces and async answers run.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool shift = false,
  bool alt = false,
}) async {
  final modifiers = [
    if (meta) LogicalKeyboardKey.metaLeft,
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await _settle(tester);
}

TextSelection _at(int offset) => TextSelection.collapsed(offset: offset);

TextSelection _range(int base, int extent) =>
    TextSelection(baseOffset: base, extentOffset: extent);

/// The user's `keybindings.json`.
void _userKeybindings(List<KeybindingEntry> entries) =>
    KeybindingService.instance.userEntries = entries;

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  late KeybindingService saved;
  setUp(() {
    saved = KeybindingService.instance;
    KeybindingService.instance = KeybindingService();
  });
  tearDown(() => KeybindingService.instance = saved);

  group('keybinding table', () {
    test('every editor keybinding has a supported command, and a valid '
        '`when` of known context keys', () {
      final service = KeybindingService();
      for (final platform in KeybindingPlatform.values) {
        for (final (index, entry) in editorExtraKeybindings.indexed) {
          final item = KeybindingItem(
            entry: entry,
            source: KeybindingSource.defaults,
            platform: platform,
            index: index,
          );
          expect(service.isSupported(entry.command), isTrue, reason: '$entry');
          expect(item.keyError(platform), isNull, reason: '$entry');
          expect(item.when?.error, isNull, reason: '$entry');
          expect(
            item.unknownContextKeys(knownContextKeys),
            isEmpty,
            reason: '$entry',
          );
        }
      }
    });

    test('upstream\'s keys, per platform', () {
      final service = KeybindingService();
      String? run(
        KeybindingPlatform platform,
        List<KeyChord> chords, [
        Map<String, Object?> context = const {},
      ]) {
        final result = service
            .resolver(platform)
            .resolve(
              (key) =>
                  context[key] ??
                  switch (key) {
                    'editorTextFocus' ||
                    'editorFocus' ||
                    'textInputFocus' ||
                    'foldingEnabled' => true,
                    _ => false,
                  },
              chords.sublist(0, chords.length - 1),
              chords.last,
              canRun: (item) => service.isSupported(item.command),
            );
        return switch (result) {
          KeybindingFound(:final command) => command,
          MoreChordsNeeded() => editorChordPrefix,
          NoKeybinding() => null,
        };
      }

      KeyChord chord(
        LogicalKeyboardKey key, {
        bool ctrl = false,
        bool shift = false,
        bool alt = false,
        bool meta = false,
      }) => KeyChord(key, ctrl: ctrl, shift: shift, alt: alt, meta: meta);

      const mac = KeybindingPlatform.mac;
      const windows = KeybindingPlatform.windows;
      const linux = KeybindingPlatform.linux;
      const left = LogicalKeyboardKey.arrowLeft;
      expect(run(mac, [chord(left, alt: true)]), 'cursorWordLeft');
      expect(run(windows, [chord(left, ctrl: true)]), 'cursorWordLeft');
      expect(run(mac, [chord(left, meta: true)]), 'cursorHome');
      expect(
        run(mac, [chord(left, ctrl: true, alt: true)]),
        'cursorWordPartLeft',
      );
      expect(run(linux, [chord(LogicalKeyboardKey.home)]), 'cursorHome');
      expect(
        run(mac, [chord(LogicalKeyboardKey.keyA, ctrl: true)]),
        'cursorLineStart',
      );
      expect(
        run(mac, [chord(LogicalKeyboardKey.keyH, ctrl: true)]),
        'deleteLeft',
      );
      expect(
        run(windows, [chord(LogicalKeyboardKey.backspace, ctrl: true)]),
        'deleteWordLeft',
      );
      expect(
        run(mac, [chord(LogicalKeyboardKey.keyJ, ctrl: true)]),
        'editor.action.joinLines',
      );
      expect(
        run(windows, [
          chord(LogicalKeyboardKey.arrowRight, shift: true, alt: true),
        ]),
        'editor.action.smartSelect.expand',
      );
      expect(
        run(mac, [
          chord(
            LogicalKeyboardKey.arrowRight,
            ctrl: true,
            shift: true,
            meta: true,
          ),
        ]),
        'editor.action.smartSelect.expand',
      );
      expect(
        run(windows, [
          chord(LogicalKeyboardKey.bracketLeft, ctrl: true, shift: true),
        ]),
        'editor.fold',
      );
      expect(
        run(mac, [
          chord(LogicalKeyboardKey.keyK, meta: true),
          chord(LogicalKeyboardKey.digit0, meta: true),
        ]),
        'editor.foldAll',
      );
      expect(
        run(windows, [
          chord(LogicalKeyboardKey.keyK, ctrl: true),
          chord(LogicalKeyboardKey.digit2, ctrl: true),
        ]),
        'editor.foldLevel2',
      );
      // Snippets: Tab and Escape while in one.
      final snippet = {'inSnippetMode': true, 'hasNextTabstop': true};
      expect(
        run(linux, [chord(LogicalKeyboardKey.tab)], snippet),
        'jumpToNextSnippetPlaceholder',
      );
      expect(run(linux, [chord(LogicalKeyboardKey.tab)]), 'tab');
      expect(
        run(linux, [chord(LogicalKeyboardKey.escape)], snippet),
        'leaveSnippet',
      );
      // The find widget's keys take precedence over the editor's.
      final find = {'findWidgetVisible': true, 'editorHasSelection': true};
      expect(
        run(linux, [chord(LogicalKeyboardKey.escape)], find),
        'closeFindWidget',
      );
      expect(
        run(mac, [chord(LogicalKeyboardKey.keyC, alt: true, meta: true)], find),
        'toggleFindCaseSensitive',
      );
      expect(
        run(windows, [chord(LogicalKeyboardKey.keyC, alt: true)], find),
        'toggleFindCaseSensitive',
      );
      // Suggestions.
      final suggest = {
        'suggestWidgetVisible': true,
        'suggestWidgetMultipleSuggestions': true,
        'suggestWidgetHasFocusedSuggestion': true,
        'suggestionMakesTextEdit': true,
        'acceptSuggestionOnEnter': true,
      };
      for (final (key, command) in [
        (LogicalKeyboardKey.arrowDown, 'selectNextSuggestion'),
        (LogicalKeyboardKey.arrowUp, 'selectPrevSuggestion'),
        (LogicalKeyboardKey.pageDown, 'selectNextPageSuggestion'),
        (LogicalKeyboardKey.tab, 'acceptSelectedSuggestion'),
        (LogicalKeyboardKey.enter, 'acceptSelectedSuggestion'),
        (LogicalKeyboardKey.escape, 'hideSuggestWidget'),
      ]) {
        expect(run(linux, [chord(key)], suggest), command, reason: '$key');
      }
      expect(
        run(mac, [chord(LogicalKeyboardKey.keyN, ctrl: true)], suggest),
        'selectNextSuggestion',
      );
    });
  });

  testWidgets('Alt+Left is cursorWordLeft on macOS; removed, it does '
      'nothing; rebound, it runs the other command', (tester) async {
    final bench = await _pump(tester, 'foo bar baz');
    bench.controller.select(11, 11);
    await _press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(bench.selection, _at(8));

    _userKeybindings([const KeybindingEntry(command: '-cursorWordLeft')]);
    await _press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(bench.selection, _at(8));
    expect(bench.text, 'foo bar baz');

    _userKeybindings([
      const KeybindingEntry(command: '-cursorWordLeft'),
      const KeybindingEntry(key: 'alt+left', command: 'cursorLineStart'),
      const KeybindingEntry(key: 'alt+j', command: 'cursorWordRight'),
    ]);
    await _press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(bench.selection, _at(0));
    await _press(tester, LogicalKeyboardKey.keyJ, alt: true);
    expect(bench.selection, _at(3));
    expect(bench.ran, isEmpty, reason: 'the editor ran them');
  }, variant: _mac);

  testWidgets('Ctrl+Left and Ctrl+Backspace work by words off macOS; '
      'Backspace without deleteLeft does nothing', (tester) async {
    final bench = await _pump(tester, 'foo bar baz');
    bench.controller.select(11, 11);
    await _press(tester, LogicalKeyboardKey.arrowLeft, control: true);
    expect(bench.selection, _at(8));
    await _press(
      tester,
      LogicalKeyboardKey.arrowLeft,
      control: true,
      shift: true,
    );
    expect(bench.selection, _range(8, 4));
    await _press(tester, LogicalKeyboardKey.end);
    expect(bench.selection, _at(11));
    await _press(tester, LogicalKeyboardKey.backspace, control: true);
    expect(bench.text, 'foo bar ');

    _userKeybindings([const KeybindingEntry(command: '-deleteLeft')]);
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(bench.text, 'foo bar ');
    _userKeybindings([const KeybindingEntry(command: '-cursorWordLeft')]);
    await _press(tester, LogicalKeyboardKey.arrowLeft, control: true);
    expect(bench.selection, _at(8));
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(bench.text, 'foo bar');
  }, variant: _windows);

  testWidgets('macOS\'s Emacs-style Control keys', (tester) async {
    final bench = await _pump(tester, 'ab\ncd');
    bench.controller.select(1, 1);
    Future<void> control(LogicalKeyboardKey key) =>
        _press(tester, key, control: true);
    await control(LogicalKeyboardKey.keyE);
    expect(bench.selection, _at(2));
    await control(LogicalKeyboardKey.keyA);
    expect(bench.selection, _at(0));
    await control(LogicalKeyboardKey.keyF);
    expect(bench.selection, _at(1));
    await control(LogicalKeyboardKey.keyN);
    expect(bench.selection, _at(4));
    await control(LogicalKeyboardKey.keyP);
    expect(bench.selection, _at(1));
    await control(LogicalKeyboardKey.keyB);
    expect(bench.selection, _at(0));
    await control(LogicalKeyboardKey.keyD);
    expect(bench.text, 'b\ncd');
    await control(LogicalKeyboardKey.keyF);
    await control(LogicalKeyboardKey.keyH);
    expect(bench.text, '\ncd');
    await control(LogicalKeyboardKey.keyO);
    expect(bench.text, '\n\ncd');
    expect(bench.selection, _at(0));
  }, variant: _mac);

  testWidgets('Tab and Shift+Tab move between snippet placeholders, '
      'Escape leaves the snippet', (tester) async {
    final bench = await _pump(tester, '');
    bench.controller.insertSnippet(r'f(${1:a}, ${2:b})$0');
    await _settle(tester);
    expect(bench.selection, _range(2, 3));
    await _press(tester, LogicalKeyboardKey.tab);
    expect(bench.selection, _range(5, 6));
    await _press(tester, LogicalKeyboardKey.tab, shift: true);
    expect(bench.selection, _range(2, 3));
    await _press(tester, LogicalKeyboardKey.escape);
    expect(bench.controller.inSnippetMode, isFalse);
    expect(bench.selection, _range(2, 3));
    // Out of the snippet, Tab is `tab`.
    await _press(tester, LogicalKeyboardKey.tab);
    expect(bench.text, isNot('f(a, b)'));
  });

  testWidgets('Tab without jumpToNextSnippetPlaceholder runs `tab`', (
    tester,
  ) async {
    final bench = await _pump(tester, '');
    _userKeybindings([
      const KeybindingEntry(command: '-jumpToNextSnippetPlaceholder'),
    ]);
    bench.controller.insertSnippet(r'f(${1:a}, ${2:b})$0');
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.tab);
    expect(bench.selection, isNot(_range(5, 6)));
    expect(bench.text, isNot('f(a, b)'));
  });

  testWidgets('find: F3 from the text, Enter and Shift+Enter in the input, '
      'Alt+C (rebound), Escape', (tester) async {
    final bench = await _pump(tester, 'foo bar Foo baz foo');
    bench.controller.select(1, 1);
    // F3 searches for the word at the caret, and keeps the focus.
    await _press(tester, LogicalKeyboardKey.f3);
    expect(bench.editor.findVisible, isTrue);
    expect(bench.editor.findMatches, hasLength(3));
    expect(bench.selection, _range(8, 11));
    expect(bench.editor.hasTextFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.f3, shift: true);
    expect(bench.selection, _range(0, 3));
    // Escape closes the widget before it clears the selection.
    await _press(tester, LogicalKeyboardKey.escape);
    expect(bench.editor.findVisible, isFalse);
    expect(bench.selection, _range(0, 3));
    await _press(tester, LogicalKeyboardKey.escape);
    expect(bench.selection, _at(3));

    // In the find input (Ctrl+F is the workbench's).
    await _press(tester, LogicalKeyboardKey.keyF, control: true);
    expect(bench.ran, ['actions.find']);
    expect(bench.editor.hasTextFocus, isFalse);
    expect(bench.editor.hasFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(bench.selection, _range(8, 11));
    await _press(tester, LogicalKeyboardKey.enter);
    expect(bench.selection, _range(16, 19));
    await _press(tester, LogicalKeyboardKey.enter, shift: true);
    expect(bench.selection, _range(8, 11));
    await _press(tester, LogicalKeyboardKey.keyC, alt: true);
    expect(bench.editor.findMatches, hasLength(2));
    await _press(tester, LogicalKeyboardKey.keyC, alt: true);
    expect(bench.editor.findMatches, hasLength(3));
    // Text keys edit the input, not the document.
    final input = tester.widget<TextField>(
      find
          .descendant(
            of: find.byType(IdeFindWidget),
            matching: find.byType(TextField),
          )
          .first,
    );
    input.controller!.selection = _at(3);
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(input.controller!.text, 'fo');
    expect(bench.text, 'foo bar Foo baz foo');

    _userKeybindings([
      const KeybindingEntry(command: '-toggleFindCaseSensitive'),
      const KeybindingEntry(
        key: 'alt+x',
        command: 'toggleFindCaseSensitive',
        when: 'editorFocus',
      ),
    ]);
    await _press(tester, LogicalKeyboardKey.keyC, alt: true);
    expect(bench.editor.findMatches, hasLength(3));
    await _press(tester, LogicalKeyboardKey.keyX, alt: true);
    expect(bench.editor.findMatches, hasLength(2));

    await _press(tester, LogicalKeyboardKey.escape);
    expect(bench.editor.findVisible, isFalse);
    expect(bench.editor.hasTextFocus, isTrue);
  }, variant: _windows);

  group('suggestions', () {
    const source = 'void main() {\n  pri\n}\n';
    FakeLanguageFeatures languages() =>
        FakeLanguageFeatures()
          ..onCompletion = (path, position, trigger) => LspCompletionList([
            const LspCompletionItem(label: 'print'),
            const LspCompletionItem(label: 'printError'),
            const LspCompletionItem(label: 'private'),
          ]);

    testWidgets('arrows, pages, Tab, Escape', (tester) async {
      final bench = await _pump(tester, source, languages: languages());
      final session = bench.editor.languageSession!.suggest;
      final caret = source.indexOf('pri') + 3;
      bench.controller.select(caret, caret);
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.space, control: true);
      expect(find.byType(IdeSuggestWidget), findsOneWidget);
      expect(session.selectedIndex, 0);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(session.selectedIndex, 1);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(session.selectedIndex, 2);
      await _press(tester, LogicalKeyboardKey.pageUp);
      expect(session.selectedIndex, 0);
      await _press(tester, LogicalKeyboardKey.pageDown);
      expect(session.selectedIndex, 2);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(IdeSuggestWidget), findsNothing);
      expect(bench.selection, _at(caret));

      await _press(tester, LogicalKeyboardKey.space, control: true);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.tab);
      expect(find.byType(IdeSuggestWidget), findsNothing);
      expect(bench.text, 'void main() {\n  printError\n}\n');
    }, variant: _windows);

    testWidgets('rebinding acceptSelectedSuggestion', (tester) async {
      final bench = await _pump(tester, source, languages: languages());
      final caret = source.indexOf('pri') + 3;
      bench.controller.select(caret, caret);
      _userKeybindings([
        const KeybindingEntry(command: '-acceptSelectedSuggestion'),
        const KeybindingEntry(
          key: 'ctrl+j',
          command: 'acceptSelectedSuggestion',
          when: 'suggestWidgetVisible && textInputFocus',
        ),
      ]);
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.space, control: true);
      expect(find.byType(IdeSuggestWidget), findsOneWidget);
      // Enter types a line break now.
      await _press(tester, LogicalKeyboardKey.enter);
      expect(bench.text, startsWith('void main() {\n  pri\n'));
      bench.controller.undo();
      bench.controller.select(caret, caret);
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.space, control: true);
      expect(find.byType(IdeSuggestWidget), findsOneWidget);
      // Ctrl+J (the panel's by default) accepts: the user's keybinding wins.
      await _press(tester, LogicalKeyboardKey.keyJ, control: true);
      expect(bench.text, 'void main() {\n  print\n}\n');
      expect(bench.ran, isEmpty);
    }, variant: _windows);
  });

  testWidgets('parameter hints: Up and Down cycle, Escape closes', (
    tester,
  ) async {
    final fake = FakeLanguageFeatures()
      ..onSignatureHelp = (path, position) => const LspSignatureHelp([
        LspSignature('add(int a, int b)'),
        LspSignature('add(double a)'),
      ]);
    final bench = await _pump(tester, 'add', languages: fake);
    bench.controller.select(3, 3);
    await _settle(tester);
    bench.controller.type('(');
    await _settle(tester);
    expect(find.text('1/2'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('2/2'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.text('1/2'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeParameterHints), findsNothing);
    expect(bench.selection, _at(4));
  });

  testWidgets('rename: Enter accepts, Escape cancels', (tester) async {
    final fake = FakeLanguageFeatures()
      ..onPrepareRename = ((path, position) => (
        range: const LspRange(LspPosition(0, 4), LspPosition(0, 7)),
        placeholder: 'foo',
      ))
      ..onRename = (path, position, newName) => LspWorkspaceEdit({
        lspUriOfPath(_file): [
          LspTextEdit(
            const LspRange(LspPosition(0, 4), LspPosition(0, 7)),
            newName,
          ),
        ],
      });
    final bench = await _pump(tester, 'int foo = 1;\n', languages: fake);
    bench.controller.select(5, 5);
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.f2);
    expect(find.byType(IdeRenameInput), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeRenameInput), findsNothing);
    expect(fake.count('rename'), 0);

    await _press(tester, LogicalKeyboardKey.f2);
    final field = find.byKey(const ValueKey('ide-rename-field'));
    await tester.enterText(field, 'bar');
    await _press(tester, LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.byType(IdeRenameInput), findsNothing);
    expect(bench.text, 'int bar = 1;\n');
  });
}
