// 九.2: ESLint and Prettier from Open VSX in a real extension host. ESLint
// lints with the project's own eslint (installed once with npm into
// BAOCODE_NPM_ESLINT, else /tmp/exthost-dl/npm-eslint) and fixes on save
// (`editor.codeActionsOnSave`); Prettier, the default formatter, formats
// on save (`editor.formatOnSave`), after the fixes.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'open_vsx_workspace.dart';

final _npm =
    Platform.environment['BAOCODE_NPM_ESLINT'] ?? '/tmp/exthost-dl/npm-eslint';

/// eslint and @eslint/js in [_npm], installed when missing.
Future<String?> _eslintModules() async {
  final modules = p.join(_npm, 'node_modules');
  if (File(p.join(modules, 'eslint', 'package.json')).existsSync() &&
      File(p.join(modules, '@eslint', 'js', 'package.json')).existsSync()) {
    return modules;
  }
  Directory(_npm).createSync(recursive: true);
  final manifest = File(p.join(_npm, 'package.json'));
  if (!manifest.existsSync()) {
    manifest.writeAsStringSync('{"name": "eslint-cache", "private": true}');
  }
  final install = await Process.run('npm', [
    'install',
    '--no-audit',
    '--no-fund',
    'eslint@9',
    '@eslint/js@9',
  ], workingDirectory: _npm);
  return install.exitCode == 0 ? modules : null;
}

Object _skip() {
  final skip = openVsxSkip();
  if (skip != false) return skip;
  return Process.runSync('which', ['npm']).exitCode == 0
      ? false
      : 'npm is not on the PATH';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '九.2: ESLint diagnostics and fixes on save; Prettier formats on save',
    () async {
      final modules = await _eslintModules();
      expect(modules, isNotNull, reason: 'npm install eslint failed');
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [
          'dbaeumer.vscode-eslint',
          'esbenp.prettier-vscode',
        ],
        settings: {
          'editor.formatOnSave': true,
          'editor.defaultFormatter': 'esbenp.prettier-vscode',
          'editor.codeActionsOnSave': {'source.fixAll.eslint': 'explicit'},
        },
        files: {
          'package.json': '{"name": "accept", "private": true}\n',
          'eslint.config.mjs': [
            'import js from "@eslint/js";',
            'export default [',
            '  js.configs.recommended,',
            '  {',
            '    languageOptions: { globals: { console: "readonly" } },',
            '    rules: { "prefer-const": "error" },',
            '  },',
            '];',
            '',
          ].join('\n'),
          'app.js': "let unused = 1\nconsole.log( 'x' )\n",
        },
        prepare: (project) =>
            Link(p.join(project, 'node_modules')).createSync(modules!),
      );
      final file = await w.open('app.js');
      await w.activated('dbaeumer.vscode-eslint');
      final languages = w.extensions.languageRoot.language;

      // ESLint's diagnostics, from the project's eslint.
      final diagnostics = await eventually('ESLint diagnostics', () {
        final found = [
          for (final d in languages.diagnosticsFor(file))
            if (d.source == 'eslint') d,
        ];
        return found.length >= 2 ? found : null;
      }, timeout: const Duration(minutes: 3));
      expect(
        diagnostics.map((d) => d.code?.toString()),
        containsAll(['no-unused-vars', 'prefer-const']),
      );
      expect(
        diagnostics.map((d) => d.message),
        contains(contains("'unused' is assigned a value but never used")),
      );

      // Prettier is the default formatter: Format Document is its.
      final edits = await eventually('Prettier edits', () async {
        final found = await languages.format(
          file,
          tabSize: 2,
          insertSpaces: true,
        );
        return found.isEmpty ? null : found;
      }, timeout: const Duration(minutes: 2));
      expect(edits, isNotEmpty);

      // Save: ESLint's fix-all (let → const), then Prettier.
      final doc = w.workspace.documents.singleWhere((d) => d.path == file);
      await w.workspace.save(doc);
      expect(
        File(file).readAsStringSync(),
        'const unused = 1;\nconsole.log("x");\n',
        reason: w.report(),
      );

      // No default formatter, two formatters (TypeScript's and Prettier's):
      // a format on save says so, offering to configure one, and formats
      // nothing.
      await w.app.userSettings.write(['editor.defaultFormatter'], null);
      doc.model.applyOffsetEdits([
        EditorOffsetEdit(doc.text.length, doc.text.length, "let b = 'y'\n"),
      ]);
      w.workspace.notifyDocumentChanged(doc);
      await w.workspace.save(doc);
      final notice = w.workspace.notifications.notifications.singleWhere(
        (n) => n.message.contains("multiple formatters for 'javascript'"),
      );
      expect(notice.primary.map((a) => a.label), ['Configure...']);
      expect(
        File(file).readAsStringSync(),
        "const unused = 1;\nconsole.log(\"x\");\nconst b = 'y'\n",
      );
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: _skip(),
  );
}
