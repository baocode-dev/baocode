import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Git on a host whose paths are spelled otherwise than here (a Mac's or
/// Linux's from Windows): the folder it runs in and the paths of its status
/// are spelled as there, not as here. Shown with Windows' from here.
void main() {
  test('runs and reads status in the host\'s spelling of paths', () async {
    final ran = <String>[];
    final service = IdeGitService(
      r'C:/work/app/',
      pathContext: p.windows,
      runner: (arguments, {required workingDirectory, limit}) async {
        ran.add(workingDirectory);
        if (arguments.first == 'rev-parse') {
          return const IdeGitOutput(0, 'C:/work/app\n', '');
        }
        return const IdeGitOutput(0, '## main\x00 M lib/a.dart\x00', '');
      },
    );
    expect(service.root, r'C:\work\app');
    final state = (await service.status())!;
    expect(ran, everyElement(r'C:\work\app'));
    expect(state.resources.single.path, r'C:\work\app\lib\a.dart');
    expect(state.decorations.file(r'C:/work/app/lib/a.dart')?.letter, 'M');
    expect(state.decorations.folder(r'C:\work\app\lib')?.letter, '•');
  });
}
