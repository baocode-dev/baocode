/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Markdown as VS Code's editor hovers render it: language servers' hovers,
// signature help and suggest documentation.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/hover/hoverWidget.css (`.monaco-hover` blocks, code
// and rules), src/vs/editor/contrib/hover/browser/hover.css and
// hoverContribution.ts (code background, rule color), and
// src/vs/editor/browser/widget/markdownRenderer/browser/
// editorMarkdownCodeBlockRenderer.ts (fenced code is tokenized in the
// editor's font and theme, in the fence's language or else the editor's).
// The colors are the color theme's: `editorHoverWidget.*` (or the suggest
// details' `editorSuggestWidget.foreground`), `textLink.foreground` and
// `textCodeBlock.background`.
//
// Deviations: tables are shown as their text, HTML is shown as text, and
// only web and mail links open (in the browser).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart';
import '../../workspace/editor_launcher.dart';

/// Colors [code] in the language named [language] (an id or an alias, as
/// code fences name them), one list of spans per line; null to leave it
/// plain.
typedef IdeCodeColorizer = Future<List<List<TextSpan>>?> Function(
  String language,
  String code,
);

/// The editor's font for code in hovers (`applyFontInfo`), and the size
/// the hover's text takes from it (`contentHoverWidget.ts`).
const ideHoverCodeStyle = TextStyle(
  fontFamily: CursorFonts.mono,
  fontSize: 13,
  height: 1.45,
);

/// [markdown] as a hover shows it. Each block carries the hover's side
/// [padding], so rules can span the whole hover as VS Code's do.
class IdeHoverMarkdown extends StatelessWidget {
  const IdeHoverMarkdown(
    this.markdown, {
    super.key,
    this.colorize,
    this.language,
    this.codeStyle = ideHoverCodeStyle,
    this.padding = 8,
    this.foreground = 'editorHoverWidget.foreground',
  });

  final String markdown;
  final IdeCodeColorizer? colorize;

  /// The editor's language, for code fences that name none.
  final String? language;

  /// The editor's font; the text takes its size and line height.
  final TextStyle codeStyle;

  /// `.hover-contents`' side padding, which rules reach across.
  final double padding;

  /// The id of the text's color: the widget's foreground.
  final String foreground;

  static final _document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );

  @override
  Widget build(BuildContext context) {
    final color = themeColors[foreground];
    final text = TextStyle(
      color: color,
      fontSize: codeStyle.fontSize,
      height: codeStyle.height,
    );
    return DefaultTextStyle.merge(
      style: text,
      child: _Blocks(
        nodes: _document.parse(markdown),
        context: _Context(
          colorize: colorize,
          language: language,
          code: codeStyle.copyWith(color: color),
          text: text,
        ),
        padding: padding,
      ),
    );
  }
}

class _Context {
  const _Context({
    required this.colorize,
    required this.language,
    required this.code,
    required this.text,
  });

  final IdeCodeColorizer? colorize;
  final String? language;
  final TextStyle code;
  final TextStyle text;
}

/// Blocks with their `margin: 8px 0` collapsed between them, none at the
/// ends. A rule (`margin: 4px -8px -4px`) sits 8px under the block above
/// and 4px over the one below.
class _Blocks extends StatelessWidget {
  const _Blocks({
    required this.nodes,
    required this.context,
    this.padding = 0,
    this.item = false,
  });

  final List<md.Node> nodes;
  final _Context context;

  /// Blocks' side padding (rules have none).
  final double padding;

  /// A list item's blocks: a list in it follows at once (`li > ul`).
  final bool item;

