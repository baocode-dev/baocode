import 'dart:async';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:test/test.dart';

import 'support.dart';

/// An actor that answers with what it was given.
final class _Echo implements RpcActor {
  final calls = <List<Object?>>[];

  @override
  FutureOr<Object?> invoke(String method, List<Object?> args) {
    calls.add(args);
    return switch (method) {
      'buffers' => RpcObjectWithBuffers({
        'uri': args.first,
        'data': RpcBuffer(Uint8List.fromList([1, 2])),
      }),
      _ => args.first,
    };
  }
}

void main() {
  const authority = 'ssh-remote+box';
  final names = {1: 'Echo'};

  test('createUriTransformer moves file URIs to the remote authority', () {
    final t = createUriTransformer(authority);
    expect(t.transformOutgoing(VsUri.file('/home/u/a.ts').toJson()), {
      r'$mid': 1,
      'path': '/home/u/a.ts',
      'scheme': 'vscode-remote',
      'authority': authority,
    });
    expect(
      t.transformIncoming(
        VsUri.parse('vscode-remote://$authority/home/u/a.ts').toJson(),
      ),
      VsUri.file('/home/u/a.ts').toJson(),
    );
    expect(
      t.transformIncoming(VsUri.file('/Users/me/x').toJson())['scheme'],
      'vscode-local',
    );
    final untitled = VsUri.parse('untitled:Untitled-1').toJson();
    expect(identical(t.transformIncoming(untitled), untitled), isTrue);
    expect(t.transformOutgoingScheme('file'), 'vscode-remote');
  });

  test('with a transformer on both sides (the remote extension host), the '
      'URIs arrive as they were sent', () async {
    final (main, host) = FakeMessagePassing.pair();
    final mainRpc = RpcProtocol(
      main,
      actorNames: names,
      uriTransformer: createUriTransformer(authority),
    );
    final echo = _Echo();
    RpcProtocol(
      host,
      actorNames: names,
      uriTransformer: createUriTransformer(authority),
    ).set(1, echo);
    final file = VsUri.file('/home/u/a.ts');
    final reply = await mainRpc.call(1, r'$echo', [
      {'uri': file, 'nested': [VsUri.parse('vscode-local:/Users/me/x')]},
    ]);
    // On the wire, the project's are the remote authority's, this
    // machine's `file:`.
    final wire = String.fromCharCodes(main.sent.first);
    expect(wire, contains('"path":"/home/u/a.ts","scheme":"vscode-remote"'));
    expect(wire, contains('"path":"/Users/me/x","scheme":"file"'));
    expect(echo.calls.single.first, {
      'uri': file.toJson(),
      'nested': [VsUri.parse('vscode-local:/Users/me/x').toJson()],
    });
    expect(reply, {
      'uri': file.toJson(),
      'nested': [VsUri.parse('vscode-local:/Users/me/x').toJson()],
    });
  });

  test('without one there (a local host serving a remote project), the '
      'project is vscode-remote and this machine file', () async {
    final (main, host) = FakeMessagePassing.pair();
    final mainRpc = RpcProtocol(
      main,
      actorNames: names,
      uriTransformer: createUriTransformer(authority),
    );
    final echo = _Echo();
    RpcProtocol(host, actorNames: names).set(1, echo);
    final reply = await mainRpc.call(1, 'buffers', [
      VsUri.file('/home/u/a.ts'),
      VsUri.parse('vscode-local:/Users/me/ext'),
    ]);
    expect(echo.calls.single, [
      VsUri.parse('vscode-remote://$authority/home/u/a.ts').toJson(),
      VsUri.file('/Users/me/ext').toJson(),
    ]);
    // Its own files come back as this machine's.
    expect(reply, {
      'uri': VsUri.file('/home/u/a.ts').toJson(),
      'data': isA<RpcBuffer>(),
    });
  });
}
