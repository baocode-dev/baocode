import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../platform/data_dir.dart';

String? pastesDirectory() => DataDirectory.current.pastesDir;

String? savePaste(String text) {
  final hash = sha256.convert(utf8.encode(text)).toString();
  final file = File(
    p.join(DataDirectory.current.pastesDir, '${hash.substring(0, 20)}.txt'),
  );
  try {
    // Pasted again: the one kept.
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text, flush: true);
    }
    return file.path;
  } on FileSystemException {
    return null;
  }
}

Future<String?> readPaste(String path) async {
  for (final candidate in _candidates(path)) {
    try {
      return await File(candidate).readAsString();
    } on Object {
      // Not there.
    }
  }
  return null;
}

String? readPasteNow(String path) {
  for (final candidate in _candidates(path)) {
    try {
      return File(candidate).readAsStringSync();
    } on Object {
      // Not there.
    }
  }
  return null;
}

Set<String> _candidates(String path) => {
  path,
  p.join(DataDirectory.current.pastesDir, p.basename(path)),
};
