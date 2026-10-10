// Unpacking the extension runtime's archives: tar (gzipped) and ZIP.
//
// Adapted from the former language server installer's archive.dart.
// Unlike that one, it streams: a tar is read as it is downloaded or
// decompressed, and a ZIP from its file, so a 400 MB runtime is never in
// memory whole.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// An archive that cannot be unpacked: broken, truncated, or with entries
/// that would land outside its folder.
final class ArchiveException implements Exception {
  const ArchiveException(this.message);

  final String message;

  @override
  String toString() => 'ArchiveException: $message';
}

/// Extracts a gzipped tar file into [directory]; returns the files whose
/// mode is executable.
Future<List<String>> extractTarGzFile(String file, String directory) =>
    extractTarStream(File(file).openRead().transform(gzip.decoder), directory);

/// Extracts a tar stream (ustar, GNU long names, pax paths) into
/// [directory], as it comes; returns the files whose mode is executable.
Future<List<String>> extractTarStream(
  Stream<List<int>> input,
  String directory,
) async {
  final reader = _TarReader(p.normalize(p.absolute(directory)));
  try {
    await for (final chunk in input) {
      await reader.add(chunk);
    }
    await reader.finish();
  } finally {
    await reader.abort();
  }
  return reader.executables;
}

/// [entry] under [directory], refusing absolute paths and `..` escapes.
String _inside(String directory, String entry) {
  final normalized = entry.replaceAll('\\', '/');
  final target = p.normalize(p.join(directory, normalized));
  if (p.isAbsolute(normalized) ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      !(p.isWithin(directory, target) || p.equals(directory, target))) {
    throw ArchiveException('Archive entry escapes its folder: $entry');
  }
  return target;
}

Future<void> _link(String directory, String path, String target) async {
  final resolved = p.normalize(p.join(p.dirname(path), target));
  if (p.isAbsolute(target) || !p.isWithin(directory, resolved)) {
    throw ArchiveException('Archive link escapes its folder: $target');
  }
  await Directory(p.dirname(path)).create(recursive: true);
  final link = Link(path);
  if (await link.exists() || await File(path).exists()) {
    await File(path).delete();
  }
  await link.create(target);
}

enum _TarState { header, content, meta, padding, done }

final class _TarReader {
  _TarReader(this.directory);

  final String directory;
  final executables = <String>[];
  final _hardLinks = <(String, String)>[];
  final _created = <String>{};

  var _state = _TarState.header;
  final _header = Uint8List(512);
  var _headerFill = 0;
  var _remaining = 0;
  var _padding = 0;
  RandomAccessFile? _out;
  String? _outPath;
  BytesBuilder? _meta;
  String? _metaType;
  String? _longName;
  String? _longLink;

  Future<void> add(List<int> chunk) async {
    var offset = 0;
    while (offset < chunk.length && _state != _TarState.done) {
      final available = chunk.length - offset;
      switch (_state) {
        case _TarState.header:
          final n = math.min(512 - _headerFill, available);
          _header.setRange(_headerFill, _headerFill + n, chunk, offset);
          _headerFill += n;
          offset += n;
          if (_headerFill == 512) {
            _headerFill = 0;
            await _onHeader();
          }
        case _TarState.content:
          final n = math.min(_remaining, available);
          await _out!.writeFrom(chunk, offset, offset + n);
          offset += n;
          _remaining -= n;
          if (_remaining == 0) await _endContent();
        case _TarState.meta:
          final n = math.min(_remaining, available);
          _meta!.add(
            Uint8List.sublistView(
              chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
              offset,
              offset + n,
            ),
          );
          offset += n;
          _remaining -= n;
          if (_remaining == 0) _endMeta();
        case _TarState.padding:
          final n = math.min(_padding, available);
          offset += n;
          _padding -= n;
          if (_padding == 0) _state = _TarState.header;
        case _TarState.done:
          break;
      }
    }
  }

  /// After the last chunk: the archive must have ended where an entry did.
  Future<void> finish() async {
    if (_state != _TarState.done &&
        !(_state == _TarState.header && _headerFill == 0)) {
      throw const ArchiveException('Truncated tar archive');
    }
    for (final (path, source) in _hardLinks) {
      await File(source).copy(path);
      if (executables.contains(source)) executables.add(path);
    }
    _hardLinks.clear();
  }

  /// Closes a file left open by a failure.
  Future<void> abort() async {
    final out = _out;
    _out = null;
    await out?.close();
  }

  String _text(int start, int length) {
    var end = start;
    while (end < start + length && _header[end] != 0) {
      end++;
    }
    return utf8.decode(_header.sublist(start, end), allowMalformed: true);
  }

  int _octal(int start, int length) {
    if (_header[start] & 0x80 != 0) {
      // Base-256, for sizes over 8 GiB.
      var value = _header[start] & 0x7F;
      for (var i = start + 1; i < start + length; i++) {
        value = value << 8 | _header[i];
      }
      return value;
    }
    final digits = _text(start, length).trim();
    if (digits.isEmpty) return 0;
    final value = int.tryParse(digits, radix: 8);
    if (value == null) throw ArchiveException('Broken tar header: "$digits"');
    return value;
  }

