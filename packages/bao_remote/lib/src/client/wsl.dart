import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ssh_launcher.dart';

/// The hosts of this machine's WSL distributions (`wsl+Ubuntu`…; see
/// [SshTarget.wslDistro]), as `wsl.exe --list` names them; none off
/// Windows, without WSL, or when it does not answer in time.
Future<List<String>> wslHosts({String wsl = 'wsl.exe'}) async {
  if (!Platform.isWindows) return const [];
  try {
    final process = await Process.start(wsl, const [
      '--list',
      '--quiet',
    ], environment: const {'WSL_UTF8': '1'});
    unawaited(process.stdin.close().catchError((Object _) {}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    final output = process.stdout.fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    final code = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    if (code != 0) return const [];
    return [
      for (final distro in wslDistributions(await output))
        SshTarget.wslHost(distro),
    ];
  } on ProcessException {
    return const [];
  }
}

/// The distributions `wsl.exe --list --quiet` printed as [bytes]: UTF-16
/// (as it prints unless `WSL_UTF8` is set, which older ones ignore) or
/// UTF-8, one a line. Docker Desktop's own are left out: not for projects.
List<String> wslDistributions(List<int> bytes) {
  // Little-endian: a byte order mark, or an ASCII name's high zero byte.
  final utf16 =
      bytes.length >= 2 &&
      bytes.length.isEven &&
      (bytes[1] == 0 || bytes[0] == 0xFF && bytes[1] == 0xFE);
  final String text;
  if (utf16) {
    text = String.fromCharCodes([
      for (var i = 0; i + 1 < bytes.length; i += 2)
        bytes[i] | (bytes[i + 1] << 8),
    ]);
  } else {
    text = utf8.decode(bytes, allowMalformed: true);
  }
  return [
    for (final line in const LineSplitter().convert(text))
      if (line.replaceAll('\u0000', '').replaceAll('\uFEFF', '').trim()
          case final distro
          when distro.isNotEmpty &&
              SshTarget.isValid(distro) &&
              !distro.startsWith('docker-desktop'))
        distro,
  ];
}
