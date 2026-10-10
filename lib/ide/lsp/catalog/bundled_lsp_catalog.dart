import 'dart:convert';

import 'package:flutter/services.dart';

import '../lsp_protocol.dart';
import '../lsp_server_definition.dart';
import 'file_matching.dart';
import 'lsp_catalog_overlay.dart';

/// The languages and servers from Helix's `languages.toml` (bundled as
/// `assets/lsp/languages.json`, see `tool/generate_lsp_languages.mjs`), with
/// [overlays] (language packs, then the user's `lsp.json`) applied on top.
///
/// [load] reads everything; lookups after it are synchronous. Before the
/// first load completes, [languageFor] and [server] find nothing.
///
/// A language may limit a server's features (Helix's `only-features` /
/// `except-features`); it then names a derived server id such as
/// `typescript-language-server#except=diagnostics,format`, which [server]
/// resolves to the base definition with those features limited. Languages
/// with the same limits share the id, so one process serves them.
class BundledLspCatalog implements LspCatalog {
  BundledLspCatalog({
    this._bundle,
    List<LspCatalogOverlay> overlays = const [],
    this._data,
  }) : overlays = List.unmodifiable(overlays);

  static const assetPath = 'assets/lsp/languages.json';

  /// Applied in order over the bundled entries; later ones win.
  final List<LspCatalogOverlay> overlays;
  final AssetBundle? _bundle;

  /// The bundled catalog's JSON instead of [assetPath], e.g. under test.
  final String? _data;

  bool _loaded = false;
  Map<String, Object?> _source = const {};
  List<LspCatalogProblem> _problems = const [];
  Map<String, LspServerDefinition> _servers = const {};
  Map<String, _Language> _languages = const {};
  Map<String, String> _byName = const {};
  Map<String, String> _byExtension = const {};
  Map<String, String> _byExtensionLower = const {};
  Map<String, String> _byShebang = const {};
  List<(LspGlob, String)> _globs = const [];
  List<(RegExp, String)> _firstLines = const [];
  final Map<String, LspServerDefinition?> _derived = {};

  bool get isLoaded => _loaded;

  /// The upstream the bundled entries came from: repository, commit, ….
  Map<String, Object?> get source => _source;

  /// Entries the last [load] skipped, and why.
  List<LspCatalogProblem> get problems => _problems;

  Iterable<LspLanguage> get languages =>
      _languages.values.map((language) => language.language);

  LspLanguage? language(String id) => _languages[id]?.language;

  /// Every server id languages can name (not the derived ones).
  Iterable<String> get serverIds => _servers.keys;

  /// Reads the bundled catalog and every overlay, replacing what an earlier
  /// call read. Overlay problems are collected in [problems]; a bundled
  /// catalog that cannot be read throws.
  Future<void> load() async {
    final text = _data ?? await (_bundle ?? rootBundle).loadString(assetPath);
    final bundled = jsonDecode(text) as Map<String, Object?>;
    final patches = <(String, LspCatalogPatch)>[];
    for (final overlay in overlays) {
      try {
        patches.add((overlay.name, await overlay.read()));
      } on Object catch (error) {
        patches.add((
          overlay.name,
          LspCatalogPatch(
            problems: [LspCatalogProblem(overlay.name, '$error')],
          ),
        ));
      }
    }
    _build(bundled, patches);
  }

