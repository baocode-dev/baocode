import 'package:bao_remote/src/platform/windows_executable.dart';
import 'package:flutter_test/flutter_test.dart';

/// A program a Windows host is asked to start by name: found as `cmd.exe`
/// finds it, so npm's `claude.cmd` starts as `claude`.
void main() {
  final files = {
    r'C:\Program Files\Git\cmd\git.exe',
    r'C:\Users\me\AppData\Roaming\npm\claude',
    r'C:\Users\me\AppData\Roaming\npm\claude.cmd',
    r'C:\Users\me\AppData\Roaming\npm\claude.ps1',
  };
  bool isFile(String path) => files.contains(path);
  const environment = {
    'Path':
        r'C:\Windows;C:\Program Files\Git\cmd;;C:\Users\me\AppData\Roaming\npm',
    'PATHEXT': '.COM;.EXE;.BAT;.CMD',
  };

  String find(String name, [Map<String, String> env = environment]) =>
      windowsExecutable(name, env, isFile: isFile);

  test('a bare name: each folder of the PATH, with each PATHEXT', () {
    expect(find('git'), r'C:\Program Files\Git\cmd\git.exe');
    // Not the script beside it Windows cannot start, nor PowerShell's.
    expect(find('claude'), r'C:\Users\me\AppData\Roaming\npm\claude.cmd');
  });

  test('a path, a name with its extension, or one found nowhere: as '
      'given', () {
    expect(find('git.exe'), 'git.exe');
    expect(find(r'C:\tools\x'), r'C:\tools\x');
    expect(find('./x'), './x');
    expect(find('printenv'), 'printenv');
    expect(find('git', const {}), 'git');
  });
}
