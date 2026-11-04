import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';

/// Which way a port is forwarded.
enum ForwardDirection {
  /// A port of the host's, reached here: a server run there, opened in
  /// this machine's browser.
  toLocal,

  /// A port of this machine's, reached there: a server run here, for the
  /// host's commands.
  toRemote,
}

/// A port forward as kept for a host (see [RemoteHostSettings.forwards]):
/// [port] the one forwarded (the host's for [ForwardDirection.toLocal],
/// this machine's for [ForwardDirection.toRemote]), and where it is
/// listened on at the other end, [listen], when the user said; the same
/// port where it is free otherwise. [auto]: found in what a terminal or a
/// command printed, not added by hand.
@immutable
class PortForwardSpec {
  const PortForwardSpec({
    required this.direction,
    required this.port,
    this.listen,
    this.auto = false,
  });

  factory PortForwardSpec.fromJson(Map<String, Object?> json) =>
      PortForwardSpec(
        direction: json['direction'] == 'toRemote'
            ? ForwardDirection.toRemote
            : ForwardDirection.toLocal,
        port: json['port'] as int,
        listen: json['listen'] as int?,
        auto: json['auto'] == true,
      );

  final ForwardDirection direction;
  final int port;
  final int? listen;
  final bool auto;

  Map<String, Object?> toJson() => {
    'direction': direction.name,
    'port': port,
    'listen': ?listen,
    if (auto) 'auto': true,
  };

  /// The same forward: the same way, of the same port.
  bool same(PortForwardSpec other) =>
      other.direction == direction && other.port == port;

  @override
  bool operator ==(Object other) =>
      other is PortForwardSpec &&
      same(other) &&
      other.listen == listen &&
      other.auto == auto;

  @override
  int get hashCode => Object.hash(direction, port, listen, auto);
}

/// What the user chose for each SSH host, by host (as the projects name
/// it), kept in the data folder's `remote-hosts.json`:
///
/// - whether its agents may act on this machine ([localAccess]): the
///   tools that run commands here and move files and ports (see
///   local_tools.dart); on until the user turns it off (Settings → SSH
///   Servers), so only an off one is kept;
/// - whether commands run here need no asking each time
///   ([runsWithoutAsking]), as the user answered on a card;
/// - the ports forwarded ([forwards]), made again as it connects.
class RemoteHostSettings extends ChangeNotifier {
  RemoteHostSettings({this._file});

  /// The app's; replaced under test.
  static RemoteHostSettings instance = RemoteHostSettings();

  final String? _file;
  String get _path =>
      _file ?? p.join(DataDirectory.current.stateDir, 'remote-hosts.json');

  Map<String, _HostSettings>? _hosts;

  Map<String, _HostSettings> get _all => _hosts ??= _read();

  Map<String, _HostSettings> _read() {
    try {
      final file = File(_path);
      if (!file.existsSync()) return {};
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is Map<String, Object?>) key: _HostSettings.fromJson(value),
      };
    } on Object {
      // Not one this wrote: started over.
      return {};
    }
  }

  void _write() {
    final hosts = _all;
    try {
      final file = File(_path);
      file.parent.createSync(recursive: true);
      final part = File('${file.path}.part');
      part.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          for (final MapEntry(:key, :value) in hosts.entries)
            if (!value.isEmpty) key: value.toJson(),
        }),
        flush: true,
      );
      part.renameSync(file.path);
    } on FileSystemException {
      // Kept for this run only.
    }
  }

  _HostSettings _of(String host) => _all[host] ?? const _HostSettings();

  void _change(String host, _HostSettings Function(_HostSettings) change) {
    final before = _of(host);
    final after = change(before);
    if (after == before) return;
    _all[host] = after;
    _write();
    notifyListeners();
  }

  bool localAccess(String host) => _of(host).localAccess;

  void setLocalAccess(String host, bool on) => _change(
    host,
    (settings) => settings.copyWith(
      localAccess: on,
      // Turned off, what the user allowed goes with it.
      runsWithoutAsking: on && settings.runsWithoutAsking,
    ),
  );

  bool runsWithoutAsking(String host) =>
      _of(host).localAccess && _of(host).runsWithoutAsking;

  void setRunsWithoutAsking(String host, bool on) =>
      _change(host, (settings) => settings.copyWith(runsWithoutAsking: on));

  List<PortForwardSpec> forwards(String host) => _of(host).forwards;

  /// Keeps [spec] among [host]'s forwards, in place of the same one's.
  void keepForward(String host, PortForwardSpec spec) => _change(
    host,
    (settings) => settings.copyWith(
      forwards: [
        for (final kept in settings.forwards)
          if (!kept.same(spec)) kept,
        spec,
      ],
    ),
  );

  void forgetForward(String host, PortForwardSpec spec) => _change(
    host,
    (settings) => settings.copyWith(
      forwards: [
        for (final kept in settings.forwards)
          if (!kept.same(spec)) kept,
      ],
    ),
  );
}

@immutable
class _HostSettings {
  const _HostSettings({
    this.localAccess = true,
    this.runsWithoutAsking = false,
    this.forwards = const [],
  });

  factory _HostSettings.fromJson(Map<String, Object?> json) => _HostSettings(
    localAccess: json['localAccess'] != false,
    runsWithoutAsking: json['runsWithoutAsking'] == true,
    forwards: [
      for (final forward in json['forwards'] as List? ?? const [])
        if (forward case final Map<String, Object?> json
            when json['port'] is int)
          PortForwardSpec.fromJson(json),
    ],
  );

  final bool localAccess;
  final bool runsWithoutAsking;
  final List<PortForwardSpec> forwards;

  bool get isEmpty => localAccess && !runsWithoutAsking && forwards.isEmpty;

  _HostSettings copyWith({
    bool? localAccess,
    bool? runsWithoutAsking,
    List<PortForwardSpec>? forwards,
  }) => _HostSettings(
    localAccess: localAccess ?? this.localAccess,
    runsWithoutAsking: runsWithoutAsking ?? this.runsWithoutAsking,
    forwards: forwards ?? this.forwards,
  );

  Map<String, Object?> toJson() => {
    if (!localAccess) 'localAccess': false,
    if (runsWithoutAsking) 'runsWithoutAsking': true,
    if (forwards.isNotEmpty)
      'forwards': [for (final forward in forwards) forward.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is _HostSettings &&
      other.localAccess == localAccess &&
      other.runsWithoutAsking == runsWithoutAsking &&
      listEquals(other.forwards, forwards);

  @override
  int get hashCode =>
      Object.hash(localAccess, runsWithoutAsking, Object.hashAll(forwards));
}
