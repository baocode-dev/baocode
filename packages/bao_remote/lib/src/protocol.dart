import 'dart:convert';
import 'dart:typed_data';

import 'search/text_query.dart';

/// The methods and notifications between the app and the server, and the
/// shapes of what they carry that are not plain JSON.
///
/// A stream (a watch, a search) is opened by a request that answers with
/// its id; its items come as [streamData], then [streamDone] or
/// [streamError]; the app ends it early with [streamCancel]. A process
/// (Claude Code, a command) is the same with its own
/// notifications: [processOutput] for stdout and stderr, [processExit]
/// once it is gone.
abstract final class RemoteProtocol {
  /// Raise it whenever a method or a shape changes: an app and a server of
  /// another version do not talk, and the app puts its own server in place.
  static const version = 4;

  static const initialize = 'initialize';
  static const shutdown = 'shutdown';

  // Streams.
  static const streamData = 'stream/data';
  static const streamError = 'stream/error';
  static const streamDone = 'stream/done';
  static const streamCancel = 'stream/cancel';

  // Files.
  static const fsList = 'fs/list';
  static const fsRead = 'fs/read';
  static const fsWrite = 'fs/write';
  static const fsCreate = 'fs/create';
  static const fsRename = 'fs/rename';
  static const fsCopy = 'fs/copy';
  static const fsDelete = 'fs/delete';
  static const fsReadBytes = 'fs/readBytes';
  static const fsWriteBytes = 'fs/writeBytes';
  static const fsWalk = 'fs/walk';
  static const fsWatch = 'fs/watch';
  static const fsStat = 'fs/stat';
  static const fsEntries = 'fs/entries';
  static const fsRealPath = 'fs/realPath';

  // Search and Git.
  static const searchText = 'search/text';
  static const gitRun = 'git/run';
  static const gitWatch = 'git/watch';

  // Processes.
  static const processStart = 'process/start';
  static const processRun = 'process/run';
  static const processWrite = 'process/write';
  static const processCloseStdin = 'process/closeStdin';
  static const processKill = 'process/kill';
  static const processOutput = 'process/output';
  static const processExit = 'process/exit';

  // Claude Code.
  static const claudeStart = 'claude/start';
  static const claudeLocate = 'claude/locate';
  static const claudeProjects = 'claude/projects';
  static const claudeRead = 'claude/read';
  static const claudeGoal = 'claude/goal';
  static const claudeDelete = 'claude/delete';
  static const claudeFork = 'claude/fork';
  static const claudeUsageOffBy = 'claude/usageOffBy';
  static const claudeInstall = 'claude/install';
  static const claudeUpload = 'claude/upload';

  // Review snapshots.
  static const reviewOpen = 'review/open';
  static const reviewCall = 'review/call';

  // Terminals.
  static const ptyStart = 'pty/start';
  static const ptyWrite = 'pty/write';
  static const ptyResize = 'pty/resize';
  static const ptyKill = 'pty/kill';
  static const ptyOutput = 'pty/output';
  static const ptyExit = 'pty/exit';
  static const ptyProfiles = 'pty/profiles';

  // The extension runtime and its VS Code server.
  static const exthostInstall = 'exthost/install';
  static const exthostUpload = 'exthost/upload';
  static const exthostStart = 'exthost/start';

  /// A file sent for the server there (an extension's .vsix), in pieces:
  /// `{name, offset, data}`, answered with its path there.
  static const exthostStage = 'exthost/stage';

  /// Deletes a file [exthostStage] sent: `{name}`.
  static const exthostUnstage = 'exthost/unstage';

  // Port forwarding (the remote host's port to one of the app's), and
  // the app's connections to a port there ([tcpConnect]).
  static const tcpListen = 'tcp/listen';
  static const tcpUnlisten = 'tcp/unlisten';
  static const tcpOpen = 'tcp/open';
  static const tcpConnect = 'tcp/connect';
  static const tcpData = 'tcp/data';
  static const tcpClose = 'tcp/close';
}

/// Bytes as JSON carries them.
String encodeBytes(List<int> bytes) => base64Encode(bytes);

