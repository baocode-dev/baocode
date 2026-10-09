/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The queries of `workspace.findFiles`, `findTextInFiles` and
// `workspaceContains`: folder queries with the folders' `files.exclude`
// and `search.exclude`, ignore-file and symlink settings, and the
// include and exclude patterns extensions give.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/search/common/queryBuilder.ts (`QueryBuilder`
// `text`, `file`, `commonQuery`, `getContentPattern`, `isCaseSensitive`,
// `isMultiline`, `parseSearchPaths`, `expandSearchPathPatterns`,
// `expandOneSearchPath`, `resolveOneSearchPathPattern`,
// `getFolderQueryForSearchPath`, `getFolderQueryForRoot`, the module's
// helpers), src/vs/workbench/services/search/common/search.ts
// (`getExcludes`, `QueryType`), src/vs/base/common/glob.ts
// (`splitGlobAware`), src/vs/base/common/strings.ts
// (`containsUppercaseCharacter`), src/vs/editor/common/model/
// textModelSearch.ts (`isMultilineRegexSource`).
//
// Deviations:
// - No `onlyOpenEditors` or `changedFileUris` queries (the search view's,
//   not the extension API's).
// - Notebook search options are passed through unchanged.
// - The settings' upstream defaults apply when no default is registered.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../configuration/configuration_service.dart';
import '../files/file_service.dart' show uriBasename, uriEqual;
import '../workspace/workspace_context.dart';

/// `QueryType`.
abstract final class QueryType {
  static const file = 1;
  static const text = 2;
  static const aiText = 3;
}

/// Upstream's defaults of the settings the queries read.
const searchSettingDefaults = <String, Object?>{
  'files.exclude': {
    '**/.git': true,
    '**/.svn': true,
    '**/.hg': true,
    '**/.DS_Store': true,
    '**/Thumbs.db': true,
  },
  'search.exclude': {
    '**/node_modules': true,
    '**/bower_components': true,
    '**/*.code-search': true,
  },
  'search.useIgnoreFiles': true,
  'search.useGlobalIgnoreFiles': false,
  'search.useParentIgnoreFiles': false,
  'search.followSymlinks': true,
  'editor.wordSeparators': r"`~!@#$%^&*()-=+[{]}\|;:'" '",.<>/?',
};

/// One folder and its glob expression (`ISearchPathPattern`).
typedef SearchPathPattern = ({VsUri searchPath, Map<String, Object?>? pattern});

/// `ISearchPathsInfo`.
typedef SearchPathsInfo = ({
  List<SearchPathPattern>? searchPaths,
  Map<String, Object?>? pattern,
});

/// `QueryBuilder`: queries as JSON (`ISearchQuery` with URI components,
/// what the extension host's providers take as `IRawQuery`).
final class QueryBuilder {
  QueryBuilder({
    required this.configuration,
    required this.workspace,
    this.userHome,
    this.isAbsolutePath = _posixAbsolute,
  });

  final ConfigurationService configuration;
  final WorkspaceContextService workspace;

  /// For `~/` in search paths.
  final String? userHome;
  final bool Function(String path) isAbsolutePath;

