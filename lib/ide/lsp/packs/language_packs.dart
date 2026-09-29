import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../catalog/lsp_catalog_overlay.dart';
import 'lsp_files.dart';

/// A folder of `language-packs/`: languages the editor highlights with a
/// Monarch grammar and edits with a language configuration, and optionally
/// the language servers that serve them. The format is in README.md.
class LanguagePack {
  const LanguagePack({
    required this.name,
    required this.directory,
    required this.languages,
    this.servers = const [],
  });

  final String name;
  final String directory;
  final List<LanguagePackLanguage> languages;
  final List<LanguagePackServer> servers;
}

class LanguagePackLanguage {
  const LanguagePackLanguage({
    required this.id,
    required this.pack,
    this.extensions = const [],
    this.filenames = const [],
    this.aliases = const [],
    this.firstLine,
    this.shebangs = const [],
    this.rootMarkers = const [],
    this.languageId,
    this.grammarPath,
    this.configurationPath,
  });

  final String id;

  /// The pack's name.
  final String pack;

  /// With the leading dot, as Monaco registers them (`.zig`).
  final List<String> extensions;
  final List<String> filenames;
  final List<String> aliases;

  /// A pattern the first line matches, as Monaco's `firstLine`.
  final String? firstLine;
  final List<String> shebangs;
  final List<String> rootMarkers;

  /// The LSP `languageId`, when it is not [id].
  final String? languageId;

  /// The Monarch grammar and language configuration files; null when the
  /// pack has none for this language.
  final String? grammarPath;
  final String? configurationPath;
}

/// A server a pack brings: its `lsp.json`-shaped [definition] and the
/// pack languages it serves.
class LanguagePackServer {
  const LanguagePackServer(this.id, this.definition, this.languages);

  final String id;
  final Map<String, Object?> definition;
  final List<String> languages;
}

/// The language packs in [directory], read once and kept until [reload].
///
/// [instance] is what the editor's `MonacoLanguageAssets` and the catalog
/// use by default: the app data folder's `language-packs/` (none on the
/// web or under `flutter test`); tests replace it or pass their own.
class LanguagePackRegistry {
  LanguagePackRegistry(this.directory, {LspFiles? files})
    : _files = files ?? LspFiles.local();

  /// `language-packs/` in [dataDirectory].
  LanguagePackRegistry.inDataDirectory(String dataDirectory, {LspFiles? files})
    : this(p.join(dataDirectory, folderName), files: files);

  static const folderName = 'language-packs';
  static const manifestFile = 'manifest.json';
  static const grammarFile = 'grammar.json';
  static const configurationFile = 'configuration.json';
  static const serverFile = 'server.json';

  static LanguagePackRegistry? _instance;

  static LanguagePackRegistry get instance =>
      _instance ??= switch (lspDataDirectory()) {
        final dir? => LanguagePackRegistry.inDataDirectory(dir),
        null => LanguagePackRegistry(null),
      };

  /// Replaces [instance]; null goes back to the app data folder's packs.
  static set instance(LanguagePackRegistry? registry) => _instance = registry;

  /// Where the packs are; null: there are none.
  final String? directory;
  final LspFiles _files;
  Future<List<LanguagePack>>? _packs;
  final Map<String, Future<Object?>> _json = {};
  List<LspCatalogProblem> _problems = const [];

  /// What the last read skipped: unreadable manifests, bad entries.
  List<LspCatalogProblem> get problems => _problems;

  Future<List<LanguagePack>> packs() => _packs ??= _read();

  /// Forgets what was read, so the next use reads the folder again.
  void reload() {
    _packs = null;
    _json.clear();
  }

  /// A pack file's JSON (a grammar or configuration), read once.
  Future<Object?> readJson(String path) => _json.putIfAbsent(path, () async {
    final text = await _files.readString(path);
    if (text == null) throw FormatException('Missing language pack file', path);
    return jsonDecode(text);
  });

  /// The packs' languages and servers as a catalog layer.
  LspCatalogOverlay get catalogOverlay => _PackOverlay(this);

  Future<List<LanguagePack>> _read() async {
    final dir = directory;
    if (dir == null) return const [];
    final problems = <LspCatalogProblem>[];
    final packs = <LanguagePack>[];
    for (final packDirectory in await _files.directories(dir)) {
      final manifestPath = p.join(packDirectory, manifestFile);
      try {
        final pack = await _readPack(packDirectory, manifestPath, problems);
        if (pack != null) packs.add(pack);
      } on FormatException catch (error) {
        problems.add(LspCatalogProblem(manifestPath, error.message));
      }
    }
    _problems = List.unmodifiable(problems);
    return List.unmodifiable(packs);
  }

