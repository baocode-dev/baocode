import 'dart:convert';
import 'dart:io';

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
          '/project/文档',
        ], shell: shell),
        '/project/a.txt /project/My\\ Docs '
        r"/project/it\'s\ \(new\)\;\$x\`id\`\[1\].txt "
        r'/project/a\\b /project/文档 ',
      );
    }
  });

  test('keeps CJK literal and uses printable shell escapes for emoji', () {
    expect(
      terminalFileDropText([
        '/项目/中文目录/说明.txt',
        '/项目/中文 空格/你好.txt',
        "/项目/中文'引号.txt",
        '/项目/👩‍💻开发/说明📁.txt',
        '/项目/café.txt',
      ], shell: '/bin/zsh'),
      '/项目/中文目录/说明.txt /项目/中文\\ 空格/你好.txt '
      "/项目/中文\\'引号.txt "
      r"$'/项目/\U0001f469"
      r'\u'
      '200d'
      r"\U0001f4bb开发/说明\U0001f4c1.txt' "
      '/项目/café.txt ',
    );
  });

  for (final shell in ['/bin/zsh', '/bin/bash', '/bin/sh']) {
    test('real $shell reads the original Unicode paths as arguments', () async {
      const paths = [
        '/项目/中文目录/说明.txt',
        '/项目/中文 空格/你好.txt',
        "/项目/中文'引号.txt",
        '/项目/👩‍💻开发/说明📁.txt',
        '/项目/café.txt',
        r'/项目/$(printf unexpected);`printf unexpected`[1]*?.txt',
        r'/项目/反斜杠\文件.txt',
        '/项目/全角　空格.txt',
      ];
      final text = terminalFileDropText(paths, shell: shell)!;
      final result = await Process.run(
        shell,
        ['-f', '-c', "printf '%s\\0' $text"],
        stdoutEncoding: null,
        stderrEncoding: utf8,
        environment: {'LC_ALL': 'en_US.UTF-8'},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        utf8.decode(result.stdout as List<int>),
        '${paths.join('\x00')}\x00',
      );
    }, skip: !File(shell).existsSync());
  }

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
