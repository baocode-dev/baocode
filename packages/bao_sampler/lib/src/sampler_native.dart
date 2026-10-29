/// The sampler's native half on Windows and Linux: native/bao_sampler.c,
/// and Linux' crash handler, native/bao_crash.c; built by hook/build.dart.
@DefaultAsset('package:bao_sampler/src/sampler_native.dart')
library;

import 'dart:ffi';

@Native<Int32 Function()>(symbol: 'bao_sampler_init')
external int samplerInit();

/// [path] is UTF-8, ending in a 0: a Uint8List's `address` (a leaf call).
@Native<Int32 Function(Pointer<Uint8>, Int32, Int32)>(
  symbol: 'bao_sampler_start',
  isLeaf: true,
)
external int samplerStart(Pointer<Uint8> path, int millis, int interval);

/// Linux' crash handler (native/bao_crash.c): the paths and the header are
/// UTF-8, each ending in a 0 (Uint8Lists' `address`, a leaf call).
@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'bao_crash_install',
  isLeaf: true,
)
external int crashInstall(
  Pointer<Uint8> events,
  Pointer<Uint8> reports,
  Pointer<Uint8> header,
);
