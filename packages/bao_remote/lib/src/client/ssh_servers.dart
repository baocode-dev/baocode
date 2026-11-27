import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// How a server saved in the app signs in.
enum SshAuth {
  /// As `ssh` would on its own: the agent, the default keys, those
  /// `~/.ssh/config` names; a password when the host asks for one.
  auto,

  /// A password, kept in the system's keychain.
  password,

  /// A private key file (its passphrase asked, when it has one).
  key,
}

/// What runs Claude Code on a server saved in the app.
enum SshCore {
  /// The host's Claude Code CLI where it has one, else BaoCode's own core.
  auto,

  /// BaoCode's own core (the server's): on the upstreams of the app alone.
  builtin,

  /// The host's Claude Code CLI, installed there when it has none.
  cli,
}

/// A server the user saved in the app (its form), rather than in
/// `~/.ssh/config`: reached through a `Host` of the app's own ssh config
/// ([sshServersConfig]), which includes the user's after it.
class SshServer {
  const SshServer({
    required this.hostName,
    this.port,
    this.user,
    this.auth = SshAuth.auto,
    this.identityFile,
    this.jump,
    this.core = SshCore.auto,
  });

  /// Its name or address.
  final String hostName;

  /// Null for ssh's (22, or what `~/.ssh/config` says).
  final int? port;

  /// Null for ssh's (the user here, or what `~/.ssh/config` says).
  final String? user;
  final SshAuth auth;

  /// The private key's path, with [SshAuth.key].
  final String? identityFile;

  /// The host it is reached through: another saved, by the name the app
  /// knows it by, or one as typed (`user@host[:port]`, an alias of
  /// `~/.ssh/config`); null for none.
  final String? jump;

  /// What runs Claude Code there.
  final SshCore core;

  /// What one would type for it: `user@host`, with `:port` after.
  String get address => [
    if (user case final user? when user.isNotEmpty) '$user@',
    hostName,
    if (port case final port? when port != 22) ':$port',
  ].join();

  Map<String, Object?> toJson() => {
    'hostName': hostName,
    'port': ?port,
    'user': ?user,
    'auth': auth.name,
    'identityFile': ?identityFile,
    'jump': ?jump,
    if (core != SshCore.auto) 'core': core.name,
  };

