// The `tildify` cases of VS Code 6a598d4a13031703d483d103c1d934a36ad27971
// src/vs/base/test/common/labels.test.ts (`getPathLabel`, Tildify), on
// `tildify` itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/base/common/labels.dart';
import 'package:monad/ide/editor/monaco/vs/base/common/platform.dart';

void main() {
  test('tildify', () {
    const path = '/some/folder/file.txt';
    expect(tildify(path, '/some', OperatingSystem.windows), path);
    expect(
      tildify(path, '/some', OperatingSystem.macintosh),
      '~/folder/file.txt',
    );
    expect(tildify(path, '/some', OperatingSystem.linux), '~/folder/file.txt');
    // `//some/folder/file.txt` (nixBadFileUri) is not under `/some`.
    expect(
      tildify('//some/folder/file.txt', '/some', OperatingSystem.macintosh),
      '//some/folder/file.txt',
    );
    // A home with its trailing slash; the home itself is left alone.
    expect(tildify(path, '/some/', OperatingSystem.linux), '~/folder/file.txt');
    expect(tildify('/some', '/some', OperatingSystem.linux), '/some');
    // macOS compares case-insensitively, Linux does not.
    expect(tildify('/SOME/file', '/some', OperatingSystem.macintosh), '~/file');
    expect(tildify('/SOME/file', '/some', OperatingSystem.linux), '/SOME/file');
    expect(tildify(path, '', OperatingSystem.linux), path);
  });
}
