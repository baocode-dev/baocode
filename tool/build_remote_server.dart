// Builds baocode-server, the app's side on a remote host (see
// packages/bao_remote), for Linux on x64 and arm64: `dart compile exe`
// cross-compiles both from this machine. Run from anywhere in the
// repository:
//
//   dart run tool/build_remote_server.dart              into build/remote/
//   dart run tool/build_remote_server.dart --out <dir>  into <dir>
//
// It writes baocode-server-linux-x64, baocode-server-linux-arm64 and
// VERSION, which names this build: the app connects to a host and puts the
// server in ~/.baocode-server/<VERSION>/ there unless it is already. A
// debug run of the app finds build/remote/.
//
// Besides, each build gzipped (baocode-server-linux-<arch>.gz) and
// servers.json, which says where each is downloaded from and its size and
// SHA-256. The installers carry VERSION and servers.json only, not the
// builds (tool/build_macos.dart, tool/build_windows.dart): the app
// downloads the one a host needs the first time, checks it against
// servers.json, and keeps it (lib/remote/remote_binaries.dart). The .gz
// files are uploaded to where servers.json says.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _architectures = ['x64', 'arm64'];

/// Where the gzipped builds are downloaded from: `<base>/<VERSION>/<file>`.
const _downloadsBase = 'https://baocode.dev/releases/remote';

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

  final digests = <int>[];
  for (final arch in _architectures) {
    final output = '${out.path}/baocode-server-linux-$arch';
    _step('Compiling baocode-server for Linux $arch');
    await _run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '--target-os',
      'linux',
      '--target-arch',
      arch,
      '-Dbaocode.version=$version',
      '-o',
      output,
      source,
    ], root.path);
    digests.addAll(sha256.convert(File(output).readAsBytesSync()).bytes);
  }

  // The app's version, and what was built: a build of other sources is
  // another folder on the host even at the same version.
  final hash = sha256.convert(digests).toString().substring(0, 12);
  final name = '${version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '.')}-$hash';
  File('${out.path}/VERSION').writeAsStringSync('$name\n');

  _step('Compressing the builds for download');
  final files = <String, Object?>{};
  for (final arch in _architectures) {
    final file = 'baocode-server-linux-$arch.gz';
    final bytes = GZipCodec(
      level: 9,
    ).encode(File('${out.path}/baocode-server-linux-$arch').readAsBytesSync());
    File('${out.path}/$file').writeAsBytesSync(bytes);
    files[arch] = {
      'url': '$_downloadsBase/$name/$file',
      'size': bytes.length,
      'sha256': '${sha256.convert(bytes)}',
    };
    stdout.writeln('  $file (${(bytes.length / 1048576).toStringAsFixed(1)} MB)');
  }
  File('${out.path}/servers.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'version': name, 'files': files})}\n',
  );
  _step('Done: ${out.path} ($name)');
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
