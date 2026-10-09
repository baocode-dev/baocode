/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadConfiguration.ts.
//
// Deviations: the initial `$initializeConfiguration` and the changes are
// sent by ExtensionHostService, which owns the configuration.

import 'package:bao_exthost/bao_exthost.dart';

import '../configuration/configuration_service.dart';
import 'main_thread_context.dart';

final class MainThreadConfiguration extends MainThreadConfigurationUnsupported {
  MainThreadConfiguration(this._configuration);

  final ConfigurationService _configuration;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadConfigurationActor(
        MainThreadConfiguration(context.service<ConfigurationService>()),
      );

  @override
  Future<void> $updateConfigurationOption(
    int? target,
    String key,
    Object? value,
    Map<String, Object?>? overrides,
    bool? scopeToLanguage,
  ) => _configuration.update(
    key,
    value,
    target: target,
    overrideIdentifier: overrides?['overrideIdentifier'] as String?,
    resource: switch (overrides?['resource']) {
      final Map<Object?, Object?> uri => VsUri.revive(uri.cast()),
      _ => null,
    },
    scopeToLanguage: scopeToLanguage,
  );

  @override
  Future<void> $removeConfigurationOption(
    int? target,
    String key,
    Map<String, Object?>? overrides,
    bool? scopeToLanguage,
  ) =>
      $updateConfigurationOption(target, key, null, overrides, scopeToLanguage);
}
