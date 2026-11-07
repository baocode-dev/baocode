import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../protocol.dart' show RemotePlatform;

/// This machine, as mason names it.
RemotePlatform machinePlatform() {
  final (os, arch) = switch (Abi.current()) {
    Abi.macosArm64 => ('darwin', 'arm64'),
    Abi.macosX64 => ('darwin', 'x64'),
    Abi.linuxArm64 => ('linux', 'arm64'),
    Abi.linuxX64 => ('linux', 'x64'),
    Abi.linuxArm => ('linux', 'arm'),
    Abi.linuxRiscv64 => ('linux', 'riscv64'),
    Abi.linuxRiscv32 => ('linux', 'riscv32'),
    Abi.windowsX64 => ('win', 'x64'),
    Abi.windowsArm64 => ('win', 'arm64'),
    final abi => (Platform.operatingSystem, '$abi'),
  };
  String? libc;
  if (os == 'linux') {
    try {
      libc =
          Directory('/lib')
              .listSync()
              .any((entry) => p.basename(entry.path).startsWith('ld-musl-'))
          ? 'musl'
          : 'gnu';
    } on FileSystemException {
      libc = 'gnu';
    }
  }
  return RemotePlatform(os, arch, libc: libc);
}
