import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'claude_history_page.dart';

export 'claude_history_page.dart' show IndexedTurnHit;

/// Persistent, incrementally-updated line & turn index for a single Claude
/// Code `.jsonl` session file.
///
/// Built in 4 MiB chunks from byte offset [scanned] onwards whenever the
/// file grows (append-only, verified by the 32-byte [mark] before [scanned]),
/// and persisted as a compact gzipped sidecar file so both page reads
/// (`ClaudeSessions.readPage`) and search (cross-conversation & in-chat ⌘F)
/// skip re-scanning multi-hundred-MB `.jsonl` files across restarts and edits.
class SessionIndex {
  SessionIndex({
    required this.path,
    this.size = 0,
    this.modified = 0,
    this.scanned = 0,
    Uint8List? mark,
    List<int>? starts,
    List<int>? ends,
    List<int>? kinds,
    List<String?>? ids,
    List<String?>? parents,
    Map<int, String>? texts,
  }) : mark = mark ?? Uint8List(0),
       starts = starts ?? <int>[],
       ends = ends ?? <int>[],
       kinds = kinds ?? <int>[],
       ids = ids ?? <String?>[],
       parents = parents ?? <String?>[],
       texts = texts ?? <int, String>{};

  static const int formatVersion = 1;
  static const int _markLength = 32;
  static const int _chunkBytes = 4 << 20;

  /// Bit flags stored in [kinds].
  static const int flagKept = 1;
  static const int flagSidechain = 2;
  static const int flagGoal = 4;
  static const int flagPrompt = 8;

  final String path;
  int size;
  int modified;
  int scanned;
  Uint8List mark;

  final List<int> starts;
  final List<int> ends;
  final List<int> kinds;
  final List<String?> ids;
  final List<String?> parents;

  /// Sparse searchable text (user prompts + assistant text blocks only,
  /// excluding tool I/O, thinking, and CLI wrappers), keyed by row index.
  final Map<int, String> texts;

  static final _json = utf8.decoder.fuse(json.decoder);

  /// Updates [kept] (or builds anew when null / rewritten) from [file] up to
  /// its current end. Returns `true` if any bytes were scanned (so the caller
  /// knows whether to persist the updated index).
  static (SessionIndex index, bool changed) readOn(
    File file,
    SessionIndex? kept, {
    int? fileSize,
    int? fileModified,
  }) {
    final stat = fileSize != null && fileModified != null
        ? null
        : file.statSync();
    final size = fileSize ?? stat!.size;
    final modified = fileModified ?? stat!.modified.microsecondsSinceEpoch;
    if (kept != null &&
        kept.size == size &&
        kept.modified == modified &&
        kept.scanned <= size) {
      return (kept, false);
    }

    final raf = file.openSync();
    try {
      final length = raf.lengthSync();
      SessionIndex? target = kept;
      if (target != null) {
        final from = target.scanned - target.mark.length;
        if (from < 0 || length < target.scanned) {
          target = null;
        } else if (target.mark.isNotEmpty) {
          raf.setPositionSync(from);
          final actual = raf.readSync(target.mark.length);
          if (actual.length != target.mark.length) {
            target = null;
          } else {
            final mark = target.mark;
            for (var i = 0; i < mark.length; i++) {
              if (actual[i] != mark[i]) {
                target = null;
                break;
              }
            }
          }
        }
      }

      final index = target ?? SessionIndex(path: file.path);
      if (length == index.scanned) {
        index
          ..size = size
          ..modified = modified;
        return (index, target == null);
      }

      var offset = index.scanned;
      raf.setPositionSync(offset);
      final tail = BytesBuilder(copy: false);
      var lineStart = offset;
      var done = offset;

      while (offset < length) {
        final toRead = math.min(_chunkBytes, length - offset);
        final chunk = raf.readSync(toRead);
        if (chunk.isEmpty) break;
        var pos = 0;
        while (pos < chunk.length) {
          final nl = chunk.indexOf(0x0a, pos);
          if (nl < 0) {
            tail.add(Uint8List.sublistView(chunk, pos));
            break;
          }
          final int lineEnd = offset + nl;
          if (tail.isEmpty) {
            _indexLine(
              index,
              Uint8List.sublistView(chunk, pos, nl),
              lineStart,
              lineEnd,
            );
          } else {
            tail.add(Uint8List.sublistView(chunk, pos, nl));
            _indexLine(index, tail.takeBytes(), lineStart, lineEnd);
          }
          pos = nl + 1;
          lineStart = done = offset + pos;
        }
        offset += chunk.length;
      }

      // Final line without trailing newline: include if valid complete JSON.
      if (tail.isNotEmpty) {
        final bytes = tail.takeBytes();
        if (_indexLine(index, bytes, lineStart, length)) {
          done = length;
        }
      }

      if (done > 0) {
        final markLen = math.min(_markLength, done);
        raf.setPositionSync(done - markLen);
        index.mark = raf.readSync(markLen);
      } else {
        index.mark = Uint8List(0);
      }
      index
        ..scanned = done
        ..size = size
        ..modified = modified;
      return (index, true);
    } finally {
      raf.closeSync();
    }
  }

