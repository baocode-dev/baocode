import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/local.dart' show AppPaths;
import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import 'magpie.dart';

/// What there is of magpie here: its settings (where its gateway listens),
/// and whether the gateway answers.
Future<MagpieStatus> probeMagpie() async {
  final environment = await ClaudeEnvironment.of();
  final dir = magpieDirectory(environment);
  var installed = false;
  var port = Magpie.defaultPort;
  if (dir != null) {
    installed = await Directory(dir).exists();
    try {
      final settings = File(p.join(dir, 'settings.json'));
      port = Magpie.portOf(jsonDecode(await settings.readAsString()));
    } on Object {
      // None, or not to be read: the gateway's own port.
    }
  }
  final version = await _version(port, installed: installed);
  return MagpieStatus(
    installed: installed || version != null,
    port: port,
    version: version,
  );
}

/// Where magpie keeps its settings: `$XDG_CONFIG_HOME/magpie`, else
/// `~/.config/magpie`, on Windows too (under the user's folder).
String? magpieDirectory(Map<String, String> environment) {
  if (environment['XDG_CONFIG_HOME'] case final config?
      when config.isNotEmpty) {
    return p.join(config, 'magpie');
  }
  final home = AppPaths.home(environment);
  return home.isEmpty ? null : p.join(home, '.config', 'magpie');
}

/// The version of the magpie at [port], as `/api/hello` answers; one before
/// that answers `/api/version` alone, where magpie is [installed] (an
/// Ollama answers it too). Null when none answers.
Future<String?> _version(int port, {required bool installed}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    // This machine's: never through the user's proxy.
    ..findProxy = (_) => 'DIRECT';
  Future<(int, Object?)> get(String path) async {
    final request = await client.getUrl(
      Uri.parse('${Magpie.baseUrl(port)}$path'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    final text = await utf8.decodeStream(response);
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    return (response.statusCode, json);
  }

  try {
    final (status, hello) = await get('/api/hello');
    if (status == 200) return Magpie.versionOf(hello);
    if (status == 404 && installed) {
      if (await get('/api/version') case (
        200,
        {'version': final String version},
      )) {
        return version;
      }
    }
    return null;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Claude Code's settings.json, decoded; null when there is none to read.
Future<Object?> readClaudeSettings() async {
  try {
    final dir = await ClaudeEnvironment.configDir();
    if (dir.isEmpty) return null;
    return jsonDecode(await File(p.join(dir, 'settings.json')).readAsString());
  } on Object {
    return null;
  }
}
