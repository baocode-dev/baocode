// What a file browser shows of a machine: where to start (its drives on
// Windows, `/` elsewhere) and a folder's entries, each with whether the
// system hides it, as Explorer and Finder do (a name with a leading dot;
// on Windows, the hidden and system attributes too).

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A place to browse a machine from: a drive on Windows (`C:\`), the root
/// elsewhere (`/`, and on a Mac its other volumes).
class BrowseRoot {
  const BrowseRoot(
    this.path, {
    this.label = '',
    this.kind = BrowseRootKind.fixed,
  });

  factory BrowseRoot.fromJson(List<Object?> json) => BrowseRoot(
    json[0] as String,
    label: json.length > 1 ? json[1] as String? ?? '' : '',
    kind: json.length > 2
        ? BrowseRootKind.values.asNameMap()[json[2]] ?? BrowseRootKind.fixed
        : BrowseRootKind.fixed,
  );

  final String path;

  /// Its volume's name (`Windows`); empty when it has none.
  final String label;
  final BrowseRootKind kind;

  List<Object?> toJson() => [path, label, kind.name];
}

enum BrowseRootKind { fixed, removable, network, optical }

/// An entry of a folder, as a file browser lists it.
class BrowseEntry {
  const BrowseEntry(
    this.name, {
    required this.isDirectory,
    this.hidden = false,
    this.system = false,
  });

  factory BrowseEntry.fromJson(List<Object?> json) {
    final flags = json[2] as int;
    return BrowseEntry(
      json[0] as String,
      isDirectory: json[1] as bool,
      hidden: flags & 1 != 0,
      system: flags & 2 != 0,
    );
  }

  final String name;

  /// A folder, or a link to one.
  final bool isDirectory;

  /// Hidden by the system's file browser until asked: a leading dot, or
  /// Windows' hidden attribute.
  final bool hidden;

  /// One of Windows' protected files (hidden and system: `pagefile.sys`,
  /// `$Recycle.Bin`), hidden further still.
  final bool system;

  List<Object?> toJson() => [
    name,
    isDirectory,
    (hidden ? 1 : 0) | (system ? 2 : 0),
  ];
}

/// The places to browse this machine from.
List<BrowseRoot> browseRoots() {
  if (Platform.isWindows) return _windowsDrives();
  return [
    const BrowseRoot('/'),
    // A Mac's other disks; its own is a link back to `/`.
    if (Platform.isMacOS)
      for (final volume in _entriesOf('/Volumes'))
        if (volume is Directory)
          BrowseRoot(volume.path, label: p.basename(volume.path)),
  ];
}

List<FileSystemEntity> _entriesOf(String path) {
  try {
    return Directory(path).listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
  } on FileSystemException {
    return const [];
  }
}

/// The entries of [directory], folders and files, each with whether it is
/// hidden; throws a [FileSystemException] when it cannot be read.
Future<List<BrowseEntry>> browseDirectory(String directory) async {
  final entries = <BrowseEntry>[];
  await for (final entity in Directory(directory).list(followLinks: false)) {
    // A link is what it leads to; one leading nowhere, a file.
    final isDirectory = switch (entity) {
      Directory() => true,
      File() => false,
      Link() => await FileSystemEntity.isDirectory(entity.path),
      _ => false,
    };
    final name = p.basename(entity.path);
    var hidden = name.startsWith('.');
    var system = false;
    if (Platform.isWindows) {
      final attributes = _windowsAttributes(entity.path);
      if (attributes != null) {
        hidden |= attributes & _fileAttributeHidden != 0;
        // Explorer's "protected operating system files": hidden and system.
        system =
            attributes & _fileAttributeHidden != 0 &&
            attributes & _fileAttributeSystem != 0;
      }
    }
    entries.add(
      BrowseEntry(
        name,
        isDirectory: isDirectory,
        hidden: hidden,
        system: system,
      ),
    );
  }
  return entries;
}

// kernel32, by hand, as bao_conpty's.

const _fileAttributeHidden = 0x2;
const _fileAttributeSystem = 0x4;
const _invalidFileAttributes = 0xFFFFFFFF;
const _heapZeroMemory = 0x8;
const _invalidHandle = -1;

/// WIN32_FIND_DATAW's size.
const _findDataSize = 592;

const _driveRemovable = 2;
const _driveFixed = 3;
const _driveRemote = 4;
const _driveCdrom = 5;

/// Whether Windows recognizes [path] as an application execution alias.
/// Unlike an ordinary link, it is resolved when Windows launches it.
bool windowsAppExecutionAliasExists(String path) {
  if (!Platform.isWindows ||
      path.contains('\u0000') ||
      path.contains('*') ||
      path.contains('?')) {
    return false;
  }
  final heap = _Heap();
  try {
    final data = heap<Uint32>(_findDataSize);
    final find = _findFirstFile(heap.utf16(path), data.cast());
    if (find == _invalidHandle) return false;
    _findClose(find);
    // WIN32_FIND_DATAW.dwReserved0 carries the reparse tag.
    return data[0] & 0x400 != 0 && data[9] == 0x8000001B;
  } finally {
    heap.free();
  }
}

/// [path]'s attributes; null when they cannot be read. One the system
/// holds open (`pagefile.sys`) has them read from its folder's listing.
int? _windowsAttributes(String path) {
  final heap = _Heap();
  try {
    final name = heap.utf16(path);
    final attributes = _getFileAttributes(name);
    if (attributes != _invalidFileAttributes) return attributes;
    // WIN32_FIND_DATAW, its attributes first.
    final data = heap<Uint32>(_findDataSize);
    final find = _findFirstFile(name, data.cast());
    if (find == _invalidHandle) return null;
    _findClose(find);
    return data.value;
  } finally {
    heap.free();
  }
}

List<BrowseRoot> _windowsDrives() {
  final mask = _getLogicalDrives();
  final roots = <BrowseRoot>[];
  for (var i = 0; i < 26; i++) {
    if (mask & (1 << i) == 0) continue;
    final path = '${String.fromCharCode(0x41 + i)}:\\';
    final heap = _Heap();
    try {
      final root = heap.utf16(path);
      final type = _getDriveType(root);
      final kind = switch (type) {
        _driveRemovable => BrowseRootKind.removable,
        _driveRemote => BrowseRootKind.network,
        _driveCdrom => BrowseRootKind.optical,
        _ => BrowseRootKind.fixed,
      };
      var label = '';
      // A fixed disk's name: asking a network drive or an empty one may
      // wait on it.
      if (type == _driveFixed) {
        const length = 261;
        final name = heap<Uint16>(length * sizeOf<Uint16>());
        if (_getVolumeInformation(
              root,
              name,
              length,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
            ) !=
            0) {
          final units = name.asTypedList(length);
          final end = units.indexOf(0);
          label = String.fromCharCodes(units, 0, end < 0 ? length : end);
        }
      }
      roots.add(BrowseRoot(path, label: label, kind: kind));
    } finally {
      heap.free();
    }
  }
  return roots;
}

/// Native memory for one call, freed together.
final class _Heap {
  final _allocated = <Pointer<Void>>[];

  /// [bytes] of zeroes.
  Pointer<T> call<T extends NativeType>(int bytes) {
    final pointer = _heapAlloc(_getProcessHeap(), _heapZeroMemory, bytes);
    if (pointer == nullptr) throw const OSError('Out of memory');
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

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _getFileAttributes = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Uint16>),
      int Function(Pointer<Uint16>)
    >('GetFileAttributesW');

final _findFirstFile = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Uint16>, Pointer<Void>),
      int Function(Pointer<Uint16>, Pointer<Void>)
    >('FindFirstFileW');

final _findClose = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('FindClose');

final _getLogicalDrives = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLogicalDrives');

final _getDriveType = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Uint16>),
      int Function(Pointer<Uint16>)
    >('GetDriveTypeW');

final _getVolumeInformation = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Uint16>,
        Pointer<Uint16>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint16>,
        Uint32,
      ),
      int Function(
        Pointer<Uint16>,
        Pointer<Uint16>,
        int,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint16>,
        int,
      )
    >('GetVolumeInformationW');

final _getProcessHeap = _kernel32
    .lookupFunction<IntPtr Function(), int Function()>(
      'GetProcessHeap',
      isLeaf: true,
    );

final _heapAlloc = _kernel32
    .lookupFunction<
      Pointer<Void> Function(IntPtr, Uint32, IntPtr),
      Pointer<Void> Function(int, int, int)
    >('HeapAlloc', isLeaf: true);

final _heapFree = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Void>),
      int Function(int, int, Pointer<Void>)
    >('HeapFree', isLeaf: true);
