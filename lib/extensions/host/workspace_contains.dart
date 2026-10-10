// Whether a folder of the workspace holds what an extension's
// `workspaceContains:` activation events ask for.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/workspaceContains.ts
// (`checkActivateWorkspaceContainsExtension`; the glob search is
// `checkGlobFileExists`, the workbench's file search with `exists`).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

/// How long the glob patterns are searched for (`WORKSPACE_CONTAINS_TIMEOUT`).
const workspaceContainsTimeout = Duration(seconds: 7);

/// `IExtensionActivationHost`.
abstract interface class ExtensionActivationHost {
  List<VsUri> get folders;

  /// Every pattern goes through the search (a remote workspace).
  bool get forceUsingSearch;

  Future<bool> exists(VsUri uri);

  /// A file matching one of [includes] is in [folders].
  Future<bool> checkExists(
    List<VsUri> folders,
    List<String> includes,
    CancellationToken token,
  );
}

/// The `workspaceContains:` event of [activationEvents] the workspace
/// meets, or null.
Future<String?> checkActivateWorkspaceContainsExtension(
  ExtensionActivationHost host,
  List<String> activationEvents,
) async {
  const prefix = 'workspaceContains:';
  final fileNames = <String>[];
  final globPatterns = <String>[];
  for (final event in activationEvents) {
    if (!event.startsWith(prefix)) continue;
    final fileNameOrGlob = event.substring(prefix.length);
    if (fileNameOrGlob.contains('*') ||
        fileNameOrGlob.contains('?') ||
        host.forceUsingSearch) {
      globPatterns.add(fileNameOrGlob);
    } else {
      fileNames.add(fileNameOrGlob);
    }
  }
  if (fileNames.isEmpty && globPatterns.isEmpty) return null;

  final result = Completer<String?>();
  void activate(String event) {
    if (!result.isCompleted) result.complete(event);
  }

  unawaited(
    Future.wait([
      for (final fileName in fileNames)
        _activateIfFileName(host, fileName, activate),
      _activateIfGlobPatterns(host, globPatterns, activate),
    ]).whenComplete(() {
      if (!result.isCompleted) result.complete(null);
    }),
  );
  return result.future;
}

Future<void> _activateIfFileName(
  ExtensionActivationHost host,
  String fileName,
  void Function(String event) activate,
) async {
  for (final folder in host.folders) {
    if (await host.exists(folder.joinPath([fileName]))) {
      activate('workspaceContains:$fileName');
      return;
    }
  }
}

Future<void> _activateIfGlobPatterns(
  ExtensionActivationHost host,
  List<String> globPatterns,
  void Function(String event) activate,
) async {
  if (globPatterns.isEmpty) return;
  final tokenSource = CancellationTokenSource();
  final timer = Timer(workspaceContainsTimeout, tokenSource.cancel);
  var exists = false;
  try {
    exists = await host.checkExists(
      host.folders,
      globPatterns,
      tokenSource.token,
    );
  } on CancellationException {
    // Timed out.
  } finally {
    timer.cancel();
  }
  if (exists) activate('workspaceContains:${globPatterns.join(',')}');
}
