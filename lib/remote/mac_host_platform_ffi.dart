import 'dart:ffi' show Abi;

/// This Mac's platform (`darwin-arm64`, `darwin-x64`); null elsewhere.
String? macHostPlatform() => switch (Abi.current()) {
  Abi.macosArm64 => 'darwin-arm64',
  Abi.macosX64 => 'darwin-x64',
  _ => null,
};
