// The web build runs no extensions but must compile (the goal's "Web 构建继续
// 走 stub"): dart2js has no dart:ffi, and flutter_svg's `SvgPicture.file`
// takes its own `File` there. A full `flutter build web` is too slow for the
// suite; this keeps the two out of what the extensions brought.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dart(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

void main() {
  test('dart:ffi only behind a dart.library.ffi import', () {
    // Imported only through `if (dart.library.ffi)`.
    const behindCondition = {
      'lib/extensions/vsix/target_platform_current_ffi.dart',
      'lib/extensions/window/secrets/credential_manager_backend.dart',
    };
    final direct = [
      for (final directory in ['lib/extensions', 'lib/ide', 'lib/theme'])
        for (final file in _dart(directory))
          if (file.readAsStringSync().contains("import 'dart:ffi'") &&
              !behindCondition.contains(file.path))
            file.path,
    ];
    expect(direct, isEmpty);
  });

  test("no SvgPicture.file with dart:io's File (svg_file.dart instead)", () {
    final uses = [
      for (final file in _dart('lib'))
        if (file.readAsStringSync().contains('SvgPicture.file(') &&
            !file.path.endsWith('svg_file_io.dart'))
          file.path,
    ];
    expect(uses, isEmpty);
  });
}
