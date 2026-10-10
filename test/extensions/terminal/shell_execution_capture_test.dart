// A command's output for `TerminalShellExecution.read()`: between the
// shell integration's executed and finished sequences, however the
// process's data is cut.

import 'package:baocode/extensions/main_thread/main_thread_terminal_shell_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const data =
      '\x1b]633;A\x07\$ \x1b]633;B\x07ls\r\n\x1b]633;E;ls;n\x07'
      '\x1b]633;C\x07a \x1b[31mred\x1b[0m\r\nb\r\n\x1b]633;D;0\x07'
      '\x1b]633;A\x07\$ ';

  test('the output, sequences inside it kept, nothing around it', () {
    final capture = ShellExecutionCapture()..add(data);
    expect(capture.take(), 'a \x1b[31mred\x1b[0m\r\nb\r\n');
    expect(capture.capturing, isFalse);
  });

  test('the same, the data cut anywhere', () {
    for (var cut = 1; cut < data.length; cut++) {
      final capture = ShellExecutionCapture()
        ..add(data.substring(0, cut))
        ..add(data.substring(cut));
      expect(capture.take(), 'a \x1b[31mred\x1b[0m\r\nb\r\n', reason: '$cut');
    }
  });

  test('FinalTerm\'s sequences, ended by ST, read as they come', () {
    final capture = ShellExecutionCapture()..add('\x1b]133;C\x1b\\out');
    expect(capture.capturing, isTrue);
    expect(capture.take(), 'out');
    capture.add('put\x1b]133;D;1\x1b\\\$ ');
    expect(capture.take(), 'put');
    expect(capture.capturing, isFalse);
  });
}
