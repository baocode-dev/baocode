// Decoding RPC arguments and replies into the types the generated protocol
// declares (lib/src/generated/), with errors that say what was expected
// where, instead of a cast error.

import 'dart:convert';

import '../base/cancellation.dart';
import '../base/uri.dart';
import 'rpc_protocol.dart';

/// An argument or reply that is not what the protocol declares.
final class RpcDecodeError implements Exception {
  RpcDecodeError(this.expected, this.value, [this.where]);

  /// The Dart type that was expected.
  final String expected;

  /// What arrived.
  final Object? value;

  /// Which argument or reply, when known.
  final String? where;

  RpcDecodeError _at(String where) => RpcDecodeError(expected, value, where);

  @override
  String toString() {
    var shown = '$value';
    if (shown.length > 80) shown = '${shown.substring(0, 77)}...';
    final at = where == null ? '' : ' for $where';
    return 'RpcDecodeError: expected $expected$at, got '
        '${value == null ? 'null' : '${value.runtimeType} $shown'}';
  }
}

/// A `string`.
String decodeString(Object? value) =>
    value is String ? value : throw RpcDecodeError('String', value);

/// A `number`.
num decodeNum(Object? value) =>
    value is num ? value : throw RpcDecodeError('num', value);

/// A numeric enum or integer literal.
int decodeInt(Object? value) => switch (value) {
  int() => value,
  double() when value == value.truncateToDouble() && value.isFinite =>
    value.toInt(),
  _ => throw RpcDecodeError('int', value),
};

/// A `boolean`.
bool decodeBool(Object? value) =>
    value is bool ? value : throw RpcDecodeError('bool', value);

/// `any`, `unknown` and what the protocol leaves untyped: as it arrived.
Object? decodeObject(Object? value) => value;

/// `UriComponents` (`URI.revive`).
VsUri decodeUri(Object? value) => switch (value) {
  VsUri() => value,
  Map() => VsUri.revive(value.cast<String, Object?>()),
  _ => throw RpcDecodeError('VsUri', value),
};

/// A `VSBuffer`.
RpcBuffer decodeBuffer(Object? value) =>
    value is RpcBuffer ? value : throw RpcDecodeError('RpcBuffer', value);

/// An object the protocol does not type further.
Map<String, Object?> decodeMap(Object? value) => switch (value) {
  Map<String, Object?>() => value,
  Map() => value.cast<String, Object?>(),
  _ => throw RpcDecodeError('Map<String, Object?>', value),
};

/// `T | undefined`, `T | null`: null, or what [decode] makes of a value.
T? Function(Object?) decodeNullable<T extends Object>(
  T Function(Object?) decode,
) =>
    (value) => value == null ? null : decode(value);

/// `T[]`.
List<T> Function(Object?) decodeListOf<T>(T Function(Object?) decode) =>
    (value) => value is List
    ? [for (final e in value) decode(e)]
    : throw RpcDecodeError('List', value);

/// `Record<string, T>` and index signatures.
Map<String, T> Function(Object?) decodeMapOf<T>(T Function(Object?) decode) =>
    (value) => value is Map
    ? {for (final e in value.entries) '${e.key}': decode(e.value)}
    : throw RpcDecodeError('Map', value);

/// What [decode] makes of the reply to [method] (`Shape.$method`).
T decodeReply<T>(String method, Object? value, T Function(Object?) decode) {
  try {
    return decode(value);
  } on RpcDecodeError catch (e) {
    throw e._at('the reply to $method');
  }
}

/// A `CancellationToken` that is not a method's last parameter: upstream
/// sends it as JSON (`CancellationToken.None`'s), and it cancels nothing.
Map<String, Object?> encodeInlineToken(CancellationToken? token) => {
  'isCancellationRequested': token?.isCancellationRequested ?? false,
};

/// A request's arguments, as a generated actor reads them: missing trailing
/// arguments are null, and [token] is what `RpcProtocol` appended to a
/// request that can be cancelled.
final class RpcArgs {
  factory RpcArgs(String method, List<Object?> args) {
    if (args.isNotEmpty && args.last is CancellationToken) {
      return RpcArgs._(
        method,
        args.sublist(0, args.length - 1),
        args.last! as CancellationToken,
      );
    }
    return RpcArgs._(method, args, CancellationToken.none);
  }

  RpcArgs._(this.method, this._args, this.token);

  /// `Shape.$method`, for errors.
  final String method;
  final List<Object?> _args;
  final CancellationToken token;

  int get length => _args.length;

  /// Argument [index] ([name] upstream), decoded.
  T arg<T>(int index, T Function(Object?) decode, String name) {
    final value = index < _args.length ? _args[index] : null;
    try {
      return decode(value);
    } on RpcDecodeError catch (e) {
      throw e._at('$method argument $index ($name)');
    }
  }

  /// The arguments from [index] on (a `...rest` parameter), decoded.
  List<T> rest<T>(int index, T Function(Object?) decode, String name) => [
    for (var i = index; i < _args.length; i++) arg(i, decode, name),
  ];

  @override
  String toString() =>
      '$method(${jsonEncode(_args, toEncodable: (o) => '$o')})';
}
