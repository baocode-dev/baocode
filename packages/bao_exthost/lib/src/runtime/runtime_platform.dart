// Which of the extension runtime's builds a machine runs.

import 'dart:io';

/// The platforms the runtime is built for, as VS Code names them
/// (`<process.platform>-<process.arch>`).
const extHostRuntimePlatforms = [
  'darwin-arm64',
  'darwin-x64',
  'win32-x64',
  'linux-x64',
  'linux-arm64',
];

/// The runtime platform of the machine this runs on; null when there is no
/// build for it.
///
/// From the Dart VM's own target (`Platform.version` ends in
/// `on "macos_arm64"`), not `dart:ffi`'s `Abi`, which a web build cannot
/// import. An x64 app under Rosetta takes the x64 runtime, which runs
/// there too; Windows on Arm takes the x64 one, which Windows emulates.
String? currentExtHostPlatform() =>
    extHostPlatformOf(os: Platform.operatingSystem, version: Platform.version);

/// [currentExtHostPlatform] for the OS name and `Platform.version` given.
String? extHostPlatformOf({required String os, required String version}) {
  final arch =
      RegExp(r'on "[a-z]+_([a-z0-9]+)"').firstMatch(version)?.group(1) ?? '';
  return switch ((os, arch)) {
    ('macos', 'arm64') => 'darwin-arm64',
    ('macos', 'x64') => 'darwin-x64',
    ('windows', 'x64' || 'arm64') => 'win32-x64',
    ('linux', 'x64') => 'linux-x64',
    ('linux', 'arm64') => 'linux-arm64',
    _ => null,
  };
}
