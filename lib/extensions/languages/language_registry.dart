/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Every language id BaoCode knows, and how a file maps to one: VS Code's
// bundled contributions (bao_editor's TextMate manifest), the user's
// `files.associations`, and the installed extensions'
// `contributes.languages` on top.
//
// The editor's own registry (bao_editor's `LanguagesRegistry`) holds the
// associations, so `getLanguageIds` answers the same way the editor's
// language picking does; this class adds what the extension host needs:
// the extension-contributed languages, the `files.associations` setting,
// the mime/name lookups, and a change notification for
// `ExtHostLanguages.$acceptLanguageIds`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/services/languagesRegistry.ts (`LanguagesRegistry`
// with its `_registerLanguages`, `getRegisteredLanguageIds`,
// `getLanguageName`, `getLanguageIdByLanguageName`, `getMimeType`) and
// `languagesAssociations.ts` (`registerConfiguredLanguageAssociation`),
// src/vs/workbench/services/language/common/languageService.ts
// (`WorkbenchLanguageService` with `_registerExtensions` and its
// `files.associations` handling, `guessLanguageIdByFilepathOrFirstLine`).
//
// Deviations:
// - The bundled languages are not re-registered here: bao_editor's
//   `LanguagesRegistry` already has them (the TextMate manifest), and this
//   class delegates name/mime/first-line lookups to it. `languageIds`
//   answers that registry's ids plus the extensions'.
// - The configuration's `files.associations` is read through
//   [ConfigurationService] instead of being watched by the language
//   service.
// - `unknown` stands in for a resource no association matches, as
//   upstream's `UNKNOWN_LANGUAGE_ID` does.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/services/languages_associations.dart';
import 'package:bao_editor/monaco/vs/editor/common/services/languages_registry.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:flutter/foundation.dart';

import '../configuration/configuration_service.dart';
import 'language_configuration_import.dart';

/// `UNKNOWN_LANGUAGE_ID`.
const String unknownLanguageId = 'unknown';

/// `ILanguageExtensionPoint`s from an extension's `contributes.languages`.
/// A malformed contribution is skipped, as upstream's validation does.
List<ILanguageExtensionPoint> languagePointsFromContribution(
  List<Map<String, Object?>> contributions,
) => [
  for (final contribution in contributions) ?_languagePoint(contribution),
];

ILanguageExtensionPoint? _languagePoint(Map<String, Object?> contribution) {
  try {
    return ILanguageExtensionPoint.fromJson(contribution);
  } on Object {
    return null;
  }
}

/// One language's definition from an extension: the point plus where its
/// files are.
class InstalledLanguage {
  const InstalledLanguage({
    required this.extensionId,
    required this.point,
    this.configurationJson,
    this.configurationPath,
    this.grammarPath,
    this.snippetPaths = const [],
  });

  final String extensionId;
  final ILanguageExtensionPoint point;

  /// The parsed `language-configuration.json`.
  final Map<String, Object?>? configurationJson;
  final String? configurationPath;

  /// The `.tmLanguage.json`/`.plist`/`.tmLanguage` of
  /// `contributes.grammars` for this language.
  final String? grammarPath;

  /// The `contributes.snippets` files for this language.
  final List<String> snippetPaths;
}

/// Every language id and the way each file maps to one.
class LanguageRegistry extends ChangeNotifier {
  LanguageRegistry({this.configuration, this.textMate});

  /// The app's settings (`files.associations`).
  ConfigurationService? configuration;

  /// The TextMate runtime the bundled grammars come from, and the languages
  /// the editor already knows.
  TextMateSyntax? textMate;

  final Map<String, InstalledLanguage> _installed = {};
  final Map<String, _LanguageConfigurationEntry> _configurations = {};
  final _changes = StreamController<int>.broadcast(sync: true);
  int _version = 0;

  /// Answer `TextMateSyntax.languageIdForPath`, which is
  /// `LanguagesRegistry.getLanguageIds` over the bundled manifest; kept so
  /// the two paths can be compared (tests).
  Future<String?> Function(String path, {String? firstLine})? bundledLanguageId;

  /// The editor's own registry, when it is known (tests).
  @visibleForTesting
  LanguagesRegistry? editorRegistry;

  /// Bumped whenever the languages or their associations change.
  int get version => _version;

  /// What changed, for `ExtHostLanguages.$acceptLanguageIds`.
  Stream<int> get changes => _changes.stream;

  /// The languages installed extensions contribute, by language id.
  Map<String, InstalledLanguage> get installed => Map.unmodifiable(_installed);

  /// The `language-configuration.json` contributions, by language id.
  Map<String, Map<String, Object?>> get languageConfigurations => {
    for (final MapEntry(:key, :value) in _configurations.entries)
      key: value.json,
  };

  /// Registers an extension's languages: `contributes.languages` with
  /// their configuration files, grammars and snippets; the configuration
  /// files are read by [readExtensionFiles].
  ///
  /// [extensionId] identifies the extension in messages.
  List<InstalledLanguage> registerExtensionLanguages(
    String extensionId,
    List<Map<String, Object?>> contributions, {
    Map<String, Map<String, Object?>> configurations = const {},
    Map<String, String> grammars = const {},
    Map<String, List<String>> snippets = const {},
    Map<String, String> configurationPaths = const {},
  }) {
    final languages = languagePointsFromContribution(contributions);
    final registered = <InstalledLanguage>[];
    for (final language in languages) {
      final installed = InstalledLanguage(
        extensionId: extensionId,
        point: language,
        configurationJson: configurations[language.id],
        configurationPath: configurationPaths[language.id],
        grammarPath: grammars[language.id],
        snippetPaths: snippets[language.id] ?? const [],
      );
      _installed[language.id] = installed;
      registered.add(installed);
      if (configurations[language.id] case final json?) {
        _configurations[language.id] = _LanguageConfigurationEntry(
          json,
          extensionId,
        );
      }
    }
    _applyAssociations();
    return registered;
  }

