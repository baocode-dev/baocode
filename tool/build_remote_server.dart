// Builds baocode-server, the app's side on a remote host (see
// packages/bao_remote), for Linux, macOS and Windows on x64 and arm64. Run
// from anywhere in the repository:
//
//   dart run tool/build_remote_server.dart              into build/remote/
//   dart run tool/build_remote_server.dart --out <dir>  into <dir>
//   dart run tool/build_remote_server.dart --macos-x64-dart <dart>
//                     the macOS x64 build too, with an x64 Dart SDK's dart
//                     (run by Rosetta on Apple silicon); --macos-arm64-dart
//                     likewise
//   dart run tool/build_remote_server.dart --only windows-x64
//                     that build alone, and nothing else written: for
//                     --from on the machine that builds the rest (CI)
//   dart run tool/build_remote_server.dart --from <dir>
//                     the builds in <dir> too (baocode-server-<platform>),
//                     those of other machines; may be given more than once
//   dart run tool/build_remote_server.dart --all        fail unless all six
//                                                       are built (CI)
//
// `dart compile exe` cross-compiles the Linux builds from any machine, but
// builds for macOS only on a Mac and for Windows only on Windows, for the
// architecture of the Dart that runs it: this one's, and on a Mac the
// other's with the --macos-<arch>-dart given. Without them a host of that
// kind is refused (the app has no server for it).
//
// It writes baocode-server-<platform> (linux-x64, linux-arm64, darwin-x64,
// darwin-arm64, windows-x64, windows-arm64) and VERSION, which names this
// build: the app connects to a host and puts the server in
// ~/.baocode-server/<VERSION>/ there unless it is already. A debug run of
// the app finds build/remote/.
//
// Besides, each build gzipped (baocode-server-<platform>.gz) and
// servers.json, which says where each is downloaded from and its size and
// SHA-256. The installers carry VERSION and servers.json only, not the
// builds (tool/build_macos.dart, tool/build_windows.dart): the app
// downloads the one a host needs the first time, checks it against
// servers.json, and keeps it (lib/remote/remote_binaries.dart). The .gz
// files are uploaded to where servers.json says.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';

const _platforms = [
  'linux-x64',
  'linux-arm64',
  'darwin-x64',
  'darwin-arm64',
  'windows-x64',
  'windows-arm64',
];

/// Where the gzipped builds are downloaded from: `<base>/<VERSION>/<file>`.
const _downloadsBase = 'https://dl.baocode.dev/releases/remote';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final at = arguments.indexOf('--out');
  final out = Directory(
    at >= 0 && at + 1 < arguments.length
        ? arguments[at + 1]
        : '${root.path}/build/remote',
  )..createSync(recursive: true);
  final version = _readVersion(File('${root.path}/pubspec.yaml'));
  final source = '${root.path}/packages/bao_remote/bin/baocode_server.dart';
  String? option(String name) {
    final at = arguments.indexOf(name);
    return at >= 0 && at + 1 < arguments.length ? arguments[at + 1] : null;
  }

  final host = switch (Abi.current()) {
    Abi.macosArm64 => 'darwin-arm64',
    Abi.macosX64 => 'darwin-x64',
    Abi.windowsX64 => 'windows-x64',
    Abi.windowsArm64 => 'windows-arm64',
    _ => null,
  };
  final only = option('--only')?.split(',');
  if (only != null && only.any((platform) => !_platforms.contains(platform))) {
    _fail('--only takes some of ${_platforms.join(', ')}.');
  }
  final from = [
    for (final (i, argument) in arguments.indexed)
      if (argument == '--from' && i + 1 < arguments.length) arguments[i + 1],
  ];
  final digests = <int>[];
  final built = <String>[];
  for (final platform in only ?? _platforms) {
    final [os, arch] = platform.split('-');
    final output = '${out.path}/baocode-server-$platform';
    // Not left from an earlier run: servers.json names only those built.
    File(output).deleteIfExists();
    final carried = [
      for (final dir in from)
        if (File('$dir/baocode-server-$platform') case final file
            when file.existsSync())
          file,
    ].firstOrNull;
    if (carried != null) {
      _step(
        'Taking baocode-server for ${_describe(platform)} from ${carried.parent.path}',
      );
      carried.copySync(output);
      digests.addAll(sha256.convert(File(output).readAsBytesSync()).bytes);
      built.add(platform);
      continue;
    }
    final dart = os == 'linux' || platform == host
        ? Platform.resolvedExecutable
        : os == 'darwin'
        ? option('--macos-$arch-dart')
        : null;
    if (dart == null) {
      _step('Not building baocode-server for ${_describe(platform)}');
      stdout.writeln(switch (os) {
        'darwin' when Platform.isMacOS =>
          '  Give an $arch Dart SDK\'s dart with --macos-$arch-dart.',
        'darwin' => '  Only a Mac builds it.',
        _ => '  Only Windows on $arch builds it (then give it with --from).',
      });
      continue;
    }
    _step('Compiling baocode-server for ${_describe(platform)}');
    await _run(dart, [
      'compile',
      'exe',
      '--target-os',
      os == 'darwin' ? 'macos' : os,
      '--target-arch',
      arch,
      '-Dbaocode.version=$version',
      '-o',
      output,
      source,
    ], root.path);
    digests.addAll(sha256.convert(File(output).readAsBytesSync()).bytes);
    built.add(platform);
  }
  if (only != null) {
    if (built.length < only.length) {
      _fail('Not built: ${only.where((p) => !built.contains(p)).join(', ')}.');
    }
    _step('Done: ${built.join(', ')} in ${out.path}');
    return;
  }
  if (arguments.contains('--all') && built.length < _platforms.length) {
    _fail(
      'Not built: ${_platforms.where((p) => !built.contains(p)).join(', ')}.',
    );
  }

  // The app's version, and what was built: a build of other sources is
  // another folder on the host even at the same version.
  final hash = sha256.convert(digests).toString().substring(0, 12);
  final name = '${version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '.')}-$hash';
  File('${out.path}/VERSION').writeAsStringSync('$name\n');

  _step('Compressing the builds for download');
  final files = <String, Object?>{};
  for (final platform in _platforms) {
    final file = 'baocode-server-$platform.gz';
    File('${out.path}/$file').deleteIfExists();
    if (!built.contains(platform)) continue;
    final bytes = GZipCodec(level: 9)
        .encode(File('${out.path}/baocode-server-$platform').readAsBytesSync());
    File('${out.path}/$file').writeAsBytesSync(bytes);
    files[platform] = {
      'url': '$_downloadsBase/$name/$file',
      'size': bytes.length,
      'sha256': '${sha256.convert(bytes)}',
    };
    stdout.writeln(
      '  $file (${(bytes.length / 1048576).toStringAsFixed(1)} MB)',
    );
  }
  File('${out.path}/servers.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'version': name, 'files': files})}\n',
  );
  _step('Done: ${out.path} ($name)');
}

/// [platform] for people: `Linux x64`, `macOS arm64`, `Windows x64`.
String _describe(String platform) {
  final [os, arch] = platform.split('-');
  final name = switch (os) {
    'darwin' => 'macOS',
    'windows' => 'Windows',
    _ => 'Linux',
  };
  return '$name $arch';
}

extension on File {
  void deleteIfExists() {
    if (existsSync()) deleteSync();
  }
}

/// pubspec.yaml's `version:`.
String _readVersion(File pubspec) {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) _fail('No "version:" line in ${pubspec.path}');
  return match.group(1)!;
}

/// Runs [executable], printing the command; stops on a non-zero exit.
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
