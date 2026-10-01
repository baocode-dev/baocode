/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Terminal profiles: the shells a new terminal can start, as VS Code finds
// them. Pure: the system, its environment and its files are passed in.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/node/terminalProfiles.ts
// (`detectAvailableProfiles`, `detectAvailableUnixProfiles`,
// `detectAvailableWindowsProfiles`, `applyConfigProfilesToMap`,
// `transformToTerminalProfiles`, `validateProfilePaths`, `getGitBashPaths`),
// the default `terminal.integrated.profiles.*` of
// src/vs/platform/terminal/common/terminalPlatformConfiguration.ts, and
// src/vs/base/node/processes.ts (`findExecutable`).
//
// Deviations: no WSL distributions (listing them runs wsl.exe), no Cmder;
// a profile's `env`, `icon`, `color` and `overrideName` are not read;
// `${env:NAME}` is the only variable a path resolves; a Windows profile's
// `args` given as one string are split at spaces.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'terminal_shell.dart';

/// A shell a new terminal can start, as VS Code's `ITerminalProfile`: its
/// [name], the [path] it resolved to and its [args]. [isAutoDetected] when
/// the system has it (`/etc/shells`, another PowerShell) rather than a
/// profile of the settings: VS Code lists those apart, as detected.
@immutable
class TerminalProfile {
  const TerminalProfile({
    required this.name,
    required this.path,
    this.args = const [],
    this.isAutoDetected = false,
  });

  final String name;
  final String path;
  final List<String> args;
  final bool isAutoDetected;

  TerminalShell get shell => (executable: path, arguments: args);

  @override
  bool operator ==(Object other) =>
      other is TerminalProfile &&
      other.name == name &&
      other.path == path &&
      listEquals(other.args, args) &&
      other.isAutoDetected == isAutoDetected;

  @override
  int get hashCode =>
      Object.hash(name, path, Object.hashAll(args), isAutoDetected);

  @override
  String toString() =>
      'TerminalProfile($name: ${[path, ...args].join(' ')}'
      '${isAutoDetected ? ', detected' : ''})';
}

/// The profiles there are, and the shell a terminal starts when no
/// default profile is set (VS Code's fallback profile: [defaultTerminalShell]).
typedef TerminalProfiles = ({
  List<TerminalProfile> profiles,
  TerminalShell systemShell,
});

/// The system [os] stands for, as the settings name it.
String terminalPlatformKey(TerminalOs os) => switch (os) {
  TerminalOs.macOS => 'osx',
  TerminalOs.linux => 'linux',
  TerminalOs.windows => 'windows',
};

/// The setting naming [os]'s default profile:
/// `terminal.integrated.defaultProfile.osx`.
String terminalDefaultProfileKey(TerminalOs os) =>
    'terminal.integrated.defaultProfile.${terminalPlatformKey(os)}';

/// The setting with the user's profiles for [os]:
/// `terminal.integrated.profiles.osx`.
String terminalProfilesKey(TerminalOs os) =>
    'terminal.integrated.profiles.${terminalPlatformKey(os)}';

/// The system the app runs on, as Flutter says (tests set it).
TerminalOs terminalOsOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS || TargetPlatform.iOS => TerminalOs.macOS,
  TargetPlatform.windows => TerminalOs.windows,
  _ => TerminalOs.linux,
};

/// A profile before its path is found: the paths to try (one on the PATH
/// when not absolute), or a [source] that names them.
typedef _Unresolved = ({
  List<String> paths,
  List<String> args,
  _Source? source,
  bool isAutoDetected,
});

enum _Source { powerShell, gitBash }