  /// Null for what is not one.
  static SshServer? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final hostName = json['hostName'];
    if (hostName is! String || hostName.isEmpty) return null;
    String? text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    return SshServer(
      hostName: hostName,
      port: switch (json['port']) {
        final int port when port > 0 && port < 65536 => port,
        _ => null,
      },
      user: text('user'),
      auth: SshAuth.values.firstWhere(
        (auth) => auth.name == json['auth'],
        orElse: () => SshAuth.auto,
      ),
      identityFile: text('identityFile'),
      jump: text('jump'),
      core: SshCore.values.firstWhere(
        (core) => core.name == json['core'],
        orElse: () => SshCore.auto,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SshServer &&
      other.hostName == hostName &&
      other.port == port &&
      other.user == user &&
      other.auth == auth &&
      other.identityFile == identityFile &&
      other.jump == jump &&
      other.core == core;

  @override
  int get hashCode =>
      Object.hash(hostName, port, user, auth, identityFile, jump, core);
}

/// The `Host` of [host] (as the app knows it) in [sshServersConfig]: a
/// name ssh takes (letters, digits, dots and dashes) that no one types.
String sshServerAlias(String host) {
  final readable = host.replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '-');
  final hash = '${crypto.sha1.convert(utf8.encode(host))}'.substring(0, 8);
  return 'baocode-$readable-$hash';
}

/// The ssh config of [servers], by the host the app knows each as: a `Host`
/// each ([sshServerAlias]), then [includes] (the user's config, the
/// system's), whose settings apply where these say nothing.
///
/// A jump through another saved server is a `ProxyCommand` running [ssh]
/// with this config ([configFile]) to that one's `Host`, rather than a
/// `ProxyJump`: ssh would run the `ssh` on PATH (on Windows, maybe not the
/// app's), with this config's path unquoted. One that goes round (a jump
/// through itself, in the end) is left out.
String sshServersConfig(
  Map<String, SshServer> servers, {
  required String ssh,
  required String configFile,
  List<String> includes = const [],
  bool windows = false,
  String? controlPath,
}) {
  final out = StringBuffer()
    ..writeln('# Written by BaoCode for the servers saved in it: edits are')
    ..writeln('# lost. Your own ~/.ssh/config is included at the end.')
    ..writeln();
  for (final MapEntry(key: host, value: server) in servers.entries) {
    out.writeln('Host ${sshServerAlias(host)}');
    out.writeln('  HostName ${server.hostName}');
    if (server.port case final port?) out.writeln('  Port $port');
    if (server.user case final user? when user.isNotEmpty) {
      out.writeln('  User ${_configWord(user)}');
    }
    // Learned the first time, as the launcher has it for others: these
    // are the user's, added in the app (a jump's ssh is given no -o).
    out.writeln('  StrictHostKeyChecking accept-new');
    switch (server.auth) {
      case SshAuth.key:
        if (server.identityFile case final file? when file.isNotEmpty) {
          out.writeln(
            '  IdentityFile ${_configWord(_path(file, windows: windows))}',
          );
          out.writeln('  IdentitiesOnly yes');
        }
      case SshAuth.password:
        out.writeln('  PreferredAuthentications password,keyboard-interactive');
      case SshAuth.auto:
        break;
    }
    if (server.jump case final jump? when !_loops(host, servers)) {
      final through = servers.containsKey(jump)
          ? [sshServerAlias(jump)]
          : _typed(jump);
      out.writeln(
        '  ProxyCommand ${_proxyCommand(ssh, configFile, through, windows)}',
      );
    }
    out.writeln();
  }
  // Out of the last Host first: an Include in one applies to it alone.
  if (includes.isNotEmpty) {
    if (servers.isNotEmpty) out.writeln('Host *');
    for (final include in includes) {
      out.writeln('Include ${_configWord(_path(include, windows: windows))}');
    }
    out.writeln();
  }
  // Fallback defaults after the user's ~/.ssh/config (OpenSSH uses the first
  // value seen): keep jump hops alive and multiplex them on POSIX so a drop
  // on an inner hop (e.g. a container behind a bastion) reconnects without
  // re-authenticating the jump host. The outermost target overrides
  // ControlMaster=no on its CLI so it never attaches to a stale master.
  out.writeln('Host *');
  out.writeln('  StrictHostKeyChecking accept-new');
  out.writeln('  ServerAliveInterval 15');
  out.writeln('  ServerAliveCountMax 4');
  if (!windows && controlPath != null && controlPath.isNotEmpty) {
    out.writeln('  ControlMaster auto');
    out.writeln(
      '  ControlPath ${_configWord(_path(controlPath, windows: windows))}',
    );
    out.writeln('  ControlPersist 30m');
  }
  return '$out';
}

/// Whether going from [host] through the jumps comes back round.
bool _loops(String host, Map<String, SshServer> servers) {
  final seen = {host};
  var at = servers[host]?.jump;
  while (at != null) {
    if (!seen.add(at)) return true;
    at = servers[at]?.jump;
  }
  return false;
}

/// `ssh`'s arguments for a host as typed: `-p` and its port, then it.
List<String> _typed(String host) {
  final colon = host.lastIndexOf(':');
  if (colon > 0) {
    final port = int.tryParse(host.substring(colon + 1));
    if (port != null) return ['-p', '$port', host.substring(0, colon)];
  }
  return [host];
}

String _proxyCommand(
  String ssh,
  String configFile,
  List<String> through,
  bool windows,
) {
  // `%` is a token in it: a path's own doubled.
  String escape(String text) => text.replaceAll('%', '%%');
  if (windows) {
    String quote(String text) => '"${escape(text)}"';
    return [
      quote(ssh),
      '-F',
      quote(configFile),
      '-W',
      '[%h]:%p',
      for (final argument in through) escape(argument),
    ].join(' ');
  }
  String quote(String text) => "'${escape(text).replaceAll("'", r"'\''")}'";
  return [
    'exec',
    quote(ssh),
    '-F',
    quote(configFile),
    '-W',
    "'[%h]:%p'",
    for (final argument in through) quote(argument),
  ].join(' ');
}

/// [path] as ssh's config takes it: with forward slashes on Windows, where
/// a backslash may be taken for an escape.
String _path(String path, {required bool windows}) =>
    windows ? path.replaceAll(r'\', '/') : path;

/// [word] as one word of ssh's config: quoted when it has a space.
String _configWord(String word) => word.contains(RegExp(r'[\s"#]'))
    ? '"${word.replaceAll('"', r'\"')}"'
    : word;
