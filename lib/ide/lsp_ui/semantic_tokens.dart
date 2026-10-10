import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/vs/base/common/color.dart' as vs;
import 'package:bao_editor/monaco/vs/editor/common/encoded_token_attributes.dart'
    as monaco;
import 'package:bao_editor/monaco/vs/editor/common/services/semantic_tokens_provider_styling.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/semanticTokens/common/semantic_tokens_config.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_token_styles.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';

import '../lsp/lsp_protocol.dart';

/// What a semantic token sets on the syntax style under it; a null field
/// keeps the syntax span's value. Upstream these are the `SEMANTIC_USE_*`
/// bits of the token's metadata, and `SparseTokensStore` replaces exactly
/// those attributes of the syntax token.
@immutable
class IdeTokenStyle {
  const IdeTokenStyle({
    this.foreground,
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
  });

  /// Decodes `SemanticTokensProviderStyling` metadata; [colorMap] is the
  /// theme's `tokenColorMap`. Null for `NO_STYLING`.
  static IdeTokenStyle? fromMetadata(int metadata, List<Color?> colorMap) {
    if (metadata == SemanticTokensProviderStylingConstants.noStyling) {
      return null;
    }
    bool? flag(int use, int mask) =>
        metadata & use != 0 ? metadata & mask != 0 : null;
    final foregroundId = monaco.TokenMetadata.getForeground(metadata);
    return IdeTokenStyle(
      foreground:
          metadata & monaco.MetadataConsts.semanticUseForeground != 0 &&
              foregroundId < colorMap.length
          ? colorMap[foregroundId]
          : null,
      bold: flag(
        monaco.MetadataConsts.semanticUseBold,
        monaco.MetadataConsts.boldMask,
      ),
      italic: flag(
        monaco.MetadataConsts.semanticUseItalic,
        monaco.MetadataConsts.italicMask,
      ),
      underline: flag(
        monaco.MetadataConsts.semanticUseUnderline,
        monaco.MetadataConsts.underlineMask,
      ),
      strikethrough: flag(
        monaco.MetadataConsts.semanticUseStrikethrough,
        monaco.MetadataConsts.strikethroughMask,
      ),
    );
  }

  final Color? foreground;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strikethrough;

