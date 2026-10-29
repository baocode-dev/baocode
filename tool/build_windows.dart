// Builds the Windows distribution: the Release bundle, then the installer
// Inno Setup makes of it. Run from anywhere in the repository:
//
//   dart run tool/build_windows.dart                build, then package
//   dart run tool/build_windows.dart --skip-build   package what is built
//   dart run tool/build_windows.dart --remote-built take the remote server
//                                                  already in build\remote\
//                                                  (CI builds it once, for
//                                                  both apps)
//   dart run tool/build_windows.dart --remote-release [VERSION]
//                                                  take the remote server
//                                                  published (the newest
//                                                  without VERSION; tool/
//                                                  fetch_remote_server.dart)
//                                                  instead of building one
//   dart run tool/build_windows.dart --patched-engine
//                                                  put in tool/engine's
//                                                  flutter_windows.dll (x64)
//   dart run tool/build_windows.dart --channel      the channel build
//                                                  (BAOCODE_CHANNEL;
//                                                  lib/channel/), its
//                                                  installer named
//                                                  -setup-channel.exe
//   dart run tool/build_windows.dart --arch arm64   say which processor
//                                                  flutter builds for: this
//                                                  machine's (flutter builds
//                                                  for no other), told by
//                                                  the Dart running this
//                                                  when not given. Arm's
//                                                  installer is named
//                                                  -setup-arm64.exe
//
// The bundle keeps Flutter's own flutter_windows.dll: the app draws with
// Skia (windows/runner/main.cpp), and tool/engine/windows_text.patch only
// changes Impeller's text (see tool/engine/README.md). --patched-engine puts
// that engine in, for x64; there is none built for arm64.
//
// The bundle carries OpenSSH for Windows (openssh\), Microsoft's build, for
// remote projects where the system's ssh is too old to ask for a password
// (Windows 10's 8.1): downloaded once into build\openssh\ and checked.
//
// The Dart code's symbols are saved as it is built, to build\symbols\
// app.windows-<x64|arm64>.symbols: the hang reports name its frames by their
// offsets in app.so (windows/runner/hang_watchdog.cpp), which
// `llvm-symbolizer --obj=` that file turns into functions and lines. Only
// saved: the app's own stack traces stay as they were, named.
//
// The installer lands in build/installers/; beside it, remote\<VERSION>\,
// the remote server's gzipped builds, which the app downloads instead of
// carrying them (tool/build_remote_server.dart), to upload with the
// release.
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Where the bundle flutter leaves behind goes (for [arch]), and where the
/// installer is written. Under build/, which the repository already ignores
/// and flutter clean already removes.
String _bundleRelative(String arch) => 'build\\windows\\$arch\\runner\\Release';
const _installersRelative = r'build\installers';
const _symbolsRelative = r'build\symbols';

/// What has to be in the bundle for the app to start. A Release build that
/// fails at the link step (a running baocode.exe holding the output file) still
/// leaves a baocode.exe behind — but data\ is written by the install step that
/// failure skipped, and the executable cannot start without it.
const _required = [
  'baocode.exe',
  'flutter_windows.dll',
  // The browsers' native messaging host and its manifest, which the
  // installer's keys point the browsers to (windows/BrowserBridge).
  'baocode-browser-host.exe',
  'dev.baocode.browser.json',
  // The VC++ runtime, carried rather than taken from System32, which may
  // be older than the build's (see windows/CMakeLists.txt).
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  r'data\app.so',
  r'data\icudtl.dat',
  r'data\flutter_assets',
];

/// The OpenSSH for Windows release the bundle carries (Win32-OpenSSH's
/// OpenSSH-Win64.zip, OpenSSH-ARM64.zip for arm64), their SHA-256, and what
/// of it goes in `openssh\`: the client, ssh-keygen (to forget a host's
/// changed key), their library and their licenses. The app takes it over the system's ssh where that one is
/// older than 8.4 or missing (chooseSsh in package:bao_remote).
const _openSshRelease = '10.0.0.0p2-Preview';
const _openSshBuilds = {
  'x64': (
    name: 'OpenSSH-Win64',
    sha256: '23f50f3458c4c5d0b12217c6a5ddfde0137210a30fa870e98b29827f7b43aba5',
  ),
  'arm64': (
    name: 'OpenSSH-ARM64',
    sha256: '698c6aec31c1dd0fb996206e8741f4531a97355686b5431ef347d531b07fcd42',
  ),
};
const _openSshFiles = [
  'ssh.exe',
  'ssh-keygen.exe',
  'libcrypto.dll',
  'LICENSE.txt',
  'NOTICE.txt',
];

