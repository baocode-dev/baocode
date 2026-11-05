import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/problem_decorations.dart';

void main() {
  final posix = p.posix;

  test('file with warnings receives warning color and problem count badge', () {
    final diagnostics = {
      '/workspace/src/AuthService.java': [
        const LspDiagnostic(
          range: LspRange(
            LspPosition(24, 7),
            LspPosition(24, 21),
          ),
          message: 'The import is never used',
          severity: LspDiagnosticSeverity.warning,
        ),
        const LspDiagnostic(
          range: LspRange(
            LspPosition(26, 7),
            LspPosition(26, 21),
          ),
          message: 'The import is never used',
          severity: LspDiagnosticSeverity.warning,
        ),
        const LspDiagnostic(
          range: LspRange(
            LspPosition(61, 34),
            LspPosition(61, 48),
          ),
          message: 'The field is never used',
          severity: LspDiagnosticSeverity.warning,
        ),
      ],
    };

    final decorations = IdeProblemDecorations(diagnostics, paths: posix);

    final fileDec = decorations.file('/workspace/src/AuthService.java');
    expect(fileDec, isNotNull);
    expect(fileDec!.colorId, 'list.warningForeground');
    expect(fileDec.letter, '3');
    expect(fileDec.tooltip, '3 warnings');

    // Parent directory receives dot with warning color
    final parentDec = decorations.folder('/workspace/src');
    expect(parentDec, isNotNull);
    expect(parentDec!.colorId, 'list.warningForeground');
    expect(parentDec.letter, '•');
    expect(parentDec.tooltip, 'Contains warnings');

    // Root directory also receives dot with warning color
    final rootDec = decorations.folder('/workspace');
    expect(rootDec, isNotNull);
    expect(rootDec!.colorId, 'list.warningForeground');
    expect(rootDec.letter, '•');
  });

  test('file with errors and warnings prioritizes error color and counts all', () {
    final diagnostics = {
      '/workspace/src/ErrorService.java': [
        const LspDiagnostic(
          range: LspRange(
            LspPosition(10, 1),
            LspPosition(10, 10),
          ),
          message: 'Syntax error',
          severity: LspDiagnosticSeverity.error,
        ),
        const LspDiagnostic(
          range: LspRange(
            LspPosition(20, 1),
            LspPosition(20, 10),
          ),
          message: 'Unused variable',
          severity: LspDiagnosticSeverity.warning,
        ),
      ],
    };

    final decorations = IdeProblemDecorations(diagnostics, paths: posix);

    final fileDec = decorations.file('/workspace/src/ErrorService.java');
    expect(fileDec, isNotNull);
    expect(fileDec!.colorId, 'list.errorForeground');
    expect(fileDec.letter, '2');
    expect(fileDec.tooltip, '1 error, 1 warning');

    // Folder upgrades to error
    final folderDec = decorations.folder('/workspace/src');
    expect(folderDec, isNotNull);
    expect(folderDec!.colorId, 'list.errorForeground');
    expect(folderDec.tooltip, 'Contains errors');
  });

  test('hints are ignored and not counted as problems', () {
    final diagnostics = {
      '/workspace/src/Clean.java': [
        const LspDiagnostic(
          range: LspRange(
            LspPosition(1, 1),
            LspPosition(1, 5),
          ),
          message: 'Could be private',
          severity: LspDiagnosticSeverity.hint,
        ),
      ],
    };

    final decorations = IdeProblemDecorations(diagnostics, paths: posix);
    expect(decorations.file('/workspace/src/Clean.java'), isNull);
    expect(decorations.folder('/workspace/src'), isNull);
  });

  test('merging problem decoration with line count retains problem color and joins badges', () {
    const problem = IdeGitDecoration(
      colorId: 'list.warningForeground',
      letter: '3',
      tooltip: '3 warnings',
    );
    const lineCount = IdeGitDecoration(
      colorId: null,
      letter: '5h',
      tooltip: '500 lines',
    );

    final merged = problem.merge(lineCount);
    expect(merged.colorId, 'list.warningForeground');
    expect(merged.letter, '3, 5h');
    expect(merged.tooltip, '3 warnings • 500 lines');
  });
}
