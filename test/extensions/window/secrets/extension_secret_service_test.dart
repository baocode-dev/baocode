import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/main_thread/main_thread_context.dart';
import 'package:baocode/extensions/main_thread/main_thread_secret_state.dart';
import 'package:baocode/extensions/window/secrets/extension_secret_service.dart';
import 'package:baocode/extensions/window/secrets/keyed_sequencer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_secret_backend.dart';

/// Two ends of a connection, delivering in a microtask.
final class _Wire implements MessagePassingProtocol {
  _Wire? peer;
  void Function(Uint8List message)? _listener;

  static (_Wire, _Wire) pair() {
    final a = _Wire();
    final b = _Wire();
    a.peer = b;
    b.peer = a;
    return (a, b);
  }

  @override
  void send(Uint8List message) {
    final to = peer;
    if (to != null) scheduleMicrotask(() => to._listener?.call(message));
  }

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      _listener = listener;
}

/// The extension host's `ExtHostSecretState`: records the changes.
final class _ExtHostSecretState implements RpcActor {
  final changes = <Map<String, Object?>>[];

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    expect(method, r'$onDidChangePassword');
    changes.add((args.single! as Map).cast());
    return null;
  }
}

/// One extension host session: our actor on one end, the extension host's
/// secret state on the other.
final class _Host {
  _Host(ExtensionSecretService secrets) {
    final (ours, theirs) = _Wire.pair();
    main = RpcProtocol(ours, actorNames: proxyIdentifierNames);
    extHost = RpcProtocol(theirs, actorNames: proxyIdentifierNames);
    context = MainThreadContext(
      rpc: main,
      services: {ExtensionSecretService: secrets},
    );
    main.set(
      MainContext.mainThreadSecretState.nid,
      MainThreadSecretState.customer(context),
    );
    extHost.set(ExtHostContext.extHostSecretState.nid, received);
  }

  late final RpcProtocol main;
  late final RpcProtocol extHost;
  late final MainThreadContext context;
  final received = _ExtHostSecretState();

  /// Calls the main thread as the extension host does.
  Future<Object?> call(String method, List<Object?> args) =>
      extHost.call(MainContext.mainThreadSecretState.nid, method, args);

  Future<void> dispose() async {
    await context.dispose();
    main.dispose();
    extHost.dispose();
  }
}

