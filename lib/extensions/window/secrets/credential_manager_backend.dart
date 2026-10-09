// The Windows Credential Manager through advapi32's CredWriteW, CredReadW,
// CredDeleteW and CredFree (dart:ffi; `cmdkey` cannot read a secret back).
// Generic credentials of the target `BaoCode Extension Secrets/<account>`,
// the value's UTF-8 bytes their blob, persisted on the machine for the user.
//
// A blob holds at most 2560 bytes (CRED_MAX_CREDENTIAL_BLOB_SIZE); longer
// values (an OAuth session list can be) are split into parts, the first in
// the target above with `parts=<n>` in its comment, the others in
// `BaoCode Extension Secrets (part <i>)/<account>`.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'secret_backend.dart';

/// What the Credential Manager keeps for a target.
typedef StoredCredential = ({Uint8List blob, String? comment});

/// Generic credentials by target name (an interface so the splitting can be
/// tested off Windows).
abstract interface class CredentialStore {
  /// Null when [target] has none.
  StoredCredential? read(String target);

  void write(String target, Uint8List blob, String? comment);

  /// False when [target] had none.
  bool delete(String target);
}

/// `CRED_MAX_CREDENTIAL_BLOB_SIZE`.
const credentialMaxBlobSize = 5 * 512;

/// The target name of [account]'s [part] (0 is the first).
String credentialTarget(String account, {int part = 0}) => part == 0
    ? '$extensionSecretsService/$account'
    : '$extensionSecretsService (part ${part + 1})/$account';

/// [bytes] in parts of at most [credentialMaxBlobSize] (one, empty, for no
/// bytes).
List<Uint8List> splitCredentialBlob(Uint8List bytes) => [
  for (var at = 0; at == 0 || at < bytes.length; at += credentialMaxBlobSize)
    Uint8List.sublistView(
      bytes,
      at,
      at + credentialMaxBlobSize < bytes.length
          ? at + credentialMaxBlobSize
          : bytes.length,
    ),
];

/// The first part's comment for a value in [parts] parts.
String? credentialPartsComment(int parts) => parts > 1 ? 'parts=$parts' : null;

/// How many parts the value whose first part has [comment] is in.
int credentialParts(String? comment) {
  final match = RegExp(r'parts=(\d+)').firstMatch(comment ?? '');
  final parts = match == null ? 1 : int.parse(match[1]!);
  return parts < 1 ? 1 : parts;
}

/// [text] in UTF-16 code units with a terminating NUL (`LPCWSTR`).
Uint16List utf16z(String text) =>
    Uint16List(text.length + 1)..setAll(0, text.codeUnits);

/// The Credential Manager's generic credentials of this user.
final class CredentialManagerBackend implements SecretBackend {
  /// [store] defaults to advapi32's, opened on first use (Windows only).
  CredentialManagerBackend({CredentialStore? store}) : _given = store;

  final CredentialStore? _given;
  CredentialStore? _opened;
  CredentialStore get _store => _given ?? (_opened ??= Advapi32Credentials());

  @override
  String get kind => 'credential-manager';

  @override
  Future<String?> read(String account) async {
    final first = _store.read(credentialTarget(account));
    if (first == null) return null;
    final parts = credentialParts(first.comment);
    final bytes = BytesBuilder(copy: false)..add(first.blob);
    for (var i = 1; i < parts; i++) {
      final part = _store.read(credentialTarget(account, part: i));
      if (part == null) {
        throw SecretBackendException('Part ${i + 1} of a secret is missing');
      }
      bytes.add(part.blob);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  @override
  Future<void> write(String account, String value) async {
    final old = _store.read(credentialTarget(account));
    final oldParts = old == null ? 0 : credentialParts(old.comment);
    final parts = splitCredentialBlob(utf8.encode(value));
    // The other parts first: the first one says how many there are.
    for (var i = 1; i < parts.length; i++) {
      _store.write(credentialTarget(account, part: i), parts[i], null);
    }
    _store.write(
      credentialTarget(account),
      parts.first,
      credentialPartsComment(parts.length),
    );
    for (var i = parts.length; i < oldParts; i++) {
      _store.delete(credentialTarget(account, part: i));
    }
  }

  @override
  Future<void> delete(String account) async {
    final old = _store.read(credentialTarget(account));
    if (old == null) return;
    _store.delete(credentialTarget(account));
    for (var i = 1; i < credentialParts(old.comment); i++) {
      _store.delete(credentialTarget(account, part: i));
    }
  }
}

/// `CREDENTIALW` (wincred.h).
final class CredentialW extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Uint16> targetName;
  external Pointer<Uint16> comment;
  // FILETIME LastWritten.
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int credentialBlobSize;
  external Pointer<Uint8> credentialBlob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Uint16> targetAlias;
  external Pointer<Uint16> userName;
}

/// `CRED_TYPE_GENERIC`.
const credTypeGeneric = 1;

/// `CRED_PERSIST_LOCAL_MACHINE`: kept across logons, on this machine only.
const credPersistLocalMachine = 2;

/// `ERROR_NOT_FOUND`.
const errorNotFound = 1168;

/// `LPTR` (`LMEM_FIXED | LMEM_ZEROINIT`).
const _lptr = 0x0040;

/// advapi32's credential functions. Memory comes from kernel32's
/// LocalAlloc (dart:ffi has no allocator of its own). The calls are leaf
/// calls so nothing of the VM's runs between one and GetLastError.
final class Advapi32Credentials implements CredentialStore {
  Advapi32Credentials() {
    final advapi = DynamicLibrary.open('advapi32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    _credWrite = advapi
        .lookupFunction<
          Int32 Function(Pointer<CredentialW>, Uint32),
          int Function(Pointer<CredentialW>, int)
        >('CredWriteW', isLeaf: true);
    _credRead = advapi
        .lookupFunction<
          Int32 Function(
            Pointer<Uint16>,
            Uint32,
            Uint32,
            Pointer<Pointer<CredentialW>>,
          ),
          int Function(Pointer<Uint16>, int, int, Pointer<Pointer<CredentialW>>)
        >('CredReadW', isLeaf: true);
    _credDelete = advapi
        .lookupFunction<
          Int32 Function(Pointer<Uint16>, Uint32, Uint32),
          int Function(Pointer<Uint16>, int, int)
        >('CredDeleteW', isLeaf: true);
    _credFree = advapi
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CredFree', isLeaf: true);
    _getLastError = kernel.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );
    _localAlloc = kernel
        .lookupFunction<
          Pointer<Void> Function(Uint32, Size),
          Pointer<Void> Function(int, int)
        >('LocalAlloc', isLeaf: true);
    _localFree = kernel
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('LocalFree', isLeaf: true);
  }

