// Reading single entries of a ZIP archive (a .vsix) without extracting it:
// the central directory is read from the end of the file, then only the
// entries asked for.
//
// The record layout follows packages/bao_remote/lib/src/lsp/install/
// archive.dart's `extractZip` (stored and deflated entries, Zip64), copied
// here rather than imported: that one extracts whole archives from memory
// and belongs to the language server installer, which is going away.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A malformed or unsupported archive.
class ZipFormatException implements Exception {
  const ZipFormatException(this.message);

  final String message;

  @override
  String toString() => 'ZipFormatException: $message';
}

/// An entry of the central directory.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.size,
    required this.localHeaderOffset,
  });

  /// As stored: `/`-separated, a folder's ending in `/`.
  final String name;

  /// 0 stored, 8 deflated.
  final int method;
  final int compressedSize;

  /// Uncompressed.
  final int size;
  final int localHeaderOffset;

  bool get isDirectory => name.endsWith('/');

  @override
  String toString() => 'ZipEntry($name, $size)';
}

/// Random access to a ZIP archive: a file ([ZipReader.open]) or bytes
/// ([ZipReader.fromBytes]). Close it when done.
class ZipReader {
  ZipReader._(this._source, this.entries)
    : _byName = {for (final entry in entries) entry.name: entry};

