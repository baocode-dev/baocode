import 'dart:convert';
import 'dart:typed_data';

import 'identity.dart';

/// Where an end can be reached: its id (what is dialled, and proven), the
/// relays it keeps to, and the addresses it was last seen at (`ip:port`).
/// The addresses are hints: tried at once, with the relays, the first way
/// through kept.
class LinkAddress {
  const LinkAddress(this.id, {this.relays = const [], this.addrs = const []});

  /// As [toJson] wrote it; null for something else.
  static LinkAddress? fromJson(Object? json) => switch (json) {
    {'id': final String id} when keyOfDeviceId(id) != null => LinkAddress(
      id,
      relays: [...?(json['relays'] as List?)?.whereType<String>()],
      addrs: [...?(json['addrs'] as List?)?.whereType<String>()],
    ),
    _ => null,
  };

  final String id;
  final List<String> relays;
  final List<String> addrs;

  LinkAddress copyWith({List<String>? relays, List<String>? addrs}) =>
      LinkAddress(
        id,
        relays: relays ?? this.relays,
        addrs: addrs ?? this.addrs,
      );

  Map<String, Object?> toJson() => {'id': id, 'relays': relays, 'addrs': addrs};

  @override
  bool operator ==(Object other) =>
      other is LinkAddress &&
      other.id == id &&
      _sameList(other.relays, relays) &&
      _sameList(other.addrs, addrs);

  @override
  int get hashCode =>
      Object.hash(id, Object.hashAll(relays), Object.hashAll(addrs));

  @override
  String toString() => 'LinkAddress($id, $relays, $addrs)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What a desktop's QR code holds, for a phone to pair with it: its public
/// key, a one-time secret that only who saw the code knows, and where it can
/// be reached (its relays, its addresses).
class PairingOffer {
  const PairingOffer({
    required this.name,
    required this.key,
    required this.token,
    required this.expires,
    this.relays = const [],
    this.addrs = const [],
  });

  /// As [uri] wrote it, or as the code's text is pasted. A code of before
  /// (version 1) is a [PairingVersionException]: the desktop needs
  /// updating.
  factory PairingOffer.parse(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text.trim());
    } on FormatException {
      throw FormatException('Not a pairing code', text);
    }
    final data = uri.queryParameters['d'];
    if (uri.scheme != scheme || uri.host != 'pair' || data == null) {
      throw FormatException('Not a pairing code', text);
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(decodeKey(data)));
    } on FormatException {
      throw FormatException('Not a pairing code', text);
    }
    if (json case {'v': final int version}
        when version != PairingOffer.version) {
      throw PairingVersionException(version);
    }
    if (json case {
      'n': final String name,
      'k': final String key,
      't': final String token,
      'x': final int expires,
    }) {
      final decoded = decodeKey(key);
      if (decoded.length != 32) {
        throw FormatException('Not a pairing code', text);
      }
      return PairingOffer(
        name: name,
        key: decoded,
        token: decodeKey(token),
        expires: DateTime.fromMillisecondsSinceEpoch(expires * 1000),
        relays: [...?(json['r'] as List?)?.whereType<String>()],
        addrs: [...?(json['a'] as List?)?.whereType<String>()],
      );
    }
    throw FormatException('Not a pairing code', text);
  }

  static const scheme = 'baocode';
  static const version = 2;

  /// The desktop's name, shown while pairing.
  final String name;

  /// The desktop's public key: its id.
  final Uint8List key;

  /// The one-time secret the phone proves it saw the code with.
  final Uint8List token;

  /// When [token] stops being taken.
  final DateTime expires;

  /// The relays the desktop keeps to (URLs).
  final List<String> relays;

  /// Its addresses (`ip:port`): on the LAN first.
  final List<String> addrs;

  String get id => deviceIdOf(key);

  /// Where to dial the desktop.
  LinkAddress get address => LinkAddress(id, relays: relays, addrs: addrs);

  bool expiredAt(DateTime now) => !now.isBefore(expires);

  /// `baocode://pair?d=…`: what the QR code holds.
  String get uri {
    final json = {
      'v': version,
      'n': name,
      'k': encodeKey(key),
      't': encodeKey(token),
      'x': expires.millisecondsSinceEpoch ~/ 1000,
      'r': relays,
      'a': addrs,
    };
    return '$scheme://pair?d=${encodeKey(utf8.encode(jsonEncode(json)))}';
  }
}

/// A pairing code of another version than this app's.
class PairingVersionException implements Exception {
  const PairingVersionException(this.version);

  final int version;

  /// The code is older: the desktop needs updating.
  bool get older => version < PairingOffer.version;

  @override
  String toString() => 'PairingVersionException($version)';
}