/// The profiles there are on [os]: those the system has (with
/// [etcShells], `/etc/shells`' text, on macOS and Linux), then VS Code's
/// default profiles over them, then [configured] (the user's
/// `terminal.integrated.profiles.<os>`: a profile set to null is taken
/// away), less those whose shell is not there. [exists] says whether a file
/// is there, [list] the names in a folder.
List<TerminalProfile> detectTerminalProfiles(
  TerminalOs os,
  Map<String, String> environment, {
  required bool Function(String path) exists,
  required List<String> Function(String directory) list,
  String? etcShells,
  Object? configured,
}) {
  String? env(String name) => switch (_lookUp(environment, name, os)) {
    final value? when value.isNotEmpty => value,
    _ => null,
  };

  // Insertion order is upstream's: a profile set again keeps its place.
  final profiles = <String, _Unresolved>{};
  _Unresolved profile(
    List<String> paths, {
    List<String> args = const [],
    _Source? source,
    bool isAutoDetected = false,
  }) => (
    paths: paths,
    args: args,
    source: source,
    isAutoDetected: isAutoDetected,
  );

  if (os == TerminalOs.windows) {
    final windir = env('windir') ?? env('SystemRoot') ?? r'C:\Windows';
    final system32 = '$windir\\System32';
    final homeDrive = env('HOMEDRIVE') ?? 'C:';
    profiles
      ..['PowerShell'] = profile(
        const [],
        source: _Source.powerShell,
        isAutoDetected: true,
      )
      ..['Windows PowerShell'] = profile([
        '$system32\\WindowsPowerShell\\v1.0\\powershell.exe',
      ], isAutoDetected: true)
      ..['Git Bash'] = profile(
        const [],
        source: _Source.gitBash,
        isAutoDetected: true,
      )
      ..['Command Prompt'] = profile([
        '$system32\\cmd.exe',
      ], isAutoDetected: true)
      ..['Cygwin'] = profile(
        [
          '$homeDrive\\cygwin64\\bin\\bash.exe',
          '$homeDrive\\cygwin\\bin\\bash.exe',
        ],
        args: const ['--login'],
        isAutoDetected: true,
      )
      ..['bash (MSYS2)'] = profile(
        ['$homeDrive\\msys64\\usr\\bin\\bash.exe'],
        args: const ['--login', '-i'],
        isAutoDetected: true,
      )
      // The default `terminal.integrated.profiles.windows`.
      ..['PowerShell'] = profile(const [], source: _Source.powerShell)
      ..['Command Prompt'] = profile([
        '$windir\\Sysnative\\cmd.exe',
        '$system32\\cmd.exe',
      ])
      ..['Git Bash'] = profile(const [], source: _Source.gitBash);
  } else {
    // Each shell /etc/shells lists, named after its file (a second of a
    // name: `sh (2)`).
    final counts = <String, int>{};
    for (var line in (etcShells ?? '').split('\n')) {
      final comment = line.indexOf('#');
      if (comment >= 0) line = line.substring(0, comment);
      line = line.trim();
      if (line.isEmpty) continue;
      var name = p.posix.basename(line);
      final count = (counts[name] ?? 0) + 1;
      counts[name] = count;
      if (count > 1) name = '$name ($count)';
      profiles[name] = profile([line], isAutoDetected: true);
    }
    // The default `terminal.integrated.profiles.osx` and `.linux`: login
    // shells on macOS.
    final login = os == TerminalOs.macOS ? const ['-l'] : const <String>[];
    profiles
      ..['bash'] = profile(['bash'], args: login)
      ..['zsh'] = profile(['zsh'], args: login)
      ..['fish'] = profile(['fish'], args: login)
      ..['tmux'] = profile(['tmux'])
      ..['pwsh'] = profile(['pwsh']);
  }
  _applyConfigured(profiles, configured, os, env);

  final result = <TerminalProfile>[];
  for (final MapEntry(key: name, value: unresolved) in profiles.entries) {
    final paths = switch (unresolved.source) {
      _Source.powerShell => windowsPowerShells(environment, list: list),
      _Source.gitBash => _gitBashPaths(env),
      null => unresolved.paths,
    };
    final args = switch (unresolved.source) {
      _Source.gitBash when unresolved.args.isEmpty => const ['--login', '-i'],
      _ => unresolved.args,
    };
    final path = _firstExisting(paths, os, environment, exists);
    if (path == null) continue;
    result.add(
      TerminalProfile(
        name: name,
        path: path,
        args: args,
        isAutoDetected: unresolved.isAutoDetected,
      ),
    );
  }
  return result;
}

