import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/keybindings/import_dialog.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/vscode_import.dart';

const _code = KeybindingsSource(
  product: VsCodeProduct.code,
  path: '/home/Library/Application Support/Code/User/keybindings.json',
  entryCount: 5,
);
const _work = KeybindingsSource(
  product: VsCodeProduct.code,
  profile: 'Work',
  path:
      '/home/Library/Application Support/Code/User/profiles/1/keybindings.json',
  entryCount: 2,
);
const _cursor = KeybindingsSource(
  product: VsCodeProduct.cursor,
  path: '/home/Library/Application Support/Cursor/User/keybindings.json',
  entryCount: 3,
);
const _atom = KeymapExtension(
  id: 'ms-vscode.atom-keybindings',
  name: 'Atom Keymap',
  version: '3.3.0',
  path: '/home/.vscode/extensions/ms-vscode.atom-keybindings-3.3.0',
  keybindings: [],
  products: [VsCodeProduct.code, VsCodeProduct.cursor],
);

void main() {
  late List<(KeybindingsSource, KeybindingsImportMode)> imported;
  late List<KeymapExtension> keymapsImported;
  late List<String> selected;

  setUp(() {
    imported = [];
    keymapsImported = [];
    selected = [];
  });

  Future<void> open(
    WidgetTester tester, {
    KeybindingsDetection detection = const KeybindingsDetection(
      sources: [_code, _work, _cursor],
      keymaps: [_atom],
    ),
    Object? failKeybindings,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showKeybindingsImportDialog(
                context,
                detection: detection,
                importKeybindings: (source, mode) async {
                  if (failKeybindings != null) throw failKeybindings;
                  imported.add((source, mode));
                  return const KeybindingsImportReport(
                    total: 3,
                    duplicates: 1,
                    unsupported: [
                      KeybindingEntry(
                        command: 'workbench.action.toggleAgentsFromKeyboard',
                        key: 'cmd+3',
                        when: '!isAuxiliaryWindowFocusedContext',
                      ),
                    ],
                  );
                },
                importKeymap: (extension) async {
                  keymapsImported.add(extension);
                  return const KeymapImportResult(
                    id: 'ms-vscode.atom-keybindings',
                    name: 'Atom',
                    builtIn: true,
                  );
                },
                selectKeymap: selected.add,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
  }

  testWidgets('pick a source, how, and the keymap; then the report', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Import Keybindings'), findsOneWidget);
    expect(_choice('Visual Studio Code'), findsOneWidget);
    expect(_choice('Visual Studio Code (Work)'), findsOneWidget);
    expect(find.textContaining('2 keybindings'), findsOneWidget);
    expect(find.text(_cursor.path), findsOneWidget);
    expect(
      find.textContaining('Also import and use Atom Keymap'),
      findsOneWidget,
    );
    expect(
      find.text('Installed in Visual Studio Code, Cursor'),
      findsOneWidget,
    );

    // The first is picked, merging, with the keymap.
    expect(_checked(tester, 'Visual Studio Code'), isTrue);
    expect(_checked(tester, 'Merge with my keybindings'), isTrue);
    expect(_checked(tester, 'Also import and use Atom Keymap'), isTrue);

    await tester.tap(_choice('Cursor'));
    await tester.tap(_choice('Replace my keybindings'));
    await tester.pump();
    expect(_checked(tester, 'Visual Studio Code'), isFalse);
    expect(_checked(tester, 'Cursor'), isTrue);
    expect(_checked(tester, 'Replace my keybindings'), isTrue);
    expect(_checked(tester, 'Merge with my keybindings'), isFalse);

    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(imported, [(_cursor, KeybindingsImportMode.replace)]);
    expect(keymapsImported, [_atom]);
    expect(selected, ['ms-vscode.atom-keybindings']);

    expect(find.text('Imported from Cursor'), findsOneWidget);
    expect(find.text('2 applied, 1 command not supported yet'), findsOneWidget);
    expect(
      find.text('workbench.action.toggleAgentsFromKeyboard'),
      findsOneWidget,
    );
    expect(
      find.text('1 keybinding you already had was skipped.'),
      findsOneWidget,
    );
    expect(
      find.text('Keymap: Atom is built in, and now in use.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Import Keybindings'), findsNothing);
  });

  testWidgets('without the keymap; an error is shown', (tester) async {
    await open(
      tester,
      failKeybindings: const KeybindingsImportException('Broken'),
    );
    await tester.tap(_choice('Also import and use Atom Keymap'));
    await tester.pump();
    expect(_checked(tester, 'Also import and use Atom Keymap'), isFalse);

    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(keymapsImported, isEmpty);
    expect(selected, isEmpty);
    expect(
      find.text('Could not import the keybindings: Broken'),
      findsOneWidget,
    );
  });

  testWidgets('nothing found: nothing to import', (tester) async {
    await open(tester, detection: const KeybindingsDetection());
    expect(find.textContaining('No keybindings or keymaps'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(imported, isEmpty);
    expect(find.text('Import Keybindings'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Import Keybindings'), findsNothing);
  });
}

/// The checkbox or radio button labelled [label].
Finder _choice(String label) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$'));

/// Whether the choice labelled [label] is checked, as its semantics say.
bool _checked(WidgetTester tester, String label) =>
    isSemantics(isChecked: true)
        .matches(tester.getSemantics(_choice(label)), {});
