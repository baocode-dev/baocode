import 'package:flutter/material.dart';

import '../../theme/codicons.dart';
import '../editor/monaco/flutter/document_snapshot.dart';
import '../editor/monaco/flutter/editor_decorations.dart';
import '../editor/monaco/vs/editor/common/core/range.dart';
import '../editor/monaco/vs/editor/contrib/gotoError/browser/marker_navigation.dart';
import '../lsp/lsp_protocol.dart';
import 'lsp_convert.dart';

/// `problemsErrorIcon.foreground` and friends (Dark Modern).
abstract final class IdeDiagnosticColors {
  static const error = Color(0xFFF14C4C);
  static const warning = Color(0xFFCCA700);
  static const info = Color(0xFF3794FF);
  static const hint = Color(0xFF8C8C8C);
}

IconData ideDiagnosticIcon(LspDiagnosticSeverity severity) =>
    switch (severity) {
      LspDiagnosticSeverity.error => Codicons.error,
      LspDiagnosticSeverity.warning => Codicons.warning,
      LspDiagnosticSeverity.information => Codicons.info,
      LspDiagnosticSeverity.hint => Codicons.lightBulb,
    };

Color ideDiagnosticColor(LspDiagnosticSeverity severity) => switch (severity) {
  LspDiagnosticSeverity.error => IdeDiagnosticColors.error,
  LspDiagnosticSeverity.warning => IdeDiagnosticColors.warning,
  LspDiagnosticSeverity.information => IdeDiagnosticColors.info,
  LspDiagnosticSeverity.hint => IdeDiagnosticColors.hint,
};

int ideMarkerSeverity(LspDiagnosticSeverity severity) => switch (severity) {
  LspDiagnosticSeverity.error => MarkerSeverity.error,
  LspDiagnosticSeverity.warning => MarkerSeverity.warning,
  LspDiagnosticSeverity.information => MarkerSeverity.info,
  LspDiagnosticSeverity.hint => MarkerSeverity.hint,
};

/// `(start, end)` offsets a diagnostic marks: an empty range grows to the
/// word at its start, else to the next (or previous) character, as Monaco's
/// marker decorations do.
(int, int) ideDiagnosticOffsets(DocumentSnapshot snapshot, LspRange range) {
  var (start, end) = lspOffsetsOf(snapshot, range);
  if (start != end) return (start, end);
  final line = snapshot.positionAtOffset(start).lineNumber - 1;
  final lineStart = snapshot.lineStarts[line];
  final lineEnd = snapshot.contentEnds[line];
  final text = snapshot.text;
  bool isWord(int i) {
    final c = text.codeUnitAt(i);
    return c == 0x5F ||
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        c > 0x7F;
  }

  if (start < lineEnd && isWord(start)) {
    var a = start;
    var b = start;
    while (a > lineStart && isWord(a - 1)) {
      a--;
    }
    while (b < lineEnd && isWord(b)) {
      b++;
    }
    return (a, b);
  }
  if (start < lineEnd) return (start, start + 1);
  if (start > lineStart) return (start - 1, start);
  return (start, end);
}

/// Squiggles (and the unnecessary-code fade) for [diagnostics] over
/// [snapshot], most severe painted last.
List<EditorDecoration> ideDiagnosticDecorations(
  DocumentSnapshot snapshot,
  List<LspDiagnostic> diagnostics, {
  Color fadeColor = const Color(0x94141414),
}) {
  final sorted = List.of(diagnostics)
    ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return [
    for (final d in sorted)
      ...() {
        final (start, end) = ideDiagnosticOffsets(snapshot, d.range);
        if (start == end) return const <EditorDecoration>[];
        return [
          if (d.unnecessary)
            EditorDecoration(start: start, end: end, overlayColor: fadeColor),
          if (d.deprecated)
            EditorDecoration(
              start: start,
              end: end,
              underlineColor: const Color(0xFFCCCCCC),
              underlineStyle: EditorUnderlineStyle.solid,
            ),
          // Unnecessary/deprecated hints show only through their style.
          if (!((d.unnecessary || d.deprecated) &&
              d.severity == LspDiagnosticSeverity.hint))
            EditorDecoration(
              start: start,
              end: end,
              kind: switch (d.severity) {
                LspDiagnosticSeverity.error => EditorDecorationKind.error,
                LspDiagnosticSeverity.warning => EditorDecorationKind.warning,
                LspDiagnosticSeverity.information => EditorDecorationKind.info,
                LspDiagnosticSeverity.hint => EditorDecorationKind.hint,
              },
            ),
        ];
      }(),
  ];
}

typedef IdeDiagnosticCounts = ({int errors, int warnings, int infos});

IdeDiagnosticCounts ideDiagnosticCounts(Map<String, List<LspDiagnostic>> all) {
  var errors = 0;
  var warnings = 0;
  var infos = 0;
  for (final list in all.values) {
    for (final d in list) {
      switch (d.severity) {
        case LspDiagnosticSeverity.error:
          errors++;
        case LspDiagnosticSeverity.warning:
          warnings++;
        case LspDiagnosticSeverity.information:
          infos++;
        case LspDiagnosticSeverity.hint:
          break;
      }
    }
  }
  return (errors: errors, warnings: warnings, infos: infos);
}

/// Every problem (hints excluded) in navigation order, for F8.
MarkerList<LspDiagnostic> ideMarkerList(Map<String, List<LspDiagnostic>> all) =>
    MarkerList([
      for (final MapEntry(key: path, value: list) in all.entries)
        for (final d in list)
          NavigationMarker(
            path,
            Range(
              d.range.start.line + 1,
              d.range.start.character + 1,
              d.range.end.line + 1,
              d.range.end.character + 1,
            ),
            ideMarkerSeverity(d.severity),
            d,
          ),
    ]);

/// Diagnostics of [all] that touch the protocol [position]'s line span.
List<LspDiagnostic> ideDiagnosticsAt(
  List<LspDiagnostic> all,
  LspPosition position,
) => [
  for (final d in all)
    if (d.range.contains(position)) d,
];
