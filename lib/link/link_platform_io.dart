import 'dart:convert';
import 'dart:io';

import 'package:bao_link/bao_link_io.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import 'link_platform.dart';

LinkPlatform? currentLinkPlatform() => IoLinkPlatform();

/// This machine's: an iroh node, the data folder's `state/mobile.json`.
class IoLinkPlatform implements LinkPlatform {
  /// The file at [path] instead, e.g. under test.
  IoLinkPlatform({this.path});

  final String? path;

  File get _file =>
      File(path ?? p.join(DataDirectory.current.stateDir, 'mobile.json'));

  @override
  Future<Map<String, Object?>> read() async {
    try {
      final file = _file;
      if (!await file.exists()) return const {};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : const {};
    } on Object {
      return const {};
    }
  }

  @override
  Future<void> write(Map<String, Object?> json) async {
    final file = _file;
    await file.parent.create(recursive: true);
    await writeFileAtomically(
      file,
      const JsonEncoder.withIndent('  ').convert(json),
    );
    if (!Platform.isWindows) {
      // The desktop's private key: the user's only.
      await Process.run('chmod', [
        '600',
        file.path,
      ]).catchError((Object _) => ProcessResult(0, 1, '', ''));
    }
  }

  @override
  Future<LinkNode> bind(
    LinkIdentity identity, {
    required List<String> relays,
    required int port,
  }) => IrohLinkNode.bind(
    identity: identity,
    relays: relays,
    port: port,
    accept: true,
  );

  @override
  Future<LinkAdvertising?> advertise(LinkAdvert advert) async {
    try {
      final broadcast = BonsoirBroadcast(
        printLogs: false,
        service: BonsoirService(
          name: advert.name.isEmpty ? 'BaoCode' : advert.name,
          type: LinkDiscovery.type,
          port: advert.port,
          attributes: advert.attributes,
        ),
      );
      await broadcast.initialize();
      await broadcast.start();
      return _Advertising(broadcast);
    } on Object catch (error) {
      // Not found on the LAN, then: the addresses kept still work.
      debugPrint('Not advertised on the LAN: $error');
      return null;
    }
  }

  DeviceInfo? _device;

  @override
  Future<DeviceInfo> device() async => _device ??= DeviceInfo(
    name: await _name(),
    kind: Platform.isMacOS
        ? 'mac'
        : Platform.isWindows
        ? 'windows'
        : 'linux',
    system: await _system(),
    laptop: await _laptop(),
  );

  static Future<String?> _run(String command, List<String> arguments) async {
    try {
      final result = await Process.run(command, arguments);
      if (result.exitCode != 0) return null;
      final out = '${result.stdout}'.trim();
      return out.isEmpty ? null : out;
    } on Object {
      return null;
    }
  }

  /// The name the user gave the computer: macOS's Computer Name (with its
  /// spaces and apostrophes), else the host's.
  static Future<String> _name() async {
    if (Platform.isMacOS) {
      if (await _run('scutil', ['--get', 'ComputerName']) case final name?) {
        return name;
      }
    }
    if (Platform.isWindows) {
      if (Platform.environment['COMPUTERNAME'] case final name?) return name;
    }
    final host = Platform.localHostname;
    return host.endsWith('.local')
        ? host.substring(0, host.length - '.local'.length)
        : host;
  }

  /// `macOS 26.1`, `Windows 11 Pro`, `Ubuntu 24.04 LTS`.
  static Future<String> _system() async {
    if (Platform.isMacOS) {
      final version = await _run('sw_vers', ['-productVersion']);
      return version == null ? 'macOS' : 'macOS $version';
    }
    final version = Platform.operatingSystemVersion;
    if (Platform.isWindows) {
      // `"Windows 10 Pro" 10.0 (Build 26100)`: 11 from build 22000.
      final name = RegExp(r'"([^"]+)"').firstMatch(version)?[1] ?? 'Windows';
      final build = int.tryParse(
        RegExp(r'Build (\d+)').firstMatch(version)?[1] ?? '',
      );
      return build != null && build >= 22000
          ? name.replaceFirst('Windows 10', 'Windows 11')
          : name;
    }
    try {
      for (final line in await File('/etc/os-release').readAsLines()) {
        if (line.startsWith('PRETTY_NAME=')) {
          return line.substring('PRETTY_NAME='.length).replaceAll('"', '');
        }
      }
    } on Object {
      // Not there.
    }
    return 'Linux';
  }

  static Future<bool> _laptop() async {
    if (Platform.isMacOS) {
      final model = await _run('sysctl', ['-n', 'hw.model']);
      return model?.contains('Book') ?? true;
    }
    return false;
  }

  final Map<String, (DateTime, String?)> _branches = {};

  @override
  String? branchOf(String folder) {
    final now = DateTime.now();
    if (_branches[folder] case (final at, final branch)
        when now.difference(at) < const Duration(seconds: 20)) {
      return branch;
    }
    final branch = _readBranch(folder);
    _branches[folder] = (now, branch);
    return branch;
  }

  /// What `.git/HEAD` says: the branch, or the commit when detached. A
  /// worktree's `.git` is a file saying where its own folder is.
  static String? _readBranch(String folder) {
    try {
      var git = p.join(folder, '.git');
      if (FileSystemEntity.isFileSync(git)) {
        final line = File(git).readAsStringSync().trim();
        if (!line.startsWith('gitdir:')) return null;
        git = p.normalize(
          p.join(folder, line.substring('gitdir:'.length).trim()),
        );
      }
      final head = File(p.join(git, 'HEAD'));
      if (!head.existsSync()) return null;
      final text = head.readAsStringSync().trim();
      const prefix = 'ref: refs/heads/';
      if (text.startsWith(prefix)) return text.substring(prefix.length);
      return text.length >= 7 ? text.substring(0, 7) : null;
    } on Object {
      return null;
    }
  }
}

class _Advertising implements LinkAdvertising {
  _Advertising(this._broadcast);

  final BonsoirBroadcast _broadcast;

  @override
  Future<void> stop() async {
    try {
      await _broadcast.stop();
    } on Object {
      // Gone already.
    }
  }
}
