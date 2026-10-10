/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Which documents a language feature provider serves, and how well.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/languageSelector.ts (`LanguageFilter`,
// `LanguageSelector`, `score`, `targetsNotebooks`, `selectLanguageIds`).
// Glob matching reuses bao_editor's port of src/vs/base/common/glob.ts.
//
// Deviations:
// - TypeScript's `string | LanguageFilter | Array<…>` union is the sealed
//   [LanguageSelector]: [LanguageIdSelector], [LanguageFilter] and
//   [LanguageSelectorList]; [LanguageSelector.parse] reads the union's JSON.
// - `Uri.fsPath` and path normalization follow bao_editor's `platform.dart`
//   operating system (overridable in tests).

import 'package:bao_editor/monaco/vs/base/common/glob.dart' as glob;
import 'package:bao_editor/monaco/vs/base/common/path.dart' as paths;
import 'package:bao_editor/monaco/vs/base/common/platform.dart' as platform;
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

/// `LanguageSelector`: a language id, a [LanguageFilter], or a list of them.
sealed class LanguageSelector {
  const LanguageSelector();

  /// Reads the upstream union: a string, a filter object (`pattern` a glob
  /// string or `{base, pattern}`), or a list of those.
  static LanguageSelector? parse(Object? json) {
    if (json is String) return LanguageIdSelector(json);
    if (json is List) {
      return LanguageSelectorList([
        for (final item in json) ?LanguageSelector.parse(item),
      ]);
    }
    if (json is Map) {
      final pattern = json['pattern'];
      return LanguageFilter(
        language: json['language'] as String?,
        scheme: json['scheme'] as String?,
        pattern: switch (pattern) {
          final String glob => glob,
          {'base': final String base, 'pattern': final String pattern} =>
            glob.IRelativePattern(base: base, pattern: pattern),
          _ => null,
        },
        notebookType: json['notebookType'] as String?,
        hasAccessToAllModels: json['hasAccessToAllModels'] == true,
        exclusive: json['exclusive'] == true,
        isBuiltin: json['isBuiltin'] == true,
      );
    }
    return null;
  }
}

/// The short-hand `'fooLang'` (`{ language: 'fooLang' }`); `'*'` is any.
final class LanguageIdSelector extends LanguageSelector {
  const LanguageIdSelector(this.languageId);

  final String languageId;
}

/// `LanguageSelector[]`: the best score of its items.
final class LanguageSelectorList extends LanguageSelector {
  const LanguageSelectorList(this.selectors);

  final List<LanguageSelector> selectors;
}

/// `LanguageFilter`.
final class LanguageFilter extends LanguageSelector {
  const LanguageFilter({
    this.language,
    this.scheme,
    this.pattern,
    this.notebookType,
    this.hasAccessToAllModels = false,
    this.exclusive = false,
    this.isBuiltin = false,
  }) : assert(
         pattern == null ||
             pattern is String ||
             pattern is glob.IRelativePattern,
       );

  final String? language;
  final String? scheme;

  /// A glob `String` or an [glob.IRelativePattern], matched on `fsPath`.
  final Object? pattern;
  final String? notebookType;

  /// This provider is implemented in the UI thread.
  final bool hasAccessToAllModels;
  final bool exclusive;

  /// This provider comes from a builtin extension.
  final bool isBuiltin;
}

bool _set(String? value) => value != null && value.isNotEmpty;

/// `score`: 10 for an exact match, 5 for a wildcard match, 0 for none.
int score(
  LanguageSelector? selector,
  VsUri candidateUri,
  String candidateLanguage,
  bool candidateIsSynchronized,
  VsUri? candidateNotebookUri,
  String? candidateNotebookType,
) {
  switch (selector) {
    case LanguageSelectorList(:final selectors):
      // array -> take max individual value
      var ret = 0;
      for (final filter in selectors) {
        final value = score(
          filter,
          candidateUri,
          candidateLanguage,
          candidateIsSynchronized,
          candidateNotebookUri,
          candidateNotebookType,
        );
        if (value == 10) {
          return value; // already at the highest
        }
        if (value > ret) {
          ret = value;
        }
      }
      return ret;

    case LanguageIdSelector(:final languageId):
      if (!candidateIsSynchronized) {
        return 0;
      }
      // short-hand notion, desugars to
      // 'fooLang' -> { language: 'fooLang'}
      // '*' -> { language: '*' }
      if (languageId == '*') {
        return 5;
      } else if (languageId == candidateLanguage) {
        return 10;
      } else {
        return 0;
      }

    case LanguageFilter(
      :final language,
      :final pattern,
      :final scheme,
      :final hasAccessToAllModels,
      :final notebookType,
    ):
      if (!candidateIsSynchronized && !hasAccessToAllModels) {
        return 0;
      }

      // selector targets a notebook -> use the notebook uri instead
      // of the "normal" document uri.
      var uri = candidateUri;
      if (_set(notebookType) && candidateNotebookUri != null) {
        uri = candidateNotebookUri;
      }

      var ret = 0;

      if (_set(scheme)) {
        if (scheme == uri.scheme) {
          ret = 10;
        } else if (scheme == '*') {
          ret = 5;
        } else {
          return 0;
        }
      }

      if (_set(language)) {
        if (language == candidateLanguage) {
          ret = 10;
        } else if (language == '*') {
          ret = ret > 5 ? ret : 5;
        } else {
          return 0;
        }
      }

      if (_set(notebookType)) {
        if (notebookType == candidateNotebookType) {
          ret = 10;
        } else if (notebookType == '*' && candidateNotebookType != null) {
          ret = ret > 5 ? ret : 5;
        } else {
          return 0;
        }
      }

      if (pattern != null && !(pattern is String && pattern.isEmpty)) {
        final Object normalizedPattern;
        if (pattern is glob.IRelativePattern) {
          // Since this pattern has a `base` property, we need
          // to normalize this path first before passing it on
          // because we will compare it against `Uri.fsPath`
          // which uses platform specific separators.
          // Refs: https://github.com/microsoft/vscode/issues/99938
          normalizedPattern = glob.IRelativePattern(
            base: paths.normalize(pattern.base),
            pattern: pattern.pattern,
          );
        } else {
          normalizedPattern = pattern;
        }
        final fsPath = uri.fsPath(windows: platform.isWindows);
        if (normalizedPattern == fsPath ||
            glob.match(normalizedPattern, fsPath)) {
          ret = 10;
        } else {
          return 0;
        }
      }

      return ret;

    case null:
      return 0;
  }
}

/// `targetsNotebooks`.
bool targetsNotebooks(LanguageSelector selector) => switch (selector) {
  LanguageIdSelector() => false,
  LanguageSelectorList(:final selectors) => selectors.any(targetsNotebooks),
  LanguageFilter(:final notebookType) => _set(notebookType),
};

/// `selectLanguageIds`.
void selectLanguageIds(LanguageSelector selector, Set<String> into) {
  switch (selector) {
    case LanguageIdSelector(:final languageId):
      into.add(languageId);
    case LanguageSelectorList(:final selectors):
      for (final item in selectors) {
        selectLanguageIds(item, into);
      }
    case LanguageFilter(:final language):
      if (_set(language)) into.add(language!);
  }
}

/// `isExclusive` (languageFeatureRegistry.ts).
bool isExclusiveSelector(LanguageSelector selector) => switch (selector) {
  LanguageIdSelector() => false,
  LanguageSelectorList(:final selectors) => selectors.every(
    isExclusiveSelector,
  ),
  LanguageFilter(:final exclusive) => exclusive,
};

/// `isBuiltinSelector` (languageFeatureRegistry.ts).
bool isBuiltinSelector(LanguageSelector selector) => switch (selector) {
  LanguageIdSelector() => false,
  LanguageSelectorList(:final selectors) => selectors.any(isBuiltinSelector),
  LanguageFilter(:final isBuiltin) => isBuiltin,
};
