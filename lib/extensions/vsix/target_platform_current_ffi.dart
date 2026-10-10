import 'dart:ffi' show Abi;

import 'target_platform.dart';

/// This machine's, from its `Abi`.
ExtensionTargetPlatform currentTargetPlatform() => switch (Abi.current()) {
  Abi.macosArm64 => ExtensionTargetPlatform.darwinArm64,
  Abi.macosX64 => ExtensionTargetPlatform.darwinX64,
  Abi.windowsX64 => ExtensionTargetPlatform.win32X64,
  Abi.windowsArm64 => ExtensionTargetPlatform.win32Arm64,
  Abi.linuxX64 => ExtensionTargetPlatform.linuxX64,
  Abi.linuxArm64 => ExtensionTargetPlatform.linuxArm64,
  Abi.linuxArm => ExtensionTargetPlatform.linuxArmhf,
  _ => ExtensionTargetPlatform.unknown,
};
