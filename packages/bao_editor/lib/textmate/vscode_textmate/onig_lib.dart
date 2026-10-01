// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/onigLib.ts (MIT, see LICENSE.md).

/// The regular expressions a grammar runs on: Oniguruma, as
/// vscode-oniguruma exposes it.
abstract interface class IOnigLib {
  OnigScanner createOnigScanner(List<String> sources);
  OnigString createOnigString(String str);
}

class IOnigCaptureIndex {
  const IOnigCaptureIndex(this.start, this.end, this.length);

  /// UTF-16 offsets into [OnigString.content].
  final int start;
  final int end;
  final int length;
}

class IOnigMatch {
  const IOnigMatch(this.index, this.captureIndices);

  /// Which of the scanner's sources matched.
  final int index;
  final List<IOnigCaptureIndex> captureIndices;
}

/// `FindOption`: bit flags for [OnigScanner.findNextMatchSync].
abstract final class FindOption {
  static const none = 0;
  static const notBeginString = 1;
  static const notEndString = 2;
  static const notBeginPosition = 4;
  static const debugCall = 8;
}

abstract interface class OnigScanner {
  /// The earliest match of any source at or after [startPosition] (a UTF-16
  /// offset); on a tie, the lowest source index.
  IOnigMatch? findNextMatchSync(
    OnigString string,
    int startPosition,
    int options,
  );

  void dispose();
}

abstract interface class OnigString {
  String get content;

  void dispose();
}

void disposeOnigString(OnigString str) => str.dispose();