  static bool _indexLine(
    SessionIndex index,
    Uint8List bytes,
    int start,
    int end,
  ) {
    if (end <= start) return true;
    final entry = decodeBytes(bytes);
    if (entry == null) return false;
    final row = index.starts.length;
    final parent = entry['parentUuid'] ?? entry['logicalParentUuid'];
    final kept = _isKept(entry);
    final sidechain = entry['isSidechain'] == true;
    final goal = kept && entry['type'] == 'attachment';
    final prompt = isPromptEntry(entry);
    index.starts.add(start);
    index.ends.add(end);
    index.ids.add(entry['uuid'] is String ? entry['uuid'] as String : null);
    index.parents.add(parent is String ? parent : null);
    index.kinds.add(
      (kept ? flagKept : 0) |
          (sidechain ? flagSidechain : 0) |
          (goal ? flagGoal : 0) |
          (prompt ? flagPrompt : 0),
    );
    final text = extractSearchableText(entry);
    if (text != null && text.isNotEmpty) {
      index.texts[row] = text;
    }
    return true;
  }

  /// Decodes a single JSONL line into a map, or null if malformed/not a map.
  static Map<String, Object?>? decodeBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      final entry = _json.convert(bytes);
      return entry is Map ? entry.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  /// Reads and decodes row [row] from [file].
  Map<String, Object?> entry(RandomAccessFile file, int row) {
    file.setPositionSync(starts[row]);
    final bytes = file.readSync(ends[row] - starts[row]);
    return decodeBytes(bytes) ?? const {};
  }

  /// The row indices along the active branch ending at the last kept message,
  /// oldest first.
  List<int> branch() {
    final byId = <String, int>{for (var i = 0; i < ids.length; i++) ?ids[i]: i};
    final rows = <int>[];
    final seen = <String>{};
    int? previousKept(int before) {
      for (var i = before - 1; i >= 0; i--) {
        if (kinds[i] & (flagKept | flagSidechain) == flagKept &&
            ids[i] != null &&
            !seen.contains(ids[i])) {
          return i;
        }
      }
      return null;
    }

    for (var row = previousKept(kinds.length); row != null;) {
      if (!seen.add(ids[row]!)) break;
      rows.add(row);
      row = switch (parents[row]) {
        final parent? => byId[parent] ?? previousKept(row),
        null => null,
      };
    }
    return [
      for (final row in rows.reversed)
        if (kinds[row] & flagKept != 0) row,
    ];
  }