void main() {
  late Directory temp;
  late String indexPath;
  late FakeSecretBackend backend;
  late ExtensionSecretService secrets;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('secrets');
    indexPath = p.join(temp.path, 'User', 'globalStorage', 'secret-keys.json');
    backend = FakeSecretBackend();
    secrets = ExtensionSecretService(backend: backend, keyIndexPath: indexPath);
  });

  tearDown(() async {
    await secrets.dispose();
    await temp.delete(recursive: true);
  });

  group('ExtensionSecretService', () {
    test('keeps secrets by extension and key in the backend', () async {
      expect(await secrets.get('pub.ext', 'token'), isNull);
      await secrets.set('pub.ext', 'token', 's3cret');
      await secrets.set('pub.other', 'token', 'other');
      expect(backend.values, {
        'pub.ext/token': 's3cret',
        'pub.other/token': 'other',
      });
      expect(await secrets.get('pub.ext', 'token'), 's3cret');
      await secrets.delete('pub.ext', 'token');
      expect(await secrets.get('pub.ext', 'token'), isNull);
      expect(await secrets.get('pub.other', 'token'), 'other');
    });

    test('reports a change only when a value changes', () async {
      final changes = <ExtensionSecretChange>[];
      secrets.changes.listen(changes.add);
      await secrets.set('pub.ext', 'a', '1');
      await secrets.set('pub.ext', 'a', '1');
      await secrets.set('pub.ext', 'a', '2');
      await secrets.delete('pub.ext', 'a');
      await secrets.delete('pub.ext', 'a');
      await secrets.delete('pub.ext', 'never');
      expect(changes, [
        (extensionId: 'pub.ext', key: 'a'),
        (extensionId: 'pub.ext', key: 'a'),
        (extensionId: 'pub.ext', key: 'a'),
      ]);
      // The same value is not written again.
      expect(backend.log.where((e) => e.startsWith('write')), [
        'write pub.ext/a=1',
        'write pub.ext/a=2',
      ]);
    });

    test('the change is out before the set completes', () async {
      final order = <String>[];
      secrets.changes.listen((_) => order.add('change'));
      await secrets.set('pub.ext', 'a', '1');
      order.add('set done');
      expect(order, ['change', 'set done']);
    });

    test('writes when the old value cannot be read', () async {
      final changes = <ExtensionSecretChange>[];
      secrets.changes.listen(changes.add);
      backend.failReads.add('pub.ext/a');
      await secrets.set('pub.ext', 'a', '1');
      expect(backend.values['pub.ext/a'], '1');
      expect(changes, hasLength(1));
      await secrets.delete('pub.ext', 'a');
      expect(backend.values, isEmpty);
      expect(changes, hasLength(2));
      await expectLater(secrets.get('pub.ext', 'a'), throwsA(isA<Exception>()));
    });

    test('keeps the key names (not the values) in an index file', () async {
      await secrets.set('pub.ext', 'b', 'x');
      await secrets.set('pub.ext', 'a', 'y');
      await secrets.set('pub.other', 'c', 'z');
      expect(await secrets.keys('pub.ext'), ['b', 'a']);
      expect(await secrets.keys('pub.none'), isEmpty);
      await secrets.delete('pub.ext', 'b');
      expect(await secrets.keys('pub.ext'), ['a']);
      await secrets.flush();
      final text = File(indexPath).readAsStringSync();
      expect(jsonDecode(text), {'pub.ext': '["a"]', 'pub.other': '["c"]'});
      expect(text, isNot(contains('y')));

      // Another run reads it back.
      final again = ExtensionSecretService(
        backend: backend,
        keyIndexPath: indexPath,
      );
      addTearDown(again.dispose);
      expect(await again.keys('pub.ext'), ['a']);
      expect(await again.keys('pub.other'), ['c']);
      // A secret found that the index lost is added; one gone is dropped.
      backend.values['pub.ext/lost'] = 'v';
      backend.values.remove('pub.other/c');
      expect(await again.get('pub.ext', 'lost'), 'v');
      expect(await again.get('pub.other', 'c'), isNull);
      expect(await again.keys('pub.ext'), ['a', 'lost']);
      expect(await again.keys('pub.other'), isEmpty);
    });

    test('runs the operations of one key in order', () async {
      final slow = FakeSecretBackend(delay: const Duration(milliseconds: 5));
      final service = ExtensionSecretService(
        backend: slow,
        keyIndexPath: p.join(temp.path, 'slow.json'),
      );
      addTearDown(service.dispose);
      final changes = <ExtensionSecretChange>[];
      service.changes.listen(changes.add);
      final done = <String>[];
      await Future.wait([
        service.set('pub.ext', 'k', '1').then((_) => done.add('set 1')),
        service.delete('pub.ext', 'k').then((_) => done.add('delete')),
        service.set('pub.ext', 'k', '2').then((_) => done.add('set 2')),
        service.get('pub.ext', 'k').then((v) => done.add('get $v')),
        service.set('pub.ext', 'other', 'o').then((_) => done.add('other')),
      ]);
      expect(slow.values, {'pub.ext/k': '2', 'pub.ext/other': 'o'});
      expect(done.where((e) => e != 'other'), [
        'set 1',
        'delete',
        'set 2',
        'get 2',
      ]);
      expect(slow.log.where((e) => !e.startsWith('read') && e.contains('/k')), [
        'write pub.ext/k=1',
        'delete pub.ext/k',
        'write pub.ext/k=2',
      ]);
      expect(changes.where((c) => c.key == 'k'), hasLength(3));
      expect(await service.keys('pub.ext'), unorderedEquals(['k', 'other']));
      // Another key's operation did not wait for these.
      expect(done.indexOf('other'), lessThan(done.indexOf('set 2')));
    });

    test('accounts keep apart ids and keys with slashes', () async {
      await secrets.set('a', 'b/c', '1');
      await secrets.set('a/b', 'c', '2');
      expect(await secrets.get('a', 'b/c'), '1');
      expect(await secrets.get('a/b', 'c'), '2');
      expect(backend.values.keys, ['a/b/c', 'a%2Fb/c']);
    });
  });

  group('KeyedSequencer', () {
    test('a failing task does not stop the next', () async {
      final sequencer = KeyedSequencer<String>();
      final first = sequencer.queue('k', () async => throw StateError('x'));
      final second = sequencer.queue('k', () async => 2);
      await expectLater(first, throwsStateError);
      expect(await second, 2);
      expect(sequencer.isBusy('k'), isFalse);
    });
  });

  group('MainThreadSecretState', () {
    test('answers what the extension host sends', () async {
      final actor = MainThreadSecretStateActor(MainThreadSecretState(secrets));
      // ExtHostSecretState.store/get/keys/delete for `pub.ext`.
      expect(
        await actor.invoke(r'$setPassword', ['pub.ext', 'token', 'v1']),
        isNull,
      );
      expect(await actor.invoke(r'$getPassword', ['pub.ext', 'token']), 'v1');
      expect(await actor.invoke(r'$getKeys', ['pub.ext']), ['token']);
      expect(
        await actor.invoke(r'$deletePassword', ['pub.ext', 'token']),
        isNull,
      );
      expect(await actor.invoke(r'$getPassword', ['pub.ext', 'token']), isNull);
      expect(await actor.invoke(r'$getKeys', ['pub.ext']), isEmpty);
    });

    test('keeps one extension\'s calls in order, as upstream', () async {
      final slow = FakeSecretBackend(delay: const Duration(milliseconds: 5));
      final service = ExtensionSecretService(
        backend: slow,
        keyIndexPath: p.join(temp.path, 'slow.json'),
      );
      addTearDown(service.dispose);
      final actor = MainThreadSecretStateActor(MainThreadSecretState(service));
      // Not awaited one by one, as an extension may call them.
      final results = await Future.wait([
        actor.invoke(r'$setPassword', ['pub.ext', 'a', '1']),
        actor.invoke(r'$setPassword', ['pub.ext', 'b', '2']),
        actor.invoke(r'$getKeys', ['pub.ext']),
        actor.invoke(r'$deletePassword', ['pub.ext', 'a']),
        actor.invoke(r'$getKeys', ['pub.ext']),
      ]);
      expect(results[2], ['a', 'b']);
      expect(results[4], ['b']);
    });

    test('every host hears every change, over RPC', () async {
      final one = _Host(secrets);
      final two = _Host(secrets);
      addTearDown(one.dispose);
      addTearDown(two.dispose);

      await one.call(r'$setPassword', ['pub.ext', 'token', 'v1']);
      expect(await two.call(r'$getPassword', ['pub.ext', 'token']), 'v1');
      await two.call(r'$deletePassword', ['pub.ext', 'token']);
      await one.call(r'$setPassword', ['pub.ext', 'token', 'v1']);
      // The same value again: no change.
      await one.call(r'$setPassword', ['pub.ext', 'token', 'v1']);
      // The app (another workspace's host not over RPC here) changes one.
      await secrets.set('pub.other', 'k', 'x');
      await pumpEventQueue();

      const token = {'extensionId': 'pub.ext', 'key': 'token'};
      const other = {'extensionId': 'pub.other', 'key': 'k'};
      for (final host in [one, two]) {
        expect(host.received.changes, [token, token, token, other]);
      }
      expect(await one.call(r'$getKeys', ['pub.ext']), ['token']);

      // A host that ended hears nothing more.
      await two.dispose();
      await secrets.set('pub.ext', 'token', 'v2');
      await pumpEventQueue();
      expect(one.received.changes, hasLength(5));
      expect(two.received.changes, hasLength(4));
    });
  });
}
