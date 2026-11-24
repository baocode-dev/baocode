import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Whether [bytes] begin as a PDF does (`%PDF-`, perhaps after a little
/// junk, as readers allow).
bool looksLikePdf(Uint8List bytes) {
  final head = latin1.decode(
    bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes,
  );
  return head.contains('%PDF-');
}

/// How many pages the PDF [bytes] (at [path]) has: from its page tree (in
/// object streams too), else from `pdfinfo` where it is installed; null
/// when neither can tell.
int? pdfPageCount(Uint8List bytes, {String? path}) {
  final text = latin1.decode(bytes);
  final counts = <int>[..._treeCounts(text)];
  if (counts.isEmpty) {
    for (final stream in _objectStreams(text)) {
      counts.addAll(_treeCounts(stream));
    }
  }
  if (counts.isNotEmpty) {
    // The root holds them all: the largest of the page tree's counts.
    return counts.reduce((a, b) => a > b ? a : b);
  }
  if (path == null) return null;
  try {
    final result = Process.runSync('pdfinfo', [path]);
    if (result.exitCode != 0) return null;
    final match = RegExp(
      r'^Pages:\s+(\d+)',
      multiLine: true,
    ).firstMatch('${result.stdout}');
    return match == null ? null : int.parse(match[1]!);
  } on ProcessException {
    return null;
  }
}

final _pagesNode = RegExp(r'/Type\s*/Pages\b');
final _count = RegExp(r'/Count\s+(\d+)');

/// The `/Count` of every `/Type /Pages` dictionary in [text].
Iterable<int> _treeCounts(String text) sync* {
  for (final node in _pagesNode.allMatches(text)) {
    final open = text.lastIndexOf('<<', node.start);
    if (open < 0) continue;
    final close = _dictionaryEnd(text, open);
    if (close < 0) continue;
    final match = _count.firstMatch(text.substring(open, close));
    if (match != null) yield int.parse(match[1]!);
  }
}

/// Where the dictionary opened at [open] ends, nested ones within it.
int _dictionaryEnd(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length - 1 && i < open + 65536; i++) {
    if (text.startsWith('<<', i)) {
      depth++;
      i++;
    } else if (text.startsWith('>>', i)) {
      depth--;
      i++;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

final _objStm = RegExp(r'/Type\s*/ObjStm\b');

/// The inflated content of [text]'s compressed object streams, where a
/// page tree may be kept.
Iterable<String> _objectStreams(String text) sync* {
  for (final match in _objStm.allMatches(text)) {
    final open = text.lastIndexOf('<<', match.start);
    if (open < 0) continue;
    final close = _dictionaryEnd(text, open);
    if (close < 0) continue;
    if (!text.substring(open, close).contains('/FlateDecode')) continue;
    var start = text.indexOf('stream', close);
    if (start < 0 || start - close > 32) continue;
    start += 'stream'.length;
    if (text.startsWith('\r\n', start)) {
      start += 2;
    } else if (text.startsWith('\n', start)) {
      start += 1;
    }
    final end = text.indexOf('endstream', start);
    if (end < 0) continue;
    try {
      yield latin1.decode(
        ZLibDecoder().convert(latin1.encode(text.substring(start, end))),
      );
    } on FormatException {
      // Not one to read.
    } on Object {
      // Damaged: skipped.
    }
  }
}
