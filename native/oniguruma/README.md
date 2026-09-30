# Oniguruma

The regular expressions TextMate grammars run on, as VS Code runs them:
Oniguruma, with vscode-oniguruma's scanner on top. hook/build.dart builds it
for macOS, Linux and Windows; lib/ide/editor/textmate/oniguruma binds it.

VS Code 6a598d4a13031703d483d103c1d934a36ad27971 pins vscode-oniguruma 1.7.0
and vscode-textmate 9.3.2.

- `onig/`: Oniguruma 6.9.8, kkos/oniguruma
  08d36110c5670c815ad6d6f969e578049d209080 (vscode-oniguruma 1.7.0's
  `deps/oniguruma` submodule), unmodified: `COPYING` and the part of `src/`
  that `src/Makefile.am` builds libonig from with `./configure`'s defaults, as
  vscode-oniguruma's `build-onig` script does (every encoding, no POSIX API),
  with the Unicode data unicode.c includes. BSD-2-Clause, see `onig/COPYING`.
- `config/config.h`: what `./configure` (or `src/config.h.windows.in`) would
  define, from the compiler instead of probes.
- `monad_onig.c`: vscode-oniguruma 1.7.0
  (microsoft/vscode-oniguruma 716aeaa229e4ae2e3b0057377b55743e9a3e995b)
  `src/onig.cc`: the scanner over a regset, with the per-regex search cache
  for strings of 1000 UTF-8 bytes or more. Its `src/index.ts` (UTF-16 to
  UTF-8 and back) is ported to Dart, in
  lib/ide/editor/textmate/oniguruma/onig_lib_io.dart. MIT, see `LICENSE.txt`.

An invalid pattern does what it does in the WebAssembly vscode-oniguruma
publishes, not what `onig.cc` reads as: there the scanner is made all the
same, and never throws. The top of `monad_onig.c` has the details;
`NativeOnigLib(strict: true)` throws instead.

test/ide/editor/textmate/oniguruma/vscode_oniguruma_parity.json is what the
published vscode-oniguruma 1.7.0 returns for a few thousand searches, made by
vscode_oniguruma_parity.mjs next to it; onig_parity_test.dart replays them.