  Future<LanguagePack?> _readPack(
    String packDirectory,
    String manifestPath,
    List<LspCatalogProblem> problems,
  ) async {
    final text = await _files.readString(manifestPath);
    if (text == null) {
      problems.add(LspCatalogProblem(manifestPath, 'no manifest.json'));
      return null;
    }
    final manifest = jsonDecode(text);
    if (manifest is! Map || manifest['languages'] is! List) {
      throw const FormatException('expected { "languages": [ … ] }');
    }
    final name = manifest['name'] is String
        ? manifest['name'] as String
        : p.basename(packDirectory);
    final hasGrammar =
        await _files.readString(p.join(packDirectory, grammarFile)) != null;
    final hasConfiguration =
        await _files.readString(p.join(packDirectory, configurationFile)) !=
        null;
    final languages = <LanguagePackLanguage>[];
    for (final (index, raw) in (manifest['languages'] as List).indexed) {
      final where = 'languages[$index]';
      if (raw is! Map ||
          raw['id'] is! String ||
          (raw['id'] as String).isEmpty) {
        problems.add(LspCatalogProblem(manifestPath, '$where: needs an "id"'));
        continue;
      }
      List<String> strings(String key) {
        final value = raw[key];
        if (value == null) return const [];
        if (value is List && value.every((item) => item is String)) {
          return List.unmodifiable(value.cast<String>());
        }
        problems.add(
          LspCatalogProblem(manifestPath, '$where.$key: expected strings'),
        );
        return const [];
      }

      String? file(String key, String fallback, bool fallbackExists) {
        final value = raw[key];
        if (value is String) return p.join(packDirectory, value);
        if (value != null) {
          problems.add(
            LspCatalogProblem(manifestPath, '$where.$key: expected a path'),
          );
        }
        return fallbackExists ? p.join(packDirectory, fallback) : null;
      }

      String? pattern = raw['firstLine'] is String
          ? raw['firstLine'] as String
          : null;
      if (pattern != null) {
        try {
          RegExp(pattern);
        } on FormatException catch (error) {
          problems.add(
            LspCatalogProblem(
              manifestPath,
              '$where.firstLine: ${error.message}',
            ),
          );
          pattern = null;
        }
      }
      languages.add(
        LanguagePackLanguage(
          id: raw['id'] as String,
          pack: name,
          extensions: [
            for (final extension in strings('extensions'))
              extension.startsWith('.') ? extension : '.$extension',
          ],
          filenames: strings('filenames'),
          aliases: strings('aliases'),
          firstLine: pattern,
          shebangs: strings('shebangs'),
          rootMarkers: strings('rootMarkers'),
          languageId: raw['languageId'] is String
              ? raw['languageId'] as String
              : null,
          grammarPath: file('grammar', grammarFile, hasGrammar),
          configurationPath: file(
            'configuration',
            configurationFile,
            hasConfiguration,
          ),
        ),
      );
    }
    return LanguagePack(
      name: name,
      directory: packDirectory,
      languages: List.unmodifiable(languages),
      servers: await _readServers(packDirectory, languages, problems),
    );
  }

  Future<List<LanguagePackServer>> _readServers(
    String packDirectory,
    List<LanguagePackLanguage> languages,
    List<LspCatalogProblem> problems,
  ) async {
    final path = p.join(packDirectory, serverFile);
    final text = await _files.readString(path);
    if (text == null) return const [];
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      problems.add(LspCatalogProblem(path, 'invalid JSON: ${error.message}'));
      return const [];
    }
    final entries = switch (json) {
      {'servers': final List<Object?> servers} => servers,
      final Map<Object?, Object?> single => [single],
      final List<Object?> servers => servers,
      _ => const <Object?>[],
    };
    final servers = <LanguagePackServer>[];
    for (final (index, entry) in entries.indexed) {
      if (entry is! Map || entry['id'] is! String) {
        problems.add(LspCatalogProblem(path, '[$index]: needs an "id"'));
        continue;
      }
      final definition = Map<String, Object?>.of(entry.cast<String, Object?>())
        ..remove('id')
        ..remove('languages');
      final served = entry['languages'];
      servers.add(
        LanguagePackServer(
          entry['id'] as String,
          definition,
          served is List
              ? served.whereType<String>().toList()
              : [for (final language in languages) language.id],
        ),
      );
    }
    return List.unmodifiable(servers);
  }
}

/// Pack languages as `lsp.json` language entries (only what a pack says),
/// and pack servers as server entries serving them.
class _PackOverlay implements LspCatalogOverlay {
  _PackOverlay(this._registry);

  final LanguagePackRegistry _registry;

  @override
  String get name => _registry.directory ?? LanguagePackRegistry.folderName;

  @override
  Future<LspCatalogPatch> read() async {
    _registry.reload();
    final packs = await _registry.packs();
    final languages = <String, Map<String, Object?>>{};
    final servers = <String, Object?>{};
    for (final pack in packs) {
      for (final language in pack.languages) {
        final entry = languages[language.id] ??= {};
        if (language.extensions.isNotEmpty) {
          entry['fileTypes'] = [
            for (final extension in language.extensions) extension.substring(1),
          ];
        }
        if (language.filenames.isNotEmpty) {
          entry['fileNames'] = language.filenames;
        }
        if (language.shebangs.isNotEmpty) {
          entry['shebangs'] = language.shebangs;
        }
        if (language.firstLine != null) {
          entry['firstLine'] = language.firstLine;
        }
        if (language.rootMarkers.isNotEmpty) {
          entry['rootMarkers'] = language.rootMarkers;
        }
        if (language.languageId != null) {
          entry['languageId'] = language.languageId;
        }
      }
      final served = <String, List<String>>{};
      for (final server in pack.servers) {
        servers[server.id] = server.definition;
        for (final language in server.languages) {
          (served[language] ??= []).add(server.id);
        }
      }
      for (final MapEntry(key: language, value: ids) in served.entries) {
        (languages[language] ??= {})['servers'] = ids;
      }
    }
    return LspCatalogPatch(
      servers: servers,
      languages: languages,
      problems: _registry.problems,
    );
  }
}
