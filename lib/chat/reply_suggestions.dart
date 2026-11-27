/// What the agent suggests the user send next, written by itself at the
/// end of its reply, each as `[$buttonTag:…]` (or legacy `<$tag>…</$tag>`):
/// no request of its own. Shown over the composer, apart from what it said
/// (see [AssistantTextItem.text]), while the user has them on
/// (`chat.promptSuggestions`, [PromptSuggestions]).
abstract final class ReplySuggestions {
  /// Legacy XML tag, still parsed for earlier conversations and models.
  static const tag = 'reply_suggestion';

  /// Current button marker name: `[next-button:…]`.
  static const buttonTag = 'next-button';

  /// The most shown.
  static const max = 4;

  /// The longest shown, in characters: a line to send, not a message.
  static const maxLength = 80;

  /// What the agent is told, with the user's message, when they turn them
  /// on (or with the first message, on).
  ///
  /// Uses plain `[next-button:…]` tokens on a clean final line rather than
  /// XML tags, which many models turned into tool calls or varied markup
  /// (#1276).
  static const on =
      '<system-reminder>Reply suggestions are on: the user turned them on '
      'in BaoCode. When you finish your turn and hand back to them, end your '
      'last message with two to four things they might send you next: in '
      'their voice and their language, short (about 20 Chinese characters, '
      'or 10 words, at most), different ways on (go ahead, change course, '
      'ask); some may go well together. They pick what to send, edit it and '
      'send it. The app shows them apart from your message: do not speak of '
      'them. None while you are still working.\n'
      '\n'
      'Write them as plain text on the very last line, not as a tool call: '
      'space-separated as [$buttonTag:…], with nothing else at the start or '
      'end of the line and nothing after the last one.\n'
      '\n'
      'Right (no other characters at the start or end of the line):\n'
      '[$buttonTag:Run the tests first] '
      '[$buttonTag:Why did the filter not apply?]\n'
      '\n'
      'Wrong:\n'
      '- [$buttonTag:Run the tests first] [$buttonTag:Commit it] '
      '(no list marker, number, or text before the first one)\n'
      'Next: [$buttonTag:Run the tests first] '
      '(nothing else on the line)\n'
      '- a code block or tool call around them\n'
      '- [$buttonTag:Want me to run the tests?] '
      '(your voice: write what the user would say)\n'
      '- more text after them</system-reminder>';

  /// With each message after, a word.
  static const stillOn =
      '<system-reminder>Reply suggestions still on: end your turn with two '
      'to four short ones as plain text on the very last line (nothing else '
      'on the line): [$buttonTag:…] [$buttonTag:…].</system-reminder>';

  /// Once, when they turn them off.
  static const off =
      '<system-reminder>Reply suggestions are off: the user turned them off '
      'in BaoCode. Write no more [$buttonTag:…].</system-reminder>';

  /// What to tell the agent with a message, suggestions [wanted] or not:
  /// [told], what it was last told this run (none yet); [suggested],
  /// whether its last reply has suggestions (told before this run).
  static List<String> notes({
    required bool wanted,
    required bool? told,
    required bool suggested,
  }) => switch ((wanted, told)) {
    (true, true) => const [stillOn],
    (true, _) => const [on],
    (false, true) => const [off],
    (false, null) when suggested => const [off],
    _ => const [],
  };

  /// [text] without the suggestions at its end, and without one still
  /// being written there (streaming): what the agent said. Only at the
  /// end: one spoken of in the middle of the text, or in code, stays.
  static String strip(String text) => switch (_tailAt(text)) {
    final at? => text.substring(0, at),
    null => text,
  };

  /// The suggestions at the end of [text], each whole; at most [max], none
  /// too long. Accepts both `[next-button:…]` and legacy
  /// `<reply_suggestion>…</reply_suggestion>` (where each line of a tag is
  /// one, as some models put them all in one).
  static List<String> of(String text) {
    final at = _tailAt(text);
    if (at == null) return const [];
    return [
      for (final match in _whole.allMatches(text, at))
        for (final line in (match[1] ?? match[2]!).split('\n'))
          if (line.trim() case final said
              when said.isNotEmpty && said.length <= maxLength)
            said,
    ].take(max).toList();
  }

  /// [text] with [suggestions] at its end, as the agent writes them.
  static String write(String text, List<String> suggestions) =>
      suggestions.isEmpty
      ? text
      : '$text\n${suggestions.map((said) => '[$buttonTag:$said]').join(' ')}';

  static const _open = '<$tag>';
  static const _buttonPrefix = '[$buttonTag';
  static const _buttonOpen = '[$buttonTag:';

  /// What one says: a `[next-button:…]` token (also tolerating a full-width
  /// colon), or a legacy `<reply_suggestion>…</reply_suggestion>` tag.
  static final _whole = RegExp(
    '\\[$buttonTag[:：]([^\\]\\r\\n]*)\\]|<$tag>([^<]*)</$tag>',
  );

  /// Before each, a list's marker some models put there.
  static const _marker = r'(?:(?:[-*•]|\d+[.)])[ \t]*)?';

  static const _completeButton = '(?<!`)\\[$buttonTag[:：][^\\]\\r\\n]*\\]';
  static const _completeXml = '<$tag>[^<]*</$tag>';
  static const _complete = '(?:$_completeButton|$_completeXml)';

  /// Whole ones (button or legacy XML); then perhaps one under way, its end
  /// not yet whole (not one in code, e.g. `` `[next-button:…]` `` or
  /// `` `<tag>` ``); or the start of its marker/tag.
  static final _tail = RegExp(
    '(?:\\s*$_marker$_complete)*'
    '(?:'
    '\\s*$_marker(?<!`)\\[$buttonTag[:：][^\\]\\r\\n]*'
    '|\\s*(?<=^|\\s)$_marker(\\[[a-z-]*)'
    '|\\s*$_marker<$tag>(?:[^<`][^<]*)?(?:</?[a-z_]*)?'
    '|\\s*(<[a-z_]*)'
    '|\\s*'
    ')\$',
  );

  static bool _mightHaveTail(String text) {
    final lb = text.lastIndexOf('[');
    if (lb >= 0 &&
        (text.contains(_buttonPrefix) ||
            _buttonOpen.startsWith(text.substring(lb)))) {
      return true;
    }
    final lt = text.lastIndexOf('<');
    if (lt >= 0 &&
        (text.contains(_open) || _open.startsWith(text.substring(lt)))) {
      return true;
    }
    return false;
  }

  /// Where the suggestions at the end of [text] start (the space before
  /// them too); null when there are none.
  static int? _tailAt(String text) {
    // Cheap first: neither format's opener, nor the start of one at the end.
    if (!_mightHaveTail(text)) return null;
    final match = _tail.firstMatch(text);
    if (match == null || match.start == match.end) return null;
    // A bracket/tag start at the end that is not theirs: none.
    if (match[1] case final start? when !_buttonOpen.startsWith(start)) {
      return null;
    }
    if (match[2] case final start? when !_open.startsWith(start)) {
      return null;
    }
    final at = match.start;
    // Only space before: nothing said.
    if (text.substring(at).trim().isEmpty) return null;
    return at;
  }
}