/// SHA-256 of Flutter's own release flutter_windows.dll that
/// tool/engine/flutter_windows.dll was built to replace (3.47.5), and of that
/// one. The patched engine only fits the Dart snapshot of the same Flutter.
const _stockEngineSha256 =
    '8bd7b61eee31aa436edb182db41624d1cd3b2688a7e03622320dbeae067b5251';
const _patchedEngineSha256 =
    'd20feefdf335b0e3ae92f4e2f1b1892b5bd9d4c80b194b14b8bb87b34b9591d5';

Future<void> main(List<String> arguments) async {
  if (!Platform.isWindows) {
    _fail(
      'This builds the Windows installer, and only runs on Windows.\n'
      'On macOS, use tool/build_macos.dart.',
    );
  }
  final skipBuild = arguments.contains('--skip-build');
  final remoteBuilt = arguments.contains('--remote-built');
  final releaseAt = arguments.indexOf('--remote-release');
  final remoteRelease = releaseAt < 0
      ? null
      : releaseAt + 1 < arguments.length &&
            !arguments[releaseAt + 1].startsWith('--')
      ? arguments[releaseAt + 1]
      : 'latest';
  final channel = arguments.contains('--channel');
  final archAt = arguments.indexOf('--arch');
  final arch = archAt >= 0 && archAt + 1 < arguments.length
      ? arguments[archAt + 1]
      : Abi.current() == Abi.windowsArm64
      ? 'arm64'
      : 'x64';
  if (!_openSshBuilds.containsKey(arch)) {
    _fail('--arch is x64 or arm64, not $arch.');
  }
  final patchedEngine = arguments.contains('--patched-engine');
  // No patched engine built for arm64.
  if (patchedEngine && arch != 'x64') {
    _fail('There is no patched engine built for $arch.');
  }

  // The script lives in tool/, so the repository is one level above it.
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final bundle = Directory('${root.path}\\${_bundleRelative(arch)}');
  final installers = Directory('${root.path}\\$_installersRelative');
  final version = _readVersion(File('${root.path}\\pubspec.yaml'));

  if (!skipBuild) {
    _step(
      'Building the Release bundle for $arch'
      '${channel ? ' (the channel build)' : ''}',
    );
    final symbols = Directory('${root.path}\\$_symbolsRelative')
      ..createSync(recursive: true);
    await _run('flutter', [
      'build',
      'windows',
      '--release',
      if (channel) '--dart-define=BAOCODE_CHANNEL=true',
      // Not --split-debug-info, which would also leave the app's stack
      // traces (errors.log) unnamed, as offsets.
      '--extra-gen-snapshot-options=--save-debugging-info='
          '${symbols.path}\\app.windows-$arch.symbols',
    ], root.path);
  } else {
    _step('Using the bundle already built');
  }

  _step('Checking the bundle');
  _checkBundle(bundle, _required);

  if (patchedEngine) {
    _step('Putting in the patched engine');
    _swapEngine(root, bundle);
  } else {
    _step('Keeping Flutter\'s own engine');
  }

  // The server remote projects run on their host (Linux and macOS, x64 and
  // arm64; macOS ones only when built on a Mac):
  // which build, and where it is downloaded from, beside the executable
  // (the installer takes the bundle whole); not the builds themselves,
  // which the app downloads.
  final remote = Directory(
    '${root.path}\\build\\${remoteRelease == null ? 'remote' : 'remote-release'}',
  );
  if (remoteRelease != null) {
    _step('Taking the remote server published');
    await _run(Platform.resolvedExecutable, [
      'run',
      '${root.path}\\tool\\fetch_remote_server.dart',
      remoteRelease,
      '--out',
      remote.path,
    ], root.path);
  } else if (remoteBuilt) {
    _step('Using the remote server already built');
    if (!File('${remote.path}\\servers.json').existsSync()) {
      _fail('No remote server built in ${remote.path}.');
    }
  } else {
    _step('Building the remote server');
    await _run(Platform.resolvedExecutable, [
      'run',
      '${root.path}\\tool\\build_remote_server.dart',
      '--out',
      remote.path,
    ], root.path);
  }
  final bundleRemote = Directory('${bundle.path}\\remote');
  // The builds an older run put there go.
  if (bundleRemote.existsSync()) bundleRemote.deleteSync(recursive: true);
  bundleRemote.createSync(recursive: true);
  for (final name in ['VERSION', 'servers.json']) {
    File('${remote.path}\\$name').copySync('${bundleRemote.path}\\$name');
  }
  _checkBundle(bundle, [r'remote\VERSION', r'remote\servers.json']);
  final remoteVersion = File('${remote.path}\\VERSION')
      .readAsStringSync()
      .trim();

  _step('Putting in OpenSSH for Windows $_openSshRelease ($arch)');
  await _putOpenSsh(root, bundle, arch);
  _checkBundle(bundle, [for (final name in _openSshFiles) 'openssh\\$name']);

  _step('Compiling the installer');
  final iscc = _findIscc();
  installers.createSync(recursive: true);
  await _run(iscc, [
    '/DBundleDir=${bundle.path}',
    '/DAppVersion=${version.full}',
    '/DOutDir=${installers.path}',
    '/DArch=$arch',
    if (channel) '/DEdition=-channel',
    '${root.path}\\tool\\baocode.iss',
  ], root.path);

  // None when published already (--remote-release).
  final downloads = Directory('${installers.path}\\remote\\$remoteVersion');
  final builds = [
    for (final file in remote.listSync())
      if (file is File && file.path.endsWith('.gz')) file,
  ];
  if (builds.isNotEmpty) {
    _step('Putting the remote server\'s builds beside it');
    downloads.createSync(recursive: true);
  }
  final servers = [
    for (final file in builds)
      file.copySync('${downloads.path}\\${file.uri.pathSegments.last}'),
  ];

  _step('Done');
  final installer = File(
    '${installers.path}\\BaoCode-${version.marketing}-setup'
    '${arch == 'x64' ? '' : '-$arch'}${channel ? '-channel' : ''}.exe',
  );
  for (final file in [installer, ...servers]) {
    if (!file.existsSync()) continue;
    final mb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    stdout.writeln('  ${file.path}  ($mb MB)');
  }
  if (servers.isEmpty) {
    stdout
      ..writeln()
      ..writeln('The app downloads the remote server published:')
      ..writeln('  https://dl.baocode.dev/releases/remote/$remoteVersion/');
  } else {
    stdout
      ..writeln()
      ..writeln('Upload the remote server\'s builds, which the app downloads')
      ..writeln('(their folder is named by the build: the macOS one\'s, if it')
      ..writeln('differs, goes beside it; or publish them with a server-* tag')
      ..writeln('and package with --remote-release):')
      ..writeln(
        '  ${downloads.path}\\*  ->  '
        'https://dl.baocode.dev/releases/remote/$remoteVersion/',
      );
  }
  stdout.writeln();
  stdout.writeln(
    'The bundle carries the Visual C++ runtime it was built with (see\n'
    'windows/CMakeLists.txt).',
  );
}

