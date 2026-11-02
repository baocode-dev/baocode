import 'dart:async';

import 'package:path/path.dart' as p;

import 'lsp_protocol.dart';
import 'lsp_server_definition.dart';

// Vue's language tools (vuejs/language-tools 3.x) split a `.vue` file
// between two servers, as VS Code runs them:
//
// - vue-language-server answers for the template and the styles. What it
//   needs of TypeScript (a file's project, a component's props, …) it asks
//   the client with `tsserver/request` notifications, and waits for the
//   `tsserver/response`, every request of its own held up meanwhile.
// - tsserver, with `@vue/typescript-plugin`, answers everything TypeScript:
//   the script, and the template's expressions, props and events (go to
//   definition, references, hover, rename, …).
//
// The manager adds the plugin to a TypeScript server it starts
// ([withTypeScriptPlugin]) and carries vue-language-server's requests to
// it (`workspace/executeCommand` [tsserverRequestCommand]).

/// The command a TypeScript server runs a tsserver request with.
const tsserverRequestCommand = 'typescript.tsserverRequest';

const vuePluginName = '@vue/typescript-plugin';
const _vueServerPackage = '@vue/language-server';

String _commandName(LspServerDefinition server) {
  final name = server.command.split(RegExp(r'[/\\]')).last.toLowerCase();
  for (final suffix in const ['.cmd', '.exe', '.bat', '.js']) {
    if (name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

/// Whether [server] runs tsserver and takes its plugins: typescript-language-server
/// (`initializationOptions.plugins`) or vtsls (`vtsls.tsserver.globalPlugins`).
bool isTypeScriptServer(LspServerDefinition server) => const {
  'typescript-language-server',
  'vtsls',
}.contains(_commandName(server));

/// Whether [server] is Vue's, which asks a TypeScript server through the
/// client.
bool isVueLanguageServer(LspServerDefinition server) =>
    _commandName(server) == 'vue-language-server';

/// [server] with the tsserver plugin [name] at [location] (a folder it
/// resolves from), for documents in [languages]; [server] when it is not a
/// TypeScript server or already has the plugin.
LspServerDefinition withTypeScriptPlugin(
  LspServerDefinition server, {
  required String name,
  required String location,
  List<String> languages = const [],
}) {
  JsonMap? initializationOptions = server.initializationOptions;
  JsonMap? settings = server.settings;
  bool named(Object? plugin) => plugin is Map && plugin['name'] == name;
  switch (_commandName(server)) {
    case 'typescript-language-server':
      final plugins = [...?(initializationOptions?['plugins'] as List?)];
      if (plugins.any(named)) return server;
      initializationOptions = {
        ...?initializationOptions,
        'plugins': [
          ...plugins,
          {'name': name, 'location': location, 'languages': languages},
        ],
      };
    case 'vtsls':
      final vtsls = (settings?['vtsls'] as Map?)?.cast<String, Object?>();
      final tsserver = (vtsls?['tsserver'] as Map?)?.cast<String, Object?>();
      final plugins = [...?(tsserver?['globalPlugins'] as List?)];
      if (plugins.any(named)) return server;
      settings = {
        ...?settings,
        'vtsls': {
          ...?vtsls,
          'tsserver': {
            ...?tsserver,
            'globalPlugins': [
              ...plugins,
              {
                'name': name,
                'location': location,
                'languages': languages,
                'configNamespace': 'typescript',
                'enableForWorkspaceTypeScriptVersions': true,
              },
            ],
          },
        },
      };
    default:
      return server;
  }
  return LspServerDefinition(
    id: server.id,
    command: server.command,
    args: server.args,
    environment: server.environment,
    initializationOptions: initializationOptions,
    settings: settings,
    rootMarkers: server.rootMarkers,
    masonPackage: server.masonPackage,
    requiredRoot: server.requiredRoot,
    onlyFeatures: server.onlyFeatures,
    exceptFeatures: server.exceptFeatures,
  );
}

/// The `@vue/language-server` package folder of a vue-language-server
/// [executable]: the package itself, or a `node_modules` (or npm's global
/// `lib/node_modules`) holding it, beside the executable or above it.
/// `@vue/typescript-plugin` resolves from there, in the version that
/// server speaks.
///
/// mason: `<package>/node_modules/.bin/vue-language-server`; npm global:
/// `<prefix>/bin/vue-language-server` (`lib/node_modules`) or, on Windows,
/// `%APPDATA%\npm\vue-language-server.cmd` (`node_modules`).
Future<String?> vueLanguageServerPackage(
  String executable, {
  required p.Context paths,
  required FutureOr<bool> Function(String path) exists,
}) async {
  var dir = paths.dirname(executable);
  for (var depth = 0; depth < 8; depth++) {
    final candidates = [
      if (paths.basename(dir) == 'language-server' &&
          paths.basename(paths.dirname(dir)) == '@vue')
        dir,
      paths.join(dir, 'node_modules', '@vue', 'language-server'),
      paths.join(dir, 'lib', 'node_modules', '@vue', 'language-server'),
    ];
    for (final candidate in candidates) {
      if (await exists(paths.join(candidate, 'package.json'))) {
        return candidate;
      }
    }
    final parent = paths.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  return null;
}

/// The folder [vuePluginName] resolves from for a project at [root] whose
/// own `node_modules` has it (or `@vue/language-server`, which brings it),
/// when no vue-language-server is found.
Future<String?> projectVuePlugin(
  String root, {
  required p.Context paths,
  required FutureOr<bool> Function(String path) exists,
}) async {
  for (final package in [vuePluginName, _vueServerPackage]) {
    if (await exists(
      paths.join(root, 'node_modules', package, 'package.json'),
    )) {
      return package == vuePluginName
          ? root
          : paths.join(root, 'node_modules', package);
    }
  }
  return null;
}

/// The requests in a `tsserver/request` notification's params: `[[id,
/// command, args], …]` (vscode-jsonrpc wraps the one array argument), or
/// a bare `[id, command, args]`.
List<(Object, String, Object?)> tsserverRequests(Object? params) {
  (Object, String, Object?)? one(Object? value) => switch (value) {
    [final Object id, final String command, ...] => (
      id,
      command,
      value.length > 2 ? value[2] : null,
    ),
    _ => null,
  };
  if (one(params) case final request?) return [request];
  return [
    if (params is List)
      for (final item in params) ?one(item),
  ];
}
