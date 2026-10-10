import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/search/query_builder.dart';
import 'package:baocode/extensions/workspace/workspace_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _File extends ChangeNotifier implements SettingsFile {
  _File([Map<String, Object?>? values]) : values = values ?? {};

  @override
  Map<String, Object?> values;

  @override
  Future<void> write(List<String> path, Object? value) async =>
      values[path.single] = value;
}

void main() {
  late WorkspaceContextService workspace;
  late ConfigurationService configuration;
  late QueryBuilder builder;

  void build({
    List<(String, String)> folders = const [('/w/one', 'one')],
    Map<String, Object?> settings = const {},
    bool multiRoot = false,
  }) {
    workspace = WorkspaceContextService(
      ExtHostWorkspace(
        id: 'id',
        name: 'w',
        folders: [
          for (final (i, (path, name)) in folders.indexed)
            ExtHostWorkspaceFolder(VsUri.file(path), name, i),
        ],
      ),
      isMultiRoot: multiRoot,
    );
    configuration = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: _File(settings),
    );
    builder = QueryBuilder(
      configuration: configuration,
      workspace: workspace,
      userHome: '/home/me',
    );
  }

  setUp(() => build());

  test('a file query carries the folder, the include and the maxResults', () {
    final query = builder.file([VsUri.file('/w/one')], {
      'includePattern': '**/*.ts',
      'maxResults': 2000,
      '_reason': 'startFileSearch',
    });
    expect(query['type'], QueryType.file);
    expect(query['maxResults'], 2000);
    expect(query['includePattern'], {'**/*.ts': true});
    expect(query['usingSearchPaths'], isFalse);
    final folderQuery = (query['folderQueries'] as List).single as Map;
    expect((folderQuery['folder']! as Map)['path'], '/w/one');
    expect(folderQuery['folderName'], isNull);
    expect(folderQuery['ignoreSymlinks'], isFalse);
  });

  test('an exclude pattern becomes the folder\'s exclude, as upstream',
      () {
    // `findFiles('**/*.ts', {exclude: '**/node_modules/**'})`.
    final query = builder.file([VsUri.file('/w/one')], {
      'excludePattern': [
        {'pattern': '**/node_modules/**'},
      ],
    });
    // As upstream: the extension's exclude is the query's own (searched
    // for with `pathIncludedInQuery`), the folder query's only the
    // settings'.
    expect(query['excludePattern'], containsPair('**/node_modules/**', true));
    final folderQuery = (query['folderQueries'] as List).single as Map;
    final excludes = (folderQuery['excludePattern'] as List).single as Map;
    expect(
      (excludes['pattern']! as Map).containsKey('**/node_modules/**'),
      isFalse,
    );
  });

  test('files.exclude and search.exclude are merged into the folder query',
      () {
    build(
      settings: {
        'files.exclude': {'**/.git': true, 'build/**': true},
        'search.exclude': {'**/out': true},
      },
    );
    final query = builder.file([VsUri.file('/w/one')], {});
    final folderQuery = (query['folderQueries'] as List).single as Map;
    final pattern =
        ((folderQuery['excludePattern'] as List).single as Map)['pattern']!
            as Map;
    expect(pattern.keys, containsAll(['**/.git', 'build/**', '**/out']));
  });

  test('the search exclude settings can be left out', () {
    build(
      settings: {
        'files.exclude': {'**/.git': true},
        'search.exclude': {'**/out': true},
      },
    );
    final query = builder.file([VsUri.file('/w/one')], {
      'disregardSearchExcludeSettings': true,
    });
    final folderQuery = (query['folderQueries'] as List).single as Map;
    final pattern =
        ((folderQuery['excludePattern'] as List).single as Map)['pattern']!
            as Map;
    expect(pattern.keys, ['**/.git']);
  });

  test('disregardExcludeSettings drops the excludes altogether', () {
    build(
      settings: {
        'files.exclude': {'**/.git': true},
      },
    );
    final query = builder.file([VsUri.file('/w/one')], {
      'disregardExcludeSettings': true,
    });
    final folderQuery = (query['folderQueries'] as List).single as Map;
    expect(folderQuery['excludePattern'], isEmpty);
  });

  test('the ignore-file and symlink settings reach the folder query', () {
    build(
      settings: {
        'search.useIgnoreFiles': false,
        'search.useGlobalIgnoreFiles': true,
        'search.followSymlinks': false,
      },
    );
    final query = builder.file([VsUri.file('/w/one')], {});
    final folderQuery = (query['folderQueries'] as List).single as Map;
    expect(folderQuery['disregardIgnoreFiles'], isTrue);
    expect(folderQuery['disregardGlobalIgnoreFiles'], isFalse);
    expect(folderQuery['ignoreSymlinks'], isTrue);

    // The extension's option wins over the setting.
    final override = builder.file([VsUri.file('/w/one')], {
      'disregardIgnoreFiles': false,
      'ignoreSymlinks': false,
    });
    final overrideQuery =
        ((override['folderQueries'] as List).single as Map);
    expect(overrideQuery['disregardIgnoreFiles'], isFalse);
    expect(overrideQuery['ignoreSymlinks'], isFalse);
  });

  test('a multi-folder workspace names each folder query', () {
    build(
      folders: [('/w/one', 'one'), ('/w/two', 'two')],
      multiRoot: true,
    );
    final query = builder.file([
      VsUri.file('/w/one'),
      VsUri.file('/w/two'),
    ], {});
    expect(
      [
        for (final f in query['folderQueries'] as List)
          (f as Map)['folderName'],
      ],
      ['one', 'two'],
    );
  });

  test('a text query carries the pattern and its options', () {
    final query = builder.text(
      {'pattern': 'Foo', 'isRegExp': false},
      [VsUri.file('/w/one')],
      {'isSmartCase': true, 'disregardExcludeSettings': true},
    );
    expect(query['type'], QueryType.text);
    final pattern = query['contentPattern']! as Map;
    expect(pattern['pattern'], 'Foo');
    // Smart case: an upper-case pattern is case sensitive.
    expect(pattern['isCaseSensitive'], true);
    expect(pattern['wordSeparators'], isNotEmpty);
    // Only `disregardExcludeSettings` is set, so upstream's flag is
    // `undefined` here.
    expect(query['userDisabledExcludesAndIgnoreFiles'], isNot(true));
  });

  test('a lower-case smart-case pattern stays case insensitive', () {
    final query = builder.text(
      {'pattern': 'foo', 'isRegExp': false},
      [VsUri.file('/w/one')],
      {'isSmartCase': true},
    );
    expect(
      (query['contentPattern']! as Map)['isCaseSensitive'],
      isNull,
      reason: 'not set: the provider decides',
    );
  });

  test('a multi-line regular expression is marked multiline', () {
    final query = builder.text(
      {'pattern': r'a\nb', 'isRegExp': true},
      [VsUri.file('/w/one')],
      {},
    );
    final pattern = query['contentPattern']! as Map;
    expect(pattern['isMultiline'], isTrue);
    // `\r?\n` becomes `\n`, as upstream normalizes it.
    expect(pattern['pattern'], r'a\nb');
  });

  test('../ and ./ search paths name folders and patterns', () {
    // `findFiles('./src/**')` in a folder's project: the folder, with the
    // pattern.
    final query = builder.file([VsUri.file('/w/one')], {
      'includePattern': './src/**',
      'expandPatterns': true,
    });
    expect(query['usingSearchPaths'], isTrue);
    final folderQuery = (query['folderQueries'] as List).single as Map;
    expect((folderQuery['folder']! as Map)['path'], '/w/one');
    expect(folderQuery['includePattern'], {'src/**': true});
  });

  test('a plain include pattern is expanded to anywhere under the folder',
      () {
    final paths = builder.parseSearchPaths('foo/bar,*.ts');
    expect(paths.searchPaths, isNull);
    expect(
      (paths.pattern ?? {}).keys,
      containsAll(['**/foo/bar/**', '**/foo/bar', '**/*.ts/**', '**/*.ts']),
    );
  });

  test('an absolute include pattern becomes its own search path', () {
    final paths = builder.parseSearchPaths('/w/one/src/**');
    expect(paths.searchPaths, hasLength(1));
    expect(paths.searchPaths!.single.searchPath.fsPath(), '/w/one/src');
    expect(paths.searchPaths!.single.pattern, {'**': true});
    expect(paths.pattern, isNull);

    // Without a trailing `**`, the pattern also matches what is under it.
    final both = builder.parseSearchPaths('/w/one/src/*.ts');
    expect(both.searchPaths!.single.pattern, {
      '*.ts': true,
      '*.ts/**': true,
    });
  });

  test('~/ in a search path is the user home', () {
    final paths = builder.parseSearchPaths('~/notes/*.md');
    expect(paths.searchPaths!.single.searchPath.fsPath(), '/home/me/notes');
    expect(paths.searchPaths!.single.pattern, {
      '*.md': true,
      '*.md/**': true,
    });
  });

  test('a search path naming no folder fails as upstream', () {
    build(folders: [('/w/one', 'one'), ('/w/two', 'two')], multiRoot: true);
    expect(
      () => builder.parseSearchPaths('./nope/x'),
      throwsA(isA<SearchPathNotFoundException>()),
    );
    // A folder's name is recognized in a multi-folder workspace.
    final paths = builder.parseSearchPaths('./two/src');
    expect(paths.searchPaths!.single.searchPath.fsPath(), '/w/two');
  });

  test('an exclude with its own root keeps that root', () {
    final query = builder.file([VsUri.file('/w/one')], {
      'excludePattern': [
        {
          'uri': VsUri.file('/w/one/sub').toJson(),
          'pattern': '**/*.map',
        },
      ],
    });
    final folderQuery = (query['folderQueries'] as List).single as Map;
    final exclude = (folderQuery['excludePattern'] as List).single as Map;
    expect((exclude['folder']! as Map)['path'], '/w/one/sub');
  });

  test('getExcludes prefers search.exclude over files.exclude', () {
    final merged = getExcludes({
      'a': true,
      'both': false,
    }, {
      'both': true,
      'b': true,
    });
    expect(merged, {'a': true, 'both': true, 'b': true});
    expect(getExcludes(null, null), isNull);
  });

  test('containsUppercaseCharacter and isMultilineRegexSource', () {
    expect(containsUppercaseCharacter('foo'), isFalse);
    expect(containsUppercaseCharacter('Foo'), isTrue);
    expect(containsUppercaseCharacter(r'\F', ignoreEscapedChars: true), isFalse);
    expect(isMultilineRegexSource(r'a\n'), isTrue);
    expect(isMultilineRegexSource('a'), isFalse);
    expect(isMultilineRegexSource(r'\d+'), isFalse);
  });

  test('splitGlobAware keeps braces whole', () {
    expect(splitGlobAware('{a,b},c', ','), ['{a,b}', 'c']);
  });

  test('escapeGlobPattern escapes wildcards', () {
    expect(escapeGlobPattern('a?.ts'), 'a[?].ts');
    expect(escapeGlobPattern('a[1].ts'), 'a[[]1[]].ts');
  });
}
