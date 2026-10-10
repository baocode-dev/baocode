import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_models.dart' show runModelTests;

void main() {
  test('packaging model gate propagates test runner failure', () async {
    final directory = await Directory.systemTemp.createTemp('model-test-gate-');
    addTearDown(() => directory.delete(recursive: true));
    // A failing local runner proves the gate's exit contract without invoking
    // nested Flutter tests or depending on a deliberately broken fixture.
    final launcher = File(
      '${directory.path}/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    await launcher.writeAsString(
      Platform.isWindows ? '@echo off\r\nexit /b 7\r\n' : '#!/bin/sh\nexit 7\n',
    );
    if (!Platform.isWindows) {
      final mode = await Process.run('chmod', ['+x', launcher.path]);
      expect(mode.exitCode, 0);
    }
    final code = await runModelTests(
      Directory.current.path,
      executable: launcher.path,
    );
    expect(code, 7);
  });
}
