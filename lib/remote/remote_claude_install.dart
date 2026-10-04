// Claude Code put on a remote host where the user has none, as VS Code's
// Claude Code extension comes with its own when it is installed on a
// remote: the official build for the host's platform, checked against its
// manifest, in the server's folder there (nothing of the user's, their
// PATH or ~/.local, is touched). The host downloads it; one that cannot
// reach the downloads is sent the build this machine downloaded, over the
// connection.

import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/claude.dart';
import 'package:path/path.dart' as p;

import 'ssh_host.dart';

final Map<SshHost, Future<void>> _installing = {};

/// Installs Claude Code on [host]: once at a time however often asked, its
/// progress on [SshHost.installingClaude]. Throws ClaudeDownloadFailed for
/// neither the host nor this machine able to get it.
Future<void> installRemoteClaude(SshHost host, {Directory? downloads}) =>
    _installing[host] ??= _install(host, downloads).whenComplete(() {
      _installing.remove(host);
      host.installingClaude = null;
    });

Future<void> _install(SshHost host, Directory? downloads) async {
  final client = await host.ready;
  host.installingClaude = const ClaudeInstallProgress(0, null);
  try {
    await client.installClaude(
      onProgress: (received, size) =>
          host.installingClaude = ClaudeInstallProgress(received, size),
    );
    return;
  } on ClaudeDownloadFailed {
    // The host cannot reach the downloads (or got them wrong): from here.
  }
  final platform = client.hello?.platform;
  if (platform == null) {
    throw const ClaudeDownloadFailed('The host did not say what it runs');
  }
  final release = ClaudeRelease();
  final build = await release.current(ClaudeRelease.platformOf(platform));
  final file = File(
    p.join(
      (downloads ?? Directory(p.join(Directory.systemTemp.path, 'baocode')))
          .path,
      'claude-${build.version}-${build.platform}',
    ),
  );
  // One download here for every host of the platform.
  if (!await ClaudeRelease.holds(file, build)) {
    await release.download(
      build,
      file,
      onProgress: (received) =>
          host.installingClaude = ClaudeInstallProgress(received, build.size),
    );
  }
  await client.uploadClaude(
    build,
    file,
    onProgress: (sent, size) => host.installingClaude = ClaudeInstallProgress(
      sent,
      size,
      uploading: true,
    ),
  );
}