/// The version pubspec.yaml carries, as `1.0.0+1`: the whole of it, the part
/// Windows records as the product version, and the build number after it.
({String full, String marketing, String build}) _readVersion(File pubspec) {
  final text = pubspec.readAsStringSync();
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(text);
  if (match == null) {
    _fail('No "version:" line in ${pubspec.path}');
  }
  final full = match.group(1)!;
  final plus = full.indexOf('+');
  return (
    full: full,
    marketing: plus < 0 ? full : full.substring(0, plus),
    build: plus < 0 ? '0' : full.substring(plus + 1),
  );
}

/// Stops unless [directory] holds every one of [required].
void _checkBundle(Directory directory, List<String> required) {
  if (!directory.existsSync()) {
    _fail(
      'No bundle at ${directory.path}.\n'
      'Build it first, without --skip-build.',
    );
  }
  final missing = [
    for (final item in required)
      if (FileSystemEntity.typeSync('${directory.path}\\$item') ==
          FileSystemEntityType.notFound)
        item,
  ];
  if (missing.isEmpty) {
    stdout.writeln('  ${directory.path} looks complete.');
    return;
  }
  _fail(
    'The bundle at ${directory.path} is incomplete; missing:\n'
    '${missing.map((item) => '  $item').join('\n')}\n'
    '\n'
    'A Release build that failed at the link step leaves exactly this: the\n'
    'install step that writes data\\ never ran. If the build reported\n'
    'LNK1104, a running baocode.exe is holding the output file — close it and\n'
    'build again.',
  );
}

