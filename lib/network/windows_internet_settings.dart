// Windows' Internet Settings (the system proxy) read from the registry in
// the process: starting `reg.exe` for them blocked the UI thread for as
// long as Windows took to start a process, over 6 s on a machine whose
// security software looks at each one, and every HTTP request after 10 s
// reads them again.

import 'dart:ffi';

import 'proxy_settings.dart';

const _key = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

/// The system proxy in `HKCU\…\Internet Settings`; direct when it cannot be
/// read.
ProxyRoute readWindowsInternetSettings() {
  final heap = _Heap();
  try {
    final key = heap.utf16(_key);
    String text(String name) => _string(heap, key, name) ?? '';
    return windowsInternetSettingsRoute(
      enabled: (_dword(heap, key, 'ProxyEnable') ?? 0) != 0,
      server: text('ProxyServer'),
      override: text('ProxyOverride'),
      autoConfigUrl: text('AutoConfigURL'),
    );
  } finally {
    heap.free();
  }
}

int? _dword(_Heap heap, Pointer<Uint16> key, String name) {
  final data = heap<Uint32>(sizeOf<Uint32>());
  final size = heap<Uint32>(sizeOf<Uint32>())..value = sizeOf<Uint32>();
  final status = _regGetValue(
    _hkeyCurrentUser,
    key,
    heap.utf16(name),
    _rrfRtRegDword,
    nullptr,
    data.cast(),
    size,
  );
  return status == _errorSuccess ? data.value : null;
}

String? _string(_Heap heap, Pointer<Uint16> key, String name) {
  final value = heap.utf16(name);
  final size = heap<Uint32>(sizeOf<Uint32>());
  // Its size first, NUL included, in bytes.
  var status = _regGetValue(
    _hkeyCurrentUser,
    key,
    value,
    _rrfRtRegSz,
    nullptr,
    nullptr,
    size,
  );
  if (status != _errorSuccess || size.value == 0) return null;
  final data = heap<Uint16>(size.value);
  status = _regGetValue(
    _hkeyCurrentUser,
    key,
    value,
    _rrfRtRegSz,
    nullptr,
    data.cast(),
    size,
  );
  if (status != _errorSuccess) return null;
  final units = data.asTypedList(size.value ~/ sizeOf<Uint16>());
  final end = units.indexOf(0);
  return String.fromCharCodes(end < 0 ? units : units.sublist(0, end));
}

/// Native memory for one read, freed together.
final class _Heap {
  final _allocated = <Pointer<Void>>[];

  /// [bytes] of zeroes.
  Pointer<T> call<T extends NativeType>(int bytes) {
    final pointer = _heapAlloc(_getProcessHeap(), _heapZeroMemory, bytes);
    if (pointer == nullptr) throw StateError('Out of memory');
    _allocated.add(pointer);
    return pointer.cast();
  }

  /// [value] in UTF-16, NUL-terminated.
  Pointer<Uint16> utf16(String value) {
    final units = value.codeUnits;
    final pointer = call<Uint16>((units.length + 1) * sizeOf<Uint16>());
    pointer.asTypedList(units.length).setAll(0, units);
    return pointer;
  }

  void free() {
    final heap = _getProcessHeap();
    for (final pointer in _allocated) {
      _heapFree(heap, 0, pointer);
    }
    _allocated.clear();
  }
}

// advapi32 and kernel32, by hand: handles are pointer-sized integers.

/// `HKEY_CURRENT_USER`, `(HKEY)(ULONG_PTR)(LONG)0x80000001`: sign-extended.
const _hkeyCurrentUser = -0x7fffffff;
const _rrfRtRegSz = 0x00000002;
const _rrfRtRegDword = 0x00000010;
const _errorSuccess = 0;
const _heapZeroMemory = 0x00000008;

final _advapi32 = DynamicLibrary.open('advapi32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _regGetValue = _advapi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint16>,
        Pointer<Uint16>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      ),
      int Function(
        int,
        Pointer<Uint16>,
        Pointer<Uint16>,
        int,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      )
    >('RegGetValueW');

final _getProcessHeap = _kernel32
    .lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');

final _heapAlloc = _kernel32
    .lookupFunction<
      Pointer<Void> Function(IntPtr, Uint32, IntPtr),
      Pointer<Void> Function(int, int, int)
    >('HeapAlloc');

final _heapFree = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Void>),
      int Function(int, int, Pointer<Void>)
    >('HeapFree');
