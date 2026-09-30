// The TextMate asset manifest: the grammar, language and color theme
// contributions of the VS Code extensions bundled in assets/textmate/, as
// tool/generate_textmate_assets.mjs copies them from each extension's
// package.json (with `%label%` placeholders localized from package.nls.json).
// Paths in the manifest are relative to assets/textmate/; see
// [TextMateThemeContribution] for the model's theme paths.

import 'dart:convert';

import '../monaco/vs/workbench/services/text_mate/common/tm_grammars.dart';
import '../monaco/vs/workbench/services/themes/common/workbench_theme_service.dart';

/// Where the generator writes the assets, as Flutter bundles them.
const String textMateAssetRoot = 'assets/textmate';

class TextMateManifest {
  const TextMateManifest({
    required this.revision,
    required this.grammars,
    required this.languages,
    required this.themes,
  });

  factory TextMateManifest.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> entries(String key) {
      final value = json[key];
      if (value is! List) {
        throw FormatException('TextMate manifest: $key is not a list');
      }
      return value.cast<Map<String, Object?>>();
    }

    final revision = json['revision'];
    if (revision is! String) {
      throw const FormatException('TextMate manifest: no revision');
    }
    return TextMateManifest(
      revision: revision,
      grammars: [
        for (final entry in entries('grammars'))
          TextMateGrammarContribution.fromJson(entry),
      ],
      languages: [
        for (final entry in entries('languages'))
          TextMateLanguageRegistration.fromJson(entry),
      ],
      themes: [
        for (final entry in entries('themes'))
          TextMateThemeContribution.fromJson(entry),
      ],
    );
  }

  static TextMateManifest parse(String source) =>
      TextMateManifest.fromJson(jsonDecode(source) as Map<String, Object?>);

  /// Loads `manifest.json` through [read], which takes a path relative to
  /// [textMateAssetRoot] (as every path in the manifest is).
  static Future<TextMateManifest> load(
    Future<String> Function(String path) read,
  ) async => parse(await read('manifest.json'));

  /// The VS Code revision the files come from.
  final String revision;
  final List<TextMateGrammarContribution> grammars;
  final List<TextMateLanguageRegistration> languages;
  final List<TextMateThemeContribution> themes;

  TextMateThemeContribution? themeById(String id) {
    for (final theme in themes) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  TextMateGrammarContribution? grammarForLanguage(String languageId) {
    for (final grammar in grammars) {
      if (grammar.language == languageId) return grammar;
    }
    return null;
  }

  TextMateGrammarContribution? grammarForScope(String scopeName) {
    for (final grammar in grammars) {
      if (grammar.scopeName == scopeName) return grammar;
    }
    return null;
  }

  TextMateLanguageRegistration? languageById(String id) {
    for (final language in languages) {
      if (language.id == id) return language;
    }
    return null;
  }
}

/// A `contributes.grammars` entry; [path] is relative to the asset root.
class TextMateGrammarContribution extends ITMSyntaxExtensionPoint {
  const TextMateGrammarContribution({
    required this.extension,
    super.language,
    required super.scopeName,
    required super.path,
    super.embeddedLanguages,
    super.tokenTypes,
    super.injectTo,
    super.balancedBracketScopes,
    super.unbalancedBracketScopes,
  });

  factory TextMateGrammarContribution.fromJson(Map<String, Object?> json) {
    final grammar = ITMSyntaxExtensionPoint.fromJson(json);
    return TextMateGrammarContribution(
      extension: _string(json, 'extension'),
      language: grammar.language,
      scopeName: grammar.scopeName,
      path: grammar.path,
      embeddedLanguages: grammar.embeddedLanguages,
      tokenTypes: grammar.tokenTypes,
      injectTo: grammar.injectTo,
      balancedBracketScopes: grammar.balancedBracketScopes,
      unbalancedBracketScopes: grammar.unbalancedBracketScopes,
    );
  }

  /// The VS Code extension (its directory under `extensions/`).
  final String extension;
}

/// A `contributes.languages` entry; [configuration] is relative to the asset
/// root.
class TextMateLanguageRegistration {
  const TextMateLanguageRegistration({
    required this.extension,
    required this.id,
    this.aliases = const [],
    this.extensions = const [],
    this.filenames = const [],
    this.filenamePatterns = const [],
    this.firstLine,
    this.mimetypes = const [],
    this.configuration,
  });

  factory TextMateLanguageRegistration.fromJson(Map<String, Object?> json) =>
      TextMateLanguageRegistration(
        extension: _string(json, 'extension'),
        id: _string(json, 'id'),
        aliases: _strings(json['aliases']),
        extensions: _strings(json['extensions']),
        filenames: _strings(json['filenames']),
        filenamePatterns: _strings(json['filenamePatterns']),
        firstLine: json['firstLine'] as String?,
        mimetypes: _strings(json['mimetypes']),
        configuration: json['configuration'] as String?,
      );

  final String extension;
  final String id;
  final List<String> aliases;

  /// File extensions with their dot (`.ts`).
  final List<String> extensions;
  final List<String> filenames;
  final List<String> filenamePatterns;

  /// A regular expression (JavaScript syntax) for the first line.
  final String? firstLine;
  final List<String> mimetypes;

  /// The language-configuration.json file.
  final String? configuration;
}

/// A `contributes.themes` entry with its label localized. Unlike the other
/// contributions, [path] is the theme file relative to its extension (as
/// `contributes.themes` names it, normalized), since
/// `ColorThemeData.fromExtensionTheme` builds the theme's id from it; the
/// file to read is [assetPath].
class TextMateThemeContribution extends IThemeExtensionPoint {
  const TextMateThemeContribution({
    required this.extension,
    required super.id,
    required String super.label,
    required super.path,
    required this.assetPath,
    super.uiTheme,
  });

  /// The manifest's `path` is the asset path, `themes/<extension>/<path>`.
  factory TextMateThemeContribution.fromJson(Map<String, Object?> json) {
    final extension = _string(json, 'extension');
    final assetPath = _string(json, 'path');
    final prefix = 'themes/$extension/';
    if (!assetPath.startsWith(prefix)) {
      throw FormatException(
        'TextMate manifest: theme $assetPath is not under $prefix',
      );
    }
    return TextMateThemeContribution(
      extension: extension,
      id: _string(json, 'id'),
      label: _string(json, 'label'),
      path: assetPath.substring(prefix.length),
      assetPath: assetPath,
      uiTheme: json['uiTheme'] as String?,
    );
  }

  final String extension;

  /// The theme file relative to [textMateAssetRoot]: the location to hand
  /// `ColorThemeData.fromExtensionTheme` with a reader of the assets.
  final String assetPath;

  @override
  String get label => super.label!;

  /// VS Code's id for the built-in extension (`vscode.<name>`), which
  /// `ColorThemeData.fromExtensionTheme` builds the theme's CSS id from.
  String get extensionId => 'vscode.$extension';
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('TextMate manifest: $key is not a string: $value');
  }
  return value;
}

List<String> _strings(Object? value) =>
    value == null ? const [] : (value as List).cast<String>();
