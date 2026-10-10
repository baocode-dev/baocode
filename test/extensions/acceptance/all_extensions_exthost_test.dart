// 九.2: every Open VSX extension of the acceptance installed together in a
// fresh data folder, as a user would have them: each activates on its
// project's files without an error, and none asks for what is not
// supported. (Each one's features are checked by its own test.)
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'package:flutter_test/flutter_test.dart';

import 'open_vsx_workspace.dart';

const _installed = [
  'ms-python.python',
  'detachhead.basedpyright',
  'rust-lang.rust-analyzer',
  'golang.go',
  'llvm-vs-code-extensions.vscode-clangd',
  'dbaeumer.vscode-eslint',
  'esbenp.prettier-vscode',
  'eamodio.gitlens',
  'usernamehw.errorlens',
  'Gruntfuggly.todo-tree',
  'streetsidesoftware.code-spell-checker',
  'vscodevim.vim',
  'ms-azuretools.vscode-docker',
  'dracula-theme.theme-dracula',
  'vscode-icons-team.vscode-icons',
];

/// Those with code, activated by the files below or at startup (Docker's
/// is its dependency, Container Tools).
const _activated = [
  'ms-python.python',
  'detachhead.basedpyright',
  'rust-lang.rust-analyzer',
  'golang.go',
  'llvm-vs-code-extensions.vscode-clangd',
  'dbaeumer.vscode-eslint',
  'esbenp.prettier-vscode',
  'eamodio.gitlens',
  'usernamehw.errorlens',
  'Gruntfuggly.todo-tree',
  'streetsidesoftware.code-spell-checker',
  'vscodevim.vim',
  'ms-azuretools.vscode-containers',
  'vscode-icons-team.vscode-icons',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '九.2: all the Open VSX extensions installed together',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: _installed,
        files: {
          'a.py': 'import os\nprint(os.getcwd())\n',
          'main.go': 'package main\n\nfunc main() {}\n',
          'go.mod': 'module x\n\ngo 1.22\n',
          'src/main.rs': 'fn main() {}\n',
          'Cargo.toml': '[package]\nname = "x"\nversion = "0.1.0"\n',
          'a.cpp': 'int main() { return 0; }\n',
          'a.js': '// TODO: x\nconst a = 1\n',
          'Dockerfile': 'FROM alpine\n',
        },
        // Their first-run pages and prompts, which wait on the user.
        settings: {'gitlens.advanced.skipOnboarding': true},
      );
      for (final file in [
        'a.py',
        'main.go',
        'src/main.rs',
        'a.cpp',
        'a.js',
        'Dockerfile',
      ]) {
        await w.open(file);
      }
      // vscode-icons' activation waits on its welcome's answer.
      await w.answer('vscode-icons', 'Activate');
      for (final id in _activated) {
        await w.activated(id, timeout: const Duration(minutes: 3));
      }
      expect(w.extensions.running.withErrors, isEmpty, reason: w.report());
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: openVsxSkip(),
  );
}
