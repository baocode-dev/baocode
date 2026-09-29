import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../lsp/packs/language_packs.dart';
import '../vs/editor/standalone/common/monarch/monarch_compile.dart' as monarch;
import '../vs/editor/standalone/common/monarch/monarch_common.dart';
import '../vs/editor/standalone/common/monarch/monarch_types.dart';

/// Data exported from Monaco v0.57.0's original language definitions.
/// Patterns are reconstructed before the pinned Monarch compiler sees them.
///
/// Language packs ([packs], else [LanguagePackRegistry.instance]) add
/// registrations of their own, listed before the bundled ones and preferred
/// over them for the same file; their grammars and configurations use the
/// bundled assets' JSON shape (see `lib/ide/lsp/packs/README.md`).
class MonacoLanguageAssets {
  const MonacoLanguageAssets({this.bundle, this.packs});

  static const revision = 'd61824269f1377111d34306e4a47172327777083';
  static const _base = 'assets/monaco/languages';

  /// Marks a pack registration's [MonacoLanguageRegistration.assetId]:
  /// `pack:<pack name>/<language id>`.
  static const packAssetPrefix = 'pack:';
  final AssetBundle? bundle;
  final LanguagePackRegistry? packs;

  AssetBundle get _assets => bundle ?? rootBundle;
  LanguagePackRegistry get _packs => packs ?? LanguagePackRegistry.instance;

  Future<Map<String, dynamic>> _manifest() async {
    final manifest = jsonDecode(
      await _assets.loadString('$_base/manifest.json'),
    ) as Map<String, dynamic>;
    if (manifest['revision'] != revision) {
      throw const FormatException('Monaco language manifest version mismatch');
    }
    return manifest;
  }

  Future<List<String>> availableLanguages() async {
    final names = ((await _manifest())['grammars'] as List).cast<String>();
    return List<String>.unmodifiable(names);
  }

  /// Pack registrations (those with a grammar) first, then the bundled
  /// ones.
  Future<List<MonacoLanguageRegistration>> registrations() async =>
      List<MonacoLanguageRegistration>.unmodifiable([
        ...(await _packRegistrations()).map((entry) => entry.$1),
        for (final raw in (await _manifest())['registrations'] as List)
          MonacoLanguageRegistration.fromMap(raw as Map<String, dynamic>),
      ]);

  Future<List<(MonacoLanguageRegistration, LanguagePackLanguage)>>
  _packRegistrations() async => [
    for (final pack in await _packs.packs())
      for (final language in pack.languages)
        if (language.grammarPath != null)
          (
            MonacoLanguageRegistration.fromMap({
              'id': language.id,
              'assetId': '$packAssetPrefix${pack.name}/${language.id}',
              'extensions': language.extensions,
              'filenames': language.filenames,
              'aliases': language.aliases,
              'firstLine': language.firstLine,
            }),
            language,
          ),
  ];

  Future<MonacoLanguage> loadRegistered(String languageId) async {
    final registration = (await registrations()).where(
      (r) => r.id == languageId,
    );
    if (registration.isEmpty) {
      throw ArgumentError.value(
        languageId,
        'languageId',
        'Unknown Monaco registration',
      );
    }
    final assetId = registration.first.assetId;
    if (assetId.startsWith(packAssetPrefix)) return _loadPack(languageId);
    final grammar = await load(assetId);
    return MonacoLanguage(
      languageId,
      grammar.definition,
      grammar.configuration,
    );
  }

  /// [languageId]'s grammar: a pack's registration of it, else the bundled
  /// grammar of that name, else the bundled registration's.
  Future<MonacoLanguage> loadLanguage(String languageId) async {
    for (final (registration, _) in await _packRegistrations()) {
      if (registration.id == languageId) return _loadPack(languageId);
    }
    return (await availableLanguages()).contains(languageId)
        ? load(languageId)
        : loadRegistered(languageId);
  }

  Future<MonacoLanguage> _loadPack(String languageId) async {
    final language = (await _packRegistrations())
        .firstWhere((entry) => entry.$1.id == languageId)
        .$2;
    final grammar = await _packs.readJson(language.grammarPath!);
    if (grammar is! Map) {
      throw FormatException(
        'A language pack grammar must be a JSON object',
        language.grammarPath,
      );
    }
    // The bundled assets' whole shape ({language, configuration}) or just
    // the Monarch definition.
    final definition =
        grammar['tokenizer'] == null && grammar['language'] is Map
        ? grammar['language'] as Map
        : grammar;
    if (definition['tokenizer'] is! Map) {
      throw FormatException(
        'A language pack grammar needs a "tokenizer" object',
        language.grammarPath,
      );
    }
    final configuration = language.configurationPath == null
        ? grammar['configuration']
        : await _packs.readJson(language.configurationPath!);
    return MonacoLanguage(
      languageId,
      _restore(definition) as IMonarchLanguage,
      configuration is Map
          ? _restore(configuration) as Map<String, Object?>
          : null,
    );
  }

