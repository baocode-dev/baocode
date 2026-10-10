import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/search/query_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/main_thread_harness.dart';

/// The extension host's search providers, as a test sees them: the main
/// thread asks `$provideFileSearchResults`/`$provideTextSearchResults`,
/// and the extension host answers by sending `$handleFileMatch`/
/// `$handleTextMatch` back with the same session.
void main() {
  late Directory temp;
  late MainThreadHarness harness;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bao-mt-search');
  });

  tearDown(() async {
    harness.dispose();
    await temp.delete(recursive: true);
  });

  test(r'$registerFileSearchProvider routes a query for its scheme',
      () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadSearch,
      r'$registerFileSearchProvider',
      [1, 'memfs'],
    );
    expect(harness.search.hasProvider('memfs', QueryType.file), isTrue);

    final uri = VsUri('memfs', path: '/a.txt');
    harness.answer(
      ExtHostContext.extHostSearch,
      r'$provideFileSearchResults',
      (args) async {
        final (handle, session) = (args[0], args[1]);
        await harness.call(
          MainContext.mainThreadSearch,
          r'$handleFileMatch',
          [handle, session, [uri.toJson()]],
        );
        return {'limitHit': true};
      },
    );
    harness.answer(ExtHostContext.extHostSearch, r'$clearCache', (_) async {
      cleared.add('cache-key');
      return null;
    });

    final complete = await harness.search.fileSearch({
      'type': QueryType.file,
      'folderQueries': [
        {'folder': uri.toJson()},
      ],
    });
    expect(complete.limitHit, isTrue);
    expect(complete.results.single['resource'], uri.toJson());

    await harness.search.clearCache('cache-key');
    expect(cleared, ['cache-key']);
  });

  test('a text search streams its file matches to the caller', () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadSearch,
      r'$registerTextSearchProvider',
      [2, 'memfs'],
    );
    final uri = VsUri('memfs', path: '/b.txt');
    harness.answer(
      ExtHostContext.extHostSearch,
      r'$provideTextSearchResults',
      (args) async {
        await harness.call(
          MainContext.mainThreadSearch,
          r'$handleTextMatch',
          [
            args[0],
            args[1],
            [
              {
                'resource': uri.toJson(),
                'results': [
                  {
                    'preview': {'text': 'hit'},
                  },
                ],
              },
            ],
          ],
        );
        return {'limitHit': false};
      },
    );

    final streamed = <Map<String, Object?>>[];
    final complete = await harness.search.textSearch({
      'type': QueryType.text,
      'folderQueries': [
        {'folder': uri.toJson()},
      ],
    }, CancellationToken.none, streamed.add);
    expect(streamed.single['resource'], uri.toJson());
    expect(complete.results.single['resource'], uri.toJson());
    expect(complete.results.single['results'], isA<List>());
  });

  test('a match for an unknown provider fails, as upstream throws', () async {
    harness = MainThreadHarness(folder: temp);
    await expectLater(
      harness.call(
        MainContext.mainThreadSearch,
        r'$handleFileMatch',
        [
          99,
          1,
          [VsUri('memfs', path: '/a.txt').toJson()],
        ],
      ),
      throwsA(
        isA<RpcRemoteError>().having(
          (e) => e.message,
          'message',
          contains('unknown provider'),
        ),
      ),
    );
  });

  test(r'$unregisterProvider stops answering', () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadSearch,
      r'$registerTextSearchProvider',
      [2, 'memfs'],
    );
    expect(harness.search.hasProvider('memfs', QueryType.text), isTrue);
    await harness.call(MainContext.mainThreadSearch, r'$unregisterProvider', [
      2,
    ]);
    expect(harness.search.hasProvider('memfs', QueryType.text), isFalse);
  });

  test('a second provider for a scheme replaces the first, as upstream',
      () async {
    // A remote project's two extension hosts both register
    // `vscode-userdata`.
    harness = MainThreadHarness(folder: temp);
    for (final handle in [4, 5]) {
      await harness.call(
        MainContext.mainThreadSearch,
        r'$registerTextSearchProvider',
        [handle, 'vscode-userdata'],
      );
    }
    final asked = <Object?>[];
    harness.answer(
      ExtHostContext.extHostSearch,
      r'$provideTextSearchResults',
      (args) async {
        asked.add(args[0]);
        return {'limitHit': false};
      },
    );
    final query = {
      'type': QueryType.text,
      'folderQueries': [
        {'folder': VsUri('vscode-userdata', path: '/u').toJson()},
      ],
    };
    await harness.search.textSearch(query, CancellationToken.none, (_) {});
    expect(asked, [5]);
    // Unregistering the replaced one leaves the one that replaced it.
    await harness.call(MainContext.mainThreadSearch, r'$unregisterProvider', [
      4,
    ]);
    expect(
      harness.search.hasProvider('vscode-userdata', QueryType.text),
      isTrue,
    );
  });

  test('an AI provider is registered for its scheme', () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadSearch,
      r'$registerAITextSearchProvider',
      [3, 'memfs'],
    );
    expect(harness.search.hasProvider('memfs', QueryType.aiText), isTrue);
    // Its AI name is asked for through `$getAIName`.
    harness.answer(ExtHostContext.extHostSearch, r'$getAIName', (args) async {
      expect(args.single, 3);
      return 'memfs AI';
    });
    expect(harness.search.hasProvider('memfs', QueryType.aiText), isTrue);
  });
}

/// What `$clearCache` was asked for.
final cleared = <String>[];