  /// Opens [path], reading its central directory only.
  static Future<ZipReader> open(String path) async {
    final file = await File(path).open();
    try {
      final source = _FileSource(file, await file.length());
      return ZipReader._(source, await _readDirectory(source));
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  static Future<ZipReader> fromBytes(Uint8List bytes) async {
    final source = _BytesSource(bytes);
    return ZipReader._(source, await _readDirectory(source));
  }

  final _ZipSource _source;

  /// In the order the central directory has them.
  final List<ZipEntry> entries;
  final Map<String, ZipEntry> _byName;

  /// The entry named [name] exactly, if any.
  ZipEntry? entry(String name) => _byName[name];

  /// The entry whose name is [name] ignoring case (as VS Code's packaging
  /// lower-cases nothing, but hand-made archives vary).
  ZipEntry? entryIgnoringCase(String name) {
    final exact = _byName[name];
    if (exact != null) return exact;
    final lower = name.toLowerCase();
    for (final entry in entries) {
      if (entry.name.toLowerCase() == lower) return entry;
    }
    return null;
  }

  /// [entry]'s content, at most [maxBytes] of it when given (a deflated
  /// entry is inflated whole first, then cut).
  Future<Uint8List> read(ZipEntry entry, {int? maxBytes}) async {
    final header = await _source.read(entry.localHeaderOffset, 30);
    final data = ByteData.sublistView(header);
    if (header.length < 30 || data.getUint32(0, Endian.little) != 0x04034b50) {
      throw ZipFormatException('Broken ZIP entry: ${entry.name}');
    }
    final start =
        entry.localHeaderOffset +
        30 +
        data.getUint16(26, Endian.little) +
        data.getUint16(28, Endian.little);
    switch (entry.method) {
      case 0:
        final length = maxBytes == null
            ? entry.compressedSize
            : math.min(maxBytes, entry.compressedSize);
        return _source.read(start, length);
      case 8:
        final raw = await _source.read(start, entry.compressedSize);
        final inflated = Uint8List.fromList(
          ZLibDecoder(raw: true).convert(raw),
        );
        return maxBytes == null || inflated.length <= maxBytes
            ? inflated
            : Uint8List.sublistView(inflated, 0, maxBytes);
      default:
        throw ZipFormatException(
          'Unsupported ZIP compression ${entry.method}: ${entry.name}',
        );
    }
  }

  /// [name]'s content as UTF-8 text (without a byte order mark), or null
  /// when there is no such entry.
  Future<String?> readText(String name, {bool ignoreCase = false}) async {
    final found = ignoreCase ? entryIgnoringCase(name) : entry(name);
    if (found == null) return null;
    return decodeText(await read(found));
  }

  Future<void> close() => _source.close();
}

/// UTF-8 [bytes] as text, without a byte order mark.
String decodeText(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

Future<List<ZipEntry>> _readDirectory(_ZipSource source) async {
  final length = source.length;
  // The end of central directory record: 22 bytes, then a comment of up to
  // 64 KiB.
  final tailLength = math.min(length, 22 + 0xFFFF + 20);
  final tailStart = length - tailLength;
  final tail = await source.read(tailStart, tailLength);
  final data = ByteData.sublistView(tail);
  var eocd = -1;
  for (var i = tail.length - 22; i >= 0; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const ZipFormatException('Not a ZIP archive');
  var count = data.getUint16(eocd + 10, Endian.little);
  var size = data.getUint32(eocd + 12, Endian.little);
  var offset = data.getUint32(eocd + 16, Endian.little);
  if ((count == 0xFFFF || offset == 0xFFFFFFFF || size == 0xFFFFFFFF) &&
      eocd >= 20 &&
      data.getUint32(eocd - 20, Endian.little) == 0x07064b50) {
    final zip64 = data.getUint64(eocd - 12, Endian.little);
    final record = ByteData.sublistView(await source.read(zip64, 56));
    if (record.lengthInBytes < 56 ||
        record.getUint32(0, Endian.little) != 0x06064b50) {
      throw const ZipFormatException('Broken Zip64 archive');
    }
    count = record.getUint64(32, Endian.little);
    size = record.getUint64(40, Endian.little);
    offset = record.getUint64(48, Endian.little);
  }
  if (offset + size > length) {
    throw const ZipFormatException('Broken ZIP central directory');
  }
  final directory = await source.read(offset, size);
  final view = ByteData.sublistView(directory);
  final entries = <ZipEntry>[];
  var at = 0;
  for (var i = 0; i < count; i++) {
    if (at + 46 > directory.length ||
        view.getUint32(at, Endian.little) != 0x02014b50) {
      throw const ZipFormatException('Broken ZIP central directory');
    }
    final flags = view.getUint16(at + 8, Endian.little);
    final method = view.getUint16(at + 10, Endian.little);
    var compressed = view.getUint32(at + 20, Endian.little);
    var uncompressed = view.getUint32(at + 24, Endian.little);
    final nameLength = view.getUint16(at + 28, Endian.little);
    final extraLength = view.getUint16(at + 30, Endian.little);
    final commentLength = view.getUint16(at + 32, Endian.little);
    var local = view.getUint32(at + 42, Endian.little);
    final nameBytes = Uint8List.sublistView(
      directory,
      at + 46,
      at + 46 + nameLength,
    );
    final name = flags & 0x800 != 0
        ? utf8.decode(nameBytes, allowMalformed: true)
        : latin1.decode(nameBytes);
    // Zip64 sizes and offset, for the fields saturated above.
    var extra = at + 46 + nameLength;
    final extraEnd = extra + extraLength;
    while (extra + 4 <= extraEnd) {
      final id = view.getUint16(extra, Endian.little);
      final fieldLength = view.getUint16(extra + 2, Endian.little);
      if (id == 0x0001) {
        var field = extra + 4;
        if (uncompressed == 0xFFFFFFFF) {
          uncompressed = view.getUint64(field, Endian.little);
          field += 8;
        }
        if (compressed == 0xFFFFFFFF) {
          compressed = view.getUint64(field, Endian.little);
          field += 8;
        }
        if (local == 0xFFFFFFFF) local = view.getUint64(field, Endian.little);
      }
      extra += 4 + fieldLength;
    }
    at = extraEnd + commentLength;
    entries.add(
      ZipEntry(
        name: name.replaceAll('\\', '/'),
        method: method,
        compressedSize: compressed,
        size: uncompressed,
        localHeaderOffset: local,
      ),
    );
  }
  return entries;
}

abstract class _ZipSource {
  int get length;
  Future<Uint8List> read(int offset, int length);
  Future<void> close();
}

class _FileSource implements _ZipSource {
  _FileSource(this._file, this.length);

  final RandomAccessFile _file;
  @override
  final int length;

  // One read at a time: a RandomAccessFile has one position.
  Future<void> _last = Future.value();

  @override
  Future<Uint8List> read(int offset, int count) {
    final result = _last.then((_) async {
      await _file.setPosition(offset);
      return _file.read(math.max(0, math.min(count, length - offset)));
    });
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> close() => _file.close();
}

class _BytesSource implements _ZipSource {
  _BytesSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    final start = math.min(offset, _bytes.length);
    return Uint8List.sublistView(
      _bytes,
      start,
      math.min(_bytes.length, start + count),
    );
  }

  @override
  Future<void> close() async {}
}