  void _build(
    Map<String, Object?> bundled,
    List<(String, LspCatalogPatch)> patches,
  ) {
    final merge = _Merge();
    merge.bundled(bundled);
    for (final (index, (name, patch)) in patches.indexed) {
      merge.problems.addAll(patch.problems);
      merge.overlay(name, index + 1, patch);
    }
    final servers = merge.servers();
    final languages = <String, _Language>{};
    for (final entry in merge.languages.values) {
      final ids = <String>[];
      for (final id in entry.servers) {
        final base = id.split('#').first;
        if (servers.containsKey(base)) {
          ids.add(id);
        } else if (!merge.disabled.contains(base)) {
          merge.problems.add(
            LspCatalogProblem(
              entry.source,
              'language "${entry.id}" names unknown server "$base"',
            ),
          );
        }
      }
      RegExp? firstLine;
      if (entry.firstLine case final pattern?) {
        try {
          firstLine = RegExp(pattern);
        } on FormatException catch (error) {
          merge.problems.add(
            LspCatalogProblem(
              entry.source,
              'language "${entry.id}": bad firstLine: ${error.message}',
            ),
          );
        }
      }
      languages[entry.id] = _Language(
        LspLanguage(
          id: entry.id,
          languageId: entry.languageId,
          fileTypes: List.unmodifiable(entry.fileTypes),
          fileNames: List.unmodifiable(entry.fileNames),
          globs: List.unmodifiable(entry.globs),
          shebangs: List.unmodifiable(entry.shebangs),
          rootMarkers: List.unmodifiable(entry.rootMarkers),
          servers: List.unmodifiable(ids),
        ),
        firstLine,
        entry.layer,
        entry.order,
      );
    }

    // Later layers, then later languages, win a name or extension (Helix's
    // own table keeps the last language to claim one).
    final ordered = languages.values.toList()
      ..sort(
        (a, b) => a.layer != b.layer
            ? a.layer.compareTo(b.layer)
            : a.order.compareTo(b.order),
      );
    final byName = <String, String>{};
    final byExtension = <String, String>{};
    final byExtensionLower = <String, String>{};
    final byShebang = <String, String>{};
    final globs = <(LspGlob, String, int)>[];
    final firstLines = <(RegExp, String)>[];
    for (final entry in ordered) {
      final language = entry.language;
      for (final name in language.fileNames) {
        byName[name] = language.id;
      }
      for (final extension in language.fileTypes) {
        byExtension[extension] = language.id;
        byExtensionLower[extension.toLowerCase()] = language.id;
      }
      for (final interpreter in language.shebangs) {
        byShebang[interpreter] = language.id;
      }
      for (final pattern in language.globs) {
        try {
          globs.add((LspGlob(pattern), language.id, entry.layer));
        } on FormatException catch (error) {
          merge.problems.add(
            LspCatalogProblem(
              'catalog',
              'language "${language.id}": bad glob "$pattern": '
                  '${error.message}',
            ),
          );
        }
      }
      if (entry.firstLine case final pattern?) {
        firstLines.add((pattern, language.id));
      }
    }
    // The latest layer's longest glob wins (Helix: the longest pattern).
    globs.sort(
      (a, b) => a.$3 != b.$3
          ? b.$3.compareTo(a.$3)
          : b.$1.pattern.length.compareTo(a.$1.pattern.length),
    );

    _source = switch (bundled['source']) {
      final Map<String, Object?> source => Map.unmodifiable(source),
      _ => const {},
    };
    _servers = Map.unmodifiable(servers);
    _languages = Map.unmodifiable(languages);
    _byName = byName;
    _byExtension = byExtension;
    _byExtensionLower = byExtensionLower;
    _byShebang = byShebang;
    _globs = [for (final (glob, id, _) in globs) (glob, id)];
    _firstLines = firstLines.reversed.toList();
    _problems = List.unmodifiable(merge.problems);
    _derived.clear();
    _loaded = true;
  }

  /// Exact file name, then globs, then the longest dotted extension
  /// (`a.test.ts`: `test.ts`, then `ts`; exact case, then lower case), then
  /// the `#!` interpreter of [firstLine], then a pack's first-line pattern.
  @override
  LspLanguage? languageFor(String path, {String? firstLine}) {
    final name = baseName(path);
    final id = _byName[name] ?? _globFor(path) ?? _extensionFor(name);
    if (id != null) return _languages[id]?.language;
    for (final interpreter in shebangCandidates(firstLine)) {
      if (_byShebang[interpreter] case final id?) {
        return _languages[id]?.language;
      }
    }
    if (firstLine != null) {
      for (final (pattern, id) in _firstLines) {
        if (pattern.hasMatch(firstLine)) return _languages[id]?.language;
      }
    }
    return null;
  }

  String? _globFor(String path) {
    for (final (glob, id) in _globs) {
      if (glob.matches(path)) return id;
    }
    return null;
  }

  String? _extensionFor(String name) {
    final candidates = extensionCandidates(name);
    for (final extension in candidates) {
      if (_byExtension[extension] case final id?) return id;
    }
    for (final extension in candidates) {
      if (_byExtensionLower[extension.toLowerCase()] case final id?) {
        return id;
      }
    }
    return null;
  }

  @override
  LspServerDefinition? server(String id) {
    final hash = id.indexOf('#');
    if (hash < 0) return _servers[id];
    return _derived.putIfAbsent(id, () {
      final base = _servers[id.substring(0, hash)];
      if (base == null) return null;
      Set<LspFeature>? only = base.onlyFeatures;
      Set<LspFeature>? except = base.exceptFeatures;
      for (final part in id.substring(hash + 1).split(';')) {
        final equals = part.indexOf('=');
        if (equals < 0) continue;
        final features = lspFeaturesFromHelix(
          part.substring(equals + 1).split(',').where((f) => f.isNotEmpty),
        );
        switch (part.substring(0, equals)) {
          case 'only':
            only = only == null ? features : only.intersection(features);
          case 'except':
            except = {...?except, ...features};
        }
      }
      return _copy(base, id: id, onlyFeatures: only, exceptFeatures: except);
    });
  }
}

