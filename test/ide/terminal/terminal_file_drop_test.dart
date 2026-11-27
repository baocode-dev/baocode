import 'package:baocode/ide/terminal/terminal_file_drop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quotes file and folder paths as separate shell arguments', () {
    for (final shell in ['/bin/zsh', '/bin/bash', '/bin/sh', '/usr/bin/fish']) {
      expect(
        terminalFileDropText([
          '/project/a.txt',
          '/project/My Docs',
          "/project/it's (new);\$x`id`[1].txt",
          r'/project/a\b',
          '/project/文档📁',
        ], shell: shell),
        '/project/a.txt /project/My\\ Docs '
        r"/project/it\'s\ \(new\)\;\$x\`id\`\[1\].txt "
        r'/project/a\\b /project/\文\档\📁 ',
      );
    }
  });

  test('uses PowerShell literal strings and cmd double quotes', () {
    for (final shell in [
      r'C:\Program Files\PowerShell\7\pwsh.exe',
      'powershell',
    ]) {
      expect(
        terminalFileDropText([r"C:\My Docs\it's $new.txt"], shell: shell),
        r"'C:\My Docs\it''s $new.txt' ",
      );
    }
    expect(
      terminalFileDropText([
        r'C:\My Docs\a.txt',
      ], shell: r'C:\Windows\System32\cmd.exe'),
      '"C:\\My Docs\\a.txt" ',
    );
  });

  test('does not send empty paths or terminal control characters', () {
    for (final paths in [
      <String>[],
      [''],
      ['/safe', '/a\nb'],
      ['/a\rb'],
      ['/a\x1b[201~b'],
      ['/a\x00b'],
      ['/a\x7fb'],
    ]) {
      expect(terminalFileDropText(paths, shell: '/bin/zsh'), isNull);
    }
  });
}