  Future<void> _onHeader() async {
    if (_header.every((b) => b == 0)) {
      _state = _TarState.done;
      return;
    }
    // The checksum: the header's bytes summed, its own field as spaces.
    var sum = 0;
    for (var i = 0; i < 512; i++) {
      sum += i >= 148 && i < 156 ? 0x20 : _header[i];
    }
    if (_octal(148, 8) != sum) {
      throw const ArchiveException('Broken tar header (checksum)');
    }
    var name = _text(0, 100);
    final mode = _octal(100, 8);
    final size = _octal(124, 12);
    final type = String.fromCharCode(_header[156] == 0 ? 0x30 : _header[156]);
    var linkName = _text(157, 100);
    if (_text(257, 5) == 'ustar') {
      final prefix = _text(345, 155);
      if (prefix.isNotEmpty) name = '$prefix/$name';
    }
    _remaining = size;
    _padding = (512 - size % 512) % 512;
    switch (type) {
      case 'L' || 'K' || 'x' || 'g':
        _metaType = type;
        _meta = BytesBuilder(copy: false);
        if (size == 0) {
          _endMeta();
        } else {
          _state = _TarState.meta;
        }
        return;
    }
    name = _longName ?? name;
    linkName = _longLink ?? linkName;
    _longName = null;
    _longLink = null;
    if (name.isEmpty || name == '.' || name == './') {
      _skipContent();
      return;
    }
    final target = _inside(directory, name);
    switch (type) {
      case '5':
        await _mkdir(target);
        _skipContent();
      case '2':
        await _link(directory, target, linkName);
        _skipContent();
      case '1':
        _hardLinks.add((target, _inside(directory, linkName)));
        _skipContent();
      case '0' || '7':
        await _mkdir(p.dirname(target));
        _out = await File(target).open(mode: FileMode.write);
        _outPath = target;
        if (mode & 0x49 != 0) executables.add(target);
        if (size == 0) {
          await _endContent();
        } else {
          _state = _TarState.content;
        }
      default:
        // Devices, FIFOs: nothing a runtime has.
        _skipContent();
    }
  }

  Future<void> _mkdir(String path) async {
    if (_created.add(path)) await Directory(path).create(recursive: true);
  }

  /// Passes over an entry's data (none, for most kinds).
  void _skipContent() {
    if (_remaining == 0) {
      _state = _padding == 0 ? _TarState.header : _TarState.padding;
    } else {
      _padding += _remaining;
      _remaining = 0;
      _state = _TarState.padding;
    }
  }

  Future<void> _endContent() async {
    final out = _out!;
    _out = null;
    _outPath = null;
    await out.close();
    _state = _padding == 0 ? _TarState.header : _TarState.padding;
  }

  void _endMeta() {
    final bytes = _meta!.takeBytes();
    _meta = null;
    String text() {
      var end = bytes.indexOf(0);
      if (end < 0) end = bytes.length;
      return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
    }

    switch (_metaType) {
      case 'L':
        _longName = text();
      case 'K':
        _longLink = text();
      case 'x':
        // Records: "<length> <key>=<value>\n".
        final records = utf8.decode(bytes, allowMalformed: true);
        var at = 0;
        while (at < records.length) {
          final space = records.indexOf(' ', at);
          if (space < 0) break;
          final length = int.tryParse(records.substring(at, space));
          if (length == null || length <= 0) break;
          final end = math.min(at + length, records.length);
          final record = records.substring(space + 1, end);
          final equals = record.indexOf('=');
          if (equals > 0) {
            final key = record.substring(0, equals);
            var value = record.substring(equals + 1);
            if (value.endsWith('\n')) {
              value = value.substring(0, value.length - 1);
            }
            if (key == 'path') _longName = value;
            if (key == 'linkpath') _longLink = value;
          }
          at = end;
        }
    }
    _state = _padding == 0 ? _TarState.header : _TarState.padding;
  }

  @override
  String toString() => '_TarReader($directory, $_outPath)';
}

