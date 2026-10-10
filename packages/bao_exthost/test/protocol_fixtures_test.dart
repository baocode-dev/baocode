// The Dart protocols against bytes the pinned upstream TypeScript produced
// (test/fixtures/protocol.json, from tool/generate_exthost_fixtures.mjs):
// IPC serialization, RPC requests and replies, PersistentProtocol framing.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:test/test.dart';

import 'support.dart';

final _fixtures = jsonDecode(
  File('test/fixtures/protocol.json').readAsStringSync(),
) as Map<String, Object?>;

List<Map<String, Object?>> _cases(String key) =>
    (_fixtures[key]! as List).cast<Map<String, Object?>>();

bool _tagged(Object? d, String tag) => d is Map && d.containsKey(tag);

/// A fixture's tagged value as Dart sends it.
Object? _dart(Object? d, {required bool rpc}) {
  if (_tagged(d, r'$undefined')) return rpc ? rpcUndefined : null;
  if (_tagged(d, r'$buffer')) {
    final bytes = unhex((d! as Map)[r'$buffer'] as String);
    return rpc ? RpcBuffer(bytes) : IpcBuffer(bytes);
  }
  if (_tagged(d, r'$uri')) {
    return VsUri.revive(((d! as Map)[r'$uri'] as Map).cast<String, Object?>());
  }
  if (_tagged(d, r'$objectWithBuffers')) {
    return RpcObjectWithBuffers(
      _dart((d! as Map)[r'$objectWithBuffers'], rpc: true),
    );
  }
  if (d is List) return [for (final e in d) _dart(e, rpc: rpc)];
  if (d is Map) {
    return {
      for (final e in d.entries) e.key as String: _dart(e.value, rpc: rpc),
    };
  }
  return d;
}

/// A value Dart decoded, in the fixtures' terms, with `undefined` as null
/// (Dart does not tell them apart).
Object? _describe(Object? v) => switch (v) {
  RpcBuffer() => {r'$buffer': hex(v.bytes)},
  IpcBuffer() => {r'$buffer': hex(v.bytes)},
  CancellationToken() => {r'$token': true},
  VsUri() => v.toJson(),
  List() => [for (final e in v) _describe(e)],
  Map() => {for (final e in v.entries) '${e.key}': _describe(e.value)},
  _ => v,
};

/// A fixture's description of what upstream decoded, as Dart decodes it.
Object? _expected(Object? d) {
  if (_tagged(d, r'$undefined')) return null;
  if (_tagged(d, r'$objectWithBuffers')) {
    return _expected((d! as Map)[r'$objectWithBuffers']);
  }
  if (_tagged(d, r'$buffer') || _tagged(d, r'$token')) return d;
  if (_tagged(d, r'$uri')) {
    final components = ((d! as Map)[r'$uri'] as Map).cast<String, Object?>();
    return VsUri.revive(components).toJson();
  }
  if (d is List) return [for (final e in d) _expected(e)];
  if (d is Map) {
    return {for (final e in d.entries) '${e.key}': _expected(e.value)};
  }
  return d;
}

/// Records the arguments of every request, and answers with [reply].
final class _Actor implements RpcActor {
  _Actor(this.reply);

  final Object? Function() reply;
  List<Object?>? args;

  @override
  Object? invoke(String method, List<Object?> args) {
    this.args = args;
    return reply();
  }
}

