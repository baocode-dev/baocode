import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/keybindings/keybindings_editing.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/pages/keybindings_page.dart';
import 'package:baocode/theme/app_theme.dart';

const _toggleSidebar = 'workbench.action.toggleSidebarVisibility';
const _toggleSidebarTitle = 'View: Toggle Primary Side Bar Visibility';

/// keybindings.json in memory: nothing on disk.
class _MemoryFile extends JsoncFile {
  _MemoryFile(this.text) : super('/memory/User/keybindings.json');

  String? text;

  @override
  Object? get value => switch (text) {
    final String text => parseJsonc(text),
    null => null,
  };

  @override
  Future<String?> readText() async => text;

  @override
  Future<void> writeText(String text) async {
    this.text = text;
    notifyListeners();
  }

  @override
  Future<void> transform(String? Function(String? text) change) async {
    final next = change(text);
    if (next != null && next != text) await writeText(next);
  }
}

void main() {
  late _MemoryFile file;
  late KeybindingService service;
  late List<String?> keymapsSelected;
  late int imports;

  setUp(() {
    keymapsSelected = [];
    imports = 0;
  });

  Future<void> open(
    WidgetTester tester, {
    String? text,
    List<KeymapChoice> keymaps = const [],
  }) async {
    tester.view.physicalSize = const Size(700, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    file = _MemoryFile(text);
    service = KeybindingService()
      ..debugPlatform = KeybindingPlatform.mac
      ..userEntries = KeybindingEntry.listFromJson(file.value);
    // As the app keeps them: the file's entries are the user's.
    file.addListener(
      () => service.userEntries = KeybindingEntry.listFromJson(file.value),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeybindingsSettingsPage(
            keybindings: service,
            editing: KeybindingsEditingService(
              file,
              platform: KeybindingPlatform.mac,
            ),
            keymaps: keymaps,
            onSelectKeymap: keymapsSelected.add,
            onImport: () => imports++,
          ),
        ),
      ),
    );
  }

  Finder searchField() => find.bySemanticsLabel('Search keybindings');

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
  }

  List<Object?> entries() => parseJsonc(file.text ?? '[]')! as List<Object?>;

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [],
  }) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(
      finder,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists keybindings and unbound commands, and searches them', (
    tester,
  ) async {
    await open(tester);
    expect(searchField(), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);

    await search(tester, 'toggle primary side bar');
    expect(find.text(_toggleSidebarTitle), findsOneWidget);
    expect(find.text(_toggleSidebar), findsOneWidget);
    expect(find.text('⌘B'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);

    // By key, when and id as well.
    await search(tester, 'shift+cmd+e');
    expect(find.text('View: Show Explorer'), findsOneWidget);
    expect(find.text(_toggleSidebarTitle), findsNothing);
    await search(tester, 'terminalFocus next');
    expect(find.text('workbench.action.terminal.focusNext'), findsOneWidget);

    // A command without a keybinding.
    await search(tester, 'close other editors');
    expect(find.text('View: Close Other Editors'), findsOneWidget);
    expect(find.text('workbench.action.closeOtherEditors'), findsOneWidget);

    await search(tester, 'nothing like this');
    expect(find.text('No keybindings found'), findsOneWidget);
  });

  testWidgets('Record Keys searches by the keys pressed', (tester) async {
    await open(tester);
    await tester.tap(find.byType(IdeInputToggle));
    await tester.pump();
    expect(find.text('Recording Keys'), findsOneWidget);

    await press(
      tester,
      LogicalKeyboardKey.keyE,
      modifiers: [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('"shift+cmd+e"'), findsOneWidget);
    expect(find.text('View: Show Explorer'), findsOneWidget);
    expect(find.text(_toggleSidebarTitle), findsNothing);

    // Two chords; a third starts over.
    await press(
      tester,
      LogicalKeyboardKey.keyK,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('"shift+cmd+e cmd+k"'), findsOneWidget);
    expect(find.text('No keybindings found'), findsOneWidget);
    await press(
      tester,
      LogicalKeyboardKey.keyK,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('"cmd+k"'), findsOneWidget);
    await press(
      tester,
      LogicalKeyboardKey.keyS,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('"cmd+k cmd+s"'), findsOneWidget);
    expect(find.text('Preferences: Open Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('View: Show Explorer'), findsNothing);
    // Typing adds nothing.
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.pump();
    expect(find.text('"cmd+k cmd+s"'), findsOneWidget);
    await press(
      tester,
      LogicalKeyboardKey.keyB,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('"cmd+b"'), findsOneWidget);
    expect(find.text(_toggleSidebarTitle), findsOneWidget);

    // Escape stops recording; the filter stays.
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('Recording Keys'), findsNothing);
    expect(find.text('"cmd+b"'), findsOneWidget);
    expect(find.text(_toggleSidebarTitle), findsOneWidget);
  });

  testWidgets('the recording dialog writes the key pressed', (tester) async {
    await open(tester, text: '// mine\n[\n]\n');
    await search(tester, 'toggle primary side bar');
    await tester.tap(find.text(_toggleSidebarTitle));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.enter);
    expect(
      find.text('Press desired key combination and then press Enter.'),
      findsOneWidget,
    );

    await press(
      tester,
      LogicalKeyboardKey.keyB,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('cmd+b'), findsOneWidget);
    expect(find.text('1 existing command has this keybinding'), findsOneWidget);
    // Escape clears what was pressed, then closes.
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('cmd+b'), findsNothing);
    expect(
      find.text('Press desired key combination and then press Enter.'),
      findsOneWidget,
    );

    await press(
      tester,
      LogicalKeyboardKey.keyB,
      modifiers: [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
    );
    expect(find.text('⌃⇧B'), findsNWidgets(1));
    expect(find.textContaining('existing command'), findsNothing);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.text('Press desired key combination and then press Enter.'),
      findsNothing,
    );
    expect(entries(), [
      {'key': 'ctrl+shift+b', 'command': _toggleSidebar},
      {'key': 'cmd+b', 'command': '-$_toggleSidebar'},
    ]);
    expect(file.text, startsWith('// mine\n'));
    // The row follows the file.
    expect(find.text('⌃⇧B'), findsOneWidget);
    expect(find.text('⌘B'), findsNothing);
    expect(find.text('User'), findsOneWidget);
  });

  testWidgets('a double click binds a command without a keybinding', (
    tester,
  ) async {
    await open(tester);
    await search(tester, 'close editors to the right');
    final title = find.text('View: Close Editors to the Right');
    await tester.tap(title);
    await tester.tap(title);
    await tester.pump();
    expect(
      find.text('Press desired key combination and then press Enter.'),
      findsOneWidget,
    );
    // Two chords, "chord to" between them.
    await press(
      tester,
      LogicalKeyboardKey.keyK,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    await press(
      tester,
      LogicalKeyboardKey.keyO,
      modifiers: [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.metaLeft],
    );
    expect(find.text('chord to'), findsOneWidget);
    expect(find.text('cmd+k alt+cmd+o'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(entries(), [
      {
        'key': 'cmd+k alt+cmd+o',
        'command': 'workbench.action.closeEditorsToTheRight',
      },
    ]);
    expect(file.text, startsWith('// Place your key bindings'));
    expect(find.text('⌘K'), findsOneWidget);
    expect(find.text('⌥⌘O'), findsOneWidget);
  });

  testWidgets('fits a small dialog', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(360, 420);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Source'), findsNothing);
    await search(tester, 'toggle primary side bar');
    expect(find.text('⌘B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the recording dialog is cancelled by Escape', (tester) async {
    await open(tester);
    await search(tester, 'toggle primary side bar');
    await tester.tap(find.text(_toggleSidebarTitle));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.text('Press desired key combination and then press Enter.'),
      findsNothing,
    );
    expect(file.text, isNull);
  });

  testWidgets('marks unsupported commands, bad keys and unknown when keys', (
    tester,
  ) async {
    await open(
      tester,
      text: '''
[
  {
    "key": "cmd+3",
    "command": "workbench.action.toggleAgentsFromKeyboard"
  },
  {"key": "cmd+4", "command": "workbench.view.explorer", "when": "fooBarFocus && editorFocus"},
  {"key": "hyper+x", "command": "workbench.view.search"},
  {"key": "cmd+5", "command": "workbench.view.scm", "when": "a =~ /b/"}
]''',
    );
    await search(tester, 'toggleAgents');
    final id = find.text('workbench.action.toggleAgentsFromKeyboard');
    expect(id, findsOneWidget);
    expect(find.text('Not supported'), findsOneWidget);
    expect(tester.widget<Text>(id).style?.color, AppColors.textFaint);
    expect(find.text('User'), findsOneWidget);

    Finder warning(String containing) => find.byWidgetPredicate(
      (widget) =>
          widget is IdeHover && (widget.message?.contains(containing) ?? false),
    );
    await search(tester, 'fooBarFocus');
    expect(find.text('fooBarFocus && editorFocus'), findsOneWidget);
    expect(warning('context key fooBarFocus'), findsOneWidget);
    expect(find.text('Not supported'), findsNothing);

    await search(tester, 'hyper');
    expect(find.text('hyper+x'), findsOneWidget);
    expect(warning('cannot read the key “hyper+x”'), findsOneWidget);

    await search(tester, 'workbench.view.scm');
    expect(warning('does not parse'), findsOneWidget);
  });

  testWidgets('the keymap dropdown and the import call back', (tester) async {
    await open(
      tester,
      keymaps: const [
        (id: 'ms-vscode.atom-keybindings', name: 'Atom'),
        (id: 'k--kato.intellij-idea-keybindings', name: 'JetBrains'),
      ],
    );
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(find.text('JetBrains'), findsOneWidget);
    await tester.tap(find.text('Atom'));
    await tester.pumpAndSettle();
    expect(keymapsSelected, ['ms-vscode.atom-keybindings']);

    service.setKeymap('ms-vscode.atom-keybindings', name: 'Atom Keymap');
    await tester.pump();
    expect(find.text('Atom'), findsOneWidget);
    await tester.tap(find.text('Atom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(keymapsSelected, ['ms-vscode.atom-keybindings', null]);

    await tester.tap(find.text('Import from VS Code/Cursor…'));
    expect(imports, 1);
  });

  testWidgets('the context menu removes, resets and changes the when', (
    tester,
  ) async {
    await open(tester);
    await search(tester, 'toggle primary side bar');

    await rightClick(tester, find.text(_toggleSidebarTitle));
    expect(find.text('Reset Keybinding'), findsOneWidget);
    await tester.tap(find.text('Remove Keybinding'));
    await tester.pumpAndSettle();
    expect(entries(), [
      {'key': 'cmd+b', 'command': '-$_toggleSidebar'},
    ]);
    // Now without a key, the user's.
    expect(find.text('⌘B'), findsNothing);
    expect(find.text('User'), findsOneWidget);

    await rightClick(tester, find.text(_toggleSidebarTitle));
    await tester.tap(find.text('Reset Keybinding'));
    await tester.pumpAndSettle();
    expect(entries(), isEmpty);
    expect(find.text('⌘B'), findsOneWidget);

    await rightClick(tester, find.text(_toggleSidebarTitle));
    await tester.tap(find.text('Change When Expression'));
    await tester.pumpAndSettle();
    final input = find.byWidgetPredicate(
      (widget) =>
          widget is IdeInputBox && widget.semanticsLabel == 'When expression',
    );
    expect(input, findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'ideMode');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(input, findsNothing);
    expect(entries(), [
      {'key': 'cmd+b', 'command': _toggleSidebar, 'when': 'ideMode'},
      {'key': 'cmd+b', 'command': '-$_toggleSidebar'},
    ]);
    expect(find.text('ideMode'), findsOneWidget);

    // Show Same Keybindings: the key as the search.
    await rightClick(tester, find.text(_toggleSidebarTitle));
    await tester.tap(find.text('Show Same Keybindings'));
    await tester.pumpAndSettle();
    expect(find.text('"cmd+b"'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('shows why a change failed', (tester) async {
    await open(tester, text: '{"not": "an array"}');
    await search(tester, 'toggle primary side bar');
    await rightClick(tester, find.text(_toggleSidebarTitle));
    await tester.tap(find.text('Remove Keybinding'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not of type Array'), findsOneWidget);
    expect(file.text, '{"not": "an array"}');
    await tester.pump(const Duration(seconds: 2));
  });
}