  /// All rows that contribute searchable text, oldest first: the active
  /// branch when UUIDs are present, otherwise all kept non-sidechain rows
  /// (e.g. minimal synthetic JSONL files without UUIDs).
  List<int> _searchableRows() {
    final active = branch();
    if (active.isNotEmpty) return active;
    return [
      for (var i = 0; i < kinds.length; i++)
        if (kinds[i] & (flagKept | flagSidechain) == flagKept) i,
    ];
  }

  /// Combined searchable conversation text (what the user typed and Claude
  /// answered), for cross-conversation search.
  String searchableText() {
    if (texts.isEmpty) return '';
    final buffer = StringBuffer();
    for (final row in _searchableRows()) {
      if (texts[row] case final text?) {
        buffer.writeln(text);
      }
    }
    return buffer.toString();
  }

  /// Searches turns on the active branch strictly before [beforeId] (or all
  /// turns when [beforeId] is null) for [pattern]. Returns matching turns
  /// oldest first with their prompt UUID and total occurrence count.
  List<IndexedTurnHit> searchTurns(RegExp pattern, {String? beforeId}) {
    if (texts.isEmpty) return const [];
    final rows = branch();
    var end = rows.length;
    if (beforeId != null) {
      end = -1;
      for (var i = 0; i < rows.length; i++) {
        if (ids[rows[i]] == beforeId) {
          end = i;
          break;
        }
      }
      if (end <= 0) return const [];
    }

    final hits = <IndexedTurnHit>[];
    String? currentPrompt;
    var currentCount = 0;

    void flush() {
      if (currentPrompt != null && currentCount > 0) {
        hits.add(
          IndexedTurnHit(promptUuid: currentPrompt, occurrences: currentCount),
        );
      }
      currentCount = 0;
    }

    for (var i = 0; i < end; i++) {
      final row = rows[i];
      if (kinds[row] & flagPrompt != 0) {
        flush();
        currentPrompt = ids[row];
      }
      final text = texts[row];
      if (text == null || text.isEmpty) continue;
      final anchor = currentPrompt ?? ids[row];
      if (anchor == null) continue;
      currentPrompt ??= anchor;
      for (final match in pattern.allMatches(text)) {
        if (match.end > match.start) currentCount++;
      }
    }
    flush();
    return hits;
  }

  Map<String, Object?> toJson() => {
    'v': formatVersion,
    'path': path,
    'size': size,
    'modified': modified,
    'scanned': scanned,
    'mark': base64Encode(mark),
    'starts': starts,
    'ends': ends,
    'kinds': kinds,
    'ids': ids,
    'parents': parents,
    'texts': {for (final MapEntry(:key, :value) in texts.entries) '$key': value},
  };

  static SessionIndex? fromJson(Map<Object?, Object?> json) {
    if (json['v'] != formatVersion) return null;
    if (json case {
      'path': final String path,
      'size': final int size,
      'modified': final int modified,
      'scanned': final int scanned,
      'mark': final String mark,
      'starts': final List<Object?> starts,
      'ends': final List<Object?> ends,
      'kinds': final List<Object?> kinds,
      'ids': final List<Object?> ids,
      'parents': final List<Object?> parents,
      'texts': final Map<Object?, Object?> texts,
    }) {
      final n = starts.length;
      if (ends.length != n ||
          kinds.length != n ||
          ids.length != n ||
          parents.length != n) {
        return null;
      }
      try {
        return SessionIndex(
          path: path,
          size: size,
          modified: modified,
          scanned: scanned,
          mark: base64Decode(mark),
          starts: [for (final v in starts) v! as int],
          ends: [for (final v in ends) v! as int],
          kinds: [for (final v in kinds) v! as int],
          ids: [for (final v in ids) v as String?],
          parents: [for (final v in parents) v as String?],
          texts: {
            for (final MapEntry(:key, :value) in texts.entries)
              int.parse(key! as String): value! as String,
          },
        );
      } on Object {
        return null;
      }
    }
    return null;
  }

