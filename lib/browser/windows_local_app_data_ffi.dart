// Windows' LocalAppData folder, asked of the Shell for the current user's
// token rather than %TEMP% or %LOCALAPPDATA%: two processes of the same user
// (e.g. a browser started by explorer.exe and BaoCode started by a desktop
// launcher or auto-run helper) can inherit different TEMP/TMP values, while
// SHGetKnownFolderPath(FOLDERID_LocalAppData) always answers the same path.

import 'dart:ffi';
import 'dart:io';

/// The current user's `LocalAppData` folder on Windows (e.g.
/// `C:\Users\<name>\AppData\Local`); null elsewhere or if the call fails.
String? windowsLocalAppData() {
  if (!Platform.isWindows) return null;
  if (_resolved) return _cached;
  _resolved = true;
  return _cached = _queryLocalAppData();
}

bool _resolved = false;
String? _cached;

String? _queryLocalAppData() {
  final rfid = _localAlloc(_lmemZeroInit, _folderIdLocalAppData.length);
  if (rfid == nullptr) return null;
  final out = _localAlloc(_lmemZeroInit, sizeOf<Pointer<Uint16>>());
  if (out == nullptr) {
    _localFree(rfid);
    return null;
  }
  try {
    rfid
        .cast<Uint8>()
        .asTypedList(_folderIdLocalAppData.length)
        .setAll(0, _folderIdLocalAppData);
    final outPtr = out.cast<Pointer<Uint16>>();
    final hr = _shGetKnownFolderPath(rfid, _kfFlagCreate, 0, outPtr);
    final pathPtr = outPtr.value;
    try {
      if (hr < 0 || pathPtr == nullptr) return null;
      final units = <int>[];
      for (var i = 0; ; i++) {
        final unit = pathPtr[i];
        if (unit == 0) break;
        units.add(unit);
      }
      return units.isEmpty ? null : String.fromCharCodes(units);
    } finally {
      if (pathPtr != nullptr) _coTaskMemFree(pathPtr.cast());
    }
  } finally {
    _localFree(out);
    _localFree(rfid);
  }
}

/// `FOLDERID_LocalAppData`: `{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}`.
const _folderIdLocalAppData = [
  0x85,
  0x27,
  0xB3,
  0xF1,
  0xBA,
  0x6F,
  0xCF,
  0x4F,
  0x9D,
  0x55,
  0x7B,
  0x8E,
  0x7F,
  0x15,
  0x70,
  0x91,
];

const _kfFlagCreate = 0x00008000;
const _lmemZeroInit = 0x40;

final _shell32 = DynamicLibrary.open('shell32.dll');
final _ole32 = DynamicLibrary.open('ole32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _shGetKnownFolderPath = _shell32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, IntPtr, Pointer<Pointer<Uint16>>),
      int Function(Pointer<Void>, int, int, Pointer<Pointer<Uint16>>)
    >('SHGetKnownFolderPath');

final _coTaskMemFree = _ole32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CoTaskMemFree',
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
