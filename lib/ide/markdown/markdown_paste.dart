/// What a paste in a markdown document does (see [MarkdownPaste]).
sealed class MarkdownPasteOutcome {
  const MarkdownPasteOutcome();
}

/// The clipboard holds text: pasted as usual.
class MarkdownPasteText extends MarkdownPasteOutcome {
  const MarkdownPasteText();
}

/// Files were put beside the document (or are the project's already):
/// [text] links to them, to insert where the paste goes.
class MarkdownPasteLinks extends MarkdownPasteOutcome {
  const MarkdownPasteLinks(this.text);

  final String text;
}

/// Nothing to insert: the paste failed (and said why) or was called off.
class MarkdownPasteNothing extends MarkdownPasteOutcome {
  const MarkdownPasteNothing();
}