  @override
  Widget build(BuildContext buildContext) {
    final children = <Widget>[];
    md.Node? previous;
    for (final node in nodes) {
      final block = _block(node, context);
      if (block == null) continue;
      if (previous != null) {
        final gap = _isRule(previous)
            ? 4.0
            : item && _isList(node)
            ? 0.0
            : 8.0;
        children.add(SizedBox(height: gap));
      }
      children.add(
        padding > 0 && !_isRule(node)
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: block,
              )
            : block,
      );
      previous = node;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static bool _isRule(md.Node node) => node is md.Element && node.tag == 'hr';

  static bool _isList(md.Node node) =>
      node is md.Element && (node.tag == 'ul' || node.tag == 'ol');
}

Widget? _block(md.Node node, _Context context) {
  if (node is md.Text) {
    return Text.rich(TextSpan(text: _unescape(node.text)));
  }
  if (node is! md.Element) return null;
  final children = node.children ?? const <md.Node>[];
  switch (node.tag) {
    case 'p':
      return Text.rich(_inlines(children, context));
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      // The browser's heading sizes, at `line-height: 1.1`.
      final scale = switch (node.tag) {
        'h1' => 2.0,
        'h2' => 1.5,
        'h3' => 1.17,
        'h4' => 1.0,
        'h5' => 0.83,
        _ => 0.67,
      };
      return Text.rich(
        _inlines(children, context),
        style: TextStyle(
          fontSize: context.text.fontSize! * scale,
          height: 1.1,
          fontWeight: FontWeight.bold,
        ),
      );
    case 'pre':
      final code = children.firstOrNull;
      final language = code is md.Element
          ? (code.attributes['class'] ?? '').replaceFirst('language-', '')
          : '';
      var text = _unescape(node.textContent);
      if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
      return _CodeBlock(
        code: text,
        language: language.isNotEmpty ? language : context.language,
        context: context,
      );
    case 'hr':
      // `border-top: 1px solid editorHoverWidget.border` at half opacity.
      final border = themeColors['editorHoverWidget.border'];
      return Container(
        height: 1,
        margin: const EdgeInsets.only(top: 4),
        color: border.withValues(alpha: border.a / 2),
      );
    case 'ul' || 'ol':
      return _List(node: node, context: context);
    case 'blockquote':
      // The browser's `margin: 1em 40px`; hovers do not style quotes.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: _Blocks(nodes: children, context: context),
      );
    default:
      // Tables and anything else: their text.
      return Text(_unescape(node.textContent));
  }
}

/// A list: 20px of indent holding the markers (`padding-left: 20px`).
class _List extends StatelessWidget {
  const _List({required this.node, required this.context});

  final md.Element node;
  final _Context context;

  @override
  Widget build(BuildContext buildContext) {
    final ordered = node.tag == 'ol';
    var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final items = [
      for (final child in node.children ?? const <md.Node>[])
        if (child is md.Element && child.tag == 'li') child,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  ordered ? '${number++}.' : '•',
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: _item(item)),
            ],
          ),
      ],
    );
  }

  /// A tight item's text comes as inline nodes, not paragraphs: each run
  /// of them is shown as a paragraph.
  Widget _item(md.Element item) {
    final blocks = <md.Node>[];
    var run = <md.Node>[];
    void endRun() {
      if (run.isNotEmpty) blocks.add(md.Element('p', run));
      run = [];
    }

    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && _blockTags.contains(child.tag)) {
        endRun();
        blocks.add(child);
      } else {
        run.add(child);
      }
    }
    endRun();
    return _Blocks(nodes: blocks, context: context, item: true);
  }

  static const _blockTags = {
    'p',
    'pre',
    'ul',
    'ol',
    'hr',
    'blockquote',
    'table',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };
}

