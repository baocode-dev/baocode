// How language ids cross between the highlighters: VS Code ids that
// Monarch knows by another name are mapped.

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_editor/textmate/textmate_worker.dart';
import 'package:baocode/theme/workbench_theme.dart';

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
}
