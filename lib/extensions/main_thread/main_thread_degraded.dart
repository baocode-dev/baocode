/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Registrations BaoCode accepts for workbench features it does not have,
// so the extensions that make them (Python, GitLens, Docker, the built-in
// Git) activate and run the rest of what they do. Each keeps what was
// registered and shows nothing; what would have to answer with data
// answers with none, or fails, as upstream does with no provider. The
// Parity report (docs/extensions/EXTHOST_PARITY.md) lists them as degraded.
//
// Upstream: VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0)
// src/vs/workbench/api/browser/mainThreadLanguageModelTools.ts (the chat
// tools: there is no chat, so none is listed or invoked),
// mainThreadProfileContentHandlers.ts (no profile export to share),
// mainThreadTimeline.ts (no Timeline view), mainThreadDataChannels.ts
// (link presentation: no chat to present links in) and the ports
// attributes of mainThreadTunnelService.ts (no Ports view or port
// forwarding).

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_context.dart';

final class MainThreadLanguageModelTools
    extends MainThreadLanguageModelToolsUnsupported {
  /// The tools extensions registered, by id; no chat lists or invokes one.
  final Map<String, Map<String, Object?>?> tools = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadLanguageModelToolsActor(MainThreadLanguageModelTools());

  /// No tool is available to an extension's own model requests: there is
  /// no chat to have contributed one.
  @override
  Future<List<Map<String, Object?>>> $getTools() async => const [];

  @override
  void $registerTool(String id, bool hasHandleToolStream) => tools[id] = null;

  @override
  void $registerToolWithDefinition(
    Map<String, Object?> extensionId,
    Map<String, Object?> definition,
    bool hasHandleToolStream,
  ) => tools['${definition['id']}'] = definition;

  @override
  void $unregisterTool(String name) => tools.remove(name);

  /// No invocation is ever running for progress to be about.
  @override
  void $acceptToolProgress(String callId, Map<String, Object?> progress) {}

  @override
  Future<Object?> $invokeTool(
    Map<String, Object?> dto,
    CancellationToken token,
  ) async => throw StateError(
    'Language model tools are not supported in BaoCode: '
    '${dto['toolId']} cannot be invoked',
  );
}

final class MainThreadProfileContentHandlers
    extends MainThreadProfileContentHandlersUnsupported {
  /// The handlers, by id, with their names; there is no profile export.
  final Map<String, String> handlers = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadProfileContentHandlersActor(MainThreadProfileContentHandlers());

  @override
  void $registerProfileContentHandler(
    String id,
    String name,
    String? description,
    String extensionId,
  ) => handlers[id] = name;

  @override
  void $unregisterProfileContentHandler(String id) => handlers.remove(id);
}

final class MainThreadTimeline extends MainThreadTimelineUnsupported {
  /// The providers' sources (`provider.id`); there is no Timeline view to
  /// ask them.
  final Set<String> providers = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadTimelineActor(MainThreadTimeline());

  @override
  void $registerTimelineProvider(Map<String, Object?> provider) =>
      providers.add('${provider['id']}');

  @override
  void $unregisterTimelineProvider(String source) => providers.remove(source);

  @override
  void $emitTimelineChangeEvent(Map<String, Object?>? e) {}
}

final class MainThreadDataChannels extends MainThreadDataChannelsUnsupported {
  /// The link presentation providers, by handle, as `extension/provider`.
  final Map<num, String> linkPresentationProviders = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadDataChannelsActor(MainThreadDataChannels());

  @override
  void $registerLinkPresentationProvider(
    num handle,
    String extensionId,
    String providerId,
  ) => linkPresentationProviders[handle] = '$extensionId/$providerId';

  @override
  void $unregisterLinkPresentationProvider(num handle) =>
      linkPresentationProviders.remove(handle);

  /// No chat asks for a link's presentation, so none is watched.
  @override
  void $createLinkPresentationWatcher(
    num handle,
    String providerId,
    VsUri resource,
  ) {}

  @override
  void $disposeLinkPresentationWatcher(num handle) {}

  @override
  void $acceptLinkPresentationProviderData(num handle, Object? data) {}
}

final class MainThreadTunnelService extends MainThreadTunnelServiceUnsupported {
  /// The ports attributes providers' selectors, by handle; no port is
  /// forwarded for them to describe.
  final Map<num, Map<String, Object?>> portsAttributesProviders = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadTunnelServiceActor(MainThreadTunnelService());

  @override
  void $registerPortsAttributesProvider(
    Map<String, Object?> selector,
    num providerHandle,
  ) => portsAttributesProviders[providerHandle] = selector;

  @override
  void $unregisterPortsAttributesProvider(num providerHandle) =>
      portsAttributesProviders.remove(providerHandle);
}