  static bool _posixAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);

  Object? _setting(String key, VsUri? resource) =>
      configuration.getValue(key, resource: resource) ??
      searchSettingDefaults[key];

  /// `text`.
  Map<String, Object?> text(
    Map<String, Object?> contentPattern,
    List<VsUri> folders, [
    Map<String, Object?> options = const {},
  ]) {
    final pattern = _contentPattern(contentPattern, options);
    final common = _commonQuery(folders, options);
    final disregardExcludes = options['disregardExcludeSettings'] == true;
    final disregardIgnore = options['disregardIgnoreFiles'] == true;
    return {
      ...common,
      'type': QueryType.text,
      'contentPattern': pattern,
      'previewOptions': ?options['previewOptions'],
      'maxFileSize': ?options['maxFileSize'],
      'surroundingContext': ?options['surroundingContext'],
      'userDisabledExcludesAndIgnoreFiles':
          disregardExcludes && disregardIgnore,
    };
  }

  /// `file`.
  Map<String, Object?> file(
    List<VsUri> folders, [
    Map<String, Object?> options = const {},
  ]) {
    final common = _commonQuery(folders, options);
    final filePattern = options['filePattern'] as String?;
    return {
      ...common,
      'type': QueryType.file,
      'filePattern': ?filePattern?.trim(),
      'exists': ?options['exists'],
      'sortByScore': ?options['sortByScore'],
      'cacheKey': ?options['cacheKey'],
      'shouldGlobMatchFilePattern': ?options['shouldGlobSearch'],
    };
  }

  Map<String, Object?> _contentPattern(
    Map<String, Object?> input,
    Map<String, Object?> options,
  ) {
    var pattern = '${input['pattern'] ?? ''}';
    final isRegExp = input['isRegExp'] == true;
    if (isRegExp) pattern = pattern.replaceAll(RegExp(r'\r?\n'), r'\n');
    final result = <String, Object?>{
      ...input,
      'pattern': pattern,
      'wordSeparators': _setting('editor.wordSeparators', null),
    };
    if (_isCaseSensitive(pattern, isRegExp, input, options)) {
      result['isCaseSensitive'] = true;
    }
    if (input['isMultiline'] == true ||
        isRegExp && isMultilineRegexSource(pattern) ||
        pattern.contains('\n')) {
      result['isMultiline'] = true;
    }
    final notebook = options['notebookSearchConfig'];
    if (notebook is Map) {
      final info = <String, Object?>{
        ...?(result['notebookInfo'] as Map?)?.cast<String, Object?>(),
      };
      if (notebook['includeMarkupInput'] == true) {
        info['isInNotebookMarkdownInput'] = true;
      }
      if (notebook['includeMarkupPreview'] == true) {
        info['isInNotebookMarkdownPreview'] = true;
      }
      if (notebook['includeCodeInput'] == true) {
        info['isInNotebookCellInput'] = true;
      }
      if (notebook['includeOutput'] == true) {
        info['isInNotebookCellOutput'] = true;
      }
      if (info.isNotEmpty) result['notebookInfo'] = info;
    }
    return result;
  }

  bool _isCaseSensitive(
    String pattern,
    bool isRegExp,
    Map<String, Object?> input,
    Map<String, Object?> options,
  ) {
    if (options['isSmartCase'] == true) {
      if (containsUppercaseCharacter(pattern, ignoreEscapedChars: isRegExp)) {
        return true;
      }
    }
    return input['isCaseSensitive'] == true;
  }

  /// `handleIncludeExclude`.
  SearchPathsInfo _handleIncludeExclude(Object? pattern, bool expand) {
    if (pattern == null) return (searchPaths: null, pattern: null);
    List<String> patterns;
    if (pattern is List) {
      patterns = [
        for (final p in pattern)
          if ('$p'.isNotEmpty) _normalizeSlashes('$p'),
      ];
      if (patterns.isEmpty) return (searchPaths: null, pattern: null);
    } else {
      final s = '$pattern';
      if (s.isEmpty) return (searchPaths: null, pattern: null);
      patterns = [_normalizeSlashes(s)];
    }
    if (expand) {
      return parseSearchPaths(pattern is List ? patterns : patterns.single);
    }
    return (searchPaths: null, pattern: _patternListToExpression(patterns));
  }

  Map<String, Object?> _commonQuery(
    List<VsUri> folders,
    Map<String, Object?> options,
  ) {
    final excludeBuilders = [
      for (final e in (options['excludePattern'] as List?) ?? const [])
        if (e is Map) e.cast<String, Object?>(),
    ];
    Object? excludePatterns = options['excludePattern'] is List
        ? [
            for (final e in excludeBuilders)
              ...switch (e['pattern']) {
                final List<Object?> l => l.map((x) => '$x'),
                final Object o => ['$o'],
                null => const <String>[],
              },
          ]
        : options['excludePattern'];
    if (excludePatterns is List && excludePatterns.length == 1) {
      excludePatterns = excludePatterns.single;
    }
    final expand = options['expandPatterns'] == true;
    final include = _handleIncludeExclude(options['includePattern'], expand);
    final exclude = _handleIncludeExclude(excludePatterns, expand);
    final includeFolderName = folders.length > 1;
    final usingSearchPaths = include.searchPaths?.isNotEmpty ?? false;
    final folderQueries = [
      if (usingSearchPaths)
        for (final sp in include.searchPaths!)
          ?_folderQueryForSearchPath(sp, options, excludeBuilders, exclude)
      else
        for (final folder in folders)
          ?_folderQueryForRoot(
            folder,
            options,
            excludeBuilders,
            exclude,
            includeFolderName,
          ),
    ];
    return {
      '_reason': ?options['_reason'],
      'folderQueries': folderQueries,
      'usingSearchPaths': usingSearchPaths,
      'excludePattern': ?exclude.pattern,
      'includePattern': ?include.pattern,
      'ignoreGlobCase': ?options['ignoreGlobCase'],
      'onlyOpenEditors': ?options['onlyOpenEditors'],
      'maxResults': ?options['maxResults'],
      'onlyFileScheme': ?options['onlyFileScheme'],
      'extraFileResources': ?_extraFiles(options),
    };
  }

  List<Object?>? _extraFiles(Map<String, Object?> options) {
    final extra = options['extraFileResources'];
    return extra is List && extra.isNotEmpty ? extra : null;
  }

  /// `parseSearchPaths`: `./a`, `../a` and absolute paths are search
  /// paths; anything else a glob anywhere (`foo` → `**/foo/**`,
  /// `**/foo`).
  SearchPathsInfo parseSearchPaths(Object pattern) {
    bool isSearchPath(String segment) =>
        isAbsolutePath(segment) || RegExp(r'^\.\.?([\/\\]|$)').hasMatch(segment);
    final patterns = pattern is List
        ? [for (final p in pattern) '$p']
        : _splitGlobPattern('$pattern');
    final home = userHome;
    final segments = [
      for (final s in patterns)
        home != null && (s == '~' || s.startsWith('~/'))
            ? '$home${s.substring(1)}'
            : s,
    ];
    final searchPathSegments = segments.where(isSearchPath).toList();
    final exprSegments = [
      for (final s in segments.where((s) => !isSearchPath(s)))
        ..._expandGlobalGlob(() {
          var t = _rtrim(_rtrim(s, '/'), r'\');
          if (t.startsWith('.')) t = '*$t';
          return t;
        }()),
    ];
    final searchPaths = _expandSearchPathPatterns(searchPathSegments);
    return (
      searchPaths: searchPaths.isEmpty ? null : searchPaths,
      pattern: _patternListToExpression(exprSegments),
    );
  }

  Map<String, Object?>? _excludesForFolder(
    VsUri folder,
    Map<String, Object?> options,
  ) {
    if (options['disregardExcludeSettings'] == true) return null;
    return getExcludes(
      _setting('files.exclude', folder),
      options['disregardSearchExcludeSettings'] == true
          ? null
          : _setting('search.exclude', folder),
    );
  }

  List<SearchPathPattern> _expandSearchPathPatterns(List<String> searchPaths) {
    if (searchPaths.isEmpty) return const [];
    final expanded = <({VsUri searchPath, String? pattern})>[];
    for (final searchPath in searchPaths) {
      var (:pathPortion, :globPortion) = _splitGlobFromPath(searchPath);
      if (globPortion != null) globPortion = _normalizeGlobPattern(globPortion);
      for (final one in _expandOneSearchPath(pathPortion)) {
        expanded.addAll(_resolveOneSearchPathPattern(one, globPortion));
      }
    }
    final byPath = <String, ({VsUri searchPath, Map<String, Object?>? pattern})>{};
    for (final one in expanded) {
      final key = one.searchPath.toString();
      final existing = byPath[key];
      if (existing != null) {
        if (one.pattern != null) {
          final pattern = {...?existing.pattern, one.pattern!: true};
          byPath[key] = (searchPath: existing.searchPath, pattern: pattern);
        }
      } else {
        byPath[key] = (
          searchPath: one.searchPath,
          pattern: one.pattern == null ? null : {one.pattern!: true},
        );
      }
    }
    return byPath.values.toList();
  }

  List<({VsUri searchPath, String? pattern})> _expandOneSearchPath(
    String searchPath,
  ) {
    final folders = workspace.workspaceFolders;
    if (isAbsolutePath(searchPath)) {
      if (folders.isNotEmpty && folders.first.uri.scheme != 'file') {
        return [
          (searchPath: folders.first.uri.replace(path: searchPath), pattern: null),
        ];
      }
      return [
        (searchPath: VsUri.file(p.normalize(searchPath)), pattern: null),
      ];
    }
    if (workspace.state == WorkbenchState.folder) {
      final workspaceUri = folders.first.uri;
      searchPath = _normalizeSlashes(searchPath);
      if (searchPath.startsWith('../') || searchPath == '..') {
        final resolved = p.posix.normalize(
          p.posix.join(workspaceUri.path, searchPath),
        );
        return [(searchPath: workspaceUri.replace(path: resolved), pattern: null)];
      }
      final cleaned = _normalizeGlobPattern(searchPath);
      return [(searchPath: workspaceUri, pattern: cleaned)];
    }
    if (searchPath == './' || searchPath == r'.\') return const [];
    final withoutDotSlash = searchPath.replaceFirst(RegExp(r'^\.[\/\\]'), '');
    final matches = <({VsUri searchPath, String? pattern})>[];
    for (final folder in folders) {
      final match = RegExp(
        '^${RegExp.escape(folder.name)}(?:/(.*)|\$)',
      ).firstMatch(withoutDotSlash);
      if (match == null) continue;
      final rest = match[1];
      matches.add((
        searchPath: folder.uri,
        pattern: rest == null || rest.isEmpty ? null : _normalizeGlobPattern(rest),
      ));
    }
    if (matches.isNotEmpty) return matches;
    final probable = RegExp(r'\.[\/\\](.+)[\/\\]?').firstMatch(searchPath);
    throw SearchPathNotFoundException(probable?[1] ?? searchPath);
  }

  List<({VsUri searchPath, String? pattern})> _resolveOneSearchPathPattern(
    ({VsUri searchPath, String? pattern}) one,
    String? globPortion,
  ) {
    final pattern = one.pattern != null && globPortion != null
        ? '${one.pattern}/$globPortion'
        : one.pattern ?? globPortion;
    return [
      (searchPath: one.searchPath, pattern: pattern),
      if (pattern != null && !pattern.endsWith('**'))
        (searchPath: one.searchPath, pattern: '$pattern/**'),
    ];
  }

  Map<String, Object?>? _folderQueryForSearchPath(
    SearchPathPattern searchPath,
    Map<String, Object?> options,
    List<Map<String, Object?>> excludeBuilders,
    SearchPathsInfo excludes,
  ) {
    final root = _folderQueryForRoot(
      searchPath.searchPath,
      options,
      excludeBuilders,
      excludes,
      false,
    );
    if (root == null) return null;
    return {...root, 'includePattern': searchPath.pattern};
  }

  Map<String, Object?>? _folderQueryForRoot(
    VsUri folder,
    Map<String, Object?> options,
    List<Map<String, Object?>> excludeBuilders,
    SearchPathsInfo excludes,
    bool includeFolderName,
  ) {
    Map<String, Object?>? thisFolderExcludePattern;
    // Only an exclude's own root when it is not this folder.
    var excludeFolderRoots = <VsUri?>[
      for (final e in excludeBuilders)
        switch (VsUri.tryRevive(e['uri'])) {
          final VsUri root when !uriEqual(root, folder) => root,
          _ => null,
        },
    ];
    if (excludeFolderRoots.isEmpty) excludeFolderRoots = [null];
    if (excludes.searchPaths case final searchPaths?) {
      final thisFolder = searchPaths
          .where((sp) => uriEqual(sp.searchPath, folder))
          .firstOrNull;
      if (thisFolder != null && thisFolder.pattern == null) return null;
      thisFolderExcludePattern = thisFolder?.pattern;
    }
    final settingExcludes = _excludesForFolder(folder, options);
    final excludePattern = <String, Object?>{
      ...?settingExcludes,
      ...?thisFolderExcludePattern,
    };
    final folderName = includeFolderName
        ? (workspace.workspaceFolders
                  .where((f) => uriEqual(f.uri, folder))
                  .firstOrNull
                  ?.name ??
              uriBasename(folder))
        : null;
    bool setting(String key) => _setting(key, folder) == true;
    bool option(String key, bool Function() fallback) =>
        options[key] is bool ? options[key]! as bool : fallback();
    return {
      'folder': folder.toJson(),
      'folderName': ?folderName,
      'excludePattern': [
        if (excludePattern.isNotEmpty)
          for (final root in excludeFolderRoots)
            {'folder': ?root?.toJson(), 'pattern': excludePattern},
      ],
      'fileEncoding': ?_setting('files.encoding', folder),
      'disregardIgnoreFiles': option(
        'disregardIgnoreFiles',
        () => !setting('search.useIgnoreFiles'),
      ),
      'disregardGlobalIgnoreFiles': option(
        'disregardGlobalIgnoreFiles',
        () => !setting('search.useGlobalIgnoreFiles'),
      ),
      'disregardParentIgnoreFiles': option(
        'disregardParentIgnoreFiles',
        () => !setting('search.useParentIgnoreFiles'),
      ),
      'ignoreSymlinks': option(
        'ignoreSymlinks',
        () => !setting('search.followSymlinks'),
      ),
      'ignoreGlobCase': ?options['ignoreGlobCase'],
    };
  }
}

/// A search path naming no workspace folder.
final class SearchPathNotFoundException implements Exception {
  const SearchPathNotFoundException(this.folderName);

  final String folderName;

  @override
  String toString() => 'Workspace folder does not exist: $folderName';
}

/// `getExcludes`: `files.exclude` with `search.exclude` over it.
Map<String, Object?>? getExcludes(Object? fileExcludes, Object? searchExcludes) {
  final files = fileExcludes is Map ? fileExcludes.cast<String, Object?>() : null;
  final search =
      searchExcludes is Map ? searchExcludes.cast<String, Object?>() : null;
  if (files == null && search == null) return null;
  if (files == null || search == null) return {...?files, ...?search};
  return {...files, ...search};
}

/// `strings.containsUppercaseCharacter`.
bool containsUppercaseCharacter(String target, {bool ignoreEscapedChars = false}) {
  if (target.isEmpty) return false;
  if (ignoreEscapedChars) target = target.replaceAll(RegExp(r'\\.'), '');
  return target.toLowerCase() != target;
}

/// `isMultilineRegexSource`.
bool isMultilineRegexSource(String searchString) {
  for (var i = 0; i < searchString.length; i++) {
    final c = searchString.codeUnitAt(i);
    if (c == 0x0A) return true;
    if (c == 0x5C) {
      i++;
      if (i >= searchString.length) break;
      final next = searchString.codeUnitAt(i);
      if (next == 0x6E || next == 0x72 || next == 0x57) return true;
    }
  }
  return false;
}

/// `glob.splitGlobAware`.
List<String> splitGlobAware(String pattern, String splitChar) {
  if (pattern.isEmpty) return const [];
  final segments = <String>[];
  var inBraces = false;
  var inBrackets = false;
  final current = StringBuffer();
  for (final char in pattern.split('')) {
    if (char == splitChar && !inBraces && !inBrackets) {
      segments.add(current.toString());
      current.clear();
      continue;
    }
    switch (char) {
      case '{':
        inBraces = true;
      case '}':
        inBraces = false;
      case '[':
        inBrackets = true;
      case ']':
        inBrackets = false;
    }
    current.write(char);
  }
  if (current.isNotEmpty) segments.add(current.toString());
  return segments;
}

List<String> _splitGlobPattern(String pattern) => [
  for (final s in splitGlobAware(pattern, ','))
    if (s.trim().isNotEmpty) s.trim(),
];

({String pathPortion, String? globPortion}) _splitGlobFromPath(
  String searchPath,
) {
  final globChar = RegExp(r'[\*\{\}\(\)\[\]\?]').firstMatch(searchPath);
  if (globChar != null) {
    final before = searchPath.substring(0, globChar.start);
    final lastSlash = RegExp(r'[/|\\][^/\\]*$').firstMatch(before);
    if (lastSlash != null) {
      var pathPortion = searchPath.substring(0, lastSlash.start);
      if (!RegExp(r'[/\\]').hasMatch(pathPortion)) pathPortion += '/';
      return (
        pathPortion: pathPortion,
        globPortion: searchPath.substring(lastSlash.start + 1),
      );
    }
  }
  return (pathPortion: searchPath, globPortion: null);
}

Map<String, Object?>? _patternListToExpression(List<String> patterns) =>
    patterns.isEmpty ? null : {for (final p in patterns) p: true};

List<String> _expandGlobalGlob(String pattern) => [
  for (final p in ['**/$pattern/**', '**/$pattern']) p.replaceAll('**/**', '**'),
];

String _normalizeSlashes(String pattern) => pattern.replaceAll(r'\', '/');

String _normalizeGlobPattern(String pattern) => _normalizeSlashes(
  pattern,
).replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'/+$'), '');

String _rtrim(String s, String needle) {
  while (s.endsWith(needle) && s.isNotEmpty) {
    s = s.substring(0, s.length - needle.length);
  }
  return s;
}

/// `escapeGlobPattern`.
String escapeGlobPattern(String path) =>
    path.replaceAllMapped(RegExp(r'([?*[\]])'), (m) => '[${m[1]}]');