  /// Whether [entry] is kept on the conversation branch.
  static bool _isKept(Map<String, Object?> entry) => switch (entry['type']) {
    'user' || 'assistant' || 'system' => true,
    'attachment' => switch (entry['attachment']) {
      {'type': 'goal_status'} => true,
      _ => false,
    },
    _ => false,
  };

  /// Whether [entry] begins a user turn (matches `ClaudeSessions`'s `_isPrompt`).
  static bool isPromptEntry(Map<String, Object?> entry) =>
      entry['type'] == 'user' &&
      entry['isSidechain'] != true &&
      entry['isMeta'] != true &&
      entry['isCompactSummary'] != true &&
      entry['uuid'] is String &&
      _promptText(entry) != null;

  /// Searchable plain text of a user or assistant line (excluding tool I/O,
  /// thinking blocks, meta/sidechain rows, and CLI wrappers).
  static String? extractSearchableText(Map<String, Object?> entry) {
    if (entry['isSidechain'] == true || entry['isMeta'] == true) return null;
    final type = entry['type'];
    if (type != 'user' && type != 'assistant') return null;
    final message = entry['message'];
    if (message is! Map<Object?, Object?>) return null;
    final content = message['content'];
    final parts = switch (content) {
      final String text => [text],
      final List<Object?> blocks => [
        for (final block in blocks)
          if (block is Map<Object?, Object?> &&
              block['type'] == 'text' &&
              block['text'] is String)
            block['text']! as String,
      ],
      _ => const <String>[],
    };
    if (parts.isEmpty) return null;
    final out = <String>[];
    for (final part in parts) {
      var trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (type == 'user') {
        if (_imageName.hasMatch(trimmed)) continue;
        if (_unwrapAgentMessage(trimmed) case final body?) {
          trimmed = body;
          if (trimmed.isEmpty) continue;
        } else if (_isCommandWrapper(trimmed) || _isCliNote(trimmed)) {
          continue;
        }
      }
      out.add(trimmed);
    }
    return out.isEmpty ? null : out.join('\n');
  }

  static String? _promptText(Map<String, Object?> entry) {
    final message = entry['message'];
    if (message is! Map) return null;
    final content = message['content'];
    final blocks = content is List<Object?> ? content : const <Object?>[];
    final text = switch (content) {
      final String text => text,
      _ => [
        for (final block in blocks)
          if (block is Map && block['type'] == 'text')
            if (block['text'] as String? ?? '' case final text
                when !_imageName.hasMatch(text) &&
                    !text.trimLeft().startsWith('<system-reminder>'))
              text,
      ].join('\n'),
    };
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      final images = blocks.any((b) => b is Map && b['type'] == 'image');
      final noted = blocks.any(
        (b) =>
            b is Map &&
            b['type'] == 'text' &&
            (b['text'] as String? ?? '').trimLeft().startsWith(
              '<system-reminder>',
            ),
      );
      return images || noted ? '' : null;
    }
    if (_botEvent.firstMatch(trimmed) case final event?) {
      return event[1]!.trim();
    }
    if (_unwrapAgentMessage(trimmed) case final body?) {
      return body;
    }
    if (_isCommandWrapper(trimmed)) {
      final name = _commandName.firstMatch(trimmed)?[1]?.trim();
      final args = _commandArgs.firstMatch(trimmed)?[1]?.trim();
      if (name == null || args == null || args.isEmpty) return null;
      return '${name.startsWith('/') ? name : '/$name'} $args';
    }
    if (_isCliNote(trimmed)) return null;
    if (trimmed.startsWith('[Request interrupted')) return null;
    return trimmed;
  }

  static String? _unwrapAgentMessage(String trimmed) {
    if (!trimmed.startsWith('<agent-message')) return null;
    if (_agentMessage.firstMatch(trimmed) case final match?) {
      final body = match[1]!.trim();
      final tail = match[2]?.trim() ?? '';
      if (tail.isEmpty) return body;
      return body.isEmpty ? tail : '$body\n$tail';
    }
    if (_agentMessageOpen.firstMatch(trimmed) case final match?) {
      return match[1]!.trim();
    }
    return null;
  }

  static bool _isCommandWrapper(String trimmed) =>
      trimmed.startsWith('<command-name>') ||
      trimmed.startsWith('<command-message>') ||
      trimmed.startsWith('<command-args>');

  static bool _isCliNote(String trimmed) =>
      trimmed.startsWith('<local-command-') ||
      trimmed.startsWith('<system-reminder>') ||
      trimmed.startsWith('<task-notification>') ||
      trimmed.startsWith('<bash-input>') ||
      trimmed.startsWith('<bash-stdout>') ||
      trimmed.startsWith('<bash-stderr>') ||
      trimmed.startsWith('<ide_opened_file>') ||
      trimmed.startsWith('<ide_selection>');

  static final _imageName = RegExp(r'^\s*\[Image #\d+\]\s*$');
  static final _botEvent = RegExp(r'^<bao-event>([\s\S]*?)(?:</bao-event>|$)');
  static final _agentMessage = RegExp(
    r'^<agent-message\b[^>]*>([\s\S]*)</agent-message>(?:\s*([\s\S]*))?$',
  );
  static final _agentMessageOpen = RegExp(r'^<agent-message\b[^>]*>([\s\S]*)$');
  static final _commandName = RegExp(r'<command-name>([\s\S]*?)</command-name>');
  static final _commandArgs = RegExp(r'<command-args>([\s\S]*?)</command-args>');
}

