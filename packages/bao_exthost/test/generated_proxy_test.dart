// The generated extension host proxies: what they put on the wire, and how
// they decode replies.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The extension host's side: records requests, answers with [reply].
final class _Recorder implements RpcActor {
  _Recorder(this.reply);

  final FutureOr<Object?> Function(String method, List<Object?> args) reply;
  final requests = <(String, List<Object?>)>[];

  @override
  FutureOr<Object?> invoke(String method, List<Object?> args) {
    requests.add((method, args));
    return reply(method, args);
  }
}

void main() {
  late FakeMessagePassing ours;
  late RpcProtocol main;
  late RpcProtocol extHost;

  setUp(() {
    final (a, b) = FakeMessagePassing.pair();
    ours = a;
    main = RpcProtocol(a, actorNames: proxyIdentifierNames);
    extHost = RpcProtocol(b, actorNames: proxyIdentifierNames);
  });

  tearDown(() {
    main.dispose();
    extHost.dispose();
  });

  test('calls the right actor and method, and decodes the reply', () async {
    final actor = _Recorder((_, _) => 'contents');
    extHost.set(ExtHostContext.extHostDocumentContentProviders.nid, actor);
    final proxy = ExtHostDocumentContentProvidersProxy(main);
    final uri = VsUri.parse('untitled:Untitled-1');
    expect(await proxy.$provideTextDocumentContent(3, uri), 'contents');

    final (method, args) = actor.requests.single;
    expect(method, r'$provideTextDocumentContent');
    expect(args, [3, uri.toJson()]);
    final request = ours.sent.first;
    expect(request[0], RpcMessageType.requestJsonArgs);
    expect(request[5], ExtHostContext.extHostDocumentContentProviders.nid);
  });

  test(
    'null for a parameter that admits undefined is sent as undefined',
    () async {
      final actor = _Recorder((_, args) => {'resolved': args[1]});
      extHost.set(ExtHostContext.extHostDebugService.nid, actor);
      final proxy = ExtHostDebugServiceProxy(main);
      final result = await proxy.$substituteVariables(null, {'type': 'node'});
      expect(result, {
        'resolved': {'type': 'node'},
      });
      expect(actor.requests.single.$2, [
        null,
        {'type': 'node'},
      ]);
      // `undefined` is what makes upstream use mixed arguments.
      expect(ours.sent.first[0], RpcMessageType.requestMixedArgs);
    },
  );

  test('a token is passed on, and cancelling it cancels the request', () async {
    final started = Completer<CancellationToken>();
    final actor = _Recorder((_, args) {
      final token = args.last! as CancellationToken;
      started.complete(token);
      return token.whenCancelled.then(
        (_) => throw const CancellationException(),
      );
    });
    extHost.set(ExtHostContext.extHostTreeViews.nid, actor);
    final proxy = ExtHostTreeViewsProxy(main);
    final source = CancellationTokenSource();
    final reply = proxy.$handleDrag('view', ['h1'], 'op', token: source.token);
    final token = await started.future;
    expect(ours.sent.first[0], RpcMessageType.requestJsonArgsWithCancellation);
    expect(actor.requests.single.$2.take(3), [
      'view',
      ['h1'],
      'op',
    ]);
    source.cancel();
    await expectLater(reply, throwsA(isA<CancellationException>()));
    expect(token.isCancellationRequested, isTrue);
  });

  test('a reply that is not the declared type is a clear error', () async {
    extHost.set(
      ExtHostContext.extHostDocumentContentProviders.nid,
      _Recorder((_, _) => 42),
    );
    final proxy = ExtHostDocumentContentProvidersProxy(main);
    await expectLater(
      proxy.$provideTextDocumentContent(1, VsUri.file('/x')),
      throwsA(
        isA<RpcDecodeError>().having(
          (e) => '$e',
          'message',
          contains(
            r'the reply to ExtHostDocumentContentProviders.$provideTextDocumentContent',
          ),
        ),
      ),
    );
  });

  test('rest parameters are spread', () async {
    final actor = _Recorder((_, _) => null);
    extHost.set(ExtHostContext.extHostCommands.nid, actor);
    await ExtHostCommandsProxy(main)
        .$executeContributedCommand('cmd', [1, 'two']);
    final (method, args) = actor.requests.single;
    expect(method, r'$executeContributedCommand');
    expect(args, ['cmd', 1, 'two']);
  });
}
