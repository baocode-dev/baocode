/// Monaco's `TextEditorCaretStyle` (`editor.cursorStyle`): how the caret is
/// drawn.
enum EditorCaretStyle {
  /// A vertical bar, Monaco's default.
  line,

  /// A box over the character after the caret, which shows in the caret's
  /// opposite color.
  block,

  /// A bar under the character after the caret.
  underline,

  /// A one pixel wide vertical bar.
  lineThin,

  /// An outlined box over the character after the caret.
  blockOutline,

  /// A one pixel high bar under the character after the caret.
  underlineThin;

  /// The style of the extension API's `TextEditorCaretStyle` [value]
  /// (one-based, `Line` first); null for an unknown value.
  static EditorCaretStyle? fromApi(int value) =>
      value >= 1 && value <= values.length ? values[value - 1] : null;

  /// Whether the caret covers the character after it (upstream's block and
  /// underline styles), as opposed to a bar before it.
  bool get coversCharacter => this != line && this != lineThin;
}

/// Monaco's `RenderLineNumbersType` (`editor.lineNumbers`, without a
/// custom function).
enum EditorLineNumbersStyle {
  off,
  on,

  /// The caret's line absolute (at the left), every other its distance.
  relative,

  /// Every tenth line, the caret's and the last.
  interval;

  /// The style of the extension API's `TextEditorLineNumbersStyle` [value]
  /// (`Off` 0, `On` 1, `Relative` 2, `Interval` 3); null for an unknown
  /// value.
  static EditorLineNumbersStyle? fromApi(int value) =>
      value >= 0 && value < values.length ? values[value] : null;
}
