import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds the pseudo terminal's native half (native/pty) for macOS and
/// Linux, for the app and for `flutter test` alike. Windows needs none: its
/// ConPTY is in kernel32. The web has no terminal.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    if (os != OS.macOS && os != OS.linux) return;
    await CBuilder.library(
      name: 'monad_pty',
      assetName: 'ide/terminal/pty_native.dart',
      sources: ['native/pty/monad_pty.c'],
      frameworks: const [],
      flags: const ['-Wall', '-Wextra'],
    ).run(input: input, output: output);
  });
}
