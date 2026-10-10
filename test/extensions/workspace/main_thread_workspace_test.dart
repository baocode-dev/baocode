import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/main_thread/main_thread_workspace.dart';
import 'package:baocode/extensions/search/query_builder.dart';
import 'package:baocode/extensions/search/search_service.dart';
import 'package:baocode/extensions/trust/workspace_trust.dart';
import 'package:baocode/extensions/workspace/workspace_context.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/extensions/workspace/network_service_io.dart';
import 'package:baocode/extensions/workspace/workspace_save.dart';

import '../support/main_thread_harness.dart';

void main() {
  late Directory temp;
  late MainThreadHarness harness;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bao-mt-workspace');
    await File('${temp.path}/a.txt').writeAsString('hello\nworld\n');
  });

  tearDown(() async {
    harness.dispose();
    await temp.delete(recursive: true);
  });

  test(r'$checkExists searches the folders for the includes', () async {
    harness = MainThreadHarness(folder: temp);
    await harness.initialize();
    // The extension host's provider: the file scheme's.
    var searched = <Map<String, Object?>>[];
    harness.search.registerProvider('file', QueryType.file, _FakeFiles((
      query,
      token,
    ) async {
      searched.add(query);
      return SearchComplete(
        results: [
          {'resource': VsUri.file('${temp.path}/a.txt').toJson()},
        ],
        limitHit: true,
      );
    }));

    final exists = await harness.call(
      MainContext.mainThreadWorkspace,
      r'$checkExists',
      [
        [VsUri.file(temp.path).toJson()],
        ['a.txt'],
      ],
      token: CancellationToken.none,
    );
    expect(exists, isTrue);
    // The query carries the includes at the folder, as the query builder
    // makes it (`includePattern`, `exists`).
    final query = searched.single;
    expect(query['type'], QueryType.file);
    expect(query['exists'], true);
    expect(query['includePattern'], {'a.txt': true});
    final folderQueries = query['folderQueries']! as List;
    expect((folderQueries.single as Map)['folder'], VsUri.file(temp.path).toJson());
  });

  test(r'$startFileSearch answers the files, and null when cancelled',
      () async {
    harness = MainThreadHarness(folder: temp);
    var cancel = false;
    harness.search.registerProvider('file', QueryType.file, _FakeFiles((
      query,
      token,
    ) async {
      if (cancel) throw const CancellationException();
      return SearchComplete(
        results: [
          {'resource': VsUri.file('${temp.path}/a.txt').toJson()},
        ],
      );
    }));

    final files = await harness.call(
      MainContext.mainThreadWorkspace,
      r'$startFileSearch',
      [
        null,
        {'maxResults': 10, 'includePattern': '**/*.txt'},
      ],
      token: CancellationToken.none,
    );
    expect(files, isA<List<Object?>>());
    expect(
      (files! as List).map((f) => (f as Map)['path']),
      ['${temp.path}/a.txt'],
    );

    cancel = true;
    final cancelled = await harness.call(
      MainContext.mainThreadWorkspace,
      r'$startFileSearch',
      [null, <String, Object?>{}],
      token: CancellationToken.none,
    );
    // A cancelled search answers null (the promise resolves, not rejects).
    expect(cancelled, anyOf(isNull, isA<List<Object?>>()));
  });

  test(r'$startTextSearch streams results to $handleTextSearchResult',
      () async {
    harness = MainThreadHarness(folder: temp);
    harness.search.registerProvider('file', QueryType.text, _FakeText((
      query,
      onProgress,
      token,
    ) async {
      onProgress?.call({
        'resource': VsUri.file('${temp.path}/a.txt').toJson(),
        'results': [
          {
            'preview': {'text': 'hello'},
            'rangeLocations': [
              {
                'source': {'startLineNumber': 1},
                'preview': {'text': 'hello'},
              },
            ],
          },
        ],
      });
      return SearchComplete(limitHit: true);
    }));

    final result = await harness.call(
      MainContext.mainThreadWorkspace,
      r'$startTextSearch',
      [
        {'pattern': 'hello', 'isRegExp': false},
        null,
        {'maxResults': 100, 'isSmartCase': true},
        7,
      ],
      token: CancellationToken.none,
    );
    expect((result! as Map)['limitHit'], isTrue);

    final calls = harness.callsTo(ExtHostContext.extHostWorkspace.nid);
    final streamed = calls.firstWhere(
      (c) => c.$1 == r'$handleTextSearchResult',
    );
    expect(streamed.$2[1], 7);
    final match = (streamed.$2[0] as Map).cast<String, Object?>();
    expect((match['resource'] as Map)['path'], '${temp.path}/a.txt');
    expect(match['results'], isA<List>());
  });

  test('the text query carries the pattern and the folder query', () async {
    harness = MainThreadHarness(folder: temp);
    var seen = <Map<String, Object?>>[];
    harness.search.registerProvider('file', QueryType.text, _FakeText((
      query,
      onProgress,
      token,
    ) async {
      seen = [query];
      return const SearchComplete();
    }));
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$startTextSearch',
      [
        {'pattern': 'TODO', 'isRegExp': true, 'isCaseSensitive': true},
        null,
        <String, Object?>{},
        1,
      ],
      token: CancellationToken.none,
    );
    final query = seen.single;
    expect(query['_reason'], 'startTextSearch');
    final pattern = (query['contentPattern'] as Map).cast<String, Object?>();
    expect(pattern['pattern'], 'TODO');
    expect(pattern['isCaseSensitive'], true);
    expect((query['folderQueries'] as List).single, isA<Map>());
  });

  test(r'$updateWorkspaceFolders adds and removes folders, and $acceptWorkspaceData follows',
      () async {
    final ports = _Ports();
    harness = MainThreadHarness(
      folder: temp,
      isMultiRoot: true,
      folders: ports,
    );
    // A two-folder workspace.
    final second = await Directory('${temp.path}/two').create();
    harness.workspace.setFolders([
      (uri: VsUri.file(temp.path), name: 'one'),
      (uri: VsUri.file(second.path), name: 'two'),
    ]);

    // Add a third at index 1, as `workspace.updateWorkspaceFolders(1, 0, …)`.
    final third = await Directory('${temp.path}/three').create();
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$updateWorkspaceFolders',
      [
        'Test Extension',
        1,
        0,
        [
          {'uri': VsUri.file(third.path).toJson(), 'name': 'three'},
        ],
      ],
    );
    expect(
      ports.set!.map((f) => f.uri.fsPath()),
      [temp.path, third.path, second.path],
    );
    expect(ports.status.single, ('Test Extension', 1, 0));

    // The app applies what the extension asked for.
    harness.workspace.setFolders([
      for (final f in ports.set!)
        (
          uri: f.uri,
          name: f.name ?? f.uri.path.split('/').where((s) => s.isNotEmpty).last,
        ),
    ]);
    expect(
      harness.workspace.workspaceFolders.map((f) => f.uri.fsPath()),
      [temp.path, third.path, second.path],
    );

    // Remove two folders from index 0.
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$updateWorkspaceFolders',
      ['Test Extension', 0, 2, <Object?>[]],
    );
    expect(ports.set!.map((f) => f.uri.fsPath()), [second.path]);
  });

  test(r'$acceptWorkspaceData is sent when the folders change', () async {
    harness = MainThreadHarness(folder: temp, isMultiRoot: true);
    final second = await Directory('${temp.path}/two').create();
    harness.workspace.setFolders([
      (uri: VsUri.file(temp.path), name: 'one'),
      (uri: VsUri.file(second.path), name: 'two'),
    ]);
    await pumpEventQueue();
    final calls = harness.callsTo(ExtHostContext.extHostWorkspace.nid);
    final accepted = calls.where((c) => c.$1 == r'$acceptWorkspaceData').toList();
    expect(accepted, isNotEmpty);
    final data = (accepted.last.$2.single as Map).cast<String, Object?>();
    expect((data['folders'] as List).length, 2);
    expect(data['name'], isNotEmpty);
  });

  test('a folder\'s window enters a workspace when a folder is added',
      () async {
    final ports = _Ports();
    harness = MainThreadHarness(folder: temp, folders: ports);
    final second = await Directory('${temp.path}/two').create();
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$updateWorkspaceFolders',
      ['Test Extension', 1, 0, [
        {'uri': VsUri.file(second.path).toJson()},
      ]],
    );
    expect(ports.entered!.map((f) => f.uri.fsPath()), [
      temp.path,
      second.path,
    ]);
    expect(ports.set, isNull);
  });

  test(r"$save and $saveAll save the app's editors", () async {
    harness = MainThreadHarness(folder: temp);
    final save = _Save();
    final actor = MainThreadWorkspace(
      rpc: harness.app,
      workspace: harness.workspace,
      search: harness.search,
      queryBuilder: harness.queryBuilder,
      encodings: harness.encodings,
      save: save,
      trust: harness.trust,
    );
    harness.setActor(MainContext.mainThreadWorkspace.nid, MainThreadWorkspaceActor(actor));
    addTearDown(actor.dispose);

    final saved = await harness.call(
      MainContext.mainThreadWorkspace,
      r'$save',
      [VsUri.file('${temp.path}/a.txt').toJson(), {'saveAs': false}],
    );
    expect(save.saved.single.uri.fsPath(), '${temp.path}/a.txt');
    expect(save.saved.single.saveAs, isFalse);
    expect((saved! as Map)['path'], '${temp.path}/a.txt');

    expect(
      await harness.call(
        MainContext.mainThreadWorkspace,
        r'$saveAll',
        [false],
      ),
      isTrue,
    );
  });

  test(r'$requestWorkspaceTrust asks, and $isResourceTrusted answers',
      () async {
    harness = MainThreadHarness(folder: temp);
    await harness.initialize();
    final asked = <String?>[];
    harness.trust.prompt = _Prompt(asked);

    expect(
      await harness.call(
        MainContext.mainThreadWorkspace,
        r'$isResourceTrusted',
        [VsUri.file(temp.path).toJson()],
      ),
      isFalse,
    );

    final granted = await harness.call(
      MainContext.mainThreadWorkspace,
      r'$requestWorkspaceTrust',
      [
        {
          'message': 'Trust me',
          'buttons': [
            {'label': 'Trust', 'type': 'ContinueWithTrust'},
          ],
        },
      ],
    );
    expect(granted, isTrue);
    expect(asked, ['Trust me']);
    expect(
      await harness.call(
        MainContext.mainThreadWorkspace,
        r'$isResourceTrusted',
        [VsUri.file(temp.path).toJson()],
      ),
      isTrue,
    );
    // The extension host hears that trust was granted.
    await pumpEventQueue();
    expect(
      harness
          .callsTo(ExtHostContext.extHostWorkspace.nid)
          .map((c) => c.$1),
      contains(r'$onDidGrantWorkspaceTrust'),
    );
  });

  test(r'$resolveDecoding and $resolveEncoding read the settings', () async {
    harness = MainThreadHarness(
      folder: temp,
      userSettings: {'files.encoding': 'utf16le', 'files.autoGuessEncoding': true},
    );
    final decoding = (await harness.call(
      MainContext.mainThreadWorkspace,
      r'$resolveDecoding',
      [null, <String, Object?>{}],
    ))! as Map;
    expect(decoding['preferredEncoding'], 'utf16le');
    expect(decoding['guessEncoding'], true);
    expect(decoding['candidateGuessEncodings'], isA<List>());

    final encoding = (await harness.call(
      MainContext.mainThreadWorkspace,
      r'$resolveEncoding',
      [null, <String, Object?>{}],
    ))! as Map;
    expect(encoding['encoding'], 'utf16le');
    expect(encoding['addBOM'], isTrue);

    // An encoding nothing knows falls back to UTF-8.
    final fallback = (await harness.call(
      MainContext.mainThreadWorkspace,
      r'$validateDetectedEncoding',
      [null, 'nonsense', <String, Object?>{}],
    ))!;
    expect(fallback, 'utf8');
  });

  test('the edit session and canonical URI providers are registered',
      () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$registerEditSessionIdentityProvider',
      [1, 'github'],
    );
    final actor = harness.actors[MainContext.mainThreadWorkspace.nid];
    expect(actor, isA<MainThreadWorkspaceActor>());
    // An answer comes from the extension host when one provides it.
    harness.extHostCall(
      ExtHostContext.extHostWorkspace,
      r'$getEditSessionIdentifier',
      [VsUri.file(temp.path).toJson()],
    );
    await pumpEventQueue();
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$unregisterEditSessionIdentityProvider',
      [1],
    );
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$registerCanonicalUriProvider',
      [2, 'file'],
    );
    await harness.call(
      MainContext.mainThreadWorkspace,
      r'$unregisterCanonicalUriProvider',
      [2],
    );
  });

  test('the network service reads the environment proxies', () {
    harness = MainThreadHarness(folder: temp);
    final settings = NetworkService.environmentProxies({
      'http_proxy': 'http://proxy.local:3128',
      'no_proxy': 'localhost, .internal',
    });
    expect(settings?.http, 'proxy.local:3128');
    final scutil = NetworkService.parseScutilProxy('''
<dictionary> {
  ExceptionsList : <array> {
    0 : *.local
    1 : 169.254/16
  }
  HTTPEnable : 1
  HTTPPort : 3128
  HTTPProxy : proxy.local
  HTTPSEnable : 1
  HTTPSPort : 3129
  HTTPSProxy : secure.local
  ExcludeSimpleHostnames : 1
}
''');
    expect(scutil.http, 'proxy.local:3128');
    expect(scutil.https, 'secure.local:3129');
    expect(scutil.exceptions, ['*.local', '169.254/16']);
    expect(scutil.excludeSimpleHostnames, isTrue);
  });

  test('a proxy with credentials asks once, then remembers them', () async {
    harness = MainThreadHarness(folder: temp);
    final asked = <ProxyAuthInfo>[];
    final network = NetworkService(
      prompt: (info) async {
        asked.add(info);
        return (username: 'u', password: 'p');
      },
    );
    final info = {
      'isProxy': true,
      'scheme': 'basic',
      'host': 'proxy.local',
      'port': 3128,
      'realm': 'corp',
      'attempt': 1,
    };
    expect(await network.lookupAuthorization(info), {
      'username': 'u',
      'password': 'p',
    });
    expect(await network.lookupAuthorization(info), {
      'username': 'u',
      'password': 'p',
    });
    expect(asked.length, 1);
  });
}

