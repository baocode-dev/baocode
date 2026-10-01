/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/editor/common/services/languagesRegistry.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (`LanguageIdCodec`,
// `LanguagesRegistry`), with `ILanguageNameIdPair` from
// src/vs/editor/common/languages/language.ts.
// Deviations:
// - Events are listener callbacks ([LanguagesRegistry.onDidChange]); the
//   constructor parameters are named. `_registerLanguages` is
//   [LanguagesRegistry.registerLanguages].
// - Registering override identifiers with the configuration registry is not
//   ported.
// - A language's `configuration` counts as present when non-null (upstream: a
//   URI, always truthy); configuration files and icons are strings.
// - Maps iterate in JavaScript object key order (array-index keys first), and
//   the name sort is stable like `Array.prototype.sort`. Lower-casing uses
//   `jsToLowerCase`. Ids and names are not special-cased for `__proto__`.
// - Invalid first-line expressions are logged with `dart:developer` `log`.
//   First lines are compiled with Dart's `RegExp`, which follows JavaScript
//   (non-unicode) syntax and semantics.

import 'dart:developer' as developer;

import '../../../base/common/ecmascript_lower_case.dart';
import '../../../base/common/lifecycle.dart';
import '../../../base/common/strings.dart';
import '../encoded_token_attributes.dart';
import '../languages/modes_registry.dart';
import '../tokens/line_tokens.dart' show ILanguageIdCodec;
import 'languages_associations.dart';

export '../languages/modes_registry.dart'
    show ILanguageExtensionPoint, ILanguageIcon, plaintextLanguageId;

const String _nullLanguageId = 'vs.editor.nullLanguage';

/// Upstream `ILanguageNameIdPair`.
typedef ILanguageNameIdPair = ({String languageName, String languageId});

class _ResolvedLanguage {
  _ResolvedLanguage(this.identifier);

  final String identifier;
  String? name;
  final List<String> mimetypes = [];
  final List<String> aliases = [];
  List<String> extensions = [];
  final List<String> filenames = [];
  final List<String> configurationFiles = [];
  final List<ILanguageIcon> icons = [];
}

/// Maps language ids to the numbers stored in encoded token metadata.
class LanguageIdCodec implements ILanguageIdCodec {
  LanguageIdCodec() {
    _register(_nullLanguageId, LanguageId.nullId);
    _register(plaintextLanguageId, LanguageId.plainText);
    _nextLanguageId = 2;
  }

  late int _nextLanguageId;
  final List<String?> _languageIdToLanguage = [];
  final Map<String, int> _languageToLanguageId = {};

  void _register(String language, int languageId) {
    while (_languageIdToLanguage.length <= languageId) {
      _languageIdToLanguage.add(null);
    }
    _languageIdToLanguage[languageId] = language;
    _languageToLanguageId[language] = languageId;
  }

  void register(String language) {
    if (_languageToLanguageId.containsKey(language)) return;
    final languageId = _nextLanguageId++;
    _register(language, languageId);
  }

  @override
  int encodeLanguageId(String languageId) =>
      _languageToLanguageId[languageId] ?? LanguageId.nullId;

  @override
  String decodeLanguageId(int languageId) {
    final language =
        languageId >= 0 && languageId < _languageIdToLanguage.length
        ? _languageIdToLanguage[languageId]
        : null;
    // `|| NULL_LANGUAGE_ID`: an empty id is falsy too.
    return language == null || language.isEmpty ? _nullLanguageId : language;
  }
}

/// The languages known to the editor and how files map to them.
class LanguagesRegistry extends Disposable {
  LanguagesRegistry({
    bool useModesRegistry = true,
    bool warnOnOverwrite = false,
  }) : // Named parameters cannot be private initializing formals.
       // ignore: prefer_initializing_formals
       _warnOnOverwrite = warnOnOverwrite,
       languageIdCodec = LanguageIdCodec() {
    instanceCount++;
    if (useModesRegistry) {
      _initializeFromRegistry();
      register(modesRegistry.onDidChangeLanguages(_initializeFromRegistry));
    }
  }

  static int instanceCount = 0;

  final List<void Function()> _onDidChangeListeners = [];
  final bool _warnOnOverwrite;
  final LanguageIdCodec languageIdCodec;
  List<ILanguageExtensionPoint> _dynamicLanguages = [];
  Map<String, _ResolvedLanguage> _languages = {};
  Map<String, String> _mimeTypesMap = {};
  Map<String, String> _nameMap = {};
  Map<String, String> _lowercaseNameMap = {};

  /// Upstream `onDidChange`: calls [listener] after languages change.
  IDisposable onDidChange(void Function() listener) {
    _onDidChangeListeners.add(listener);
    return toDisposable(() => _onDidChangeListeners.remove(listener));
  }

  @override
  void dispose() {
    instanceCount--;
    _onDidChangeListeners.clear();
    super.dispose();
  }

  /// Replaces the extension-contributed languages (the workbench passes all
  /// `contributes.languages`, see WorkbenchLanguageService).
  void setDynamicLanguages(List<ILanguageExtensionPoint> def) {
    _dynamicLanguages = def;
    _initializeFromRegistry();
  }

  void _initializeFromRegistry() {
    _languages = {};
    _mimeTypesMap = {};
    _nameMap = {};
    _lowercaseNameMap = {};

    clearPlatformLanguageAssociations();
    final desc = <ILanguageExtensionPoint>[
      ...modesRegistry.getLanguages(),
      ..._dynamicLanguages,
    ];
    registerLanguages(desc);
  }

  /// Registers [desc] with the core modes registry.
  IDisposable registerLanguage(ILanguageExtensionPoint desc) =>
      modesRegistry.registerLanguage(desc);

  /// Upstream `_registerLanguages`.
  void registerLanguages(List<ILanguageExtensionPoint> desc) {
    for (final d in desc) {
      _registerLanguage(d);
    }

    // Rebuild fast path maps.
    _mimeTypesMap = {};
    _nameMap = {};
    _lowercaseNameMap = {};
    for (final langId in _jsKeys(_languages)) {
      final language = _languages[langId]!;
      final name = language.name;
      if (name != null && name.isNotEmpty) {
        _nameMap[name] = language.identifier;
      }
      for (final alias in language.aliases) {
        _lowercaseNameMap[jsToLowerCase(alias)] = language.identifier;
      }
      for (final mimetype in language.mimetypes) {
        _mimeTypesMap[mimetype] = language.identifier;
      }
    }

    for (final listener in _onDidChangeListeners.toList()) {
      listener();
    }
  }

  void _registerLanguage(ILanguageExtensionPoint lang) {
    final langId = lang.id;
    var resolvedLanguage = _languages[langId];
    if (resolvedLanguage == null) {
      languageIdCodec.register(langId);
      resolvedLanguage = _ResolvedLanguage(langId);
      _languages[langId] = resolvedLanguage;
    }
    _mergeLanguage(resolvedLanguage, lang);
  }

  void _mergeLanguage(
    _ResolvedLanguage resolvedLanguage,
    ILanguageExtensionPoint lang,
  ) {
    final langId = lang.id;

    String? primaryMime;

    final mimetypes = lang.mimetypes;
    if (mimetypes != null && mimetypes.isNotEmpty) {
      resolvedLanguage.mimetypes.addAll(mimetypes);
      primaryMime = mimetypes[0];
    }

    if (primaryMime == null || primaryMime.isEmpty) {
      primaryMime = 'text/x-$langId';
      resolvedLanguage.mimetypes.add(primaryMime);
    }

    final extensions = lang.extensions;
    if (extensions != null) {
      if (lang.configuration != null) {
        // Insert first as this appears to be the 'primary' definition.
        resolvedLanguage.extensions = [
          ...extensions,
          ...resolvedLanguage.extensions,
        ];
      } else {
        resolvedLanguage.extensions = [
          ...resolvedLanguage.extensions,
          ...extensions,
        ];
      }
      for (final extension in extensions) {
        registerPlatformLanguageAssociation(
          ILanguageAssociation(
            id: langId,
            mime: primaryMime,
            extension: extension,
          ),
          _warnOnOverwrite,
        );
      }
    }

    final filenames = lang.filenames;
    if (filenames != null) {
      for (final filename in filenames) {
        registerPlatformLanguageAssociation(
          ILanguageAssociation(
            id: langId,
            mime: primaryMime,
            filename: filename,
          ),
          _warnOnOverwrite,
        );
        resolvedLanguage.filenames.add(filename);
      }
    }

    final filenamePatterns = lang.filenamePatterns;
    if (filenamePatterns != null) {
      for (final filenamePattern in filenamePatterns) {
        registerPlatformLanguageAssociation(
          ILanguageAssociation(
            id: langId,
            mime: primaryMime,
            filepattern: filenamePattern,
          ),
          _warnOnOverwrite,
        );
      }
    }

    final firstLine = lang.firstLine;
    if (firstLine != null && firstLine.isNotEmpty) {
      var firstLineRegexStr = firstLine;
      if (firstLineRegexStr[0] != '^') {
        firstLineRegexStr = '^$firstLineRegexStr';
      }
      try {
        final firstLineRegex = RegExp(firstLineRegexStr);
        if (!regExpLeadsToEndlessLoop(firstLineRegex)) {
          registerPlatformLanguageAssociation(
            ILanguageAssociation(
              id: langId,
              mime: primaryMime,
              firstline: firstLineRegex,
            ),
            _warnOnOverwrite,
          );
        }
      } on FormatException catch (err) {
        // Most likely, the regex was bad.
        developer.log(
          '[${lang.id}]: Invalid regular expression `$firstLineRegexStr`: ',
          name: 'languagesRegistry',
          error: err,
        );
      }
    }

    resolvedLanguage.aliases.add(langId);

    List<String?>? langAliases;
    final aliases = lang.aliases;
    if (aliases != null) {
      // An empty list signals that this language should not get a name.
      langAliases = aliases.isEmpty ? const [null] : aliases;
    }

    if (langAliases != null) {
      for (final langAlias in langAliases) {
        if (langAlias == null || langAlias.isEmpty) continue;
        resolvedLanguage.aliases.add(langAlias);
      }
    }

    final containsAliases = langAliases != null && langAliases.isNotEmpty;
    if (containsAliases && langAliases[0] == null) {
      // This language should not get a name.
    } else {
      final firstAlias = containsAliases ? langAliases[0] : null;
      final bestName = firstAlias == null || firstAlias.isEmpty
          ? langId
          : firstAlias;
      final name = resolvedLanguage.name;
      if (containsAliases || name == null || name.isEmpty) {
        resolvedLanguage.name = bestName;
      }
    }

    final configuration = lang.configuration;
    if (configuration != null) {
      resolvedLanguage.configurationFiles.add(configuration);
    }

    final icon = lang.icon;
    if (icon != null) resolvedLanguage.icons.add(icon);
  }

  bool isRegisteredLanguageId(String? languageId) {
    if (languageId == null || languageId.isEmpty) return false;
    return _languages.containsKey(languageId);
  }

  List<String> getRegisteredLanguageIds() => _jsKeys(_languages);

  List<ILanguageNameIdPair> getSortedRegisteredLanguageNames() {
    final result = <ILanguageNameIdPair>[
      for (final languageName in _jsKeys(_nameMap))
        (languageName: languageName, languageId: _nameMap[languageName]!),
    ];
    _stableSort(
      result,
      (a, b) => compareIgnoreCase(a.languageName, b.languageName),
    );
    return result;
  }

  String? getLanguageName(String languageId) => _languages[languageId]?.name;

  String? getMimeType(String languageId) {
    final language = _languages[languageId];
    if (language == null) return null;
    final mimetype = language.mimetypes.firstOrNull;
    return mimetype == null || mimetype.isEmpty ? null : mimetype;
  }

  List<String> getExtensions(String languageId) =>
      List.unmodifiable(_languages[languageId]?.extensions ?? const []);

  List<String> getFilenames(String languageId) =>
      List.unmodifiable(_languages[languageId]?.filenames ?? const []);

  ILanguageIcon? getIcon(String languageId) =>
      _languages[languageId]?.icons.firstOrNull;

  List<String> getConfigurationFiles(String languageId) =>
      List.unmodifiable(_languages[languageId]?.configurationFiles ?? const []);

  /// The language id for a name or alias, ignoring case.
  String? getLanguageIdByLanguageName(String languageName) =>
      _lowercaseNameMap[jsToLowerCase(languageName)];

  /// The language id for a mime type (case-sensitive).
  String? getLanguageIdByMimeType(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return null;
    return _mimeTypesMap[mimeType];
  }

  /// The language ids for [resource] and its [firstLine], best first,
  /// followed by `plaintext`; `['unknown']` if nothing matches and `[]`
  /// without a resource and first line.
  List<String> guessLanguageIdByFilepathOrFirstLine(
    Uri? resource, [
    String? firstLine,
  ]) {
    if (resource == null && (firstLine == null || firstLine.isEmpty)) {
      return [];
    }
    return getLanguageIds(resource, firstLine);
  }
}

// `Object.keys` order: array-index keys ascending, then insertion order.
List<String> _jsKeys(Map<String, Object?> object) {
  final indices = <String>[], others = <String>[];
  for (final key in object.keys) {
    (_isArrayIndex(key) ? indices : others).add(key);
  }
  if (indices.isEmpty) return others;
  indices.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return [...indices, ...others];
}

bool _isArrayIndex(String key) {
  if (key.isEmpty || key.length > 10) return false;
  if (key.length > 1 && key.startsWith('0')) return false;
  for (final unit in key.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return int.parse(key) < 0xFFFFFFFF;
}

// A stable sort, like JavaScript's `Array.prototype.sort`.
void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}