Uint8List decodeBytes(Object? data) =>
    data is String ? base64Decode(data) : Uint8List(0);

/// The machine the server runs on (`linux`/`darwin`, `x64`/`arm64`, the
/// C library).
class RemotePlatform {
  const RemotePlatform(this.os, this.arch, {this.libc});

  factory RemotePlatform.fromJson(Map<String, Object?> json) => RemotePlatform(
    json['os'] as String,
    json['arch'] as String,
    libc: json['libc'] as String?,
  );

  /// `linux`, `darwin`, `win`.
  final String os;

  /// `x64`, `arm64`, …
  final String arch;

  /// `gnu` or `musl` on Linux.
  final String? libc;

  Map<String, Object?> toJson() => {'os': os, 'arch': arch, 'libc': ?libc};

  @override
  String toString() => libc == null ? '$os-$arch' : '$os-$arch-$libc';
}

/// What the server says of itself when the app connects.
class RemoteHello {
  const RemoteHello({
    required this.protocol,
    required this.version,
    required this.platform,
    required this.pid,
    required this.home,
    required this.dataDir,
  });

  factory RemoteHello.fromJson(Map<String, Object?> json) => RemoteHello(
    protocol: json['protocol'] as int,
    version: json['version'] as String? ?? '',
    platform: RemotePlatform.fromJson(
      (json['platform'] as Map).cast<String, Object?>(),
    ),
    pid: json['pid'] as int,
    home: json['home'] as String? ?? '',
    dataDir: json['dataDir'] as String? ?? '',
  );

  /// [RemoteProtocol.version] of the server.
  final int protocol;

  /// The build of the server (the app's version it came with).
  final String version;
  final RemotePlatform platform;

  /// The server's process id.
  final int pid;

  /// The user's home folder there.
  final String home;

  /// Where the server keeps its own state there (`~/.baocode-server/data`).
  final String dataDir;

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'version': version,
    'platform': platform.toJson(),
    'pid': pid,
    'home': home,
    'dataDir': dataDir,
  };
}

/// [IdeTextQuery] as JSON.
Map<String, Object?> textQueryToJson(IdeTextQuery query) => {
  'pattern': query.pattern,
  'isRegExp': query.isRegExp,
  'isCaseSensitive': query.isCaseSensitive,
  'isWordMatch': query.isWordMatch,
  'includes': query.includes,
  'excludes': query.excludes,
  'useExcludesAndIgnoreFiles': query.useExcludesAndIgnoreFiles,
  'maxResults': query.maxResults,
};

IdeTextQuery textQueryFromJson(Map<String, Object?> json) => IdeTextQuery(
  json['pattern'] as String,
  isRegExp: json['isRegExp'] as bool? ?? false,
  isCaseSensitive: json['isCaseSensitive'] as bool? ?? false,
  isWordMatch: json['isWordMatch'] as bool? ?? false,
  includes: json['includes'] as String? ?? '',
  excludes: json['excludes'] as String? ?? '',
  useExcludesAndIgnoreFiles: json['useExcludesAndIgnoreFiles'] as bool? ?? true,
  maxResults: json['maxResults'] as int? ?? 20000,
);

/// A search's item ([IdeFileMatches] or [IdeTextSearchComplete]) as JSON.
Map<String, Object?> searchItemToJson(Object item) => switch (item) {
  IdeFileMatches(:final path, :final matches) => {
    'path': path,
    'matches': [
      for (final match in matches)
        [match.line, match.start, match.end, match.text],
    ],
  },
  IdeTextSearchComplete(:final limitHit) => {'complete': limitHit},
  _ => throw ArgumentError.value(item, 'item', 'not a search item'),
};

Object searchItemFromJson(Map<String, Object?> json) {
  if (json['complete'] case final bool limitHit) {
    return IdeTextSearchComplete(limitHit: limitHit);
  }
  return IdeFileMatches(json['path'] as String, [
    for (final match in json['matches'] as List)
      if (match case [
        final int line,
        final int start,
        final int end,
        final String text,
      ])
        IdeTextMatch(line, start, end, text),
  ]);
}