  late final int Function(Pointer<CredentialW>, int) _credWrite;
  late final int Function(
    Pointer<Uint16>,
    int,
    int,
    Pointer<Pointer<CredentialW>>,
  )
  _credRead;
  late final int Function(Pointer<Uint16>, int, int) _credDelete;
  late final void Function(Pointer<Void>) _credFree;
  late final int Function() _getLastError;
  late final Pointer<Void> Function(int, int) _localAlloc;
  late final Pointer<Void> Function(Pointer<Void>) _localFree;

  Pointer<Void> _alloc(int bytes) {
    final memory = _localAlloc(_lptr, bytes < 1 ? 1 : bytes);
    if (memory == nullptr) throw SecretBackendException('Out of memory');
    return memory;
  }

  void _free(Pointer<NativeType> memory) {
    if (memory != nullptr) _localFree(memory.cast());
  }

  Pointer<Uint16> _wide(String text) {
    final units = utf16z(text);
    final memory = _alloc(units.lengthInBytes).cast<Uint16>();
    memory.asTypedList(units.length).setAll(0, units);
    return memory;
  }

  static String? _readWide(Pointer<Uint16> text) {
    if (text == nullptr) return null;
    var length = 0;
    while (text[length] != 0) {
      length++;
    }
    return String.fromCharCodes(text.asTypedList(length));
  }

  @override
  StoredCredential? read(String target) {
    final name = _wide(target);
    final out = _alloc(sizeOf<Pointer<CredentialW>>())
        .cast<Pointer<CredentialW>>();
    try {
      if (_credRead(name, credTypeGeneric, 0, out) == 0) {
        final error = _getLastError();
        if (error == errorNotFound) return null;
        throw SecretBackendException('CredReadW failed (error $error)');
      }
      final credential = out.value;
      try {
        final size = credential.ref.credentialBlobSize;
        final blob = size == 0 || credential.ref.credentialBlob == nullptr
            ? Uint8List(0)
            : Uint8List.fromList(
                credential.ref.credentialBlob.asTypedList(size),
              );
        return (blob: blob, comment: _readWide(credential.ref.comment));
      } finally {
        _credFree(credential.cast());
      }
    } finally {
      _free(name);
      _free(out);
    }
  }

  @override
  void write(String target, Uint8List blob, String? comment) {
    final credential = _alloc(sizeOf<CredentialW>()).cast<CredentialW>();
    final name = _wide(target);
    final remark = comment == null ? nullptr.cast<Uint16>() : _wide(comment);
    final data = _alloc(blob.length).cast<Uint8>();
    data.asTypedList(blob.length).setAll(0, blob);
    credential.ref
      ..type = credTypeGeneric
      ..targetName = name
      ..comment = remark
      ..credentialBlobSize = blob.length
      ..credentialBlob = data
      ..persist = credPersistLocalMachine;
    try {
      if (_credWrite(credential, 0) == 0) {
        throw SecretBackendException(
          'CredWriteW failed (error ${_getLastError()})',
        );
      }
    } finally {
      data.asTypedList(blob.length).fillRange(0, blob.length, 0);
      _free(data);
      _free(remark);
      _free(name);
      _free(credential);
    }
  }

  @override
  bool delete(String target) {
    final name = _wide(target);
    try {
      if (_credDelete(name, credTypeGeneric, 0) != 0) return true;
      final error = _getLastError();
      if (error == errorNotFound) return false;
      throw SecretBackendException('CredDeleteW failed (error $error)');
    } finally {
      _free(name);
    }
  }
}
