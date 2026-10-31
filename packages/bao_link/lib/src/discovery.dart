import 'dart:typed_data';

import 'identity.dart';

/// How a desktop makes itself known on its LAN, by DNS-SD (Bonjour,
/// mDNS): for the phones paired with it to find it again wherever its
/// address moves to, and for new ones to list it among those nearby.
///
/// What it tells is public: its name and key, and whether it pairs now. A
/// phone dials the key, which the desktop has to prove, so one pretending
/// to be it gets nowhere.
abstract final class LinkDiscovery {
  /// The DNS-SD service type. The port is the desktop's UDP one (QUIC);
  /// the type keeps its old name, as the phones' app manifests list it.
  static const type = '_baocode._tcp';

  static const version = '2';
}

/// A desktop as it advertises itself, and as a phone finds it: the TXT
/// record's `v` (version), `k` (its key) and `p` (`1` while it pairs).
class LinkAdvert {
  const LinkAdvert({
    required this.name,
    required this.key,
    required this.port,
    this.pairing = false,
    this.addresses = const [],
  });

  /// The advert found as [name] at [port], with [attributes]; null for
  /// one of another version, or not one of BaoCode's.
  static LinkAdvert? parse({
    required String name,
    required int port,
    required Map<String, String> attributes,
    List<String> addresses = const [],
  }) {
    if (attributes['v'] != LinkDiscovery.version) return null;
    final Uint8List key;
    try {
      key = decodeKey(attributes['k'] ?? '');
    } on FormatException {
      return null;
    }
    if (key.length != 32 || port <= 0 || port > 65535) return null;
    return LinkAdvert(
      name: name,
      key: key,
      port: port,
      pairing: attributes['p'] == '1',
      addresses: addresses,
    );
  }

  /// The desktop's name, as the service's.
  final String name;
  final Uint8List key;
  final int port;

  /// It takes a new phone now: its user is pairing one.
  final bool pairing;

  /// Where it was found (IPv4, IPv6), as resolved: the phone's side only.
  final List<String> addresses;

  String get id => deviceIdOf(key);

  Map<String, String> get attributes => {
    'v': LinkDiscovery.version,
    'k': encodeKey(key),
    'p': pairing ? '1' : '0',
  };

  /// Where to dial (`ip:port`): IPv4 first; not link-local IPv6 addresses,
  /// which need an interface named.
  List<String> get addrs {
    final usable = [
      for (final address in addresses)
        if (!address.toLowerCase().startsWith('fe80') && !address.contains('%'))
          address,
    ];
    return [
      for (final address in usable)
        if (!address.contains(':')) '$address:$port',
      for (final address in usable)
        if (address.contains(':')) '[$address]:$port',
    ];
  }

  /// The same desktop telling the same.
  bool sameAs(LinkAdvert other) =>
      other.id == id &&
      other.name == name &&
      other.port == port &&
      other.pairing == pairing;
}
