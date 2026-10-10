// Which highlighter a file gets, and how language ids cross between the
// highlighters and language servers: language packs keep their Monarch
// grammars, VS Code ids that Monarch knows by another name are mapped, and
// language servers keep their own ids whatever highlights the file.

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_editor/textmate/textmate_worker.dart';
import 'package:baocode/ide/lsp/catalog/bundled_lsp_catalog.dart';
import 'package:baocode/ide/lsp/packs/language_packs.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:path/path.dart' as p;

final _packsDirectory = p.absolute('test/fixtures/lsp/packs');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextMateSyntax syntax({MonacoLanguageAssets? monarch}) {
    final syntax = TextMateSyntax(
      themes: WorkbenchThemeService.instance,
      monarch: monarch,
      launch: () async => TextMateInProcessWorker.create(),
    );
    addTearDown(syntax.dispose);
    return syntax;
  }

  test('a language pack keeps the files it claims', () async {
    final packs = syntax(
      monarch: MonacoLanguageAssets(
        packs: LanguagePackRegistry(_packsDirectory),
      ),
    );
    // The ini-override pack claims `.ini`, which VS Code's ini grammar
    // would highlight; the Toy pack claims a language VS Code lacks.
    expect(await packs.languageIdForPath('/w/settings.ini'), isNull);
    expect(await packs.languageIdForPath('/w/hello.toy'), isNull);
    expect(await packs.languageIdForPath('/w/Toyfile'), isNull);
    expect(await packs.languageIdForPath('/w/a.ts'), 'typescript');
    // Without the packs, VS Code's grammar takes `.ini`.
    expect(await syntax().languageIdForPath('/w/settings.ini'), 'ini');
  });

  test('VS Code ids Monarch names otherwise are mapped', () async {
    const monarch = MonacoLanguageAssets();
    final vscode = syntax();
    for (final (path, vscodeId, monarchId) in const [
      ('run.sh', 'shellscript', 'shell'),
      ('App.jsx', 'javascriptreact', 'javascript'),
      ('App.tsx', 'typescriptreact', 'typescript'),
      ('app.properties', 'properties', 'ini'),
      ('kernel.cu', 'cuda-cpp', 'cpp'),
      ('index.jade', 'jade', 'pug'),
      ('main.dart', 'dart', 'dart'),
      ('main.rs', 'rust', 'rust'),
    ]) {
      expect(await vscode.languageIdForPath('/w/$path'), vscodeId);
      expect(monarchLanguageIdFor(vscodeId), monarchId, reason: vscodeId);
      expect(
        await monarch.languageIdForName(monarchLanguageIdFor(vscodeId)),
        monarchId,
        reason: vscodeId,
      );
    }
    expect(monarchLanguageIdFor('no-such-language'), 'no-such-language');
  });

  test('language servers keep their own ids', () async {
    final catalog = BundledLspCatalog();
    await catalog.load();
    final vscode = syntax();
    // Highlighting uses VS Code's ids; the catalog's are what servers get.
    for (final (path, highlight, server) in const [
      ('run.sh', 'shellscript', 'bash'),
      ('App.tsx', 'typescriptreact', 'typescriptreact'),
      ('main.py', 'python', 'python'),
      ('main.rs', 'rust', 'rust'),
    ]) {
      expect(await vscode.languageIdForPath('/w/$path'), highlight);
      final language = catalog.languageFor(path)!;
      expect(language.languageId ?? language.id, server, reason: path);
    }
  });
}
