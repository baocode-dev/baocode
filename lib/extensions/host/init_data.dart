/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What an extension host is started with (`IExtensionHostInitData`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/remoteExtensionHost.ts
// (`_createExtHostInitData`), extensionHostProtocol.ts (the types),
// src/vs/platform/workspaces/node/workspaces.ts
// (`getSingleFolderWorkspaceIdentifier`).
//
// Deviations:
// - `remote.authority` is null for the app's server on this machine (the
//   server's own URIs are mapped by the app, see server_uris.dart). A
//   remote project's host there is told the project's authority; this
//   machine's host for its ui extensions is not (the server would turn
//   the project's `vscode-remote:` URIs into its own `file:` ones), so
//   `vscode.env.remoteName` is undefined in it.
// - A folder's workspace id hashes its path only, not also its creation
//   time.

import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:crypto/crypto.dart';

import 'implicit_activation_events.dart';

/// The product the extension host is told it runs in.
final class ExtHostProduct {
  const ExtHostProduct({
    required this.commit,
    required this.version,
    this.quality = 'stable',
    this.date,
  });

  final String commit;
  final String version;
  final String? quality;
  final String? date;

  /// From the runtime's `product.json`.
  factory ExtHostProduct.fromJson(Map<String, Object?> product) =>
      ExtHostProduct(
        commit: product['commit'] as String,
        version: product['version'] as String,
        quality: product['quality'] as String?,
        date: product['date'] as String?,
      );
}

/// The folders an extension host serves.
final class ExtHostWorkspace {
  const ExtHostWorkspace({
    required this.id,
    required this.name,
    required this.folders,
    this.configuration,
    this.transient = false,
  });

  /// One folder.
  factory ExtHostWorkspace.folder(String path, {String? name}) {
    final uri = VsUri.file(path);
    return ExtHostWorkspace(
      id: folderWorkspaceId(path),
      name:
          name ??
          uri.path.split('/').where((s) => s.isNotEmpty).lastOrNull ??
          path,
      folders: [ExtHostWorkspaceFolder(uri, name ?? _basename(uri), 0)],
    );
  }

  final String id;
  final String name;
  final List<ExtHostWorkspaceFolder> folders;

  /// A `.code-workspace` file, when the workspace is one.
  final VsUri? configuration;
  final bool transient;

  /// `IStaticWorkspaceData`.
  Map<String, Object?> toStaticJson() => {
    'id': id,
    'name': name,
    'transient': transient,
    'configuration': configuration?.toJson(),
    'isUntitled': false,
  };

  /// `IWorkspaceData`, for `$initializeWorkspace`.
  Map<String, Object?> toJson() => {
    ...toStaticJson(),
    'folders': [for (final f in folders) f.toJson()],
  };

  /// `getSingleFolderWorkspaceIdentifier`'s id.
  static String folderWorkspaceId(String path) =>
      md5.convert(utf8.encode(path)).toString();

  static String _basename(VsUri uri) =>
      uri.path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? uri.path;
}

/// `IWorkspaceFolderData`.
final class ExtHostWorkspaceFolder {
  const ExtHostWorkspaceFolder(this.uri, this.name, this.index);

  final VsUri uri;
  final String name;
  final int index;

  Map<String, Object?> toJson() => {
    'uri': uri.toJson(),
    'name': name,
    'index': index,
  };
}

/// `LogLevel`.
enum ExtHostLogLevel { off, trace, debug, info, warning, error }

/// `_createExtHostInitData`: [environment] is the server's
/// (`getEnvironmentData`, with `file:` URIs), [extensions] all it scanned,
/// [myExtensions] the ids of those this host runs (all of them unless
/// some must run elsewhere).
Map<String, Object?> buildExtHostInitData({
  required ExtHostProduct product,
  required Map<String, Object?> environment,
  required List<Map<String, Object?>> extensions,
  required ExtHostWorkspace? workspace,
  required String language,
  required String sessionId,
  required String machineId,
  Iterable<String>? myExtensions,
  int extensionsVersionId = 0,
  List<VsUri> extensionDevelopmentLocations = const [],
  VsUri? extensionTestsLocation,
  bool isExtensionDevelopmentDebug = false,
  ExtHostLogLevel logLevel = ExtHostLogLevel.info,
  String firstSessionDate = '',
  bool autoStart = true,
  bool isRemote = false,
  String? remoteAuthority,
}) {
  final ids = [for (final e in extensions) _identifierValue(e['identifier'])];
  return {
    'commit': product.commit,
    'version': product.version,
    'quality': product.quality,
    'date': product.date,
    'parentPid': environment['pid'] ?? 0,
    'environment': {
      'isExtensionDevelopmentDebug': isExtensionDevelopmentDebug,
      'appRoot': environment['appRoot'],
      'appName': 'BaoCode',
      'appHost': 'desktop',
      'appUriScheme': 'baocode',
      'isExtensionTelemetryLoggingOnly': false,
      'appLanguage': language,
      if (extensionDevelopmentLocations.isNotEmpty)
        'extensionDevelopmentLocationURI': [
          for (final uri in extensionDevelopmentLocations) uri.toJson(),
        ],
      'extensionTestsLocationURI': ?extensionTestsLocation?.toJson(),
      'globalStorageHome': environment['globalStorageHome'],
      'workspaceStorageHome': environment['workspaceStorageHome'],
    },
    'workspace': workspace?.toStaticJson(),
    'remote': {
      'isRemote': isRemote,
      'authority': remoteAuthority,
      'connectionData': null,
    },
    'consoleForward': {'includeStack': false, 'logNative': false},
    'extensions': {
      'versionId': extensionsVersionId,
      'allExtensions': extensions,
      'activationEvents': createActivationEventsMap(extensions),
      'myExtensions': [
        for (final id in myExtensions ?? ids)
          {'value': id, '_lower': id.toLowerCase()},
      ],
    },
    'telemetryInfo': {
      'sessionId': sessionId,
      'machineId': machineId,
      'sqmId': '',
      'devDeviceId': machineId,
      'firstSessionDate': firstSessionDate,
    },
    'logLevel': logLevel.index,
    'loggers': const <Object?>[],
    'logsLocation': environment['extensionHostLogsPath'],
    'autoStart': autoStart,
    'uiKind': 1,
  };
}

String _identifierValue(Object? identifier) =>
    identifier is Map ? '${identifier['value']}' : '$identifier';

/// [initData] as a host whose connection transforms URIs with [transformer]
/// must be sent it: the URIs `ExtensionHostMain._transform` transforms on
/// the way in, transformed on the way out.
Map<String, Object?> transformInitDataOutgoing(
  Map<String, Object?> initData,
  UriTransformer transformer,
) {
  Object? out(Object? value) => transformOutgoingUris(value, transformer);
  final environment = {
    ...(initData['environment'] as Map).cast<String, Object?>(),
  };
  for (final key in const [
    'appRoot',
    'extensionDevelopmentLocationURI',
    'extensionTestsLocationURI',
    'globalStorageHome',
    'workspaceStorageHome',
  ]) {
    if (environment.containsKey(key)) environment[key] = out(environment[key]);
  }
  final extensions = {
    ...(initData['extensions'] as Map).cast<String, Object?>(),
  };
  extensions['allExtensions'] = [
    for (final e in extensions['allExtensions'] as List)
      {
        ...(e as Map).cast<String, Object?>(),
        if (e.containsKey('extensionLocation'))
          'extensionLocation': out(e['extensionLocation']),
      },
  ];
  return {
    ...initData,
    'environment': environment,
    'extensions': extensions,
    for (final key in const ['nlsBaseUrl', 'logsLocation', 'workspace'])
      if (initData.containsKey(key)) key: out(initData[key]),
  };
}