/// Extracts the ZIP [file] (stored or deflated entries, Zip64 included)
/// into [directory], an entry at a time; returns the files whose Unix mode
/// is executable.
Future<List<String>> extractZipFile(String file, String directory) async {
  final root = p.normalize(p.absolute(directory));
  final raf = await File(file).open();
  try {
    final length = await raf.length();
    Future<Uint8List> readAt(int position, int count) async {
      await raf.setPosition(position);
      final bytes = await raf.read(count);
      if (bytes.length != count) {
        throw const ArchiveException('Truncated ZIP archive');
      }
      return bytes;
    }

    final tailLength = math.min(length, 22 + 0xFFFF);
    final tailStart = length - tailLength;
    final tail = await readAt(tailStart, tailLength);
    final tailData = ByteData.sublistView(tail);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tailData.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const ArchiveException('Not a ZIP archive');
    var count = tailData.getUint16(eocd + 10, Endian.little);
    var directorySize = tailData.getUint32(eocd + 12, Endian.little);
    var directoryStart = tailData.getUint32(eocd + 16, Endian.little);
    if ((count == 0xFFFF ||
            directoryStart == 0xFFFFFFFF ||
            directorySize == 0xFFFFFFFF) &&
        eocd >= 20 &&
        tailData.getUint32(eocd - 20, Endian.little) == 0x07064b50) {
      final zip64 = tailData.getUint64(eocd - 12, Endian.little);
      final record = ByteData.sublistView(await readAt(zip64, 56));
      if (record.getUint32(0, Endian.little) != 0x06064b50) {
        throw const ArchiveException('Broken Zip64 archive');
      }
      count = record.getUint64(32, Endian.little);
      directorySize = record.getUint64(40, Endian.little);
      directoryStart = record.getUint64(48, Endian.little);
    }
    final central = await readAt(directoryStart, directorySize);
    final data = ByteData.sublistView(central);
    final executables = <String>[];
    final created = <String>{};
    var offset = 0;
    for (var i = 0; i < count; i++) {
      if (offset + 46 > central.length ||
          data.getUint32(offset, Endian.little) != 0x02014b50) {
        throw const ArchiveException('Broken ZIP central directory');
      }
      final madeBy = data.getUint16(offset + 4, Endian.little);
      final flags = data.getUint16(offset + 8, Endian.little);
      final method = data.getUint16(offset + 10, Endian.little);
      var compressed = data.getUint32(offset + 20, Endian.little);
      var size = data.getUint32(offset + 24, Endian.little);
      final nameLength = data.getUint16(offset + 28, Endian.little);
      final extraLength = data.getUint16(offset + 30, Endian.little);
      final commentLength = data.getUint16(offset + 32, Endian.little);
      final external = data.getUint32(offset + 38, Endian.little);
      var local = data.getUint32(offset + 42, Endian.little);
      final nameBytes = central.sublist(offset + 46, offset + 46 + nameLength);
      final name = flags & 0x800 != 0
          ? utf8.decode(nameBytes, allowMalformed: true)
          : latin1.decode(nameBytes);
      // Zip64 sizes and offset, for the fields saturated above.
      var extra = offset + 46 + nameLength;
      final extraEnd = extra + extraLength;
      while (extra + 4 <= extraEnd) {
        final id = data.getUint16(extra, Endian.little);
        final fieldLength = data.getUint16(extra + 2, Endian.little);
        if (id == 0x0001) {
          var field = extra + 4;
          if (size == 0xFFFFFFFF) {
            size = data.getUint64(field, Endian.little);
            field += 8;
          }
          if (compressed == 0xFFFFFFFF) {
            compressed = data.getUint64(field, Endian.little);
            field += 8;
          }
          if (local == 0xFFFFFFFF) local = data.getUint64(field, Endian.little);
        }
        extra += 4 + fieldLength;
      }
      offset = extraEnd + commentLength;

      final target = _inside(root, name);
      final mode = madeBy >> 8 == 3 ? external >> 16 : 0;
      if (name.endsWith('/') || name.endsWith('\\')) {
        if (created.add(target)) {
          await Directory(target).create(recursive: true);
        }
        continue;
      }
      final header = ByteData.sublistView(await readAt(local, 30));
      if (header.getUint32(0, Endian.little) != 0x04034b50) {
        throw ArchiveException('Broken ZIP entry: $name');
      }
      final start =
          local +
          30 +
          header.getUint16(26, Endian.little) +
          header.getUint16(28, Endian.little);
      Stream<List<int>> raw() async* {
        var position = start;
        var left = compressed;
        while (left > 0) {
          final chunk = await readAt(position, math.min(left, 1 << 20));
          position += chunk.length;
          left -= chunk.length;
          yield chunk;
        }
      }

      final Stream<List<int>> content = switch (method) {
        0 => raw(),
        8 => raw().transform(ZLibDecoder(raw: true)),
        _ => throw ArchiveException(
          'Unsupported ZIP compression $method: $name',
        ),
      };
      if (mode & 0xF000 == 0xA000) {
        final target0 = await utf8.decodeStream(content);
        await _link(root, target, target0);
        continue;
      }
      final parent = p.dirname(target);
      if (created.add(parent)) await Directory(parent).create(recursive: true);
      final out = await File(target).open(mode: FileMode.write);
      try {
        var written = 0;
        await for (final chunk in content) {
          written += chunk.length;
          await out.writeFrom(chunk);
        }
        if (written != size) {
          throw ArchiveException('Broken ZIP entry (size): $name');
        }
      } finally {
        await out.close();
      }
      if (mode & 0x49 != 0) executables.add(target);
    }
    return executables;
  } finally {
    await raf.close();
  }
}
