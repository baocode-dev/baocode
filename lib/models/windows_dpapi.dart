// The user's DPAPI, called in the process: starting PowerShell for it was
// refused where a policy (Software Restriction Policies, AppLocker) keeps
// users from running powershell.exe, and no key could be kept.

import 'dart:ffi';
import 'dart:typed_data';

import 'secret_store.dart';

/// [data] encrypted for the current user, as `ProtectedData.Protect(data,
/// null, CurrentUser)` did: what PowerShell kept reads the same.
Uint8List dpapiProtect(Uint8List data) => _crypt(data, protect: true);

/// What [dpapiProtect] encrypted.
Uint8List dpapiUnprotect(Uint8List data) => _crypt(data, protect: false);

Uint8List _crypt(Uint8List data, {required bool protect}) {
  final input = _alloc<_Blob>(sizeOf<_Blob>());
  final output = _alloc<_Blob>(sizeOf<_Blob>());
  // At least a byte: LocalAlloc of none gives no buffer.
  final bytes = _alloc<Uint8>(data.isEmpty ? 1 : data.length);
  try {
    bytes.asTypedList(data.length).setAll(0, data);
    input.ref
      ..cbData = data.length
      ..pbData = bytes;
    final ok = (protect ? _cryptProtectData : _cryptUnprotectData)(
      input,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _cryptProtectUiForbidden,
      output,
    );
    if (ok == 0) {
      final error = _getLastError();
      throw SecretStoreException(
        'Windows could not ${protect ? 'encrypt' : 'decrypt'} the key '
        '(error $error)',
      );
    }
    final result = output.ref.pbData;
    try {
      return Uint8List.fromList(result.asTypedList(output.ref.cbData));
    } finally {
      _localFree(result.cast());
    }
  } finally {
    // The secret in the clear, not left in freed memory.
    bytes.asTypedList(data.length).fillRange(0, data.length, 0);
    _localFree(bytes.cast());
    _localFree(input.cast());
    _localFree(output.cast());
  }
}

/// [bytes] of zeroes.
Pointer<T> _alloc<T extends NativeType>(int bytes) {
  final pointer = _localAlloc(_lmemZeroInit, bytes);
  if (pointer == nullptr) throw StateError('Out of memory');
  return pointer.cast();
}

/// `DATA_BLOB`.
final class _Blob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

const _cryptProtectUiForbidden = 0x1;
const _lmemZeroInit = 0x40;

final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _CryptNative = Int32 Function(
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_Blob>,
);
typedef _CryptDart = int Function(
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_Blob>,
);

// Leaf calls, so nothing of the VM's runs between them and GetLastError.
final _cryptProtectData = _crypt32.lookupFunction<_CryptNative, _CryptDart>(
  'CryptProtectData',
  isLeaf: true,
);

final _cryptUnprotectData = _crypt32.lookupFunction<_CryptNative, _CryptDart>(
  'CryptUnprotectData',
  isLeaf: true,
);

final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );

final _localAlloc = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Uint32, IntPtr),
      Pointer<Void> Function(int, int)
    >('LocalAlloc');

final _localFree = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');
