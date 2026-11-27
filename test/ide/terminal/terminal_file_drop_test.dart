import 'dart:convert';
import 'dart:io';

import 'package:baocode/ide/terminal/terminal_file_drop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quotes file and folder paths as separate shell arguments', () {
    for (final shell in [
      '/bin/zsh',
      '/bin/bash',
      '/bin/sh',
      '/bin/dash',
      '/usr/bin/fish',
    ]) {
      expect(
        terminalFileDropText([
          '/project/a.txt',
          '/project/My Docs',
          "/project/it's (new);\$x`id`[1]%2.txt",
          r'/project/a\b',
          '/project/文档',
        ], shell: shell),
        '/project/a.txt /project/My\\ Docs '
        r"/project/it\'s\ \(new\)\;\$x\`id\`\[1\]\%2.txt "
        r'/project/a\\b /project/文档 ',
      );
    }
  });

  test('preserves CJK, symbols and emoji literally in POSIX shells', () {
    for (final shell in ['/bin/zsh', '/bin/bash', '/bin/sh', '/usr/bin/fish']) {
      expect(
        terminalFileDropText([
          '/项目/中文目录/说明.txt',
          '/项目/中文 空格/你好.txt',
          "/项目/中文'引号.txt",
          '/项目/👩‍💻开发/说明📁.txt',
          '/项目/★笔记✓©™.txt',
          '/项目/café.txt',
        ], shell: shell),
        '/项目/中文目录/说明.txt /项目/中文\\ 空格/你好.txt '
        "/项目/中文\\'引号.txt "
        '/项目/👩‍💻开发/说明📁.txt '
        '/项目/★笔记✓©™.txt '
        '/项目/café.txt ',
      );
    }
  });

  if (!Platform.isWindows) {
    for (final shell in ['/bin/zsh', '/bin/bash', '/bin/sh', '/bin/dash']) {
      test(
        'real $shell reads the original Unicode paths as arguments',
        () async {
          const paths = [
            '/项目/中文目录/说明.txt',
            '/项目/中文 空格/你好.txt',
            "/项目/中文'引号.txt",
            '/项目/👩‍💻开发/说明📁.txt',
            '/项目/★笔记✓©™.txt',
            '/项目/café.txt',
            r'/项目/$(printf unexpected);`printf unexpected`[1]*?!%2.txt',
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
        },
        skip: !File(shell).existsSync(),
      );
    }

    test(
      'bash with history expansion enabled keeps exclamation marks literal',
      () async {
        const paths = ['/项目/hello!world.txt', '/项目/a!!b.txt'];
        final text = terminalFileDropText(paths, shell: '/bin/bash')!;
        final result = await Process.run(
          '/bin/bash',
          ['-H', '-c', "printf '%s\\0' $text"],
          stdoutEncoding: null,
          stderrEncoding: utf8,
          environment: {'LC_ALL': 'en_US.UTF-8'},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          utf8.decode(result.stdout as List<int>),
          '${paths.join('\x00')}\x00',
        );
      },
      skip: !File('/bin/bash').existsSync(),
    );
  }

  test(
    'uses PowerShell literal strings only when needed and escapes quotes',
    () {
      for (final shell in [
        r'C:\Program Files\PowerShell\7\pwsh.exe',
        'powershell',
        'powershell.exe',
      ]) {
        expect(
          terminalFileDropText([
            r'C:\project\a.txt',
            r'C:\项目\说明📁.txt',
            r"C:\My Docs\it's $new (1).txt",
            'C:\\Docs\\curly’s.txt',
          ], shell: shell),
          r'C:\project\a.txt C:\项目\说明📁.txt '
          r"'C:\My Docs\it''s $new (1).txt' "
          "'C:\\Docs\\curly’’s.txt' ",
        );
      }
    },
  );

  test(
    'uses cmd double quotes only when needed and rejects embedded quotes',
    () {
      expect(
        terminalFileDropText([
          r'C:\project\a.txt',
          r'C:\',
          r'C:\My Docs\a & b (1).txt',
        ], shell: r'C:\Windows\System32\cmd.exe'),
        'C:\\project\\a.txt C:\\ "C:\\My Docs\\a & b (1).txt" ',
      );
      expect(
        terminalFileDropText([r'C:\bad"name.txt'], shell: 'cmd.exe'),
        isNull,
      );
    },
  );

  if (Platform.isWindows) {
    test('real PowerShell reads dropped paths as literal arguments', () async {
      const paths = [
        r'C:\project\a.txt',
        r'C:\项目\说明.txt',
        r"C:\My Docs\it's $env:PATH (1) [2].txt",
        'C:\\Docs\\curly’s.txt',
      ];
      final text = terminalFileDropText(paths, shell: 'powershell.exe')!;
      final script =
          '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; '
          'function Show { param([Parameter(ValueFromRemainingArguments=\$true)]\$a) '
          '[Console]::Out.Write((\$a -join "`0")) }; '
          'Show $text';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, paths.join('\x00'));
    });

    test(
      'real cmd.exe reads dropped paths with spaces and metacharacters',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'baocode-cmd-drop',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final files = [
          '${directory.path}\\plain.txt',
          '${directory.path}\\My Docs (1) & more.txt',
          '${directory.path}\\中文 目录 (2) & 测试.txt',
        ];
        for (final path in files) {
          await File(path).writeAsString('ok');
        }
        final checker = File('${directory.path}\\check.cmd');
        await checker.writeAsString(
          '@echo off\r\n'
          ':loop\r\n'
          'if "%~1"=="" goto :eof\r\n'
          'if exist "%~1" echo FOUND:"%~1"\r\n'
          'shift\r\n'
          'goto :loop\r\n',
        );
        final text = terminalFileDropText(files, shell: 'cmd.exe')!;
        final runner = File('${directory.path}\\run.cmd');
        await runner.writeAsString(
          '@echo off\r\n'
          'chcp 65001 >nul\r\n'
          'call "${checker.path}" $text\r\n',
        );
        final result = await Process.run(
          'cmd.exe',
          ['/d', '/c', runner.path],
          stdoutEncoding: const Utf8Codec(allowMalformed: true),
          stderrEncoding: const Utf8Codec(allowMalformed: true),
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        for (final path in files) {
          expect(result.stdout, contains('FOUND:"$path"'));
        }
      },
    );
  }

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
