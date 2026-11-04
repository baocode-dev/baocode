import 'dart:ffi' show Abi;

/// The server build this machine makes itself (`darwin-arm64`,
/// `windows-x64`, …): a Mac's or Windows'; null elsewhere.
String? hostServerPlatform() => switch (Abi.current()) {
  Abi.macosArm64 => 'darwin-arm64',
  Abi.macosX64 => 'darwin-x64',
  Abi.windowsArm64 => 'windows-arm64',
  Abi.windowsX64 => 'windows-x64',
  _ => null,
};
