import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../chat/widgets/markdown_view.dart';
import 'markdown_blocks.dart';

/// A markdown text as the preview shows it: its blocks (those with
/// something in them), its headings' anchors, and each block parsed with
/// the link definitions of the whole text.
class MarkdownSource {
  factory MarkdownSource(String text) {
    final lines = MarkdownLines(text);
    final blocks = [
      for (final block in splitMarkdownBlocks(lines))
        if (block.kind != MarkdownBlockKind.blank) block,
    ];
    return MarkdownSource._(lines, blocks);
  }

  MarkdownSource._(this.lines, this.blocks) {
    // Link definitions apply to the whole text: read first.
    for (final block in blocks) {
      if (block.kind == MarkdownBlockKind.paragraph &&
          _definition.hasMatch(lines[block.start])) {
        _document.parseLines(_split(source(block)));
      }
    }
    final taken = <String, int>{};
    for (final (index, block) in blocks.indexed) {
      if (block.kind != MarkdownBlockKind.heading) continue;
      final base = markdownSlug(
        parse(block).map((node) => node.textContent).join(),
      );
      final count = taken[base];
      taken[base] = (count ?? 0) + 1;
      anchors[index] = count == null ? base : '$base-$count';
    }
  }

  final MarkdownLines lines;

  /// The blocks, empty lines aside.
  final List<MarkdownBlock> blocks;

  /// The headings' anchors (`#getting-started`), by their index in
  /// [blocks], as GitHub makes them.
  final Map<int, String> anchors = {};

  final md.Document _document = MarkdownView.document();
  final Map<MarkdownBlock, List<md.Node>> _parsed = {};

  String get text => lines.text;

  /// [block]'s text, without the line break after it.
  String source(MarkdownBlock block) => lines.source(block.start, block.end);

  /// [block] parsed, its task boxes numbered (see [numberTasks]).
  List<md.Node> parse(MarkdownBlock block) => _parsed.putIfAbsent(block, () {
    final nodes = _document.parseLines(_split(source(block)));
    numberTasks(nodes);
    return nodes;
  });

  /// The block [line] (zero-based) is in, or the first after it, or the
  /// last; null without blocks.
  int? blockAt(int line) {
    if (blocks.isEmpty) return null;
    for (final (index, block) in blocks.indexed) {
      if (line < block.end) return index;
    }
    return blocks.length - 1;
  }

  /// The heading block whose anchor is [anchor].
  int? heading(String anchor) {
    final wanted = markdownSlug(Uri.decodeComponent(anchor));
    for (final MapEntry(:key, :value) in anchors.entries) {
      if (value == anchor || value == wanted) return key;
    }
    return null;
  }

  /// Where the marks of [block]'s task boxes (the space or `x` between the
  /// brackets) are in the text, in the order of their lines: box `n` of
  /// [numberTasks] is the `n`th.
  List<int> taskMarks(MarkdownBlock block) {
    final marks = <int>[];
    String? fence;
    for (var line = block.start; line < block.end; line++) {
      final text = lines[line];
      final content = text.replaceFirst(_quotePrefix, '');
      if (fence != null) {
        if (content.trimLeft().startsWith(fence)) fence = null;
        continue;
      }
      final item = _taskItem.firstMatch(text);
      final opened = _fenceStart.firstMatch(
        item == null ? content.replaceFirst(_itemMarker, '') : content,
      );
      if (item != null) marks.add(lines.starts[line] + item.end - 2);
      if (opened != null) fence = opened[1];
    }
    return marks;
  }

  static List<String> _split(String text) => text.split(_lineBreak);
}

final _lineBreak = RegExp('\r\n|\r|\n');
final _definition = RegExp(r'^ {0,3}\[[^\]]+\]:');
final _quotePrefix = RegExp(r'^(?:[ \t]*>[ \t]?)*');
final _itemMarker = RegExp(r'^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+');
final _taskItem = RegExp(
  r'^(?:[ \t]*>[ \t]?)*[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+ {0,3}\[[ xX]\](?=[ \t])',
);
final _fenceStart = RegExp(r'^[ \t]*(`{3,}|~{3,})');

/// [heading]'s anchor, as GitHub makes one: lower case, its punctuation
/// dropped and its spaces dashes. Letters of any script stay.
String markdownSlug(String heading) => heading
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\p{Pc}\- ]', unicode: true), '')
    .replaceAll(' ', '-');

/// Where a link of a markdown file goes.
sealed class MarkdownLinkTarget {
  const MarkdownLinkTarget();
}

/// A heading of the same file.
class MarkdownAnchorLink extends MarkdownLinkTarget {
  const MarkdownAnchorLink(this.anchor);

  final String anchor;
}

/// A web page or a mail, for the browser.
class MarkdownExternalLink extends MarkdownLinkTarget {
  const MarkdownExternalLink(this.uri);

  final Uri uri;
}

/// A file of the project's host, and the part of it after `#`.
class MarkdownFileLink extends MarkdownLinkTarget {
  const MarkdownFileLink(this.path, [this.fragment]);

  final String path;
  final String? fragment;
}

/// Where [href], in the markdown file at [document], goes: relative paths
/// are the file's folder's, in [context]'s style (a remote project's are
/// POSIX). Null for what opens nothing (other schemes).
MarkdownLinkTarget? resolveMarkdownLink(
  String? href,
  String document,
  p.Context context,
) {
  final link = href?.trim();
  if (link == null || link.isEmpty) return null;
  if (link.startsWith('#')) {
    return MarkdownAnchorLink(_decode(link.substring(1)));
  }
  final uri = Uri.tryParse(link);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  // `C:\notes.md` is a path, not a scheme.
  if (scheme.length > 1) {
    if (const {'http', 'https', 'mailto'}.contains(scheme)) {
      return MarkdownExternalLink(uri!);
    }
    if (scheme == 'file' && uri!.path.isNotEmpty) {
      final path = uri.toFilePath(windows: context.style == p.Style.windows);
      return MarkdownFileLink(path, uri.hasFragment ? uri.fragment : null);
    }
    return null;
  }
  final hash = link.indexOf('#');
  final relative = _decode(hash < 0 ? link : link.substring(0, hash));
  final fragment = hash < 0 ? null : _decode(link.substring(hash + 1));
  if (relative.isEmpty) {
    return fragment == null ? null : MarkdownAnchorLink(fragment);
  }
  return MarkdownFileLink(
    context.normalize(
      context.isAbsolute(relative)
          ? relative
          : context.join(context.dirname(document), relative),
    ),
    fragment,
  );
}

/// An image's [src] in the markdown file at [document]: a web address, or
/// the path of a file of the project's host. Null for what is neither.
({Uri? url, String? path})? resolveMarkdownImage(
  String src,
  String document,
  p.Context context,
) {
  final target = resolveMarkdownLink(src, document, context);
  return switch (target) {
    MarkdownExternalLink(:final uri) when uri.scheme.startsWith('http') => (
      url: uri,
      path: null,
    ),
    MarkdownFileLink(:final path) => (url: null, path: path),
    _ => null,
  };
}

String _decode(String text) {
  try {
    return Uri.decodeComponent(text);
  } on ArgumentError {
    return text;
  }
}