  /// [style] with the attributes this sets replaced.
  TextStyle applyTo(TextStyle? style) {
    final base = style ?? const TextStyle();
    var decoration = base.decoration;
    if (underline != null || strikethrough != null) {
      final current = decoration ?? TextDecoration.none;
      decoration = TextDecoration.combine([
        if (underline ?? current.contains(TextDecoration.underline))
          TextDecoration.underline,
        if (current.contains(TextDecoration.overline)) TextDecoration.overline,
        if (strikethrough ?? current.contains(TextDecoration.lineThrough))
          TextDecoration.lineThrough,
      ]);
    }
    return base.copyWith(
      color: foreground,
      fontStyle: italic == null
          ? null
          : italic!
          ? FontStyle.italic
          : FontStyle.normal,
      fontWeight: bold == null
          ? null
          : bold!
          ? FontWeight.bold
          : FontWeight.normal,
      decoration: decoration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdeTokenStyle &&
      other.foreground == foreground &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough;

  @override
  int get hashCode =>
      Object.hash(foreground, bold, italic, underline, strikethrough);

  @override
  String toString() =>
      'IdeTokenStyle(foreground: $foreground, bold: $bold, italic: $italic, '
      'underline: $underline, strikethrough: $strikethrough)';
}

/// The style a color theme gives a semantic token of [type] with
/// [modifiers] in a document of [languageId] (VS Code's language id); null
/// leaves the syntax style.
typedef IdeSemanticTokenStyler = IdeTokenStyle? Function(
  String type,
  Set<String> modifiers,
  String languageId,
);

/// The semantic token styles of [theme] as VS Code's editor paints them:
/// `ColorThemeData.getTokenStyleMetadata` encoded by
/// `SemanticTokensProviderStyling`, cached per type, modifiers and language.
/// [semanticHighlightingEnabled] is `editor.semanticHighlighting.enabled`;
/// by default the theme decides (its `semanticHighlighting`), and a theme
/// without it styles nothing.
IdeSemanticTokenStyler ideSemanticTokenStyler(
  ColorThemeData theme, {
  Object semanticHighlightingEnabled = semanticHighlightingConfiguredByTheme,
}) {
  if (!isSemanticColoringEnabled(
    semanticHighlightingEnabled,
    theme.semanticHighlighting,
  )) {
    return (type, modifiers, languageId) => null;
  }
  final styles = ColorThemeTokenStyles(theme);
  final colorMap = [
    for (final color in theme.tokenColorMap)
      color == null ? null : _flutterColor(vs.Color.fromHex(color)),
  ];
  final cache = <String, IdeTokenStyle?>{};
  return (type, modifiers, languageId) {
    final key = '$languageId\u0000$type\u0000${modifiers.join('\u0000')}';
    if (cache.containsKey(key)) return cache[key];
    final metadata = semanticTokenStyleToMetadata(
      styles.getTokenStyleMetadata(type, modifiers.toList(), languageId),
    );
    return cache[key] = IdeTokenStyle.fromMetadata(metadata, colorMap);
  };
}

Color _flutterColor(vs.Color color) => Color.fromARGB(
  (color.rgba.a * 255).round(),
  color.rgba.r,
  color.rgba.g,
  color.rgba.b,
);

/// The editor's default color theme (`workbench.colorTheme`):
/// `ThemeSettingDefaults.colorThemeDark`.
const String ideDefaultColorThemeId = 'Bao Dark';

// The stylers, not futures of them: a future answers in the zone it was made
// in, which may be gone (a widget test's fake async zone).
final Map<AssetBundle, IdeSemanticTokenStyler> _defaultStylers = {};

/// [ideDefaultColorThemeId]'s styler, from the bundled theme files (read
/// through [bundle], by default [rootBundle]); loaded once per bundle.
Future<IdeSemanticTokenStyler> ideDefaultSemanticTokenStyler({
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  final loaded = _defaultStylers[assets];
  if (loaded != null) return loaded;
  // `loadString` decodes large files in another isolate.
  Future<String> read(String path) async {
    final data = await assets.load('$textMateAssetRoot/$path');
    return utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  final manifest = await TextMateManifest.load(read);
  final contribution = manifest.themeById(ideDefaultColorThemeId);
  if (contribution == null) {
    throw StateError('No bundled theme $ideDefaultColorThemeId');
  }
  final theme = ColorThemeData.fromExtensionTheme(
    contribution,
    contribution.assetPath,
    extensionId: contribution.extensionId,
  );
  await theme.ensureLoaded(read);
  return _defaultStylers[assets] ??= ideSemanticTokenStyler(theme);
}

/// Semantic tokens of one document version, styled and grouped by
/// zero-based line.
class IdeSemanticTokens {
  /// [languageId] is the document's (VS Code's) language id, which theme
  /// rules may select.
  IdeSemanticTokens(
    this.snapshot,
    List<LspSemanticToken> tokens, {
    required IdeSemanticTokenStyler styler,
    String languageId = 'plaintext',
  }) {
    for (final token in tokens) {
      if (token.length <= 0) continue;
      final style = styler(token.type, token.modifiers, languageId);
      if (style == null) continue;
      _byLine.putIfAbsent(token.line, () => []).add((
        token.character,
        token.character + token.length,
        style,
      ));
    }
    for (final list in _byLine.values) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
    }
  }

  /// The text the tokens describe.
  final DocumentSnapshot snapshot;
  final Map<int, List<(int, int, IdeTokenStyle)>> _byLine = {};

  /// No token changes a style (none arrived, or the theme styles none).
  bool get isEmpty => _byLine.isEmpty;

  String _lineText(int line) => snapshot.text.substring(
    snapshot.lineStarts[line],
    snapshot.contentEnds[line],
  );

  /// Syntax spans [base] (keyed by one-based line) restyled by the tokens.
  /// A line whose text differs from the tokens' keeps its syntax styles
  /// until newer tokens arrive, so typing never waits for the server.
  Map<int, List<TextSpan>> overlay(Map<int, List<TextSpan>>? base) =>
      _SemanticStyledLines(this, base);
}

class _SemanticStyledLines extends MapBase<int, List<TextSpan>> {
  _SemanticStyledLines(this._tokens, this._base);

  final IdeSemanticTokens _tokens;
  final Map<int, List<TextSpan>>? _base;
  final Map<int, (List<TextSpan>?, List<TextSpan>?)> _cache = {};

  @override
  List<TextSpan>? operator [](Object? key) {
    if (key is! int) return null;
    final base = _base?[key];
    final line = key - 1;
    final tokens = _tokens._byLine[line];
    if (tokens == null || line >= _tokens.snapshot.lineCount) return base;
    final cached = _cache[key];
    if (cached != null && identical(cached.$1, base)) return cached.$2;
    final result = _restyle(base, _tokens._lineText(line), tokens);
    _cache[key] = (base, result);
    return result;
  }

  static const _none = IdeTokenStyle();

  static List<TextSpan>? _restyle(
    List<TextSpan>? base,
    String text,
    List<(int, int, IdeTokenStyle)> tokens,
  ) {
    final spans = base ?? [TextSpan(text: text)];
    final buffer = StringBuffer();
    for (final span in spans) {
      buffer.write(span.text ?? '');
    }
    if (buffer.toString() != text) return base;
    final result = <TextSpan>[];
    var offset = 0;
    var t = 0;
    for (final span in spans) {
      final spanText = span.text ?? '';
      final spanEnd = offset + spanText.length;
      var at = offset;
      while (at < spanEnd) {
        while (t < tokens.length && tokens[t].$2 <= at) {
          t++;
        }
        final (tokenStart, tokenEnd, style) = t < tokens.length
            ? tokens[t]
            : (spanEnd, spanEnd, _none);
        if (tokenStart > at) {
          final end = tokenStart < spanEnd ? tokenStart : spanEnd;
          result.add(
            TextSpan(
              text: spanText.substring(at - offset, end - offset),
              style: span.style,
            ),
          );
          at = end;
        } else {
          final end = tokenEnd < spanEnd ? tokenEnd : spanEnd;
          result.add(
            TextSpan(
              text: spanText.substring(at - offset, end - offset),
              style: style.applyTo(span.style),
            ),
          );
          at = end;
        }
      }
      offset = spanEnd;
    }
    return List.unmodifiable(result);
  }

  @override
  Iterable<int> get keys => {
    ...?_base?.keys,
    for (final line in _tokens._byLine.keys) line + 1,
  };

  @override
  void operator []=(int key, List<TextSpan> value) =>
      throw UnsupportedError('read-only');

  @override
  void clear() => throw UnsupportedError('read-only');

  @override
  List<TextSpan>? remove(Object? key) => throw UnsupportedError('read-only');
}
