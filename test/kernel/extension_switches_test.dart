import 'package:baocode/kernel/extension_switches.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings → Customize's switches, as settings.json keeps them and as
/// Claude Code is given them.
void main() {
  test('all on while unset; read and written back as they are', () {
    expect(ExtensionSwitches.parse(const {}), ExtensionSwitches.none);
    expect(ExtensionSwitches.none.denyRules, isEmpty);
    expect(ExtensionSwitches.none.toSettings().values, everyElement(isNull));

    final switches = ExtensionSwitches.parse(const {
      ExtensionSwitches.skillsKey: ['review', 3, ''],
      ExtensionSwitches.serversKey: ['docs'],
      ExtensionSwitches.toolsKey: {
        'git': ['push'],
        'empty': <String>[],
        'bad': 'push',
      },
    });
    expect(switches.disabledSkills, {'review'});
    expect(switches.serverEnabled('docs'), isFalse);
    expect(switches.toolEnabled('git', 'push'), isFalse);
    expect(switches.toolEnabled('git', 'status'), isTrue);
    expect(switches.disabledTools.keys, ['git']);
    expect(ExtensionSwitches.parse(switches.toSettings()), switches);
  });

  test('turned on and off; a server with no tool off left out', () {
    var switches = ExtensionSwitches.none
        .withSkills(['a', 'b'], false)
        .withTool('git', 'push', false);
    expect(switches.disabledSkills, {'a', 'b'});
    switches = switches.withSkills(['a'], true).withTool('git', 'push', true);
    expect(switches.disabledSkills, {'b'});
    expect(switches.disabledTools, isEmpty);
    expect(switches.toSettings()[ExtensionSwitches.toolsKey], isNull);
  });

  test('as Claude Code is given them: rules by its names, a server off '
      'covering its tools', () {
    const switches = ExtensionSwitches(
      disabledSkills: {'review'},
      disabledServers: {'claude.ai Docs'},
      disabledTools: {
        'claude.ai Docs': {'search'},
        'my-git': {'push.force'},
      },
    );
    expect(switches.denyRules, [
      'mcp__claude_ai_Docs',
      // The server's own off already: its tool not named again.
      'mcp__my-git__push_force',
    ]);
    expect(switches.skillOverrides, {'review': 'off'});
  });
}
