import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../lsp_server_definition.dart';
import 'install_io.dart';

/// Unpacks a downloaded file where it lies, as mason's `std.unpack` does:
/// `.zip`/`.vsix`, `.tar`, `.tar.gz`/`.tgz` and `.gz` in Dart; `.tar.xz`,
/// `.tar.bz2` and `.tar.zst` with the system `tar`. The archive is removed
/// afterwards; any other file is left as it is.
///
/// Returns the files the archive marks executable (Unix mode bits), which
/// the caller makes executable ([makeExecutable]).
Future<List<String>> unpackDownload(
  String file, {
  required CommandRunner runner,
}) async {
  final name = p.basename(file).toLowerCase();
  final directory = p.dirname(file);
  List<String> executables;
  if (name.endsWith('.zip') || name.endsWith('.vsix')) {
    executables = await extractZip(await File(file).readAsBytes(), directory);
  } else if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
    executables = await extractTar(
      gzip.decode(await File(file).readAsBytes()),
      directory,
    );
  } else if (name.endsWith('.tar')) {
    executables = await extractTar(await File(file).readAsBytes(), directory);
  } else if (name.endsWith('.tar.xz') ||
      name.endsWith('.txz') ||
      name.endsWith('.tar.bz2') ||
      name.endsWith('.tar.zst')) {
    final result = await runner.run('tar', [
      '-xf',
      file,
      '-C',
      directory,
    ], workingDirectory: directory);
    if (result.exitCode != 0) {
      throw LspInstallException(
        'Could not unpack ${p.basename(file)}',
        detail: result.stderr,
      );
    }
    executables = const [];
  } else if (name.endsWith('.gz')) {
    final target = file.substring(0, file.length - 3);
    await File(target)
        .writeAsBytes(gzip.decode(await File(file).readAsBytes()));
    executables = const [];
  } else {
    return const [];
  }
  await File(file).delete();
  return executables;
}

/// Sets the executable bits of [files] with `chmod`, in batches; nothing on
/// Windows.
Future<void> makeExecutable(
  List<String> files, {
  required CommandRunner runner,
  required bool windows,
}) async {
  if (windows || files.isEmpty) return;
  for (var start = 0; start < files.length; start += 200) {
    final batch = files.sublist(start, (start + 200).clamp(0, files.length));
    final result = await runner.run('chmod', ['+x', ...batch]);
    if (result.exitCode != 0) {
      throw LspInstallException(
        'Could not make files executable',
        detail: result.stderr,
      );
    }
  }
}

/// [entry] under [directory], refusing absolute paths and `..` escapes.
String _inside(String directory, String entry) {
  final normalized = entry.replaceAll('\\', '/');
  final target = p.normalize(p.join(directory, normalized));
  if (p.isAbsolute(normalized) ||
      normalized.startsWith('/') ||
      !(p.isWithin(directory, target) || p.equals(directory, target))) {
    throw LspInstallException('Archive entry escapes its folder: $entry');
  }
  return target;
}

Future<void> _link(String directory, String path, String target) async {
  final resolved = p.normalize(p.join(p.dirname(path), target));
  if (p.isAbsolute(target) || !p.isWithin(directory, resolved)) {
    throw LspInstallException('Archive link escapes its folder: $target');
  }
  await Directory(p.dirname(path)).create(recursive: true);
  final link = Link(path);
  if (await link.exists() || await File(path).exists()) {
    await File(path).delete();
  }
  await link.create(target);
}

