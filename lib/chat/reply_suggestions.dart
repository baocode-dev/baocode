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
  static String strip(String text) => _parse(text).stripped;

  /// The suggestions at the end of [text], each whole; at most [max], none
  /// too long. Accepts both `[next-button:…]` and legacy
  /// `<reply_suggestion>…</reply_suggestion>` (where each line of a tag is
  /// one, as some models put them all in one).
  static List<String> of(String text) => _parse(text).suggestions;

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

  static const _cacheLimit = 256;

  /// Bounded identity-keyed LRU cache for parsed `(stripped, suggestions)`
  /// results. Avoids repeating regex scans across frequent rebuilds when
  /// [AssistantTextItem.text] and [AssistantTextItem.suggestions] read the
  /// same `raw` string instance.
  static final Map<String, ({String stripped, List<String> suggestions})>
  _cache = Map.identity();

  static ({String stripped, List<String> suggestions}) _parse(String text) {
    final cached = _cache.remove(text);
    if (cached != null) {
      _cache[text] = cached;
      return cached;
    }
    final at = _tailAt(text);
    final ({String stripped, List<String> suggestions}) result;
    if (at == null) {
      result = (stripped: text, suggestions: const []);
    } else {
      final extracted = [
        for (final match in _whole.allMatches(text, at))
          for (final line in (match[1] ?? match[2]!).split('\n'))
            if (line.trim() case final said
                when said.isNotEmpty && said.length <= maxLength)
              said,
      ];
      final limited = extracted.length > max
          ? extracted.sublist(0, max)
          : extracted;
      result = (
        stripped: text.substring(0, at),
        suggestions: limited.isEmpty
            ? const []
            : List<String>.unmodifiable(limited),
      );
    }
    if (_cache.length >= _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    _cache[text] = result;
    return result;
  }

  /// Earliest character index in [text] where a valid suggestion tail could
  /// begin (or null when no suggestion opener or partial opener exists).
  static int? _scanStart(String text) {
    final len = text.length;
    var anchor = len;

    final lb = text.lastIndexOf('[');
    if (lb >= 0) {
      final firstButton = text.indexOf(_buttonPrefix);
      if (firstButton >= 0) {
        if (firstButton < anchor) anchor = firstButton;
      } else if (_buttonOpen.startsWith(text.substring(lb))) {
        if (lb < anchor) anchor = lb;
      }
    }

    final lt = text.lastIndexOf('<');
    if (lt >= 0) {
      final firstXml = text.indexOf(_open);
      if (firstXml >= 0) {
        if (firstXml < anchor) anchor = firstXml;
      } else if (_open.startsWith(text.substring(lt))) {
        if (lt < anchor) anchor = lt;
      }
    }

    if (anchor == len) return null;

    // Step left across any optional list marker (`- `, `* `, `• `, `1. `, `2) `)
    // and leading whitespace so `_tail.firstMatch(text, start)` matches the
    // exact same start index as scanning from 0 without walking the full body.
    var i = anchor;
    while (i > 0 && _isInlineSpace(text.codeUnitAt(i - 1))) {
      i--;
    }
    if (i > 0) {
      final prev = text.codeUnitAt(i - 1);
      if (prev == 0x2D /* - */ ||
          prev == 0x2A /* * */ ||
          prev == 0x2022 /* • */ ) {
        i--;
      } else if (prev == 0x2E /* . */ || prev == 0x29 /* ) */ ) {
        var j = i - 1;
        while (j > 0 && _isAsciiDigit(text.codeUnitAt(j - 1))) {
          j--;
        }
        if (j < i - 1) i = j;
      }
    }
    while (i > 0 && _isWhitespace(text.codeUnitAt(i - 1))) {
      i--;
    }
    return i;
  }

  static bool _isInlineSpace(int cu) => cu == 0x20 || cu == 0x09;

  static bool _isAsciiDigit(int cu) => cu >= 0x30 && cu <= 0x39;

  static bool _isWhitespace(int cu) =>
      cu == 0x20 ||
      cu == 0x09 ||
      cu == 0x0A ||
      cu == 0x0D ||
      cu == 0x0B ||
      cu == 0x0C ||
      cu == 0xA0 ||
      cu == 0xFEFF ||
      cu == 0x3000;

  /// Where the suggestions at the end of [text] start (the space before
  /// them too); null when there are none.
  static int? _tailAt(String text) {
    // Cheap first: neither format's opener, nor the start of one at the end.
    final start = _scanStart(text);
    if (start == null) return null;
    final match = _tail.allMatches(text, start).firstOrNull;
    if (match == null || match.start == match.end) return null;
    // A bracket/tag start at the end that is not theirs: none.
    if (match[1] case final open? when !_buttonOpen.startsWith(open)) {
      return null;
    }
    if (match[2] case final open? when !_open.startsWith(open)) {
      return null;
    }
    final at = match.start;
    // Only space before: nothing said.
    if (text.substring(at).trim().isEmpty) return null;
    return at;
  }
}