void main() {
  test('the fixtures come from the pinned upstream', () {
    expect(_fixtures['revision'], '08d4889f9ec4a1685d257b9b95de036c8e1ce1e5');
  });

  group('IPC serialization', () {
    for (final c in _cases('ipc')) {
      test(c['name'], () {
        final bytes = unhex(c['bytes']! as String);
        final reader = IpcReader(bytes);
        expect(_describe(reader.read()), _expected(c['decoded']));
        expect(reader.isAtEnd, isTrue);
        if (c['encode'] == true) {
          final out = BytesBuilder();
          ipcSerialize(out, _dart(c['value'], rpc: false));
          expect(hex(out.takeBytes()), c['bytes']);
        }
      });
    }
  });

  group('RPC requests', () {
    for (final c in _cases('rpcRequests')) {
      test('${c['name']}: encode', () async {
        final wire = FakeMessagePassing();
        final rpc = RpcProtocol(wire, actorNames: proxyIdentifierNames);
        final args = (c['args']! as List).toList();
        CancellationTokenSource? source;
        if (args.isNotEmpty && _tagged(args.last, r'$token')) {
          args.removeLast();
          source = CancellationTokenSource();
        }
        final dartArgs = [for (final a in args) _dart(a, rpc: true)];
        rpc
            .call(
              c['rpcId']! as int,
              c['method']! as String,
              dartArgs,
              token: source?.token,
            )
            .ignore();
        if (c['cancel'] == true) source!.cancel();
        await settle();
        expect([for (final m in wire.sent) hex(m)], c['messages']);
        rpc.dispose();
      });

      test('${c['name']}: decode', () async {
        final wire = FakeMessagePassing();
        final rpc = RpcProtocol(wire, actorNames: proxyIdentifierNames);
        final actor = _Actor(() => null);
        rpc.set(c['rpcId']! as int, actor);
        wire.receive(unhex((c['messages']! as List).first as String));
        await settle();
        expect(_describe(actor.args), _expected(c['args']));
        rpc.dispose();
      });
    }
  });

  group('RPC replies', () {
    for (final c in _cases('rpcReplies')) {
      final error = c['error'] as Map<String, Object?>?;
      final messages = (c['messages']! as List).cast<String>();

      test('${c['name']}: serve', () async {
        if (error != null && _tagged(error, r'$undefined')) {
          // Dart cannot reject with `undefined` (ReplyErrEmpty).
          return;
        }
        final wire = FakeMessagePassing();
        final rpc = RpcProtocol(wire, actorNames: proxyIdentifierNames);
        final actor = _Actor(() {
          if (error != null) {
            final e = error[r'$error']! as Map;
            if (e['name'] == 'Canceled') throw const CancellationException();
            throw RpcRemoteError(
              name: e['name']! as String,
              message: e['message']! as String,
              stack: '<stack>',
            );
          }
          final result = c['result'];
          // A JSON `null` reply, as opposed to `undefined`.
          if (result == null) return rpcNull;
          return _dart(result, rpc: true);
        });
        rpc.set(c['rpcId']! as int, actor);
        wire.receive(unhex(c['request']! as String));
        await settle();
        expect(_describe(actor.args), _expected(c['received']));
        expect(wire.sent, hasLength(2));
        expect(hex(wire.sent[0]), messages[0], reason: 'Acknowledged');
        if (error == null) {
          expect(hex(wire.sent[1]), messages[1]);
        } else {
          // Stacks differ: compare the rest, keys in order.
          final ours = wire.sent[1];
          final theirs = unhex(messages[1]);
          expect(hex(ours.sublist(0, 5)), hex(theirs.sublist(0, 5)));
          Map<String, Object?> json(Uint8List m) =>
              (jsonDecode(utf8.decode(m.sublist(9))) as Map<String, Object?>)
                ..remove('stack');
          expect(json(ours).keys, json(theirs).keys);
          expect(json(ours), json(theirs));
        }
        rpc.dispose();
      });

      if (error == null) {
        test('${c['name']}: receive preserving JSON null', () async {
          final wire = FakeMessagePassing();
          final rpc = RpcProtocol(wire, actorNames: proxyIdentifierNames);
          final reply = rpc.call(
            c['rpcId']! as int,
            c['method']! as String,
            [],
            preserveJsonNull: true,
          );
          for (final m in messages) {
            wire.receive(unhex(m));
          }
          final value = await reply;
          if (c['result'] == null) {
            expect(value, same(rpcNull));
          } else {
            expect(_describe(value), _expected(c['result']));
          }
          rpc.dispose();
        });
      }

      test('${c['name']}: receive', () async {
        final wire = FakeMessagePassing();
        final rpc = RpcProtocol(wire, actorNames: proxyIdentifierNames);
        final reply = rpc.call(c['rpcId']! as int, c['method']! as String, []);
        for (final m in messages) {
          wire.receive(unhex(m));
        }
        if (error == null) {
          final value = await reply;
          final result = c['result'];
          expect(_describe(value), result == null ? null : _expected(result));
        } else if (_tagged(error, r'$undefined')) {
          await expectLater(reply, throwsA(isA<RpcRemoteError>()));
        } else {
          final e = error[r'$error']! as Map;
          if (e['name'] == 'Canceled') {
            await expectLater(reply, throwsA(isA<CancellationException>()));
          } else {
            await expectLater(
              reply,
              throwsA(
                isA<RpcRemoteError>()
                    .having((r) => r.name, 'name', e['name'])
                    .having((r) => r.message, 'message', e['message'])
                    .having((r) => r.stack, 'stack', '<stack>'),
              ),
            );
          }
        }
        expect(rpc.responsiveState, ResponsiveState.responsive);
        rpc.dispose();
      });
    }
  });

  group('PersistentProtocol framing', () {
    final fixture = _fixtures['persistent']! as Map<String, Object?>;
    final ops = (fixture['ops']! as List).cast<List<Object?>>();

    test('writes what upstream writes', () async {
      final socket = FakeSocket();
      final protocol = PersistentProtocol(socket, sendKeepAlive: false);
      final messages = <String>[];
      final controls = <String>[];
      protocol.onMessage.listener = (m) => messages.add(hex(m));
      protocol.onControlMessage.listener = (m) => controls.add(hex(m));
      for (final op in ops) {
        final arg = op.length > 1 ? unhex(op[1]! as String) : null;
        switch (op[0]) {
          case 'send':
            protocol.send(arg!);
          case 'sendControl':
            protocol.sendControl(arg!);
          case 'receive':
            socket.receive(arg!);
          case 'sendPause':
            protocol.sendPause();
          case 'sendResume':
            protocol.sendResume();
          case 'sendDisconnect':
            protocol.sendDisconnect();
          default:
            fail('Unknown op ${op[0]}');
        }
        await settle();
      }
      expect(hex(socket.written.takeBytes()), fixture['written']);
      expect(messages, fixture['messages']);
      expect(controls, fixture['controls']);
      protocol.dispose();
    });

    test('reads what upstream writes, in any chunks', () {
      final bytes = unhex(fixture['written']! as String);
      for (final size in [1, 7, 13, 64, bytes.length]) {
        final read = BytesBuilder();
        final reader = ProtocolReader((m) {
          final header = ByteData(ProtocolConstants.headerLength)
            ..setUint8(0, m.type)
            ..setUint32(1, m.id)
            ..setUint32(5, m.ack)
            ..setUint32(9, m.data.length);
          read
            ..add(header.buffer.asUint8List())
            ..add(m.data);
        });
        for (var i = 0; i < bytes.length; i += size) {
          reader.accept(
            Uint8List.sublistView(
              bytes,
              i,
              i + size > bytes.length ? bytes.length : i + size,
            ),
          );
        }
        expect(
          hex(read.takeBytes()),
          fixture['written'],
          reason: 'chunks of $size',
        );
      }
    });
  });
}
