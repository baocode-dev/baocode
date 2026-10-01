import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../vs/editor/common/encoded_token_attributes.dart' as monaco;
import '../vs/editor/common/languages/supports/tokenization.dart';

/// Pinned built-in Monaco theme rules, interpreted by the ported TokenTheme.
class MonacoThemeAssets {
  const MonacoThemeAssets({this.bundle});

  static const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
  static const path = 'packages/bao_editor/assets/monaco/themes.json';
  final AssetBundle? bundle;

  Future<MonacoBuiltinTheme> load(String id) async {
    final data = jsonDecode(
      await (bundle ?? rootBundle).loadString(path),
    ) as Map<String, dynamic>;
    if (data['revision'] != revision) {
      throw const FormatException('Monaco theme revision mismatch');
    }
    final themes = data['themes'] as Map<String, dynamic>;
    if (!themes.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown Monaco built-in theme');
    }
    final source = themes[id] as Map<String, dynamic>;
    final rules = <TokenThemeRule>[
      for (final item in source['rules'] as List)
        TokenThemeRule(
          token: (item as Map<String, dynamic>)['token'] as String,
          foreground: item['foreground'] as String?,
          background: item['background'] as String?,
          fontStyle: item['fontStyle'] as String?,
        ),
    ];
    final colors = ((source['encodedTokensColors'] as List?) ?? const [])
        .cast<String>();
    return MonacoBuiltinTheme(
      id,
      TokenTheme.createFromRawTokenTheme(rules, colors),
    );
  }
}

class MonacoBuiltinTheme {
  const MonacoBuiltinTheme(this.id, this.tokenTheme);

  final String id;
  final TokenTheme tokenTheme;

  Color get foreground => styleForToken('').color!;

  Color get background {
    final metadata = tokenTheme.matchRule('').metadata;
    return tokenTheme.getColorMap()[monaco.TokenMetadata.getBackground(
      metadata,
    )]!;
  }

  TextStyle styleForToken(String tokenType) {
    final rule = tokenTheme.matchRule(tokenType);
    final metadata = rule.metadata;
    final colors = tokenTheme.getColorMap();
    final foreground = colors[monaco.TokenMetadata.getForeground(metadata)];
    final backgroundId = monaco.TokenMetadata.getBackground(metadata);
    final defaultBackgroundId = monaco.TokenMetadata.getBackground(
      tokenTheme.matchRule('').metadata,
    );
    final flags = monaco.TokenMetadata.getFontStyle(metadata);
    final underline = flags & monaco.FontStyle.underline != 0;
    final strikethrough = flags & monaco.FontStyle.strikethrough != 0;
    return TextStyle(
      color: foreground,
      backgroundColor: backgroundId == defaultBackgroundId
          ? null
          : colors[backgroundId],
      fontStyle: flags & monaco.FontStyle.italic != 0
          ? FontStyle.italic
          : FontStyle.normal,
      fontWeight: flags & monaco.FontStyle.bold != 0
          ? FontWeight.bold
          : FontWeight.normal,
      decoration: underline && strikethrough
          ? TextDecoration.combine([
              TextDecoration.underline,
              TextDecoration.lineThrough,
            ])
          : underline
          ? TextDecoration.underline
          : strikethrough
          ? TextDecoration.lineThrough
          : null,
    );
  }
}
