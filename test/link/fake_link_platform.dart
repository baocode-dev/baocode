import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode/link/link_platform.dart';

/// The machine, in memory: its node is on [network], where phones' nodes
/// dial it; what it advertises is in [advertised].
class FakeLinkPlatform implements LinkPlatform {
  Map<String, Object?> kept = {};
  final network = MemoryLinkNetwork();

  /// The node bound last, while it is.
  MemoryLinkNode? node;

  /// What it was bound with last.
  List<String> boundRelays = const [];
  int binds = 0;

  /// Advertised now, the latest last.
  final List<LinkAdvert> advertised = [];

  @override
  Future<Map<String, Object?>> read() async => kept;

  @override
  Future<void> write(Map<String, Object?> json) async => kept = json;

  @override
  Future<LinkNode> bind(
    LinkIdentity identity, {
    required List<String> relays,
    required int port,
  }) async {
    binds++;
    boundRelays = relays;
    return node = network.node(identity.id, relays: relays);
  }

  /// A phone on the same network, as [identity].
  MemoryLinkNode phone(LinkIdentity identity) => network.node(identity.id);

  @override
  Future<LinkAdvertising?> advertise(LinkAdvert advert) async {
    advertised.add(advert);
    return _Advertising(() => advertised.remove(advert));
  }

  @override
  Future<DeviceInfo> device() async =>
      const DeviceInfo(name: 'Test Mac', kind: 'mac', system: 'macOS 26.1');

  @override
  String? branchOf(String folder) => 'main';
}

class _Advertising implements LinkAdvertising {
  _Advertising(this._stop);

  final void Function() _stop;

  @override
  Future<void> stop() async => _stop();
}
