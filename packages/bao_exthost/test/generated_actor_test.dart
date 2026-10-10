// The generated main thread side: actors decode requests into the shapes'
// types, and fallbacks reject what is not implemented, counting it.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Workspace extends MainThreadWorkspaceUnsupported {
  final calls = <List<Object?>>[];

  @override
  Future<List<VsUri>?> $startFileSearch(
    VsUri? includeFolder,
    Map<String, Object?> options,
    CancellationToken token,
  ) async {
    calls.add([includeFolder, options, token]);
    return [VsUri.file('/found')];
  }

  @override
  Future<bool> $checkExists(
    List<VsUri> folders,
    List<String> includes,
    CancellationToken token,
  ) async {
    calls.add([folders, includes, token]);
    return folders.isNotEmpty;
  }
}

final class _Dialogs extends MainThreadDialogsUnsupported {
  Object? options = 'unset';

  @override
  Future<List<VsUri>?> $showOpenDialog(Map<String, Object?>? options) async {
    this.options = options;
    return null;
  }
}

final class _Commands extends MainThreadCommandsUnsupported {
  final registered = <String>[];

  @override
  void $registerCommand(String id) => registered.add(id);
}

void main() {
  setUp(ExtHostParity.instance.reset);

  test('decodes URIs, objects and the cancellation token', () async {
    final workspace = _Workspace();
    final actor = MainThreadWorkspaceActor(workspace);
    final source = CancellationTokenSource();
    final result = await actor.invoke(r'$startFileSearch', [
      {r'$mid': 1, 'scheme': 'file', 'path': '/w s'},
      {'maxResults': 3},
      source.token,
    ]);
    expect(result, [VsUri.file('/found')]);
    final [folder, options, token] = workspace.calls.single;
    expect(folder, VsUri.file('/w s'));
    expect(options, {'maxResults': 3});
    expect(token, same(source.token));

    await actor.invoke(r'$checkExists', [
      [
        {r'$mid': 1, 'scheme': 'file', 'path': '/a'},
        {r'$mid': 1, 'scheme': 'vscode-remote', 'authority': 'h', 'path': '/b'},
      ],
      ['**/x'],
      CancellationToken.none,
    ]);
    expect(workspace.calls.last[0], [
      VsUri.file('/a'),
      VsUri('vscode-remote', authority: 'h', path: '/b'),
    ]);
    expect(workspace.calls.last[1], isA<List<String>>());
  });

  test('nullable and missing trailing arguments are null', () async {
    final workspace = _Workspace();
    final actor = MainThreadWorkspaceActor(workspace);
    // `includeFolder: UriComponents | null`, sent as null; no token sent.
    await actor.invoke(r'$startFileSearch', [null, <String, Object?>{}]);
    expect(workspace.calls.single[0], isNull);
    expect(workspace.calls.single[2], same(CancellationToken.none));

    final dialogs = _Dialogs();
    await MainThreadDialogsActor(dialogs).invoke(r'$showOpenDialog', []);
    expect(dialogs.options, isNull);
  });

  test('a missing required argument is a clear error', () async {
    final actor = MainThreadWorkspaceActor(_Workspace());
    await expectLater(
      actor.invoke(r'$startFileSearch', [null]),
      throwsA(
        isA<RpcDecodeError>().having(
          (e) => '$e',
          'message',
          allOf(
            contains(
              r'MainThreadWorkspace.$startFileSearch argument 1 (options)',
            ),
            contains('Map<String, Object?>'),
          ),
        ),
      ),
    );
    await expectLater(
      actor.invoke(r'$checkExists', [
        [42],
        <String>[],
      ]),
      throwsA(isA<RpcDecodeError>()),
    );
  });

  test('unsupported methods throw RpcUnsupported and are counted', () async {
    final commands = _Commands();
    final actor = MainThreadCommandsActor(commands);
    final seen = <String>[];
    final sub = ExtHostParity.instance.onUnsupportedCall.listen(
      (c) => seen.add(c.name),
    );
    expect(await actor.invoke(r'$registerCommand', ['a.b']), isNull);
    expect(commands.registered, ['a.b']);

    for (var i = 0; i < 2; i++) {
      await expectLater(
        actor.invoke(r'$getCommands', []),
        throwsA(
          isA<RpcUnsupported>().having(
            (e) => e.what,
            'what',
            r'MainThreadCommands.$getCommands',
          ),
        ),
      );
    }
    expect(
      ExtHostParity.instance.count('MainThreadCommands', r'$getCommands'),
      2,
    );
    expect(ExtHostParity.instance.unsupportedCalls, {
      r'MainThreadCommands.$getCommands': 2,
    });
    expect(seen, [
      r'MainThreadCommands.$getCommands',
      r'MainThreadCommands.$getCommands',
    ]);
    await sub.cancel();

    // A method the shape does not have.
    await expectLater(
      actor.invoke(r'$nope', []),
      throwsA(isA<RpcUnsupported>()),
    );
  });

  test('an unsupported request replies an error over RPC', () async {
    final (ours, theirs) = FakeMessagePassing.pair();
    final main = RpcProtocol(ours, actorNames: proxyIdentifierNames);
    final extHost = RpcProtocol(theirs, actorNames: proxyIdentifierNames);
    main.set(
      MainThreadCommandsActor.identifier.nid,
      MainThreadCommandsActor(MainThreadCommandsUnsupported()),
    );
    await expectLater(
      extHost.call(MainContext.mainThreadCommands.nid, r'$getCommands', []),
      throwsA(
        isA<RpcRemoteError>()
            .having((e) => e.name, 'name', 'Unsupported')
            .having((e) => e.message, 'message', contains(r'$getCommands')),
      ),
    );
    expect(
      ExtHostParity.instance.count('MainThreadCommands', r'$getCommands'),
      1,
    );
    main.dispose();
    extHost.dispose();
  });

  test('there is a fallback actor for every main thread shape', () async {
    expect(unsupportedMainThreadActors.keys, [
      for (final id in MainContext.all) id.nid,
    ]);
    final clipboard =
        unsupportedMainThreadActors[MainContext.mainThreadClipboard.nid]!();
    expect(clipboard, isA<MainThreadClipboardActor>());
    await expectLater(
      clipboard.invoke(r'$readText', []),
      throwsA(isA<RpcUnsupported>()),
    );
    expect(
      ExtHostParity.instance.count('MainThreadClipboard', r'$readText'),
      1,
    );
  });

  test('every main thread shape has methods listed for parity', () {
    expect(exthostProtocolMethods, hasLength(MainContext.all.length));
    expect(exthostProtocolMethods['MainThreadCommands'], [
      r'$registerCommand',
      r'$unregisterCommand',
      r'$fireCommandActivationEvent',
      r'$executeCommand',
      r'$getCommands',
    ]);
  });

  test('decoders', () {
    expect(decodeInt(3.0), 3);
    expect(() => decodeInt(3.5), throwsA(isA<RpcDecodeError>()));
    expect(decodeNullable(decodeString)(null), isNull);
    expect(
      decodeMapOf(decodeUri)({
        'a': {'scheme': 'file', 'path': '/x'},
      }),
      {'a': VsUri.file('/x')},
    );
    expect(
      () => decodeReply(r'X.$y', 1, decodeString),
      throwsA(
        isA<RpcDecodeError>().having(
          (e) => '$e',
          'message',
          contains(r'the reply to X.$y'),
        ),
      ),
    );
  });
}
