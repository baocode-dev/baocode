import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/keybindings/keybindings_editing.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:path/path.dart' as p;

const _toggleSidebar = 'workbench.action.toggleSidebarVisibility';
const _explorer = 'workbench.view.explorer';
const _chat = 'workbench.action.toggleAuxiliaryBar';
const _focusNext = 'workbench.action.terminal.focusNext';

/// The user's file: comments above, between and after entries.
const _userFile = '''
// My keybindings
[
    // Explorer
    {
        "key": "cmd+1",
        "command": "workbench.view.explorer" // trailing
    },
    /* the chat */
    {
        "key": "cmd+3",
        "command": "workbench.action.toggleAuxiliaryBar",
        "when": "editorTextFocus"
    }
    // the end
]
''';

void main() {
  late Directory temp;
  late String path;
  late JsoncFile file;
  late KeybindingService service;
  late KeybindingsEditingService editing;

  Future<void> start([String? text = _userFile]) async {
    if (text != null) await File(path).writeAsString(text);
    await file.load();
  }

  String text() => File(path).readAsStringSync();
  List<Object?> entries() => parseJsonc(text())! as List<Object?>;

  KeybindingItem defaultItem(String command) => service
      .resolver()
      .lookupKeybindings(command)
      .firstWhere((item) => item.isDefault);
  KeybindingItem userItem(String command) => service
      .resolver()
      .lookupKeybindings(command)
      .firstWhere((item) => !item.isDefault);
  KeySequence keys(String text) => KeySequence.parse(text)!;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode-keybindings-editing');
    path = p.join(temp.path, 'User', 'keybindings.json');
    Directory(p.dirname(path)).createSync(recursive: true);
    file = JsoncFile(path);
    service = KeybindingService()..debugPlatform = KeybindingPlatform.mac;
    // As the app keeps them: the file's entries are the user's.
    file.addListener(
      () => service.userEntries = KeybindingEntry.listFromJson(file.value),
    );
    editing = KeybindingsEditingService(file, platform: KeybindingPlatform.mac);
  });

  tearDown(() {
    file.dispose();
    temp.deleteSync(recursive: true);
  });

  void expectCommentsKept() {
    final now = text();
    for (final comment in [
      '// My keybindings',
      '// Explorer',
      '// trailing',
      '/* the chat */',
      '// the end',
    ]) {
      expect(now, contains(comment));
    }
  }

  group('editKeybinding', () {
    test('overrides a default one and removes its key', () async {
      await start();
      await editing.editKeybinding(
        defaultItem(_toggleSidebar),
        keys('ctrl+shift+b'),
      );
      expect(entries().skip(2), [
        {'key': 'ctrl+shift+b', 'command': _toggleSidebar},
        {'key': 'cmd+b', 'command': '-$_toggleSidebar'},
      ]);
      expectCommentsKept();
      final items = service.resolver().lookupKeybindings(_toggleSidebar);
      expect(items, hasLength(1));
      expect(items.single.isDefault, isFalse);
      expect(items.single.keys, keys('ctrl+shift+b'));
    });

    test('keeps the when of a default one, and removes it with it', () async {
      await start();
      await editing.editKeybinding(defaultItem(_focusNext), keys('cmd+down'));
      expect(entries().skip(2), [
        {'key': 'cmd+down', 'command': _focusNext, 'when': 'terminalFocus'},
        {
          'key': 'shift+cmd+]',
          'command': '-$_focusNext',
          'when': 'terminalFocus',
        },
      ]);
    });

    test('adds no second removal of the same key', () async {
      await start('''
[
  {"key": "cmd+b", "command": "-$_toggleSidebar"}
]''');
      // Still shown, e.g. from before the file changed.
      final item = KeybindingItem(
        entry: service.defaults.firstWhere((e) => e.command == _toggleSidebar),
        source: KeybindingSource.defaults,
        platform: KeybindingPlatform.mac,
      );
      await editing.editKeybinding(item, keys('ctrl+shift+b'));
      expect(entries(), [
        {'key': 'cmd+b', 'command': '-$_toggleSidebar'},
        {'key': 'ctrl+shift+b', 'command': _toggleSidebar},
      ]);
    });

    test('changes a user one in place', () async {
      await start();
      await editing.editKeybinding(userItem(_explorer), keys('cmd+2'));
      expect(entries(), [
        {'key': 'cmd+2', 'command': _explorer},
        {'key': 'cmd+3', 'command': _chat, 'when': 'editorTextFocus'},
      ]);
      expectCommentsKept();
      expect(text(), contains('"key": "cmd+2",\n        "command"'));
    });

    test('sets a user one\'s when as well, when given', () async {
      await start();
      await editing.editKeybinding(
        userItem(_explorer),
        keys('cmd+2'),
        when: 'ideMode',
      );
      expect(entries().first, {
        'key': 'cmd+2',
        'command': _explorer,
        'when': 'ideMode',
      });
      expectCommentsKept();
    });

    test('changes the key a user one has for this platform', () async {
      await start('''
[
  {"key": "ctrl+1", "mac": "cmd+1", "command": "$_explorer"}
]''');
      await editing.editKeybinding(userItem(_explorer), keys('cmd+2'));
      expect(entries(), [
        {'key': 'ctrl+1', 'mac': 'cmd+2', 'command': _explorer},
      ]);
    });

    test('finds a user one past what is not an entry', () async {
      await start('''
[
  {"key": "cmd+9"},
  {"key": "cmd+1", "command": "$_explorer"}
]''');
      final item = userItem(_explorer);
      expect(item.index, 0);
      await editing.editKeybinding(item, keys('cmd+2'));
      expect(entries(), [
        {'key': 'cmd+9'},
        {'key': 'cmd+2', 'command': _explorer},
      ]);
    });

    test('writes nothing when nothing changes', () async {
      await start();
      final before = File(path).lastModifiedSync();
      await editing.editKeybinding(userItem(_explorer), keys('cmd+1'));
      await editing.editKeybinding(defaultItem(_toggleSidebar), keys('cmd+b'));
      expect(text(), _userFile);
      expect(File(path).lastModifiedSync(), before);
    });
  });

  group('changeWhen', () {
    test('changes a user one in place, or removes it', () async {
      await start();
      await editing.changeWhen(userItem(_chat), 'ideMode && editorFocus');
      expect(entries()[1], {
        'key': 'cmd+3',
        'command': _chat,
        'when': 'ideMode && editorFocus',
      });
      await editing.changeWhen(userItem(_chat), '  ');
      expect(entries()[1], {'key': 'cmd+3', 'command': _chat});
      expectCommentsKept();
    });

    test('overrides a default one', () async {
      await start();
      await editing.changeWhen(defaultItem(_toggleSidebar), 'ideMode');
      expect(entries().skip(2), [
        {'key': 'cmd+b', 'command': _toggleSidebar, 'when': 'ideMode'},
        {'key': 'cmd+b', 'command': '-$_toggleSidebar'},
      ]);
    });
  });

  group('removeKeybinding', () {
    test('deletes a user one', () async {
      await start();
      await editing.removeKeybinding(userItem(_chat));
      expect(entries(), [
        {'key': 'cmd+1', 'command': _explorer},
      ]);
      final now = text();
      expect(now, contains('// My keybindings'));
      expect(now, contains('// trailing'));
      expect(now, contains('// the end'));
    });

    test('removes a default one by its key and when', () async {
      await start();
      await editing.removeKeybinding(defaultItem(_focusNext));
      expect(entries().last, {
        'key': 'shift+cmd+]',
        'command': '-$_focusNext',
        'when': 'terminalFocus',
      });
      expectCommentsKept();
      expect(service.resolver().lookupKeybindings(_focusNext), isEmpty);
      // Once only.
      final item = KeybindingItem(
        entry: service.defaults.firstWhere((e) => e.command == _focusNext),
        source: KeybindingSource.defaults,
        platform: KeybindingPlatform.mac,
      );
      await editing.removeKeybinding(item);
      expect(entries(), hasLength(3));
    });
  });

  test('resetKeybinding removes every user entry of the command', () async {
    await start('''
// Mine
[
  {"key": "ctrl+shift+b", "command": "$_toggleSidebar"}, // override
  {"key": "cmd+1", "command": "$_explorer"},
  {"key": "cmd+b", "command": "-$_toggleSidebar"},
  {"key": "cmd+2", "command": "$_toggleSidebar", "when": "ideMode"}
]''');
    expect(service.resolver().lookupKeybindings(_toggleSidebar), hasLength(2));
    await editing.resetKeybinding(_toggleSidebar);
    expect(entries(), [
      {'key': 'cmd+1', 'command': _explorer},
    ]);
    expect(text(), startsWith('// Mine\n'));
    final items = service.resolver().lookupKeybindings(_toggleSidebar);
    expect(items.single.isDefault, isTrue);
    expect(items.single.keys, keys('cmd+b'));
  });

  test('addKeybinding keeps the default ones', () async {
    await start();
    await editing.addKeybinding(
      _toggleSidebar,
      keys('cmd+k cmd+b'),
      when: 'ideMode',
    );
    expect(entries().last, {
      'key': 'cmd+k cmd+b',
      'command': _toggleSidebar,
      'when': 'ideMode',
    });
    expectCommentsKept();
    final items = service.resolver().lookupKeybindings(_toggleSidebar);
    expect(items.map((item) => item.isDefault), [false, true]);
  });

  group('the file', () {
    test('is made when missing, as upstream makes it', () async {
      await start(null);
      await editing.addKeybinding(_explorer, keys('cmd+1'));
      expect(
        text(),
        startsWith(
          '// Place your key bindings in this file to override the '
          'defaults\n[\n',
        ),
      );
      expect(entries(), [
        {'key': 'cmd+1', 'command': _explorer},
      ]);
    });

    test('gets an array when it has only comments', () async {
      await start('// nothing yet\n');
      await editing.addKeybinding(_explorer, keys('cmd+1'));
      expect(text(), startsWith('// nothing yet\n'));
      expect(entries(), [
        {'key': 'cmd+1', 'command': _explorer},
      ]);
    });

    test('is left alone while it does not parse', () async {
      await start();
      const broken = '[\n  {"key": "cmd+1", "command": \n';
      File(path).writeAsStringSync(broken);
      await expectLater(
        editing.addKeybinding(_explorer, keys('cmd+2')),
        throwsA(isA<JsoncFileException>()),
      );
      expect(text(), broken);
      // The next change runs once it is fixed.
      File(path).writeAsStringSync('[]');
      await editing.addKeybinding(_explorer, keys('cmd+2'));
      expect(entries(), hasLength(1));
    });

    test('is left alone when it is not an array', () async {
      await start('{"key": "cmd+1"}');
      await expectLater(
        editing.removeKeybinding(defaultItem(_toggleSidebar)),
        throwsA(isA<JsoncFileException>()),
      );
      expect(text(), '{"key": "cmd+1"}');
    });

    test('takes the changes one at a time', () async {
      await start();
      await Future.wait([
        editing.editKeybinding(userItem(_explorer), keys('cmd+2')),
        editing.removeKeybinding(defaultItem(_focusNext)),
        editing.addKeybinding(_chat, keys('cmd+4')),
      ]);
      expect(entries(), hasLength(4));
      expect(entries().first, {'key': 'cmd+2', 'command': _explorer});
      expectCommentsKept();
    });
  });
}
