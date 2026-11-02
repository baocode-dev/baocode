import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

/// Builds rust/ (iroh, and the C interface lib/src/ffi.dart binds) for
/// the app's platform, for an app and for `dart test` alike. rustup has to
/// be there: it fetches the version rust/rust-toolchain.toml names. The
/// web has none.
///
/// A library already built, at `build/prebuilt/<target>/`, is taken as it
/// is: CI's, from the cache bao_iroh.yml fills for the sources as they are
/// (release.yml and mobile.yml restore it). Nowhere else is there one.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final prebuilt = _prebuilt(input);
    if (prebuilt != null) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'src/ffi.dart',
          linkMode: DynamicLoadingBundled(),
          file: prebuilt.uri,
        ),
      );
      output.dependencies.add(prebuilt.uri);
      return;
    }
    await const RustBuilder(assetName: 'src/ffi.dart')
        .run(input: input, output: output);
  });
}

File? _prebuilt(BuildInput input) {
  final code = input.config.code;
  if (code.linkModePreference == LinkModePreference.static ||
      code.linkModePreference == LinkModePreference.preferStatic) {
    return null;
  }
  final triple = switch ((code.targetOS, code.targetArchitecture)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.iOS, Architecture.arm64) when code.iOS.targetSdk == IOSSdk.iPhoneOS =>
      'aarch64-apple-ios',
    (OS.iOS, Architecture.arm64)
        when code.iOS.targetSdk == IOSSdk.iPhoneSimulator =>
      'aarch64-apple-ios-sim',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    _ => null,
  };
  if (triple == null) return null;
  final name = code.targetOS.libraryFileName(
    'bao_iroh',
    DynamicLoadingBundled(),
  );
  final file = File.fromUri(
    input.packageRoot.resolve('build/prebuilt/$triple/$name'),
  );
  return file.existsSync() ? file : null;
}
