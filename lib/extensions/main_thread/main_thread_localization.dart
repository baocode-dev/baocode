/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadLocalization.ts and the language
// packs' translations of built-in extensions
// (src/vs/platform/languagePacks/node/languagePacks.ts:
// `getBuiltInExtensionTranslationsUri`, from the installed language pack
// extensions' `contributes.localizations[].translations`).
//
// Deviations: the language packs are read from the extensions the host
// runs (upstream keeps a cache file of the installed ones); bundles are
// read from the local file system.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';

import '../extension_host_service_io.dart';
import 'main_thread_context.dart';

/// The translations of built-in extensions that the language packs among
/// [extensions] contribute for [language]: extension id → file.
Map<String, VsUri> builtInTranslations(
  Iterable<Map<String, Object?>> extensions,
  String language,
) {
  final wanted = _locale(language);
  final result = <String, VsUri>{};
  for (final extension in extensions) {
    final contributes = extension['contributes'];
    if (contributes is! Map) continue;
    final localizations = contributes['localizations'];
    if (localizations is! List) continue;
    final location = VsUri.tryRevive(extension['extensionLocation']);
    if (location == null) continue;
    for (final localization in localizations) {
      if (localization is! Map) continue;
      if (_locale('${localization['languageId']}') != wanted) continue;
      final translations = localization['translations'];
      if (translations is! List) continue;
      for (final translation in translations) {
        if (translation is! Map) continue;
        final id = translation['id'];
        final path = translation['path'];
        if (id is! String || path is! String) continue;
        result[id.toLowerCase()] = location.joinPath([path]);
      }
    }
  }
  return result;
}

/// A language as language packs name it: lowercase, `zh` as `zh-cn`.
String _locale(String language) {
  final lower = language.toLowerCase().replaceAll('_', '-');
  return switch (lower) {
    'zh' || 'zh-hans' => 'zh-cn',
    'zh-hant' => 'zh-tw',
    _ => lower,
  };
}

final class MainThreadLocalization extends MainThreadLocalizationUnsupported {
  MainThreadLocalization(this._extensions);

  final Iterable<Map<String, Object?>> Function() _extensions;

  static RpcActor customer(MainThreadContext context) {
    final host = context.maybeService<ExtensionHostService>();
    return MainThreadLocalizationActor(
      MainThreadLocalization(() => host?.extensions.value ?? const []),
    );
  }

  @override
  Future<VsUri?> $fetchBuiltInBundleUri(String id, String language) async =>
      builtInTranslations(_extensions(), language)[id.toLowerCase()];

  @override
  Future<String> $fetchBundleContents(VsUri uriComponents) =>
      File(uriComponents.fsPath(windows: Platform.isWindows)).readAsString();
}
