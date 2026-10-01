/// Oniguruma's scanner, native/oniguruma/bao_onig.c, built by
/// hook/build.dart for macOS, Linux and Windows. The calls a tokenizer makes
/// per line and per match are leaf calls.
@DefaultAsset('package:bao_editor/textmate/oniguruma/onig_native.dart')
library;

import 'dart:ffi';

/// A scanner: its regexes, their regset and its result.
final class OnigScannerHandle extends Opaque {}

/// Room for an invalid pattern's message (Oniguruma's
/// `ONIG_MAX_ERROR_MESSAGE_LEN` is 90).
const onigErrorLength = 128;

@Native<Pointer<Void> Function(Int64)>(symbol: 'bao_onig_malloc', isLeaf: true)
external Pointer<Void> onigMalloc(int count);

@Native<Void Function(Pointer<Void>)>(symbol: 'bao_onig_free', isLeaf: true)
external void onigFree(Pointer<Void> pointer);

@Native<Int64 Function()>(symbol: 'bao_onig_next_string_id', isLeaf: true)
external int onigNextStringId();

@Native<Int32 Function()>(symbol: 'bao_onig_version', isLeaf: true)
external int onigVersion();

/// A scanner over [count] UTF-8 patterns laid end to end, with the index of
/// the first invalid one (or -1) in [invalid] and its message in [error]
/// ([onigErrorLength] bytes). An invalid pattern still makes a scanner, as in
/// VS Code: see native/oniguruma/bao_onig.c.
@Native<
  Pointer<OnigScannerHandle> Function(
    Pointer<Uint8>,
    Pointer<Int32>,
    Int32,
    Pointer<Int32>,
    Pointer<Uint8>,
  )
>(symbol: 'bao_onig_scanner_new')
external Pointer<OnigScannerHandle> onigScannerNew(
  Pointer<Uint8> patterns,
  Pointer<Int32> lengths,
  int count,
  Pointer<Int32> invalid,
  Pointer<Uint8> error,
);

/// Takes `Pointer<Void>` to serve as a [NativeFinalizer]'s callback.
@Native<Void Function(Pointer<Void>)>(
  symbol: 'bao_onig_scanner_free',
  isLeaf: true,
)
external void onigScannerFree(Pointer<Void> scanner);

/// The register count, then each register's UTF-8 start and end: read as
/// unsigned, as vscode-oniguruma's `HEAPU32` does.
@Native<Pointer<Uint32> Function(Pointer<OnigScannerHandle>)>(
  symbol: 'bao_onig_scanner_result',
  isLeaf: true,
)
external Pointer<Uint32> onigScannerResult(Pointer<OnigScannerHandle> scanner);

@Native<Int32 Function(Pointer<OnigScannerHandle>)>(
  symbol: 'bao_onig_scanner_capacity',
  isLeaf: true,
)
external int onigScannerCapacity(Pointer<OnigScannerHandle> scanner);

/// The index of the matching pattern, or -1.
@Native<
  Int32 Function(
    Pointer<OnigScannerHandle>,
    Int64,
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'bao_onig_find_next', isLeaf: true)
external int onigFindNext(
  Pointer<OnigScannerHandle> scanner,
  int stringId,
  Pointer<Uint8> string,
  int length,
  int position,
  int options,
);