/// Fenced code, tokenized in the editor's theme once its colors are in;
/// plain until then. No box around it, as in VS Code.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.code,
    required this.language,
    required this.context,
  });

  final String code;
  final String? language;
  final _Context context;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  /// Recently colored blocks, by color theme, so a hover shown again is
  /// colored at once.
  static final _recent =
      <(Object, IdeCodeColorizer, String, String), List<TextSpan>>{};

  List<TextSpan>? _spans;
  int _request = 0;

  /// The color theme [_spans] are colored in.
  Object? _theme;

  @override
  void initState() {
    super.initState();
    _color();
  }

  @override
  void didUpdateWidget(_CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.context.colorize != widget.context.colorize) {
      _spans = null;
      _color();
    }
  }

  void _color() {
    final theme = _theme = WorkbenchThemeService.instance.colorTheme;
    final colorize = widget.context.colorize;
    final language = widget.language;
    final request = ++_request;
    if (colorize == null || language == null) return;
    final key = (theme, colorize, language, widget.code);
    if (_recent[key] case final spans?) {
      _spans = spans;
      return;
    }
    colorize(language, widget.code).then(
      (lines) {
        if (lines == null) return;
        final spans = [
          for (final (index, line) in lines.indexed) ...[
            if (index > 0) const TextSpan(text: '\n'),
            ...line,
          ],
        ];
        _recent.remove(key);
        _recent[key] = spans;
        while (_recent.length > 32) {
          _recent.remove(_recent.keys.first);
        }
        if (mounted && request == _request) setState(() => _spans = spans);
      },
      // Left plain: the text is all there is to show.
      onError: (Object _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    // A new color theme colors the code again.
    if (!identical(_theme, WorkbenchThemeService.instance.colorTheme)) {
      _spans = null;
      _color();
    }
    return Text.rich(
      TextSpan(text: _spans == null ? widget.code : null, children: _spans),
      style: widget.context.code,
    );
  }
}

TextSpan _inlines(List<md.Node> nodes, _Context context) =>
    TextSpan(children: [for (final node in nodes) _inline(node, context)]);

InlineSpan _inline(md.Node node, _Context context) {
  if (node is md.Text) return TextSpan(text: _unescape(node.text));
  if (node is! md.Element) return const TextSpan();
  final children = node.children ?? const <md.Node>[];
  List<InlineSpan> inner() => [
    for (final child in children) _inline(child, context),
  ];
  return switch (node.tag) {
    'strong' || 'b' => TextSpan(
      style: const TextStyle(fontWeight: FontWeight.bold),
      children: inner(),
    ),
    'em' || 'i' => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: inner(),
    ),
    'del' => TextSpan(
      style: const TextStyle(decoration: TextDecoration.lineThrough),
      children: inner(),
    ),
    // `.monaco-hover code`: the editor font on `textCodeBlock.background`,
    // `padding: 0 0.4em`, `border-radius: 3px`.
    'code' => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.code.fontSize! * 0.4),
        decoration: BoxDecoration(
          color: themeColors['textCodeBlock.background'],
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(_unescape(node.textContent), style: context.code),
      ),
    ),
    'a' => TextSpan(
      style: TextStyle(color: themeColors['textLink.foreground']),
      children: switch (_linkRecognizer(node.attributes['href'])) {
        final recognizer? => [
          for (final span in inner()) _linked(span, recognizer),
        ],
        null => inner(),
      },
    ),
    'br' => const TextSpan(text: '\n'),
    'img' => TextSpan(text: node.attributes['alt'] ?? ''),
    _ => TextSpan(children: inner()),
  };
}

/// Opens web and mail links in the browser; a server's other links
/// (`command:`, `file:`) are left as text.
GestureRecognizer? _linkRecognizer(String? href) {
  final uri = href == null ? null : Uri.tryParse(href.trim());
  if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
    return null;
  }
  return TapGestureRecognizer()..onTap = () => openExternal(uri.toString());
}

/// [span] with every piece of its text tappable: a tap lands on the
/// innermost span, which does not inherit its parent's recognizer.
InlineSpan _linked(InlineSpan span, GestureRecognizer recognizer) =>
    switch (span) {
      TextSpan(:final text, :final style, :final children) => TextSpan(
        text: text,
        style: style,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
        children: [
          for (final child in children ?? const <InlineSpan>[])
            _linked(child, recognizer),
        ],
      ),
      _ => span,
    };

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
