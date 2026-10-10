// Writing the extension runtime's archives (tool/build_exthost_runtime.dart,
// and the tests' fake runtimes): tar and ZIP, byte for byte the same for
// the same entries, so that a build can be repeated and checked against
// the hashes the app ships with.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes a tar archive (ustar; pax `path` records for longer names) to
/// [sink]: entries as they are added, with no owner and [mtime] (seconds
/// since the epoch) for all, so equal input makes equal bytes.
final class TarWriter {
  TarWriter(this._sink, {this.mtime = 0});

  final Sink<List<int>> _sink;
  final int mtime;

  void addDirectory(String path, {int mode = 0x1ED /* 0755 */}) {
    final name = path.endsWith('/') ? path : '$path/';
    _header(name, mode: mode, size: 0, type: '5');
  }

  void addFile(String path, List<int> content, {int mode = 0x1A4 /* 0644 */}) {
    _header(path, mode: mode, size: content.length, type: '0');
    _sink.add(content);
    _pad(content.length);
  }

  /// The two zero blocks that end an archive; then the sink is closed.
  void close() {
    _sink.add(Uint8List(1024));
    _sink.close();
  }

  void _pad(int size) {
    final padding = (512 - size % 512) % 512;
    if (padding > 0) _sink.add(Uint8List(padding));
  }

  void _header(
    String path, {
    required int mode,
    required int size,
    required String type,
  }) {
    final name = utf8.encode(path);
    var field = name;
    var prefix = <int>[];
    if (name.length > 100) {
      // ustar's prefix/name split at a slash, else a pax record.
      final split = _split(path);
      if (split != null) {
        prefix = utf8.encode(split.$1);
        field = utf8.encode(split.$2);
      } else {
        _pax(path);
        field = utf8.encode(path.substring(0, 99).replaceAll('/', '_'));
        field = field.length > 100 ? field.sublist(0, 100) : field;
      }
    }
    _sink.add(_block(field, prefix, mode: mode, size: size, type: type));
  }

  (String, String)? _split(String path) {
    for (var i = path.length - 1; i > 0; i--) {
      if (path[i] != '/') continue;
      final prefix = path.substring(0, i);
      final rest = path.substring(i + 1);
      if (utf8.encode(prefix).length <= 155 &&
          utf8.encode(rest).length <= 100 &&
          rest.isNotEmpty) {
        return (prefix, rest);
      }
    }
    return null;
  }

  void _pax(String path) {
    // "<length> path=<value>\n", the length counting its own digits.
    final body = utf8.encode(' path=$path\n').length;
    var length = body + 1;
    while ('$length'.length + body != length) {
      length = '$length'.length + body;
    }
    final record = utf8.encode('$length path=$path\n');
    _sink.add(
      _block(
        utf8.encode('PaxHeaders/x'),
        const [],
        mode: 0x1A4,
        size: record.length,
        type: 'x',
      ),
    );
    _sink.add(record);
    _pad(record.length);
  }

  Uint8List _block(
    List<int> name,
    List<int> prefix, {
    required int mode,
    required int size,
    required String type,
  }) {
    final block = Uint8List(512);
    void put(int at, List<int> bytes) =>
        block.setRange(at, at + bytes.length, bytes);
    void octal(int at, int width, int value) => put(
      at,
      ascii.encode('${value.toRadixString(8).padLeft(width - 1, '0')}\x00'),
    );
    put(0, name);
    octal(100, 8, mode);
    octal(108, 8, 0);
    octal(116, 8, 0);
    octal(124, 12, size);
    octal(136, 12, mtime);
    put(148, ascii.encode('        '));
    block[156] = type.codeUnitAt(0);
    put(257, ascii.encode('ustar\x0000'));
    put(345, prefix);
    var sum = 0;
    for (final b in block) {
      sum += b;
    }
    put(148, ascii.encode('${sum.toRadixString(8).padLeft(6, '0')}\x00 '));
    return block;
  }
}

/// Writes a ZIP archive to [file]: deflated entries (stored when that is
/// no smaller), Unix modes kept, all dated 1980-01-01, so equal input makes
/// equal bytes. No Zip64: up to 65535 entries and 4 GiB.
final class ZipWriter {
  ZipWriter(this._file);

  final RandomAccessFile _file;
  final _central = BytesBuilder();
  var _count = 0;
  var _offset = 0;

  void addDirectory(String path, {int mode = 0x1ED}) {
    final name = path.endsWith('/') ? path : '$path/';
    _entry(name, const [], 0, 0, mode | 0x4000, method: 0);
  }

  void addFile(String path, List<int> content, {int mode = 0x1A4}) {
    // gzip's member is a raw deflate stream between a 10-byte header (no
    // name: zlib writes none) and the CRC-32 and size: one pass for both.
    final gz = GZipCodec(level: 9).encode(content);
    if (gz[3] != 0) throw StateError('Unexpected gzip header flags');
    final trailer = ByteData.sublistView(
      Uint8List.fromList(gz.sublist(gz.length - 8)),
    );
    final crc = trailer.getUint32(0, Endian.little);
    final deflated = gz.sublist(10, gz.length - 8);
    final stored = deflated.length >= content.length;
    _entry(
      path,
      stored ? content : deflated,
      crc,
      content.length,
      mode | 0x8000,
      method: stored ? 0 : 8,
    );
  }

  void _entry(
    String path,
    List<int> data,
    int crc,
    int size,
    int mode, {
    required int method,
  }) {
    final name = utf8.encode(path);
    if (_count == 0xFFFF ||
        _offset + data.length + 30 + name.length > 0xFFFFFFFF) {
      throw StateError('Too big for a ZIP without Zip64');
    }
    const dosTime = 0;
    const dosDate = (0 << 9) | (1 << 5) | 1; // 1980-01-01
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x800, Endian.little) // UTF-8 names
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, dosTime, Endian.little)
      ..setUint16(12, dosDate, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, size, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    final central = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 3 << 8 | 20, Endian.little) // made by Unix, 2.0
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x800, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint16(12, dosTime, Endian.little)
      ..setUint16(14, dosDate, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, size, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(
        38,
        mode << 16 | (mode & 0x4000 != 0 ? 0x10 : 0),
        Endian.little,
      )
      ..setUint32(42, _offset, Endian.little);
    _central
      ..add(central.buffer.asUint8List())
      ..add(name);
    _file
      ..writeFromSync(local.buffer.asUint8List())
      ..writeFromSync(name)
      ..writeFromSync(data);
    _offset += 30 + name.length + data.length;
    _count++;
  }

  /// The central directory and its end; then the file is closed.
  void close() {
    final central = _central.takeBytes();
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, _count, Endian.little)
      ..setUint16(10, _count, Endian.little)
      ..setUint32(12, central.length, Endian.little)
      ..setUint32(16, _offset, Endian.little);
    _file
      ..writeFromSync(central)
      ..writeFromSync(end.buffer.asUint8List())
      ..closeSync();
  }
}