/// The server id a language names for [server] limited to [only] or
/// without [except] (Helix feature names); [server] itself without limits.
String lspFeatureServerId(
  String server, {
  Iterable<String>? only,
  Iterable<String>? except,
}) {
  final parts = [
    if (only != null) 'only=${(only.toSet().toList()..sort()).join(',')}',
    if (except != null && except.isNotEmpty)
      'except=${(except.toSet().toList()..sort()).join(',')}',
  ];
  return parts.isEmpty ? server : '$server#${parts.join(';')}';
}

/// The [LspFeature]s among Helix feature [names]; names the client has no
/// feature for (`inlay-hints`, `workspace-symbols`, …) are left out.
Set<LspFeature> lspFeaturesFromHelix(Iterable<String> names) => {
  for (final name in names)
    ?switch (name) {
      'rename-symbol' => LspFeature.rename,
      _ => LspFeature.byHelixName(name),
    },
};

LspServerDefinition _copy(
  LspServerDefinition base, {
  required String id,
  Set<LspFeature>? onlyFeatures,
  Set<LspFeature>? exceptFeatures,
}) => LspServerDefinition(
  id: id,
  command: base.command,
  args: base.args,
  environment: base.environment,
  initializationOptions: base.initializationOptions,
  settings: base.settings,
  rootMarkers: base.rootMarkers,
  masonPackage: base.masonPackage,
  requiredRoot: base.requiredRoot,
  onlyFeatures: onlyFeatures,
  exceptFeatures: exceptFeatures,
);

class _Language {
  const _Language(this.language, this.firstLine, this.layer, this.order);

  final LspLanguage language;
  final RegExp? firstLine;
  final int layer;
  final int order;
}

class _LanguageEntry {
  _LanguageEntry(this.id, this.source, this.layer, this.order);

  final String id;
  String source;
  int layer;
  final int order;
  String? languageId;
  List<String> fileTypes = const [];
  List<String> fileNames = const [];
  List<String> globs = const [];
  List<String> shebangs = const [];
  List<String> rootMarkers = const [];
  List<String> servers = const [];
  String? firstLine;
}

class _ServerEntry {
  _ServerEntry(this.id);

  final String id;
  String? command;
  List<String> args = const [];
  Map<String, String> environment = const {};
  JsonMap? initializationOptions;
  JsonMap? settings;
  List<String> rootMarkers = const [];
  String? masonPackage;
  bool requiredRoot = false;
  Set<LspFeature>? onlyFeatures;
  Set<LspFeature>? exceptFeatures;
}

/// Folds the bundled catalog and each overlay's patch into server and
/// language entries, reporting (and skipping) what does not validate.
class _Merge {
  final problems = <LspCatalogProblem>[];
  final languages = <String, _LanguageEntry>{};
  final disabled = <String>{};
  final _servers = <String, _ServerEntry>{};

  Map<String, LspServerDefinition> servers() => {
    for (final entry in _servers.values)
      if (!disabled.contains(entry.id) && entry.command != null)
        entry.id: LspServerDefinition(
          id: entry.id,
          command: entry.command!,
          args: List.unmodifiable(entry.args),
          environment: Map.unmodifiable(entry.environment),
          initializationOptions: entry.initializationOptions,
          settings: entry.settings,
          rootMarkers: List.unmodifiable(entry.rootMarkers),
          masonPackage: entry.masonPackage,
          requiredRoot: entry.requiredRoot,
          onlyFeatures: entry.onlyFeatures,
          exceptFeatures: entry.exceptFeatures,
        ),
  };

