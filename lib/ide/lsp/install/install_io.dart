import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fetches a URL into a file. Injected so tests never reach the network.
abstract interface class Downloader {
  /// Writes [url]'s body to [destination]; [onProgress] gets bytes so far
  /// and the total when known. Throws on failure (an HTTP error status
  /// included).
  Future<void> download(
    Uri url,
    String destination, {
    void Function(int received, int? total)? onProgress,
  });
}

/// Runs a command to completion. Injected so tests never run installers.
abstract interface class CommandRunner {
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

class CommandResult {
  const CommandResult(this.exitCode, {this.stdout = '', this.stderr = ''});

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Downloads over HTTPS with `dart:io`, following redirects (GitHub
/// release assets redirect to their storage), into a temporary file that
/// is renamed once complete.
class HttpDownloader implements Downloader {
  HttpDownloader({HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;

  @override
  Future<void> download(
    Uri url,
    String destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = _client()..userAgent = 'baocode-ide';
    final partial = File('$destination.part');
    try {
      final request = await client.getUrl(url);
      request.followRedirects = true;
      request.maxRedirects = 10;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      await partial.rename(destination);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }
}

/// Runs commands with `Process.run`; Windows batch files (`npm.cmd`) run
/// through the shell, as they must.
class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner();

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final lower = executable.toLowerCase();
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell:
          Platform.isWindows &&
          (lower.endsWith('.cmd') || lower.endsWith('.bat')),
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
    return CommandResult(
      result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }
}
