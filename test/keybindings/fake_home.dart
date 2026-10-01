// A home like the user's, in a temporary folder: Visual Studio Code with
// its keybindings (a trailing comma), a profile of its own and the Agents
// one (which shares the default one's), Cursor with keybindings that have
// a comment, and the Atom keymap installed in both.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Code's `keybindings.json`, as the user's is.
const codeKeybindings = '''
[
  {
    "key": "cmd+e",
    "command": "workbench.action.navigateBack",
    "when": "canNavigateBack"
  },
  {
    "key": "shift+cmd+e",
    "command": "workbench.action.navigateForward",
    "when": "canNavigateForward"
  },
  {
    "key": "cmd+1",
    "command": "workbench.action.toggleSidebarVisibility"
  },
  {
    "key": "cmd+2",
    "command": "workbench.action.terminal.toggleTerminal"
  },
  {
    "key": "cmd+3",
    "command": "workbench.action.toggleAuxiliaryBar"
  },
]''';

/// Cursor's: a command the app does not have, and comments.
const cursorKeybindings = '''
// Place your key bindings in this file to override the defaults
[
    {
        "key": "cmd+e",
        "command": "workbench.action.navigateBack",
        "when": "canNavigateBack"
    },
    // Cursor's agents pane.
    {
        "key": "cmd+3",
        "command": "workbench.action.toggleAgentsFromKeyboard",
        "when": "!isAuxiliaryWindowFocusedContext"
    },
    {
        "key": "cmd+1",
        "command": "workbench.action.toggleSidebarVisibility"
    }
]
''';

/// The Work profile's.
const workKeybindings = '''
[
  { "key": "cmd+k cmd+t", "command": "workbench.action.selectTheme" },
  { "key": "cmd+k cmd+c", "command": "-editor.action.addCommentLine", "when": "editorTextFocus" }
]
''';

/// The commands the tests treat as the app's.
const supportedCommands = {
  'workbench.action.navigateBack',
  'workbench.action.navigateForward',
  'workbench.action.toggleSidebarVisibility',
  'workbench.action.terminal.toggleTerminal',
  'workbench.action.toggleAuxiliaryBar',
  'workbench.action.selectTheme',
  'editor.action.addCommentLine',
};

/// The Atom keymap's manifest (a few of its keybindings), [version].
Map<String, Object?> atomManifest(String version) => {
  'name': 'atom-keybindings',
  'displayName': 'Atom Keymap',
  'version': version,
  'publisher': 'ms-vscode',
  'license': 'MIT',
  'categories': ['Keymaps'],
  'contributes': {
    'keybindings': [
      {
        'mac': 'cmd+1',
        'win': 'ctrl+1',
        'linux': 'ctrl+1',
        'key': 'ctrl+1',
        'when': 'filesExplorerFocus && !inputFocus',
        'command': 'explorer.openToSide',
      },
      {
        'mac': 'cmd+\\',
        'win': 'ctrl+\\',
        'linux': 'ctrl+\\',
        'key': 'ctrl+\\',
        'command': 'workbench.action.toggleSidebarVisibility',
      },
    ],
    'configurationDefaults': {'editor.multiCursorModifier': 'ctrlCmd'},
  },
};

/// Builds the home in a new temporary folder; the caller deletes it.
Future<Directory> createFakeHome() async {
  final home = await Directory.systemTemp.createTemp('monad_keybindings_');
  final support = p.join(home.path, 'Library', 'Application Support');

  Future<void> write(String path, String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<void> writeJson(String path, Object json) =>
      write(path, const JsonEncoder.withIndent('  ').convert(json));

  // Visual Studio Code.
  final code = p.join(support, 'Code', 'User');
  await write(p.join(code, 'keybindings.json'), codeKeybindings);
  await write(p.join(code, 'settings.json'), '{}');
  await writeJson(p.join(code, 'globalStorage', 'storage.json'), {
    'telemetry.machineId': 'x',
    'userDataProfiles': [
      {
        'location': 'builtin/agents',
        'name': 'Agents',
        'useDefaultFlags': {'settings': true, 'keybindings': true},
      },
      {'location': '-5f3e2a1', 'name': 'Work', 'icon': 'briefcase'},
      // Without keybindings of its own.
      {'location': '7c1d0b2', 'name': 'Empty'},
      // Invalid: no name.
      {'location': '9a9a9a9'},
    ],
  });
  await Directory(
    p.join(code, 'profiles', 'builtin', 'agents', 'globalStorage'),
  ).create(recursive: true);
  await write(
    p.join(code, 'profiles', '-5f3e2a1', 'keybindings.json'),
    workKeybindings,
  );
  await write(p.join(code, 'profiles', '7c1d0b2', 'settings.json'), '{}');
  await write(p.join(code, 'profiles', '9a9a9a9', 'keybindings.json'), '[]');

  // Cursor: no profiles.
  final cursor = p.join(support, 'Cursor', 'User');
  await write(p.join(cursor, 'keybindings.json'), cursorKeybindings);
  await writeJson(p.join(cursor, 'globalStorage', 'storage.json'), {
    'theme': 'vs-dark',
  });

  // Code - Insiders was run, but no keybindings were set.
  await write(
    p.join(support, 'Code - Insiders', 'User', 'settings.json'),
    '{}',
  );

  // Extensions: the Atom keymap in both, an update of it Code has not
  // cleaned up (and an older one it has), another extension, and a keymap
  // only Cursor has.
  final codeExtensions = p.join(home.path, '.vscode', 'extensions');
  await writeJson(
    p.join(codeExtensions, 'ms-vscode.atom-keybindings-3.3.0', 'package.json'),
    atomManifest('3.3.0'),
  );
  await writeJson(
    p.join(codeExtensions, 'ms-vscode.atom-keybindings-3.2.0', 'package.json'),
    atomManifest('3.2.0'),
  );
  await writeJson(
    p.join(codeExtensions, 'ms-vscode.atom-keybindings-3.4.0', 'package.json'),
    atomManifest('3.4.0'),
  );
  await writeJson(p.join(codeExtensions, '.obsolete'), {
    'ms-vscode.atom-keybindings-3.4.0': true,
  });
  await writeJson(p.join(codeExtensions, 'golang.go-0.56.1', 'package.json'), {
    'name': 'go',
    'publisher': 'golang',
    'version': '0.56.1',
    'categories': ['Programming Languages', 'Debuggers'],
    'contributes': {
      'keybindings': [
        {'key': 'ctrl+shift+g', 'command': 'go.test.cursor'},
      ],
    },
  });
  await write(p.join(codeExtensions, 'extensions.json'), '[]');

  final cursorExtensions = p.join(home.path, '.cursor', 'extensions');
  await writeJson(
    p.join(
      cursorExtensions,
      'ms-vscode.atom-keybindings-3.3.0-universal',
      'package.json',
    ),
    atomManifest('3.3.0'),
  );
  final emacs = p.join(cursorExtensions, 'acme.emacs-keymap-1.2.0-universal');
  await writeJson(p.join(emacs, 'package.json'), {
    'name': 'emacs-keymap',
    'displayName': '%displayName%',
    'publisher': 'Acme',
    'version': '1.2.0',
    'categories': ['Keymaps'],
    'contributes': {
      // A single keybinding, not an array.
      'keybindings': {
        'key': 'ctrl+x ctrl+s',
        'command': 'workbench.action.files.save',
        'emacs': 'save-buffer',
      },
    },
  });
  await writeJson(p.join(emacs, 'package.nls.json'), {
    'displayName': 'Emacs Keymap',
  });
  return home;
}
