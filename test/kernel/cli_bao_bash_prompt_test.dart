import 'package:bao_agent/bao_agent.dart' show Shell;
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/process_transport_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Claude Code's CLI given BaoCode Bash is told what it has, as the
/// built-in core's Bash tool is.
void main() {
  String appended(ClaudeLaunch launch) {
    final arguments = launch.arguments;
    return arguments[arguments.indexOf('--append-system-prompt') + 1];
  }

  test('told of it ahead of its own instructions', () {
    const launch = ClaudeLaunch(cwd: '/w', instructions: 'Be brief.');
    final told = ProcessTransport.toldOfBash(launch, baoBash: true);
    final prompt = appended(told);
    expect(prompt, contains(Shell.baoBashNote));
    expect(prompt, endsWith('${Shell.baoBashNote}\n\nBe brief.'));
    expect(
      appended(
        ProcessTransport.toldOfBash(
          const ClaudeLaunch(cwd: '/w'),
          baoBash: true,
        ),
      ),
      endsWith(Shell.baoBashNote),
    );
  });

  test('nothing said without it, nor in a prompt of its own', () {
    const launch = ClaudeLaunch(cwd: '/w', instructions: 'Be brief.');
    expect(ProcessTransport.toldOfBash(launch, baoBash: false), same(launch));
    const own = ClaudeLaunch(
      cwd: '/w',
      instructions: 'Title it.',
      ownPrompt: true,
    );
    expect(ProcessTransport.toldOfBash(own, baoBash: true), same(own));
  });
}
