import 'dart:io';

import 'package:baocode/kernel/claude_code/core_ripgrep_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'rg on the core\'s PATH runs Claude Code\'s build as ripgrep (#883)',
    () async {
      final temp = await Directory.systemTemp.createTemp('core_ripgrep');
      addTearDown(() => temp.delete(recursive: true));
      // Says what it was run as, and with what.
      final build = File(p.join(temp.path, "it's claude"))
        ..writeAsStringSync('#!/bin/sh\necho "\$ARGV0" "\$@"\n');
      await Process.run('chmod', ['755', build.path]);

      final bin = await CoreRipgrep.writeShims(
        p.join(temp.path, 'bin'),
        build.path,
      );
      final result = await Process.run(
        'sh',
        ['-c', 'rg --files "a b"'],
        environment: {'PATH': '$bin:/usr/bin:/bin'},
      );
      expect(result.stdout, 'rg --files a b\n');

      // Written again only where it changed.
      final shim = File(p.join(bin, 'rg'));
      final written = shim.lastModifiedSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await CoreRipgrep.writeShims(bin, build.path);
      expect(shim.lastModifiedSync(), written);

      // cmd.exe's too, on Windows.
      await CoreRipgrep.writeShims(bin, r'C:\b\claude.exe', windows: true);
      expect(
        File(p.join(bin, 'rg.cmd')).readAsStringSync(),
        contains(r'"C:\b\claude.exe" %*'),
      );
    },
    skip: Platform.isWindows ? 'POSIX shell scripts' : null,
  );
}
