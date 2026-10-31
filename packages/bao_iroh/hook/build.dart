import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

/// Builds rust/ (iroh, and the C interface lib/src/ffi.dart binds) for
/// the app's platform, for an app and for `dart test` alike. rustup has to
/// be there: it fetches the version rust/rust-toolchain.toml names. The
/// web has none.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await const RustBuilder(
      assetName: 'src/ffi.dart',
    ).run(input: input, output: output);
  });
}
