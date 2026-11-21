import 'dart:io';

import 'package:path/path.dart' as p;

import '../proxy/translate/antigravity_signature.dart';

/// Gemini's thought signatures a tool call's id refers to, one file each in
/// [directory], named by its key: kept across restarts, as the
/// conversations whose calls carry them are. One not read for
/// [keepFor] is removed; its call then goes back as history Gemini did not
/// sign, which it takes.
class FileSignatureStore implements SignatureStore {
  FileSignatureStore(this.directory);

  final String Function() directory;

  static const keepFor = Duration(days: 90);

  final Map<String, String> _memory = {};
  DateTime? _prunedAt;

  @override
  String? keep(String signature) {
    final key = signatureKey(signature);
    if (_memory[key] == signature) return key;
    _memory[key] = signature;
    try {
      final dir = Directory(directory());
      final file = File(p.join(dir.path, key));
      if (!file.existsSync()) {
        dir.createSync(recursive: true);
        final temp = File(p.join(dir.path, '.tmp-$key-$pid'));
        temp.writeAsStringSync(signature, flush: true);
        temp.renameSync(file.path);
      }
      _prune(dir);
    } on FileSystemException {
      // Kept in memory alone, while the app runs.
    }
    return key;
  }

  @override
  String? kept(String key) {
    if (_memory[key] case final signature?) return signature;
    if (!RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(key)) return null;
    try {
      final file = File(p.join(directory(), key));
      final signature = file.readAsStringSync();
      if (signature.isEmpty || signatureKey(signature) != key) return null;
      file.setLastModifiedSync(DateTime.now());
      return _memory[key] = signature;
    } on FileSystemException {
      return null;
    }
  }

  /// Removes, at most hourly, the signatures not read for [keepFor].
  void _prune(Directory dir) {
    final now = DateTime.now();
    final at = _prunedAt;
    if (at != null && now.difference(at) < const Duration(hours: 1)) return;
    _prunedAt = now;
    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        if (now.difference(entry.lastModifiedSync()) > keepFor) {
          entry.deleteSync();
        }
      }
    } on FileSystemException {
      // Next time.
    }
  }
}