/// Manages gzip-compressed [SessionIndex] sidecar files on disk under
/// [cacheDir] (when provided) so both paging and search share the same
/// incremental index across restarts.
class SessionIndexStore {
  const SessionIndexStore({this.cacheDir});

  /// Directory where `.idx.gz` files are stored; null disables disk I/O.
  final String? cacheDir;

  /// Cache file path for session file [sessionPath].
  String? indexFilePath(String sessionPath) {
    final dir = cacheDir;
    if (dir == null || dir.isEmpty) return null;
    final key = sha256.convert(utf8.encode(sessionPath)).toString().substring(
      0,
      24,
    );
    return p.join(dir, '$key.idx.gz');
  }

  /// Loads a persisted index from disk if present and valid; null otherwise.
  SessionIndex? loadDisk(String sessionPath) {
    final idxPath = indexFilePath(sessionPath);
    if (idxPath == null) return null;
    final file = File(idxPath);
    if (!file.existsSync()) return null;
    try {
      final raw = gzip.decode(file.readAsBytesSync());
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map) return null;
      final index = SessionIndex.fromJson(decoded);
      if (index == null || index.path != sessionPath) return null;
      return index;
    } on Object {
      return null;
    }
  }

  /// Atomically writes [index] as a gzipped sidecar file.
  void saveDisk(SessionIndex index) {
    final idxPath = indexFilePath(index.path);
    if (idxPath == null) return;
    try {
      final target = File(idxPath);
      target.parent.createSync(recursive: true);
      final encoded = gzip.encode(utf8.encode(jsonEncode(index.toJson())));
      final temp = File('$idxPath.$pid.tmp')
        ..writeAsBytesSync(encoded, flush: true);
      temp.renameSync(idxPath);
    } on Object {
      // Cache write failure must never break history reading or search.
    }
  }

  /// Opens [sessionPath] using [inMemory] if provided, else disk cache,
  /// updates it incrementally if the file changed, and persists if updated.
  SessionIndex openSync(
    String sessionPath, {
    SessionIndex? inMemory,
    int? fileSize,
    int? fileModified,
  }) {
    final file = File(sessionPath);
    final seed = inMemory ?? loadDisk(sessionPath);
    final (updated, changed) = SessionIndex.readOn(
      file,
      seed,
      fileSize: fileSize,
      fileModified: fileModified,
    );
    if (changed || (seed == null && cacheDir != null)) {
      saveDisk(updated);
    }
    return updated;
  }
}