  /// Resolves pinned filenames/extensions, including registrations whose ID
  /// differs from the grammar's source folder (e.g. C shares the C++ lexer).
  /// Pack registrations come first, so they win a filename, an extension
  /// as long as the best bundled one, and a first line.
  /// The id of the language named [name], by its id or an alias, in any
  /// case (`ILanguageService.getLanguageIdByLanguageName`): how code fences
  /// in markdown name languages.
  Future<String?> languageIdForName(String name) async {
    final lower = name.trim().toLowerCase();
    for (final registration in await registrations()) {
      if (registration.id.toLowerCase() == lower ||
          registration.aliases.any((alias) => alias.toLowerCase() == lower)) {
        return registration.id;
      }
    }
    return null;
  }

  Future<MonacoLanguage?> forPath(String path, {String? firstLine}) async {
    final filename = p.basename(path);
    final lower = filename.toLowerCase();
    final candidates = await registrations();
    for (final registration in candidates) {
      if (registration.filenames.any((name) => name.toLowerCase() == lower)) {
        return loadRegistered(registration.id);
      }
    }
    final byExtension = <(int, int, MonacoLanguageRegistration)>[];
    for (final (index, registration) in candidates.indexed) {
      for (final extension in registration.extensions) {
        if (lower.endsWith(extension.toLowerCase())) {
          byExtension.add((extension.length, index, registration));
        }
      }
    }
    if (byExtension.isNotEmpty) {
      byExtension.sort(
        (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2),
      );
      return loadRegistered(byExtension.first.$3.id);
    }
    if (firstLine != null) {
      for (final registration in candidates) {
        final pattern = registration.firstLinePattern;
        if (pattern != null && RegExp(pattern).hasMatch(firstLine)) {
          return loadRegistered(registration.id);
        }
      }
    }
    return null;
  }

  Future<MonacoLanguage> load(String languageId) async {
    final names = await availableLanguages();
    if (!names.contains(languageId)) {
      throw ArgumentError.value(
        languageId,
        'languageId',
        'Unknown Monaco language',
      );
    }
    final encoded = jsonDecode(
      await _assets.loadString('$_base/$languageId.json'),
    ) as Map<String, dynamic>;
    if (encoded['revision'] != revision ||
        encoded['languageId'] != languageId) {
      throw const FormatException(
        'Monaco language version or identity mismatch',
      );
    }
    return MonacoLanguage(
      languageId,
      _restore(encoded['language']) as IMonarchLanguage,
      _restore(encoded['configuration']) as Map<String, Object?>?,
    );
  }

  Object? _restore(Object? encoded) {
    if (encoded is List) return encoded.map(_restore).toList();
    if (encoded is! Map) return encoded;
    if (encoded.containsKey(r'$regex')) {
      final pattern = encoded[r'$regex'] as String;
      final flags = encoded[r'$flags'] as String;
      return RegExp(
        pattern,
        caseSensitive: !flags.contains('i'),
        multiLine: flags.contains('m'),
        unicode: flags.contains('u'),
        dotAll: flags.contains('s'),
      );
    }
    return <String, Object?>{
      for (final entry in encoded.entries)
        entry.key as String: _restore(entry.value),
    };
  }
}

class MonacoLanguageRegistration {
  MonacoLanguageRegistration.fromMap(Map<String, dynamic> data)
    : id = data['id'] as String,
      assetId = data['assetId'] as String,
      extensions = List<String>.unmodifiable(
        (data['extensions'] as List? ?? const []).cast<String>(),
      ),
      filenames = List<String>.unmodifiable(
        (data['filenames'] as List? ?? const []).cast<String>(),
      ),
      aliases = List<String>.unmodifiable(
        (data['aliases'] as List? ?? const []).cast<String>(),
      ),
      firstLinePattern = data['firstLine'] as String?;

  final String id;
  final String assetId;
  final List<String> extensions;
  final List<String> filenames;
  final List<String> aliases;
  final String? firstLinePattern;
}

class MonacoLanguage {
  const MonacoLanguage(this.id, this.definition, this.configuration);

  final String id;
  final IMonarchLanguage definition;
  final Map<String, Object?>? configuration;

  ILexer compile() => monarch.compile(id, definition);
}
