import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'windows_vswhere.dart';

/// Builds the native code, for the app and for `flutter test` alike: the
/// pseudo terminal's native half (native/pty) for macOS and Linux (Windows
/// needs none: its ConPTY is in kernel32), and Oniguruma with its scanner
/// (native/oniguruma) for macOS, Linux and Windows. The web has neither.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    if (os == OS.macOS || os == OS.linux) {
      await CBuilder.library(
        name: 'baocode_pty',
        assetName: 'ide/terminal/pty_native.dart',
        sources: ['native/pty/baocode_pty.c'],
        frameworks: const [],
        flags: const ['-Wall', '-Wextra'],
      ).run(input: input, output: output);
    }
    if (os == OS.macOS || os == OS.linux || os == OS.windows) {
      if (os == OS.windows) {
        await configureWindowsCompiler(input.config);
      }
      await CBuilder.library(
        name: 'baocode_onig',
        assetName: 'ide/editor/textmate/oniguruma/onig_native.dart',
        sources: [
          'native/oniguruma/baocode_onig.c',
          for (final source in _oniguruma) 'native/oniguruma/onig/src/$source',
        ],
        includes: const [
          'native/oniguruma/config',
          'native/oniguruma/onig/src',
        ],
        // Oniguruma is linked in, not imported from a DLL of its own.
        defines: const {'ONIG_STATIC': null},
        frameworks: const [],
        // Oniguruma's st.c has K&R-style declarations, which C23 (GCC 15's
        // default) no longer takes.
        std: os == OS.windows ? null : 'gnu11',
        flags: os == OS.windows
            ? const ['/W3', '/utf-8', '/D_CRT_SECURE_NO_WARNINGS']
            : const [
                '-Wall',
                '-fvisibility=hidden',
                '-Wno-deprecated-non-prototype',
              ],
      ).run(input: input, output: output);
    }
  });
}

/// Oniguruma's sources as its src/Makefile.am builds libonig with
/// `./configure`'s defaults (no POSIX API), which is how vscode-oniguruma
/// builds it: every encoding, though only UTF-8 is used. unicode.c includes
/// the rest of native/oniguruma/onig/src (the Unicode data).
const _oniguruma = [
  'regparse.c',
  'regcomp.c',
  'regexec.c',
  'regenc.c',
  'regerror.c',
  'regext.c',
  'regsyntax.c',
  'regtrav.c',
  'regversion.c',
  'st.c',
  'reggnu.c',
  'unicode.c',
  'unicode_unfold_key.c',
  'unicode_fold1_key.c',
  'unicode_fold2_key.c',
  'unicode_fold3_key.c',
  'ascii.c',
  'utf8.c',
  'utf16_be.c',
  'utf16_le.c',
  'utf32_be.c',
  'utf32_le.c',
  'euc_jp.c',
  'euc_jp_prop.c',
  'sjis.c',
  'sjis_prop.c',
  'iso8859_1.c',
  'iso8859_2.c',
  'iso8859_3.c',
  'iso8859_4.c',
  'iso8859_5.c',
  'iso8859_6.c',
  'iso8859_7.c',
  'iso8859_8.c',
  'iso8859_9.c',
  'iso8859_10.c',
  'iso8859_11.c',
  'iso8859_13.c',
  'iso8859_14.c',
  'iso8859_15.c',
  'iso8859_16.c',
  'euc_tw.c',
  'euc_kr.c',
  'big5.c',
  'gb18030.c',
  'koi8_r.c',
  'cp1251.c',
  'onig_init.c',
];
