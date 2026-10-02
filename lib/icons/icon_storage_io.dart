import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import 'icon_storage.dart';

/// [DataDirectory.iconsDir], or [path].
class DirectoryIconStorage implements IconStorage {
  DirectoryIconStorage([this.path]);

  final String? path;

  String get _dir => path ?? DataDirectory.current.iconsDir;

  File _file(String name) => File(p.join(_dir, p.basename(name)));

  /// One after another: the last written is the last made.
  Future<void> _writing = Future.value();

  @override
  Future<List<Object?>> readIndex() async {
    try {
      final decoded = jsonDecode(await _file('index.json').readAsString());
      return decoded is List ? decoded : const [];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> writeIndex(List<Object?> index) {
    final text = const JsonEncoder.withIndent('  ').convert(index);
    return _writing = _writing.then((_) async {
      try {
        await Directory(_dir).create(recursive: true);
        await writeFileAtomically(_file('index.json'), text);
      } on Object {
        // Not kept this time; the next change writes it again.
      }
    });
  }

  @override
  Future<Uint8List?> read(String name) async {
    try {
      return await _file(name).readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    await Directory(_dir).create(recursive: true);
    final file = _file(name);
    final partial = File('${file.path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  }

  @override
  Future<void> delete(String name) async {
    try {
      await _file(name).delete();
    } on Object {
      // Gone already.
    }
  }

  @override
  Future<int?> userFileSize(String path) async {
    try {
      return await File(path).length();
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint8List?> readUserFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } on Object {
      return null;
    }
  }
}