/// The user's profiles ([configured]) over [profiles]
/// (`applyConfigProfilesToMap`): null takes one away; one with a `path`
/// (or, on Windows, a `source`) sets it.
void _applyConfigured(
  Map<String, _Unresolved> profiles,
  Object? configured,
  TerminalOs os,
  String? Function(String name) env,
) {
  if (configured is! Map) return;
  String resolve(String path) => path.replaceAllMapped(
    RegExp(r'\$\{env:([^}]+)\}'),
    (match) => env(match.group(1)!) ?? '',
  );
  for (final MapEntry(:key, :value) in configured.entries) {
    if (key is! String) continue;
    if (value == null) {
      profiles.remove(key);
      continue;
    }
    if (value is! Map) continue;
    final paths = switch (value['path']) {
      final String path => [resolve(path)],
      final List<Object?> paths => [
        for (final path in paths)
          if (path is String) resolve(path),
      ],
      _ => const <String>[],
    };
    final source = os == TerminalOs.windows
        ? switch (value['source']) {
            'PowerShell' => _Source.powerShell,
            'Git Bash' => _Source.gitBash,
            _ => null,
          }
        : null;
    if (paths.isEmpty && source == null) continue;
    final args = switch (value['args']) {
      final List<Object?> args => [
        for (final arg in args)
          if (arg is String) arg,
      ],
      final String args when os == TerminalOs.windows => [
        for (final arg in args.split(' '))
          if (arg.isNotEmpty) arg,
      ],
      _ => const <String>[],
    };
    profiles[key] = (
      paths: paths,
      args: args,
      source: paths.isEmpty ? source : null,
      isAutoDetected: false,
    );
  }
}

/// Where Git for Windows' bash may be (`getGitBashPaths`, less the one
/// beside a `git` on the PATH).
List<String> _gitBashPaths(String? Function(String name) env) => [
  for (final dir in {
    if (env('ProgramW6432') case final programs?) '$programs\\Git',
    if (env('ProgramFiles') case final programs?) '$programs\\Git',
    if (env('ProgramFiles(X86)') case final programs?) '$programs\\Git',
    if (env('LocalAppData') case final local?) '$local\\Program\\Git',
    if (env('UserProfile') case final home?) ...[
      '$home\\scoop\\apps\\git-with-openssh\\current',
      '$home\\scoop\\apps\\git\\current',
    ],
  }) ...['$dir\\bin\\bash.exe', '$dir\\usr\\bin\\bash.exe'],
];

/// The first of [paths] that is there: an absolute one as it is, a name
/// on the PATH (with Windows' executable extensions), as `findExecutable`.
String? _firstExisting(
  List<String> paths,
  TerminalOs os,
  Map<String, String> environment,
  bool Function(String path) exists,
) {
  final context = os == TerminalOs.windows ? p.windows : p.posix;
  for (final path in paths) {
    if (context.isAbsolute(path)) {
      if (exists(path)) return path;
      continue;
    }
    final directories = (_lookUp(environment, 'PATH', os) ?? '').split(
      os == TerminalOs.windows ? ';' : ':',
    );
    final extensions = os == TerminalOs.windows && context.extension(path) == ''
        ? (_lookUp(environment, 'PATHEXT', os) ?? '.COM;.EXE;.BAT;.CMD')
              .split(';')
              .where((extension) => extension.isNotEmpty)
              .map((extension) => extension.toLowerCase())
              .toList()
        : const [''];
    for (final directory in directories) {
      if (directory.isEmpty) continue;
      for (final extension in extensions) {
        final candidate = context.join(directory, '$path$extension');
        if (exists(candidate)) return candidate;
      }
    }
  }
  return null;
}

/// The default profile's name: [setting] (the user's
/// `terminal.integrated.defaultProfile.<os>`) when a profile has it, else
/// the profile that is [systemShell], the shell a terminal starts with no
/// profile set (upstream's fallback profile, which the dropdown does not
/// name).
String? terminalDefaultProfileName(
  List<TerminalProfile> profiles, {
  Object? setting,
  TerminalShell? systemShell,
}) {
  if (setting is String && profiles.any((profile) => profile.name == setting)) {
    return setting;
  }
  final shell = systemShell?.executable;
  if (shell == null || shell.isEmpty) return null;
  // A profile of the settings first, then one detected.
  final ordered = [
    ...profiles.where((profile) => !profile.isAutoDetected),
    ...profiles.where((profile) => profile.isAutoDetected),
  ];
  for (final profile in ordered) {
    if (profile.path == shell) return profile.name;
  }
  final name = p.basenameWithoutExtension(shell.replaceAll(r'\', '/'));
  for (final profile in ordered) {
    if (profile.name.toLowerCase() == name.toLowerCase()) return profile.name;
  }
  return null;
}

/// [name] in [environment]; on Windows, in any case.
String? _lookUp(Map<String, String> environment, String name, TerminalOs os) {
  if (environment[name] case final value?) return value;
  if (os != TerminalOs.windows) return null;
  final upper = name.toUpperCase();
  for (final MapEntry(:key, :value) in environment.entries) {
    if (key.toUpperCase() == upper) return value;
  }
  return null;
}
