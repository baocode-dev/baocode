import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../theme/cursor_theme.dart';
import '../widgets/file_label.dart';
import 'composer_mock_data.dart';

/// Inline, atomic token for an @mention or a /command. It occupies a single
/// character in the document, so the caret skips it and backspace deletes it
/// as a whole.
class ComposerTokenEmbed {
  static const type = 'composer-token';

  static Embeddable fromSuggestion(Suggestion suggestion) => Embeddable(
    type,
    jsonEncode({
      'kind': suggestion.kind.name,
      'label': suggestion.label,
      'value': suggestion.value,
    }),
  );

  static ({SuggestionKind kind, String label, String value}) decode(
    Object? data,
  ) {
    final map = jsonDecode(data as String) as Map<String, dynamic>;
    return (
      kind: SuggestionKind.values.byName(map['kind'] as String),
      label: map['label'] as String,
      value: map['value'] as String,
    );
  }

  /// Text a token contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) {
    final token = decode(data);
    return token.kind == SuggestionKind.command
        ? '/${token.value}'
        : '@${token.value}';
  }
}

/// A composer document for sent [text], the inverse of
/// [ComposerTokenEmbed.plainText]: `@value` of a known mention, any other
/// `@path`, and a leading `/command` become tokens again.
Delta composerDeltaFromText(String text) {
  final delta = Delta();
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    delta.insert(buffer.toString());
    buffer.clear();
  }

  void token(Suggestion suggestion) {
    flush();
    delta.insert(ComposerTokenEmbed.fromSuggestion(suggestion).toJson());
  }

  // Where a token's value may end: not inside a path or word.
  final valueChar = RegExp(r'[A-Za-z0-9_./\-]');
  bool endsAt(int index) =>
      index >= text.length || !valueChar.hasMatch(text[index]);
  List<Suggestion> longestFirst(List<Suggestion> source) =>
      [...source]..sort((a, b) => b.value.length.compareTo(a.value.length));

  var i = 0;
  if (text.startsWith('/')) {
    for (final command in longestFirst(ComposerMockData.commands)) {
      if (text.startsWith(command.value, 1) &&
          endsAt(1 + command.value.length)) {
        token(command);
        i = 1 + command.value.length;
        break;
      }
    }
  }
  final mentions = longestFirst(ComposerMockData.mentions);
  while (i < text.length) {
    final atBoundary = i == 0 || text[i - 1].trim().isEmpty;
    if (text[i] == '@' && atBoundary) {
      var mention = mentions
          .where((m) => text.startsWith(m.value, i + 1))
          .where((m) => endsAt(i + 1 + m.value.length))
          .firstOrNull;
      if (mention == null) {
        var end = i + 1;
        while (!endsAt(end)) {
          end++;
        }
        final path = text.substring(i + 1, end);
        if (path.isNotEmpty) {
          final slash = path.lastIndexOf('/');
          mention = Suggestion(
            kind: SuggestionKind.file,
            label: path.substring(slash + 1),
            detail: slash < 0 ? '' : path.substring(0, slash),
          );
        }
      }
      if (mention != null) {
        token(mention);
        i += 1 + mention.value.length;
        continue;
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flush();
  delta.insert('\n');
  return delta;
}

class ComposerTokenEmbedBuilder extends EmbedBuilder {
  const ComposerTokenEmbedBuilder();

  @override
  String get key => ComposerTokenEmbed.type;

  @override
  bool get expanded => false;

  // Baseline alignment against a baseline we report ourselves (see
  // [_CenteredOnText]). `PlaceholderAlignment.middle` depends on the glyph
  // runs sharing the line, so a line holding only a token and a trailing
  // space laid out taller than one with text, and the composer jumped.
  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: widget,
  );

  @override
  String toPlainText(Embed node) =>
      ComposerTokenEmbed.plainText(node.value.data);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      ComposerTokenChip(
        data: embedContext.node.value.data,
        textStyle: embedContext.textStyle,
      );
}

/// The inline tag for a token ([ComposerTokenEmbed] data), centered on text
/// of [textStyle]: used in the composer and in sent messages alike.
///
/// Inside a selectable area it copies as its message text (`@lib/main.dart`,
/// `/plan`) whenever any of it is selected, not as the label it shows.
class ComposerTokenChip extends StatelessWidget {
  const ComposerTokenChip({
    super.key,
    required this.data,
    required this.textStyle,
  });

  final Object? data;
  final TextStyle textStyle;

  /// [ComposerTokenChip] as a span for rich text of [textStyle].
  static InlineSpan span(Object? data, TextStyle textStyle) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: ComposerTokenChip(data: data, textStyle: textStyle),
  );

  @override
  Widget build(BuildContext context) {
    final token = ComposerTokenEmbed.decode(data);
    final isCommand = token.kind == SuggestionKind.command;
    return _CopiesAs(
      text: ComposerTokenEmbed.plainText(data),
      child: _CenteredOnText(
        textStyle: textStyle,
        // A 1.5 line height would otherwise make the token taller than the
        // line itself.
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            height: 1.25,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
            decoration: BoxDecoration(
              color: isCommand ? const Color(0x264C9DFF) : CursorColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isCommand
                    ? const Color(0x404C9DFF)
                    : CursorColors.borderStrong,
              ),
            ),
            child: switch (token.kind) {
              SuggestionKind.file => FileLabel(token.label, fontSize: 12),
              SuggestionKind.command => Text(
                '/${token.label}',
                style: const TextStyle(
                  color: CursorColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _ => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    token.kind == SuggestionKind.folder
                        ? Icons.folder_outlined
                        : Icons.alternate_email_rounded,
                    size: 13,
                    color: CursorColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    token.label,
                    style: const TextStyle(
                      color: CursorColors.text,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Makes the text in [child] copy as [text] when any of it is selected.
class _CopiesAs extends StatefulWidget {
  const _CopiesAs({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  State<_CopiesAs> createState() => _CopiesAsState();
}

class _CopiesAsState extends State<_CopiesAs> {
  late final _delegate = _CopiesAsDelegate(widget.text);

  @override
  void didUpdateWidget(_CopiesAs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _delegate.text = widget.text;
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _CopiesAsDelegate extends StaticSelectionContainerDelegate {
  _CopiesAsDelegate(this.text);

  String text;

  @override
  SelectedContent? getSelectedContent() => super.getSelectedContent() == null
      ? null
      : SelectedContent(plainText: text);
}

/// Reports a baseline that puts the child's vertical center on the center of
/// the glyphs of [textStyle], so a baseline-aligned token sits optically
/// centered on the surrounding text regardless of what else is on the line.
class _CenteredOnText extends SingleChildRenderObjectWidget {
  const _CenteredOnText({required this.textStyle, required super.child});

  final TextStyle textStyle;

  /// Distance from the alphabetic baseline up to the glyph center.
  double _glyphCenterAboveBaseline(TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: textStyle.copyWith(height: null)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final metrics = painter.computeLineMetrics().first;
    painter.dispose();
    return (metrics.ascent - metrics.descent) / 2;
  }

  @override
  _RenderCenteredOnText createRenderObject(BuildContext context) =>
      _RenderCenteredOnText(
        _glyphCenterAboveBaseline(MediaQuery.textScalerOf(context)),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredOnText renderObject,
  ) {
    renderObject.centerAboveBaseline = _glyphCenterAboveBaseline(
      MediaQuery.textScalerOf(context),
    );
  }
}

class _RenderCenteredOnText extends RenderProxyBox {
  _RenderCenteredOnText(this._centerAboveBaseline);

  double _centerAboveBaseline;
  set centerAboveBaseline(double value) {
    if (value == _centerAboveBaseline) return;
    _centerAboveBaseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      size.height / 2 + _centerAboveBaseline;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => getDryLayout(constraints).height / 2 + _centerAboveBaseline;
}