  void bundled(Map<String, Object?> json) {
    const source = BundledLspCatalog.assetPath;
    final reader = _Reader(source, problems);
    final servers = json['servers'];
    if (servers is Map) {
      for (final MapEntry(:key, :value) in servers.entries) {
        if (value is! Map) continue;
        final entry = _servers[key as String] = _ServerEntry(key);
        final where = 'servers.$key';
        entry.command = reader.string(value['command'], '$where.command');
        entry.args = reader.strings(value['args'], '$where.args') ?? const [];
        entry.environment =
            reader.stringMap(value['environment'], '$where.environment') ??
            const {};
        // Helix sends `config` as initializationOptions and answers
        // workspace/configuration from it.
        final config = reader.object(value['config'], '$where.config');
        entry.initializationOptions = config;
        entry.settings = config;
        final roots = reader.strings(
          value['requiredRoots'],
          '$where.requiredRoots',
        );
        entry.rootMarkers = roots ?? const [];
        entry.requiredRoot = roots != null;
        entry.masonPackage = reader.string(value['mason'], '$where.mason');
      }
    }
    final list = json['languages'];
    if (list is List) {
      for (final value in list) {
        if (value is! Map || value['id'] is! String) continue;
        final id = value['id'] as String;
        final entry = languages[id] = _LanguageEntry(
          id,
          source,
          0,
          languages.length,
        );
        final where = 'languages.$id';
        entry.languageId = reader.string(
          value['languageId'],
          '$where.languageId',
        );
        entry.fileTypes =
            reader.strings(value['fileTypes'], '$where.fileTypes') ?? const [];
        entry.fileNames =
            reader.strings(value['fileNames'], '$where.fileNames') ?? const [];
        entry.globs =
            reader.strings(value['globs'], '$where.globs') ?? const [];
        entry.shebangs =
            reader.strings(value['shebangs'], '$where.shebangs') ?? const [];
        entry.rootMarkers =
            reader.strings(value['roots'], '$where.roots') ?? const [];
        entry.servers =
            reader.serverRefs(value['servers'], '$where.servers') ?? const [];
      }
    }
  }

  void overlay(String source, int layer, LspCatalogPatch patch) {
    final reader = _Reader(source, problems);
    for (final MapEntry(:key, :value) in patch.servers.entries) {
      final where = 'servers.$key';
      if (value is! Map) {
        reader.problem(where, 'expected an object');
        continue;
      }
      _overlayServer(reader, key, where, value.cast<String, Object?>());
    }
    for (final MapEntry(:key, :value) in patch.languages.entries) {
      final where = 'languages.$key';
      if (value is! Map) {
        reader.problem(where, 'expected an object');
        continue;
      }
      _overlayLanguage(
        reader,
        source,
        layer,
        key,
        where,
        value.cast<String, Object?>(),
      );
    }
  }

  static const _serverKeys = {
    'command',
    'args',
    'environment',
    'config',
    'settings',
    'initializationOptions',
    'rootMarkers',
    'requiredRoot',
    'masonPackage',
    'onlyFeatures',
    'exceptFeatures',
    'disabled',
  };

  void _overlayServer(
    _Reader reader,
    String id,
    String where,
    Map<String, Object?> json,
  ) {
    if (id.contains('#')) {
      reader.problem(where, 'server ids cannot contain "#"');
      return;
    }
    for (final key in json.keys) {
      if (!_serverKeys.contains(key)) reader.problem(where, 'unknown "$key"');
    }
    if (json['disabled'] == true) {
      disabled.add(id);
      return;
    }
    if (json.containsKey('disabled') && json['disabled'] != false) {
      reader.problem('$where.disabled', 'expected true or false');
    }
    final existing = _servers[id];
    final command = reader.string(json['command'], '$where.command');
    if (existing == null && command == null) {
      reader.problem(where, 'a new server needs a "command"');
      return;
    }
    disabled.remove(id);
    final entry = _servers[id] ??= _ServerEntry(id);
    if (command != null) entry.command = command;
    if (reader.strings(json['args'], '$where.args') case final args?) {
      entry.args = args;
    }
    if (reader.stringMap(json['environment'], '$where.environment')
        case final environment?) {
      entry.environment = environment;
    }
    if (reader.object(json['config'], '$where.config') case final config?) {
      entry.initializationOptions = config;
      entry.settings = config;
    }
    if (reader.object(json['settings'], '$where.settings')
        case final settings?) {
      entry.settings = settings;
    }
    if (reader.object(
          json['initializationOptions'],
          '$where.initializationOptions',
        )
        case final options?) {
      entry.initializationOptions = options;
    }
    if (reader.strings(json['rootMarkers'], '$where.rootMarkers')
        case final markers?) {
      entry.rootMarkers = markers;
    }
    if (reader.boolean(json['requiredRoot'], '$where.requiredRoot')
        case final required?) {
      entry.requiredRoot = required;
    }
    if (json.containsKey('masonPackage')) {
      entry.masonPackage = reader.string(
        json['masonPackage'],
        '$where.masonPackage',
      );
    }
    if (reader.strings(json['onlyFeatures'], '$where.onlyFeatures')
        case final only?) {
      entry.onlyFeatures = lspFeaturesFromHelix(only);
    }
    if (reader.strings(json['exceptFeatures'], '$where.exceptFeatures')
        case final except?) {
      entry.exceptFeatures = lspFeaturesFromHelix(except);
    }
  }

