import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'file_service.dart';

class LocalIdeFileService implements IdeFileService {
  LocalIdeFileService(this.root);

  final String root;
  late final Future<String> _canonicalRoot = Directory(root)
      .resolveSymbolicLinks();
  final Map<String, _FileSnapshot> _snapshots = {};
  Future<void> _operations = Future<void>.value();

  static const _maximumFileBytes = 5 * 1024 * 1024;
  static const _hiddenDirectories = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'node_modules',
  };

  // Reads and writes share a queue so an old read cannot replace a newer save's
  // baseline. Failed operations must not poison the queue.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<String> _inside(String path) async {
    final base = p.normalize(await _canonicalRoot);
    final target = p.normalize(await File(path).resolveSymbolicLinks());
    if (target != base && !p.isWithin(base, target)) {
      throw FileSystemException('File is outside the project', path);
    }
    return target;
  }

  Future<String> _fileInside(String path) async {
    final target = await _inside(path);
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('Only regular files can be edited', path);
    }
    return target;
  }

  @override
  Future<List<IdeFile>> list(String directory) async {
    final resolved = await _inside(directory);
    final entries = await Directory(resolved).list(followLinks: false).toList();
    final files = <IdeFile>[
      for (final entry in entries)
        if (entry is Directory || entry is File)
          if (entry is! Directory ||
              !_hiddenDirectories.contains(p.basename(entry.path)))
            IdeFile(
              entry.path,
              p.basename(entry.path),
              isDirectory: entry is Directory,
            ),
    ];
    files.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  @override
  Future<String> read(String path) => _serialize(() async {
    final resolved = await _fileInside(path);
    final handle = await File(resolved).open();
    late Uint8List bytes;
    try {
      _checkSize(await handle.length());
      // Bound the read itself, not just the earlier stat: files may grow.
      bytes = await handle.read(_maximumFileBytes + 1);
      _checkSize(bytes.length);
      _checkSize(await handle.length());
      if (await _fileInside(path) != resolved) {
        throw IdeFileConflictException(path);
      }
    } finally {
      await handle.close();
    }
    final text = _decode(bytes);
    _snapshots[_key(path)] = _FileSnapshot(
      resolved,
      bytes,
      text,
      RegExp(r'\r\n|\n|\r').firstMatch(text)?.group(0) ?? '\n',
      bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf,
    );
    return text;
  });

  @override
  Future<void> write(String path, String text, {String? expectedText}) =>
      _serialize(() async {
        final snapshot = _snapshots[_key(path)];
        if (snapshot == null) {
          throw StateError('Read the file before saving it: $path');
        }
        final resolved = await _fileInside(path);
        if (snapshot.path != resolved ||
            (expectedText != null && _lf(expectedText) != _lf(snapshot.text))) {
          throw IdeFileConflictException(path);
        }
        // A no-op preserves even mixed line endings byte for byte. Otherwise,
        // retain the original BOM and newline convention, regardless of the
        // line endings emitted by the editor.
        final bytes = _lf(text) == _lf(snapshot.text)
            ? snapshot.bytes
            : Uint8List.fromList([
                if (snapshot.hasBom) ...[0xef, 0xbb, 0xbf],
                ...utf8.encode(_lf(text).replaceAll('\n', snapshot.lineEnding)),
              ]);
        _checkSize(bytes.length);
        _decode(bytes);

        // Compare the complete file before opening it for writing. Opening in
        // FileMode.write would truncate before a conflict could be detected;
        // writeOnly keeps the existing bytes until the comparison is done.
        final current = await File(resolved).readAsBytes();
        if (await _fileInside(path) != resolved ||
            !_sameBytes(current, snapshot.bytes)) {
          throw IdeFileConflictException(path);
        }
        final handle = await File(resolved).open(mode: FileMode.writeOnly);
        var locked = false;
        try {
          await handle.lock(FileLock.blockingExclusive);
          locked = true;
          await handle.setPosition(0);
          await handle.writeFrom(bytes);
          await handle.truncate(bytes.length);
          await handle.flush();
          _snapshots[_key(path)] = _FileSnapshot(
            resolved,
            bytes,
            text,
            snapshot.lineEnding,
            snapshot.hasBom,
          );
        } finally {
          try {
            if (locked) await handle.unlock();
          } finally {
            await handle.close();
          }
        }
      });

  static String _key(String path) => p.normalize(p.absolute(path));

  static String _lf(String text) => text.replaceAll(RegExp(r'\r\n?'), '\n');

  static void _checkSize(int length) {
    if (length > _maximumFileBytes) {
      throw const FormatException('Files over 5 MB cannot be edited');
    }
  }

  static String _decode(List<int> bytes) {
    if (bytes.any(
      (byte) =>
          (byte < 32 && byte != 9 && byte != 10 && byte != 12 && byte != 13) ||
          byte == 127,
    )) {
      throw const FormatException('Binary files cannot be edited');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FileSnapshot {
  const _FileSnapshot(
    this.path,
    this.bytes,
    this.text,
    this.lineEnding,
    this.hasBom,
  );

  final String path;
  final Uint8List bytes;
  final String text;
  final String lineEnding;
  final bool hasBom;
}
