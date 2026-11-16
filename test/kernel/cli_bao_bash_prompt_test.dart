import 'package:bao_agent/bao_agent.dart' show Shell;
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/process_transport_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Claude Code's CLI given BaoCode Bash is told what it has, as the
/// built-in core's Bash tool is.
void main() {
  const bash = {'CLAUDE_CODE_GIT_BASH_PATH': r'C:\bao\bash.exe'};

  String appended(ClaudeLaunch launch) {
    final arguments = launch.arguments;
    return arguments[arguments.indexOf('--append-system-prompt') + 1];
  }

  test('told of it ahead of its own instructions', () {
    const launch = ClaudeLaunch(cwd: '/w', instructions: 'Be brief.');
    final told = ProcessTransport.toldOfBash(launch, bash);
    final prompt = appended(told);
    expect(prompt, contains(Shell.baoBashNote));
    expect(prompt, endsWith('${Shell.baoBashNote}\n\nBe brief.'));
    expect(
      appended(
        ProcessTransport.toldOfBash(const ClaudeLaunch(cwd: '/w'), bash),
      ),
      endsWith(Shell.baoBashNote),
    );
  });

  test('nothing said without it, nor in a prompt of its own', () {
    const launch = ClaudeLaunch(cwd: '/w', instructions: 'Be brief.');
    expect(ProcessTransport.toldOfBash(launch, const {}), same(launch));
    const own = ClaudeLaunch(
      cwd: '/w',
      instructions: 'Title it.',
      ownPrompt: true,
    );
    expect(ProcessTransport.toldOfBash(own, bash), same(own));
  });
}