/// Extracts a ZIP archive (stored or deflated entries, Zip64 included)
/// into [directory]; returns the files whose Unix mode is executable.
Future<List<String>> extractZip(Uint8List bytes, String directory) async {
  final data = ByteData.sublistView(bytes);
  var eocd = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const LspInstallException('Not a ZIP archive');
  var count = data.getUint16(eocd + 10, Endian.little);
  var offset = data.getUint32(eocd + 16, Endian.little);
  if ((count == 0xFFFF || offset == 0xFFFFFFFF) &&
      eocd >= 20 &&
      data.getUint32(eocd - 20, Endian.little) == 0x07064b50) {
    final zip64 = data.getUint64(eocd - 12, Endian.little);
    if (data.getUint32(zip64, Endian.little) != 0x06064b50) {
      throw const LspInstallException('Broken Zip64 archive');
    }
    count = data.getUint64(zip64 + 32, Endian.little);
    offset = data.getUint64(zip64 + 48, Endian.little);
  }
  final executables = <String>[];
  for (var i = 0; i < count; i++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) {
      throw const LspInstallException('Broken ZIP central directory');
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
    final nameBytes = bytes.sublist(offset + 46, offset + 46 + nameLength);
    final name = flags & 0x800 != 0
        ? utf8.decode(nameBytes, allowMalformed: true)
        : latin1.decode(nameBytes);
    // Zip64 sizes and offset, for the fields saturated above.
    var extra = offset + 46 + nameLength;
    final extraEnd = extra + extraLength;
    while (extra + 4 <= extraEnd) {
      final id = data.getUint16(extra, Endian.little);
      final length = data.getUint16(extra + 2, Endian.little);
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
      extra += 4 + length;
    }
    offset = extraEnd + commentLength;

    final target = _inside(directory, name);
    final mode = madeBy >> 8 == 3 ? external >> 16 : 0;
    if (name.endsWith('/')) {
      await Directory(target).create(recursive: true);
      continue;
    }
    if (data.getUint32(local, Endian.little) != 0x04034b50) {
      throw LspInstallException('Broken ZIP entry: $name');
    }
    final start =
        local +
        30 +
        data.getUint16(local + 26, Endian.little) +
        data.getUint16(local + 28, Endian.little);
    final raw = Uint8List.sublistView(bytes, start, start + compressed);
    final List<int> content = switch (method) {
      0 => raw,
      8 => ZLibDecoder(raw: true).convert(raw),
      _ => throw LspInstallException(
        'Unsupported ZIP compression $method: $name',
      ),
    };
    if (mode & 0xF000 == 0xA000) {
      await _link(directory, target, utf8.decode(content));
      continue;
    }
    await Directory(p.dirname(target)).create(recursive: true);
    await File(target).writeAsBytes(content);
    if (mode & 0x49 != 0) executables.add(target);
  }
  return executables;
}

/// Extracts a tar archive (ustar, GNU long names, pax paths) into
/// [directory]; returns the files whose mode is executable.
Future<List<String>> extractTar(List<int> input, String directory) async {
  final bytes = input is Uint8List ? input : Uint8List.fromList(input);
  String text(int start, int length) {
    var end = start;
    while (end < start + length && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
  }

  int octal(int start, int length) {
    if (bytes[start] & 0x80 != 0) {
      // Base-256 for sizes over 8 GiB.
      var value = bytes[start] & 0x7F;
      for (var i = start + 1; i < start + length; i++) {
        value = value << 8 | bytes[i];
      }
      return value;
    }
    final digits = text(start, length).trim();
    return digits.isEmpty ? 0 : int.parse(digits, radix: 8);
  }

  final executables = <String>[];
  final hardLinks = <(String, String)>[];
  String? longName;
  String? longLink;
  var offset = 0;
  while (offset + 512 <= bytes.length) {
    if (bytes.sublist(offset, offset + 512).every((b) => b == 0)) break;
    var name = text(offset, 100);
    final mode = octal(offset + 100, 8);
    final size = octal(offset + 124, 12);
    final type = String.fromCharCode(
      bytes[offset + 156] == 0 ? 0x30 : bytes[offset + 156],
    );
    var linkName = text(offset + 157, 100);
    if (text(offset + 257, 5) == 'ustar') {
      final prefix = text(offset + 345, 155);
      if (prefix.isNotEmpty) name = '$prefix/$name';
    }
    final dataStart = offset + 512;
    if (dataStart + size > bytes.length) {
      throw const LspInstallException('Truncated tar archive');
    }
    offset = dataStart + (size + 511) ~/ 512 * 512;
    switch (type) {
      case 'L':
        longName = text(dataStart, size);
        continue;
      case 'K':
        longLink = text(dataStart, size);
        continue;
      case 'x':
        final records = utf8.decode(
          bytes.sublist(dataStart, dataStart + size),
          allowMalformed: true,
        );
        for (final record in records.split('\n')) {
          final space = record.indexOf(' ');
          final equals = record.indexOf('=');
          if (space < 0 || equals < space) continue;
          final key = record.substring(space + 1, equals);
          final value = record.substring(equals + 1);
          if (key == 'path') longName = value;
          if (key == 'linkpath') longLink = value;
        }
        continue;
      case 'g':
        continue;
    }
    name = longName ?? name;
    linkName = longLink ?? linkName;
    longName = null;
    longLink = null;
    if (name.isEmpty || name == '.' || name == './') continue;
    final target = _inside(directory, name);
    switch (type) {
      case '5':
        await Directory(target).create(recursive: true);
      case '2':
        await _link(directory, target, linkName);
      case '1':
        hardLinks.add((target, _inside(directory, linkName)));
      case '0' || '7':
        await Directory(p.dirname(target)).create(recursive: true);
        await File(target).writeAsBytes(
          Uint8List.sublistView(bytes, dataStart, dataStart + size),
        );
        if (mode & 0x49 != 0) executables.add(target);
    }
  }
  for (final (path, source) in hardLinks) {
    await File(source).copy(path);
    if (executables.contains(source)) executables.add(path);
  }
  return executables;
}
