/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The platforms an extension package is built for.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensions/common/extensions.ts (`TargetPlatform`) and
// src/vs/platform/extensionManagement/common/extensionManagement.ts
// (`TargetPlatformToString`, `toTargetPlatform`, `getTargetPlatform`,
// `isNotWebExtensionInWebTargetPlatform`, `isTargetPlatformCompatible`).
//
// Deviations: [ExtensionTargetPlatform.current] reads Dart's
// `Abi.current()` (upstream asks the running Node for its platform and
// arch, and checks for Alpine's musl); [web] without dart:ffi.

import 'target_platform_current.dart'
    if (dart.library.ffi) 'target_platform_current_ffi.dart';

/// `TargetPlatform`.
enum ExtensionTargetPlatform {
  win32X64('win32-x64', 'Windows 64 bit'),
  win32Arm64('win32-arm64', 'Windows ARM'),
  linuxX64('linux-x64', 'Linux 64 bit'),
  linuxArm64('linux-arm64', 'Linux ARM 64'),
  linuxArmhf('linux-armhf', 'Linux ARM'),
  alpineX64('alpine-x64', 'Alpine Linux 64 bit'),
  alpineArm64('alpine-arm64', 'Alpine ARM 64'),
  darwinX64('darwin-x64', 'Mac'),
  darwinArm64('darwin-arm64', 'Mac Silicon'),
  web('web', 'Web'),
  universal('universal', 'universal'),
  unknown('unknown', 'unknown'),
  undefined('undefined', 'undefined');

  const ExtensionTargetPlatform(this.id, this.label);

  /// As galleries and `extension.vsixmanifest` spell it: `darwin-arm64`.
  final String id;

  /// `TargetPlatformToString`.
  final String label;

  /// `toTargetPlatform`: [unknown] for anything else.
  static ExtensionTargetPlatform parse(String? id) {
    for (final platform in values) {
      if (platform.id == id && platform != unknown && platform != undefined) {
        return platform;
      }
    }
    return unknown;
  }

  /// This machine's, as `getTargetPlatform(platform, arch)`.
  static ExtensionTargetPlatform get current => currentTargetPlatform();

  /// Whether an extension built for this platform is a platform-specific
  /// one (not [universal], [undefined] or [unknown]).
  bool get isSpecific =>
      this != universal && this != undefined && this != unknown;

  /// `isTargetPlatformCompatible(this, allTargetPlatforms, product)`.
  bool isCompatibleWith(
    ExtensionTargetPlatform product, {
    Iterable<ExtensionTargetPlatform> allTargetPlatforms = const [],
  }) {
    // `isNotWebExtensionInWebTargetPlatform`.
    if (product == web && !allTargetPlatforms.contains(web)) return false;
    return switch (this) {
      undefined || universal => true,
      unknown => false,
      _ => this == product,
    };
  }
}
