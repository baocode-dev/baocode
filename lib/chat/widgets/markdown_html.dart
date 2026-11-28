import 'package:markdown/markdown.dart' as md;

/// Common inline HTML elements (`<kbd>`, `<sub>`, `<sup>`, `<mark>`, `<br>`,
/// `<b>`, `<i>`, `<u>`, `<s>`, `<code>`, …) parsed into AST elements so
/// Markdown widgets render them instead of showing raw tags as text.
///
/// Paired tags require a matching closing tag; unclosed tags and tags outside
/// the allowlist (such as `<https://…>` or `List<String>`) are left untouched.
class InlineHtmlElementSyntax extends md.InlineSyntax {
  InlineHtmlElementSyntax()
    : super(
        r'<([A-Za-z][A-Za-z0-9]*)(\s[^<>]*)?(/?)>',
        startCharacter: 0x3C, // <
      );

  static const _pairedTags = {
    'kbd',
    'sub',
    'sup',
    'mark',
    'b',
    'strong',
    'i',
    'em',
    's',
    'del',
    'strike',
    'u',
    'ins',
    'code',
  };

  static final _tagPattern = RegExp(
    r'<(?:(/)([A-Za-z][A-Za-z0-9]*)\s*|([A-Za-z][A-Za-z0-9]*)(?:\s[^<>]*)?(/?))>',
  );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final pos = startMatchPos ?? parser.pos;
    if (pos >= parser.source.length || parser.source.codeUnitAt(pos) != 0x3C) {
      return false;
    }
    final match = pattern.matchAsPrefix(parser.source, pos);
    if (match == null) return false;

    final tag = match[1]!.toLowerCase();
    final selfClosing = match[3] == '/';
    if (tag == 'br') {
      parser.writeText();
      parser.addNode(md.Element.empty('br'));
      parser.consume(match[0]!.length);
      return true;
    }
    if (selfClosing || !_pairedTags.contains(tag)) return false;

    final contentStart = match.end;
    final close = _findClosing(parser.source, contentStart, tag);
    if (close == null) return false;

    final inner = parser.source.substring(contentStart, close.start);
    parser.writeText();
    final children = tag == 'code'
        ? <md.Node>[md.Text(inner)]
        : parser.document.parseInline(inner);
    parser.addNode(md.Element(tag, children));
    parser.consume(close.end - pos);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;

  static ({int start, int end})? _findClosing(
    String source,
    int start,
    String tag,
  ) {
    final skipCode = tag != 'code';
    var depth = 0;
    var i = start;
    while (i < source.length) {
      final code = source.codeUnitAt(i);
      if (skipCode && code == 0x60) {
        var ticks = 1;
        while (i + ticks < source.length &&
            source.codeUnitAt(i + ticks) == 0x60) {
          ticks++;
        }
        final closeTicks = _findClosingTicks(source, i + ticks, ticks);
        if (closeTicks != -1) {
          i = closeTicks;
          continue;
        }
        i += ticks;
        continue;
      }
      if (code == 0x3C) {
        final match = _tagPattern.matchAsPrefix(source, i);
        if (match != null) {
          final isClosing = match[1] == '/';
          final name = (match[2] ?? match[3])!.toLowerCase();
          if (name == tag) {
            if (isClosing) {
              if (depth == 0) return (start: match.start, end: match.end);
              depth--;
            } else if (match[4] != '/') {
              depth++;
            }
            i = match.end;
            continue;
          }
        }
      }
      i++;
    }
    return null;
  }

  static int _findClosingTicks(String source, int start, int count) {
    var i = start;
    while (i < source.length) {
      if (source.codeUnitAt(i) != 0x60) {
        i++;
        continue;
      }
      var run = 1;
      while (i + run < source.length && source.codeUnitAt(i + run) == 0x60) {
        run++;
      }
      if (run == count) return i + run;
      i += run;
    }
    return -1;
  }
}