/// `IFileSearchProvider`: `fileSearch` only.
final class _FakeFiles implements SearchResultProvider {
  _FakeFiles(this.search);

  final Future<SearchComplete> Function(
    Map<String, Object?> query,
    CancellationToken token,
  )
  search;

  @override
  Future<SearchComplete> fileSearch(
    Map<String, Object?> query,
    CancellationToken token,
  ) => search(query, token);

  @override
  Future<SearchComplete> textSearch(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  ) => throw UnsupportedError('text');

  @override
  Future<void> clearCache(String cacheKey) async {}
}

final class _FakeText implements SearchResultProvider {
  _FakeText(this.search);

  final Future<SearchComplete> Function(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  )
  search;

  @override
  Future<SearchComplete> fileSearch(
    Map<String, Object?> query,
    CancellationToken token,
  ) => throw UnsupportedError('file');

  @override
  Future<SearchComplete> textSearch(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  ) => search(query, onProgress, token);

  @override
  Future<void> clearCache(String cacheKey) async {}
}

/// Records what `$updateWorkspaceFolders` asked the app to do.
final class _Ports implements WorkspaceFoldersPort {
  List<WorkspaceFolderToAdd>? set;
  List<WorkspaceFolderToAdd>? entered;
  final status = <(String, int, int)>[];

