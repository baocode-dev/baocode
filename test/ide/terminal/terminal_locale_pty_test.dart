@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:baocode/ide/terminal/pty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final inherited in [
    {'LANG': ''},
    {'LC_CTYPE': 'C'},
    {'LC_ALL': 'C'},
    {'LC_CTYPE': 'en_US.UTF-8'},
    {'LANG': 'zh_AU.UTF-8'},
    {'LC_CTYPE': 'zh_AU.UTF-8'},
    {'LC_ALL': 'zh_AU.UTF-8'},
  ]) {
    test('interactive zsh preserves Chinese input with $inherited', () async {
      final directory = Directory.systemTemp.createTempSync(
        'baocode-locale-pty',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final pty = await spawnPty(
        await terminalLaunch(
          directory.path,
          shell: (executable: '/bin/zsh', arguments: ['-f', '-i']),
          shellIntegration: false,
          columns: 160,
          rows: 24,
          environment: TerminalEnvironmentRequest(
            strict: true,
            env: {
              'PATH': '/usr/bin:/bin',
              'HOME': directory.path,
              'ZDOTDIR': directory.path,
              'PROMPT': 'READY> ',
              'RPROMPT': '',
              'LANG': 'en_US.UTF-8',
              ...inherited,
            },
          ),
        ),
      );
      addTearDown(() async {
        pty.kill();
        await pty.exitCode.timeout(const Duration(seconds: 5));
      });
      final printed = StringBuffer();
      final subscription = const Utf8Decoder(allowMalformed: true)
          .bind(pty.output)
          .listen(printed.write);
      addTearDown(subscription.cancel);
      Future<void> until(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $printed');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await until(() => printed.toString().contains('READY> '));
      printed.clear();
      const path = '/tmp/快捷指令/中文 空格';
      pty.writeText("\x1b[200~printf 'RESULT:%s\\n' '$path' \x1b[201~");
      await until(() => printed.toString().contains(path));
      expect(printed.toString(), isNot(contains('<008')));
      printed.clear();
      pty.writeText('\r');
      await until(() => printed.toString().contains('RESULT:$path'));
    }, skip: !File('/bin/zsh').existsSync());
  }
}
