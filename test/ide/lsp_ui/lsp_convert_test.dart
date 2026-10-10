import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';

void main() {
  test('a remote host spells file URIs its own way', () {
    const uri = 'file:///Users/me/app/src/site-structure.ts';
    expect(
      lspPathOfUri(uri, paths: p.posix),
      '/Users/me/app/src/site-structure.ts',
    );
    expect(
      lspPathOfUri('file:///C:/app/main.ts', paths: p.windows),
      r'C:\app\main.ts',
    );
    expect(lspPathOfUri('untitled:Untitled-1', paths: p.posix), isNull);
  });

  test('locations keep the host spelling', () {
    const range = LspRange(LspPosition(1, 2), LspPosition(1, 5));
    final location = IdeLocation.of(
      const LspLocation('file:///Users/me/a.ts', range),
      paths: p.posix,
    );
    expect(location, const IdeLocation('/Users/me/a.ts', range));
  });
}