  static const _languageKeys = {
    'fileTypes',
    'fileNames',
    'globs',
    'shebangs',
    'servers',
    'rootMarkers',
    'languageId',
    'firstLine',
  };

  void _overlayLanguage(
    _Reader reader,
    String source,
    int layer,
    String id,
    String where,
    Map<String, Object?> json,
  ) {
    for (final key in json.keys) {
      if (!_languageKeys.contains(key)) {
        reader.problem(where, 'unknown "$key"');
      }
    }
    final entry = languages[id] ??= _LanguageEntry(
      id,
      source,
      layer,
      languages.length,
    );
    entry.source = source;
    var matchers = false;
    if (reader.strings(json['fileTypes'], '$where.fileTypes')
        case final types?) {
      entry.fileTypes = [
        for (final type in types)
          type.startsWith('.') ? type.substring(1) : type,
      ];
      matchers = true;
    }
    if (reader.strings(json['fileNames'], '$where.fileNames')
        case final names?) {
      entry.fileNames = names;
      matchers = true;
    }
    if (reader.strings(json['globs'], '$where.globs') case final globs?) {
      entry.globs = globs;
      matchers = true;
    }
    if (reader.strings(json['shebangs'], '$where.shebangs')
        case final shebangs?) {
      entry.shebangs = shebangs;
      matchers = true;
    }
    if (json.containsKey('firstLine')) {
      entry.firstLine = reader.string(json['firstLine'], '$where.firstLine');
      matchers = true;
    }
    if (matchers) entry.layer = layer;
    if (reader.serverRefs(json['servers'], '$where.servers')
        case final servers?) {
      entry.servers = servers;
    }
    if (reader.strings(json['rootMarkers'], '$where.rootMarkers')
        case final markers?) {
      entry.rootMarkers = markers;
    }
    if (json.containsKey('languageId')) {
      entry.languageId = reader.string(json['languageId'], '$where.languageId');
    }
  }
}

/// Typed reads of JSON fields; a wrong type is a problem, read as absent.
class _Reader {
  _Reader(this.source, this.problems);

  final String source;
  final List<LspCatalogProblem> problems;

  void problem(String where, String message) =>
      problems.add(LspCatalogProblem(source, '$where: $message'));

  String? string(Object? value, String where) {
    if (value == null || value is String) return value as String?;
    problem(where, 'expected a string');
    return null;
  }

  bool? boolean(Object? value, String where) {
    if (value == null || value is bool) return value as bool?;
    problem(where, 'expected true or false');
    return null;
  }

  List<String>? strings(Object? value, String where) {
    if (value == null) return null;
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>().toList();
    }
    problem(where, 'expected a list of strings');
    return null;
  }

  Map<String, String>? stringMap(Object? value, String where) {
    if (value == null) return null;
    if (value is Map && value.values.every((item) => item is String)) {
      return value.cast<String, String>();
    }
    problem(where, 'expected an object of strings');
    return null;
  }

  JsonMap? object(Object? value, String where) {
    if (value == null) return null;
    if (value is Map) return value.cast<String, Object?>();
    problem(where, 'expected an object');
    return null;
  }

  /// Server references: ids, or `{ name, only/except… }` feature limits
  /// (`onlyFeatures`, `only-features`, `only`, likewise for except).
  List<String>? serverRefs(Object? value, String where) {
    if (value == null) return null;
    if (value is! List) {
      problem(where, 'expected a list');
      return null;
    }
    final ids = <String>[];
    for (final (index, item) in value.indexed) {
      if (item is String) {
        ids.add(item);
        continue;
      }
      if (item is Map && item['name'] is String) {
        List<String>? features(List<String> keys) {
          for (final key in keys) {
            if (item.containsKey(key)) {
              return strings(item[key], '$where[$index].$key');
            }
          }
          return null;
        }

        final name = item['name'] as String;
        if (name.contains('#')) {
          problem('$where[$index]', 'server ids cannot contain "#"');
          continue;
        }
        ids.add(
          lspFeatureServerId(
            name,
            only: features(const ['onlyFeatures', 'only-features', 'only']),
            except: features(const [
              'exceptFeatures',
              'except-features',
              'except',
            ]),
          ),
        );
        continue;
      }
      problem('$where[$index]', 'expected a server id or { "name": … }');
    }
    return ids;
  }
}
