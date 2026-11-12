import 'dart:io';

import 'package:bao_agent/bao_agent.dart' show FileIndex;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'with no rg of its own, the program named is run as ripgrep (#883)',
    () async {
      final temp = await Directory.systemTemp.createTemp('file_index');
      addTearDown(() => temp.delete(recursive: true));
      final root = await Directory(p.join(temp.path, 'root')).create();
      // Claude Code's build: ripgrep only with ARGV0=rg.
      final multicall = File(p.join(temp.path, 'claude'))
        ..writeAsStringSync(
          '#!/bin/sh\n'
          '[ "\$ARGV0" = rg ] || exit 2\n'
          r"printf 'a.txt\0sub/b.txt\0'"
          '\n',
        );
      await Process.run('chmod', ['755', multicall.path]);
      final index = FileIndex({
        'PATH': p.join(temp.path, 'none'),
        FileIndex.multicallVariable: multicall.path,
      });
      expect(index.ripgrep, multicall.path);
      expect(await index.list(root.path), [
        p.join(root.path, 'a.txt'),
        p.join(root.path, 'sub', 'b.txt'),
      ]);

      // One of its own goes first.
      final bin = await Directory(p.join(temp.path, 'bin')).create();
      final own = File(p.join(bin.path, 'rg'))
        ..writeAsStringSync('#!/bin/sh\n');
      await Process.run('chmod', ['755', own.path]);
      expect(
        FileIndex({
          'PATH': bin.path,
          FileIndex.multicallVariable: multicall.path,
        }).ripgrep,
        own.path,
      );
    },
    skip: Platform.isWindows ? 'POSIX shell scripts' : null,
  );
}