/// Replaces the bundle's flutter_windows.dll with tool/engine's, provided the
/// bundle's is the stock engine that one was built from (or it already is).
void _swapEngine(Directory root, Directory bundle) {
  final patched = File('${root.path}\\tool\\engine\\flutter_windows.dll');
  final target = File('${bundle.path}\\flutter_windows.dll');
  String sha256Of(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();

  if (!patched.existsSync()) _fail('No patched engine at ${patched.path}.');
  if (sha256Of(patched) != _patchedEngineSha256) {
    _fail(
      '${patched.path} is not the engine this script expects.\n'
      'After rebuilding it, update _patchedEngineSha256 in this script.',
    );
  }
  final current = sha256Of(target);
  if (current == _patchedEngineSha256) {
    stdout.writeln('  The bundle already has it.');
    return;
  }
  if (current != _stockEngineSha256) {
    _fail(
      'The bundle\'s flutter_windows.dll is not the stock engine the patched\n'
      'one replaces, so Flutter has changed version. Rebuild the engine with\n'
      'tool/engine/build_windows_engine.ps1 -Tag <the new version> -Mode release,\n'
      'put its flutter_windows.dll in tool/engine, and update both hashes in\n'
      'this script; or build without --patched-engine.\n'
      '  bundle: $current',
    );
  }
  patched.copySync(target.path);
  stdout.writeln('  ${target.path} replaced.');
}

/// Puts [_openSshFiles] of the OpenSSH release for [arch] in the bundle's
/// `openssh\`: downloaded into build\openssh\ once, and checked against
/// its SHA-256 ([_openSshBuilds]) each time.
Future<void> _putOpenSsh(Directory root, Directory bundle, String arch) async {
  final (name: build, sha256: expected) = _openSshBuilds[arch]!;
  final cache = Directory('${root.path}\\build\\openssh');
  final zip = File('${cache.path}\\$build-$_openSshRelease.zip');
  String sha256Of(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();
  if (!zip.existsSync() || sha256Of(zip) != expected) {
    final url = Uri.parse(
      'https://github.com/PowerShell/Win32-OpenSSH/releases/download/'
      '$_openSshRelease/$build.zip',
    );
    stdout.writeln('  Downloading $url');
    cache.createSync(recursive: true);
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(url)).close();
      if (response.statusCode != 200) {
        _fail('$url answered ${response.statusCode}.');
      }
      await response.pipe(zip.openWrite());
    } finally {
      client.close();
    }
    if (sha256Of(zip) != expected) {
      zip.deleteSync();
      _fail(
        'The OpenSSH download is not the one this script expects.\n'
        'After choosing another release, update _openSshRelease and\n'
        '_openSshBuilds in this script.',
      );
    }
  }
  final unpacked = Directory('${cache.path}\\$build-$_openSshRelease');
  if (unpacked.existsSync()) unpacked.deleteSync(recursive: true);
  unpacked.createSync(recursive: true);
  // Windows' own tar (bsdtar) reads zips.
  await _run('tar', ['-xf', zip.path, '-C', unpacked.path], root.path);
  final target = Directory('${bundle.path}\\openssh');
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  for (final name in _openSshFiles) {
    final file = File('${unpacked.path}\\$build\\$name');
    if (!file.existsSync()) _fail('No $name in the OpenSSH release.');
    file.copySync('${target.path}\\$name');
  }
}

/// The Inno Setup compiler: where winget puts it, then where a manual
/// install does, then wherever the PATH has it.
String _findIscc() {
  final local = Platform.environment['LOCALAPPDATA'];
  final candidates = [
    if (local != null) '$local\\Programs\\Inno Setup 6\\ISCC.exe',
    for (final variable in ['ProgramFiles(x86)', 'ProgramFiles'])
      if (Platform.environment[variable] case final root?)
        '$root\\Inno Setup 6\\ISCC.exe',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  _fail(
    'ISCC.exe (the Inno Setup compiler) was not found. Install it with:\n'
    '\n'
    '  winget install --id JRSoftware.InnoSetup\n'
    '\n'
    'or download it from https://jrsoftware.org/isdl.php',
  );
}

/// Runs [executable], printing the command; stops the script on a non-zero
/// exit. A .bat (flutter's own launcher, on Windows) needs a shell.
Future<void> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  stdout.writeln('  \$ $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: executable == 'flutter',
  );
  final output = '${result.stdout}'.trim();
  if (output.isNotEmpty) stdout.writeln(output);
  final error = '${result.stderr}'.trim();
  if (error.isNotEmpty) stderr.writeln(error);
  if (result.exitCode != 0) {
    _fail('$executable exited with code ${result.exitCode}.');
  }
}

void _step(String message) => stdout.writeln('\n==> $message');

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
