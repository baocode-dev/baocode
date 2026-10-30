import 'package:flutter/foundation.dart';

/// Where an editor's view of a document was left: Monaco's
/// `ICodeEditorViewState` (the scroll as the line at the top and how far
/// into it, so it still holds when lines above wrap or change height) with
/// the folding contribution's collapsed regions. A surface given a
/// controller with one ([EditorSurfaceController.viewState]) shows it so.
@immutable
class EditorViewState {
  const EditorViewState({
    required this.firstLine,
    this.firstLineOffset = 0,
    this.scrollLeft = 0,
    this.folds = const [],
  });

  /// The one-based model line at the top (upstream `firstPosition`).
  final int firstLine;

  /// How far the view is scrolled past [firstLine]'s top (upstream
  /// `firstPositionDeltaTop`, negated).
  final double firstLineOffset;

  final double scrollLeft;

  /// The collapsed regions (upstream `CollapseMemento`).
  final List<EditorFoldState> folds;

  Map<String, Object?> toJson() => {
    'line': firstLine,
    if (firstLineOffset != 0) 'offset': firstLineOffset,
    if (scrollLeft != 0) 'left': scrollLeft,
    if (folds.isNotEmpty) 'folds': [for (final fold in folds) fold.toJson()],
  };

  /// One [toJson] made; null for anything else.
  static EditorViewState? fromJson(Object? json) {
    if (json is! Map) return null;
    final line = json['line'];
    if (line is! int || line < 1) return null;
    double finite(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : 0;
    return EditorViewState(
      firstLine: line,
      firstLineOffset: finite(json['offset']),
      scrollLeft: finite(json['left']).clamp(0, double.infinity),
      folds: [
        if (json['folds'] case final List<Object?> folds)
          for (final fold in folds) ?EditorFoldState.fromJson(fold),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorViewState &&
      other.firstLine == firstLine &&
      other.firstLineOffset == firstLineOffset &&
      other.scrollLeft == scrollLeft &&
      listEquals(other.folds, folds);

  @override
  int get hashCode => Object.hash(
    firstLine,
    firstLineOffset,
    scrollLeft,
    Object.hashAll(folds),
  );
}

/// A collapsed region of an [EditorViewState] (upstream `ILineMemento`):
/// given back only while the lines it hides are as they were ([checksum]).
@immutable
class EditorFoldState {
  const EditorFoldState(
    this.startLineNumber,
    this.endLineNumber, {
    this.checksum,
    this.userDefined = false,
  });

  final int startLineNumber;
  final int endLineNumber;

  /// Of the hidden lines' text ([foldChecksum]); null restores it whatever
  /// they say.
  final int? checksum;

  /// Whether it was folded from a selection (Fold Selection) rather than
  /// a region the language gives.
  final bool userDefined;

  Map<String, Object?> toJson() => {
    'start': startLineNumber,
    'end': endLineNumber,
    'checksum': ?checksum,
    if (userDefined) 'user': true,
  };

  static EditorFoldState? fromJson(Object? json) {
    if (json is! Map) return null;
    final (start, end) = (json['start'], json['end']);
    if (start is! int || end is! int || start < 1 || end <= start) return null;
    return EditorFoldState(
      start,
      end,
      checksum: json['checksum'] is int ? json['checksum'] as int : null,
      userDefined: json['user'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorFoldState &&
      other.startLineNumber == startLineNumber &&
      other.endLineNumber == endLineNumber &&
      other.checksum == checksum &&
      other.userDefined == userDefined;

  @override
  int get hashCode =>
      Object.hash(startLineNumber, endLineNumber, checksum, userDefined);
}

/// A hash of [text] the same in every run (FNV-1a over its UTF-16 code
/// units, 32 bits): upstream's `_getLinesChecksum` of the lines a fold
/// hides.
int foldChecksum(String text) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < text.length; i++) {
    hash ^= text.codeUnitAt(i);
    // Times the prime 2^24 + 0x193, in parts the web's doubles hold.
    hash = (((hash << 24) & 0xffffffff) + hash * 0x193) & 0xffffffff;
  }
  return hash;
}
