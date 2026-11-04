import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'usage_ledger.dart';
import 'usage_record.dart';
import 'usage_trace.dart';

/// The calls in [directory]: `<yyyy-MM-dd>.jsonl` a day, and `index.json`.
///
/// Appended to under the file's lock, as the turns' records are (see
/// TurnStatsFiles): another of the app's processes writing at once loses
/// no line. Read off the UI isolate.
class UsageFiles implements UsageStorage {
  UsageFiles(this.directory);

  final String directory;

  static final _dayFile = RegExp(r'^(\d{4}-\d{2}-\d{2})\.jsonl$');

  File _file(String day) => File(p.join(directory, '$day.jsonl'));
  File get _index => File(p.join(directory, 'index.json'));

  @override
  void append(String day, List<String> lines) {
    if (lines.isEmpty) return;
    final file = _file(day);
    try {
      file.parent.createSync(recursive: true);
      final open = file.openSync(mode: FileMode.append);
      try {
        open.lockSync(FileLock.blockingExclusive);
        open
          ..setPositionSync(open.lengthSync())
          ..writeStringSync('${lines.join('\n')}\n')
          ..flushSync();
      } finally {
        open.closeSync();
      }
    } on FileSystemException catch (error) {
      debugPrint('Usage not kept: $error');
    }
  }

  @override
  Future<List<UsageCall>> read(List<String> days) {
    final paths = [for (final day in days) _file(day).path];
    return Isolate.run(() => _readAll(paths));
  }

  static List<UsageCall> _readAll(List<String> paths) {
    final calls = <UsageCall>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        calls.addAll(
          decodeUsageLines(
            const LineSplitter().convert(
              utf8.decode(file.readAsBytesSync(), allowMalformed: true),
            ),
          ),
        );
      } on FileSystemException {
        continue;
      }
    }
    return calls;
  }

  @override
  Future<List<String>> days() async => (await sizes()).keys.toList()..sort();

  @override
  Future<Map<String, int>> sizes() async {
    final folder = Directory(directory);
    final sizes = <String, int>{};
    try {
      if (!await folder.exists()) return sizes;
      await for (final entry in folder.list()) {
        if (entry is! File) continue;
        final match = _dayFile.firstMatch(p.basename(entry.path));
        if (match == null) continue;
        sizes[match.group(1)!] = await entry.length();
      }
    } on FileSystemException {
      // What was read.
    }
    return sizes;
  }

  @override
  Future<void> delete(String day) async {
    try {
      await _file(day).delete();
    } on FileSystemException {
      // Gone already.
    }
  }

  @override
  Future<int> rewrite(String day, bool Function(UsageCall call) drop) async {
    final file = _file(day);
    if (!await file.exists()) return 0;
    final open = await file.open(mode: FileMode.append);
    try {
      await open.lock(FileLock.blockingExclusive);
      await open.setPosition(0);
      final bytes = await open.read(await open.length());
      final kept = StringBuffer();
      var dropped = 0, calls = 0;
      for (final line in const LineSplitter().convert(
        utf8.decode(bytes, allowMalformed: true),
      )) {
        final call = UsageCall.decode(line);
        if (call != null && drop(call)) {
          dropped++;
        } else if (line.isNotEmpty) {
          kept.writeln(line);
          if (call != null) calls++;
        }
      }
      if (dropped == 0) return 0;
      await open.truncate(0);
      await open.setPosition(0);
      // The shapes alone are nothing to keep.
      if (calls > 0) await open.writeString(kept.toString());
      await open.flush();
      return dropped;
    } finally {
      await open.close();
      if (await file.exists() && await file.length() == 0) {
        await file.delete().catchError((Object _) => file);
      }
    }
  }

  // --- Traces -------------------------------------------------------------

  Directory get _traces => Directory(p.join(directory, 'traces'));

  File _trace(String day, String id) =>
      File(p.join(_traces.path, day, '$id.json.gz'));

  static final _traceFile = RegExp(r'^([0-9a-z]+)\.json\.gz$');

  @override
  void writeTrace(String day, String id, Map<String, Object?> trace) {
    final path = _trace(day, id).path;
    // Encoded and squeezed off the UI isolate: a request's whole context
    // is megabytes.
    unawaited(
      Isolate.run(() {
        final file = File(path);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(trace))));
      }).catchError((Object error) => debugPrint('Trace not kept: $error')),
    );
  }

  @override
  Future<UsageTrace?> readTrace(String day, String id) {
    final path = _trace(day, id).path;
    return Isolate.run(() {
      final file = File(path);
      if (!file.existsSync()) return null;
      try {
        return UsageTrace.fromJson(
          jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync()))),
        );
      } on Object {
        return null;
      }
    });
  }

  @override
  Future<Map<String, ({int bytes, int count})>> traceSizes() async {
    final sizes = <String, ({int bytes, int count})>{};
    try {
      if (!await _traces.exists()) return sizes;
      await for (final folder in _traces.list()) {
        if (folder is! Directory) continue;
        final day = p.basename(folder.path);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) continue;
        var bytes = 0, count = 0;
        await for (final entry in folder.list()) {
          if (entry is! File || !_traceFile.hasMatch(p.basename(entry.path))) {
            continue;
          }
          bytes += await entry.length();
          count++;
        }
        sizes[day] = (bytes: bytes, count: count);
      }
    } on FileSystemException {
      // What was read.
    }
    return sizes;
  }

  @override
  Future<void> deleteTraces(String day, [Set<String>? ids]) async {
    try {
      if (ids == null) {
        final folder = Directory(p.join(_traces.path, day));
        if (await folder.exists()) await folder.delete(recursive: true);
        return;
      }
      for (final id in ids) {
        final file = _trace(day, id);
        if (await file.exists()) await file.delete();
      }
    } on FileSystemException {
      // Gone already.
    }
  }

  @override
  Future<Map<String, Object?>?> readIndex() async {
    try {
      final json = jsonDecode(await _index.readAsString());
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  @override
  void writeIndex(Map<String, Object?> index) {
    try {
      _index.parent.createSync(recursive: true);
      final temp = File('${_index.path}.tmp')
        ..writeAsStringSync(jsonEncode(index), flush: true);
      temp.renameSync(_index.path);
    } on FileSystemException catch (error) {
      debugPrint('Usage index not kept: $error');
    }
  }
}

UsageStorage usageStorageIn(String directory) => UsageFiles(directory);
