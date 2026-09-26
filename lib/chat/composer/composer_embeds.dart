import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';

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
  Widget build(BuildContext context, EmbedContext embedContext) {
    final token = ComposerTokenEmbed.decode(embedContext.node.value.data);
    final isCommand = token.kind == SuggestionKind.command;
    return _CenteredOnText(
      textStyle: embedContext.textStyle,
      // The editor's 1.5 line height would otherwise make the token taller
      // than the line itself.
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: _buildToken(token, isCommand),
      ),
    );
  }

  Widget _buildToken(
    ({SuggestionKind kind, String label, String value}) token,
    bool isCommand,
  ) {
    return Container(
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
              style: const TextStyle(color: CursorColors.text, fontSize: 12),
            ),
          ],
        ),
      },
    );
  }
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