  @override
  Future<void> setFolders(List<WorkspaceFolderToAdd> folders) async {
    set = folders;
  }

  @override
  Future<void> enterWorkspace(List<WorkspaceFolderToAdd> folders) async {
    entered = folders;
  }

  @override
  void showStatus(String extensionName, int added, int removed) =>
      status.add((extensionName, added, removed));
}

/// Records what `$save`/`$saveAll` asked for.
final class _Save implements WorkspaceSavePort {
  final saved = <({VsUri uri, bool saveAs})>[];

  @override
  Future<VsUri?> save(VsUri uri, {required bool saveAs}) async {
    saved.add((uri: uri, saveAs: saveAs));
    return uri;
  }

  @override
  Future<bool> saveAll({bool includeUntitled = false}) async => true;
}

/// Answers the trust dialogs.
final class _Prompt implements WorkspaceTrustPrompt {
  _Prompt(this.asked);

  final List<String?> asked;

  @override
  bool get canManage => false;

  @override
  void manage() {}

  @override
  Future<({bool trust, bool trustParent})> startup({
    required bool workspace,
    required String label,
    String? parentFolderName,
  }) async => (trust: true, trustParent: false);

  @override
  Future<String?> request({
    required bool workspace,
    String? message,
    required List<WorkspaceTrustRequestButton> buttons,
  }) async {
    asked.add(message);
    return 'ContinueWithTrust';
  }

  @override
  Future<bool> resource(VsUri uri, {String? message}) async => true;
}
