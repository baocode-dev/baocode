import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/pty.dart';

import 'fake_pty.dart';

/// The fake widget tests use in place of a terminal process.
void main() {
  test('records what it is sent, and plays the process', () async {
    final started = <FakePty>[];
    final pty = await FakePty.starter(started)(
      const PtyLaunch(executable: '/bin/zsh', workingDirectory: '/p'),
    ) as FakePty;
    expect(started, [pty]);
    expect(pty.launch!.executable, '/bin/zsh');

    final printed = <int>[];
    var closed = false;
    pty.output.listen(printed.addAll, onDone: () => closed = true);

    pty
      ..writeText('ls\r')
      ..write(Uint8List.fromList([3]))
      ..resize(100, 30)
      ..kill()
      ..kill(PtySignal.kill)
      ..emitText('héllo')
      ..emit([0x0d, 0x0a]);
    expect(pty.written, 'ls\r\x03');
    expect(pty.resizes, [(columns: 100, rows: 30)]);
    expect(pty.kills, [PtySignal.hangup, PtySignal.kill]);

    pty.exit(2);
    expect(await pty.exitCode, 2);
    expect(closed, isTrue);
    expect(utf8.decode(printed), 'héllo\r\n');

    pty.writeText('late');
    expect(pty.written, 'ls\r\x03');
  });
}