  /// Forgets everything [extensionId] contributed.
  void unregisterExtension(String extensionId) {
    var changed = false;
    for (final id in _installed.entries
        .where((entry) => entry.value.extensionId == extensionId)
        .map((entry) => entry.key)
        .toList()) {
      _installed.remove(id);
      _configurations.remove('$id\u0000$extensionId');
      changed = true;
    }
    for (final key in _configurations.keys
        .where((key) => _configurations[key]!.extensionId == extensionId)
        .toList()) {
      _configurations.remove(key);
      changed = true;
    }
    if (changed) _applyAssociations();
  }

  /// The `LanguageConfiguration` an installed extension registered for
  /// [languageId], as [languageConfigurationFromJson] reads it.
  LanguageConfigurationEntry? languageConfigurationOf(String languageId) {
    final entry = _configurations[languageId];
    return entry == null
        ? null
        : LanguageConfigurationEntry(entry.json, entry.extensionId);
  }

  /// `contributes.languages`' points, for the editor's registry.
  List<ILanguageExtensionPoint> get contributedPoints => [
    for (final installed in _installed.values) installed.point,
  ];

  /// The language id [path] (a file path) is opened as, or
  /// [unknownLanguageId]: the associations of the file name, else of
  /// [firstLine].
  String languageIdFor(String path, {String? firstLine}) {
    final ids = languageIdsForPath(path, firstLine: firstLine);
    return ids.isEmpty ? unknownLanguageId : ids.first;
  }

  /// Every language id [path] could be, best first, then `plaintext`.
  List<String> languageIdsForPath(String path, {String? firstLine}) {
    final ids = getLanguageIds(Uri.file(path), firstLine);
    return [
      for (final id in ids)
        if (id != plaintextLanguageId) id,
      if (ids.contains(plaintextLanguageId)) plaintextLanguageId,
    ];
  }

  /// Whether [languageId] is one the editor knows (bundled or
  /// contributed).
  bool isRegistered(String languageId) {
    if (languageId == unknownLanguageId || languageId == plaintextLanguageId) {
      return true;
    }
    if (_installed.containsKey(languageId)) return true;
    return editorRegistry?.isRegisteredLanguageId(languageId) ?? false;
  }

  /// Every registered language id.
  List<String> get languageIds {
    final ids = <String>{
      ...?editorRegistry?.getRegisteredLanguageIds(),
      for (final id in _installed.keys) id,
    };
    ids.remove(plaintextLanguageId);
    return [plaintextLanguageId, ...ids];
  }

  /// The language id for a language's name or alias, ignoring case.
  String? languageIdByName(String name) {
    final known = editorRegistry?.getLanguageIdByLanguageName(name);
    if (known != null) return known;
    final wanted = name.toLowerCase();
    for (final installed in _installed.values) {
      final aliases = installed.point.aliases ?? const <String>[];
      for (final alias in aliases) {
        if (alias.toLowerCase() == wanted) return installed.point.id;
      }
      if (installed.point.id.toLowerCase() == wanted) return installed.point.id;
    }
    return null;
  }

  /// The language's display name.
  String? languageName(String languageId) =>
      _installed[languageId]?.point.aliases?.firstOrNull ??
      editorRegistry?.getLanguageName(languageId);

  /// The language's mime type.
  String? mimeType(String languageId) =>
      _installed[languageId]?.point.mimetypes?.firstOrNull ??
      editorRegistry?.getMimeType(languageId);

  /// The `files.associations` the user configured, as
  /// `registerConfiguredLanguageAssociation` expects them.
  void _applyAssociations() {
    clearConfiguredLanguageAssociations();
    final contributions = <ILanguageAssociation>[];
    final value = configuration?.getValue('files.associations');
    if (value is Map) {
      for (final MapEntry(:key, :value) in value.entries) {
        final id = '$value';
        if (key is String && key.isNotEmpty && id.isNotEmpty) {
          contributions.add(
            ILanguageAssociation(
              id: id,
              mime: 'text/x-$id',
              filepattern: key,
            ),
          );
        }
      }
    }
    // The extensions' languages win over the bundled ones for the same
    // file, as the last registered association wins upstream.
    for (final id in _installed.keys.toList()) {
      final point = _installed[id]!.point;
      for (final filepattern in point.filenamePatterns ?? const <String>[]) {
        contributions.add(
          ILanguageAssociation(
            id: id,
            mime: point.mimetypes?.firstOrNull ?? 'text/x-$id',
            filepattern: filepattern,
          ),
        );
      }
      for (final filename in point.filenames ?? const <String>[]) {
        contributions.add(
          ILanguageAssociation(
            id: id,
            mime: point.mimetypes?.firstOrNull ?? 'text/x-$id',
            filename: filename,
          ),
        );
      }
      for (final extension in point.extensions ?? const <String>[]) {
        contributions.add(
          ILanguageAssociation(
            id: id,
            mime: point.mimetypes?.firstOrNull ?? 'text/x-$id',
            extension: extension,
          ),
        );
      }
    }
    for (final association in contributions) {
      registerConfiguredLanguageAssociation(association);
    }
    _version++;
    _changes.add(_version);
    notifyListeners();
  }

  /// The user's settings changed (`files.associations`).
  void configurationChanged() => _applyAssociations();

  @override
  void dispose() {
    unawaited(_changes.close());
    super.dispose();
  }
}

class _LanguageConfigurationEntry {
  const _LanguageConfigurationEntry(this.json, this.extensionId);

  final Map<String, Object?> json;
  final String extensionId;
}
