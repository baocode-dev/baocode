/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// GENERATED FILE - DO NOT EDIT. Regenerate with tool/generate_exthost_protocol.mjs.
//
// The main thread's shapes (`MainThread*Shape`): what the extension host
// calls. Each has an interface, a fallback that rejects every call (extend
// it and override what is supported) and an actor that decodes requests.
//
// Generated from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/common/extHost.protocol.ts; proxy identifier numbers from the compiled
// out/vs/workbench/api/node/extensionHostProcess.js.

// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import '../base/cancellation.dart';
import '../base/uri.dart';
import '../parity.dart';
import '../rpc/rpc_args.dart';
import '../rpc/rpc_protocol.dart';
import 'proxy_identifiers.g.dart';

Never _unsupported(String shape, String method) {
  ExtHostParity.instance.recordUnsupported(shape, method);
  throw RpcUnsupported('$shape.$method');
}

// --- MainThreadAuthentication --------------------------------------------------

/// `MainThreadAuthenticationShape` (`MainThreadAuthentication`).
abstract interface class MainThreadAuthenticationShape {
  /// `$registerAuthenticationProvider(details: IRegisterAuthenticationProviderDetails): Promise<void>`
  FutureOr<void> $registerAuthenticationProvider(Map<String, Object?> details);

  /// `$unregisterAuthenticationProvider(id: string): Promise<void>`
  FutureOr<void> $unregisterAuthenticationProvider(String id);

  /// `$ensureProvider(id: string): Promise<void>`
  FutureOr<void> $ensureProvider(String id);

  /// `$sendDidChangeSessions(providerId: string, event: Dto<AuthenticationSessionsChangeEvent>): Promise<void>`
  FutureOr<void> $sendDidChangeSessions(
    String providerId,
    Map<String, Object?> event,
  );

  /// `$getSession(providerId: string, scopeListOrRequest: ReadonlyArray<string> | IAuthenticationWwwAuthenticateRequest, extensionId: string, extensionName: string, options: AuthenticationGetSessionOptions): Promise<Dto<AuthenticationSession> | undefined>`
  Future<Map<String, Object?>?> $getSession(
    String providerId,
    Object? scopeListOrRequest,
    String extensionId,
    String extensionName,
    Map<String, Object?> options,
  );

  /// `$getAccounts(providerId: string): Promise<ReadonlyArray<Dto<AuthenticationSessionAccount>>>`
  Future<List<Map<String, Object?>>> $getAccounts(String providerId);

  /// `$removeSession(providerId: string, sessionId: string): Promise<void>`
  FutureOr<void> $removeSession(String providerId, String sessionId);

  /// `$waitForUriHandler(expectedUri: UriComponents): Promise<UriComponents>`
  Future<VsUri> $waitForUriHandler(VsUri expectedUri);

  /// `$showContinueNotification(message: string): Promise<boolean>`
  Future<bool> $showContinueNotification(String message);

  /// `$showDeviceCodeModal(userCode: string, verificationUri: string): Promise<boolean>`
  Future<bool> $showDeviceCodeModal(String userCode, String verificationUri);

  /// `$promptForClientRegistration(authorizationServerUrl: string): Promise<{ clientId: string; clientSecret?: string } | undefined>`
  Future<Map<String, Object?>?> $promptForClientRegistration(
    String authorizationServerUrl,
  );

  /// `$promptForResourceClientSecret(resourceClientId: string, resource: string): Promise<string | undefined>`
  Future<String?> $promptForResourceClientSecret(
    String resourceClientId,
    String resource,
  );

  /// `$registerDynamicAuthenticationProvider(details: IRegisterDynamicAuthenticationProviderDetails): Promise<void>`
  FutureOr<void> $registerDynamicAuthenticationProvider(
    Map<String, Object?> details,
  );

  /// `$setSessionsForDynamicAuthProvider(authProviderId: string, clientId: string, sessions: (IAuthorizationTokenResponse & { created_at: number })[]): Promise<void>`
  FutureOr<void> $setSessionsForDynamicAuthProvider(
    String authProviderId,
    String clientId,
    List<Map<String, Object?>> sessions,
  );

  /// `$sendDidChangeDynamicProviderInfo({ providerId, clientId, authorizationServer, label, clientSecret }: { providerId: string; clientId?: string; authorizationServer?: UriComponents; label?: string; clientSecret?: string }): Promise<void>`
  FutureOr<void> $sendDidChangeDynamicProviderInfo(Map<String, Object?> arg0);
}

/// [MainThreadAuthenticationShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadAuthenticationUnsupported
    implements MainThreadAuthenticationShape {
  const MainThreadAuthenticationUnsupported();

  @override
  FutureOr<void> $registerAuthenticationProvider(
    Map<String, Object?> details,
  ) => _unsupported(
    'MainThreadAuthentication',
    r'$registerAuthenticationProvider',
  );

  @override
  FutureOr<void> $unregisterAuthenticationProvider(String id) => _unsupported(
    'MainThreadAuthentication',
    r'$unregisterAuthenticationProvider',
  );

  @override
  FutureOr<void> $ensureProvider(String id) =>
      _unsupported('MainThreadAuthentication', r'$ensureProvider');

  @override
  FutureOr<void> $sendDidChangeSessions(
    String providerId,
    Map<String, Object?> event,
  ) => _unsupported('MainThreadAuthentication', r'$sendDidChangeSessions');

  @override
  Future<Map<String, Object?>?> $getSession(
    String providerId,
    Object? scopeListOrRequest,
    String extensionId,
    String extensionName,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadAuthentication', r'$getSession');

  @override
  Future<List<Map<String, Object?>>> $getAccounts(String providerId) =>
      _unsupported('MainThreadAuthentication', r'$getAccounts');

  @override
  FutureOr<void> $removeSession(String providerId, String sessionId) =>
      _unsupported('MainThreadAuthentication', r'$removeSession');

  @override
  Future<VsUri> $waitForUriHandler(VsUri expectedUri) =>
      _unsupported('MainThreadAuthentication', r'$waitForUriHandler');

  @override
  Future<bool> $showContinueNotification(String message) =>
      _unsupported('MainThreadAuthentication', r'$showContinueNotification');

  @override
  Future<bool> $showDeviceCodeModal(String userCode, String verificationUri) =>
      _unsupported('MainThreadAuthentication', r'$showDeviceCodeModal');

  @override
  Future<Map<String, Object?>?> $promptForClientRegistration(
    String authorizationServerUrl,
  ) =>
      _unsupported('MainThreadAuthentication', r'$promptForClientRegistration');

  @override
  Future<String?> $promptForResourceClientSecret(
    String resourceClientId,
    String resource,
  ) => _unsupported(
    'MainThreadAuthentication',
    r'$promptForResourceClientSecret',
  );

  @override
  FutureOr<void> $registerDynamicAuthenticationProvider(
    Map<String, Object?> details,
  ) => _unsupported(
    'MainThreadAuthentication',
    r'$registerDynamicAuthenticationProvider',
  );

  @override
  FutureOr<void> $setSessionsForDynamicAuthProvider(
    String authProviderId,
    String clientId,
    List<Map<String, Object?>> sessions,
  ) => _unsupported(
    'MainThreadAuthentication',
    r'$setSessionsForDynamicAuthProvider',
  );

  @override
  FutureOr<void> $sendDidChangeDynamicProviderInfo(Map<String, Object?> arg0) =>
      _unsupported(
        'MainThreadAuthentication',
        r'$sendDidChangeDynamicProviderInfo',
      );
}

/// Decodes requests to [MainContext.mainThreadAuthentication] and calls [target].
final class MainThreadAuthenticationActor implements RpcActor {
  MainThreadAuthenticationActor(this.target);

  static const identifier = MainContext.mainThreadAuthentication;

  final MainThreadAuthenticationShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadAuthentication.$method', args);
    switch (method) {
      case r'$registerAuthenticationProvider':
        await target.$registerAuthenticationProvider(
          a.arg(0, decodeMap, 'details'),
        );
        return null;
      case r'$unregisterAuthenticationProvider':
        await target.$unregisterAuthenticationProvider(
          a.arg(0, decodeString, 'id'),
        );
        return null;
      case r'$ensureProvider':
        await target.$ensureProvider(a.arg(0, decodeString, 'id'));
        return null;
      case r'$sendDidChangeSessions':
        await target.$sendDidChangeSessions(
          a.arg(0, decodeString, 'providerId'),
          a.arg(1, decodeMap, 'event'),
        );
        return null;
      case r'$getSession':
        return await target.$getSession(
          a.arg(0, decodeString, 'providerId'),
          a.arg(1, decodeObject, 'scopeListOrRequest'),
          a.arg(2, decodeString, 'extensionId'),
          a.arg(3, decodeString, 'extensionName'),
          a.arg(4, decodeMap, 'options'),
        );
      case r'$getAccounts':
        return await target.$getAccounts(a.arg(0, decodeString, 'providerId'));
      case r'$removeSession':
        await target.$removeSession(
          a.arg(0, decodeString, 'providerId'),
          a.arg(1, decodeString, 'sessionId'),
        );
        return null;
      case r'$waitForUriHandler':
        return await target.$waitForUriHandler(
          a.arg(0, decodeUri, 'expectedUri'),
        );
      case r'$showContinueNotification':
        return await target.$showContinueNotification(
          a.arg(0, decodeString, 'message'),
        );
      case r'$showDeviceCodeModal':
        return await target.$showDeviceCodeModal(
          a.arg(0, decodeString, 'userCode'),
          a.arg(1, decodeString, 'verificationUri'),
        );
      case r'$promptForClientRegistration':
        return await target.$promptForClientRegistration(
          a.arg(0, decodeString, 'authorizationServerUrl'),
        );
      case r'$promptForResourceClientSecret':
        return await target.$promptForResourceClientSecret(
          a.arg(0, decodeString, 'resourceClientId'),
          a.arg(1, decodeString, 'resource'),
        );
      case r'$registerDynamicAuthenticationProvider':
        await target.$registerDynamicAuthenticationProvider(
          a.arg(0, decodeMap, 'details'),
        );
        return null;
      case r'$setSessionsForDynamicAuthProvider':
        await target.$setSessionsForDynamicAuthProvider(
          a.arg(0, decodeString, 'authProviderId'),
          a.arg(1, decodeString, 'clientId'),
          a.arg(2, decodeListOf(decodeMap), 'sessions'),
        );
        return null;
      case r'$sendDidChangeDynamicProviderInfo':
        await target.$sendDidChangeDynamicProviderInfo(
          a.arg(0, decodeMap, 'arg0'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadAuthentication.$method');
    }
  }
}

// --- MainThreadBulkEdits -------------------------------------------------------

/// `MainThreadBulkEditsShape` (`MainThreadBulkEdits`).
abstract interface class MainThreadBulkEditsShape {
  /// `$tryApplyWorkspaceEdit(workspaceEditDto: SerializableObjectWithBuffers<IWorkspaceEditDto>, undoRedoGroupId?: number, isRefactoring?: boolean): Promise<boolean>`
  Future<bool> $tryApplyWorkspaceEdit(
    Object? workspaceEditDto,
    num? undoRedoGroupId,
    bool? isRefactoring,
  );
}

/// [MainThreadBulkEditsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadBulkEditsUnsupported implements MainThreadBulkEditsShape {
  const MainThreadBulkEditsUnsupported();

  @override
  Future<bool> $tryApplyWorkspaceEdit(
    Object? workspaceEditDto,
    num? undoRedoGroupId,
    bool? isRefactoring,
  ) => _unsupported('MainThreadBulkEdits', r'$tryApplyWorkspaceEdit');
}

/// Decodes requests to [MainContext.mainThreadBulkEdits] and calls [target].
final class MainThreadBulkEditsActor implements RpcActor {
  MainThreadBulkEditsActor(this.target);

  static const identifier = MainContext.mainThreadBulkEdits;

  final MainThreadBulkEditsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadBulkEdits.$method', args);
    switch (method) {
      case r'$tryApplyWorkspaceEdit':
        return await target.$tryApplyWorkspaceEdit(
          a.arg(0, decodeObject, 'workspaceEditDto'),
          a.arg(1, decodeNullable(decodeNum), 'undoRedoGroupId'),
          a.arg(2, decodeNullable(decodeBool), 'isRefactoring'),
        );
      default:
        throw RpcUnsupported('MainThreadBulkEdits.$method');
    }
  }
}

// --- MainThreadLanguageModels --------------------------------------------------

/// `MainThreadLanguageModelsShape` (`MainThreadLanguageModels`).
abstract interface class MainThreadLanguageModelsShape {
  /// `$registerLanguageModelProvider(vendor: string): void`
  FutureOr<void> $registerLanguageModelProvider(String vendor);

  /// `$onLMProviderChange(vendor: string): void`
  FutureOr<void> $onLMProviderChange(String vendor);

  /// `$unregisterProvider(vendor: string): void`
  FutureOr<void> $unregisterProvider(String vendor);

  /// `$tryStartChatRequest(extension: ExtensionIdentifier, modelIdentifier: string, requestId: number, messages: SerializableObjectWithBuffers<IChatMessage[]>, options: {}, token: CancellationToken): Promise<void>`
  FutureOr<void> $tryStartChatRequest(
    Map<String, Object?> extension,
    String modelIdentifier,
    num requestId,
    Object? messages,
    Map<String, Object?> options,
    CancellationToken token,
  );

  /// `$reportResponsePart(requestId: number, chunk: SerializableObjectWithBuffers<IChatResponsePart | IChatResponsePart[]>): Promise<void>`
  FutureOr<void> $reportResponsePart(num requestId, Object? chunk);

  /// `$reportResponseDone(requestId: number, error: SerializedError | undefined): Promise<void>`
  FutureOr<void> $reportResponseDone(
    num requestId,
    Map<String, Object?>? error,
  );

  /// `$selectChatModels(selector: ILanguageModelChatSelector): Promise<string[]>`
  Future<List<String>> $selectChatModels(Map<String, Object?> selector);

  /// `$countTokens(modelId: string, value: string | IChatMessage, token: CancellationToken): Promise<number>`
  Future<num> $countTokens(
    String modelId,
    Object? value,
    CancellationToken token,
  );

  /// `$cancelLanguageModelChatRequest(requestId: number): void`
  FutureOr<void> $cancelLanguageModelChatRequest(num requestId);

  /// `$fileIsIgnored(uri: UriComponents, token: CancellationToken): Promise<boolean>`
  Future<bool> $fileIsIgnored(VsUri uri, CancellationToken token);

  /// `$registerFileIgnoreProvider(handle: number): void`
  FutureOr<void> $registerFileIgnoreProvider(num handle);

  /// `$unregisterFileIgnoreProvider(handle: number): void`
  FutureOr<void> $unregisterFileIgnoreProvider(num handle);
}

/// [MainThreadLanguageModelsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLanguageModelsUnsupported
    implements MainThreadLanguageModelsShape {
  const MainThreadLanguageModelsUnsupported();

  @override
  FutureOr<void> $registerLanguageModelProvider(String vendor) => _unsupported(
    'MainThreadLanguageModels',
    r'$registerLanguageModelProvider',
  );

  @override
  FutureOr<void> $onLMProviderChange(String vendor) =>
      _unsupported('MainThreadLanguageModels', r'$onLMProviderChange');

  @override
  FutureOr<void> $unregisterProvider(String vendor) =>
      _unsupported('MainThreadLanguageModels', r'$unregisterProvider');

  @override
  FutureOr<void> $tryStartChatRequest(
    Map<String, Object?> extension,
    String modelIdentifier,
    num requestId,
    Object? messages,
    Map<String, Object?> options,
    CancellationToken token,
  ) => _unsupported('MainThreadLanguageModels', r'$tryStartChatRequest');

  @override
  FutureOr<void> $reportResponsePart(num requestId, Object? chunk) =>
      _unsupported('MainThreadLanguageModels', r'$reportResponsePart');

  @override
  FutureOr<void> $reportResponseDone(
    num requestId,
    Map<String, Object?>? error,
  ) => _unsupported('MainThreadLanguageModels', r'$reportResponseDone');

  @override
  Future<List<String>> $selectChatModels(Map<String, Object?> selector) =>
      _unsupported('MainThreadLanguageModels', r'$selectChatModels');

  @override
  Future<num> $countTokens(
    String modelId,
    Object? value,
    CancellationToken token,
  ) => _unsupported('MainThreadLanguageModels', r'$countTokens');

  @override
  FutureOr<void> $cancelLanguageModelChatRequest(num requestId) => _unsupported(
    'MainThreadLanguageModels',
    r'$cancelLanguageModelChatRequest',
  );

  @override
  Future<bool> $fileIsIgnored(VsUri uri, CancellationToken token) =>
      _unsupported('MainThreadLanguageModels', r'$fileIsIgnored');

  @override
  FutureOr<void> $registerFileIgnoreProvider(num handle) =>
      _unsupported('MainThreadLanguageModels', r'$registerFileIgnoreProvider');

  @override
  FutureOr<void> $unregisterFileIgnoreProvider(num handle) => _unsupported(
    'MainThreadLanguageModels',
    r'$unregisterFileIgnoreProvider',
  );
}

/// Decodes requests to [MainContext.mainThreadLanguageModels] and calls [target].
final class MainThreadLanguageModelsActor implements RpcActor {
  MainThreadLanguageModelsActor(this.target);

  static const identifier = MainContext.mainThreadLanguageModels;

  final MainThreadLanguageModelsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLanguageModels.$method', args);
    switch (method) {
      case r'$registerLanguageModelProvider':
        await target.$registerLanguageModelProvider(
          a.arg(0, decodeString, 'vendor'),
        );
        return null;
      case r'$onLMProviderChange':
        await target.$onLMProviderChange(a.arg(0, decodeString, 'vendor'));
        return null;
      case r'$unregisterProvider':
        await target.$unregisterProvider(a.arg(0, decodeString, 'vendor'));
        return null;
      case r'$tryStartChatRequest':
        await target.$tryStartChatRequest(
          a.arg(0, decodeMap, 'extension'),
          a.arg(1, decodeString, 'modelIdentifier'),
          a.arg(2, decodeNum, 'requestId'),
          a.arg(3, decodeObject, 'messages'),
          a.arg(4, decodeMap, 'options'),
          a.token,
        );
        return null;
      case r'$reportResponsePart':
        await target.$reportResponsePart(
          a.arg(0, decodeNum, 'requestId'),
          a.arg(1, decodeObject, 'chunk'),
        );
        return null;
      case r'$reportResponseDone':
        await target.$reportResponseDone(
          a.arg(0, decodeNum, 'requestId'),
          a.arg(1, decodeNullable(decodeMap), 'error'),
        );
        return null;
      case r'$selectChatModels':
        return await target.$selectChatModels(a.arg(0, decodeMap, 'selector'));
      case r'$countTokens':
        return await target.$countTokens(
          a.arg(0, decodeString, 'modelId'),
          a.arg(1, decodeObject, 'value'),
          a.token,
        );
      case r'$cancelLanguageModelChatRequest':
        await target.$cancelLanguageModelChatRequest(
          a.arg(0, decodeNum, 'requestId'),
        );
        return null;
      case r'$fileIsIgnored':
        return await target.$fileIsIgnored(a.arg(0, decodeUri, 'uri'), a.token);
      case r'$registerFileIgnoreProvider':
        await target.$registerFileIgnoreProvider(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$unregisterFileIgnoreProvider':
        await target.$unregisterFileIgnoreProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadLanguageModels.$method');
    }
  }
}

// --- MainThreadEmbeddings ------------------------------------------------------

/// `MainThreadEmbeddingsShape` (`MainThreadEmbeddings`).
abstract interface class MainThreadEmbeddingsShape {
  /// `$registerEmbeddingProvider(handle: number, identifier: string): void`
  FutureOr<void> $registerEmbeddingProvider(num handle, String identifier);

  /// `$unregisterEmbeddingProvider(handle: number): void`
  FutureOr<void> $unregisterEmbeddingProvider(num handle);

  /// `$computeEmbeddings(embeddingsModel: string, input: string[], token: CancellationToken): Promise<({ values: number[] }[])>`
  Future<List<Map<String, Object?>>> $computeEmbeddings(
    String embeddingsModel,
    List<String> input,
    CancellationToken token,
  );
}

/// [MainThreadEmbeddingsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadEmbeddingsUnsupported
    implements MainThreadEmbeddingsShape {
  const MainThreadEmbeddingsUnsupported();

  @override
  FutureOr<void> $registerEmbeddingProvider(num handle, String identifier) =>
      _unsupported('MainThreadEmbeddings', r'$registerEmbeddingProvider');

  @override
  FutureOr<void> $unregisterEmbeddingProvider(num handle) =>
      _unsupported('MainThreadEmbeddings', r'$unregisterEmbeddingProvider');

  @override
  Future<List<Map<String, Object?>>> $computeEmbeddings(
    String embeddingsModel,
    List<String> input,
    CancellationToken token,
  ) => _unsupported('MainThreadEmbeddings', r'$computeEmbeddings');
}

/// Decodes requests to [MainContext.mainThreadEmbeddings] and calls [target].
final class MainThreadEmbeddingsActor implements RpcActor {
  MainThreadEmbeddingsActor(this.target);

  static const identifier = MainContext.mainThreadEmbeddings;

  final MainThreadEmbeddingsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadEmbeddings.$method', args);
    switch (method) {
      case r'$registerEmbeddingProvider':
        await target.$registerEmbeddingProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'identifier'),
        );
        return null;
      case r'$unregisterEmbeddingProvider':
        await target.$unregisterEmbeddingProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$computeEmbeddings':
        return await target.$computeEmbeddings(
          a.arg(0, decodeString, 'embeddingsModel'),
          a.arg(1, decodeListOf(decodeString), 'input'),
          a.token,
        );
      default:
        throw RpcUnsupported('MainThreadEmbeddings.$method');
    }
  }
}

// --- MainThreadChatAgents2 -----------------------------------------------------

/// `MainThreadChatAgentsShape2` (`MainThreadChatAgents2`).
abstract interface class MainThreadChatAgents2Shape {
  /// `$registerAgent(handle: number, extension: ExtensionIdentifier, id: string, metadata: IExtensionChatAgentMetadata, dynamicProps: IDynamicChatAgentProps | undefined): void`
  FutureOr<void> $registerAgent(
    num handle,
    Map<String, Object?> extension,
    String id,
    Map<String, Object?> metadata,
    Map<String, Object?>? dynamicProps,
  );

  /// `$registerChatParticipantDetectionProvider(handle: number): void`
  FutureOr<void> $registerChatParticipantDetectionProvider(num handle);

  /// `$unregisterChatParticipantDetectionProvider(handle: number): void`
  FutureOr<void> $unregisterChatParticipantDetectionProvider(num handle);

  /// `$registerPromptFileProvider(handle: number, type: string, extension: ExtensionIdentifier): void`
  FutureOr<void> $registerPromptFileProvider(
    num handle,
    String type,
    Map<String, Object?> extension,
  );

  /// `$unregisterPromptFileProvider(handle: number): void`
  FutureOr<void> $unregisterPromptFileProvider(num handle);

  /// `$onDidChangePromptFiles(handle: number): void`
  FutureOr<void> $onDidChangePromptFiles(num handle);

  /// `$registerChatSessionCustomizationProvider(handle: number, chatSessionType: string, metadata: IChatSessionCustomizationProviderMetadataDto, extension: ExtensionIdentifier): void`
  FutureOr<void> $registerChatSessionCustomizationProvider(
    num handle,
    String chatSessionType,
    Map<String, Object?> metadata,
    Map<String, Object?> extension,
  );

  /// `$unregisterChatSessionCustomizationProvider(handle: number): void`
  FutureOr<void> $unregisterChatSessionCustomizationProvider(num handle);

  /// `$onDidChangeCustomizations(handle: number): void`
  FutureOr<void> $onDidChangeCustomizations(num handle);

  /// `$registerAgentCompletionsProvider(handle: number, id: string, triggerCharacters: string[]): void`
  FutureOr<void> $registerAgentCompletionsProvider(
    num handle,
    String id,
    List<String> triggerCharacters,
  );

  /// `$unregisterAgentCompletionsProvider(handle: number, id: string): void`
  FutureOr<void> $unregisterAgentCompletionsProvider(num handle, String id);

  /// `$updateAgent(handle: number, metadataUpdate: IExtensionChatAgentMetadata): void`
  FutureOr<void> $updateAgent(num handle, Map<String, Object?> metadataUpdate);

  /// `$unregisterAgent(handle: number): void`
  FutureOr<void> $unregisterAgent(num handle);

  /// `$transferActiveChatSession(toWorkspace: UriComponents): Promise<void>`
  FutureOr<void> $transferActiveChatSession(VsUri toWorkspace);

  /// `$provideCustomAgents(token: CancellationToken): Promise<ICustomAgentDto[]>`
  Future<List<Map<String, Object?>>> $provideCustomAgents(
    CancellationToken token,
  );

  /// `$provideInstructions(token: CancellationToken): Promise<IInstructionDto[]>`
  Future<List<Map<String, Object?>>> $provideInstructions(
    CancellationToken token,
  );

  /// `$provideSkills(token: CancellationToken): Promise<ISkillDto[]>`
  Future<List<Map<String, Object?>>> $provideSkills(CancellationToken token);

  /// `$provideSlashCommands(token: CancellationToken): Promise<ISlashCommandDto[]>`
  Future<List<Map<String, Object?>>> $provideSlashCommands(
    CancellationToken token,
  );

  /// `$provideHooks(token: CancellationToken): Promise<IHookDto[]>`
  Future<List<Map<String, Object?>>> $provideHooks(CancellationToken token);

  /// `$providePlugins(token: CancellationToken): Promise<IPluginDto[]>`
  Future<List<Map<String, Object?>>> $providePlugins(CancellationToken token);

  /// `$handleProgressChunk(requestId: string, chunks: (IChatProgressDto | [IChatProgressDto, number])[]): Promise<void>`
  FutureOr<void> $handleProgressChunk(String requestId, List<Object?> chunks);

  /// `$handleAnchorResolve(requestId: string, handle: string, anchor: Dto<IChatContentInlineReference>): void`
  FutureOr<void> $handleAnchorResolve(
    String requestId,
    String handle,
    Map<String, Object?> anchor,
  );
}

/// [MainThreadChatAgents2Shape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatAgents2Unsupported
    implements MainThreadChatAgents2Shape {
  const MainThreadChatAgents2Unsupported();

  @override
  FutureOr<void> $registerAgent(
    num handle,
    Map<String, Object?> extension,
    String id,
    Map<String, Object?> metadata,
    Map<String, Object?>? dynamicProps,
  ) => _unsupported('MainThreadChatAgents2', r'$registerAgent');

  @override
  FutureOr<void> $registerChatParticipantDetectionProvider(num handle) =>
      _unsupported(
        'MainThreadChatAgents2',
        r'$registerChatParticipantDetectionProvider',
      );

  @override
  FutureOr<void> $unregisterChatParticipantDetectionProvider(num handle) =>
      _unsupported(
        'MainThreadChatAgents2',
        r'$unregisterChatParticipantDetectionProvider',
      );

  @override
  FutureOr<void> $registerPromptFileProvider(
    num handle,
    String type,
    Map<String, Object?> extension,
  ) => _unsupported('MainThreadChatAgents2', r'$registerPromptFileProvider');

  @override
  FutureOr<void> $unregisterPromptFileProvider(num handle) =>
      _unsupported('MainThreadChatAgents2', r'$unregisterPromptFileProvider');

  @override
  FutureOr<void> $onDidChangePromptFiles(num handle) =>
      _unsupported('MainThreadChatAgents2', r'$onDidChangePromptFiles');

  @override
  FutureOr<void> $registerChatSessionCustomizationProvider(
    num handle,
    String chatSessionType,
    Map<String, Object?> metadata,
    Map<String, Object?> extension,
  ) => _unsupported(
    'MainThreadChatAgents2',
    r'$registerChatSessionCustomizationProvider',
  );

  @override
  FutureOr<void> $unregisterChatSessionCustomizationProvider(num handle) =>
      _unsupported(
        'MainThreadChatAgents2',
        r'$unregisterChatSessionCustomizationProvider',
      );

  @override
  FutureOr<void> $onDidChangeCustomizations(num handle) =>
      _unsupported('MainThreadChatAgents2', r'$onDidChangeCustomizations');

  @override
  FutureOr<void> $registerAgentCompletionsProvider(
    num handle,
    String id,
    List<String> triggerCharacters,
  ) => _unsupported(
    'MainThreadChatAgents2',
    r'$registerAgentCompletionsProvider',
  );

  @override
  FutureOr<void> $unregisterAgentCompletionsProvider(num handle, String id) =>
      _unsupported(
        'MainThreadChatAgents2',
        r'$unregisterAgentCompletionsProvider',
      );

  @override
  FutureOr<void> $updateAgent(
    num handle,
    Map<String, Object?> metadataUpdate,
  ) => _unsupported('MainThreadChatAgents2', r'$updateAgent');

  @override
  FutureOr<void> $unregisterAgent(num handle) =>
      _unsupported('MainThreadChatAgents2', r'$unregisterAgent');

  @override
  FutureOr<void> $transferActiveChatSession(VsUri toWorkspace) =>
      _unsupported('MainThreadChatAgents2', r'$transferActiveChatSession');

  @override
  Future<List<Map<String, Object?>>> $provideCustomAgents(
    CancellationToken token,
  ) => _unsupported('MainThreadChatAgents2', r'$provideCustomAgents');

  @override
  Future<List<Map<String, Object?>>> $provideInstructions(
    CancellationToken token,
  ) => _unsupported('MainThreadChatAgents2', r'$provideInstructions');

  @override
  Future<List<Map<String, Object?>>> $provideSkills(CancellationToken token) =>
      _unsupported('MainThreadChatAgents2', r'$provideSkills');

  @override
  Future<List<Map<String, Object?>>> $provideSlashCommands(
    CancellationToken token,
  ) => _unsupported('MainThreadChatAgents2', r'$provideSlashCommands');

  @override
  Future<List<Map<String, Object?>>> $provideHooks(CancellationToken token) =>
      _unsupported('MainThreadChatAgents2', r'$provideHooks');

  @override
  Future<List<Map<String, Object?>>> $providePlugins(CancellationToken token) =>
      _unsupported('MainThreadChatAgents2', r'$providePlugins');

  @override
  FutureOr<void> $handleProgressChunk(String requestId, List<Object?> chunks) =>
      _unsupported('MainThreadChatAgents2', r'$handleProgressChunk');

  @override
  FutureOr<void> $handleAnchorResolve(
    String requestId,
    String handle,
    Map<String, Object?> anchor,
  ) => _unsupported('MainThreadChatAgents2', r'$handleAnchorResolve');
}

/// Decodes requests to [MainContext.mainThreadChatAgents2] and calls [target].
final class MainThreadChatAgents2Actor implements RpcActor {
  MainThreadChatAgents2Actor(this.target);

  static const identifier = MainContext.mainThreadChatAgents2;

  final MainThreadChatAgents2Shape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatAgents2.$method', args);
    switch (method) {
      case r'$registerAgent':
        await target.$registerAgent(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'extension'),
          a.arg(2, decodeString, 'id'),
          a.arg(3, decodeMap, 'metadata'),
          a.arg(4, decodeNullable(decodeMap), 'dynamicProps'),
        );
        return null;
      case r'$registerChatParticipantDetectionProvider':
        await target.$registerChatParticipantDetectionProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$unregisterChatParticipantDetectionProvider':
        await target.$unregisterChatParticipantDetectionProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$registerPromptFileProvider':
        await target.$registerPromptFileProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'type'),
          a.arg(2, decodeMap, 'extension'),
        );
        return null;
      case r'$unregisterPromptFileProvider':
        await target.$unregisterPromptFileProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$onDidChangePromptFiles':
        await target.$onDidChangePromptFiles(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$registerChatSessionCustomizationProvider':
        await target.$registerChatSessionCustomizationProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'chatSessionType'),
          a.arg(2, decodeMap, 'metadata'),
          a.arg(3, decodeMap, 'extension'),
        );
        return null;
      case r'$unregisterChatSessionCustomizationProvider':
        await target.$unregisterChatSessionCustomizationProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$onDidChangeCustomizations':
        await target.$onDidChangeCustomizations(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$registerAgentCompletionsProvider':
        await target.$registerAgentCompletionsProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
          a.arg(2, decodeListOf(decodeString), 'triggerCharacters'),
        );
        return null;
      case r'$unregisterAgentCompletionsProvider':
        await target.$unregisterAgentCompletionsProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
        );
        return null;
      case r'$updateAgent':
        await target.$updateAgent(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'metadataUpdate'),
        );
        return null;
      case r'$unregisterAgent':
        await target.$unregisterAgent(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$transferActiveChatSession':
        await target.$transferActiveChatSession(
          a.arg(0, decodeUri, 'toWorkspace'),
        );
        return null;
      case r'$provideCustomAgents':
        return await target.$provideCustomAgents(a.token);
      case r'$provideInstructions':
        return await target.$provideInstructions(a.token);
      case r'$provideSkills':
        return await target.$provideSkills(a.token);
      case r'$provideSlashCommands':
        return await target.$provideSlashCommands(a.token);
      case r'$provideHooks':
        return await target.$provideHooks(a.token);
      case r'$providePlugins':
        return await target.$providePlugins(a.token);
      case r'$handleProgressChunk':
        await target.$handleProgressChunk(
          a.arg(0, decodeString, 'requestId'),
          a.arg(1, decodeListOf(decodeObject), 'chunks'),
        );
        return null;
      case r'$handleAnchorResolve':
        await target.$handleAnchorResolve(
          a.arg(0, decodeString, 'requestId'),
          a.arg(1, decodeString, 'handle'),
          a.arg(2, decodeMap, 'anchor'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadChatAgents2.$method');
    }
  }
}

// --- MainThreadCodeMapper ------------------------------------------------------

/// `MainThreadCodeMapperShape` (`MainThreadCodeMapper`).
abstract interface class MainThreadCodeMapperShape {
  /// `$registerCodeMapperProvider(handle: number, displayName: string): void`
  FutureOr<void> $registerCodeMapperProvider(num handle, String displayName);

  /// `$unregisterCodeMapperProvider(handle: number): void`
  FutureOr<void> $unregisterCodeMapperProvider(num handle);

  /// `$handleProgress(requestId: string, data: ICodeMapperProgressDto): Promise<void>`
  FutureOr<void> $handleProgress(String requestId, Map<String, Object?> data);
}

/// [MainThreadCodeMapperShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadCodeMapperUnsupported
    implements MainThreadCodeMapperShape {
  const MainThreadCodeMapperUnsupported();

  @override
  FutureOr<void> $registerCodeMapperProvider(num handle, String displayName) =>
      _unsupported('MainThreadCodeMapper', r'$registerCodeMapperProvider');

  @override
  FutureOr<void> $unregisterCodeMapperProvider(num handle) =>
      _unsupported('MainThreadCodeMapper', r'$unregisterCodeMapperProvider');

  @override
  FutureOr<void> $handleProgress(String requestId, Map<String, Object?> data) =>
      _unsupported('MainThreadCodeMapper', r'$handleProgress');
}

/// Decodes requests to [MainContext.mainThreadCodeMapper] and calls [target].
final class MainThreadCodeMapperActor implements RpcActor {
  MainThreadCodeMapperActor(this.target);

  static const identifier = MainContext.mainThreadCodeMapper;

  final MainThreadCodeMapperShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadCodeMapper.$method', args);
    switch (method) {
      case r'$registerCodeMapperProvider':
        await target.$registerCodeMapperProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'displayName'),
        );
        return null;
      case r'$unregisterCodeMapperProvider':
        await target.$unregisterCodeMapperProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$handleProgress':
        await target.$handleProgress(
          a.arg(0, decodeString, 'requestId'),
          a.arg(1, decodeMap, 'data'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadCodeMapper.$method');
    }
  }
}

// --- MainThreadLanguageModelTools ----------------------------------------------

/// `MainThreadLanguageModelToolsShape` (`MainThreadChatSkills`).
abstract interface class MainThreadLanguageModelToolsShape {
  /// `$getTools(): Promise<Dto<IToolDataDto>[]>`
  Future<List<Map<String, Object?>>> $getTools();

  /// `$acceptToolProgress(callId: string, progress: IToolProgressStep): void`
  FutureOr<void> $acceptToolProgress(
    String callId,
    Map<String, Object?> progress,
  );

  /// `$invokeTool(dto: Dto<IToolInvocation>, token?: CancellationToken): Promise<Dto<IToolResult> | SerializableObjectWithBuffers<Dto<IToolResult>>>`
  Future<Object?> $invokeTool(
    Map<String, Object?> dto,
    CancellationToken token,
  );

  /// `$countTokensForInvocation(callId: string, input: string, token: CancellationToken): Promise<number>`
  Future<num> $countTokensForInvocation(
    String callId,
    String input,
    CancellationToken token,
  );

  /// `$registerTool(id: string, hasHandleToolStream: boolean): void`
  FutureOr<void> $registerTool(String id, bool hasHandleToolStream);

  /// `$registerToolWithDefinition(extensionId: ExtensionIdentifier, definition: IToolDefinitionDto, hasHandleToolStream: boolean): void`
  FutureOr<void> $registerToolWithDefinition(
    Map<String, Object?> extensionId,
    Map<String, Object?> definition,
    bool hasHandleToolStream,
  );

  /// `$unregisterTool(name: string): void`
  FutureOr<void> $unregisterTool(String name);
}

/// [MainThreadLanguageModelToolsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLanguageModelToolsUnsupported
    implements MainThreadLanguageModelToolsShape {
  const MainThreadLanguageModelToolsUnsupported();

  @override
  Future<List<Map<String, Object?>>> $getTools() =>
      _unsupported('MainThreadLanguageModelTools', r'$getTools');

  @override
  FutureOr<void> $acceptToolProgress(
    String callId,
    Map<String, Object?> progress,
  ) => _unsupported('MainThreadLanguageModelTools', r'$acceptToolProgress');

  @override
  Future<Object?> $invokeTool(
    Map<String, Object?> dto,
    CancellationToken token,
  ) => _unsupported('MainThreadLanguageModelTools', r'$invokeTool');

  @override
  Future<num> $countTokensForInvocation(
    String callId,
    String input,
    CancellationToken token,
  ) => _unsupported(
    'MainThreadLanguageModelTools',
    r'$countTokensForInvocation',
  );

  @override
  FutureOr<void> $registerTool(String id, bool hasHandleToolStream) =>
      _unsupported('MainThreadLanguageModelTools', r'$registerTool');

  @override
  FutureOr<void> $registerToolWithDefinition(
    Map<String, Object?> extensionId,
    Map<String, Object?> definition,
    bool hasHandleToolStream,
  ) => _unsupported(
    'MainThreadLanguageModelTools',
    r'$registerToolWithDefinition',
  );

  @override
  FutureOr<void> $unregisterTool(String name) =>
      _unsupported('MainThreadLanguageModelTools', r'$unregisterTool');
}

/// Decodes requests to [MainContext.mainThreadLanguageModelTools] and calls [target].
final class MainThreadLanguageModelToolsActor implements RpcActor {
  MainThreadLanguageModelToolsActor(this.target);

  static const identifier = MainContext.mainThreadLanguageModelTools;

  final MainThreadLanguageModelToolsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLanguageModelTools.$method', args);
    switch (method) {
      case r'$getTools':
        return await target.$getTools();
      case r'$acceptToolProgress':
        await target.$acceptToolProgress(
          a.arg(0, decodeString, 'callId'),
          a.arg(1, decodeMap, 'progress'),
        );
        return null;
      case r'$invokeTool':
        return await target.$invokeTool(a.arg(0, decodeMap, 'dto'), a.token);
      case r'$countTokensForInvocation':
        return await target.$countTokensForInvocation(
          a.arg(0, decodeString, 'callId'),
          a.arg(1, decodeString, 'input'),
          a.token,
        );
      case r'$registerTool':
        await target.$registerTool(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeBool, 'hasHandleToolStream'),
        );
        return null;
      case r'$registerToolWithDefinition':
        await target.$registerToolWithDefinition(
          a.arg(0, decodeMap, 'extensionId'),
          a.arg(1, decodeMap, 'definition'),
          a.arg(2, decodeBool, 'hasHandleToolStream'),
        );
        return null;
      case r'$unregisterTool':
        await target.$unregisterTool(a.arg(0, decodeString, 'name'));
        return null;
      default:
        throw RpcUnsupported('MainThreadLanguageModelTools.$method');
    }
  }
}

// --- MainThreadGitExtension ----------------------------------------------------

/// `MainThreadGitExtensionShape` (`MainThreadGitExtension`).
abstract interface class MainThreadGitExtensionShape {
  /// `$onDidChangeRepository(handle: number): Promise<void>`
  FutureOr<void> $onDidChangeRepository(num handle);
}

/// [MainThreadGitExtensionShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadGitExtensionUnsupported
    implements MainThreadGitExtensionShape {
  const MainThreadGitExtensionUnsupported();

  @override
  FutureOr<void> $onDidChangeRepository(num handle) =>
      _unsupported('MainThreadGitExtension', r'$onDidChangeRepository');
}

/// Decodes requests to [MainContext.mainThreadGitExtension] and calls [target].
final class MainThreadGitExtensionActor implements RpcActor {
  MainThreadGitExtensionActor(this.target);

  static const identifier = MainContext.mainThreadGitExtension;

  final MainThreadGitExtensionShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadGitExtension.$method', args);
    switch (method) {
      case r'$onDidChangeRepository':
        await target.$onDidChangeRepository(a.arg(0, decodeNum, 'handle'));
        return null;
      default:
        throw RpcUnsupported('MainThreadGitExtension.$method');
    }
  }
}

// --- MainThreadClipboard -------------------------------------------------------

/// `MainThreadClipboardShape` (`MainThreadClipboard`).
abstract interface class MainThreadClipboardShape {
  /// `$readText(): Promise<string>`
  Future<String> $readText();

  /// `$writeText(value: string): Promise<void>`
  FutureOr<void> $writeText(String value);
}

/// [MainThreadClipboardShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadClipboardUnsupported implements MainThreadClipboardShape {
  const MainThreadClipboardUnsupported();

  @override
  Future<String> $readText() =>
      _unsupported('MainThreadClipboard', r'$readText');

  @override
  FutureOr<void> $writeText(String value) =>
      _unsupported('MainThreadClipboard', r'$writeText');
}

/// Decodes requests to [MainContext.mainThreadClipboard] and calls [target].
final class MainThreadClipboardActor implements RpcActor {
  MainThreadClipboardActor(this.target);

  static const identifier = MainContext.mainThreadClipboard;

  final MainThreadClipboardShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadClipboard.$method', args);
    switch (method) {
      case r'$readText':
        return await target.$readText();
      case r'$writeText':
        await target.$writeText(a.arg(0, decodeString, 'value'));
        return null;
      default:
        throw RpcUnsupported('MainThreadClipboard.$method');
    }
  }
}

// --- MainThreadCommands --------------------------------------------------------

/// `MainThreadCommandsShape` (`MainThreadCommands`).
abstract interface class MainThreadCommandsShape {
  /// `$registerCommand(id: string): void`
  FutureOr<void> $registerCommand(String id);

  /// `$unregisterCommand(id: string): void`
  FutureOr<void> $unregisterCommand(String id);

  /// `$fireCommandActivationEvent(id: string): void`
  FutureOr<void> $fireCommandActivationEvent(String id);

  /// `$executeCommand(id: string, args: unknown[] | SerializableObjectWithBuffers<unknown[]>, retry: boolean): Promise<unknown | undefined>`
  Future<Object?> $executeCommand(String id, Object? args, bool retry);

  /// `$getCommands(): Promise<string[]>`
  Future<List<String>> $getCommands();
}

/// [MainThreadCommandsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadCommandsUnsupported implements MainThreadCommandsShape {
  const MainThreadCommandsUnsupported();

  @override
  FutureOr<void> $registerCommand(String id) =>
      _unsupported('MainThreadCommands', r'$registerCommand');

  @override
  FutureOr<void> $unregisterCommand(String id) =>
      _unsupported('MainThreadCommands', r'$unregisterCommand');

  @override
  FutureOr<void> $fireCommandActivationEvent(String id) =>
      _unsupported('MainThreadCommands', r'$fireCommandActivationEvent');

  @override
  Future<Object?> $executeCommand(String id, Object? args, bool retry) =>
      _unsupported('MainThreadCommands', r'$executeCommand');

  @override
  Future<List<String>> $getCommands() =>
      _unsupported('MainThreadCommands', r'$getCommands');
}

/// Decodes requests to [MainContext.mainThreadCommands] and calls [target].
final class MainThreadCommandsActor implements RpcActor {
  MainThreadCommandsActor(this.target);

  static const identifier = MainContext.mainThreadCommands;

  final MainThreadCommandsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadCommands.$method', args);
    switch (method) {
      case r'$registerCommand':
        await target.$registerCommand(a.arg(0, decodeString, 'id'));
        return null;
      case r'$unregisterCommand':
        await target.$unregisterCommand(a.arg(0, decodeString, 'id'));
        return null;
      case r'$fireCommandActivationEvent':
        await target.$fireCommandActivationEvent(a.arg(0, decodeString, 'id'));
        return null;
      case r'$executeCommand':
        return await target.$executeCommand(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeObject, 'args'),
          a.arg(2, decodeBool, 'retry'),
        );
      case r'$getCommands':
        return await target.$getCommands();
      default:
        throw RpcUnsupported('MainThreadCommands.$method');
    }
  }
}

// --- MainThreadComments --------------------------------------------------------

/// `MainThreadCommentsShape` (`MainThreadComments`).
abstract interface class MainThreadCommentsShape {
  /// `$registerCommentController(handle: number, id: string, label: string, extensionId: string): void`
  FutureOr<void> $registerCommentController(
    num handle,
    String id,
    String label,
    String extensionId,
  );

  /// `$unregisterCommentController(handle: number): void`
  FutureOr<void> $unregisterCommentController(num handle);

  /// `$updateCommentControllerFeatures(handle: number, features: CommentProviderFeatures): void`
  FutureOr<void> $updateCommentControllerFeatures(
    num handle,
    Map<String, Object?> features,
  );

  /// `$createCommentThread(handle: number, commentThreadHandle: number, threadId: string, resource: UriComponents, range: IRange | ICellRange | undefined, comments: languages.Comment[], extensionId: ExtensionIdentifier, isTemplate: boolean, editorId?: string): languages.CommentThread<IRange | ICellRange> | undefined`
  FutureOr<Map<String, Object?>?> $createCommentThread(
    num handle,
    num commentThreadHandle,
    String threadId,
    VsUri resource,
    Map<String, Object?>? range,
    List<Map<String, Object?>> comments,
    Map<String, Object?> extensionId,
    bool isTemplate,
    String? editorId,
  );

  /// `$updateCommentThread(handle: number, commentThreadHandle: number, threadId: string, resource: UriComponents, changes: CommentThreadChanges): void`
  FutureOr<void> $updateCommentThread(
    num handle,
    num commentThreadHandle,
    String threadId,
    VsUri resource,
    Map<String, Object?> changes,
  );

  /// `$deleteCommentThread(handle: number, commentThreadHandle: number): void`
  FutureOr<void> $deleteCommentThread(num handle, num commentThreadHandle);

  /// `$updateCommentingRanges(handle: number, resourceHints?: languages.CommentingRangeResourceHint): void`
  FutureOr<void> $updateCommentingRanges(
    num handle,
    Map<String, Object?>? resourceHints,
  );

  /// `$revealCommentThread(handle: number, commentThreadHandle: number, commentUniqueIdInThread: number, options: languages.CommentThreadRevealOptions): Promise<void>`
  FutureOr<void> $revealCommentThread(
    num handle,
    num commentThreadHandle,
    num commentUniqueIdInThread,
    Map<String, Object?> options,
  );

  /// `$hideCommentThread(handle: number, commentThreadHandle: number): void`
  FutureOr<void> $hideCommentThread(num handle, num commentThreadHandle);
}

/// [MainThreadCommentsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadCommentsUnsupported implements MainThreadCommentsShape {
  const MainThreadCommentsUnsupported();

  @override
  FutureOr<void> $registerCommentController(
    num handle,
    String id,
    String label,
    String extensionId,
  ) => _unsupported('MainThreadComments', r'$registerCommentController');

  @override
  FutureOr<void> $unregisterCommentController(num handle) =>
      _unsupported('MainThreadComments', r'$unregisterCommentController');

  @override
  FutureOr<void> $updateCommentControllerFeatures(
    num handle,
    Map<String, Object?> features,
  ) => _unsupported('MainThreadComments', r'$updateCommentControllerFeatures');

  @override
  FutureOr<Map<String, Object?>?> $createCommentThread(
    num handle,
    num commentThreadHandle,
    String threadId,
    VsUri resource,
    Map<String, Object?>? range,
    List<Map<String, Object?>> comments,
    Map<String, Object?> extensionId,
    bool isTemplate,
    String? editorId,
  ) => _unsupported('MainThreadComments', r'$createCommentThread');

  @override
  FutureOr<void> $updateCommentThread(
    num handle,
    num commentThreadHandle,
    String threadId,
    VsUri resource,
    Map<String, Object?> changes,
  ) => _unsupported('MainThreadComments', r'$updateCommentThread');

  @override
  FutureOr<void> $deleteCommentThread(num handle, num commentThreadHandle) =>
      _unsupported('MainThreadComments', r'$deleteCommentThread');

  @override
  FutureOr<void> $updateCommentingRanges(
    num handle,
    Map<String, Object?>? resourceHints,
  ) => _unsupported('MainThreadComments', r'$updateCommentingRanges');

  @override
  FutureOr<void> $revealCommentThread(
    num handle,
    num commentThreadHandle,
    num commentUniqueIdInThread,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadComments', r'$revealCommentThread');

  @override
  FutureOr<void> $hideCommentThread(num handle, num commentThreadHandle) =>
      _unsupported('MainThreadComments', r'$hideCommentThread');
}

/// Decodes requests to [MainContext.mainThreadComments] and calls [target].
final class MainThreadCommentsActor implements RpcActor {
  MainThreadCommentsActor(this.target);

  static const identifier = MainContext.mainThreadComments;

  final MainThreadCommentsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadComments.$method', args);
    switch (method) {
      case r'$registerCommentController':
        await target.$registerCommentController(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
          a.arg(2, decodeString, 'label'),
          a.arg(3, decodeString, 'extensionId'),
        );
        return null;
      case r'$unregisterCommentController':
        await target.$unregisterCommentController(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$updateCommentControllerFeatures':
        await target.$updateCommentControllerFeatures(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'features'),
        );
        return null;
      case r'$createCommentThread':
        return await target.$createCommentThread(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'commentThreadHandle'),
          a.arg(2, decodeString, 'threadId'),
          a.arg(3, decodeUri, 'resource'),
          a.arg(4, decodeNullable(decodeMap), 'range'),
          a.arg(5, decodeListOf(decodeMap), 'comments'),
          a.arg(6, decodeMap, 'extensionId'),
          a.arg(7, decodeBool, 'isTemplate'),
          a.arg(8, decodeNullable(decodeString), 'editorId'),
        );
      case r'$updateCommentThread':
        await target.$updateCommentThread(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'commentThreadHandle'),
          a.arg(2, decodeString, 'threadId'),
          a.arg(3, decodeUri, 'resource'),
          a.arg(4, decodeMap, 'changes'),
        );
        return null;
      case r'$deleteCommentThread':
        await target.$deleteCommentThread(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'commentThreadHandle'),
        );
        return null;
      case r'$updateCommentingRanges':
        await target.$updateCommentingRanges(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeMap), 'resourceHints'),
        );
        return null;
      case r'$revealCommentThread':
        await target.$revealCommentThread(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'commentThreadHandle'),
          a.arg(2, decodeNum, 'commentUniqueIdInThread'),
          a.arg(3, decodeMap, 'options'),
        );
        return null;
      case r'$hideCommentThread':
        await target.$hideCommentThread(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'commentThreadHandle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadComments.$method');
    }
  }
}

// --- MainThreadConfiguration ---------------------------------------------------

/// `MainThreadConfigurationShape` (`MainThreadConfiguration`).
abstract interface class MainThreadConfigurationShape {
  /// `$updateConfigurationOption(target: ConfigurationTarget | null, key: string, value: unknown, overrides: IConfigurationOverrides | undefined, scopeToLanguage: boolean | undefined): Promise<void>`
  FutureOr<void> $updateConfigurationOption(
    int? target,
    String key,
    Object? value,
    Map<String, Object?>? overrides,
    bool? scopeToLanguage,
  );

  /// `$removeConfigurationOption(target: ConfigurationTarget | null, key: string, overrides: IConfigurationOverrides | undefined, scopeToLanguage: boolean | undefined): Promise<void>`
  FutureOr<void> $removeConfigurationOption(
    int? target,
    String key,
    Map<String, Object?>? overrides,
    bool? scopeToLanguage,
  );
}

/// [MainThreadConfigurationShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadConfigurationUnsupported
    implements MainThreadConfigurationShape {
  const MainThreadConfigurationUnsupported();

  @override
  FutureOr<void> $updateConfigurationOption(
    int? target,
    String key,
    Object? value,
    Map<String, Object?>? overrides,
    bool? scopeToLanguage,
  ) => _unsupported('MainThreadConfiguration', r'$updateConfigurationOption');

  @override
  FutureOr<void> $removeConfigurationOption(
    int? target,
    String key,
    Map<String, Object?>? overrides,
    bool? scopeToLanguage,
  ) => _unsupported('MainThreadConfiguration', r'$removeConfigurationOption');
}

/// Decodes requests to [MainContext.mainThreadConfiguration] and calls [target].
final class MainThreadConfigurationActor implements RpcActor {
  MainThreadConfigurationActor(this.target);

  static const identifier = MainContext.mainThreadConfiguration;

  final MainThreadConfigurationShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadConfiguration.$method', args);
    switch (method) {
      case r'$updateConfigurationOption':
        await target.$updateConfigurationOption(
          a.arg(0, decodeNullable(decodeInt), 'target'),
          a.arg(1, decodeString, 'key'),
          a.arg(2, decodeObject, 'value'),
          a.arg(3, decodeNullable(decodeMap), 'overrides'),
          a.arg(4, decodeNullable(decodeBool), 'scopeToLanguage'),
        );
        return null;
      case r'$removeConfigurationOption':
        await target.$removeConfigurationOption(
          a.arg(0, decodeNullable(decodeInt), 'target'),
          a.arg(1, decodeString, 'key'),
          a.arg(2, decodeNullable(decodeMap), 'overrides'),
          a.arg(3, decodeNullable(decodeBool), 'scopeToLanguage'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadConfiguration.$method');
    }
  }
}

// --- MainThreadConsole ---------------------------------------------------------

/// `MainThreadConsoleShape` (`MainThreadConsole`).
abstract interface class MainThreadConsoleShape {
  /// `$logExtensionHostMessage(msg: IRemoteConsoleLog): void`
  FutureOr<void> $logExtensionHostMessage(Map<String, Object?> msg);
}

/// [MainThreadConsoleShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadConsoleUnsupported implements MainThreadConsoleShape {
  const MainThreadConsoleUnsupported();

  @override
  FutureOr<void> $logExtensionHostMessage(Map<String, Object?> msg) =>
      _unsupported('MainThreadConsole', r'$logExtensionHostMessage');
}

/// Decodes requests to [MainContext.mainThreadConsole] and calls [target].
final class MainThreadConsoleActor implements RpcActor {
  MainThreadConsoleActor(this.target);

  static const identifier = MainContext.mainThreadConsole;

  final MainThreadConsoleShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadConsole.$method', args);
    switch (method) {
      case r'$logExtensionHostMessage':
        await target.$logExtensionHostMessage(a.arg(0, decodeMap, 'msg'));
        return null;
      default:
        throw RpcUnsupported('MainThreadConsole.$method');
    }
  }
}

// --- MainThreadDebugService ----------------------------------------------------

/// `MainThreadDebugServiceShape` (`MainThreadDebugService`).
abstract interface class MainThreadDebugServiceShape {
  /// `$registerDebugTypes(debugTypes: string[]): void`
  FutureOr<void> $registerDebugTypes(List<String> debugTypes);

  /// `$sessionCached(sessionID: string): void`
  FutureOr<void> $sessionCached(String sessionID);

  /// `$acceptDAMessage(handle: number, message: DebugProtocol.ProtocolMessage): void`
  FutureOr<void> $acceptDAMessage(num handle, Map<String, Object?> message);

  /// `$acceptDAError(handle: number, name: string, message: string, stack: string | undefined): void`
  FutureOr<void> $acceptDAError(
    num handle,
    String name,
    String message,
    String? stack,
  );

  /// `$acceptDAExit(handle: number, code: number | undefined, signal: string | undefined): void`
  FutureOr<void> $acceptDAExit(num handle, num? code, String? signal);

  /// `$registerDebugConfigurationProvider(type: string, triggerKind: DebugConfigurationProviderTriggerKind, hasProvideMethod: boolean, hasResolveMethod: boolean, hasResolve2Method: boolean, handle: number): Promise<void>`
  FutureOr<void> $registerDebugConfigurationProvider(
    String type,
    int triggerKind,
    bool hasProvideMethod,
    bool hasResolveMethod,
    bool hasResolve2Method,
    num handle,
  );

  /// `$registerDebugAdapterDescriptorFactory(type: string, handle: number): Promise<void>`
  FutureOr<void> $registerDebugAdapterDescriptorFactory(
    String type,
    num handle,
  );

  /// `$unregisterDebugConfigurationProvider(handle: number): void`
  FutureOr<void> $unregisterDebugConfigurationProvider(num handle);

  /// `$unregisterDebugAdapterDescriptorFactory(handle: number): void`
  FutureOr<void> $unregisterDebugAdapterDescriptorFactory(num handle);

  /// `$startDebugging(folder: UriComponents | undefined, nameOrConfig: string | IDebugConfiguration, options: IStartDebuggingOptions): Promise<boolean>`
  Future<bool> $startDebugging(
    VsUri? folder,
    Object? nameOrConfig,
    Map<String, Object?> options,
  );

  /// `$stopDebugging(sessionId: DebugSessionUUID | undefined): Promise<void>`
  FutureOr<void> $stopDebugging(String? sessionId);

  /// `$setDebugSessionName(id: DebugSessionUUID, name: string): void`
  FutureOr<void> $setDebugSessionName(String id, String name);

  /// `$customDebugAdapterRequest(id: DebugSessionUUID, command: string, args: any): Promise<any>`
  Future<Object?> $customDebugAdapterRequest(
    String id,
    String command,
    Object? args,
  );

  /// `$getDebugProtocolBreakpoint(id: DebugSessionUUID, breakpoinId: string): Promise<DebugProtocol.Breakpoint | undefined>`
  Future<Map<String, Object?>?> $getDebugProtocolBreakpoint(
    String id,
    String breakpoinId,
  );

  /// `$appendDebugConsole(value: string): void`
  FutureOr<void> $appendDebugConsole(String value);

  /// `$registerBreakpoints(breakpoints: Array<ISourceMultiBreakpointDto | IFunctionBreakpointDto | IDataBreakpointDto>): Promise<void>`
  FutureOr<void> $registerBreakpoints(List<Map<String, Object?>> breakpoints);

  /// `$unregisterBreakpoints(breakpointIds: string[], functionBreakpointIds: string[], dataBreakpointIds: string[]): Promise<void>`
  FutureOr<void> $unregisterBreakpoints(
    List<String> breakpointIds,
    List<String> functionBreakpointIds,
    List<String> dataBreakpointIds,
  );

  /// `$registerDebugVisualizer(extensionId: string, id: string): void`
  FutureOr<void> $registerDebugVisualizer(String extensionId, String id);

  /// `$unregisterDebugVisualizer(extensionId: string, id: string): void`
  FutureOr<void> $unregisterDebugVisualizer(String extensionId, String id);

  /// `$registerDebugVisualizerTree(treeId: string, canEdit: boolean): void`
  FutureOr<void> $registerDebugVisualizerTree(String treeId, bool canEdit);

  /// `$unregisterDebugVisualizerTree(treeId: string): void`
  FutureOr<void> $unregisterDebugVisualizerTree(String treeId);
}

/// [MainThreadDebugServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDebugServiceUnsupported
    implements MainThreadDebugServiceShape {
  const MainThreadDebugServiceUnsupported();

  @override
  FutureOr<void> $registerDebugTypes(List<String> debugTypes) =>
      _unsupported('MainThreadDebugService', r'$registerDebugTypes');

  @override
  FutureOr<void> $sessionCached(String sessionID) =>
      _unsupported('MainThreadDebugService', r'$sessionCached');

  @override
  FutureOr<void> $acceptDAMessage(num handle, Map<String, Object?> message) =>
      _unsupported('MainThreadDebugService', r'$acceptDAMessage');

  @override
  FutureOr<void> $acceptDAError(
    num handle,
    String name,
    String message,
    String? stack,
  ) => _unsupported('MainThreadDebugService', r'$acceptDAError');

  @override
  FutureOr<void> $acceptDAExit(num handle, num? code, String? signal) =>
      _unsupported('MainThreadDebugService', r'$acceptDAExit');

  @override
  FutureOr<void> $registerDebugConfigurationProvider(
    String type,
    int triggerKind,
    bool hasProvideMethod,
    bool hasResolveMethod,
    bool hasResolve2Method,
    num handle,
  ) => _unsupported(
    'MainThreadDebugService',
    r'$registerDebugConfigurationProvider',
  );

  @override
  FutureOr<void> $registerDebugAdapterDescriptorFactory(
    String type,
    num handle,
  ) => _unsupported(
    'MainThreadDebugService',
    r'$registerDebugAdapterDescriptorFactory',
  );

  @override
  FutureOr<void> $unregisterDebugConfigurationProvider(num handle) =>
      _unsupported(
        'MainThreadDebugService',
        r'$unregisterDebugConfigurationProvider',
      );

  @override
  FutureOr<void> $unregisterDebugAdapterDescriptorFactory(num handle) =>
      _unsupported(
        'MainThreadDebugService',
        r'$unregisterDebugAdapterDescriptorFactory',
      );

  @override
  Future<bool> $startDebugging(
    VsUri? folder,
    Object? nameOrConfig,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadDebugService', r'$startDebugging');

  @override
  FutureOr<void> $stopDebugging(String? sessionId) =>
      _unsupported('MainThreadDebugService', r'$stopDebugging');

  @override
  FutureOr<void> $setDebugSessionName(String id, String name) =>
      _unsupported('MainThreadDebugService', r'$setDebugSessionName');

  @override
  Future<Object?> $customDebugAdapterRequest(
    String id,
    String command,
    Object? args,
  ) => _unsupported('MainThreadDebugService', r'$customDebugAdapterRequest');

  @override
  Future<Map<String, Object?>?> $getDebugProtocolBreakpoint(
    String id,
    String breakpoinId,
  ) => _unsupported('MainThreadDebugService', r'$getDebugProtocolBreakpoint');

  @override
  FutureOr<void> $appendDebugConsole(String value) =>
      _unsupported('MainThreadDebugService', r'$appendDebugConsole');

  @override
  FutureOr<void> $registerBreakpoints(List<Map<String, Object?>> breakpoints) =>
      _unsupported('MainThreadDebugService', r'$registerBreakpoints');

  @override
  FutureOr<void> $unregisterBreakpoints(
    List<String> breakpointIds,
    List<String> functionBreakpointIds,
    List<String> dataBreakpointIds,
  ) => _unsupported('MainThreadDebugService', r'$unregisterBreakpoints');

  @override
  FutureOr<void> $registerDebugVisualizer(String extensionId, String id) =>
      _unsupported('MainThreadDebugService', r'$registerDebugVisualizer');

  @override
  FutureOr<void> $unregisterDebugVisualizer(String extensionId, String id) =>
      _unsupported('MainThreadDebugService', r'$unregisterDebugVisualizer');

  @override
  FutureOr<void> $registerDebugVisualizerTree(String treeId, bool canEdit) =>
      _unsupported('MainThreadDebugService', r'$registerDebugVisualizerTree');

  @override
  FutureOr<void> $unregisterDebugVisualizerTree(String treeId) =>
      _unsupported('MainThreadDebugService', r'$unregisterDebugVisualizerTree');
}

/// Decodes requests to [MainContext.mainThreadDebugService] and calls [target].
final class MainThreadDebugServiceActor implements RpcActor {
  MainThreadDebugServiceActor(this.target);

  static const identifier = MainContext.mainThreadDebugService;

  final MainThreadDebugServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDebugService.$method', args);
    switch (method) {
      case r'$registerDebugTypes':
        await target.$registerDebugTypes(
          a.arg(0, decodeListOf(decodeString), 'debugTypes'),
        );
        return null;
      case r'$sessionCached':
        await target.$sessionCached(a.arg(0, decodeString, 'sessionID'));
        return null;
      case r'$acceptDAMessage':
        await target.$acceptDAMessage(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'message'),
        );
        return null;
      case r'$acceptDAError':
        await target.$acceptDAError(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'name'),
          a.arg(2, decodeString, 'message'),
          a.arg(3, decodeNullable(decodeString), 'stack'),
        );
        return null;
      case r'$acceptDAExit':
        await target.$acceptDAExit(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeNum), 'code'),
          a.arg(2, decodeNullable(decodeString), 'signal'),
        );
        return null;
      case r'$registerDebugConfigurationProvider':
        await target.$registerDebugConfigurationProvider(
          a.arg(0, decodeString, 'type'),
          a.arg(1, decodeInt, 'triggerKind'),
          a.arg(2, decodeBool, 'hasProvideMethod'),
          a.arg(3, decodeBool, 'hasResolveMethod'),
          a.arg(4, decodeBool, 'hasResolve2Method'),
          a.arg(5, decodeNum, 'handle'),
        );
        return null;
      case r'$registerDebugAdapterDescriptorFactory':
        await target.$registerDebugAdapterDescriptorFactory(
          a.arg(0, decodeString, 'type'),
          a.arg(1, decodeNum, 'handle'),
        );
        return null;
      case r'$unregisterDebugConfigurationProvider':
        await target.$unregisterDebugConfigurationProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$unregisterDebugAdapterDescriptorFactory':
        await target.$unregisterDebugAdapterDescriptorFactory(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$startDebugging':
        return await target.$startDebugging(
          a.arg(0, decodeNullable(decodeUri), 'folder'),
          a.arg(1, decodeObject, 'nameOrConfig'),
          a.arg(2, decodeMap, 'options'),
        );
      case r'$stopDebugging':
        await target.$stopDebugging(
          a.arg(0, decodeNullable(decodeString), 'sessionId'),
        );
        return null;
      case r'$setDebugSessionName':
        await target.$setDebugSessionName(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'name'),
        );
        return null;
      case r'$customDebugAdapterRequest':
        return await target.$customDebugAdapterRequest(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'command'),
          a.arg(2, decodeObject, 'args'),
        );
      case r'$getDebugProtocolBreakpoint':
        return await target.$getDebugProtocolBreakpoint(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'breakpoinId'),
        );
      case r'$appendDebugConsole':
        await target.$appendDebugConsole(a.arg(0, decodeString, 'value'));
        return null;
      case r'$registerBreakpoints':
        await target.$registerBreakpoints(
          a.arg(0, decodeListOf(decodeMap), 'breakpoints'),
        );
        return null;
      case r'$unregisterBreakpoints':
        await target.$unregisterBreakpoints(
          a.arg(0, decodeListOf(decodeString), 'breakpointIds'),
          a.arg(1, decodeListOf(decodeString), 'functionBreakpointIds'),
          a.arg(2, decodeListOf(decodeString), 'dataBreakpointIds'),
        );
        return null;
      case r'$registerDebugVisualizer':
        await target.$registerDebugVisualizer(
          a.arg(0, decodeString, 'extensionId'),
          a.arg(1, decodeString, 'id'),
        );
        return null;
      case r'$unregisterDebugVisualizer':
        await target.$unregisterDebugVisualizer(
          a.arg(0, decodeString, 'extensionId'),
          a.arg(1, decodeString, 'id'),
        );
        return null;
      case r'$registerDebugVisualizerTree':
        await target.$registerDebugVisualizerTree(
          a.arg(0, decodeString, 'treeId'),
          a.arg(1, decodeBool, 'canEdit'),
        );
        return null;
      case r'$unregisterDebugVisualizerTree':
        await target.$unregisterDebugVisualizerTree(
          a.arg(0, decodeString, 'treeId'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadDebugService.$method');
    }
  }
}

// --- MainThreadDecorations -----------------------------------------------------

/// `MainThreadDecorationsShape` (`MainThreadDecorations`).
abstract interface class MainThreadDecorationsShape {
  /// `$registerDecorationProvider(handle: number, label: string): void`
  FutureOr<void> $registerDecorationProvider(num handle, String label);

  /// `$unregisterDecorationProvider(handle: number): void`
  FutureOr<void> $unregisterDecorationProvider(num handle);

  /// `$onDidChange(handle: number, resources: UriComponents[] | null): void`
  FutureOr<void> $onDidChange(num handle, List<VsUri>? resources);
}

/// [MainThreadDecorationsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDecorationsUnsupported
    implements MainThreadDecorationsShape {
  const MainThreadDecorationsUnsupported();

  @override
  FutureOr<void> $registerDecorationProvider(num handle, String label) =>
      _unsupported('MainThreadDecorations', r'$registerDecorationProvider');

  @override
  FutureOr<void> $unregisterDecorationProvider(num handle) =>
      _unsupported('MainThreadDecorations', r'$unregisterDecorationProvider');

  @override
  FutureOr<void> $onDidChange(num handle, List<VsUri>? resources) =>
      _unsupported('MainThreadDecorations', r'$onDidChange');
}

/// Decodes requests to [MainContext.mainThreadDecorations] and calls [target].
final class MainThreadDecorationsActor implements RpcActor {
  MainThreadDecorationsActor(this.target);

  static const identifier = MainContext.mainThreadDecorations;

  final MainThreadDecorationsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDecorations.$method', args);
    switch (method) {
      case r'$registerDecorationProvider':
        await target.$registerDecorationProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'label'),
        );
        return null;
      case r'$unregisterDecorationProvider':
        await target.$unregisterDecorationProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$onDidChange':
        await target.$onDidChange(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeListOf(decodeUri)), 'resources'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadDecorations.$method');
    }
  }
}

// --- MainThreadDiagnostics -----------------------------------------------------

/// `MainThreadDiagnosticsShape` (`MainThreadDiagnostics`).
abstract interface class MainThreadDiagnosticsShape {
  /// `$changeMany(owner: string, entries: [UriComponents, IMarkerData[] | undefined][]): void`
  FutureOr<void> $changeMany(String owner, List<List<Object?>> entries);

  /// `$clear(owner: string): void`
  FutureOr<void> $clear(String owner);
}

/// [MainThreadDiagnosticsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDiagnosticsUnsupported
    implements MainThreadDiagnosticsShape {
  const MainThreadDiagnosticsUnsupported();

  @override
  FutureOr<void> $changeMany(String owner, List<List<Object?>> entries) =>
      _unsupported('MainThreadDiagnostics', r'$changeMany');

  @override
  FutureOr<void> $clear(String owner) =>
      _unsupported('MainThreadDiagnostics', r'$clear');
}

/// Decodes requests to [MainContext.mainThreadDiagnostics] and calls [target].
final class MainThreadDiagnosticsActor implements RpcActor {
  MainThreadDiagnosticsActor(this.target);

  static const identifier = MainContext.mainThreadDiagnostics;

  final MainThreadDiagnosticsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDiagnostics.$method', args);
    switch (method) {
      case r'$changeMany':
        await target.$changeMany(
          a.arg(0, decodeString, 'owner'),
          a.arg(1, decodeListOf(decodeListOf(decodeObject)), 'entries'),
        );
        return null;
      case r'$clear':
        await target.$clear(a.arg(0, decodeString, 'owner'));
        return null;
      default:
        throw RpcUnsupported('MainThreadDiagnostics.$method');
    }
  }
}

// --- MainThreadDialogs ---------------------------------------------------------

/// `MainThreadDiaglogsShape` (`MainThreadDiaglogs`).
abstract interface class MainThreadDialogsShape {
  /// `$showOpenDialog(options?: MainThreadDialogOpenOptions): Promise<UriComponents[] | undefined>`
  Future<List<VsUri>?> $showOpenDialog(Map<String, Object?>? options);

  /// `$showSaveDialog(options?: MainThreadDialogSaveOptions): Promise<UriComponents | undefined>`
  Future<VsUri?> $showSaveDialog(Map<String, Object?>? options);
}

/// [MainThreadDialogsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDialogsUnsupported implements MainThreadDialogsShape {
  const MainThreadDialogsUnsupported();

  @override
  Future<List<VsUri>?> $showOpenDialog(Map<String, Object?>? options) =>
      _unsupported('MainThreadDialogs', r'$showOpenDialog');

  @override
  Future<VsUri?> $showSaveDialog(Map<String, Object?>? options) =>
      _unsupported('MainThreadDialogs', r'$showSaveDialog');
}

/// Decodes requests to [MainContext.mainThreadDialogs] and calls [target].
final class MainThreadDialogsActor implements RpcActor {
  MainThreadDialogsActor(this.target);

  static const identifier = MainContext.mainThreadDialogs;

  final MainThreadDialogsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDialogs.$method', args);
    switch (method) {
      case r'$showOpenDialog':
        return await target.$showOpenDialog(
          a.arg(0, decodeNullable(decodeMap), 'options'),
        );
      case r'$showSaveDialog':
        return await target.$showSaveDialog(
          a.arg(0, decodeNullable(decodeMap), 'options'),
        );
      default:
        throw RpcUnsupported('MainThreadDialogs.$method');
    }
  }
}

// --- MainThreadDocuments -------------------------------------------------------

/// `MainThreadDocumentsShape` (`MainThreadDocuments`).
abstract interface class MainThreadDocumentsShape {
  /// `$tryCreateDocument(options?: { language?: string; content?: string; encoding?: string }): Promise<UriComponents>`
  Future<VsUri> $tryCreateDocument(Map<String, Object?>? options);

  /// `$tryOpenDocument(uri: UriComponents, options?: { encoding?: string }): Promise<UriComponents>`
  Future<VsUri> $tryOpenDocument(VsUri uri, Map<String, Object?>? options);

  /// `$trySaveDocument(uri: UriComponents): Promise<boolean>`
  Future<bool> $trySaveDocument(VsUri uri);
}

/// [MainThreadDocumentsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDocumentsUnsupported implements MainThreadDocumentsShape {
  const MainThreadDocumentsUnsupported();

  @override
  Future<VsUri> $tryCreateDocument(Map<String, Object?>? options) =>
      _unsupported('MainThreadDocuments', r'$tryCreateDocument');

  @override
  Future<VsUri> $tryOpenDocument(VsUri uri, Map<String, Object?>? options) =>
      _unsupported('MainThreadDocuments', r'$tryOpenDocument');

  @override
  Future<bool> $trySaveDocument(VsUri uri) =>
      _unsupported('MainThreadDocuments', r'$trySaveDocument');
}

/// Decodes requests to [MainContext.mainThreadDocuments] and calls [target].
final class MainThreadDocumentsActor implements RpcActor {
  MainThreadDocumentsActor(this.target);

  static const identifier = MainContext.mainThreadDocuments;

  final MainThreadDocumentsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDocuments.$method', args);
    switch (method) {
      case r'$tryCreateDocument':
        return await target.$tryCreateDocument(
          a.arg(0, decodeNullable(decodeMap), 'options'),
        );
      case r'$tryOpenDocument':
        return await target.$tryOpenDocument(
          a.arg(0, decodeUri, 'uri'),
          a.arg(1, decodeNullable(decodeMap), 'options'),
        );
      case r'$trySaveDocument':
        return await target.$trySaveDocument(a.arg(0, decodeUri, 'uri'));
      default:
        throw RpcUnsupported('MainThreadDocuments.$method');
    }
  }
}

// --- MainThreadDocumentContentProviders ----------------------------------------

/// `MainThreadDocumentContentProvidersShape` (`MainThreadDocumentContentProviders`).
abstract interface class MainThreadDocumentContentProvidersShape {
  /// `$registerTextContentProvider(handle: number, scheme: string): void`
  FutureOr<void> $registerTextContentProvider(num handle, String scheme);

  /// `$unregisterTextContentProvider(handle: number): void`
  FutureOr<void> $unregisterTextContentProvider(num handle);

  /// `$onVirtualDocumentChange(uri: UriComponents, value: string): Promise<void>`
  FutureOr<void> $onVirtualDocumentChange(VsUri uri, String value);
}

/// [MainThreadDocumentContentProvidersShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDocumentContentProvidersUnsupported
    implements MainThreadDocumentContentProvidersShape {
  const MainThreadDocumentContentProvidersUnsupported();

  @override
  FutureOr<void> $registerTextContentProvider(num handle, String scheme) =>
      _unsupported(
        'MainThreadDocumentContentProviders',
        r'$registerTextContentProvider',
      );

  @override
  FutureOr<void> $unregisterTextContentProvider(num handle) => _unsupported(
    'MainThreadDocumentContentProviders',
    r'$unregisterTextContentProvider',
  );

  @override
  FutureOr<void> $onVirtualDocumentChange(VsUri uri, String value) =>
      _unsupported(
        'MainThreadDocumentContentProviders',
        r'$onVirtualDocumentChange',
      );
}

/// Decodes requests to [MainContext.mainThreadDocumentContentProviders] and calls [target].
final class MainThreadDocumentContentProvidersActor implements RpcActor {
  MainThreadDocumentContentProvidersActor(this.target);

  static const identifier = MainContext.mainThreadDocumentContentProviders;

  final MainThreadDocumentContentProvidersShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDocumentContentProviders.$method', args);
    switch (method) {
      case r'$registerTextContentProvider':
        await target.$registerTextContentProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
        );
        return null;
      case r'$unregisterTextContentProvider':
        await target.$unregisterTextContentProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$onVirtualDocumentChange':
        await target.$onVirtualDocumentChange(
          a.arg(0, decodeUri, 'uri'),
          a.arg(1, decodeString, 'value'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadDocumentContentProviders.$method');
    }
  }
}

// --- MainThreadTextEditors -----------------------------------------------------

/// `MainThreadTextEditorsShape` (`MainThreadTextEditors`).
abstract interface class MainThreadTextEditorsShape {
  /// `$tryShowTextDocument(resource: UriComponents, options: ITextDocumentShowOptions): Promise<string | undefined>`
  Future<String?> $tryShowTextDocument(
    VsUri resource,
    Map<String, Object?> options,
  );

  /// `$registerTextEditorDecorationType(extensionId: ExtensionIdentifier, key: string, options: editorCommon.IDecorationRenderOptions): void`
  FutureOr<void> $registerTextEditorDecorationType(
    Map<String, Object?> extensionId,
    String key,
    Map<String, Object?> options,
  );

  /// `$removeTextEditorDecorationType(key: string): void`
  FutureOr<void> $removeTextEditorDecorationType(String key);

  /// `$tryShowEditor(id: string, position: EditorGroupColumn): Promise<void>`
  FutureOr<void> $tryShowEditor(String id, num position);

  /// `$tryHideEditor(id: string): Promise<void>`
  FutureOr<void> $tryHideEditor(String id);

  /// `$trySetOptions(id: string, options: ITextEditorConfigurationUpdate): Promise<void>`
  FutureOr<void> $trySetOptions(String id, Map<String, Object?> options);

  /// `$trySetDecorations(id: string, key: string, ranges: editorCommon.IDecorationOptions[]): Promise<void>`
  FutureOr<void> $trySetDecorations(
    String id,
    String key,
    List<Map<String, Object?>> ranges,
  );

  /// `$trySetDecorationsFast(id: string, key: string, ranges: number[]): Promise<void>`
  FutureOr<void> $trySetDecorationsFast(
    String id,
    String key,
    List<num> ranges,
  );

  /// `$tryRevealRange(id: string, range: IRange, revealType: TextEditorRevealType): Promise<void>`
  FutureOr<void> $tryRevealRange(
    String id,
    Map<String, Object?> range,
    int revealType,
  );

  /// `$trySetSelections(id: string, selections: ISelection[]): Promise<void>`
  FutureOr<void> $trySetSelections(
    String id,
    List<Map<String, Object?>> selections,
  );

  /// `$tryApplyEdits(id: string, modelVersionId: number, edits: ISingleEditOperation[], opts: IApplyEditsOptions): Promise<boolean>`
  Future<bool> $tryApplyEdits(
    String id,
    num modelVersionId,
    List<Map<String, Object?>> edits,
    Map<String, Object?> opts,
  );

  /// `$tryInsertSnippet(id: string, modelVersionId: number, template: string, selections: readonly IRange[], opts: IUndoStopOptions): Promise<boolean>`
  Future<bool> $tryInsertSnippet(
    String id,
    num modelVersionId,
    String template,
    List<Map<String, Object?>> selections,
    Map<String, Object?> opts,
  );

  /// `$getDiffInformation(id: string): Promise<IChange[]>`
  Future<List<Map<String, Object?>>> $getDiffInformation(String id);
}

/// [MainThreadTextEditorsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTextEditorsUnsupported
    implements MainThreadTextEditorsShape {
  const MainThreadTextEditorsUnsupported();

  @override
  Future<String?> $tryShowTextDocument(
    VsUri resource,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadTextEditors', r'$tryShowTextDocument');

  @override
  FutureOr<void> $registerTextEditorDecorationType(
    Map<String, Object?> extensionId,
    String key,
    Map<String, Object?> options,
  ) => _unsupported(
    'MainThreadTextEditors',
    r'$registerTextEditorDecorationType',
  );

  @override
  FutureOr<void> $removeTextEditorDecorationType(String key) =>
      _unsupported('MainThreadTextEditors', r'$removeTextEditorDecorationType');

  @override
  FutureOr<void> $tryShowEditor(String id, num position) =>
      _unsupported('MainThreadTextEditors', r'$tryShowEditor');

  @override
  FutureOr<void> $tryHideEditor(String id) =>
      _unsupported('MainThreadTextEditors', r'$tryHideEditor');

  @override
  FutureOr<void> $trySetOptions(String id, Map<String, Object?> options) =>
      _unsupported('MainThreadTextEditors', r'$trySetOptions');

  @override
  FutureOr<void> $trySetDecorations(
    String id,
    String key,
    List<Map<String, Object?>> ranges,
  ) => _unsupported('MainThreadTextEditors', r'$trySetDecorations');

  @override
  FutureOr<void> $trySetDecorationsFast(
    String id,
    String key,
    List<num> ranges,
  ) => _unsupported('MainThreadTextEditors', r'$trySetDecorationsFast');

  @override
  FutureOr<void> $tryRevealRange(
    String id,
    Map<String, Object?> range,
    int revealType,
  ) => _unsupported('MainThreadTextEditors', r'$tryRevealRange');

  @override
  FutureOr<void> $trySetSelections(
    String id,
    List<Map<String, Object?>> selections,
  ) => _unsupported('MainThreadTextEditors', r'$trySetSelections');

  @override
  Future<bool> $tryApplyEdits(
    String id,
    num modelVersionId,
    List<Map<String, Object?>> edits,
    Map<String, Object?> opts,
  ) => _unsupported('MainThreadTextEditors', r'$tryApplyEdits');

  @override
  Future<bool> $tryInsertSnippet(
    String id,
    num modelVersionId,
    String template,
    List<Map<String, Object?>> selections,
    Map<String, Object?> opts,
  ) => _unsupported('MainThreadTextEditors', r'$tryInsertSnippet');

  @override
  Future<List<Map<String, Object?>>> $getDiffInformation(String id) =>
      _unsupported('MainThreadTextEditors', r'$getDiffInformation');
}

/// Decodes requests to [MainContext.mainThreadTextEditors] and calls [target].
final class MainThreadTextEditorsActor implements RpcActor {
  MainThreadTextEditorsActor(this.target);

  static const identifier = MainContext.mainThreadTextEditors;

  final MainThreadTextEditorsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTextEditors.$method', args);
    switch (method) {
      case r'$tryShowTextDocument':
        return await target.$tryShowTextDocument(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeMap, 'options'),
        );
      case r'$registerTextEditorDecorationType':
        await target.$registerTextEditorDecorationType(
          a.arg(0, decodeMap, 'extensionId'),
          a.arg(1, decodeString, 'key'),
          a.arg(2, decodeMap, 'options'),
        );
        return null;
      case r'$removeTextEditorDecorationType':
        await target.$removeTextEditorDecorationType(
          a.arg(0, decodeString, 'key'),
        );
        return null;
      case r'$tryShowEditor':
        await target.$tryShowEditor(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeNum, 'position'),
        );
        return null;
      case r'$tryHideEditor':
        await target.$tryHideEditor(a.arg(0, decodeString, 'id'));
        return null;
      case r'$trySetOptions':
        await target.$trySetOptions(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeMap, 'options'),
        );
        return null;
      case r'$trySetDecorations':
        await target.$trySetDecorations(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'key'),
          a.arg(2, decodeListOf(decodeMap), 'ranges'),
        );
        return null;
      case r'$trySetDecorationsFast':
        await target.$trySetDecorationsFast(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'key'),
          a.arg(2, decodeListOf(decodeNum), 'ranges'),
        );
        return null;
      case r'$tryRevealRange':
        await target.$tryRevealRange(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeMap, 'range'),
          a.arg(2, decodeInt, 'revealType'),
        );
        return null;
      case r'$trySetSelections':
        await target.$trySetSelections(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeListOf(decodeMap), 'selections'),
        );
        return null;
      case r'$tryApplyEdits':
        return await target.$tryApplyEdits(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeNum, 'modelVersionId'),
          a.arg(2, decodeListOf(decodeMap), 'edits'),
          a.arg(3, decodeMap, 'opts'),
        );
      case r'$tryInsertSnippet':
        return await target.$tryInsertSnippet(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeNum, 'modelVersionId'),
          a.arg(2, decodeString, 'template'),
          a.arg(3, decodeListOf(decodeMap), 'selections'),
          a.arg(4, decodeMap, 'opts'),
        );
      case r'$getDiffInformation':
        return await target.$getDiffInformation(a.arg(0, decodeString, 'id'));
      default:
        throw RpcUnsupported('MainThreadTextEditors.$method');
    }
  }
}

// --- MainThreadEditorInsets ----------------------------------------------------

/// `MainThreadEditorInsetsShape` (`MainThreadEditorInsets`).
abstract interface class MainThreadEditorInsetsShape {
  /// `$createEditorInset(handle: number, id: string, uri: UriComponents, line: number, height: number, options: IWebviewContentOptions, extensionId: ExtensionIdentifier, extensionLocation: UriComponents): Promise<void>`
  FutureOr<void> $createEditorInset(
    num handle,
    String id,
    VsUri uri,
    num line,
    num height,
    Map<String, Object?> options,
    Map<String, Object?> extensionId,
    VsUri extensionLocation,
  );

  /// `$disposeEditorInset(handle: number): void`
  FutureOr<void> $disposeEditorInset(num handle);

  /// `$setHtml(handle: number, value: string): void`
  FutureOr<void> $setHtml(num handle, String value);

  /// `$setOptions(handle: number, options: IWebviewContentOptions): void`
  FutureOr<void> $setOptions(num handle, Map<String, Object?> options);

  /// `$postMessage(handle: number, value: any): Promise<boolean>`
  Future<bool> $postMessage(num handle, Object? value);
}

/// [MainThreadEditorInsetsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadEditorInsetsUnsupported
    implements MainThreadEditorInsetsShape {
  const MainThreadEditorInsetsUnsupported();

  @override
  FutureOr<void> $createEditorInset(
    num handle,
    String id,
    VsUri uri,
    num line,
    num height,
    Map<String, Object?> options,
    Map<String, Object?> extensionId,
    VsUri extensionLocation,
  ) => _unsupported('MainThreadEditorInsets', r'$createEditorInset');

  @override
  FutureOr<void> $disposeEditorInset(num handle) =>
      _unsupported('MainThreadEditorInsets', r'$disposeEditorInset');

  @override
  FutureOr<void> $setHtml(num handle, String value) =>
      _unsupported('MainThreadEditorInsets', r'$setHtml');

  @override
  FutureOr<void> $setOptions(num handle, Map<String, Object?> options) =>
      _unsupported('MainThreadEditorInsets', r'$setOptions');

  @override
  Future<bool> $postMessage(num handle, Object? value) =>
      _unsupported('MainThreadEditorInsets', r'$postMessage');
}

/// Decodes requests to [MainContext.mainThreadEditorInsets] and calls [target].
final class MainThreadEditorInsetsActor implements RpcActor {
  MainThreadEditorInsetsActor(this.target);

  static const identifier = MainContext.mainThreadEditorInsets;

  final MainThreadEditorInsetsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadEditorInsets.$method', args);
    switch (method) {
      case r'$createEditorInset':
        await target.$createEditorInset(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
          a.arg(2, decodeUri, 'uri'),
          a.arg(3, decodeNum, 'line'),
          a.arg(4, decodeNum, 'height'),
          a.arg(5, decodeMap, 'options'),
          a.arg(6, decodeMap, 'extensionId'),
          a.arg(7, decodeUri, 'extensionLocation'),
        );
        return null;
      case r'$disposeEditorInset':
        await target.$disposeEditorInset(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$setHtml':
        await target.$setHtml(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'value'),
        );
        return null;
      case r'$setOptions':
        await target.$setOptions(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'options'),
        );
        return null;
      case r'$postMessage':
        return await target.$postMessage(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeObject, 'value'),
        );
      default:
        throw RpcUnsupported('MainThreadEditorInsets.$method');
    }
  }
}

// --- MainThreadEditorTabs ------------------------------------------------------

/// `MainThreadEditorTabsShape` (`MainThreadEditorTabs`).
abstract interface class MainThreadEditorTabsShape {
  /// `$moveTab(tabId: string, index: number, viewColumn: EditorGroupColumn, preserveFocus?: boolean): void`
  FutureOr<void> $moveTab(
    String tabId,
    num index,
    num viewColumn,
    bool? preserveFocus,
  );

  /// `$closeTab(tabIds: string[], preserveFocus?: boolean): Promise<boolean>`
  Future<bool> $closeTab(List<String> tabIds, bool? preserveFocus);

  /// `$closeGroup(groupIds: number[], preservceFocus?: boolean): Promise<boolean>`
  Future<bool> $closeGroup(List<num> groupIds, bool? preservceFocus);
}

/// [MainThreadEditorTabsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadEditorTabsUnsupported
    implements MainThreadEditorTabsShape {
  const MainThreadEditorTabsUnsupported();

  @override
  FutureOr<void> $moveTab(
    String tabId,
    num index,
    num viewColumn,
    bool? preserveFocus,
  ) => _unsupported('MainThreadEditorTabs', r'$moveTab');

  @override
  Future<bool> $closeTab(List<String> tabIds, bool? preserveFocus) =>
      _unsupported('MainThreadEditorTabs', r'$closeTab');

  @override
  Future<bool> $closeGroup(List<num> groupIds, bool? preservceFocus) =>
      _unsupported('MainThreadEditorTabs', r'$closeGroup');
}

/// Decodes requests to [MainContext.mainThreadEditorTabs] and calls [target].
final class MainThreadEditorTabsActor implements RpcActor {
  MainThreadEditorTabsActor(this.target);

  static const identifier = MainContext.mainThreadEditorTabs;

  final MainThreadEditorTabsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadEditorTabs.$method', args);
    switch (method) {
      case r'$moveTab':
        await target.$moveTab(
          a.arg(0, decodeString, 'tabId'),
          a.arg(1, decodeNum, 'index'),
          a.arg(2, decodeNum, 'viewColumn'),
          a.arg(3, decodeNullable(decodeBool), 'preserveFocus'),
        );
        return null;
      case r'$closeTab':
        return await target.$closeTab(
          a.arg(0, decodeListOf(decodeString), 'tabIds'),
          a.arg(1, decodeNullable(decodeBool), 'preserveFocus'),
        );
      case r'$closeGroup':
        return await target.$closeGroup(
          a.arg(0, decodeListOf(decodeNum), 'groupIds'),
          a.arg(1, decodeNullable(decodeBool), 'preservceFocus'),
        );
      default:
        throw RpcUnsupported('MainThreadEditorTabs.$method');
    }
  }
}

// --- MainThreadErrors ----------------------------------------------------------

/// `MainThreadErrorsShape` (`MainThreadErrors`).
abstract interface class MainThreadErrorsShape {
  /// `$onUnexpectedError(err: any | SerializedError): void`
  FutureOr<void> $onUnexpectedError(Object? err);
}

/// [MainThreadErrorsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadErrorsUnsupported implements MainThreadErrorsShape {
  const MainThreadErrorsUnsupported();

  @override
  FutureOr<void> $onUnexpectedError(Object? err) =>
      _unsupported('MainThreadErrors', r'$onUnexpectedError');
}

/// Decodes requests to [MainContext.mainThreadErrors] and calls [target].
final class MainThreadErrorsActor implements RpcActor {
  MainThreadErrorsActor(this.target);

  static const identifier = MainContext.mainThreadErrors;

  final MainThreadErrorsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadErrors.$method', args);
    switch (method) {
      case r'$onUnexpectedError':
        await target.$onUnexpectedError(a.arg(0, decodeObject, 'err'));
        return null;
      default:
        throw RpcUnsupported('MainThreadErrors.$method');
    }
  }
}

// --- MainThreadTreeViews -------------------------------------------------------

/// `MainThreadTreeViewsShape` (`MainThreadTreeViews`).
abstract interface class MainThreadTreeViewsShape {
  /// `$registerTreeViewDataProvider(treeViewId: string, options: { showCollapseAll: boolean; canSelectMany: boolean; dropMimeTypes: readonly string[]; dragMimeTypes: readonly string[]; hasHandleDrag: boolean; hasHandleDrop: boolean; manuallyManageCheckboxes: boolean }): Promise<void>`
  FutureOr<void> $registerTreeViewDataProvider(
    String treeViewId,
    Map<String, Object?> options,
  );

  /// `$refresh(treeViewId: string, itemsToRefresh?: { [treeItemHandle: string]: ITreeItem }): Promise<void>`
  FutureOr<void> $refresh(
    String treeViewId,
    Map<String, Map<String, Object?>>? itemsToRefresh,
  );

  /// `$reveal(treeViewId: string, itemInfo: { item: ITreeItem; parentChain: ITreeItem[] } | undefined, options: IRevealOptions): Promise<void>`
  FutureOr<void> $reveal(
    String treeViewId,
    Map<String, Object?>? itemInfo,
    Map<String, Object?> options,
  );

  /// `$setMessage(treeViewId: string, message: string | IMarkdownString): void`
  FutureOr<void> $setMessage(String treeViewId, Object? message);

  /// `$setTitle(treeViewId: string, title: string, description: string | undefined): void`
  FutureOr<void> $setTitle(
    String treeViewId,
    String title,
    String? description,
  );

  /// `$setBadge(treeViewId: string, badge: IViewBadge | undefined): void`
  FutureOr<void> $setBadge(String treeViewId, Map<String, Object?>? badge);

  /// `$resolveDropFileData(destinationViewId: string, requestId: number, dataItemId: string): Promise<VSBuffer>`
  Future<RpcBuffer> $resolveDropFileData(
    String destinationViewId,
    num requestId,
    String dataItemId,
  );

  /// `$disposeTree(treeViewId: string): Promise<void>`
  FutureOr<void> $disposeTree(String treeViewId);

  /// `$logResolveTreeNodeFailure(extensionId: string): void`
  FutureOr<void> $logResolveTreeNodeFailure(String extensionId);
}

/// [MainThreadTreeViewsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTreeViewsUnsupported implements MainThreadTreeViewsShape {
  const MainThreadTreeViewsUnsupported();

  @override
  FutureOr<void> $registerTreeViewDataProvider(
    String treeViewId,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadTreeViews', r'$registerTreeViewDataProvider');

  @override
  FutureOr<void> $refresh(
    String treeViewId,
    Map<String, Map<String, Object?>>? itemsToRefresh,
  ) => _unsupported('MainThreadTreeViews', r'$refresh');

  @override
  FutureOr<void> $reveal(
    String treeViewId,
    Map<String, Object?>? itemInfo,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadTreeViews', r'$reveal');

  @override
  FutureOr<void> $setMessage(String treeViewId, Object? message) =>
      _unsupported('MainThreadTreeViews', r'$setMessage');

  @override
  FutureOr<void> $setTitle(
    String treeViewId,
    String title,
    String? description,
  ) => _unsupported('MainThreadTreeViews', r'$setTitle');

  @override
  FutureOr<void> $setBadge(String treeViewId, Map<String, Object?>? badge) =>
      _unsupported('MainThreadTreeViews', r'$setBadge');

  @override
  Future<RpcBuffer> $resolveDropFileData(
    String destinationViewId,
    num requestId,
    String dataItemId,
  ) => _unsupported('MainThreadTreeViews', r'$resolveDropFileData');

  @override
  FutureOr<void> $disposeTree(String treeViewId) =>
      _unsupported('MainThreadTreeViews', r'$disposeTree');

  @override
  FutureOr<void> $logResolveTreeNodeFailure(String extensionId) =>
      _unsupported('MainThreadTreeViews', r'$logResolveTreeNodeFailure');
}

/// Decodes requests to [MainContext.mainThreadTreeViews] and calls [target].
final class MainThreadTreeViewsActor implements RpcActor {
  MainThreadTreeViewsActor(this.target);

  static const identifier = MainContext.mainThreadTreeViews;

  final MainThreadTreeViewsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTreeViews.$method', args);
    switch (method) {
      case r'$registerTreeViewDataProvider':
        await target.$registerTreeViewDataProvider(
          a.arg(0, decodeString, 'treeViewId'),
          a.arg(1, decodeMap, 'options'),
        );
        return null;
      case r'$refresh':
        await target.$refresh(
          a.arg(0, decodeString, 'treeViewId'),
          a.arg(1, decodeNullable(decodeMapOf(decodeMap)), 'itemsToRefresh'),
        );
        return null;
      case r'$reveal':
        await target.$reveal(
          a.arg(0, decodeString, 'treeViewId'),
          a.arg(1, decodeNullable(decodeMap), 'itemInfo'),
          a.arg(2, decodeMap, 'options'),
        );
        return null;
      case r'$setMessage':
        await target.$setMessage(
          a.arg(0, decodeString, 'treeViewId'),
          a.arg(1, decodeObject, 'message'),
        );
        return null;
      case r'$setTitle':
        await target.$setTitle(
          a.arg(0, decodeString, 'treeViewId'),
          a.arg(1, decodeString, 'title'),
          a.arg(2, decodeNullable(decodeString), 'description'),
        );
        return null;
      case r'$setBadge':
        await target.$setBadge(
          a.arg(0, decodeString, 'treeViewId'),
          a.arg(1, decodeNullable(decodeMap), 'badge'),
        );
        return null;
      case r'$resolveDropFileData':
        return await target.$resolveDropFileData(
          a.arg(0, decodeString, 'destinationViewId'),
          a.arg(1, decodeNum, 'requestId'),
          a.arg(2, decodeString, 'dataItemId'),
        );
      case r'$disposeTree':
        await target.$disposeTree(a.arg(0, decodeString, 'treeViewId'));
        return null;
      case r'$logResolveTreeNodeFailure':
        await target.$logResolveTreeNodeFailure(
          a.arg(0, decodeString, 'extensionId'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTreeViews.$method');
    }
  }
}

// --- MainThreadDownloadService -------------------------------------------------

/// `MainThreadDownloadServiceShape` (`MainThreadDownloadService`).
abstract interface class MainThreadDownloadServiceShape {
  /// `$download(uri: UriComponents, to: UriComponents): Promise<void>`
  FutureOr<void> $download(VsUri uri, VsUri to);
}

/// [MainThreadDownloadServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDownloadServiceUnsupported
    implements MainThreadDownloadServiceShape {
  const MainThreadDownloadServiceUnsupported();

  @override
  FutureOr<void> $download(VsUri uri, VsUri to) =>
      _unsupported('MainThreadDownloadService', r'$download');
}

/// Decodes requests to [MainContext.mainThreadDownloadService] and calls [target].
final class MainThreadDownloadServiceActor implements RpcActor {
  MainThreadDownloadServiceActor(this.target);

  static const identifier = MainContext.mainThreadDownloadService;

  final MainThreadDownloadServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDownloadService.$method', args);
    switch (method) {
      case r'$download':
        await target.$download(
          a.arg(0, decodeUri, 'uri'),
          a.arg(1, decodeUri, 'to'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadDownloadService.$method');
    }
  }
}

// --- MainThreadLanguageFeatures ------------------------------------------------

/// `MainThreadLanguageFeaturesShape` (`MainThreadLanguageFeatures`).
abstract interface class MainThreadLanguageFeaturesShape {
  /// `$unregister(handle: number): void`
  FutureOr<void> $unregister(num handle);

  /// `$registerDocumentSymbolProvider(handle: number, selector: IDocumentFilterDto[], label: string): void`
  FutureOr<void> $registerDocumentSymbolProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String label,
  );

  /// `$registerCodeLensSupport(handle: number, selector: IDocumentFilterDto[], eventHandle: number | undefined): void`
  FutureOr<void> $registerCodeLensSupport(
    num handle,
    List<Map<String, Object?>> selector,
    num? eventHandle,
  );

  /// `$emitCodeLensEvent(eventHandle: number, event?: any): void`
  FutureOr<void> $emitCodeLensEvent(num eventHandle, Object? event);

  /// `$registerDefinitionSupport(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerDefinitionSupport(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerDeclarationSupport(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerDeclarationSupport(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerImplementationSupport(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerImplementationSupport(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerTypeDefinitionSupport(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerTypeDefinitionSupport(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerHoverProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerHoverProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerEvaluatableExpressionProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerEvaluatableExpressionProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerInlineValuesProvider(handle: number, selector: IDocumentFilterDto[], eventHandle: number | undefined): void`
  FutureOr<void> $registerInlineValuesProvider(
    num handle,
    List<Map<String, Object?>> selector,
    num? eventHandle,
  );

  /// `$emitInlineValuesEvent(eventHandle: number, event?: any): void`
  FutureOr<void> $emitInlineValuesEvent(num eventHandle, Object? event);

  /// `$registerDocumentHighlightProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerDocumentHighlightProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerMultiDocumentHighlightProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerMultiDocumentHighlightProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerLinkedEditingRangeProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerLinkedEditingRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerReferenceSupport(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerReferenceSupport(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerCodeActionSupport(handle: number, selector: IDocumentFilterDto[], metadata: ICodeActionProviderMetadataDto, displayName: string, extensionID: string, supportsResolve: boolean): void`
  FutureOr<void> $registerCodeActionSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
    String displayName,
    String extensionID,
    bool supportsResolve,
  );

  /// `$registerPasteEditProvider(handle: number, selector: IDocumentFilterDto[], metadata: IPasteEditProviderMetadataDto): void`
  FutureOr<void> $registerPasteEditProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
  );

  /// `$registerDocumentFormattingSupport(handle: number, selector: IDocumentFilterDto[], extensionId: ExtensionIdentifier, displayName: string): void`
  FutureOr<void> $registerDocumentFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    String displayName,
  );

  /// `$registerRangeFormattingSupport(handle: number, selector: IDocumentFilterDto[], extensionId: ExtensionIdentifier, displayName: string, supportRanges: boolean): void`
  FutureOr<void> $registerRangeFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    String displayName,
    bool supportRanges,
  );

  /// `$registerOnTypeFormattingSupport(handle: number, selector: IDocumentFilterDto[], autoFormatTriggerCharacters: string[], extensionId: ExtensionIdentifier): void`
  FutureOr<void> $registerOnTypeFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    List<String> autoFormatTriggerCharacters,
    Map<String, Object?> extensionId,
  );

  /// `$registerNavigateTypeSupport(handle: number, supportsResolve: boolean): void`
  FutureOr<void> $registerNavigateTypeSupport(num handle, bool supportsResolve);

  /// `$registerRenameSupport(handle: number, selector: IDocumentFilterDto[], supportsResolveInitialValues: boolean): void`
  FutureOr<void> $registerRenameSupport(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolveInitialValues,
  );

  /// `$registerNewSymbolNamesProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerNewSymbolNamesProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerDocumentSemanticTokensProvider(handle: number, selector: IDocumentFilterDto[], legend: languages.SemanticTokensLegend, eventHandle: number | undefined): void`
  FutureOr<void> $registerDocumentSemanticTokensProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> legend,
    num? eventHandle,
  );

  /// `$emitDocumentSemanticTokensEvent(eventHandle: number): void`
  FutureOr<void> $emitDocumentSemanticTokensEvent(num eventHandle);

  /// `$registerDocumentRangeSemanticTokensProvider(handle: number, selector: IDocumentFilterDto[], legend: languages.SemanticTokensLegend, eventHandle: number | undefined): void`
  FutureOr<void> $registerDocumentRangeSemanticTokensProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> legend,
    num? eventHandle,
  );

  /// `$emitDocumentRangeSemanticTokensEvent(eventHandle: number): void`
  FutureOr<void> $emitDocumentRangeSemanticTokensEvent(num eventHandle);

  /// `$registerCompletionsProvider(handle: number, selector: IDocumentFilterDto[], triggerCharacters: string[], supportsResolveDetails: boolean, extensionId: ExtensionIdentifier): void`
  FutureOr<void> $registerCompletionsProvider(
    num handle,
    List<Map<String, Object?>> selector,
    List<String> triggerCharacters,
    bool supportsResolveDetails,
    Map<String, Object?> extensionId,
  );

  /// `$registerInlineCompletionsSupport(handle: number, selector: IDocumentFilterDto[], supportsHandleEvents: boolean, extensionId: string, extensionVersion: string, groupId: string | undefined, yieldsToExtensionIds: string[], displayName: string | undefined, debounceDelayMs: number | undefined, excludesExtensionIds: string[], supportsSetModelId: boolean, supportsOnDidChange: boolean, initialModelInfo: IInlineCompletionModelInfoDto | undefined, supportsOnDidChangeModelInfo: boolean, supportsSetProviderOption: boolean, initialProviderOptions: readonly IInlineCompletionProviderOptionDto[] | undefined, supportsOnDidChangeProviderOptions: boolean): void`
  FutureOr<void> $registerInlineCompletionsSupport(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsHandleEvents,
    String extensionId,
    String extensionVersion,
    String? groupId,
    List<String> yieldsToExtensionIds,
    String? displayName,
    num? debounceDelayMs,
    List<String> excludesExtensionIds,
    bool supportsSetModelId,
    bool supportsOnDidChange,
    Map<String, Object?>? initialModelInfo,
    bool supportsOnDidChangeModelInfo,
    bool supportsSetProviderOption,
    List<Map<String, Object?>>? initialProviderOptions,
    bool supportsOnDidChangeProviderOptions,
  );

  /// `$emitInlineCompletionsChange(handle: number, changeHint: IInlineCompletionChangeHintDto | undefined): void`
  FutureOr<void> $emitInlineCompletionsChange(
    num handle,
    Map<String, Object?>? changeHint,
  );

  /// `$emitInlineCompletionModelInfoChange(handle: number, data: IInlineCompletionModelInfoDto | undefined): void`
  FutureOr<void> $emitInlineCompletionModelInfoChange(
    num handle,
    Map<String, Object?>? data,
  );

  /// `$emitInlineCompletionProviderOptionsChange(handle: number, data: readonly IInlineCompletionProviderOptionDto[] | undefined): void`
  FutureOr<void> $emitInlineCompletionProviderOptionsChange(
    num handle,
    List<Map<String, Object?>>? data,
  );

  /// `$registerSignatureHelpProvider(handle: number, selector: IDocumentFilterDto[], metadata: ISignatureHelpProviderMetadataDto): void`
  FutureOr<void> $registerSignatureHelpProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
  );

  /// `$registerInlayHintsProvider(handle: number, selector: IDocumentFilterDto[], supportsResolve: boolean, eventHandle: number | undefined, displayName: string | undefined): void`
  FutureOr<void> $registerInlayHintsProvider(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolve,
    num? eventHandle,
    String? displayName,
  );

  /// `$emitInlayHintsEvent(eventHandle: number): void`
  FutureOr<void> $emitInlayHintsEvent(num eventHandle);

  /// `$registerDocumentLinkProvider(handle: number, selector: IDocumentFilterDto[], supportsResolve: boolean): void`
  FutureOr<void> $registerDocumentLinkProvider(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolve,
  );

  /// `$registerDocumentColorProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerDocumentColorProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerFoldingRangeProvider(handle: number, selector: IDocumentFilterDto[], extensionId: ExtensionIdentifier, eventHandle: number | undefined): void`
  FutureOr<void> $registerFoldingRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    num? eventHandle,
  );

  /// `$emitFoldingRangeEvent(eventHandle: number, event?: any): void`
  FutureOr<void> $emitFoldingRangeEvent(num eventHandle, Object? event);

  /// `$registerSelectionRangeProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerSelectionRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerCallHierarchyProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerCallHierarchyProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerTypeHierarchyProvider(handle: number, selector: IDocumentFilterDto[]): void`
  FutureOr<void> $registerTypeHierarchyProvider(
    num handle,
    List<Map<String, Object?>> selector,
  );

  /// `$registerDocumentOnDropEditProvider(handle: number, selector: IDocumentFilterDto[], metadata?: IDocumentDropEditProviderMetadata): void`
  FutureOr<void> $registerDocumentOnDropEditProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?>? metadata,
  );

  /// `$resolvePasteFileData(handle: number, requestId: number, dataId: string): Promise<VSBuffer>`
  Future<RpcBuffer> $resolvePasteFileData(
    num handle,
    num requestId,
    String dataId,
  );

  /// `$resolveDocumentOnDropFileData(handle: number, requestId: number, dataId: string): Promise<VSBuffer>`
  Future<RpcBuffer> $resolveDocumentOnDropFileData(
    num handle,
    num requestId,
    String dataId,
  );

  /// `$setLanguageConfiguration(handle: number, languageId: string, configuration: ILanguageConfigurationDto): void`
  FutureOr<void> $setLanguageConfiguration(
    num handle,
    String languageId,
    Map<String, Object?> configuration,
  );
}

/// [MainThreadLanguageFeaturesShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLanguageFeaturesUnsupported
    implements MainThreadLanguageFeaturesShape {
  const MainThreadLanguageFeaturesUnsupported();

  @override
  FutureOr<void> $unregister(num handle) =>
      _unsupported('MainThreadLanguageFeatures', r'$unregister');

  @override
  FutureOr<void> $registerDocumentSymbolProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String label,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentSymbolProvider',
  );

  @override
  FutureOr<void> $registerCodeLensSupport(
    num handle,
    List<Map<String, Object?>> selector,
    num? eventHandle,
  ) => _unsupported('MainThreadLanguageFeatures', r'$registerCodeLensSupport');

  @override
  FutureOr<void> $emitCodeLensEvent(num eventHandle, Object? event) =>
      _unsupported('MainThreadLanguageFeatures', r'$emitCodeLensEvent');

  @override
  FutureOr<void> $registerDefinitionSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) =>
      _unsupported('MainThreadLanguageFeatures', r'$registerDefinitionSupport');

  @override
  FutureOr<void> $registerDeclarationSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDeclarationSupport',
  );

  @override
  FutureOr<void> $registerImplementationSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerImplementationSupport',
  );

  @override
  FutureOr<void> $registerTypeDefinitionSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerTypeDefinitionSupport',
  );

  @override
  FutureOr<void> $registerHoverProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported('MainThreadLanguageFeatures', r'$registerHoverProvider');

  @override
  FutureOr<void> $registerEvaluatableExpressionProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerEvaluatableExpressionProvider',
  );

  @override
  FutureOr<void> $registerInlineValuesProvider(
    num handle,
    List<Map<String, Object?>> selector,
    num? eventHandle,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerInlineValuesProvider',
  );

  @override
  FutureOr<void> $emitInlineValuesEvent(num eventHandle, Object? event) =>
      _unsupported('MainThreadLanguageFeatures', r'$emitInlineValuesEvent');

  @override
  FutureOr<void> $registerDocumentHighlightProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentHighlightProvider',
  );

  @override
  FutureOr<void> $registerMultiDocumentHighlightProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerMultiDocumentHighlightProvider',
  );

  @override
  FutureOr<void> $registerLinkedEditingRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerLinkedEditingRangeProvider',
  );

  @override
  FutureOr<void> $registerReferenceSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported('MainThreadLanguageFeatures', r'$registerReferenceSupport');

  @override
  FutureOr<void> $registerCodeActionSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
    String displayName,
    String extensionID,
    bool supportsResolve,
  ) =>
      _unsupported('MainThreadLanguageFeatures', r'$registerCodeActionSupport');

  @override
  FutureOr<void> $registerPasteEditProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
  ) =>
      _unsupported('MainThreadLanguageFeatures', r'$registerPasteEditProvider');

  @override
  FutureOr<void> $registerDocumentFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    String displayName,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentFormattingSupport',
  );

  @override
  FutureOr<void> $registerRangeFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    String displayName,
    bool supportRanges,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerRangeFormattingSupport',
  );

  @override
  FutureOr<void> $registerOnTypeFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    List<String> autoFormatTriggerCharacters,
    Map<String, Object?> extensionId,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerOnTypeFormattingSupport',
  );

  @override
  FutureOr<void> $registerNavigateTypeSupport(
    num handle,
    bool supportsResolve,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerNavigateTypeSupport',
  );

  @override
  FutureOr<void> $registerRenameSupport(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolveInitialValues,
  ) => _unsupported('MainThreadLanguageFeatures', r'$registerRenameSupport');

  @override
  FutureOr<void> $registerNewSymbolNamesProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerNewSymbolNamesProvider',
  );

  @override
  FutureOr<void> $registerDocumentSemanticTokensProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> legend,
    num? eventHandle,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentSemanticTokensProvider',
  );

  @override
  FutureOr<void> $emitDocumentSemanticTokensEvent(num eventHandle) =>
      _unsupported(
        'MainThreadLanguageFeatures',
        r'$emitDocumentSemanticTokensEvent',
      );

  @override
  FutureOr<void> $registerDocumentRangeSemanticTokensProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> legend,
    num? eventHandle,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentRangeSemanticTokensProvider',
  );

  @override
  FutureOr<void> $emitDocumentRangeSemanticTokensEvent(num eventHandle) =>
      _unsupported(
        'MainThreadLanguageFeatures',
        r'$emitDocumentRangeSemanticTokensEvent',
      );

  @override
  FutureOr<void> $registerCompletionsProvider(
    num handle,
    List<Map<String, Object?>> selector,
    List<String> triggerCharacters,
    bool supportsResolveDetails,
    Map<String, Object?> extensionId,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerCompletionsProvider',
  );

  @override
  FutureOr<void> $registerInlineCompletionsSupport(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsHandleEvents,
    String extensionId,
    String extensionVersion,
    String? groupId,
    List<String> yieldsToExtensionIds,
    String? displayName,
    num? debounceDelayMs,
    List<String> excludesExtensionIds,
    bool supportsSetModelId,
    bool supportsOnDidChange,
    Map<String, Object?>? initialModelInfo,
    bool supportsOnDidChangeModelInfo,
    bool supportsSetProviderOption,
    List<Map<String, Object?>>? initialProviderOptions,
    bool supportsOnDidChangeProviderOptions,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerInlineCompletionsSupport',
  );

  @override
  FutureOr<void> $emitInlineCompletionsChange(
    num handle,
    Map<String, Object?>? changeHint,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$emitInlineCompletionsChange',
  );

  @override
  FutureOr<void> $emitInlineCompletionModelInfoChange(
    num handle,
    Map<String, Object?>? data,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$emitInlineCompletionModelInfoChange',
  );

  @override
  FutureOr<void> $emitInlineCompletionProviderOptionsChange(
    num handle,
    List<Map<String, Object?>>? data,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$emitInlineCompletionProviderOptionsChange',
  );

  @override
  FutureOr<void> $registerSignatureHelpProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerSignatureHelpProvider',
  );

  @override
  FutureOr<void> $registerInlayHintsProvider(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolve,
    num? eventHandle,
    String? displayName,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerInlayHintsProvider',
  );

  @override
  FutureOr<void> $emitInlayHintsEvent(num eventHandle) =>
      _unsupported('MainThreadLanguageFeatures', r'$emitInlayHintsEvent');

  @override
  FutureOr<void> $registerDocumentLinkProvider(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolve,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentLinkProvider',
  );

  @override
  FutureOr<void> $registerDocumentColorProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentColorProvider',
  );

  @override
  FutureOr<void> $registerFoldingRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    num? eventHandle,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerFoldingRangeProvider',
  );

  @override
  FutureOr<void> $emitFoldingRangeEvent(num eventHandle, Object? event) =>
      _unsupported('MainThreadLanguageFeatures', r'$emitFoldingRangeEvent');

  @override
  FutureOr<void> $registerSelectionRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerSelectionRangeProvider',
  );

  @override
  FutureOr<void> $registerCallHierarchyProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerCallHierarchyProvider',
  );

  @override
  FutureOr<void> $registerTypeHierarchyProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerTypeHierarchyProvider',
  );

  @override
  FutureOr<void> $registerDocumentOnDropEditProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?>? metadata,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$registerDocumentOnDropEditProvider',
  );

  @override
  Future<RpcBuffer> $resolvePasteFileData(
    num handle,
    num requestId,
    String dataId,
  ) => _unsupported('MainThreadLanguageFeatures', r'$resolvePasteFileData');

  @override
  Future<RpcBuffer> $resolveDocumentOnDropFileData(
    num handle,
    num requestId,
    String dataId,
  ) => _unsupported(
    'MainThreadLanguageFeatures',
    r'$resolveDocumentOnDropFileData',
  );

  @override
  FutureOr<void> $setLanguageConfiguration(
    num handle,
    String languageId,
    Map<String, Object?> configuration,
  ) => _unsupported('MainThreadLanguageFeatures', r'$setLanguageConfiguration');
}

/// Decodes requests to [MainContext.mainThreadLanguageFeatures] and calls [target].
final class MainThreadLanguageFeaturesActor implements RpcActor {
  MainThreadLanguageFeaturesActor(this.target);

  static const identifier = MainContext.mainThreadLanguageFeatures;

  final MainThreadLanguageFeaturesShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLanguageFeatures.$method', args);
    switch (method) {
      case r'$unregister':
        await target.$unregister(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$registerDocumentSymbolProvider':
        await target.$registerDocumentSymbolProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeString, 'label'),
        );
        return null;
      case r'$registerCodeLensSupport':
        await target.$registerCodeLensSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeNullable(decodeNum), 'eventHandle'),
        );
        return null;
      case r'$emitCodeLensEvent':
        await target.$emitCodeLensEvent(
          a.arg(0, decodeNum, 'eventHandle'),
          a.arg(1, decodeObject, 'event'),
        );
        return null;
      case r'$registerDefinitionSupport':
        await target.$registerDefinitionSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerDeclarationSupport':
        await target.$registerDeclarationSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerImplementationSupport':
        await target.$registerImplementationSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerTypeDefinitionSupport':
        await target.$registerTypeDefinitionSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerHoverProvider':
        await target.$registerHoverProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerEvaluatableExpressionProvider':
        await target.$registerEvaluatableExpressionProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerInlineValuesProvider':
        await target.$registerInlineValuesProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeNullable(decodeNum), 'eventHandle'),
        );
        return null;
      case r'$emitInlineValuesEvent':
        await target.$emitInlineValuesEvent(
          a.arg(0, decodeNum, 'eventHandle'),
          a.arg(1, decodeObject, 'event'),
        );
        return null;
      case r'$registerDocumentHighlightProvider':
        await target.$registerDocumentHighlightProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerMultiDocumentHighlightProvider':
        await target.$registerMultiDocumentHighlightProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerLinkedEditingRangeProvider':
        await target.$registerLinkedEditingRangeProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerReferenceSupport':
        await target.$registerReferenceSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerCodeActionSupport':
        await target.$registerCodeActionSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'metadata'),
          a.arg(3, decodeString, 'displayName'),
          a.arg(4, decodeString, 'extensionID'),
          a.arg(5, decodeBool, 'supportsResolve'),
        );
        return null;
      case r'$registerPasteEditProvider':
        await target.$registerPasteEditProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'metadata'),
        );
        return null;
      case r'$registerDocumentFormattingSupport':
        await target.$registerDocumentFormattingSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'extensionId'),
          a.arg(3, decodeString, 'displayName'),
        );
        return null;
      case r'$registerRangeFormattingSupport':
        await target.$registerRangeFormattingSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'extensionId'),
          a.arg(3, decodeString, 'displayName'),
          a.arg(4, decodeBool, 'supportRanges'),
        );
        return null;
      case r'$registerOnTypeFormattingSupport':
        await target.$registerOnTypeFormattingSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeListOf(decodeString), 'autoFormatTriggerCharacters'),
          a.arg(3, decodeMap, 'extensionId'),
        );
        return null;
      case r'$registerNavigateTypeSupport':
        await target.$registerNavigateTypeSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeBool, 'supportsResolve'),
        );
        return null;
      case r'$registerRenameSupport':
        await target.$registerRenameSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeBool, 'supportsResolveInitialValues'),
        );
        return null;
      case r'$registerNewSymbolNamesProvider':
        await target.$registerNewSymbolNamesProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerDocumentSemanticTokensProvider':
        await target.$registerDocumentSemanticTokensProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'legend'),
          a.arg(3, decodeNullable(decodeNum), 'eventHandle'),
        );
        return null;
      case r'$emitDocumentSemanticTokensEvent':
        await target.$emitDocumentSemanticTokensEvent(
          a.arg(0, decodeNum, 'eventHandle'),
        );
        return null;
      case r'$registerDocumentRangeSemanticTokensProvider':
        await target.$registerDocumentRangeSemanticTokensProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'legend'),
          a.arg(3, decodeNullable(decodeNum), 'eventHandle'),
        );
        return null;
      case r'$emitDocumentRangeSemanticTokensEvent':
        await target.$emitDocumentRangeSemanticTokensEvent(
          a.arg(0, decodeNum, 'eventHandle'),
        );
        return null;
      case r'$registerCompletionsProvider':
        await target.$registerCompletionsProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeListOf(decodeString), 'triggerCharacters'),
          a.arg(3, decodeBool, 'supportsResolveDetails'),
          a.arg(4, decodeMap, 'extensionId'),
        );
        return null;
      case r'$registerInlineCompletionsSupport':
        await target.$registerInlineCompletionsSupport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeBool, 'supportsHandleEvents'),
          a.arg(3, decodeString, 'extensionId'),
          a.arg(4, decodeString, 'extensionVersion'),
          a.arg(5, decodeNullable(decodeString), 'groupId'),
          a.arg(6, decodeListOf(decodeString), 'yieldsToExtensionIds'),
          a.arg(7, decodeNullable(decodeString), 'displayName'),
          a.arg(8, decodeNullable(decodeNum), 'debounceDelayMs'),
          a.arg(9, decodeListOf(decodeString), 'excludesExtensionIds'),
          a.arg(10, decodeBool, 'supportsSetModelId'),
          a.arg(11, decodeBool, 'supportsOnDidChange'),
          a.arg(12, decodeNullable(decodeMap), 'initialModelInfo'),
          a.arg(13, decodeBool, 'supportsOnDidChangeModelInfo'),
          a.arg(14, decodeBool, 'supportsSetProviderOption'),
          a.arg(
            15,
            decodeNullable(decodeListOf(decodeMap)),
            'initialProviderOptions',
          ),
          a.arg(16, decodeBool, 'supportsOnDidChangeProviderOptions'),
        );
        return null;
      case r'$emitInlineCompletionsChange':
        await target.$emitInlineCompletionsChange(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeMap), 'changeHint'),
        );
        return null;
      case r'$emitInlineCompletionModelInfoChange':
        await target.$emitInlineCompletionModelInfoChange(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeMap), 'data'),
        );
        return null;
      case r'$emitInlineCompletionProviderOptionsChange':
        await target.$emitInlineCompletionProviderOptionsChange(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeListOf(decodeMap)), 'data'),
        );
        return null;
      case r'$registerSignatureHelpProvider':
        await target.$registerSignatureHelpProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'metadata'),
        );
        return null;
      case r'$registerInlayHintsProvider':
        await target.$registerInlayHintsProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeBool, 'supportsResolve'),
          a.arg(3, decodeNullable(decodeNum), 'eventHandle'),
          a.arg(4, decodeNullable(decodeString), 'displayName'),
        );
        return null;
      case r'$emitInlayHintsEvent':
        await target.$emitInlayHintsEvent(a.arg(0, decodeNum, 'eventHandle'));
        return null;
      case r'$registerDocumentLinkProvider':
        await target.$registerDocumentLinkProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeBool, 'supportsResolve'),
        );
        return null;
      case r'$registerDocumentColorProvider':
        await target.$registerDocumentColorProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerFoldingRangeProvider':
        await target.$registerFoldingRangeProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeMap, 'extensionId'),
          a.arg(3, decodeNullable(decodeNum), 'eventHandle'),
        );
        return null;
      case r'$emitFoldingRangeEvent':
        await target.$emitFoldingRangeEvent(
          a.arg(0, decodeNum, 'eventHandle'),
          a.arg(1, decodeObject, 'event'),
        );
        return null;
      case r'$registerSelectionRangeProvider':
        await target.$registerSelectionRangeProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerCallHierarchyProvider':
        await target.$registerCallHierarchyProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerTypeHierarchyProvider':
        await target.$registerTypeHierarchyProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
        );
        return null;
      case r'$registerDocumentOnDropEditProvider':
        await target.$registerDocumentOnDropEditProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeNullable(decodeMap), 'metadata'),
        );
        return null;
      case r'$resolvePasteFileData':
        return await target.$resolvePasteFileData(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'requestId'),
          a.arg(2, decodeString, 'dataId'),
        );
      case r'$resolveDocumentOnDropFileData':
        return await target.$resolveDocumentOnDropFileData(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'requestId'),
          a.arg(2, decodeString, 'dataId'),
        );
      case r'$setLanguageConfiguration':
        await target.$setLanguageConfiguration(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'languageId'),
          a.arg(2, decodeMap, 'configuration'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadLanguageFeatures.$method');
    }
  }
}

// --- MainThreadLanguages -------------------------------------------------------

/// `MainThreadLanguagesShape` (`MainThreadLanguages`).
abstract interface class MainThreadLanguagesShape {
  /// `$changeLanguage(resource: UriComponents, languageId: string): Promise<void>`
  FutureOr<void> $changeLanguage(VsUri resource, String languageId);

  /// `$tokensAtPosition(resource: UriComponents, position: IPosition): Promise<undefined | { type: StandardTokenType; range: IRange }>`
  Future<Map<String, Object?>?> $tokensAtPosition(
    VsUri resource,
    Map<String, Object?> position,
  );

  /// `$computeFullSyntaxHighlighting(source: string, languageId: string): Promise<ISyntaxHighlightingResultDto>`
  Future<Map<String, Object?>> $computeFullSyntaxHighlighting(
    String source,
    String languageId,
  );

  /// `$setLanguageStatus(handle: number, status: ILanguageStatus): void`
  FutureOr<void> $setLanguageStatus(num handle, Map<String, Object?> status);

  /// `$removeLanguageStatus(handle: number): void`
  FutureOr<void> $removeLanguageStatus(num handle);
}

/// [MainThreadLanguagesShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLanguagesUnsupported implements MainThreadLanguagesShape {
  const MainThreadLanguagesUnsupported();

  @override
  FutureOr<void> $changeLanguage(VsUri resource, String languageId) =>
      _unsupported('MainThreadLanguages', r'$changeLanguage');

  @override
  Future<Map<String, Object?>?> $tokensAtPosition(
    VsUri resource,
    Map<String, Object?> position,
  ) => _unsupported('MainThreadLanguages', r'$tokensAtPosition');

  @override
  Future<Map<String, Object?>> $computeFullSyntaxHighlighting(
    String source,
    String languageId,
  ) => _unsupported('MainThreadLanguages', r'$computeFullSyntaxHighlighting');

  @override
  FutureOr<void> $setLanguageStatus(num handle, Map<String, Object?> status) =>
      _unsupported('MainThreadLanguages', r'$setLanguageStatus');

  @override
  FutureOr<void> $removeLanguageStatus(num handle) =>
      _unsupported('MainThreadLanguages', r'$removeLanguageStatus');
}

/// Decodes requests to [MainContext.mainThreadLanguages] and calls [target].
final class MainThreadLanguagesActor implements RpcActor {
  MainThreadLanguagesActor(this.target);

  static const identifier = MainContext.mainThreadLanguages;

  final MainThreadLanguagesShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLanguages.$method', args);
    switch (method) {
      case r'$changeLanguage':
        await target.$changeLanguage(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeString, 'languageId'),
        );
        return null;
      case r'$tokensAtPosition':
        return await target.$tokensAtPosition(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeMap, 'position'),
        );
      case r'$computeFullSyntaxHighlighting':
        return await target.$computeFullSyntaxHighlighting(
          a.arg(0, decodeString, 'source'),
          a.arg(1, decodeString, 'languageId'),
        );
      case r'$setLanguageStatus':
        await target.$setLanguageStatus(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'status'),
        );
        return null;
      case r'$removeLanguageStatus':
        await target.$removeLanguageStatus(a.arg(0, decodeNum, 'handle'));
        return null;
      default:
        throw RpcUnsupported('MainThreadLanguages.$method');
    }
  }
}

// --- MainThreadLogger ----------------------------------------------------------

/// `MainThreadLoggerShape` (`MainThreadLogger`).
abstract interface class MainThreadLoggerShape {
  /// `$log(file: UriComponents, messages: [LogLevel, string][]): void`
  FutureOr<void> $log(VsUri file, List<List<Object?>> messages);

  /// `$flush(file: UriComponents): void`
  FutureOr<void> $flush(VsUri file);

  /// `$createLogger(file: UriComponents, options?: ILoggerOptions): Promise<void>`
  FutureOr<void> $createLogger(VsUri file, Map<String, Object?>? options);

  /// `$registerLogger(logger: UriDto<ILoggerResource>): Promise<void>`
  FutureOr<void> $registerLogger(Map<String, Object?> logger);

  /// `$deregisterLogger(resource: UriComponents): Promise<void>`
  FutureOr<void> $deregisterLogger(VsUri resource);

  /// `$setVisibility(resource: UriComponents, visible: boolean): Promise<void>`
  FutureOr<void> $setVisibility(VsUri resource, bool visible);
}

/// [MainThreadLoggerShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLoggerUnsupported implements MainThreadLoggerShape {
  const MainThreadLoggerUnsupported();

  @override
  FutureOr<void> $log(VsUri file, List<List<Object?>> messages) =>
      _unsupported('MainThreadLogger', r'$log');

  @override
  FutureOr<void> $flush(VsUri file) =>
      _unsupported('MainThreadLogger', r'$flush');

  @override
  FutureOr<void> $createLogger(VsUri file, Map<String, Object?>? options) =>
      _unsupported('MainThreadLogger', r'$createLogger');

  @override
  FutureOr<void> $registerLogger(Map<String, Object?> logger) =>
      _unsupported('MainThreadLogger', r'$registerLogger');

  @override
  FutureOr<void> $deregisterLogger(VsUri resource) =>
      _unsupported('MainThreadLogger', r'$deregisterLogger');

  @override
  FutureOr<void> $setVisibility(VsUri resource, bool visible) =>
      _unsupported('MainThreadLogger', r'$setVisibility');
}

/// Decodes requests to [MainContext.mainThreadLogger] and calls [target].
final class MainThreadLoggerActor implements RpcActor {
  MainThreadLoggerActor(this.target);

  static const identifier = MainContext.mainThreadLogger;

  final MainThreadLoggerShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLogger.$method', args);
    switch (method) {
      case r'$log':
        await target.$log(
          a.arg(0, decodeUri, 'file'),
          a.arg(1, decodeListOf(decodeListOf(decodeObject)), 'messages'),
        );
        return null;
      case r'$flush':
        await target.$flush(a.arg(0, decodeUri, 'file'));
        return null;
      case r'$createLogger':
        await target.$createLogger(
          a.arg(0, decodeUri, 'file'),
          a.arg(1, decodeNullable(decodeMap), 'options'),
        );
        return null;
      case r'$registerLogger':
        await target.$registerLogger(a.arg(0, decodeMap, 'logger'));
        return null;
      case r'$deregisterLogger':
        await target.$deregisterLogger(a.arg(0, decodeUri, 'resource'));
        return null;
      case r'$setVisibility':
        await target.$setVisibility(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeBool, 'visible'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadLogger.$method');
    }
  }
}

// --- MainThreadMessageService --------------------------------------------------

/// `MainThreadMessageServiceShape` (`MainThreadMessageService`).
abstract interface class MainThreadMessageServiceShape {
  /// `$showMessage(severity: Severity, message: string, options: MainThreadMessageOptions, commands: { title: string; isCloseAffordance: boolean; handle: number }[]): Promise<number | undefined>`
  Future<num?> $showMessage(
    int severity,
    String message,
    Map<String, Object?> options,
    List<Map<String, Object?>> commands,
  );
}

/// [MainThreadMessageServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadMessageServiceUnsupported
    implements MainThreadMessageServiceShape {
  const MainThreadMessageServiceUnsupported();

  @override
  Future<num?> $showMessage(
    int severity,
    String message,
    Map<String, Object?> options,
    List<Map<String, Object?>> commands,
  ) => _unsupported('MainThreadMessageService', r'$showMessage');
}

/// Decodes requests to [MainContext.mainThreadMessageService] and calls [target].
final class MainThreadMessageServiceActor implements RpcActor {
  MainThreadMessageServiceActor(this.target);

  static const identifier = MainContext.mainThreadMessageService;

  final MainThreadMessageServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadMessageService.$method', args);
    switch (method) {
      case r'$showMessage':
        return await target.$showMessage(
          a.arg(0, decodeInt, 'severity'),
          a.arg(1, decodeString, 'message'),
          a.arg(2, decodeMap, 'options'),
          a.arg(3, decodeListOf(decodeMap), 'commands'),
        );
      default:
        throw RpcUnsupported('MainThreadMessageService.$method');
    }
  }
}

// --- MainThreadOutputService ---------------------------------------------------

/// `MainThreadOutputServiceShape` (`MainThreadOutputService`).
abstract interface class MainThreadOutputServiceShape {
  /// `$register(label: string, file: UriComponents, languageId: string | undefined, extensionId: string): Promise<string>`
  Future<String> $register(
    String label,
    VsUri file,
    String? languageId,
    String extensionId,
  );

  /// `$update(channelId: string, mode: OutputChannelUpdateMode, till?: number): Promise<void>`
  FutureOr<void> $update(String channelId, int mode, num? till);

  /// `$reveal(channelId: string, preserveFocus: boolean): Promise<void>`
  FutureOr<void> $reveal(String channelId, bool preserveFocus);

  /// `$close(channelId: string): Promise<void>`
  FutureOr<void> $close(String channelId);

  /// `$dispose(channelId: string): Promise<void>`
  FutureOr<void> $dispose(String channelId);
}

/// [MainThreadOutputServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadOutputServiceUnsupported
    implements MainThreadOutputServiceShape {
  const MainThreadOutputServiceUnsupported();

  @override
  Future<String> $register(
    String label,
    VsUri file,
    String? languageId,
    String extensionId,
  ) => _unsupported('MainThreadOutputService', r'$register');

  @override
  FutureOr<void> $update(String channelId, int mode, num? till) =>
      _unsupported('MainThreadOutputService', r'$update');

  @override
  FutureOr<void> $reveal(String channelId, bool preserveFocus) =>
      _unsupported('MainThreadOutputService', r'$reveal');

  @override
  FutureOr<void> $close(String channelId) =>
      _unsupported('MainThreadOutputService', r'$close');

  @override
  FutureOr<void> $dispose(String channelId) =>
      _unsupported('MainThreadOutputService', r'$dispose');
}

/// Decodes requests to [MainContext.mainThreadOutputService] and calls [target].
final class MainThreadOutputServiceActor implements RpcActor {
  MainThreadOutputServiceActor(this.target);

  static const identifier = MainContext.mainThreadOutputService;

  final MainThreadOutputServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadOutputService.$method', args);
    switch (method) {
      case r'$register':
        return await target.$register(
          a.arg(0, decodeString, 'label'),
          a.arg(1, decodeUri, 'file'),
          a.arg(2, decodeNullable(decodeString), 'languageId'),
          a.arg(3, decodeString, 'extensionId'),
        );
      case r'$update':
        await target.$update(
          a.arg(0, decodeString, 'channelId'),
          a.arg(1, decodeInt, 'mode'),
          a.arg(2, decodeNullable(decodeNum), 'till'),
        );
        return null;
      case r'$reveal':
        await target.$reveal(
          a.arg(0, decodeString, 'channelId'),
          a.arg(1, decodeBool, 'preserveFocus'),
        );
        return null;
      case r'$close':
        await target.$close(a.arg(0, decodeString, 'channelId'));
        return null;
      case r'$dispose':
        await target.$dispose(a.arg(0, decodeString, 'channelId'));
        return null;
      default:
        throw RpcUnsupported('MainThreadOutputService.$method');
    }
  }
}

// --- MainThreadProgress --------------------------------------------------------

/// `MainThreadProgressShape` (`MainThreadProgress`).
abstract interface class MainThreadProgressShape {
  /// `$startProgress(handle: number, options: IProgressOptions, extensionId?: string): Promise<void>`
  FutureOr<void> $startProgress(
    num handle,
    Map<String, Object?> options,
    String? extensionId,
  );

  /// `$progressReport(handle: number, message: IProgressStep): void`
  FutureOr<void> $progressReport(num handle, Map<String, Object?> message);

  /// `$progressEnd(handle: number): void`
  FutureOr<void> $progressEnd(num handle);
}

/// [MainThreadProgressShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadProgressUnsupported implements MainThreadProgressShape {
  const MainThreadProgressUnsupported();

  @override
  FutureOr<void> $startProgress(
    num handle,
    Map<String, Object?> options,
    String? extensionId,
  ) => _unsupported('MainThreadProgress', r'$startProgress');

  @override
  FutureOr<void> $progressReport(num handle, Map<String, Object?> message) =>
      _unsupported('MainThreadProgress', r'$progressReport');

  @override
  FutureOr<void> $progressEnd(num handle) =>
      _unsupported('MainThreadProgress', r'$progressEnd');
}

/// Decodes requests to [MainContext.mainThreadProgress] and calls [target].
final class MainThreadProgressActor implements RpcActor {
  MainThreadProgressActor(this.target);

  static const identifier = MainContext.mainThreadProgress;

  final MainThreadProgressShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadProgress.$method', args);
    switch (method) {
      case r'$startProgress':
        await target.$startProgress(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'options'),
          a.arg(2, decodeNullable(decodeString), 'extensionId'),
        );
        return null;
      case r'$progressReport':
        await target.$progressReport(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'message'),
        );
        return null;
      case r'$progressEnd':
        await target.$progressEnd(a.arg(0, decodeNum, 'handle'));
        return null;
      default:
        throw RpcUnsupported('MainThreadProgress.$method');
    }
  }
}

// --- MainThreadQuickDiff -------------------------------------------------------

/// `MainThreadQuickDiffShape` (`MainThreadQuickDiff`).
abstract interface class MainThreadQuickDiffShape {
  /// `$registerQuickDiffProvider(handle: number, selector: IDocumentFilterDto[], id: string, label: string, rootUri: UriComponents | undefined): Promise<void>`
  FutureOr<void> $registerQuickDiffProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String id,
    String label,
    VsUri? rootUri,
  );

  /// `$unregisterQuickDiffProvider(handle: number): Promise<void>`
  FutureOr<void> $unregisterQuickDiffProvider(num handle);

  /// `$createSourceControlDiffInformation(handle: number, uri: UriComponents): Promise<void>`
  FutureOr<void> $createSourceControlDiffInformation(num handle, VsUri uri);

  /// `$disposeSourceControlDiffInformation(handle: number): Promise<void>`
  FutureOr<void> $disposeSourceControlDiffInformation(num handle);
}

/// [MainThreadQuickDiffShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadQuickDiffUnsupported implements MainThreadQuickDiffShape {
  const MainThreadQuickDiffUnsupported();

  @override
  FutureOr<void> $registerQuickDiffProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String id,
    String label,
    VsUri? rootUri,
  ) => _unsupported('MainThreadQuickDiff', r'$registerQuickDiffProvider');

  @override
  FutureOr<void> $unregisterQuickDiffProvider(num handle) =>
      _unsupported('MainThreadQuickDiff', r'$unregisterQuickDiffProvider');

  @override
  FutureOr<void> $createSourceControlDiffInformation(num handle, VsUri uri) =>
      _unsupported(
        'MainThreadQuickDiff',
        r'$createSourceControlDiffInformation',
      );

  @override
  FutureOr<void> $disposeSourceControlDiffInformation(num handle) =>
      _unsupported(
        'MainThreadQuickDiff',
        r'$disposeSourceControlDiffInformation',
      );
}

/// Decodes requests to [MainContext.mainThreadQuickDiff] and calls [target].
final class MainThreadQuickDiffActor implements RpcActor {
  MainThreadQuickDiffActor(this.target);

  static const identifier = MainContext.mainThreadQuickDiff;

  final MainThreadQuickDiffShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadQuickDiff.$method', args);
    switch (method) {
      case r'$registerQuickDiffProvider':
        await target.$registerQuickDiffProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeString, 'id'),
          a.arg(3, decodeString, 'label'),
          a.arg(4, decodeNullable(decodeUri), 'rootUri'),
        );
        return null;
      case r'$unregisterQuickDiffProvider':
        await target.$unregisterQuickDiffProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$createSourceControlDiffInformation':
        await target.$createSourceControlDiffInformation(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'uri'),
        );
        return null;
      case r'$disposeSourceControlDiffInformation':
        await target.$disposeSourceControlDiffInformation(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadQuickDiff.$method');
    }
  }
}

// --- MainThreadAgentEditorComments ---------------------------------------------

/// `MainThreadAgentEditorCommentsShape` (`MainThreadAgentEditorComments`).
abstract interface class MainThreadAgentEditorCommentsShape {
  /// `$createAgentEditorComments(handle: number, uri: UriComponents): Promise<void>`
  FutureOr<void> $createAgentEditorComments(num handle, VsUri uri);

  /// `$addComment(handle: number, range: IRange, body: string): Promise<void>`
  FutureOr<void> $addComment(
    num handle,
    Map<String, Object?> range,
    String body,
  );

  /// `$deleteComment(handle: number, id: string): Promise<void>`
  FutureOr<void> $deleteComment(num handle, String id);

  /// `$disposeAgentEditorComments(handle: number): Promise<void>`
  FutureOr<void> $disposeAgentEditorComments(num handle);
}

/// [MainThreadAgentEditorCommentsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadAgentEditorCommentsUnsupported
    implements MainThreadAgentEditorCommentsShape {
  const MainThreadAgentEditorCommentsUnsupported();

  @override
  FutureOr<void> $createAgentEditorComments(num handle, VsUri uri) =>
      _unsupported(
        'MainThreadAgentEditorComments',
        r'$createAgentEditorComments',
      );

  @override
  FutureOr<void> $addComment(
    num handle,
    Map<String, Object?> range,
    String body,
  ) => _unsupported('MainThreadAgentEditorComments', r'$addComment');

  @override
  FutureOr<void> $deleteComment(num handle, String id) =>
      _unsupported('MainThreadAgentEditorComments', r'$deleteComment');

  @override
  FutureOr<void> $disposeAgentEditorComments(num handle) => _unsupported(
    'MainThreadAgentEditorComments',
    r'$disposeAgentEditorComments',
  );
}

/// Decodes requests to [MainContext.mainThreadAgentEditorComments] and calls [target].
final class MainThreadAgentEditorCommentsActor implements RpcActor {
  MainThreadAgentEditorCommentsActor(this.target);

  static const identifier = MainContext.mainThreadAgentEditorComments;

  final MainThreadAgentEditorCommentsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadAgentEditorComments.$method', args);
    switch (method) {
      case r'$createAgentEditorComments':
        await target.$createAgentEditorComments(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'uri'),
        );
        return null;
      case r'$addComment':
        await target.$addComment(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'range'),
          a.arg(2, decodeString, 'body'),
        );
        return null;
      case r'$deleteComment':
        await target.$deleteComment(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
        );
        return null;
      case r'$disposeAgentEditorComments':
        await target.$disposeAgentEditorComments(a.arg(0, decodeNum, 'handle'));
        return null;
      default:
        throw RpcUnsupported('MainThreadAgentEditorComments.$method');
    }
  }
}

// --- MainThreadDocumentDiff ----------------------------------------------------

/// `MainThreadDocumentDiffShape` (`MainThreadDocumentDiff`).
abstract interface class MainThreadDocumentDiffShape {
  /// `$computeDocumentDiff(originalUri: UriComponents, modifiedUri: UriComponents, ignoreTrimWhitespace: boolean, maxComputationTimeMs: number, computeMoves: boolean): Promise<IDocumentDiffResultDto | null>`
  Future<Map<String, Object?>?> $computeDocumentDiff(
    VsUri originalUri,
    VsUri modifiedUri,
    bool ignoreTrimWhitespace,
    num maxComputationTimeMs,
    bool computeMoves,
  );
}

/// [MainThreadDocumentDiffShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDocumentDiffUnsupported
    implements MainThreadDocumentDiffShape {
  const MainThreadDocumentDiffUnsupported();

  @override
  Future<Map<String, Object?>?> $computeDocumentDiff(
    VsUri originalUri,
    VsUri modifiedUri,
    bool ignoreTrimWhitespace,
    num maxComputationTimeMs,
    bool computeMoves,
  ) => _unsupported('MainThreadDocumentDiff', r'$computeDocumentDiff');
}

/// Decodes requests to [MainContext.mainThreadDocumentDiff] and calls [target].
final class MainThreadDocumentDiffActor implements RpcActor {
  MainThreadDocumentDiffActor(this.target);

  static const identifier = MainContext.mainThreadDocumentDiff;

  final MainThreadDocumentDiffShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDocumentDiff.$method', args);
    switch (method) {
      case r'$computeDocumentDiff':
        return await target.$computeDocumentDiff(
          a.arg(0, decodeUri, 'originalUri'),
          a.arg(1, decodeUri, 'modifiedUri'),
          a.arg(2, decodeBool, 'ignoreTrimWhitespace'),
          a.arg(3, decodeNum, 'maxComputationTimeMs'),
          a.arg(4, decodeBool, 'computeMoves'),
        );
      default:
        throw RpcUnsupported('MainThreadDocumentDiff.$method');
    }
  }
}

// --- MainThreadQuickOpen -------------------------------------------------------

/// `MainThreadQuickOpenShape` (`MainThreadQuickOpen`).
abstract interface class MainThreadQuickOpenShape {
  /// `$show(instance: number, options: quickInput.IPickOptions<TransferQuickPickItem>, token: CancellationToken): Promise<number | number[] | undefined>`
  Future<Object?> $show(
    num instance,
    Map<String, Object?> options,
    CancellationToken token,
  );

  /// `$setItems(instance: number, items: TransferQuickPickItemOrSeparator[]): Promise<void>`
  FutureOr<void> $setItems(num instance, List<Map<String, Object?>> items);

  /// `$setError(instance: number, error: Error): Promise<void>`
  FutureOr<void> $setError(num instance, Map<String, Object?> error);

  /// `$input(options: IInputBoxOptions | undefined, validateInput: boolean, token: CancellationToken): Promise<string | undefined>`
  Future<String?> $input(
    Map<String, Object?>? options,
    bool validateInput,
    CancellationToken token,
  );

  /// `$createOrUpdate(params: TransferQuickInput): Promise<void>`
  FutureOr<void> $createOrUpdate(Map<String, Object?> params);

  /// `$dispose(id: number): Promise<void>`
  FutureOr<void> $dispose(num id);
}

/// [MainThreadQuickOpenShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadQuickOpenUnsupported implements MainThreadQuickOpenShape {
  const MainThreadQuickOpenUnsupported();

  @override
  Future<Object?> $show(
    num instance,
    Map<String, Object?> options,
    CancellationToken token,
  ) => _unsupported('MainThreadQuickOpen', r'$show');

  @override
  FutureOr<void> $setItems(num instance, List<Map<String, Object?>> items) =>
      _unsupported('MainThreadQuickOpen', r'$setItems');

  @override
  FutureOr<void> $setError(num instance, Map<String, Object?> error) =>
      _unsupported('MainThreadQuickOpen', r'$setError');

  @override
  Future<String?> $input(
    Map<String, Object?>? options,
    bool validateInput,
    CancellationToken token,
  ) => _unsupported('MainThreadQuickOpen', r'$input');

  @override
  FutureOr<void> $createOrUpdate(Map<String, Object?> params) =>
      _unsupported('MainThreadQuickOpen', r'$createOrUpdate');

  @override
  FutureOr<void> $dispose(num id) =>
      _unsupported('MainThreadQuickOpen', r'$dispose');
}

/// Decodes requests to [MainContext.mainThreadQuickOpen] and calls [target].
final class MainThreadQuickOpenActor implements RpcActor {
  MainThreadQuickOpenActor(this.target);

  static const identifier = MainContext.mainThreadQuickOpen;

  final MainThreadQuickOpenShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadQuickOpen.$method', args);
    switch (method) {
      case r'$show':
        return await target.$show(
          a.arg(0, decodeNum, 'instance'),
          a.arg(1, decodeMap, 'options'),
          a.token,
        );
      case r'$setItems':
        await target.$setItems(
          a.arg(0, decodeNum, 'instance'),
          a.arg(1, decodeListOf(decodeMap), 'items'),
        );
        return null;
      case r'$setError':
        await target.$setError(
          a.arg(0, decodeNum, 'instance'),
          a.arg(1, decodeMap, 'error'),
        );
        return null;
      case r'$input':
        return await target.$input(
          a.arg(0, decodeNullable(decodeMap), 'options'),
          a.arg(1, decodeBool, 'validateInput'),
          a.token,
        );
      case r'$createOrUpdate':
        await target.$createOrUpdate(a.arg(0, decodeMap, 'params'));
        return null;
      case r'$dispose':
        await target.$dispose(a.arg(0, decodeNum, 'id'));
        return null;
      default:
        throw RpcUnsupported('MainThreadQuickOpen.$method');
    }
  }
}

// --- MainThreadStatusBar -------------------------------------------------------

/// `MainThreadStatusBarShape` (`MainThreadStatusBar`).
abstract interface class MainThreadStatusBarShape {
  /// `$setEntry(id: string, statusId: string, extensionId: string | undefined, statusName: string, text: string, tooltip: IMarkdownString | string | undefined, hasTooltipProvider: boolean, command: ICommandDto | undefined, color: string | ThemeColor | undefined, backgroundColor: string | ThemeColor | undefined, alignLeft: boolean, priority: number | undefined, accessibilityInformation: IAccessibilityInformation | undefined): void`
  FutureOr<void> $setEntry(
    String id,
    String statusId,
    String? extensionId,
    String statusName,
    String text,
    Object? tooltip,
    bool hasTooltipProvider,
    Map<String, Object?>? command,
    Object? color,
    Object? backgroundColor,
    bool alignLeft,
    num? priority,
    Map<String, Object?>? accessibilityInformation,
  );

  /// `$disposeEntry(id: string): void`
  FutureOr<void> $disposeEntry(String id);
}

/// [MainThreadStatusBarShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadStatusBarUnsupported implements MainThreadStatusBarShape {
  const MainThreadStatusBarUnsupported();

  @override
  FutureOr<void> $setEntry(
    String id,
    String statusId,
    String? extensionId,
    String statusName,
    String text,
    Object? tooltip,
    bool hasTooltipProvider,
    Map<String, Object?>? command,
    Object? color,
    Object? backgroundColor,
    bool alignLeft,
    num? priority,
    Map<String, Object?>? accessibilityInformation,
  ) => _unsupported('MainThreadStatusBar', r'$setEntry');

  @override
  FutureOr<void> $disposeEntry(String id) =>
      _unsupported('MainThreadStatusBar', r'$disposeEntry');
}

/// Decodes requests to [MainContext.mainThreadStatusBar] and calls [target].
final class MainThreadStatusBarActor implements RpcActor {
  MainThreadStatusBarActor(this.target);

  static const identifier = MainContext.mainThreadStatusBar;

  final MainThreadStatusBarShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadStatusBar.$method', args);
    switch (method) {
      case r'$setEntry':
        await target.$setEntry(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'statusId'),
          a.arg(2, decodeNullable(decodeString), 'extensionId'),
          a.arg(3, decodeString, 'statusName'),
          a.arg(4, decodeString, 'text'),
          a.arg(5, decodeObject, 'tooltip'),
          a.arg(6, decodeBool, 'hasTooltipProvider'),
          a.arg(7, decodeNullable(decodeMap), 'command'),
          a.arg(8, decodeObject, 'color'),
          a.arg(9, decodeObject, 'backgroundColor'),
          a.arg(10, decodeBool, 'alignLeft'),
          a.arg(11, decodeNullable(decodeNum), 'priority'),
          a.arg(12, decodeNullable(decodeMap), 'accessibilityInformation'),
        );
        return null;
      case r'$disposeEntry':
        await target.$disposeEntry(a.arg(0, decodeString, 'id'));
        return null;
      default:
        throw RpcUnsupported('MainThreadStatusBar.$method');
    }
  }
}

// --- MainThreadSecretState -----------------------------------------------------

/// `MainThreadSecretStateShape` (`MainThreadSecretState`).
abstract interface class MainThreadSecretStateShape {
  /// `$getPassword(extensionId: string, key: string): Promise<string | undefined>`
  Future<String?> $getPassword(String extensionId, String key);

  /// `$setPassword(extensionId: string, key: string, value: string): Promise<void>`
  FutureOr<void> $setPassword(String extensionId, String key, String value);

  /// `$deletePassword(extensionId: string, key: string): Promise<void>`
  FutureOr<void> $deletePassword(String extensionId, String key);

  /// `$getKeys(extensionId: string): Promise<string[]>`
  Future<List<String>> $getKeys(String extensionId);
}

/// [MainThreadSecretStateShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadSecretStateUnsupported
    implements MainThreadSecretStateShape {
  const MainThreadSecretStateUnsupported();

  @override
  Future<String?> $getPassword(String extensionId, String key) =>
      _unsupported('MainThreadSecretState', r'$getPassword');

  @override
  FutureOr<void> $setPassword(String extensionId, String key, String value) =>
      _unsupported('MainThreadSecretState', r'$setPassword');

  @override
  FutureOr<void> $deletePassword(String extensionId, String key) =>
      _unsupported('MainThreadSecretState', r'$deletePassword');

  @override
  Future<List<String>> $getKeys(String extensionId) =>
      _unsupported('MainThreadSecretState', r'$getKeys');
}

/// Decodes requests to [MainContext.mainThreadSecretState] and calls [target].
final class MainThreadSecretStateActor implements RpcActor {
  MainThreadSecretStateActor(this.target);

  static const identifier = MainContext.mainThreadSecretState;

  final MainThreadSecretStateShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadSecretState.$method', args);
    switch (method) {
      case r'$getPassword':
        return await target.$getPassword(
          a.arg(0, decodeString, 'extensionId'),
          a.arg(1, decodeString, 'key'),
        );
      case r'$setPassword':
        await target.$setPassword(
          a.arg(0, decodeString, 'extensionId'),
          a.arg(1, decodeString, 'key'),
          a.arg(2, decodeString, 'value'),
        );
        return null;
      case r'$deletePassword':
        await target.$deletePassword(
          a.arg(0, decodeString, 'extensionId'),
          a.arg(1, decodeString, 'key'),
        );
        return null;
      case r'$getKeys':
        return await target.$getKeys(a.arg(0, decodeString, 'extensionId'));
      default:
        throw RpcUnsupported('MainThreadSecretState.$method');
    }
  }
}

// --- MainThreadStorage ---------------------------------------------------------

/// `MainThreadStorageShape` (`MainThreadStorage`).
abstract interface class MainThreadStorageShape {
  /// `$initializeExtensionStorage(shared: boolean, extensionId: string): Promise<string | undefined>`
  Future<String?> $initializeExtensionStorage(bool shared, String extensionId);

  /// `$setValue(shared: boolean, extensionId: string, value: object): Promise<void>`
  FutureOr<void> $setValue(
    bool shared,
    String extensionId,
    Map<String, Object?> value,
  );

  /// `$registerExtensionStorageKeysToSync(extension: IExtensionIdWithVersion, keys: string[]): void`
  FutureOr<void> $registerExtensionStorageKeysToSync(
    Map<String, Object?> extension,
    List<String> keys,
  );
}

/// [MainThreadStorageShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadStorageUnsupported implements MainThreadStorageShape {
  const MainThreadStorageUnsupported();

  @override
  Future<String?> $initializeExtensionStorage(
    bool shared,
    String extensionId,
  ) => _unsupported('MainThreadStorage', r'$initializeExtensionStorage');

  @override
  FutureOr<void> $setValue(
    bool shared,
    String extensionId,
    Map<String, Object?> value,
  ) => _unsupported('MainThreadStorage', r'$setValue');

  @override
  FutureOr<void> $registerExtensionStorageKeysToSync(
    Map<String, Object?> extension,
    List<String> keys,
  ) =>
      _unsupported('MainThreadStorage', r'$registerExtensionStorageKeysToSync');
}

/// Decodes requests to [MainContext.mainThreadStorage] and calls [target].
final class MainThreadStorageActor implements RpcActor {
  MainThreadStorageActor(this.target);

  static const identifier = MainContext.mainThreadStorage;

  final MainThreadStorageShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadStorage.$method', args);
    switch (method) {
      case r'$initializeExtensionStorage':
        return await target.$initializeExtensionStorage(
          a.arg(0, decodeBool, 'shared'),
          a.arg(1, decodeString, 'extensionId'),
        );
      case r'$setValue':
        await target.$setValue(
          a.arg(0, decodeBool, 'shared'),
          a.arg(1, decodeString, 'extensionId'),
          a.arg(2, decodeMap, 'value'),
        );
        return null;
      case r'$registerExtensionStorageKeysToSync':
        await target.$registerExtensionStorageKeysToSync(
          a.arg(0, decodeMap, 'extension'),
          a.arg(1, decodeListOf(decodeString), 'keys'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadStorage.$method');
    }
  }
}

// --- MainThreadSpeech ----------------------------------------------------------

/// `MainThreadSpeechShape` (`MainThreadSpeechProvider`).
abstract interface class MainThreadSpeechShape {
  /// `$registerProvider(handle: number, identifier: string, metadata: ISpeechProviderMetadata): void`
  FutureOr<void> $registerProvider(
    num handle,
    String identifier,
    Map<String, Object?> metadata,
  );

  /// `$unregisterProvider(handle: number): void`
  FutureOr<void> $unregisterProvider(num handle);

  /// `$emitSpeechToTextEvent(session: number, event: ISpeechToTextEvent): void`
  FutureOr<void> $emitSpeechToTextEvent(
    num session,
    Map<String, Object?> event,
  );

  /// `$emitTextToSpeechEvent(session: number, event: ITextToSpeechEvent): void`
  FutureOr<void> $emitTextToSpeechEvent(
    num session,
    Map<String, Object?> event,
  );

  /// `$emitKeywordRecognitionEvent(session: number, event: IKeywordRecognitionEvent): void`
  FutureOr<void> $emitKeywordRecognitionEvent(
    num session,
    Map<String, Object?> event,
  );
}

/// [MainThreadSpeechShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadSpeechUnsupported implements MainThreadSpeechShape {
  const MainThreadSpeechUnsupported();

  @override
  FutureOr<void> $registerProvider(
    num handle,
    String identifier,
    Map<String, Object?> metadata,
  ) => _unsupported('MainThreadSpeech', r'$registerProvider');

  @override
  FutureOr<void> $unregisterProvider(num handle) =>
      _unsupported('MainThreadSpeech', r'$unregisterProvider');

  @override
  FutureOr<void> $emitSpeechToTextEvent(
    num session,
    Map<String, Object?> event,
  ) => _unsupported('MainThreadSpeech', r'$emitSpeechToTextEvent');

  @override
  FutureOr<void> $emitTextToSpeechEvent(
    num session,
    Map<String, Object?> event,
  ) => _unsupported('MainThreadSpeech', r'$emitTextToSpeechEvent');

  @override
  FutureOr<void> $emitKeywordRecognitionEvent(
    num session,
    Map<String, Object?> event,
  ) => _unsupported('MainThreadSpeech', r'$emitKeywordRecognitionEvent');
}

/// Decodes requests to [MainContext.mainThreadSpeech] and calls [target].
final class MainThreadSpeechActor implements RpcActor {
  MainThreadSpeechActor(this.target);

  static const identifier = MainContext.mainThreadSpeech;

  final MainThreadSpeechShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadSpeech.$method', args);
    switch (method) {
      case r'$registerProvider':
        await target.$registerProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'identifier'),
          a.arg(2, decodeMap, 'metadata'),
        );
        return null;
      case r'$unregisterProvider':
        await target.$unregisterProvider(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$emitSpeechToTextEvent':
        await target.$emitSpeechToTextEvent(
          a.arg(0, decodeNum, 'session'),
          a.arg(1, decodeMap, 'event'),
        );
        return null;
      case r'$emitTextToSpeechEvent':
        await target.$emitTextToSpeechEvent(
          a.arg(0, decodeNum, 'session'),
          a.arg(1, decodeMap, 'event'),
        );
        return null;
      case r'$emitKeywordRecognitionEvent':
        await target.$emitKeywordRecognitionEvent(
          a.arg(0, decodeNum, 'session'),
          a.arg(1, decodeMap, 'event'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadSpeech.$method');
    }
  }
}

// --- MainThreadTelemetry -------------------------------------------------------

/// `MainThreadTelemetryShape` (`MainThreadTelemetry`).
abstract interface class MainThreadTelemetryShape {
  /// `$publicLog(eventName: string, data?: any): void`
  FutureOr<void> $publicLog(String eventName, Object? data);

  /// `$publicLog2(eventName: string, data?: StrictPropertyCheck<T, E>): void`
  FutureOr<void> $publicLog2(String eventName, Object? data);
}

/// [MainThreadTelemetryShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTelemetryUnsupported implements MainThreadTelemetryShape {
  const MainThreadTelemetryUnsupported();

  @override
  FutureOr<void> $publicLog(String eventName, Object? data) =>
      _unsupported('MainThreadTelemetry', r'$publicLog');

  @override
  FutureOr<void> $publicLog2(String eventName, Object? data) =>
      _unsupported('MainThreadTelemetry', r'$publicLog2');
}

/// Decodes requests to [MainContext.mainThreadTelemetry] and calls [target].
final class MainThreadTelemetryActor implements RpcActor {
  MainThreadTelemetryActor(this.target);

  static const identifier = MainContext.mainThreadTelemetry;

  final MainThreadTelemetryShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTelemetry.$method', args);
    switch (method) {
      case r'$publicLog':
        await target.$publicLog(
          a.arg(0, decodeString, 'eventName'),
          a.arg(1, decodeObject, 'data'),
        );
        return null;
      case r'$publicLog2':
        await target.$publicLog2(
          a.arg(0, decodeString, 'eventName'),
          a.arg(1, decodeObject, 'data'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTelemetry.$method');
    }
  }
}

// --- MainThreadMeteredConnection -----------------------------------------------

/// `MainThreadMeteredConnectionShape` (`MainThreadMeteredConnection`).
abstract interface class MainThreadMeteredConnectionShape {}

/// [MainThreadMeteredConnectionShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadMeteredConnectionUnsupported
    implements MainThreadMeteredConnectionShape {
  const MainThreadMeteredConnectionUnsupported();
}

/// Decodes requests to [MainContext.mainThreadMeteredConnection] and calls [target].
final class MainThreadMeteredConnectionActor implements RpcActor {
  MainThreadMeteredConnectionActor(this.target);

  static const identifier = MainContext.mainThreadMeteredConnection;

  final MainThreadMeteredConnectionShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    throw RpcUnsupported('MainThreadMeteredConnection.$method');
  }
}

// --- MainThreadTerminalService -------------------------------------------------

/// `MainThreadTerminalServiceShape` (`MainThreadTerminalService`).
abstract interface class MainThreadTerminalServiceShape {
  /// `$createTerminal(extHostTerminalId: string, config: TerminalLaunchConfig): Promise<void>`
  FutureOr<void> $createTerminal(
    String extHostTerminalId,
    Map<String, Object?> config,
  );

  /// `$dispose(id: ExtHostTerminalIdentifier): void`
  FutureOr<void> $dispose(Object? id);

  /// `$hide(id: ExtHostTerminalIdentifier): void`
  FutureOr<void> $hide(Object? id);

  /// `$sendText(id: ExtHostTerminalIdentifier, text: string, shouldExecute: boolean): void`
  FutureOr<void> $sendText(Object? id, String text, bool shouldExecute);

  /// `$show(id: ExtHostTerminalIdentifier, preserveFocus: boolean): void`
  FutureOr<void> $show(Object? id, bool preserveFocus);

  /// `$registerProcessSupport(isSupported: boolean): void`
  FutureOr<void> $registerProcessSupport(bool isSupported);

  /// `$registerProfileProvider(id: string, extensionIdentifier: string): void`
  FutureOr<void> $registerProfileProvider(
    String id,
    String extensionIdentifier,
  );

  /// `$unregisterProfileProvider(id: string): void`
  FutureOr<void> $unregisterProfileProvider(String id);

  /// `$registerCompletionProvider(id: string, extensionIdentifier: string, ...triggerCharacters: string[]): void`
  FutureOr<void> $registerCompletionProvider(
    String id,
    String extensionIdentifier,
    List<String> triggerCharacters,
  );

  /// `$unregisterCompletionProvider(id: string): void`
  FutureOr<void> $unregisterCompletionProvider(String id);

  /// `$registerQuickFixProvider(id: string, extensionIdentifier: string): void`
  FutureOr<void> $registerQuickFixProvider(
    String id,
    String extensionIdentifier,
  );

  /// `$unregisterQuickFixProvider(id: string): void`
  FutureOr<void> $unregisterQuickFixProvider(String id);

  /// `$setEnvironmentVariableCollection(extensionIdentifier: string, persistent: boolean, collection: ISerializableEnvironmentVariableCollection | undefined, descriptionMap: ISerializableEnvironmentDescriptionMap): void`
  FutureOr<void> $setEnvironmentVariableCollection(
    String extensionIdentifier,
    bool persistent,
    List<List<Object?>>? collection,
    List<List<Object?>> descriptionMap,
  );

  /// `$startSendingDataEvents(): void`
  FutureOr<void> $startSendingDataEvents();

  /// `$stopSendingDataEvents(): void`
  FutureOr<void> $stopSendingDataEvents();

  /// `$startSendingCommandEvents(): void`
  FutureOr<void> $startSendingCommandEvents();

  /// `$stopSendingCommandEvents(): void`
  FutureOr<void> $stopSendingCommandEvents();

  /// `$startLinkProvider(): void`
  FutureOr<void> $startLinkProvider();

  /// `$stopLinkProvider(): void`
  FutureOr<void> $stopLinkProvider();

  /// `$sendProcessData(terminalId: number, data: string): void`
  FutureOr<void> $sendProcessData(num terminalId, String data);

  /// `$sendProcessReady(terminalId: number, pid: number, cwd: string, windowsPty: IProcessReadyWindowsPty | undefined): void`
  FutureOr<void> $sendProcessReady(
    num terminalId,
    num pid,
    String cwd,
    Map<String, Object?>? windowsPty,
  );

  /// `$sendProcessProperty(terminalId: number, property: IProcessProperty<any>): void`
  FutureOr<void> $sendProcessProperty(
    num terminalId,
    Map<String, Object?> property,
  );

  /// `$sendProcessExit(terminalId: number, exitCode: number | undefined): void`
  FutureOr<void> $sendProcessExit(num terminalId, num? exitCode);
}

/// [MainThreadTerminalServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTerminalServiceUnsupported
    implements MainThreadTerminalServiceShape {
  const MainThreadTerminalServiceUnsupported();

  @override
  FutureOr<void> $createTerminal(
    String extHostTerminalId,
    Map<String, Object?> config,
  ) => _unsupported('MainThreadTerminalService', r'$createTerminal');

  @override
  FutureOr<void> $dispose(Object? id) =>
      _unsupported('MainThreadTerminalService', r'$dispose');

  @override
  FutureOr<void> $hide(Object? id) =>
      _unsupported('MainThreadTerminalService', r'$hide');

  @override
  FutureOr<void> $sendText(Object? id, String text, bool shouldExecute) =>
      _unsupported('MainThreadTerminalService', r'$sendText');

  @override
  FutureOr<void> $show(Object? id, bool preserveFocus) =>
      _unsupported('MainThreadTerminalService', r'$show');

  @override
  FutureOr<void> $registerProcessSupport(bool isSupported) =>
      _unsupported('MainThreadTerminalService', r'$registerProcessSupport');

  @override
  FutureOr<void> $registerProfileProvider(
    String id,
    String extensionIdentifier,
  ) => _unsupported('MainThreadTerminalService', r'$registerProfileProvider');

  @override
  FutureOr<void> $unregisterProfileProvider(String id) =>
      _unsupported('MainThreadTerminalService', r'$unregisterProfileProvider');

  @override
  FutureOr<void> $registerCompletionProvider(
    String id,
    String extensionIdentifier,
    List<String> triggerCharacters,
  ) =>
      _unsupported('MainThreadTerminalService', r'$registerCompletionProvider');

  @override
  FutureOr<void> $unregisterCompletionProvider(String id) => _unsupported(
    'MainThreadTerminalService',
    r'$unregisterCompletionProvider',
  );

  @override
  FutureOr<void> $registerQuickFixProvider(
    String id,
    String extensionIdentifier,
  ) => _unsupported('MainThreadTerminalService', r'$registerQuickFixProvider');

  @override
  FutureOr<void> $unregisterQuickFixProvider(String id) =>
      _unsupported('MainThreadTerminalService', r'$unregisterQuickFixProvider');

  @override
  FutureOr<void> $setEnvironmentVariableCollection(
    String extensionIdentifier,
    bool persistent,
    List<List<Object?>>? collection,
    List<List<Object?>> descriptionMap,
  ) => _unsupported(
    'MainThreadTerminalService',
    r'$setEnvironmentVariableCollection',
  );

  @override
  FutureOr<void> $startSendingDataEvents() =>
      _unsupported('MainThreadTerminalService', r'$startSendingDataEvents');

  @override
  FutureOr<void> $stopSendingDataEvents() =>
      _unsupported('MainThreadTerminalService', r'$stopSendingDataEvents');

  @override
  FutureOr<void> $startSendingCommandEvents() =>
      _unsupported('MainThreadTerminalService', r'$startSendingCommandEvents');

  @override
  FutureOr<void> $stopSendingCommandEvents() =>
      _unsupported('MainThreadTerminalService', r'$stopSendingCommandEvents');

  @override
  FutureOr<void> $startLinkProvider() =>
      _unsupported('MainThreadTerminalService', r'$startLinkProvider');

  @override
  FutureOr<void> $stopLinkProvider() =>
      _unsupported('MainThreadTerminalService', r'$stopLinkProvider');

  @override
  FutureOr<void> $sendProcessData(num terminalId, String data) =>
      _unsupported('MainThreadTerminalService', r'$sendProcessData');

  @override
  FutureOr<void> $sendProcessReady(
    num terminalId,
    num pid,
    String cwd,
    Map<String, Object?>? windowsPty,
  ) => _unsupported('MainThreadTerminalService', r'$sendProcessReady');

  @override
  FutureOr<void> $sendProcessProperty(
    num terminalId,
    Map<String, Object?> property,
  ) => _unsupported('MainThreadTerminalService', r'$sendProcessProperty');

  @override
  FutureOr<void> $sendProcessExit(num terminalId, num? exitCode) =>
      _unsupported('MainThreadTerminalService', r'$sendProcessExit');
}

/// Decodes requests to [MainContext.mainThreadTerminalService] and calls [target].
final class MainThreadTerminalServiceActor implements RpcActor {
  MainThreadTerminalServiceActor(this.target);

  static const identifier = MainContext.mainThreadTerminalService;

  final MainThreadTerminalServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTerminalService.$method', args);
    switch (method) {
      case r'$createTerminal':
        await target.$createTerminal(
          a.arg(0, decodeString, 'extHostTerminalId'),
          a.arg(1, decodeMap, 'config'),
        );
        return null;
      case r'$dispose':
        await target.$dispose(a.arg(0, decodeObject, 'id'));
        return null;
      case r'$hide':
        await target.$hide(a.arg(0, decodeObject, 'id'));
        return null;
      case r'$sendText':
        await target.$sendText(
          a.arg(0, decodeObject, 'id'),
          a.arg(1, decodeString, 'text'),
          a.arg(2, decodeBool, 'shouldExecute'),
        );
        return null;
      case r'$show':
        await target.$show(
          a.arg(0, decodeObject, 'id'),
          a.arg(1, decodeBool, 'preserveFocus'),
        );
        return null;
      case r'$registerProcessSupport':
        await target.$registerProcessSupport(
          a.arg(0, decodeBool, 'isSupported'),
        );
        return null;
      case r'$registerProfileProvider':
        await target.$registerProfileProvider(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'extensionIdentifier'),
        );
        return null;
      case r'$unregisterProfileProvider':
        await target.$unregisterProfileProvider(a.arg(0, decodeString, 'id'));
        return null;
      case r'$registerCompletionProvider':
        await target.$registerCompletionProvider(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'extensionIdentifier'),
          a.rest(2, decodeString, 'triggerCharacters'),
        );
        return null;
      case r'$unregisterCompletionProvider':
        await target.$unregisterCompletionProvider(
          a.arg(0, decodeString, 'id'),
        );
        return null;
      case r'$registerQuickFixProvider':
        await target.$registerQuickFixProvider(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'extensionIdentifier'),
        );
        return null;
      case r'$unregisterQuickFixProvider':
        await target.$unregisterQuickFixProvider(a.arg(0, decodeString, 'id'));
        return null;
      case r'$setEnvironmentVariableCollection':
        await target.$setEnvironmentVariableCollection(
          a.arg(0, decodeString, 'extensionIdentifier'),
          a.arg(1, decodeBool, 'persistent'),
          a.arg(
            2,
            decodeNullable(decodeListOf(decodeListOf(decodeObject))),
            'collection',
          ),
          a.arg(3, decodeListOf(decodeListOf(decodeObject)), 'descriptionMap'),
        );
        return null;
      case r'$startSendingDataEvents':
        await target.$startSendingDataEvents();
        return null;
      case r'$stopSendingDataEvents':
        await target.$stopSendingDataEvents();
        return null;
      case r'$startSendingCommandEvents':
        await target.$startSendingCommandEvents();
        return null;
      case r'$stopSendingCommandEvents':
        await target.$stopSendingCommandEvents();
        return null;
      case r'$startLinkProvider':
        await target.$startLinkProvider();
        return null;
      case r'$stopLinkProvider':
        await target.$stopLinkProvider();
        return null;
      case r'$sendProcessData':
        await target.$sendProcessData(
          a.arg(0, decodeNum, 'terminalId'),
          a.arg(1, decodeString, 'data'),
        );
        return null;
      case r'$sendProcessReady':
        await target.$sendProcessReady(
          a.arg(0, decodeNum, 'terminalId'),
          a.arg(1, decodeNum, 'pid'),
          a.arg(2, decodeString, 'cwd'),
          a.arg(3, decodeNullable(decodeMap), 'windowsPty'),
        );
        return null;
      case r'$sendProcessProperty':
        await target.$sendProcessProperty(
          a.arg(0, decodeNum, 'terminalId'),
          a.arg(1, decodeMap, 'property'),
        );
        return null;
      case r'$sendProcessExit':
        await target.$sendProcessExit(
          a.arg(0, decodeNum, 'terminalId'),
          a.arg(1, decodeNullable(decodeNum), 'exitCode'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTerminalService.$method');
    }
  }
}

// --- MainThreadTerminalShellIntegration ----------------------------------------

/// `MainThreadTerminalShellIntegrationShape` (`MainThreadTerminalShellIntegration`).
abstract interface class MainThreadTerminalShellIntegrationShape {
  /// `$executeCommand(terminalId: number, commandLine: string): void`
  FutureOr<void> $executeCommand(num terminalId, String commandLine);
}

/// [MainThreadTerminalShellIntegrationShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTerminalShellIntegrationUnsupported
    implements MainThreadTerminalShellIntegrationShape {
  const MainThreadTerminalShellIntegrationUnsupported();

  @override
  FutureOr<void> $executeCommand(num terminalId, String commandLine) =>
      _unsupported('MainThreadTerminalShellIntegration', r'$executeCommand');
}

/// Decodes requests to [MainContext.mainThreadTerminalShellIntegration] and calls [target].
final class MainThreadTerminalShellIntegrationActor implements RpcActor {
  MainThreadTerminalShellIntegrationActor(this.target);

  static const identifier = MainContext.mainThreadTerminalShellIntegration;

  final MainThreadTerminalShellIntegrationShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTerminalShellIntegration.$method', args);
    switch (method) {
      case r'$executeCommand':
        await target.$executeCommand(
          a.arg(0, decodeNum, 'terminalId'),
          a.arg(1, decodeString, 'commandLine'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTerminalShellIntegration.$method');
    }
  }
}

// --- MainThreadWebviews --------------------------------------------------------

/// `MainThreadWebviewsShape` (`MainThreadWebviews`).
abstract interface class MainThreadWebviewsShape {
  /// `$setHtml(handle: WebviewHandle, value: string): void`
  FutureOr<void> $setHtml(String handle, String value);

  /// `$setOptions(handle: WebviewHandle, options: IWebviewContentOptions): void`
  FutureOr<void> $setOptions(String handle, Map<String, Object?> options);

  /// `$postMessage(handle: WebviewHandle, value: string, ...buffers: VSBuffer[]): Promise<boolean>`
  Future<bool> $postMessage(
    String handle,
    String value,
    List<RpcBuffer> buffers,
  );
}

/// [MainThreadWebviewsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadWebviewsUnsupported implements MainThreadWebviewsShape {
  const MainThreadWebviewsUnsupported();

  @override
  FutureOr<void> $setHtml(String handle, String value) =>
      _unsupported('MainThreadWebviews', r'$setHtml');

  @override
  FutureOr<void> $setOptions(String handle, Map<String, Object?> options) =>
      _unsupported('MainThreadWebviews', r'$setOptions');

  @override
  Future<bool> $postMessage(
    String handle,
    String value,
    List<RpcBuffer> buffers,
  ) => _unsupported('MainThreadWebviews', r'$postMessage');
}

/// Decodes requests to [MainContext.mainThreadWebviews] and calls [target].
final class MainThreadWebviewsActor implements RpcActor {
  MainThreadWebviewsActor(this.target);

  static const identifier = MainContext.mainThreadWebviews;

  final MainThreadWebviewsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadWebviews.$method', args);
    switch (method) {
      case r'$setHtml':
        await target.$setHtml(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeString, 'value'),
        );
        return null;
      case r'$setOptions':
        await target.$setOptions(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeMap, 'options'),
        );
        return null;
      case r'$postMessage':
        return await target.$postMessage(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeString, 'value'),
          a.rest(2, decodeBuffer, 'buffers'),
        );
      default:
        throw RpcUnsupported('MainThreadWebviews.$method');
    }
  }
}

// --- MainThreadWebviewPanels ---------------------------------------------------

/// `MainThreadWebviewPanelsShape` (`MainThreadWebviewPanels`).
abstract interface class MainThreadWebviewPanelsShape {
  /// `$createWebviewPanel(extension: WebviewExtensionDescription, handle: WebviewHandle, viewType: string, initData: IWebviewInitData, showOptions: WebviewPanelShowOptions): void`
  FutureOr<void> $createWebviewPanel(
    Map<String, Object?> extension,
    String handle,
    String viewType,
    Map<String, Object?> initData,
    Map<String, Object?> showOptions,
  );

  /// `$disposeWebview(handle: WebviewHandle): void`
  FutureOr<void> $disposeWebview(String handle);

  /// `$reveal(handle: WebviewHandle, showOptions: WebviewPanelShowOptions): void`
  FutureOr<void> $reveal(String handle, Map<String, Object?> showOptions);

  /// `$setTitle(handle: WebviewHandle, value: string): void`
  FutureOr<void> $setTitle(String handle, String value);

  /// `$setIconPath(handle: WebviewHandle, value: IWebviewIconPath | undefined): void`
  FutureOr<void> $setIconPath(String handle, Map<String, Object?>? value);

  /// `$registerSerializer(viewType: string, options: { serializeBuffersForPostMessage: boolean }): void`
  FutureOr<void> $registerSerializer(
    String viewType,
    Map<String, Object?> options,
  );

  /// `$unregisterSerializer(viewType: string): void`
  FutureOr<void> $unregisterSerializer(String viewType);
}

/// [MainThreadWebviewPanelsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadWebviewPanelsUnsupported
    implements MainThreadWebviewPanelsShape {
  const MainThreadWebviewPanelsUnsupported();

  @override
  FutureOr<void> $createWebviewPanel(
    Map<String, Object?> extension,
    String handle,
    String viewType,
    Map<String, Object?> initData,
    Map<String, Object?> showOptions,
  ) => _unsupported('MainThreadWebviewPanels', r'$createWebviewPanel');

  @override
  FutureOr<void> $disposeWebview(String handle) =>
      _unsupported('MainThreadWebviewPanels', r'$disposeWebview');

  @override
  FutureOr<void> $reveal(String handle, Map<String, Object?> showOptions) =>
      _unsupported('MainThreadWebviewPanels', r'$reveal');

  @override
  FutureOr<void> $setTitle(String handle, String value) =>
      _unsupported('MainThreadWebviewPanels', r'$setTitle');

  @override
  FutureOr<void> $setIconPath(String handle, Map<String, Object?>? value) =>
      _unsupported('MainThreadWebviewPanels', r'$setIconPath');

  @override
  FutureOr<void> $registerSerializer(
    String viewType,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadWebviewPanels', r'$registerSerializer');

  @override
  FutureOr<void> $unregisterSerializer(String viewType) =>
      _unsupported('MainThreadWebviewPanels', r'$unregisterSerializer');
}

/// Decodes requests to [MainContext.mainThreadWebviewPanels] and calls [target].
final class MainThreadWebviewPanelsActor implements RpcActor {
  MainThreadWebviewPanelsActor(this.target);

  static const identifier = MainContext.mainThreadWebviewPanels;

  final MainThreadWebviewPanelsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadWebviewPanels.$method', args);
    switch (method) {
      case r'$createWebviewPanel':
        await target.$createWebviewPanel(
          a.arg(0, decodeMap, 'extension'),
          a.arg(1, decodeString, 'handle'),
          a.arg(2, decodeString, 'viewType'),
          a.arg(3, decodeMap, 'initData'),
          a.arg(4, decodeMap, 'showOptions'),
        );
        return null;
      case r'$disposeWebview':
        await target.$disposeWebview(a.arg(0, decodeString, 'handle'));
        return null;
      case r'$reveal':
        await target.$reveal(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeMap, 'showOptions'),
        );
        return null;
      case r'$setTitle':
        await target.$setTitle(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeString, 'value'),
        );
        return null;
      case r'$setIconPath':
        await target.$setIconPath(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeNullable(decodeMap), 'value'),
        );
        return null;
      case r'$registerSerializer':
        await target.$registerSerializer(
          a.arg(0, decodeString, 'viewType'),
          a.arg(1, decodeMap, 'options'),
        );
        return null;
      case r'$unregisterSerializer':
        await target.$unregisterSerializer(a.arg(0, decodeString, 'viewType'));
        return null;
      default:
        throw RpcUnsupported('MainThreadWebviewPanels.$method');
    }
  }
}

// --- MainThreadWebviewViews ----------------------------------------------------

/// `MainThreadWebviewViewsShape` (`MainThreadWebviewViews`).
abstract interface class MainThreadWebviewViewsShape {
  /// `$registerWebviewViewProvider(extension: WebviewExtensionDescription, viewType: string, options: { retainContextWhenHidden?: boolean; serializeBuffersForPostMessage: boolean }): void`
  FutureOr<void> $registerWebviewViewProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
  );

  /// `$unregisterWebviewViewProvider(viewType: string): void`
  FutureOr<void> $unregisterWebviewViewProvider(String viewType);

  /// `$setWebviewViewTitle(handle: WebviewHandle, value: string | undefined): void`
  FutureOr<void> $setWebviewViewTitle(String handle, String? value);

  /// `$setWebviewViewDescription(handle: WebviewHandle, value: string | undefined): void`
  FutureOr<void> $setWebviewViewDescription(String handle, String? value);

  /// `$setWebviewViewBadge(handle: WebviewHandle, badge: IViewBadge | undefined): void`
  FutureOr<void> $setWebviewViewBadge(
    String handle,
    Map<String, Object?>? badge,
  );

  /// `$show(handle: WebviewHandle, preserveFocus: boolean): void`
  FutureOr<void> $show(String handle, bool preserveFocus);
}

/// [MainThreadWebviewViewsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadWebviewViewsUnsupported
    implements MainThreadWebviewViewsShape {
  const MainThreadWebviewViewsUnsupported();

  @override
  FutureOr<void> $registerWebviewViewProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadWebviewViews', r'$registerWebviewViewProvider');

  @override
  FutureOr<void> $unregisterWebviewViewProvider(String viewType) =>
      _unsupported('MainThreadWebviewViews', r'$unregisterWebviewViewProvider');

  @override
  FutureOr<void> $setWebviewViewTitle(String handle, String? value) =>
      _unsupported('MainThreadWebviewViews', r'$setWebviewViewTitle');

  @override
  FutureOr<void> $setWebviewViewDescription(String handle, String? value) =>
      _unsupported('MainThreadWebviewViews', r'$setWebviewViewDescription');

  @override
  FutureOr<void> $setWebviewViewBadge(
    String handle,
    Map<String, Object?>? badge,
  ) => _unsupported('MainThreadWebviewViews', r'$setWebviewViewBadge');

  @override
  FutureOr<void> $show(String handle, bool preserveFocus) =>
      _unsupported('MainThreadWebviewViews', r'$show');
}

/// Decodes requests to [MainContext.mainThreadWebviewViews] and calls [target].
final class MainThreadWebviewViewsActor implements RpcActor {
  MainThreadWebviewViewsActor(this.target);

  static const identifier = MainContext.mainThreadWebviewViews;

  final MainThreadWebviewViewsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadWebviewViews.$method', args);
    switch (method) {
      case r'$registerWebviewViewProvider':
        await target.$registerWebviewViewProvider(
          a.arg(0, decodeMap, 'extension'),
          a.arg(1, decodeString, 'viewType'),
          a.arg(2, decodeMap, 'options'),
        );
        return null;
      case r'$unregisterWebviewViewProvider':
        await target.$unregisterWebviewViewProvider(
          a.arg(0, decodeString, 'viewType'),
        );
        return null;
      case r'$setWebviewViewTitle':
        await target.$setWebviewViewTitle(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeNullable(decodeString), 'value'),
        );
        return null;
      case r'$setWebviewViewDescription':
        await target.$setWebviewViewDescription(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeNullable(decodeString), 'value'),
        );
        return null;
      case r'$setWebviewViewBadge':
        await target.$setWebviewViewBadge(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeNullable(decodeMap), 'badge'),
        );
        return null;
      case r'$show':
        await target.$show(
          a.arg(0, decodeString, 'handle'),
          a.arg(1, decodeBool, 'preserveFocus'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadWebviewViews.$method');
    }
  }
}

// --- MainThreadCustomEditors ---------------------------------------------------

/// `MainThreadCustomEditorsShape` (`MainThreadCustomEditors`).
abstract interface class MainThreadCustomEditorsShape {
  /// `$registerTextEditorProvider(extension: WebviewExtensionDescription, viewType: string, options: IWebviewPanelOptions, capabilities: CustomEditorProviderCapabilities, serializeBuffersForPostMessage: boolean): void`
  FutureOr<void> $registerTextEditorProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?> capabilities,
    bool serializeBuffersForPostMessage,
  );

  /// `$registerCustomEditorProvider(extension: WebviewExtensionDescription, viewType: string, options: IWebviewPanelOptions, capabilities: CustomEditorProviderCapabilities, supportsMultipleEditorsPerDocument: boolean, serializeBuffersForPostMessage: boolean): void`
  FutureOr<void> $registerCustomEditorProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?> capabilities,
    bool supportsMultipleEditorsPerDocument,
    bool serializeBuffersForPostMessage,
  );

  /// `$unregisterEditorProvider(viewType: string): void`
  FutureOr<void> $unregisterEditorProvider(String viewType);

  /// `$onDidEdit(resource: UriComponents, viewType: string, editId: number, label: string | undefined): void`
  FutureOr<void> $onDidEdit(
    VsUri resource,
    String viewType,
    num editId,
    String? label,
  );

  /// `$onContentChange(resource: UriComponents, viewType: string): void`
  FutureOr<void> $onContentChange(VsUri resource, String viewType);
}

/// [MainThreadCustomEditorsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadCustomEditorsUnsupported
    implements MainThreadCustomEditorsShape {
  const MainThreadCustomEditorsUnsupported();

  @override
  FutureOr<void> $registerTextEditorProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?> capabilities,
    bool serializeBuffersForPostMessage,
  ) => _unsupported('MainThreadCustomEditors', r'$registerTextEditorProvider');

  @override
  FutureOr<void> $registerCustomEditorProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?> capabilities,
    bool supportsMultipleEditorsPerDocument,
    bool serializeBuffersForPostMessage,
  ) =>
      _unsupported('MainThreadCustomEditors', r'$registerCustomEditorProvider');

  @override
  FutureOr<void> $unregisterEditorProvider(String viewType) =>
      _unsupported('MainThreadCustomEditors', r'$unregisterEditorProvider');

  @override
  FutureOr<void> $onDidEdit(
    VsUri resource,
    String viewType,
    num editId,
    String? label,
  ) => _unsupported('MainThreadCustomEditors', r'$onDidEdit');

  @override
  FutureOr<void> $onContentChange(VsUri resource, String viewType) =>
      _unsupported('MainThreadCustomEditors', r'$onContentChange');
}

/// Decodes requests to [MainContext.mainThreadCustomEditors] and calls [target].
final class MainThreadCustomEditorsActor implements RpcActor {
  MainThreadCustomEditorsActor(this.target);

  static const identifier = MainContext.mainThreadCustomEditors;

  final MainThreadCustomEditorsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadCustomEditors.$method', args);
    switch (method) {
      case r'$registerTextEditorProvider':
        await target.$registerTextEditorProvider(
          a.arg(0, decodeMap, 'extension'),
          a.arg(1, decodeString, 'viewType'),
          a.arg(2, decodeMap, 'options'),
          a.arg(3, decodeMap, 'capabilities'),
          a.arg(4, decodeBool, 'serializeBuffersForPostMessage'),
        );
        return null;
      case r'$registerCustomEditorProvider':
        await target.$registerCustomEditorProvider(
          a.arg(0, decodeMap, 'extension'),
          a.arg(1, decodeString, 'viewType'),
          a.arg(2, decodeMap, 'options'),
          a.arg(3, decodeMap, 'capabilities'),
          a.arg(4, decodeBool, 'supportsMultipleEditorsPerDocument'),
          a.arg(5, decodeBool, 'serializeBuffersForPostMessage'),
        );
        return null;
      case r'$unregisterEditorProvider':
        await target.$unregisterEditorProvider(
          a.arg(0, decodeString, 'viewType'),
        );
        return null;
      case r'$onDidEdit':
        await target.$onDidEdit(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeString, 'viewType'),
          a.arg(2, decodeNum, 'editId'),
          a.arg(3, decodeNullable(decodeString), 'label'),
        );
        return null;
      case r'$onContentChange':
        await target.$onContentChange(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeString, 'viewType'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadCustomEditors.$method');
    }
  }
}

// --- MainThreadUrls ------------------------------------------------------------

/// `MainThreadUrlsShape` (`MainThreadUrls`).
abstract interface class MainThreadUrlsShape {
  /// `$registerUriHandler(handle: number, extensionId: ExtensionIdentifier, extensionDisplayName: string): Promise<void>`
  FutureOr<void> $registerUriHandler(
    num handle,
    Map<String, Object?> extensionId,
    String extensionDisplayName,
  );

  /// `$unregisterUriHandler(handle: number): Promise<void>`
  FutureOr<void> $unregisterUriHandler(num handle);

  /// `$createAppUri(uri: UriComponents): Promise<UriComponents>`
  Future<VsUri> $createAppUri(VsUri uri);
}

/// [MainThreadUrlsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadUrlsUnsupported implements MainThreadUrlsShape {
  const MainThreadUrlsUnsupported();

  @override
  FutureOr<void> $registerUriHandler(
    num handle,
    Map<String, Object?> extensionId,
    String extensionDisplayName,
  ) => _unsupported('MainThreadUrls', r'$registerUriHandler');

  @override
  FutureOr<void> $unregisterUriHandler(num handle) =>
      _unsupported('MainThreadUrls', r'$unregisterUriHandler');

  @override
  Future<VsUri> $createAppUri(VsUri uri) =>
      _unsupported('MainThreadUrls', r'$createAppUri');
}

/// Decodes requests to [MainContext.mainThreadUrls] and calls [target].
final class MainThreadUrlsActor implements RpcActor {
  MainThreadUrlsActor(this.target);

  static const identifier = MainContext.mainThreadUrls;

  final MainThreadUrlsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadUrls.$method', args);
    switch (method) {
      case r'$registerUriHandler':
        await target.$registerUriHandler(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'extensionId'),
          a.arg(2, decodeString, 'extensionDisplayName'),
        );
        return null;
      case r'$unregisterUriHandler':
        await target.$unregisterUriHandler(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$createAppUri':
        return await target.$createAppUri(a.arg(0, decodeUri, 'uri'));
      default:
        throw RpcUnsupported('MainThreadUrls.$method');
    }
  }
}

// --- MainThreadUriOpeners ------------------------------------------------------

/// `MainThreadUriOpenersShape` (`MainThreadUriOpeners`).
abstract interface class MainThreadUriOpenersShape {
  /// `$registerUriOpener(id: string, schemes: readonly string[], extensionId: ExtensionIdentifier, label: string): Promise<void>`
  FutureOr<void> $registerUriOpener(
    String id,
    List<String> schemes,
    Map<String, Object?> extensionId,
    String label,
  );

  /// `$unregisterUriOpener(id: string): Promise<void>`
  FutureOr<void> $unregisterUriOpener(String id);
}

/// [MainThreadUriOpenersShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadUriOpenersUnsupported
    implements MainThreadUriOpenersShape {
  const MainThreadUriOpenersUnsupported();

  @override
  FutureOr<void> $registerUriOpener(
    String id,
    List<String> schemes,
    Map<String, Object?> extensionId,
    String label,
  ) => _unsupported('MainThreadUriOpeners', r'$registerUriOpener');

  @override
  FutureOr<void> $unregisterUriOpener(String id) =>
      _unsupported('MainThreadUriOpeners', r'$unregisterUriOpener');
}

/// Decodes requests to [MainContext.mainThreadUriOpeners] and calls [target].
final class MainThreadUriOpenersActor implements RpcActor {
  MainThreadUriOpenersActor(this.target);

  static const identifier = MainContext.mainThreadUriOpeners;

  final MainThreadUriOpenersShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadUriOpeners.$method', args);
    switch (method) {
      case r'$registerUriOpener':
        await target.$registerUriOpener(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeListOf(decodeString), 'schemes'),
          a.arg(2, decodeMap, 'extensionId'),
          a.arg(3, decodeString, 'label'),
        );
        return null;
      case r'$unregisterUriOpener':
        await target.$unregisterUriOpener(a.arg(0, decodeString, 'id'));
        return null;
      default:
        throw RpcUnsupported('MainThreadUriOpeners.$method');
    }
  }
}

// --- MainThreadProfileContentHandlers ------------------------------------------

/// `MainThreadProfileContentHandlersShape` (`MainThreadProfileContentHandlers`).
abstract interface class MainThreadProfileContentHandlersShape {
  /// `$registerProfileContentHandler(id: string, name: string, description: string | undefined, extensionId: string): Promise<void>`
  FutureOr<void> $registerProfileContentHandler(
    String id,
    String name,
    String? description,
    String extensionId,
  );

  /// `$unregisterProfileContentHandler(id: string): Promise<void>`
  FutureOr<void> $unregisterProfileContentHandler(String id);
}

/// [MainThreadProfileContentHandlersShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadProfileContentHandlersUnsupported
    implements MainThreadProfileContentHandlersShape {
  const MainThreadProfileContentHandlersUnsupported();

  @override
  FutureOr<void> $registerProfileContentHandler(
    String id,
    String name,
    String? description,
    String extensionId,
  ) => _unsupported(
    'MainThreadProfileContentHandlers',
    r'$registerProfileContentHandler',
  );

  @override
  FutureOr<void> $unregisterProfileContentHandler(String id) => _unsupported(
    'MainThreadProfileContentHandlers',
    r'$unregisterProfileContentHandler',
  );
}

/// Decodes requests to [MainContext.mainThreadProfileContentHandlers] and calls [target].
final class MainThreadProfileContentHandlersActor implements RpcActor {
  MainThreadProfileContentHandlersActor(this.target);

  static const identifier = MainContext.mainThreadProfileContentHandlers;

  final MainThreadProfileContentHandlersShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadProfileContentHandlers.$method', args);
    switch (method) {
      case r'$registerProfileContentHandler':
        await target.$registerProfileContentHandler(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'name'),
          a.arg(2, decodeNullable(decodeString), 'description'),
          a.arg(3, decodeString, 'extensionId'),
        );
        return null;
      case r'$unregisterProfileContentHandler':
        await target.$unregisterProfileContentHandler(
          a.arg(0, decodeString, 'id'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadProfileContentHandlers.$method');
    }
  }
}

// --- MainThreadWorkspace -------------------------------------------------------

/// `MainThreadWorkspaceShape` (`MainThreadWorkspace`).
abstract interface class MainThreadWorkspaceShape {
  /// `$startFileSearch(includeFolder: UriComponents | null, options: IFileQueryBuilderOptions, token: CancellationToken): Promise<UriComponents[] | null>`
  Future<List<VsUri>?> $startFileSearch(
    VsUri? includeFolder,
    Map<String, Object?> options,
    CancellationToken token,
  );

  /// `$startTextSearch(query: search.IPatternInfo, folder: UriComponents | null, options: ITextQueryBuilderOptions, requestId: number, token: CancellationToken): Promise<ITextSearchComplete | null>`
  Future<Map<String, Object?>?> $startTextSearch(
    Map<String, Object?> query,
    VsUri? folder,
    Map<String, Object?> options,
    num requestId,
    CancellationToken token,
  );

  /// `$checkExists(folders: readonly UriComponents[], includes: string[], token: CancellationToken): Promise<boolean>`
  Future<bool> $checkExists(
    List<VsUri> folders,
    List<String> includes,
    CancellationToken token,
  );

  /// `$save(uri: UriComponents, options: { saveAs: boolean }): Promise<UriComponents | undefined>`
  Future<VsUri?> $save(VsUri uri, Map<String, Object?> options);

  /// `$saveAll(includeUntitled?: boolean): Promise<boolean>`
  Future<bool> $saveAll(bool? includeUntitled);

  /// `$updateWorkspaceFolders(extensionName: string, index: number, deleteCount: number, workspaceFoldersToAdd: { uri: UriComponents; name?: string }[]): Promise<void>`
  FutureOr<void> $updateWorkspaceFolders(
    String extensionName,
    num index,
    num deleteCount,
    List<Map<String, Object?>> workspaceFoldersToAdd,
  );

  /// `$resolveProxy(url: string): Promise<string | undefined>`
  Future<String?> $resolveProxy(String url);

  /// `$lookupAuthorization(authInfo: AuthInfo): Promise<Credentials | undefined>`
  Future<Map<String, Object?>?> $lookupAuthorization(
    Map<String, Object?> authInfo,
  );

  /// `$lookupKerberosAuthorization(url: string): Promise<string | undefined>`
  Future<String?> $lookupKerberosAuthorization(String url);

  /// `$loadCertificates(): Promise<string[]>`
  Future<List<String>> $loadCertificates();

  /// `$requestResourceTrust(options: ResourceTrustRequestOptionsDto): Promise<boolean | undefined>`
  Future<bool?> $requestResourceTrust(Map<String, Object?> options);

  /// `$requestWorkspaceTrust(options?: WorkspaceTrustRequestOptions): Promise<boolean | undefined>`
  Future<bool?> $requestWorkspaceTrust(Map<String, Object?>? options);

  /// `$isResourceTrusted(resource: UriComponents): Promise<boolean>`
  Future<bool> $isResourceTrusted(VsUri resource);

  /// `$registerEditSessionIdentityProvider(handle: number, scheme: string): void`
  FutureOr<void> $registerEditSessionIdentityProvider(
    num handle,
    String scheme,
  );

  /// `$unregisterEditSessionIdentityProvider(handle: number): void`
  FutureOr<void> $unregisterEditSessionIdentityProvider(num handle);

  /// `$registerCanonicalUriProvider(handle: number, scheme: string): void`
  FutureOr<void> $registerCanonicalUriProvider(num handle, String scheme);

  /// `$unregisterCanonicalUriProvider(handle: number): void`
  FutureOr<void> $unregisterCanonicalUriProvider(num handle);

  /// `$resolveDecoding(resource: UriComponents | undefined, options?: { encoding?: string }): Promise<{ preferredEncoding: string; guessEncoding: boolean; candidateGuessEncodings: string[] }>`
  Future<Map<String, Object?>> $resolveDecoding(
    VsUri? resource,
    Map<String, Object?>? options,
  );

  /// `$validateDetectedEncoding(resource: UriComponents | undefined, detectedEncoding: string, options?: { encoding?: string }): Promise<string>`
  Future<String> $validateDetectedEncoding(
    VsUri? resource,
    String detectedEncoding,
    Map<String, Object?>? options,
  );

  /// `$resolveEncoding(resource: UriComponents | undefined, options?: { encoding?: string }): Promise<{ encoding: string; addBOM: boolean }>`
  Future<Map<String, Object?>> $resolveEncoding(
    VsUri? resource,
    Map<String, Object?>? options,
  );
}

/// [MainThreadWorkspaceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadWorkspaceUnsupported implements MainThreadWorkspaceShape {
  const MainThreadWorkspaceUnsupported();

  @override
  Future<List<VsUri>?> $startFileSearch(
    VsUri? includeFolder,
    Map<String, Object?> options,
    CancellationToken token,
  ) => _unsupported('MainThreadWorkspace', r'$startFileSearch');

  @override
  Future<Map<String, Object?>?> $startTextSearch(
    Map<String, Object?> query,
    VsUri? folder,
    Map<String, Object?> options,
    num requestId,
    CancellationToken token,
  ) => _unsupported('MainThreadWorkspace', r'$startTextSearch');

  @override
  Future<bool> $checkExists(
    List<VsUri> folders,
    List<String> includes,
    CancellationToken token,
  ) => _unsupported('MainThreadWorkspace', r'$checkExists');

  @override
  Future<VsUri?> $save(VsUri uri, Map<String, Object?> options) =>
      _unsupported('MainThreadWorkspace', r'$save');

  @override
  Future<bool> $saveAll(bool? includeUntitled) =>
      _unsupported('MainThreadWorkspace', r'$saveAll');

  @override
  FutureOr<void> $updateWorkspaceFolders(
    String extensionName,
    num index,
    num deleteCount,
    List<Map<String, Object?>> workspaceFoldersToAdd,
  ) => _unsupported('MainThreadWorkspace', r'$updateWorkspaceFolders');

  @override
  Future<String?> $resolveProxy(String url) =>
      _unsupported('MainThreadWorkspace', r'$resolveProxy');

  @override
  Future<Map<String, Object?>?> $lookupAuthorization(
    Map<String, Object?> authInfo,
  ) => _unsupported('MainThreadWorkspace', r'$lookupAuthorization');

  @override
  Future<String?> $lookupKerberosAuthorization(String url) =>
      _unsupported('MainThreadWorkspace', r'$lookupKerberosAuthorization');

  @override
  Future<List<String>> $loadCertificates() =>
      _unsupported('MainThreadWorkspace', r'$loadCertificates');

  @override
  Future<bool?> $requestResourceTrust(Map<String, Object?> options) =>
      _unsupported('MainThreadWorkspace', r'$requestResourceTrust');

  @override
  Future<bool?> $requestWorkspaceTrust(Map<String, Object?>? options) =>
      _unsupported('MainThreadWorkspace', r'$requestWorkspaceTrust');

  @override
  Future<bool> $isResourceTrusted(VsUri resource) =>
      _unsupported('MainThreadWorkspace', r'$isResourceTrusted');

  @override
  FutureOr<void> $registerEditSessionIdentityProvider(
    num handle,
    String scheme,
  ) => _unsupported(
    'MainThreadWorkspace',
    r'$registerEditSessionIdentityProvider',
  );

  @override
  FutureOr<void> $unregisterEditSessionIdentityProvider(num handle) =>
      _unsupported(
        'MainThreadWorkspace',
        r'$unregisterEditSessionIdentityProvider',
      );

  @override
  FutureOr<void> $registerCanonicalUriProvider(num handle, String scheme) =>
      _unsupported('MainThreadWorkspace', r'$registerCanonicalUriProvider');

  @override
  FutureOr<void> $unregisterCanonicalUriProvider(num handle) =>
      _unsupported('MainThreadWorkspace', r'$unregisterCanonicalUriProvider');

  @override
  Future<Map<String, Object?>> $resolveDecoding(
    VsUri? resource,
    Map<String, Object?>? options,
  ) => _unsupported('MainThreadWorkspace', r'$resolveDecoding');

  @override
  Future<String> $validateDetectedEncoding(
    VsUri? resource,
    String detectedEncoding,
    Map<String, Object?>? options,
  ) => _unsupported('MainThreadWorkspace', r'$validateDetectedEncoding');

  @override
  Future<Map<String, Object?>> $resolveEncoding(
    VsUri? resource,
    Map<String, Object?>? options,
  ) => _unsupported('MainThreadWorkspace', r'$resolveEncoding');
}

/// Decodes requests to [MainContext.mainThreadWorkspace] and calls [target].
final class MainThreadWorkspaceActor implements RpcActor {
  MainThreadWorkspaceActor(this.target);

  static const identifier = MainContext.mainThreadWorkspace;

  final MainThreadWorkspaceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadWorkspace.$method', args);
    switch (method) {
      case r'$startFileSearch':
        return await target.$startFileSearch(
          a.arg(0, decodeNullable(decodeUri), 'includeFolder'),
          a.arg(1, decodeMap, 'options'),
          a.token,
        );
      case r'$startTextSearch':
        return await target.$startTextSearch(
          a.arg(0, decodeMap, 'query'),
          a.arg(1, decodeNullable(decodeUri), 'folder'),
          a.arg(2, decodeMap, 'options'),
          a.arg(3, decodeNum, 'requestId'),
          a.token,
        );
      case r'$checkExists':
        return await target.$checkExists(
          a.arg(0, decodeListOf(decodeUri), 'folders'),
          a.arg(1, decodeListOf(decodeString), 'includes'),
          a.token,
        );
      case r'$save':
        return await target.$save(
          a.arg(0, decodeUri, 'uri'),
          a.arg(1, decodeMap, 'options'),
        );
      case r'$saveAll':
        return await target.$saveAll(
          a.arg(0, decodeNullable(decodeBool), 'includeUntitled'),
        );
      case r'$updateWorkspaceFolders':
        await target.$updateWorkspaceFolders(
          a.arg(0, decodeString, 'extensionName'),
          a.arg(1, decodeNum, 'index'),
          a.arg(2, decodeNum, 'deleteCount'),
          a.arg(3, decodeListOf(decodeMap), 'workspaceFoldersToAdd'),
        );
        return null;
      case r'$resolveProxy':
        return await target.$resolveProxy(a.arg(0, decodeString, 'url'));
      case r'$lookupAuthorization':
        return await target.$lookupAuthorization(
          a.arg(0, decodeMap, 'authInfo'),
        );
      case r'$lookupKerberosAuthorization':
        return await target.$lookupKerberosAuthorization(
          a.arg(0, decodeString, 'url'),
        );
      case r'$loadCertificates':
        return await target.$loadCertificates();
      case r'$requestResourceTrust':
        return await target.$requestResourceTrust(
          a.arg(0, decodeMap, 'options'),
        );
      case r'$requestWorkspaceTrust':
        return await target.$requestWorkspaceTrust(
          a.arg(0, decodeNullable(decodeMap), 'options'),
        );
      case r'$isResourceTrusted':
        return await target.$isResourceTrusted(a.arg(0, decodeUri, 'resource'));
      case r'$registerEditSessionIdentityProvider':
        await target.$registerEditSessionIdentityProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
        );
        return null;
      case r'$unregisterEditSessionIdentityProvider':
        await target.$unregisterEditSessionIdentityProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$registerCanonicalUriProvider':
        await target.$registerCanonicalUriProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
        );
        return null;
      case r'$unregisterCanonicalUriProvider':
        await target.$unregisterCanonicalUriProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$resolveDecoding':
        return await target.$resolveDecoding(
          a.arg(0, decodeNullable(decodeUri), 'resource'),
          a.arg(1, decodeNullable(decodeMap), 'options'),
        );
      case r'$validateDetectedEncoding':
        return await target.$validateDetectedEncoding(
          a.arg(0, decodeNullable(decodeUri), 'resource'),
          a.arg(1, decodeString, 'detectedEncoding'),
          a.arg(2, decodeNullable(decodeMap), 'options'),
        );
      case r'$resolveEncoding':
        return await target.$resolveEncoding(
          a.arg(0, decodeNullable(decodeUri), 'resource'),
          a.arg(1, decodeNullable(decodeMap), 'options'),
        );
      default:
        throw RpcUnsupported('MainThreadWorkspace.$method');
    }
  }
}

// --- MainThreadFileSystem ------------------------------------------------------

/// `MainThreadFileSystemShape` (`MainThreadFileSystem`).
abstract interface class MainThreadFileSystemShape {
  /// `$registerFileSystemProvider(handle: number, scheme: string, capabilities: files.FileSystemProviderCapabilities, readonlyMessage?: IMarkdownString): Promise<void>`
  FutureOr<void> $registerFileSystemProvider(
    num handle,
    String scheme,
    int capabilities,
    Map<String, Object?>? readonlyMessage,
  );

  /// `$unregisterProvider(handle: number): void`
  FutureOr<void> $unregisterProvider(num handle);

  /// `$onFileSystemChange(handle: number, resource: IFileChangeDto[]): void`
  FutureOr<void> $onFileSystemChange(
    num handle,
    List<Map<String, Object?>> resource,
  );

  /// `$stat(resource: UriComponents): Promise<files.IStat>`
  Future<Map<String, Object?>> $stat(VsUri resource);

  /// `$readdir(resource: UriComponents): Promise<[string, files.FileType][]>`
  Future<List<List<Object?>>> $readdir(VsUri resource);

  /// `$readFile(resource: UriComponents): Promise<VSBuffer>`
  Future<RpcBuffer> $readFile(VsUri resource);

  /// `$writeFile(resource: UriComponents, content: VSBuffer): Promise<void>`
  FutureOr<void> $writeFile(VsUri resource, RpcBuffer content);

  /// `$rename(resource: UriComponents, target: UriComponents, opts: files.IFileOverwriteOptions): Promise<void>`
  FutureOr<void> $rename(
    VsUri resource,
    VsUri target,
    Map<String, Object?> opts,
  );

  /// `$copy(resource: UriComponents, target: UriComponents, opts: files.IFileOverwriteOptions): Promise<void>`
  FutureOr<void> $copy(VsUri resource, VsUri target, Map<String, Object?> opts);

  /// `$mkdir(resource: UriComponents): Promise<void>`
  FutureOr<void> $mkdir(VsUri resource);

  /// `$delete(resource: UriComponents, opts: files.IFileDeleteOptions): Promise<void>`
  FutureOr<void> $delete(VsUri resource, Map<String, Object?> opts);

  /// `$ensureActivation(scheme: string): Promise<void>`
  FutureOr<void> $ensureActivation(String scheme);
}

/// [MainThreadFileSystemShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadFileSystemUnsupported
    implements MainThreadFileSystemShape {
  const MainThreadFileSystemUnsupported();

  @override
  FutureOr<void> $registerFileSystemProvider(
    num handle,
    String scheme,
    int capabilities,
    Map<String, Object?>? readonlyMessage,
  ) => _unsupported('MainThreadFileSystem', r'$registerFileSystemProvider');

  @override
  FutureOr<void> $unregisterProvider(num handle) =>
      _unsupported('MainThreadFileSystem', r'$unregisterProvider');

  @override
  FutureOr<void> $onFileSystemChange(
    num handle,
    List<Map<String, Object?>> resource,
  ) => _unsupported('MainThreadFileSystem', r'$onFileSystemChange');

  @override
  Future<Map<String, Object?>> $stat(VsUri resource) =>
      _unsupported('MainThreadFileSystem', r'$stat');

  @override
  Future<List<List<Object?>>> $readdir(VsUri resource) =>
      _unsupported('MainThreadFileSystem', r'$readdir');

  @override
  Future<RpcBuffer> $readFile(VsUri resource) =>
      _unsupported('MainThreadFileSystem', r'$readFile');

  @override
  FutureOr<void> $writeFile(VsUri resource, RpcBuffer content) =>
      _unsupported('MainThreadFileSystem', r'$writeFile');

  @override
  FutureOr<void> $rename(
    VsUri resource,
    VsUri target,
    Map<String, Object?> opts,
  ) => _unsupported('MainThreadFileSystem', r'$rename');

  @override
  FutureOr<void> $copy(
    VsUri resource,
    VsUri target,
    Map<String, Object?> opts,
  ) => _unsupported('MainThreadFileSystem', r'$copy');

  @override
  FutureOr<void> $mkdir(VsUri resource) =>
      _unsupported('MainThreadFileSystem', r'$mkdir');

  @override
  FutureOr<void> $delete(VsUri resource, Map<String, Object?> opts) =>
      _unsupported('MainThreadFileSystem', r'$delete');

  @override
  FutureOr<void> $ensureActivation(String scheme) =>
      _unsupported('MainThreadFileSystem', r'$ensureActivation');
}

/// Decodes requests to [MainContext.mainThreadFileSystem] and calls [target].
final class MainThreadFileSystemActor implements RpcActor {
  MainThreadFileSystemActor(this.target);

  static const identifier = MainContext.mainThreadFileSystem;

  final MainThreadFileSystemShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadFileSystem.$method', args);
    switch (method) {
      case r'$registerFileSystemProvider':
        await target.$registerFileSystemProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
          a.arg(2, decodeInt, 'capabilities'),
          a.arg(3, decodeNullable(decodeMap), 'readonlyMessage'),
        );
        return null;
      case r'$unregisterProvider':
        await target.$unregisterProvider(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$onFileSystemChange':
        await target.$onFileSystemChange(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'resource'),
        );
        return null;
      case r'$stat':
        return await target.$stat(a.arg(0, decodeUri, 'resource'));
      case r'$readdir':
        return await target.$readdir(a.arg(0, decodeUri, 'resource'));
      case r'$readFile':
        return await target.$readFile(a.arg(0, decodeUri, 'resource'));
      case r'$writeFile':
        await target.$writeFile(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeBuffer, 'content'),
        );
        return null;
      case r'$rename':
        await target.$rename(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeUri, 'target'),
          a.arg(2, decodeMap, 'opts'),
        );
        return null;
      case r'$copy':
        await target.$copy(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeUri, 'target'),
          a.arg(2, decodeMap, 'opts'),
        );
        return null;
      case r'$mkdir':
        await target.$mkdir(a.arg(0, decodeUri, 'resource'));
        return null;
      case r'$delete':
        await target.$delete(
          a.arg(0, decodeUri, 'resource'),
          a.arg(1, decodeMap, 'opts'),
        );
        return null;
      case r'$ensureActivation':
        await target.$ensureActivation(a.arg(0, decodeString, 'scheme'));
        return null;
      default:
        throw RpcUnsupported('MainThreadFileSystem.$method');
    }
  }
}

// --- MainThreadFileSystemEventService ------------------------------------------

/// `MainThreadFileSystemEventServiceShape` (`MainThreadFileSystemEventService`).
abstract interface class MainThreadFileSystemEventServiceShape {
  /// `$watch(extensionId: string, session: number, resource: UriComponents, opts: files.IWatchOptions, correlate: boolean): void`
  FutureOr<void> $watch(
    String extensionId,
    num session,
    VsUri resource,
    Map<String, Object?> opts,
    bool correlate,
  );

  /// `$unwatch(session: number): void`
  FutureOr<void> $unwatch(num session);
}

/// [MainThreadFileSystemEventServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadFileSystemEventServiceUnsupported
    implements MainThreadFileSystemEventServiceShape {
  const MainThreadFileSystemEventServiceUnsupported();

  @override
  FutureOr<void> $watch(
    String extensionId,
    num session,
    VsUri resource,
    Map<String, Object?> opts,
    bool correlate,
  ) => _unsupported('MainThreadFileSystemEventService', r'$watch');

  @override
  FutureOr<void> $unwatch(num session) =>
      _unsupported('MainThreadFileSystemEventService', r'$unwatch');
}

/// Decodes requests to [MainContext.mainThreadFileSystemEventService] and calls [target].
final class MainThreadFileSystemEventServiceActor implements RpcActor {
  MainThreadFileSystemEventServiceActor(this.target);

  static const identifier = MainContext.mainThreadFileSystemEventService;

  final MainThreadFileSystemEventServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadFileSystemEventService.$method', args);
    switch (method) {
      case r'$watch':
        await target.$watch(
          a.arg(0, decodeString, 'extensionId'),
          a.arg(1, decodeNum, 'session'),
          a.arg(2, decodeUri, 'resource'),
          a.arg(3, decodeMap, 'opts'),
          a.arg(4, decodeBool, 'correlate'),
        );
        return null;
      case r'$unwatch':
        await target.$unwatch(a.arg(0, decodeNum, 'session'));
        return null;
      default:
        throw RpcUnsupported('MainThreadFileSystemEventService.$method');
    }
  }
}

// --- MainThreadExtensionService ------------------------------------------------

/// `MainThreadExtensionServiceShape` (`MainThreadExtensionService`).
abstract interface class MainThreadExtensionServiceShape {
  /// `$getExtension(extensionId: string): Promise<Dto<IExtensionDescription> | undefined>`
  Future<Map<String, Object?>?> $getExtension(String extensionId);

  /// `$activateExtension(extensionId: ExtensionIdentifier, reason: ExtensionActivationReason): Promise<void>`
  FutureOr<void> $activateExtension(
    Map<String, Object?> extensionId,
    Map<String, Object?> reason,
  );

  /// `$onWillActivateExtension(extensionId: ExtensionIdentifier): Promise<void>`
  FutureOr<void> $onWillActivateExtension(Map<String, Object?> extensionId);

  /// `$onDidActivateExtension(extensionId: ExtensionIdentifier, codeLoadingTime: number, activateCallTime: number, activateResolvedTime: number, activationReason: ExtensionActivationReason): void`
  FutureOr<void> $onDidActivateExtension(
    Map<String, Object?> extensionId,
    num codeLoadingTime,
    num activateCallTime,
    num activateResolvedTime,
    Map<String, Object?> activationReason,
  );

  /// `$onExtensionActivationError(extensionId: ExtensionIdentifier, error: SerializedError, missingExtensionDependency: MissingExtensionDependency | null): Promise<void>`
  FutureOr<void> $onExtensionActivationError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
    Map<String, Object?>? missingExtensionDependency,
  );

  /// `$onExtensionRuntimeError(extensionId: ExtensionIdentifier, error: SerializedError): void`
  FutureOr<void> $onExtensionRuntimeError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
  );

  /// `$setPerformanceMarks(marks: performance.PerformanceMark[]): Promise<void>`
  FutureOr<void> $setPerformanceMarks(List<Map<String, Object?>> marks);

  /// `$asBrowserUri(uri: UriComponents): Promise<UriComponents>`
  Future<VsUri> $asBrowserUri(VsUri uri);
}

/// [MainThreadExtensionServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadExtensionServiceUnsupported
    implements MainThreadExtensionServiceShape {
  const MainThreadExtensionServiceUnsupported();

  @override
  Future<Map<String, Object?>?> $getExtension(String extensionId) =>
      _unsupported('MainThreadExtensionService', r'$getExtension');

  @override
  FutureOr<void> $activateExtension(
    Map<String, Object?> extensionId,
    Map<String, Object?> reason,
  ) => _unsupported('MainThreadExtensionService', r'$activateExtension');

  @override
  FutureOr<void> $onWillActivateExtension(Map<String, Object?> extensionId) =>
      _unsupported('MainThreadExtensionService', r'$onWillActivateExtension');

  @override
  FutureOr<void> $onDidActivateExtension(
    Map<String, Object?> extensionId,
    num codeLoadingTime,
    num activateCallTime,
    num activateResolvedTime,
    Map<String, Object?> activationReason,
  ) => _unsupported('MainThreadExtensionService', r'$onDidActivateExtension');

  @override
  FutureOr<void> $onExtensionActivationError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
    Map<String, Object?>? missingExtensionDependency,
  ) => _unsupported(
    'MainThreadExtensionService',
    r'$onExtensionActivationError',
  );

  @override
  FutureOr<void> $onExtensionRuntimeError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
  ) => _unsupported('MainThreadExtensionService', r'$onExtensionRuntimeError');

  @override
  FutureOr<void> $setPerformanceMarks(List<Map<String, Object?>> marks) =>
      _unsupported('MainThreadExtensionService', r'$setPerformanceMarks');

  @override
  Future<VsUri> $asBrowserUri(VsUri uri) =>
      _unsupported('MainThreadExtensionService', r'$asBrowserUri');
}

/// Decodes requests to [MainContext.mainThreadExtensionService] and calls [target].
final class MainThreadExtensionServiceActor implements RpcActor {
  MainThreadExtensionServiceActor(this.target);

  static const identifier = MainContext.mainThreadExtensionService;

  final MainThreadExtensionServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadExtensionService.$method', args);
    switch (method) {
      case r'$getExtension':
        return await target.$getExtension(
          a.arg(0, decodeString, 'extensionId'),
        );
      case r'$activateExtension':
        await target.$activateExtension(
          a.arg(0, decodeMap, 'extensionId'),
          a.arg(1, decodeMap, 'reason'),
        );
        return null;
      case r'$onWillActivateExtension':
        await target.$onWillActivateExtension(
          a.arg(0, decodeMap, 'extensionId'),
        );
        return null;
      case r'$onDidActivateExtension':
        await target.$onDidActivateExtension(
          a.arg(0, decodeMap, 'extensionId'),
          a.arg(1, decodeNum, 'codeLoadingTime'),
          a.arg(2, decodeNum, 'activateCallTime'),
          a.arg(3, decodeNum, 'activateResolvedTime'),
          a.arg(4, decodeMap, 'activationReason'),
        );
        return null;
      case r'$onExtensionActivationError':
        await target.$onExtensionActivationError(
          a.arg(0, decodeMap, 'extensionId'),
          a.arg(1, decodeMap, 'error'),
          a.arg(2, decodeNullable(decodeMap), 'missingExtensionDependency'),
        );
        return null;
      case r'$onExtensionRuntimeError':
        await target.$onExtensionRuntimeError(
          a.arg(0, decodeMap, 'extensionId'),
          a.arg(1, decodeMap, 'error'),
        );
        return null;
      case r'$setPerformanceMarks':
        await target.$setPerformanceMarks(
          a.arg(0, decodeListOf(decodeMap), 'marks'),
        );
        return null;
      case r'$asBrowserUri':
        return await target.$asBrowserUri(a.arg(0, decodeUri, 'uri'));
      default:
        throw RpcUnsupported('MainThreadExtensionService.$method');
    }
  }
}

// --- MainThreadSCM -------------------------------------------------------------

/// `MainThreadSCMShape` (`MainThreadSCM`).
abstract interface class MainThreadSCMShape {
  /// `$registerSourceControl(handle: number, parentHandle: number | undefined, id: string, label: string, rootUri: UriComponents | undefined, iconPath: IconPathDto | undefined, isHidden: boolean | undefined, inputBoxDocumentUri: UriComponents): Promise<void>`
  FutureOr<void> $registerSourceControl(
    num handle,
    num? parentHandle,
    String id,
    String label,
    VsUri? rootUri,
    Object? iconPath,
    bool? isHidden,
    VsUri inputBoxDocumentUri,
  );

  /// `$updateSourceControl(handle: number, features: SCMProviderFeatures): Promise<void>`
  FutureOr<void> $updateSourceControl(
    num handle,
    Map<String, Object?> features,
  );

  /// `$unregisterSourceControl(handle: number): Promise<void>`
  FutureOr<void> $unregisterSourceControl(num handle);

  /// `$registerGroups(sourceControlHandle: number, groups: [number /*handle*/, string /*id*/, string /*label*/, SCMGroupFeatures, /* multiDiffEditorEnableViewChanges */ boolean][], splices: SCMRawResourceSplices[]): Promise<void>`
  FutureOr<void> $registerGroups(
    num sourceControlHandle,
    List<List<Object?>> groups,
    List<List<Object?>> splices,
  );

  /// `$updateGroup(sourceControlHandle: number, handle: number, features: SCMGroupFeatures): Promise<void>`
  FutureOr<void> $updateGroup(
    num sourceControlHandle,
    num handle,
    Map<String, Object?> features,
  );

  /// `$updateGroupLabel(sourceControlHandle: number, handle: number, label: string): Promise<void>`
  FutureOr<void> $updateGroupLabel(
    num sourceControlHandle,
    num handle,
    String label,
  );

  /// `$unregisterGroup(sourceControlHandle: number, handle: number): Promise<void>`
  FutureOr<void> $unregisterGroup(num sourceControlHandle, num handle);

  /// `$spliceResourceStates(sourceControlHandle: number, splices: SCMRawResourceSplices[]): Promise<void>`
  FutureOr<void> $spliceResourceStates(
    num sourceControlHandle,
    List<List<Object?>> splices,
  );

  /// `$setInputBoxValue(sourceControlHandle: number, value: string): Promise<void>`
  FutureOr<void> $setInputBoxValue(num sourceControlHandle, String value);

  /// `$setInputBoxPlaceholder(sourceControlHandle: number, placeholder: string): Promise<void>`
  FutureOr<void> $setInputBoxPlaceholder(
    num sourceControlHandle,
    String placeholder,
  );

  /// `$setInputBoxEnablement(sourceControlHandle: number, enabled: boolean): Promise<void>`
  FutureOr<void> $setInputBoxEnablement(num sourceControlHandle, bool enabled);

  /// `$setInputBoxVisibility(sourceControlHandle: number, visible: boolean): Promise<void>`
  FutureOr<void> $setInputBoxVisibility(num sourceControlHandle, bool visible);

  /// `$showValidationMessage(sourceControlHandle: number, message: string | IMarkdownString, type: InputValidationType): Promise<void>`
  FutureOr<void> $showValidationMessage(
    num sourceControlHandle,
    Object? message,
    int type,
  );

  /// `$setValidationProviderIsEnabled(sourceControlHandle: number, enabled: boolean): Promise<void>`
  FutureOr<void> $setValidationProviderIsEnabled(
    num sourceControlHandle,
    bool enabled,
  );

  /// `$onDidChangeHistoryProviderCurrentHistoryItemRefs(sourceControlHandle: number, historyItemRef?: SCMHistoryItemRefDto, historyItemRemoteRef?: SCMHistoryItemRefDto, historyItemBaseRef?: SCMHistoryItemRefDto): Promise<void>`
  FutureOr<void> $onDidChangeHistoryProviderCurrentHistoryItemRefs(
    num sourceControlHandle,
    Map<String, Object?>? historyItemRef,
    Map<String, Object?>? historyItemRemoteRef,
    Map<String, Object?>? historyItemBaseRef,
  );

  /// `$onDidChangeHistoryProviderHistoryItemRefs(sourceControlHandle: number, historyItemRefs: SCMHistoryItemRefsChangeEventDto): Promise<void>`
  FutureOr<void> $onDidChangeHistoryProviderHistoryItemRefs(
    num sourceControlHandle,
    Map<String, Object?> historyItemRefs,
  );

  /// `$onDidChangeArtifacts(sourceControlHandle: number, groups: string[]): Promise<void>`
  FutureOr<void> $onDidChangeArtifacts(
    num sourceControlHandle,
    List<String> groups,
  );
}

/// [MainThreadSCMShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadSCMUnsupported implements MainThreadSCMShape {
  const MainThreadSCMUnsupported();

  @override
  FutureOr<void> $registerSourceControl(
    num handle,
    num? parentHandle,
    String id,
    String label,
    VsUri? rootUri,
    Object? iconPath,
    bool? isHidden,
    VsUri inputBoxDocumentUri,
  ) => _unsupported('MainThreadSCM', r'$registerSourceControl');

  @override
  FutureOr<void> $updateSourceControl(
    num handle,
    Map<String, Object?> features,
  ) => _unsupported('MainThreadSCM', r'$updateSourceControl');

  @override
  FutureOr<void> $unregisterSourceControl(num handle) =>
      _unsupported('MainThreadSCM', r'$unregisterSourceControl');

  @override
  FutureOr<void> $registerGroups(
    num sourceControlHandle,
    List<List<Object?>> groups,
    List<List<Object?>> splices,
  ) => _unsupported('MainThreadSCM', r'$registerGroups');

  @override
  FutureOr<void> $updateGroup(
    num sourceControlHandle,
    num handle,
    Map<String, Object?> features,
  ) => _unsupported('MainThreadSCM', r'$updateGroup');

  @override
  FutureOr<void> $updateGroupLabel(
    num sourceControlHandle,
    num handle,
    String label,
  ) => _unsupported('MainThreadSCM', r'$updateGroupLabel');

  @override
  FutureOr<void> $unregisterGroup(num sourceControlHandle, num handle) =>
      _unsupported('MainThreadSCM', r'$unregisterGroup');

  @override
  FutureOr<void> $spliceResourceStates(
    num sourceControlHandle,
    List<List<Object?>> splices,
  ) => _unsupported('MainThreadSCM', r'$spliceResourceStates');

  @override
  FutureOr<void> $setInputBoxValue(num sourceControlHandle, String value) =>
      _unsupported('MainThreadSCM', r'$setInputBoxValue');

  @override
  FutureOr<void> $setInputBoxPlaceholder(
    num sourceControlHandle,
    String placeholder,
  ) => _unsupported('MainThreadSCM', r'$setInputBoxPlaceholder');

  @override
  FutureOr<void> $setInputBoxEnablement(
    num sourceControlHandle,
    bool enabled,
  ) => _unsupported('MainThreadSCM', r'$setInputBoxEnablement');

  @override
  FutureOr<void> $setInputBoxVisibility(
    num sourceControlHandle,
    bool visible,
  ) => _unsupported('MainThreadSCM', r'$setInputBoxVisibility');

  @override
  FutureOr<void> $showValidationMessage(
    num sourceControlHandle,
    Object? message,
    int type,
  ) => _unsupported('MainThreadSCM', r'$showValidationMessage');

  @override
  FutureOr<void> $setValidationProviderIsEnabled(
    num sourceControlHandle,
    bool enabled,
  ) => _unsupported('MainThreadSCM', r'$setValidationProviderIsEnabled');

  @override
  FutureOr<void> $onDidChangeHistoryProviderCurrentHistoryItemRefs(
    num sourceControlHandle,
    Map<String, Object?>? historyItemRef,
    Map<String, Object?>? historyItemRemoteRef,
    Map<String, Object?>? historyItemBaseRef,
  ) => _unsupported(
    'MainThreadSCM',
    r'$onDidChangeHistoryProviderCurrentHistoryItemRefs',
  );

  @override
  FutureOr<void> $onDidChangeHistoryProviderHistoryItemRefs(
    num sourceControlHandle,
    Map<String, Object?> historyItemRefs,
  ) => _unsupported(
    'MainThreadSCM',
    r'$onDidChangeHistoryProviderHistoryItemRefs',
  );

  @override
  FutureOr<void> $onDidChangeArtifacts(
    num sourceControlHandle,
    List<String> groups,
  ) => _unsupported('MainThreadSCM', r'$onDidChangeArtifacts');
}

/// Decodes requests to [MainContext.mainThreadSCM] and calls [target].
final class MainThreadSCMActor implements RpcActor {
  MainThreadSCMActor(this.target);

  static const identifier = MainContext.mainThreadSCM;

  final MainThreadSCMShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadSCM.$method', args);
    switch (method) {
      case r'$registerSourceControl':
        await target.$registerSourceControl(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeNum), 'parentHandle'),
          a.arg(2, decodeString, 'id'),
          a.arg(3, decodeString, 'label'),
          a.arg(4, decodeNullable(decodeUri), 'rootUri'),
          a.arg(5, decodeObject, 'iconPath'),
          a.arg(6, decodeNullable(decodeBool), 'isHidden'),
          a.arg(7, decodeUri, 'inputBoxDocumentUri'),
        );
        return null;
      case r'$updateSourceControl':
        await target.$updateSourceControl(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'features'),
        );
        return null;
      case r'$unregisterSourceControl':
        await target.$unregisterSourceControl(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$registerGroups':
        await target.$registerGroups(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeListOf(decodeListOf(decodeObject)), 'groups'),
          a.arg(2, decodeListOf(decodeListOf(decodeObject)), 'splices'),
        );
        return null;
      case r'$updateGroup':
        await target.$updateGroup(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeNum, 'handle'),
          a.arg(2, decodeMap, 'features'),
        );
        return null;
      case r'$updateGroupLabel':
        await target.$updateGroupLabel(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeNum, 'handle'),
          a.arg(2, decodeString, 'label'),
        );
        return null;
      case r'$unregisterGroup':
        await target.$unregisterGroup(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeNum, 'handle'),
        );
        return null;
      case r'$spliceResourceStates':
        await target.$spliceResourceStates(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeListOf(decodeListOf(decodeObject)), 'splices'),
        );
        return null;
      case r'$setInputBoxValue':
        await target.$setInputBoxValue(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeString, 'value'),
        );
        return null;
      case r'$setInputBoxPlaceholder':
        await target.$setInputBoxPlaceholder(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeString, 'placeholder'),
        );
        return null;
      case r'$setInputBoxEnablement':
        await target.$setInputBoxEnablement(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeBool, 'enabled'),
        );
        return null;
      case r'$setInputBoxVisibility':
        await target.$setInputBoxVisibility(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeBool, 'visible'),
        );
        return null;
      case r'$showValidationMessage':
        await target.$showValidationMessage(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeObject, 'message'),
          a.arg(2, decodeInt, 'type'),
        );
        return null;
      case r'$setValidationProviderIsEnabled':
        await target.$setValidationProviderIsEnabled(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeBool, 'enabled'),
        );
        return null;
      case r'$onDidChangeHistoryProviderCurrentHistoryItemRefs':
        await target.$onDidChangeHistoryProviderCurrentHistoryItemRefs(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeNullable(decodeMap), 'historyItemRef'),
          a.arg(2, decodeNullable(decodeMap), 'historyItemRemoteRef'),
          a.arg(3, decodeNullable(decodeMap), 'historyItemBaseRef'),
        );
        return null;
      case r'$onDidChangeHistoryProviderHistoryItemRefs':
        await target.$onDidChangeHistoryProviderHistoryItemRefs(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeMap, 'historyItemRefs'),
        );
        return null;
      case r'$onDidChangeArtifacts':
        await target.$onDidChangeArtifacts(
          a.arg(0, decodeNum, 'sourceControlHandle'),
          a.arg(1, decodeListOf(decodeString), 'groups'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadSCM.$method');
    }
  }
}

// --- MainThreadSearch ----------------------------------------------------------

/// `MainThreadSearchShape` (`MainThreadSearch`).
abstract interface class MainThreadSearchShape {
  /// `$registerFileSearchProvider(handle: number, scheme: string): void`
  FutureOr<void> $registerFileSearchProvider(num handle, String scheme);

  /// `$registerAITextSearchProvider(handle: number, scheme: string): void`
  FutureOr<void> $registerAITextSearchProvider(num handle, String scheme);

  /// `$registerTextSearchProvider(handle: number, scheme: string): void`
  FutureOr<void> $registerTextSearchProvider(num handle, String scheme);

  /// `$unregisterProvider(handle: number): void`
  FutureOr<void> $unregisterProvider(num handle);

  /// `$handleFileMatch(handle: number, session: number, data: UriComponents[]): void`
  FutureOr<void> $handleFileMatch(num handle, num session, List<VsUri> data);

  /// `$handleTextMatch(handle: number, session: number, data: search.IRawFileMatch2[]): void`
  FutureOr<void> $handleTextMatch(
    num handle,
    num session,
    List<Map<String, Object?>> data,
  );

  /// `$handleKeywordResult(handle: number, session: number, data: AISearchKeyword): void`
  FutureOr<void> $handleKeywordResult(
    num handle,
    num session,
    Map<String, Object?> data,
  );

  /// `$handleTelemetry(eventName: string, data: any): void`
  FutureOr<void> $handleTelemetry(String eventName, Object? data);
}

/// [MainThreadSearchShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadSearchUnsupported implements MainThreadSearchShape {
  const MainThreadSearchUnsupported();

  @override
  FutureOr<void> $registerFileSearchProvider(num handle, String scheme) =>
      _unsupported('MainThreadSearch', r'$registerFileSearchProvider');

  @override
  FutureOr<void> $registerAITextSearchProvider(num handle, String scheme) =>
      _unsupported('MainThreadSearch', r'$registerAITextSearchProvider');

  @override
  FutureOr<void> $registerTextSearchProvider(num handle, String scheme) =>
      _unsupported('MainThreadSearch', r'$registerTextSearchProvider');

  @override
  FutureOr<void> $unregisterProvider(num handle) =>
      _unsupported('MainThreadSearch', r'$unregisterProvider');

  @override
  FutureOr<void> $handleFileMatch(num handle, num session, List<VsUri> data) =>
      _unsupported('MainThreadSearch', r'$handleFileMatch');

  @override
  FutureOr<void> $handleTextMatch(
    num handle,
    num session,
    List<Map<String, Object?>> data,
  ) => _unsupported('MainThreadSearch', r'$handleTextMatch');

  @override
  FutureOr<void> $handleKeywordResult(
    num handle,
    num session,
    Map<String, Object?> data,
  ) => _unsupported('MainThreadSearch', r'$handleKeywordResult');

  @override
  FutureOr<void> $handleTelemetry(String eventName, Object? data) =>
      _unsupported('MainThreadSearch', r'$handleTelemetry');
}

/// Decodes requests to [MainContext.mainThreadSearch] and calls [target].
final class MainThreadSearchActor implements RpcActor {
  MainThreadSearchActor(this.target);

  static const identifier = MainContext.mainThreadSearch;

  final MainThreadSearchShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadSearch.$method', args);
    switch (method) {
      case r'$registerFileSearchProvider':
        await target.$registerFileSearchProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
        );
        return null;
      case r'$registerAITextSearchProvider':
        await target.$registerAITextSearchProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
        );
        return null;
      case r'$registerTextSearchProvider':
        await target.$registerTextSearchProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'scheme'),
        );
        return null;
      case r'$unregisterProvider':
        await target.$unregisterProvider(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$handleFileMatch':
        await target.$handleFileMatch(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'session'),
          a.arg(2, decodeListOf(decodeUri), 'data'),
        );
        return null;
      case r'$handleTextMatch':
        await target.$handleTextMatch(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'session'),
          a.arg(2, decodeListOf(decodeMap), 'data'),
        );
        return null;
      case r'$handleKeywordResult':
        await target.$handleKeywordResult(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'session'),
          a.arg(2, decodeMap, 'data'),
        );
        return null;
      case r'$handleTelemetry':
        await target.$handleTelemetry(
          a.arg(0, decodeString, 'eventName'),
          a.arg(1, decodeObject, 'data'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadSearch.$method');
    }
  }
}

// --- MainThreadShare -----------------------------------------------------------

/// `MainThreadShareShape` (`MainThreadShare`).
abstract interface class MainThreadShareShape {
  /// `$registerShareProvider(handle: number, selector: IDocumentFilterDto[], id: string, label: string, priority: number): void`
  FutureOr<void> $registerShareProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String id,
    String label,
    num priority,
  );

  /// `$unregisterShareProvider(handle: number): void`
  FutureOr<void> $unregisterShareProvider(num handle);
}

/// [MainThreadShareShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadShareUnsupported implements MainThreadShareShape {
  const MainThreadShareUnsupported();

  @override
  FutureOr<void> $registerShareProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String id,
    String label,
    num priority,
  ) => _unsupported('MainThreadShare', r'$registerShareProvider');

  @override
  FutureOr<void> $unregisterShareProvider(num handle) =>
      _unsupported('MainThreadShare', r'$unregisterShareProvider');
}

/// Decodes requests to [MainContext.mainThreadShare] and calls [target].
final class MainThreadShareActor implements RpcActor {
  MainThreadShareActor(this.target);

  static const identifier = MainContext.mainThreadShare;

  final MainThreadShareShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadShare.$method', args);
    switch (method) {
      case r'$registerShareProvider':
        await target.$registerShareProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'selector'),
          a.arg(2, decodeString, 'id'),
          a.arg(3, decodeString, 'label'),
          a.arg(4, decodeNum, 'priority'),
        );
        return null;
      case r'$unregisterShareProvider':
        await target.$unregisterShareProvider(a.arg(0, decodeNum, 'handle'));
        return null;
      default:
        throw RpcUnsupported('MainThreadShare.$method');
    }
  }
}

// --- MainThreadTask ------------------------------------------------------------

/// `MainThreadTaskShape` (`MainThreadTask`).
abstract interface class MainThreadTaskShape {
  /// `$createTaskId(task: tasks.ITaskDTO): Promise<string>`
  Future<String> $createTaskId(Map<String, Object?> task);

  /// `$registerTaskProvider(handle: number, type: string): Promise<void>`
  FutureOr<void> $registerTaskProvider(num handle, String type);

  /// `$unregisterTaskProvider(handle: number): Promise<void>`
  FutureOr<void> $unregisterTaskProvider(num handle);

  /// `$fetchTasks(filter?: tasks.ITaskFilterDTO): Promise<tasks.ITaskDTO[]>`
  Future<List<Map<String, Object?>>> $fetchTasks(Map<String, Object?>? filter);

  /// `$getTaskExecution(value: tasks.ITaskHandleDTO | tasks.ITaskDTO): Promise<tasks.ITaskExecutionDTO>`
  Future<Map<String, Object?>> $getTaskExecution(Map<String, Object?> value);

  /// `$executeTask(task: tasks.ITaskHandleDTO | tasks.ITaskDTO): Promise<tasks.ITaskExecutionDTO>`
  Future<Map<String, Object?>> $executeTask(Map<String, Object?> task);

  /// `$terminateTask(id: string): Promise<void>`
  FutureOr<void> $terminateTask(String id);

  /// `$registerTaskSystem(scheme: string, info: tasks.ITaskSystemInfoDTO): void`
  FutureOr<void> $registerTaskSystem(String scheme, Map<String, Object?> info);

  /// `$customExecutionComplete(id: string, result?: number): Promise<void>`
  FutureOr<void> $customExecutionComplete(String id, num? result);

  /// `$registerSupportedExecutions(custom?: boolean, shell?: boolean, process?: boolean): Promise<void>`
  FutureOr<void> $registerSupportedExecutions(
    bool? custom,
    bool? shell,
    bool? process,
  );
}

/// [MainThreadTaskShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTaskUnsupported implements MainThreadTaskShape {
  const MainThreadTaskUnsupported();

  @override
  Future<String> $createTaskId(Map<String, Object?> task) =>
      _unsupported('MainThreadTask', r'$createTaskId');

  @override
  FutureOr<void> $registerTaskProvider(num handle, String type) =>
      _unsupported('MainThreadTask', r'$registerTaskProvider');

  @override
  FutureOr<void> $unregisterTaskProvider(num handle) =>
      _unsupported('MainThreadTask', r'$unregisterTaskProvider');

  @override
  Future<List<Map<String, Object?>>> $fetchTasks(
    Map<String, Object?>? filter,
  ) => _unsupported('MainThreadTask', r'$fetchTasks');

  @override
  Future<Map<String, Object?>> $getTaskExecution(Map<String, Object?> value) =>
      _unsupported('MainThreadTask', r'$getTaskExecution');

  @override
  Future<Map<String, Object?>> $executeTask(Map<String, Object?> task) =>
      _unsupported('MainThreadTask', r'$executeTask');

  @override
  FutureOr<void> $terminateTask(String id) =>
      _unsupported('MainThreadTask', r'$terminateTask');

  @override
  FutureOr<void> $registerTaskSystem(
    String scheme,
    Map<String, Object?> info,
  ) => _unsupported('MainThreadTask', r'$registerTaskSystem');

  @override
  FutureOr<void> $customExecutionComplete(String id, num? result) =>
      _unsupported('MainThreadTask', r'$customExecutionComplete');

  @override
  FutureOr<void> $registerSupportedExecutions(
    bool? custom,
    bool? shell,
    bool? process,
  ) => _unsupported('MainThreadTask', r'$registerSupportedExecutions');
}

/// Decodes requests to [MainContext.mainThreadTask] and calls [target].
final class MainThreadTaskActor implements RpcActor {
  MainThreadTaskActor(this.target);

  static const identifier = MainContext.mainThreadTask;

  final MainThreadTaskShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTask.$method', args);
    switch (method) {
      case r'$createTaskId':
        return await target.$createTaskId(a.arg(0, decodeMap, 'task'));
      case r'$registerTaskProvider':
        await target.$registerTaskProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'type'),
        );
        return null;
      case r'$unregisterTaskProvider':
        await target.$unregisterTaskProvider(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$fetchTasks':
        return await target.$fetchTasks(
          a.arg(0, decodeNullable(decodeMap), 'filter'),
        );
      case r'$getTaskExecution':
        return await target.$getTaskExecution(a.arg(0, decodeMap, 'value'));
      case r'$executeTask':
        return await target.$executeTask(a.arg(0, decodeMap, 'task'));
      case r'$terminateTask':
        await target.$terminateTask(a.arg(0, decodeString, 'id'));
        return null;
      case r'$registerTaskSystem':
        await target.$registerTaskSystem(
          a.arg(0, decodeString, 'scheme'),
          a.arg(1, decodeMap, 'info'),
        );
        return null;
      case r'$customExecutionComplete':
        await target.$customExecutionComplete(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeNullable(decodeNum), 'result'),
        );
        return null;
      case r'$registerSupportedExecutions':
        await target.$registerSupportedExecutions(
          a.arg(0, decodeNullable(decodeBool), 'custom'),
          a.arg(1, decodeNullable(decodeBool), 'shell'),
          a.arg(2, decodeNullable(decodeBool), 'process'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTask.$method');
    }
  }
}

// --- MainThreadWindow ----------------------------------------------------------

/// `MainThreadWindowShape` (`MainThreadWindow`).
abstract interface class MainThreadWindowShape {
  /// `$getInitialState(): Promise<{ isFocused: boolean; isActive: boolean }>`
  Future<Map<String, Object?>> $getInitialState();

  /// `$openUri(uri: UriComponents, uriString: string | undefined, options: IOpenUriOptions): Promise<boolean>`
  Future<bool> $openUri(
    VsUri uri,
    String? uriString,
    Map<String, Object?> options,
  );

  /// `$asExternalUri(uri: UriComponents, options: IOpenUriOptions): Promise<UriComponents>`
  Future<VsUri> $asExternalUri(VsUri uri, Map<String, Object?> options);
}

/// [MainThreadWindowShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadWindowUnsupported implements MainThreadWindowShape {
  const MainThreadWindowUnsupported();

  @override
  Future<Map<String, Object?>> $getInitialState() =>
      _unsupported('MainThreadWindow', r'$getInitialState');

  @override
  Future<bool> $openUri(
    VsUri uri,
    String? uriString,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadWindow', r'$openUri');

  @override
  Future<VsUri> $asExternalUri(VsUri uri, Map<String, Object?> options) =>
      _unsupported('MainThreadWindow', r'$asExternalUri');
}

/// Decodes requests to [MainContext.mainThreadWindow] and calls [target].
final class MainThreadWindowActor implements RpcActor {
  MainThreadWindowActor(this.target);

  static const identifier = MainContext.mainThreadWindow;

  final MainThreadWindowShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadWindow.$method', args);
    switch (method) {
      case r'$getInitialState':
        return await target.$getInitialState();
      case r'$openUri':
        return await target.$openUri(
          a.arg(0, decodeUri, 'uri'),
          a.arg(1, decodeNullable(decodeString), 'uriString'),
          a.arg(2, decodeMap, 'options'),
        );
      case r'$asExternalUri':
        return await target.$asExternalUri(
          a.arg(0, decodeUri, 'uri'),
          a.arg(1, decodeMap, 'options'),
        );
      default:
        throw RpcUnsupported('MainThreadWindow.$method');
    }
  }
}

// --- MainThreadPower -----------------------------------------------------------

/// `MainThreadPowerShape` (`MainThreadPower`).
abstract interface class MainThreadPowerShape {
  /// `$getSystemIdleState(idleThreshold: number): Promise<PowerSystemIdleState>`
  Future<String> $getSystemIdleState(num idleThreshold);

  /// `$getSystemIdleTime(): Promise<number>`
  Future<num> $getSystemIdleTime();

  /// `$getCurrentThermalState(): Promise<PowerThermalState>`
  Future<String> $getCurrentThermalState();

  /// `$isOnBatteryPower(): Promise<boolean>`
  Future<bool> $isOnBatteryPower();

  /// `$startPowerSaveBlocker(type: PowerSaveBlockerType): Promise<number>`
  Future<num> $startPowerSaveBlocker(String type);

  /// `$stopPowerSaveBlocker(id: number): Promise<boolean>`
  Future<bool> $stopPowerSaveBlocker(num id);

  /// `$isPowerSaveBlockerStarted(id: number): Promise<boolean>`
  Future<bool> $isPowerSaveBlockerStarted(num id);
}

/// [MainThreadPowerShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadPowerUnsupported implements MainThreadPowerShape {
  const MainThreadPowerUnsupported();

  @override
  Future<String> $getSystemIdleState(num idleThreshold) =>
      _unsupported('MainThreadPower', r'$getSystemIdleState');

  @override
  Future<num> $getSystemIdleTime() =>
      _unsupported('MainThreadPower', r'$getSystemIdleTime');

  @override
  Future<String> $getCurrentThermalState() =>
      _unsupported('MainThreadPower', r'$getCurrentThermalState');

  @override
  Future<bool> $isOnBatteryPower() =>
      _unsupported('MainThreadPower', r'$isOnBatteryPower');

  @override
  Future<num> $startPowerSaveBlocker(String type) =>
      _unsupported('MainThreadPower', r'$startPowerSaveBlocker');

  @override
  Future<bool> $stopPowerSaveBlocker(num id) =>
      _unsupported('MainThreadPower', r'$stopPowerSaveBlocker');

  @override
  Future<bool> $isPowerSaveBlockerStarted(num id) =>
      _unsupported('MainThreadPower', r'$isPowerSaveBlockerStarted');
}

/// Decodes requests to [MainContext.mainThreadPower] and calls [target].
final class MainThreadPowerActor implements RpcActor {
  MainThreadPowerActor(this.target);

  static const identifier = MainContext.mainThreadPower;

  final MainThreadPowerShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadPower.$method', args);
    switch (method) {
      case r'$getSystemIdleState':
        return await target.$getSystemIdleState(
          a.arg(0, decodeNum, 'idleThreshold'),
        );
      case r'$getSystemIdleTime':
        return await target.$getSystemIdleTime();
      case r'$getCurrentThermalState':
        return await target.$getCurrentThermalState();
      case r'$isOnBatteryPower':
        return await target.$isOnBatteryPower();
      case r'$startPowerSaveBlocker':
        return await target.$startPowerSaveBlocker(
          a.arg(0, decodeString, 'type'),
        );
      case r'$stopPowerSaveBlocker':
        return await target.$stopPowerSaveBlocker(a.arg(0, decodeNum, 'id'));
      case r'$isPowerSaveBlockerStarted':
        return await target.$isPowerSaveBlockerStarted(
          a.arg(0, decodeNum, 'id'),
        );
      default:
        throw RpcUnsupported('MainThreadPower.$method');
    }
  }
}

// --- MainThreadLabelService ----------------------------------------------------

/// `MainThreadLabelServiceShape` (`MainThreadLabelService`).
abstract interface class MainThreadLabelServiceShape {
  /// `$registerResourceLabelFormatter(handle: number, formatter: ResourceLabelFormatter): void`
  FutureOr<void> $registerResourceLabelFormatter(
    num handle,
    Map<String, Object?> formatter,
  );

  /// `$unregisterResourceLabelFormatter(handle: number): void`
  FutureOr<void> $unregisterResourceLabelFormatter(num handle);
}

/// [MainThreadLabelServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLabelServiceUnsupported
    implements MainThreadLabelServiceShape {
  const MainThreadLabelServiceUnsupported();

  @override
  FutureOr<void> $registerResourceLabelFormatter(
    num handle,
    Map<String, Object?> formatter,
  ) => _unsupported(
    'MainThreadLabelService',
    r'$registerResourceLabelFormatter',
  );

  @override
  FutureOr<void> $unregisterResourceLabelFormatter(num handle) => _unsupported(
    'MainThreadLabelService',
    r'$unregisterResourceLabelFormatter',
  );
}

/// Decodes requests to [MainContext.mainThreadLabelService] and calls [target].
final class MainThreadLabelServiceActor implements RpcActor {
  MainThreadLabelServiceActor(this.target);

  static const identifier = MainContext.mainThreadLabelService;

  final MainThreadLabelServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLabelService.$method', args);
    switch (method) {
      case r'$registerResourceLabelFormatter':
        await target.$registerResourceLabelFormatter(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'formatter'),
        );
        return null;
      case r'$unregisterResourceLabelFormatter':
        await target.$unregisterResourceLabelFormatter(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadLabelService.$method');
    }
  }
}

// --- MainThreadNotebook --------------------------------------------------------

/// `MainThreadNotebookShape` (`MainThreadNotebook`).
abstract interface class MainThreadNotebookShape {
  /// `$registerNotebookSerializer(handle: number, extension: notebookCommon.NotebookExtensionDescription, viewType: string, options: notebookCommon.TransientOptions, registration: notebookCommon.INotebookContributionData | undefined): void`
  FutureOr<void> $registerNotebookSerializer(
    num handle,
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?>? registration,
  );

  /// `$unregisterNotebookSerializer(handle: number): void`
  FutureOr<void> $unregisterNotebookSerializer(num handle);

  /// `$registerNotebookCellStatusBarItemProvider(handle: number, eventHandle: number | undefined, viewType: string): Promise<void>`
  FutureOr<void> $registerNotebookCellStatusBarItemProvider(
    num handle,
    num? eventHandle,
    String viewType,
  );

  /// `$unregisterNotebookCellStatusBarItemProvider(handle: number, eventHandle: number | undefined): Promise<void>`
  FutureOr<void> $unregisterNotebookCellStatusBarItemProvider(
    num handle,
    num? eventHandle,
  );

  /// `$emitCellStatusBarEvent(eventHandle: number): void`
  FutureOr<void> $emitCellStatusBarEvent(num eventHandle);
}

/// [MainThreadNotebookShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadNotebookUnsupported implements MainThreadNotebookShape {
  const MainThreadNotebookUnsupported();

  @override
  FutureOr<void> $registerNotebookSerializer(
    num handle,
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?>? registration,
  ) => _unsupported('MainThreadNotebook', r'$registerNotebookSerializer');

  @override
  FutureOr<void> $unregisterNotebookSerializer(num handle) =>
      _unsupported('MainThreadNotebook', r'$unregisterNotebookSerializer');

  @override
  FutureOr<void> $registerNotebookCellStatusBarItemProvider(
    num handle,
    num? eventHandle,
    String viewType,
  ) => _unsupported(
    'MainThreadNotebook',
    r'$registerNotebookCellStatusBarItemProvider',
  );

  @override
  FutureOr<void> $unregisterNotebookCellStatusBarItemProvider(
    num handle,
    num? eventHandle,
  ) => _unsupported(
    'MainThreadNotebook',
    r'$unregisterNotebookCellStatusBarItemProvider',
  );

  @override
  FutureOr<void> $emitCellStatusBarEvent(num eventHandle) =>
      _unsupported('MainThreadNotebook', r'$emitCellStatusBarEvent');
}

/// Decodes requests to [MainContext.mainThreadNotebook] and calls [target].
final class MainThreadNotebookActor implements RpcActor {
  MainThreadNotebookActor(this.target);

  static const identifier = MainContext.mainThreadNotebook;

  final MainThreadNotebookShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadNotebook.$method', args);
    switch (method) {
      case r'$registerNotebookSerializer':
        await target.$registerNotebookSerializer(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'extension'),
          a.arg(2, decodeString, 'viewType'),
          a.arg(3, decodeMap, 'options'),
          a.arg(4, decodeNullable(decodeMap), 'registration'),
        );
        return null;
      case r'$unregisterNotebookSerializer':
        await target.$unregisterNotebookSerializer(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$registerNotebookCellStatusBarItemProvider':
        await target.$registerNotebookCellStatusBarItemProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeNum), 'eventHandle'),
          a.arg(2, decodeString, 'viewType'),
        );
        return null;
      case r'$unregisterNotebookCellStatusBarItemProvider':
        await target.$unregisterNotebookCellStatusBarItemProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeNum), 'eventHandle'),
        );
        return null;
      case r'$emitCellStatusBarEvent':
        await target.$emitCellStatusBarEvent(
          a.arg(0, decodeNum, 'eventHandle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadNotebook.$method');
    }
  }
}

// --- MainThreadNotebookDocuments -----------------------------------------------

/// `MainThreadNotebookDocumentsShape` (`MainThreadNotebookDocumentsShape`).
abstract interface class MainThreadNotebookDocumentsShape {
  /// `$tryCreateNotebook(options: { viewType: string; content?: NotebookDataDto }): Promise<UriComponents>`
  Future<VsUri> $tryCreateNotebook(Map<String, Object?> options);

  /// `$tryOpenNotebook(uriComponents: UriComponents): Promise<UriComponents>`
  Future<VsUri> $tryOpenNotebook(VsUri uriComponents);

  /// `$trySaveNotebook(uri: UriComponents): Promise<boolean>`
  Future<bool> $trySaveNotebook(VsUri uri);
}

/// [MainThreadNotebookDocumentsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadNotebookDocumentsUnsupported
    implements MainThreadNotebookDocumentsShape {
  const MainThreadNotebookDocumentsUnsupported();

  @override
  Future<VsUri> $tryCreateNotebook(Map<String, Object?> options) =>
      _unsupported('MainThreadNotebookDocuments', r'$tryCreateNotebook');

  @override
  Future<VsUri> $tryOpenNotebook(VsUri uriComponents) =>
      _unsupported('MainThreadNotebookDocuments', r'$tryOpenNotebook');

  @override
  Future<bool> $trySaveNotebook(VsUri uri) =>
      _unsupported('MainThreadNotebookDocuments', r'$trySaveNotebook');
}

/// Decodes requests to [MainContext.mainThreadNotebookDocuments] and calls [target].
final class MainThreadNotebookDocumentsActor implements RpcActor {
  MainThreadNotebookDocumentsActor(this.target);

  static const identifier = MainContext.mainThreadNotebookDocuments;

  final MainThreadNotebookDocumentsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadNotebookDocuments.$method', args);
    switch (method) {
      case r'$tryCreateNotebook':
        return await target.$tryCreateNotebook(a.arg(0, decodeMap, 'options'));
      case r'$tryOpenNotebook':
        return await target.$tryOpenNotebook(
          a.arg(0, decodeUri, 'uriComponents'),
        );
      case r'$trySaveNotebook':
        return await target.$trySaveNotebook(a.arg(0, decodeUri, 'uri'));
      default:
        throw RpcUnsupported('MainThreadNotebookDocuments.$method');
    }
  }
}

// --- MainThreadNotebookEditors -------------------------------------------------

/// `MainThreadNotebookEditorsShape` (`MainThreadNotebookEditorsShape`).
abstract interface class MainThreadNotebookEditorsShape {
  /// `$tryShowNotebookDocument(uriComponents: UriComponents, viewType: string, options: INotebookDocumentShowOptions): Promise<string>`
  Future<String> $tryShowNotebookDocument(
    VsUri uriComponents,
    String viewType,
    Map<String, Object?> options,
  );

  /// `$tryRevealRange(id: string, range: ICellRange, revealType: NotebookEditorRevealType): Promise<void>`
  FutureOr<void> $tryRevealRange(
    String id,
    Map<String, Object?> range,
    int revealType,
  );

  /// `$trySetSelections(id: string, range: ICellRange[]): void`
  FutureOr<void> $trySetSelections(String id, List<Map<String, Object?>> range);
}

/// [MainThreadNotebookEditorsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadNotebookEditorsUnsupported
    implements MainThreadNotebookEditorsShape {
  const MainThreadNotebookEditorsUnsupported();

  @override
  Future<String> $tryShowNotebookDocument(
    VsUri uriComponents,
    String viewType,
    Map<String, Object?> options,
  ) => _unsupported('MainThreadNotebookEditors', r'$tryShowNotebookDocument');

  @override
  FutureOr<void> $tryRevealRange(
    String id,
    Map<String, Object?> range,
    int revealType,
  ) => _unsupported('MainThreadNotebookEditors', r'$tryRevealRange');

  @override
  FutureOr<void> $trySetSelections(
    String id,
    List<Map<String, Object?>> range,
  ) => _unsupported('MainThreadNotebookEditors', r'$trySetSelections');
}

/// Decodes requests to [MainContext.mainThreadNotebookEditors] and calls [target].
final class MainThreadNotebookEditorsActor implements RpcActor {
  MainThreadNotebookEditorsActor(this.target);

  static const identifier = MainContext.mainThreadNotebookEditors;

  final MainThreadNotebookEditorsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadNotebookEditors.$method', args);
    switch (method) {
      case r'$tryShowNotebookDocument':
        return await target.$tryShowNotebookDocument(
          a.arg(0, decodeUri, 'uriComponents'),
          a.arg(1, decodeString, 'viewType'),
          a.arg(2, decodeMap, 'options'),
        );
      case r'$tryRevealRange':
        await target.$tryRevealRange(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeMap, 'range'),
          a.arg(2, decodeInt, 'revealType'),
        );
        return null;
      case r'$trySetSelections':
        await target.$trySetSelections(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeListOf(decodeMap), 'range'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadNotebookEditors.$method');
    }
  }
}

// --- MainThreadNotebookKernels -------------------------------------------------

/// `MainThreadNotebookKernelsShape` (`MainThreadNotebookKernels`).
abstract interface class MainThreadNotebookKernelsShape {
  /// `$postMessage(handle: number, editorId: string | undefined, message: any): Promise<boolean>`
  Future<bool> $postMessage(num handle, String? editorId, Object? message);

  /// `$addKernel(handle: number, data: INotebookKernelDto2): Promise<void>`
  FutureOr<void> $addKernel(num handle, Map<String, Object?> data);

  /// `$updateKernel(handle: number, data: Partial<INotebookKernelDto2>): void`
  FutureOr<void> $updateKernel(num handle, Map<String, Object?> data);

  /// `$removeKernel(handle: number): void`
  FutureOr<void> $removeKernel(num handle);

  /// `$updateNotebookPriority(handle: number, uri: UriComponents, value: number | undefined): void`
  FutureOr<void> $updateNotebookPriority(num handle, VsUri uri, num? value);

  /// `$createExecution(handle: number, controllerId: string, uri: UriComponents, cellHandle: number): void`
  FutureOr<void> $createExecution(
    num handle,
    String controllerId,
    VsUri uri,
    num cellHandle,
  );

  /// `$updateExecution(handle: number, data: SerializableObjectWithBuffers<ICellExecuteUpdateDto[]>): void`
  FutureOr<void> $updateExecution(num handle, Object? data);

  /// `$completeExecution(handle: number, data: SerializableObjectWithBuffers<ICellExecutionCompleteDto>): void`
  FutureOr<void> $completeExecution(num handle, Object? data);

  /// `$createNotebookExecution(handle: number, controllerId: string, uri: UriComponents): void`
  FutureOr<void> $createNotebookExecution(
    num handle,
    String controllerId,
    VsUri uri,
  );

  /// `$beginNotebookExecution(handle: number): void`
  FutureOr<void> $beginNotebookExecution(num handle);

  /// `$completeNotebookExecution(handle: number): void`
  FutureOr<void> $completeNotebookExecution(num handle);

  /// `$addKernelDetectionTask(handle: number, notebookType: string): Promise<void>`
  FutureOr<void> $addKernelDetectionTask(num handle, String notebookType);

  /// `$removeKernelDetectionTask(handle: number): void`
  FutureOr<void> $removeKernelDetectionTask(num handle);

  /// `$addKernelSourceActionProvider(handle: number, eventHandle: number, notebookType: string): Promise<void>`
  FutureOr<void> $addKernelSourceActionProvider(
    num handle,
    num eventHandle,
    String notebookType,
  );

  /// `$removeKernelSourceActionProvider(handle: number, eventHandle: number): void`
  FutureOr<void> $removeKernelSourceActionProvider(num handle, num eventHandle);

  /// `$emitNotebookKernelSourceActionsChangeEvent(eventHandle: number): void`
  FutureOr<void> $emitNotebookKernelSourceActionsChangeEvent(num eventHandle);

  /// `$receiveVariable(requestId: string, variable: VariablesResult): void`
  FutureOr<void> $receiveVariable(
    String requestId,
    Map<String, Object?> variable,
  );

  /// `$variablesUpdated(notebookUri: UriComponents): void`
  FutureOr<void> $variablesUpdated(VsUri notebookUri);
}

/// [MainThreadNotebookKernelsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadNotebookKernelsUnsupported
    implements MainThreadNotebookKernelsShape {
  const MainThreadNotebookKernelsUnsupported();

  @override
  Future<bool> $postMessage(num handle, String? editorId, Object? message) =>
      _unsupported('MainThreadNotebookKernels', r'$postMessage');

  @override
  FutureOr<void> $addKernel(num handle, Map<String, Object?> data) =>
      _unsupported('MainThreadNotebookKernels', r'$addKernel');

  @override
  FutureOr<void> $updateKernel(num handle, Map<String, Object?> data) =>
      _unsupported('MainThreadNotebookKernels', r'$updateKernel');

  @override
  FutureOr<void> $removeKernel(num handle) =>
      _unsupported('MainThreadNotebookKernels', r'$removeKernel');

  @override
  FutureOr<void> $updateNotebookPriority(num handle, VsUri uri, num? value) =>
      _unsupported('MainThreadNotebookKernels', r'$updateNotebookPriority');

  @override
  FutureOr<void> $createExecution(
    num handle,
    String controllerId,
    VsUri uri,
    num cellHandle,
  ) => _unsupported('MainThreadNotebookKernels', r'$createExecution');

  @override
  FutureOr<void> $updateExecution(num handle, Object? data) =>
      _unsupported('MainThreadNotebookKernels', r'$updateExecution');

  @override
  FutureOr<void> $completeExecution(num handle, Object? data) =>
      _unsupported('MainThreadNotebookKernels', r'$completeExecution');

  @override
  FutureOr<void> $createNotebookExecution(
    num handle,
    String controllerId,
    VsUri uri,
  ) => _unsupported('MainThreadNotebookKernels', r'$createNotebookExecution');

  @override
  FutureOr<void> $beginNotebookExecution(num handle) =>
      _unsupported('MainThreadNotebookKernels', r'$beginNotebookExecution');

  @override
  FutureOr<void> $completeNotebookExecution(num handle) =>
      _unsupported('MainThreadNotebookKernels', r'$completeNotebookExecution');

  @override
  FutureOr<void> $addKernelDetectionTask(num handle, String notebookType) =>
      _unsupported('MainThreadNotebookKernels', r'$addKernelDetectionTask');

  @override
  FutureOr<void> $removeKernelDetectionTask(num handle) =>
      _unsupported('MainThreadNotebookKernels', r'$removeKernelDetectionTask');

  @override
  FutureOr<void> $addKernelSourceActionProvider(
    num handle,
    num eventHandle,
    String notebookType,
  ) => _unsupported(
    'MainThreadNotebookKernels',
    r'$addKernelSourceActionProvider',
  );

  @override
  FutureOr<void> $removeKernelSourceActionProvider(
    num handle,
    num eventHandle,
  ) => _unsupported(
    'MainThreadNotebookKernels',
    r'$removeKernelSourceActionProvider',
  );

  @override
  FutureOr<void> $emitNotebookKernelSourceActionsChangeEvent(num eventHandle) =>
      _unsupported(
        'MainThreadNotebookKernels',
        r'$emitNotebookKernelSourceActionsChangeEvent',
      );

  @override
  FutureOr<void> $receiveVariable(
    String requestId,
    Map<String, Object?> variable,
  ) => _unsupported('MainThreadNotebookKernels', r'$receiveVariable');

  @override
  FutureOr<void> $variablesUpdated(VsUri notebookUri) =>
      _unsupported('MainThreadNotebookKernels', r'$variablesUpdated');
}

/// Decodes requests to [MainContext.mainThreadNotebookKernels] and calls [target].
final class MainThreadNotebookKernelsActor implements RpcActor {
  MainThreadNotebookKernelsActor(this.target);

  static const identifier = MainContext.mainThreadNotebookKernels;

  final MainThreadNotebookKernelsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadNotebookKernels.$method', args);
    switch (method) {
      case r'$postMessage':
        return await target.$postMessage(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNullable(decodeString), 'editorId'),
          a.arg(2, decodeObject, 'message'),
        );
      case r'$addKernel':
        await target.$addKernel(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'data'),
        );
        return null;
      case r'$updateKernel':
        await target.$updateKernel(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'data'),
        );
        return null;
      case r'$removeKernel':
        await target.$removeKernel(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$updateNotebookPriority':
        await target.$updateNotebookPriority(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'uri'),
          a.arg(2, decodeNullable(decodeNum), 'value'),
        );
        return null;
      case r'$createExecution':
        await target.$createExecution(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'controllerId'),
          a.arg(2, decodeUri, 'uri'),
          a.arg(3, decodeNum, 'cellHandle'),
        );
        return null;
      case r'$updateExecution':
        await target.$updateExecution(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeObject, 'data'),
        );
        return null;
      case r'$completeExecution':
        await target.$completeExecution(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeObject, 'data'),
        );
        return null;
      case r'$createNotebookExecution':
        await target.$createNotebookExecution(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'controllerId'),
          a.arg(2, decodeUri, 'uri'),
        );
        return null;
      case r'$beginNotebookExecution':
        await target.$beginNotebookExecution(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$completeNotebookExecution':
        await target.$completeNotebookExecution(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$addKernelDetectionTask':
        await target.$addKernelDetectionTask(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'notebookType'),
        );
        return null;
      case r'$removeKernelDetectionTask':
        await target.$removeKernelDetectionTask(a.arg(0, decodeNum, 'handle'));
        return null;
      case r'$addKernelSourceActionProvider':
        await target.$addKernelSourceActionProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'eventHandle'),
          a.arg(2, decodeString, 'notebookType'),
        );
        return null;
      case r'$removeKernelSourceActionProvider':
        await target.$removeKernelSourceActionProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeNum, 'eventHandle'),
        );
        return null;
      case r'$emitNotebookKernelSourceActionsChangeEvent':
        await target.$emitNotebookKernelSourceActionsChangeEvent(
          a.arg(0, decodeNum, 'eventHandle'),
        );
        return null;
      case r'$receiveVariable':
        await target.$receiveVariable(
          a.arg(0, decodeString, 'requestId'),
          a.arg(1, decodeMap, 'variable'),
        );
        return null;
      case r'$variablesUpdated':
        await target.$variablesUpdated(a.arg(0, decodeUri, 'notebookUri'));
        return null;
      default:
        throw RpcUnsupported('MainThreadNotebookKernels.$method');
    }
  }
}

// --- MainThreadNotebookRenderers -----------------------------------------------

/// `MainThreadNotebookRenderersShape` (`MainThreadNotebookRenderers`).
abstract interface class MainThreadNotebookRenderersShape {
  /// `$postMessage(editorId: string | undefined, rendererId: string, message: unknown): Promise<boolean>`
  Future<bool> $postMessage(
    String? editorId,
    String rendererId,
    Object? message,
  );
}

/// [MainThreadNotebookRenderersShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadNotebookRenderersUnsupported
    implements MainThreadNotebookRenderersShape {
  const MainThreadNotebookRenderersUnsupported();

  @override
  Future<bool> $postMessage(
    String? editorId,
    String rendererId,
    Object? message,
  ) => _unsupported('MainThreadNotebookRenderers', r'$postMessage');
}

/// Decodes requests to [MainContext.mainThreadNotebookRenderers] and calls [target].
final class MainThreadNotebookRenderersActor implements RpcActor {
  MainThreadNotebookRenderersActor(this.target);

  static const identifier = MainContext.mainThreadNotebookRenderers;

  final MainThreadNotebookRenderersShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadNotebookRenderers.$method', args);
    switch (method) {
      case r'$postMessage':
        return await target.$postMessage(
          a.arg(0, decodeNullable(decodeString), 'editorId'),
          a.arg(1, decodeString, 'rendererId'),
          a.arg(2, decodeObject, 'message'),
        );
      default:
        throw RpcUnsupported('MainThreadNotebookRenderers.$method');
    }
  }
}

// --- MainThreadInteractive -----------------------------------------------------

/// `MainThreadInteractiveShape` (`MainThreadInteractive`).
abstract interface class MainThreadInteractiveShape {}

/// [MainThreadInteractiveShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadInteractiveUnsupported
    implements MainThreadInteractiveShape {
  const MainThreadInteractiveUnsupported();
}

/// Decodes requests to [MainContext.mainThreadInteractive] and calls [target].
final class MainThreadInteractiveActor implements RpcActor {
  MainThreadInteractiveActor(this.target);

  static const identifier = MainContext.mainThreadInteractive;

  final MainThreadInteractiveShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    throw RpcUnsupported('MainThreadInteractive.$method');
  }
}

// --- MainThreadTheming ---------------------------------------------------------

/// `MainThreadThemingShape` (`MainThreadTheming`).
abstract interface class MainThreadThemingShape {}

/// [MainThreadThemingShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadThemingUnsupported implements MainThreadThemingShape {
  const MainThreadThemingUnsupported();
}

/// Decodes requests to [MainContext.mainThreadTheming] and calls [target].
final class MainThreadThemingActor implements RpcActor {
  MainThreadThemingActor(this.target);

  static const identifier = MainContext.mainThreadTheming;

  final MainThreadThemingShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    throw RpcUnsupported('MainThreadTheming.$method');
  }
}

// --- MainThreadTunnelService ---------------------------------------------------

/// `MainThreadTunnelServiceShape` (`MainThreadTunnelService`).
abstract interface class MainThreadTunnelServiceShape {
  /// `$openTunnel(tunnelOptions: TunnelOptions, source: string | undefined): Promise<TunnelDto | undefined>`
  Future<Map<String, Object?>?> $openTunnel(
    Map<String, Object?> tunnelOptions,
    String? source,
  );

  /// `$closeTunnel(remote: { host: string; port: number }): Promise<void>`
  FutureOr<void> $closeTunnel(Map<String, Object?> remote);

  /// `$getTunnels(): Promise<TunnelDescription[]>`
  Future<List<Map<String, Object?>>> $getTunnels();

  /// `$setTunnelProvider(features: TunnelProviderFeatures | undefined, enablePortsView: boolean): Promise<void>`
  FutureOr<void> $setTunnelProvider(
    Map<String, Object?>? features,
    bool enablePortsView,
  );

  /// `$hasTunnelProvider(): Promise<boolean>`
  Future<bool> $hasTunnelProvider();

  /// `$setRemoteTunnelService(processId: number): Promise<void>`
  FutureOr<void> $setRemoteTunnelService(num processId);

  /// `$setCandidateFilter(): Promise<void>`
  FutureOr<void> $setCandidateFilter();

  /// `$onFoundNewCandidates(candidates: CandidatePort[]): Promise<void>`
  FutureOr<void> $onFoundNewCandidates(List<Map<String, Object?>> candidates);

  /// `$setCandidatePortSource(source: CandidatePortSource): Promise<void>`
  FutureOr<void> $setCandidatePortSource(int source);

  /// `$registerPortsAttributesProvider(selector: PortAttributesSelector, providerHandle: number): Promise<void>`
  FutureOr<void> $registerPortsAttributesProvider(
    Map<String, Object?> selector,
    num providerHandle,
  );

  /// `$unregisterPortsAttributesProvider(providerHandle: number): Promise<void>`
  FutureOr<void> $unregisterPortsAttributesProvider(num providerHandle);
}

/// [MainThreadTunnelServiceShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTunnelServiceUnsupported
    implements MainThreadTunnelServiceShape {
  const MainThreadTunnelServiceUnsupported();

  @override
  Future<Map<String, Object?>?> $openTunnel(
    Map<String, Object?> tunnelOptions,
    String? source,
  ) => _unsupported('MainThreadTunnelService', r'$openTunnel');

  @override
  FutureOr<void> $closeTunnel(Map<String, Object?> remote) =>
      _unsupported('MainThreadTunnelService', r'$closeTunnel');

  @override
  Future<List<Map<String, Object?>>> $getTunnels() =>
      _unsupported('MainThreadTunnelService', r'$getTunnels');

  @override
  FutureOr<void> $setTunnelProvider(
    Map<String, Object?>? features,
    bool enablePortsView,
  ) => _unsupported('MainThreadTunnelService', r'$setTunnelProvider');

  @override
  Future<bool> $hasTunnelProvider() =>
      _unsupported('MainThreadTunnelService', r'$hasTunnelProvider');

  @override
  FutureOr<void> $setRemoteTunnelService(num processId) =>
      _unsupported('MainThreadTunnelService', r'$setRemoteTunnelService');

  @override
  FutureOr<void> $setCandidateFilter() =>
      _unsupported('MainThreadTunnelService', r'$setCandidateFilter');

  @override
  FutureOr<void> $onFoundNewCandidates(List<Map<String, Object?>> candidates) =>
      _unsupported('MainThreadTunnelService', r'$onFoundNewCandidates');

  @override
  FutureOr<void> $setCandidatePortSource(int source) =>
      _unsupported('MainThreadTunnelService', r'$setCandidatePortSource');

  @override
  FutureOr<void> $registerPortsAttributesProvider(
    Map<String, Object?> selector,
    num providerHandle,
  ) => _unsupported(
    'MainThreadTunnelService',
    r'$registerPortsAttributesProvider',
  );

  @override
  FutureOr<void> $unregisterPortsAttributesProvider(num providerHandle) =>
      _unsupported(
        'MainThreadTunnelService',
        r'$unregisterPortsAttributesProvider',
      );
}

/// Decodes requests to [MainContext.mainThreadTunnelService] and calls [target].
final class MainThreadTunnelServiceActor implements RpcActor {
  MainThreadTunnelServiceActor(this.target);

  static const identifier = MainContext.mainThreadTunnelService;

  final MainThreadTunnelServiceShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTunnelService.$method', args);
    switch (method) {
      case r'$openTunnel':
        return await target.$openTunnel(
          a.arg(0, decodeMap, 'tunnelOptions'),
          a.arg(1, decodeNullable(decodeString), 'source'),
        );
      case r'$closeTunnel':
        await target.$closeTunnel(a.arg(0, decodeMap, 'remote'));
        return null;
      case r'$getTunnels':
        return await target.$getTunnels();
      case r'$setTunnelProvider':
        await target.$setTunnelProvider(
          a.arg(0, decodeNullable(decodeMap), 'features'),
          a.arg(1, decodeBool, 'enablePortsView'),
        );
        return null;
      case r'$hasTunnelProvider':
        return await target.$hasTunnelProvider();
      case r'$setRemoteTunnelService':
        await target.$setRemoteTunnelService(a.arg(0, decodeNum, 'processId'));
        return null;
      case r'$setCandidateFilter':
        await target.$setCandidateFilter();
        return null;
      case r'$onFoundNewCandidates':
        await target.$onFoundNewCandidates(
          a.arg(0, decodeListOf(decodeMap), 'candidates'),
        );
        return null;
      case r'$setCandidatePortSource':
        await target.$setCandidatePortSource(a.arg(0, decodeInt, 'source'));
        return null;
      case r'$registerPortsAttributesProvider':
        await target.$registerPortsAttributesProvider(
          a.arg(0, decodeMap, 'selector'),
          a.arg(1, decodeNum, 'providerHandle'),
        );
        return null;
      case r'$unregisterPortsAttributesProvider':
        await target.$unregisterPortsAttributesProvider(
          a.arg(0, decodeNum, 'providerHandle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTunnelService.$method');
    }
  }
}

// --- MainThreadManagedSockets --------------------------------------------------

/// `MainThreadManagedSocketsShape` (`MainThreadManagedSockets`).
abstract interface class MainThreadManagedSocketsShape {
  /// `$registerSocketFactory(socketFactoryId: number): Promise<void>`
  FutureOr<void> $registerSocketFactory(num socketFactoryId);

  /// `$unregisterSocketFactory(socketFactoryId: number): Promise<void>`
  FutureOr<void> $unregisterSocketFactory(num socketFactoryId);

  /// `$onDidManagedSocketHaveData(socketId: number, data: VSBuffer): void`
  FutureOr<void> $onDidManagedSocketHaveData(num socketId, RpcBuffer data);

  /// `$onDidManagedSocketClose(socketId: number, error: string | undefined): void`
  FutureOr<void> $onDidManagedSocketClose(num socketId, String? error);

  /// `$onDidManagedSocketEnd(socketId: number): void`
  FutureOr<void> $onDidManagedSocketEnd(num socketId);
}

/// [MainThreadManagedSocketsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadManagedSocketsUnsupported
    implements MainThreadManagedSocketsShape {
  const MainThreadManagedSocketsUnsupported();

  @override
  FutureOr<void> $registerSocketFactory(num socketFactoryId) =>
      _unsupported('MainThreadManagedSockets', r'$registerSocketFactory');

  @override
  FutureOr<void> $unregisterSocketFactory(num socketFactoryId) =>
      _unsupported('MainThreadManagedSockets', r'$unregisterSocketFactory');

  @override
  FutureOr<void> $onDidManagedSocketHaveData(num socketId, RpcBuffer data) =>
      _unsupported('MainThreadManagedSockets', r'$onDidManagedSocketHaveData');

  @override
  FutureOr<void> $onDidManagedSocketClose(num socketId, String? error) =>
      _unsupported('MainThreadManagedSockets', r'$onDidManagedSocketClose');

  @override
  FutureOr<void> $onDidManagedSocketEnd(num socketId) =>
      _unsupported('MainThreadManagedSockets', r'$onDidManagedSocketEnd');
}

/// Decodes requests to [MainContext.mainThreadManagedSockets] and calls [target].
final class MainThreadManagedSocketsActor implements RpcActor {
  MainThreadManagedSocketsActor(this.target);

  static const identifier = MainContext.mainThreadManagedSockets;

  final MainThreadManagedSocketsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadManagedSockets.$method', args);
    switch (method) {
      case r'$registerSocketFactory':
        await target.$registerSocketFactory(
          a.arg(0, decodeNum, 'socketFactoryId'),
        );
        return null;
      case r'$unregisterSocketFactory':
        await target.$unregisterSocketFactory(
          a.arg(0, decodeNum, 'socketFactoryId'),
        );
        return null;
      case r'$onDidManagedSocketHaveData':
        await target.$onDidManagedSocketHaveData(
          a.arg(0, decodeNum, 'socketId'),
          a.arg(1, decodeBuffer, 'data'),
        );
        return null;
      case r'$onDidManagedSocketClose':
        await target.$onDidManagedSocketClose(
          a.arg(0, decodeNum, 'socketId'),
          a.arg(1, decodeNullable(decodeString), 'error'),
        );
        return null;
      case r'$onDidManagedSocketEnd':
        await target.$onDidManagedSocketEnd(a.arg(0, decodeNum, 'socketId'));
        return null;
      default:
        throw RpcUnsupported('MainThreadManagedSockets.$method');
    }
  }
}

// --- MainThreadBrowserTunnelProxy ----------------------------------------------

/// `MainThreadBrowserTunnelProxyShape` (`MainThreadBrowserTunnelProxy`).
abstract interface class MainThreadBrowserTunnelProxyShape {
  /// `$updateProxyInfo(info: ITunnelProxyInfo | undefined): void`
  FutureOr<void> $updateProxyInfo(Map<String, Object?>? info);
}

/// [MainThreadBrowserTunnelProxyShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadBrowserTunnelProxyUnsupported
    implements MainThreadBrowserTunnelProxyShape {
  const MainThreadBrowserTunnelProxyUnsupported();

  @override
  FutureOr<void> $updateProxyInfo(Map<String, Object?>? info) =>
      _unsupported('MainThreadBrowserTunnelProxy', r'$updateProxyInfo');
}

/// Decodes requests to [MainContext.mainThreadBrowserTunnelProxy] and calls [target].
final class MainThreadBrowserTunnelProxyActor implements RpcActor {
  MainThreadBrowserTunnelProxyActor(this.target);

  static const identifier = MainContext.mainThreadBrowserTunnelProxy;

  final MainThreadBrowserTunnelProxyShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadBrowserTunnelProxy.$method', args);
    switch (method) {
      case r'$updateProxyInfo':
        await target.$updateProxyInfo(
          a.arg(0, decodeNullable(decodeMap), 'info'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadBrowserTunnelProxy.$method');
    }
  }
}

// --- MainThreadTimeline --------------------------------------------------------

/// `MainThreadTimelineShape` (`MainThreadTimeline`).
abstract interface class MainThreadTimelineShape {
  /// `$registerTimelineProvider(provider: TimelineProviderDescriptor): void`
  FutureOr<void> $registerTimelineProvider(Map<String, Object?> provider);

  /// `$unregisterTimelineProvider(source: string): void`
  FutureOr<void> $unregisterTimelineProvider(String source);

  /// `$emitTimelineChangeEvent(e: TimelineChangeEvent | undefined): void`
  FutureOr<void> $emitTimelineChangeEvent(Map<String, Object?>? e);
}

/// [MainThreadTimelineShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTimelineUnsupported implements MainThreadTimelineShape {
  const MainThreadTimelineUnsupported();

  @override
  FutureOr<void> $registerTimelineProvider(Map<String, Object?> provider) =>
      _unsupported('MainThreadTimeline', r'$registerTimelineProvider');

  @override
  FutureOr<void> $unregisterTimelineProvider(String source) =>
      _unsupported('MainThreadTimeline', r'$unregisterTimelineProvider');

  @override
  FutureOr<void> $emitTimelineChangeEvent(Map<String, Object?>? e) =>
      _unsupported('MainThreadTimeline', r'$emitTimelineChangeEvent');
}

/// Decodes requests to [MainContext.mainThreadTimeline] and calls [target].
final class MainThreadTimelineActor implements RpcActor {
  MainThreadTimelineActor(this.target);

  static const identifier = MainContext.mainThreadTimeline;

  final MainThreadTimelineShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTimeline.$method', args);
    switch (method) {
      case r'$registerTimelineProvider':
        await target.$registerTimelineProvider(a.arg(0, decodeMap, 'provider'));
        return null;
      case r'$unregisterTimelineProvider':
        await target.$unregisterTimelineProvider(
          a.arg(0, decodeString, 'source'),
        );
        return null;
      case r'$emitTimelineChangeEvent':
        await target.$emitTimelineChangeEvent(
          a.arg(0, decodeNullable(decodeMap), 'e'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTimeline.$method');
    }
  }
}

// --- MainThreadTesting ---------------------------------------------------------

/// `MainThreadTestingShape` (`MainThreadTesting`).
abstract interface class MainThreadTestingShape {
  /// Registers that there's a test controller with the given ID
  ///
  /// `$registerTestController(controllerId: string, label: string, capability: TestControllerCapability): void`
  FutureOr<void> $registerTestController(
    String controllerId,
    String label,
    int capability,
  );

  /// Updates the label of an existing test controller.
  ///
  /// `$updateController(controllerId: string, patch: ITestControllerPatch): void`
  FutureOr<void> $updateController(
    String controllerId,
    Map<String, Object?> patch,
  );

  /// Diposes of the test controller with the given ID
  ///
  /// `$unregisterTestController(controllerId: string): void`
  FutureOr<void> $unregisterTestController(String controllerId);

  /// Requests tests published to VS Code.
  ///
  /// `$subscribeToDiffs(): void`
  FutureOr<void> $subscribeToDiffs();

  /// Stops requesting tests published to VS Code.
  ///
  /// `$unsubscribeFromDiffs(): void`
  FutureOr<void> $unsubscribeFromDiffs();

  /// Publishes that new tests were available on the given source.
  ///
  /// `$publishDiff(controllerId: string, diff: TestsDiffOp.Serialized[]): void`
  FutureOr<void> $publishDiff(
    String controllerId,
    List<Map<String, Object?>> diff,
  );

  /// Gets coverage details from a test result.
  ///
  /// `$getCoverageDetails(resultId: string, taskIndex: number, uri: UriComponents, token: CancellationToken): Promise<CoverageDetails.Serialized[]>`
  Future<List<Map<String, Object?>>> $getCoverageDetails(
    String resultId,
    num taskIndex,
    VsUri uri,
    CancellationToken token,
  );

  /// Called when a new test run configuration is available
  ///
  /// `$publishTestRunProfile(config: ITestRunProfile): void`
  FutureOr<void> $publishTestRunProfile(Map<String, Object?> config);

  /// Updates an existing test run configuration
  ///
  /// `$updateTestRunConfig(controllerId: string, configId: number, update: Partial<ITestRunProfile>): void`
  FutureOr<void> $updateTestRunConfig(
    String controllerId,
    num configId,
    Map<String, Object?> update,
  );

  /// Removes a previously-published test run config
  ///
  /// `$removeTestProfile(controllerId: string, configId: number): void`
  FutureOr<void> $removeTestProfile(String controllerId, num configId);

  /// Request by an extension to run tests.
  ///
  /// `$runTests(req: ResolvedTestRunRequest, token: CancellationToken): Promise<string>`
  Future<String> $runTests(Map<String, Object?> req, CancellationToken token);

  /// Adds tests to the run. The tests are given in descending depth. The first
  /// item will be a previously-known test, or a test root.
  ///
  /// `$addTestsToRun(controllerId: string, runId: string, tests: ITestItem.Serialized[]): void`
  FutureOr<void> $addTestsToRun(
    String controllerId,
    String runId,
    List<Map<String, Object?>> tests,
  );

  /// Updates the state of a test run in the given run.
  ///
  /// `$updateTestStateInRun(runId: string, taskId: string, testId: string, state: TestResultState, duration?: number): void`
  FutureOr<void> $updateTestStateInRun(
    String runId,
    String taskId,
    String testId,
    int state,
    num? duration,
  );

  /// Appends a message to a test in the run.
  ///
  /// `$appendTestMessagesInRun(runId: string, taskId: string, testId: string, messages: ITestMessage.Serialized[]): void`
  FutureOr<void> $appendTestMessagesInRun(
    String runId,
    String taskId,
    String testId,
    List<Map<String, Object?>> messages,
  );

  /// Appends raw output to the test run..
  ///
  /// `$appendOutputToRun(runId: string, taskId: string, output: VSBuffer, location?: ILocationDto, testId?: string): void`
  FutureOr<void> $appendOutputToRun(
    String runId,
    String taskId,
    RpcBuffer output,
    Map<String, Object?>? location,
    String? testId,
  );

  /// Triggered when coverage is added to test results.
  ///
  /// `$appendCoverage(runId: string, taskId: string, coverage: IFileCoverage.Serialized): void`
  FutureOr<void> $appendCoverage(
    String runId,
    String taskId,
    Map<String, Object?> coverage,
  );

  /// Signals a task in a test run started.
  ///
  /// `$startedTestRunTask(runId: string, task: ITestRunTask): void`
  FutureOr<void> $startedTestRunTask(String runId, Map<String, Object?> task);

  /// Signals a task in a test run ended.
  ///
  /// `$finishedTestRunTask(runId: string, taskId: string): void`
  FutureOr<void> $finishedTestRunTask(String runId, String taskId);

  /// Start a new extension-provided test run.
  ///
  /// `$startedExtensionTestRun(req: ExtensionRunTestsRequest): void`
  FutureOr<void> $startedExtensionTestRun(Map<String, Object?> req);

  /// Signals that an extension-provided test run finished.
  ///
  /// `$finishedExtensionTestRun(runId: string): void`
  FutureOr<void> $finishedExtensionTestRun(String runId);

  /// Marks a test (or controller) as retired in all results.
  ///
  /// `$markTestRetired(testIds: string[] | undefined): void`
  FutureOr<void> $markTestRetired(List<String>? testIds);
}

/// [MainThreadTestingShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadTestingUnsupported implements MainThreadTestingShape {
  const MainThreadTestingUnsupported();

  @override
  FutureOr<void> $registerTestController(
    String controllerId,
    String label,
    int capability,
  ) => _unsupported('MainThreadTesting', r'$registerTestController');

  @override
  FutureOr<void> $updateController(
    String controllerId,
    Map<String, Object?> patch,
  ) => _unsupported('MainThreadTesting', r'$updateController');

  @override
  FutureOr<void> $unregisterTestController(String controllerId) =>
      _unsupported('MainThreadTesting', r'$unregisterTestController');

  @override
  FutureOr<void> $subscribeToDiffs() =>
      _unsupported('MainThreadTesting', r'$subscribeToDiffs');

  @override
  FutureOr<void> $unsubscribeFromDiffs() =>
      _unsupported('MainThreadTesting', r'$unsubscribeFromDiffs');

  @override
  FutureOr<void> $publishDiff(
    String controllerId,
    List<Map<String, Object?>> diff,
  ) => _unsupported('MainThreadTesting', r'$publishDiff');

  @override
  Future<List<Map<String, Object?>>> $getCoverageDetails(
    String resultId,
    num taskIndex,
    VsUri uri,
    CancellationToken token,
  ) => _unsupported('MainThreadTesting', r'$getCoverageDetails');

  @override
  FutureOr<void> $publishTestRunProfile(Map<String, Object?> config) =>
      _unsupported('MainThreadTesting', r'$publishTestRunProfile');

  @override
  FutureOr<void> $updateTestRunConfig(
    String controllerId,
    num configId,
    Map<String, Object?> update,
  ) => _unsupported('MainThreadTesting', r'$updateTestRunConfig');

  @override
  FutureOr<void> $removeTestProfile(String controllerId, num configId) =>
      _unsupported('MainThreadTesting', r'$removeTestProfile');

  @override
  Future<String> $runTests(Map<String, Object?> req, CancellationToken token) =>
      _unsupported('MainThreadTesting', r'$runTests');

  @override
  FutureOr<void> $addTestsToRun(
    String controllerId,
    String runId,
    List<Map<String, Object?>> tests,
  ) => _unsupported('MainThreadTesting', r'$addTestsToRun');

  @override
  FutureOr<void> $updateTestStateInRun(
    String runId,
    String taskId,
    String testId,
    int state,
    num? duration,
  ) => _unsupported('MainThreadTesting', r'$updateTestStateInRun');

  @override
  FutureOr<void> $appendTestMessagesInRun(
    String runId,
    String taskId,
    String testId,
    List<Map<String, Object?>> messages,
  ) => _unsupported('MainThreadTesting', r'$appendTestMessagesInRun');

  @override
  FutureOr<void> $appendOutputToRun(
    String runId,
    String taskId,
    RpcBuffer output,
    Map<String, Object?>? location,
    String? testId,
  ) => _unsupported('MainThreadTesting', r'$appendOutputToRun');

  @override
  FutureOr<void> $appendCoverage(
    String runId,
    String taskId,
    Map<String, Object?> coverage,
  ) => _unsupported('MainThreadTesting', r'$appendCoverage');

  @override
  FutureOr<void> $startedTestRunTask(String runId, Map<String, Object?> task) =>
      _unsupported('MainThreadTesting', r'$startedTestRunTask');

  @override
  FutureOr<void> $finishedTestRunTask(String runId, String taskId) =>
      _unsupported('MainThreadTesting', r'$finishedTestRunTask');

  @override
  FutureOr<void> $startedExtensionTestRun(Map<String, Object?> req) =>
      _unsupported('MainThreadTesting', r'$startedExtensionTestRun');

  @override
  FutureOr<void> $finishedExtensionTestRun(String runId) =>
      _unsupported('MainThreadTesting', r'$finishedExtensionTestRun');

  @override
  FutureOr<void> $markTestRetired(List<String>? testIds) =>
      _unsupported('MainThreadTesting', r'$markTestRetired');
}

/// Decodes requests to [MainContext.mainThreadTesting] and calls [target].
final class MainThreadTestingActor implements RpcActor {
  MainThreadTestingActor(this.target);

  static const identifier = MainContext.mainThreadTesting;

  final MainThreadTestingShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadTesting.$method', args);
    switch (method) {
      case r'$registerTestController':
        await target.$registerTestController(
          a.arg(0, decodeString, 'controllerId'),
          a.arg(1, decodeString, 'label'),
          a.arg(2, decodeInt, 'capability'),
        );
        return null;
      case r'$updateController':
        await target.$updateController(
          a.arg(0, decodeString, 'controllerId'),
          a.arg(1, decodeMap, 'patch'),
        );
        return null;
      case r'$unregisterTestController':
        await target.$unregisterTestController(
          a.arg(0, decodeString, 'controllerId'),
        );
        return null;
      case r'$subscribeToDiffs':
        await target.$subscribeToDiffs();
        return null;
      case r'$unsubscribeFromDiffs':
        await target.$unsubscribeFromDiffs();
        return null;
      case r'$publishDiff':
        await target.$publishDiff(
          a.arg(0, decodeString, 'controllerId'),
          a.arg(1, decodeListOf(decodeMap), 'diff'),
        );
        return null;
      case r'$getCoverageDetails':
        return await target.$getCoverageDetails(
          a.arg(0, decodeString, 'resultId'),
          a.arg(1, decodeNum, 'taskIndex'),
          a.arg(2, decodeUri, 'uri'),
          a.token,
        );
      case r'$publishTestRunProfile':
        await target.$publishTestRunProfile(a.arg(0, decodeMap, 'config'));
        return null;
      case r'$updateTestRunConfig':
        await target.$updateTestRunConfig(
          a.arg(0, decodeString, 'controllerId'),
          a.arg(1, decodeNum, 'configId'),
          a.arg(2, decodeMap, 'update'),
        );
        return null;
      case r'$removeTestProfile':
        await target.$removeTestProfile(
          a.arg(0, decodeString, 'controllerId'),
          a.arg(1, decodeNum, 'configId'),
        );
        return null;
      case r'$runTests':
        return await target.$runTests(a.arg(0, decodeMap, 'req'), a.token);
      case r'$addTestsToRun':
        await target.$addTestsToRun(
          a.arg(0, decodeString, 'controllerId'),
          a.arg(1, decodeString, 'runId'),
          a.arg(2, decodeListOf(decodeMap), 'tests'),
        );
        return null;
      case r'$updateTestStateInRun':
        await target.$updateTestStateInRun(
          a.arg(0, decodeString, 'runId'),
          a.arg(1, decodeString, 'taskId'),
          a.arg(2, decodeString, 'testId'),
          a.arg(3, decodeInt, 'state'),
          a.arg(4, decodeNullable(decodeNum), 'duration'),
        );
        return null;
      case r'$appendTestMessagesInRun':
        await target.$appendTestMessagesInRun(
          a.arg(0, decodeString, 'runId'),
          a.arg(1, decodeString, 'taskId'),
          a.arg(2, decodeString, 'testId'),
          a.arg(3, decodeListOf(decodeMap), 'messages'),
        );
        return null;
      case r'$appendOutputToRun':
        await target.$appendOutputToRun(
          a.arg(0, decodeString, 'runId'),
          a.arg(1, decodeString, 'taskId'),
          a.arg(2, decodeBuffer, 'output'),
          a.arg(3, decodeNullable(decodeMap), 'location'),
          a.arg(4, decodeNullable(decodeString), 'testId'),
        );
        return null;
      case r'$appendCoverage':
        await target.$appendCoverage(
          a.arg(0, decodeString, 'runId'),
          a.arg(1, decodeString, 'taskId'),
          a.arg(2, decodeMap, 'coverage'),
        );
        return null;
      case r'$startedTestRunTask':
        await target.$startedTestRunTask(
          a.arg(0, decodeString, 'runId'),
          a.arg(1, decodeMap, 'task'),
        );
        return null;
      case r'$finishedTestRunTask':
        await target.$finishedTestRunTask(
          a.arg(0, decodeString, 'runId'),
          a.arg(1, decodeString, 'taskId'),
        );
        return null;
      case r'$startedExtensionTestRun':
        await target.$startedExtensionTestRun(a.arg(0, decodeMap, 'req'));
        return null;
      case r'$finishedExtensionTestRun':
        await target.$finishedExtensionTestRun(a.arg(0, decodeString, 'runId'));
        return null;
      case r'$markTestRetired':
        await target.$markTestRetired(
          a.arg(0, decodeNullable(decodeListOf(decodeString)), 'testIds'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadTesting.$method');
    }
  }
}

// --- MainThreadLocalization ----------------------------------------------------

/// `MainThreadLocalizationShape` (`MainThreadLocalizationShape`).
abstract interface class MainThreadLocalizationShape {
  /// `$fetchBuiltInBundleUri(id: string, language: string): Promise<UriComponents | undefined>`
  Future<VsUri?> $fetchBuiltInBundleUri(String id, String language);

  /// `$fetchBundleContents(uriComponents: UriComponents): Promise<string>`
  Future<String> $fetchBundleContents(VsUri uriComponents);
}

/// [MainThreadLocalizationShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadLocalizationUnsupported
    implements MainThreadLocalizationShape {
  const MainThreadLocalizationUnsupported();

  @override
  Future<VsUri?> $fetchBuiltInBundleUri(String id, String language) =>
      _unsupported('MainThreadLocalization', r'$fetchBuiltInBundleUri');

  @override
  Future<String> $fetchBundleContents(VsUri uriComponents) =>
      _unsupported('MainThreadLocalization', r'$fetchBundleContents');
}

/// Decodes requests to [MainContext.mainThreadLocalization] and calls [target].
final class MainThreadLocalizationActor implements RpcActor {
  MainThreadLocalizationActor(this.target);

  static const identifier = MainContext.mainThreadLocalization;

  final MainThreadLocalizationShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadLocalization.$method', args);
    switch (method) {
      case r'$fetchBuiltInBundleUri':
        return await target.$fetchBuiltInBundleUri(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeString, 'language'),
        );
      case r'$fetchBundleContents':
        return await target.$fetchBundleContents(
          a.arg(0, decodeUri, 'uriComponents'),
        );
      default:
        throw RpcUnsupported('MainThreadLocalization.$method');
    }
  }
}

// --- MainThreadMcp -------------------------------------------------------------

/// `MainThreadMcpShape` (`MainThreadMcpShape`).
abstract interface class MainThreadMcpShape {
  /// `$onDidChangeState(id: number, state: McpConnectionState): void`
  FutureOr<void> $onDidChangeState(num id, Map<String, Object?> state);

  /// `$onDidPublishLog(id: number, level: LogLevel, log: string): void`
  FutureOr<void> $onDidPublishLog(num id, int level, String log);

  /// `$onDidReceiveMessage(id: number, message: string): void`
  FutureOr<void> $onDidReceiveMessage(num id, String message);

  /// `$upsertMcpCollection(collection: McpCollectionDefinition.FromExtHost, servers: McpServerDefinition.Serialized[]): void`
  FutureOr<void> $upsertMcpCollection(
    Map<String, Object?> collection,
    List<Map<String, Object?>> servers,
  );

  /// `$deleteMcpCollection(collectionId: string): void`
  FutureOr<void> $deleteMcpCollection(String collectionId);

  /// `$getTokenFromServerMetadata(id: number, authDetails: IMcpAuthenticationDetails, options?: IMcpAuthenticationOptions): Promise<string | undefined>`
  Future<String?> $getTokenFromServerMetadata(
    num id,
    Map<String, Object?> authDetails,
    Map<String, Object?>? options,
  );

  /// `$getTokenForProviderId(id: number, providerId: string, scopes: string[], options?: IMcpAuthenticationOptions): Promise<string | undefined>`
  Future<String?> $getTokenForProviderId(
    num id,
    String providerId,
    List<String> scopes,
    Map<String, Object?>? options,
  );

  /// `$logMcpAuthSetup(data: IAuthMetadataSource): void`
  FutureOr<void> $logMcpAuthSetup(Map<String, Object?> data);

  /// `$startMcpGateway(chatSessionResource?: UriComponents): Promise<{ servers: { label: string; address: UriComponents }[]; gatewayId: string } | undefined>`
  Future<Map<String, Object?>?> $startMcpGateway(VsUri? chatSessionResource);

  /// `$disposeMcpGateway(gatewayId: string): void`
  FutureOr<void> $disposeMcpGateway(String gatewayId);
}

/// [MainThreadMcpShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadMcpUnsupported implements MainThreadMcpShape {
  const MainThreadMcpUnsupported();

  @override
  FutureOr<void> $onDidChangeState(num id, Map<String, Object?> state) =>
      _unsupported('MainThreadMcp', r'$onDidChangeState');

  @override
  FutureOr<void> $onDidPublishLog(num id, int level, String log) =>
      _unsupported('MainThreadMcp', r'$onDidPublishLog');

  @override
  FutureOr<void> $onDidReceiveMessage(num id, String message) =>
      _unsupported('MainThreadMcp', r'$onDidReceiveMessage');

  @override
  FutureOr<void> $upsertMcpCollection(
    Map<String, Object?> collection,
    List<Map<String, Object?>> servers,
  ) => _unsupported('MainThreadMcp', r'$upsertMcpCollection');

  @override
  FutureOr<void> $deleteMcpCollection(String collectionId) =>
      _unsupported('MainThreadMcp', r'$deleteMcpCollection');

  @override
  Future<String?> $getTokenFromServerMetadata(
    num id,
    Map<String, Object?> authDetails,
    Map<String, Object?>? options,
  ) => _unsupported('MainThreadMcp', r'$getTokenFromServerMetadata');

  @override
  Future<String?> $getTokenForProviderId(
    num id,
    String providerId,
    List<String> scopes,
    Map<String, Object?>? options,
  ) => _unsupported('MainThreadMcp', r'$getTokenForProviderId');

  @override
  FutureOr<void> $logMcpAuthSetup(Map<String, Object?> data) =>
      _unsupported('MainThreadMcp', r'$logMcpAuthSetup');

  @override
  Future<Map<String, Object?>?> $startMcpGateway(VsUri? chatSessionResource) =>
      _unsupported('MainThreadMcp', r'$startMcpGateway');

  @override
  FutureOr<void> $disposeMcpGateway(String gatewayId) =>
      _unsupported('MainThreadMcp', r'$disposeMcpGateway');
}

/// Decodes requests to [MainContext.mainThreadMcp] and calls [target].
final class MainThreadMcpActor implements RpcActor {
  MainThreadMcpActor(this.target);

  static const identifier = MainContext.mainThreadMcp;

  final MainThreadMcpShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadMcp.$method', args);
    switch (method) {
      case r'$onDidChangeState':
        await target.$onDidChangeState(
          a.arg(0, decodeNum, 'id'),
          a.arg(1, decodeMap, 'state'),
        );
        return null;
      case r'$onDidPublishLog':
        await target.$onDidPublishLog(
          a.arg(0, decodeNum, 'id'),
          a.arg(1, decodeInt, 'level'),
          a.arg(2, decodeString, 'log'),
        );
        return null;
      case r'$onDidReceiveMessage':
        await target.$onDidReceiveMessage(
          a.arg(0, decodeNum, 'id'),
          a.arg(1, decodeString, 'message'),
        );
        return null;
      case r'$upsertMcpCollection':
        await target.$upsertMcpCollection(
          a.arg(0, decodeMap, 'collection'),
          a.arg(1, decodeListOf(decodeMap), 'servers'),
        );
        return null;
      case r'$deleteMcpCollection':
        await target.$deleteMcpCollection(
          a.arg(0, decodeString, 'collectionId'),
        );
        return null;
      case r'$getTokenFromServerMetadata':
        return await target.$getTokenFromServerMetadata(
          a.arg(0, decodeNum, 'id'),
          a.arg(1, decodeMap, 'authDetails'),
          a.arg(2, decodeNullable(decodeMap), 'options'),
        );
      case r'$getTokenForProviderId':
        return await target.$getTokenForProviderId(
          a.arg(0, decodeNum, 'id'),
          a.arg(1, decodeString, 'providerId'),
          a.arg(2, decodeListOf(decodeString), 'scopes'),
          a.arg(3, decodeNullable(decodeMap), 'options'),
        );
      case r'$logMcpAuthSetup':
        await target.$logMcpAuthSetup(a.arg(0, decodeMap, 'data'));
        return null;
      case r'$startMcpGateway':
        return await target.$startMcpGateway(
          a.arg(0, decodeNullable(decodeUri), 'chatSessionResource'),
        );
      case r'$disposeMcpGateway':
        await target.$disposeMcpGateway(a.arg(0, decodeString, 'gatewayId'));
        return null;
      default:
        throw RpcUnsupported('MainThreadMcp.$method');
    }
  }
}

// --- MainThreadAiRelatedInformation --------------------------------------------

/// `MainThreadAiRelatedInformationShape` (`MainThreadAiRelatedInformation`).
abstract interface class MainThreadAiRelatedInformationShape {
  /// `$getAiRelatedInformation(query: string, types: RelatedInformationType[]): Promise<RelatedInformationResult[]>`
  Future<List<Map<String, Object?>>> $getAiRelatedInformation(
    String query,
    List<int> types,
  );

  /// `$registerAiRelatedInformationProvider(handle: number, type: RelatedInformationType): void`
  FutureOr<void> $registerAiRelatedInformationProvider(num handle, int type);

  /// `$unregisterAiRelatedInformationProvider(handle: number): void`
  FutureOr<void> $unregisterAiRelatedInformationProvider(num handle);
}

/// [MainThreadAiRelatedInformationShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadAiRelatedInformationUnsupported
    implements MainThreadAiRelatedInformationShape {
  const MainThreadAiRelatedInformationUnsupported();

  @override
  Future<List<Map<String, Object?>>> $getAiRelatedInformation(
    String query,
    List<int> types,
  ) => _unsupported(
    'MainThreadAiRelatedInformation',
    r'$getAiRelatedInformation',
  );

  @override
  FutureOr<void> $registerAiRelatedInformationProvider(num handle, int type) =>
      _unsupported(
        'MainThreadAiRelatedInformation',
        r'$registerAiRelatedInformationProvider',
      );

  @override
  FutureOr<void> $unregisterAiRelatedInformationProvider(num handle) =>
      _unsupported(
        'MainThreadAiRelatedInformation',
        r'$unregisterAiRelatedInformationProvider',
      );
}

/// Decodes requests to [MainContext.mainThreadAiRelatedInformation] and calls [target].
final class MainThreadAiRelatedInformationActor implements RpcActor {
  MainThreadAiRelatedInformationActor(this.target);

  static const identifier = MainContext.mainThreadAiRelatedInformation;

  final MainThreadAiRelatedInformationShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadAiRelatedInformation.$method', args);
    switch (method) {
      case r'$getAiRelatedInformation':
        return await target.$getAiRelatedInformation(
          a.arg(0, decodeString, 'query'),
          a.arg(1, decodeListOf(decodeInt), 'types'),
        );
      case r'$registerAiRelatedInformationProvider':
        await target.$registerAiRelatedInformationProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeInt, 'type'),
        );
        return null;
      case r'$unregisterAiRelatedInformationProvider':
        await target.$unregisterAiRelatedInformationProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadAiRelatedInformation.$method');
    }
  }
}

// --- MainThreadAiEmbeddingVector -----------------------------------------------

/// `MainThreadAiEmbeddingVectorShape` (`MainThreadAiEmbeddingVector`).
abstract interface class MainThreadAiEmbeddingVectorShape {
  /// `$registerAiEmbeddingVectorProvider(model: string, handle: number): void`
  FutureOr<void> $registerAiEmbeddingVectorProvider(String model, num handle);

  /// `$unregisterAiEmbeddingVectorProvider(handle: number): void`
  FutureOr<void> $unregisterAiEmbeddingVectorProvider(num handle);
}

/// [MainThreadAiEmbeddingVectorShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadAiEmbeddingVectorUnsupported
    implements MainThreadAiEmbeddingVectorShape {
  const MainThreadAiEmbeddingVectorUnsupported();

  @override
  FutureOr<void> $registerAiEmbeddingVectorProvider(String model, num handle) =>
      _unsupported(
        'MainThreadAiEmbeddingVector',
        r'$registerAiEmbeddingVectorProvider',
      );

  @override
  FutureOr<void> $unregisterAiEmbeddingVectorProvider(num handle) =>
      _unsupported(
        'MainThreadAiEmbeddingVector',
        r'$unregisterAiEmbeddingVectorProvider',
      );
}

/// Decodes requests to [MainContext.mainThreadAiEmbeddingVector] and calls [target].
final class MainThreadAiEmbeddingVectorActor implements RpcActor {
  MainThreadAiEmbeddingVectorActor(this.target);

  static const identifier = MainContext.mainThreadAiEmbeddingVector;

  final MainThreadAiEmbeddingVectorShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadAiEmbeddingVector.$method', args);
    switch (method) {
      case r'$registerAiEmbeddingVectorProvider':
        await target.$registerAiEmbeddingVectorProvider(
          a.arg(0, decodeString, 'model'),
          a.arg(1, decodeNum, 'handle'),
        );
        return null;
      case r'$unregisterAiEmbeddingVectorProvider':
        await target.$unregisterAiEmbeddingVectorProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadAiEmbeddingVector.$method');
    }
  }
}

// --- MainThreadChatStatus ------------------------------------------------------

/// `MainThreadChatStatusShape` (`MainThreadChatStatus`).
abstract interface class MainThreadChatStatusShape {
  /// `$setEntry(id: string, entry: ChatStatusItemDto): void`
  FutureOr<void> $setEntry(String id, Map<String, Object?> entry);

  /// `$disposeEntry(id: string): void`
  FutureOr<void> $disposeEntry(String id);
}

/// [MainThreadChatStatusShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatStatusUnsupported
    implements MainThreadChatStatusShape {
  const MainThreadChatStatusUnsupported();

  @override
  FutureOr<void> $setEntry(String id, Map<String, Object?> entry) =>
      _unsupported('MainThreadChatStatus', r'$setEntry');

  @override
  FutureOr<void> $disposeEntry(String id) =>
      _unsupported('MainThreadChatStatus', r'$disposeEntry');
}

/// Decodes requests to [MainContext.mainThreadChatStatus] and calls [target].
final class MainThreadChatStatusActor implements RpcActor {
  MainThreadChatStatusActor(this.target);

  static const identifier = MainContext.mainThreadChatStatus;

  final MainThreadChatStatusShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatStatus.$method', args);
    switch (method) {
      case r'$setEntry':
        await target.$setEntry(
          a.arg(0, decodeString, 'id'),
          a.arg(1, decodeMap, 'entry'),
        );
        return null;
      case r'$disposeEntry':
        await target.$disposeEntry(a.arg(0, decodeString, 'id'));
        return null;
      default:
        throw RpcUnsupported('MainThreadChatStatus.$method');
    }
  }
}

// --- MainThreadChatQuota -------------------------------------------------------

/// `MainThreadChatQuotaShape` (`MainThreadChatQuota`).
abstract interface class MainThreadChatQuotaShape {
  /// `$updateQuotas(quotas: IQuotaSnapshotsDto): void`
  FutureOr<void> $updateQuotas(Map<String, Object?> quotas);
}

/// [MainThreadChatQuotaShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatQuotaUnsupported implements MainThreadChatQuotaShape {
  const MainThreadChatQuotaUnsupported();

  @override
  FutureOr<void> $updateQuotas(Map<String, Object?> quotas) =>
      _unsupported('MainThreadChatQuota', r'$updateQuotas');
}

/// Decodes requests to [MainContext.mainThreadChatQuota] and calls [target].
final class MainThreadChatQuotaActor implements RpcActor {
  MainThreadChatQuotaActor(this.target);

  static const identifier = MainContext.mainThreadChatQuota;

  final MainThreadChatQuotaShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatQuota.$method', args);
    switch (method) {
      case r'$updateQuotas':
        await target.$updateQuotas(a.arg(0, decodeMap, 'quotas'));
        return null;
      default:
        throw RpcUnsupported('MainThreadChatQuota.$method');
    }
  }
}

// --- MainThreadChatInputNotification -------------------------------------------

/// `MainThreadChatInputNotificationShape` (`MainThreadChatInputNotification`).
abstract interface class MainThreadChatInputNotificationShape {
  /// `$setNotification(notification: ChatInputNotificationDto): void`
  FutureOr<void> $setNotification(Map<String, Object?> notification);

  /// `$disposeNotification(id: string): void`
  FutureOr<void> $disposeNotification(String id);
}

/// [MainThreadChatInputNotificationShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatInputNotificationUnsupported
    implements MainThreadChatInputNotificationShape {
  const MainThreadChatInputNotificationUnsupported();

  @override
  FutureOr<void> $setNotification(Map<String, Object?> notification) =>
      _unsupported('MainThreadChatInputNotification', r'$setNotification');

  @override
  FutureOr<void> $disposeNotification(String id) =>
      _unsupported('MainThreadChatInputNotification', r'$disposeNotification');
}

/// Decodes requests to [MainContext.mainThreadChatInputNotification] and calls [target].
final class MainThreadChatInputNotificationActor implements RpcActor {
  MainThreadChatInputNotificationActor(this.target);

  static const identifier = MainContext.mainThreadChatInputNotification;

  final MainThreadChatInputNotificationShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatInputNotification.$method', args);
    switch (method) {
      case r'$setNotification':
        await target.$setNotification(a.arg(0, decodeMap, 'notification'));
        return null;
      case r'$disposeNotification':
        await target.$disposeNotification(a.arg(0, decodeString, 'id'));
        return null;
      default:
        throw RpcUnsupported('MainThreadChatInputNotification.$method');
    }
  }
}

// --- MainThreadAiSettingsSearch ------------------------------------------------

/// `MainThreadAiSettingsSearchShape` (`MainThreadAiSettingsSearch`).
abstract interface class MainThreadAiSettingsSearchShape {
  /// `$registerAiSettingsSearchProvider(handle: number): void`
  FutureOr<void> $registerAiSettingsSearchProvider(num handle);

  /// `$unregisterAiSettingsSearchProvider(handle: number): void`
  FutureOr<void> $unregisterAiSettingsSearchProvider(num handle);

  /// `$handleSearchResult(handle: number, result: AiSettingsSearchResult): void`
  FutureOr<void> $handleSearchResult(num handle, Map<String, Object?> result);
}

/// [MainThreadAiSettingsSearchShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadAiSettingsSearchUnsupported
    implements MainThreadAiSettingsSearchShape {
  const MainThreadAiSettingsSearchUnsupported();

  @override
  FutureOr<void> $registerAiSettingsSearchProvider(num handle) => _unsupported(
    'MainThreadAiSettingsSearch',
    r'$registerAiSettingsSearchProvider',
  );

  @override
  FutureOr<void> $unregisterAiSettingsSearchProvider(num handle) =>
      _unsupported(
        'MainThreadAiSettingsSearch',
        r'$unregisterAiSettingsSearchProvider',
      );

  @override
  FutureOr<void> $handleSearchResult(num handle, Map<String, Object?> result) =>
      _unsupported('MainThreadAiSettingsSearch', r'$handleSearchResult');
}

/// Decodes requests to [MainContext.mainThreadAiSettingsSearch] and calls [target].
final class MainThreadAiSettingsSearchActor implements RpcActor {
  MainThreadAiSettingsSearchActor(this.target);

  static const identifier = MainContext.mainThreadAiSettingsSearch;

  final MainThreadAiSettingsSearchShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadAiSettingsSearch.$method', args);
    switch (method) {
      case r'$registerAiSettingsSearchProvider':
        await target.$registerAiSettingsSearchProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$unregisterAiSettingsSearchProvider':
        await target.$unregisterAiSettingsSearchProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$handleSearchResult':
        await target.$handleSearchResult(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'result'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadAiSettingsSearch.$method');
    }
  }
}

// --- MainThreadDataChannels ----------------------------------------------------

/// `MainThreadDataChannelsShape` (`MainThreadDataChannels`).
abstract interface class MainThreadDataChannelsShape {
  /// `$createLinkPresentationWatcher(handle: number, providerId: string, resource: UriComponents): void`
  FutureOr<void> $createLinkPresentationWatcher(
    num handle,
    String providerId,
    VsUri resource,
  );

  /// `$disposeLinkPresentationWatcher(handle: number): void`
  FutureOr<void> $disposeLinkPresentationWatcher(num handle);

  /// `$registerLinkPresentationProvider(handle: number, extensionId: string, providerId: string): void`
  FutureOr<void> $registerLinkPresentationProvider(
    num handle,
    String extensionId,
    String providerId,
  );

  /// `$unregisterLinkPresentationProvider(handle: number): void`
  FutureOr<void> $unregisterLinkPresentationProvider(num handle);

  /// `$acceptLinkPresentationProviderData(handle: number, data: unknown): void`
  FutureOr<void> $acceptLinkPresentationProviderData(num handle, Object? data);
}

/// [MainThreadDataChannelsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadDataChannelsUnsupported
    implements MainThreadDataChannelsShape {
  const MainThreadDataChannelsUnsupported();

  @override
  FutureOr<void> $createLinkPresentationWatcher(
    num handle,
    String providerId,
    VsUri resource,
  ) =>
      _unsupported('MainThreadDataChannels', r'$createLinkPresentationWatcher');

  @override
  FutureOr<void> $disposeLinkPresentationWatcher(num handle) => _unsupported(
    'MainThreadDataChannels',
    r'$disposeLinkPresentationWatcher',
  );

  @override
  FutureOr<void> $registerLinkPresentationProvider(
    num handle,
    String extensionId,
    String providerId,
  ) => _unsupported(
    'MainThreadDataChannels',
    r'$registerLinkPresentationProvider',
  );

  @override
  FutureOr<void> $unregisterLinkPresentationProvider(num handle) =>
      _unsupported(
        'MainThreadDataChannels',
        r'$unregisterLinkPresentationProvider',
      );

  @override
  FutureOr<void> $acceptLinkPresentationProviderData(
    num handle,
    Object? data,
  ) => _unsupported(
    'MainThreadDataChannels',
    r'$acceptLinkPresentationProviderData',
  );
}

/// Decodes requests to [MainContext.mainThreadDataChannels] and calls [target].
final class MainThreadDataChannelsActor implements RpcActor {
  MainThreadDataChannelsActor(this.target);

  static const identifier = MainContext.mainThreadDataChannels;

  final MainThreadDataChannelsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadDataChannels.$method', args);
    switch (method) {
      case r'$createLinkPresentationWatcher':
        await target.$createLinkPresentationWatcher(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'providerId'),
          a.arg(2, decodeUri, 'resource'),
        );
        return null;
      case r'$disposeLinkPresentationWatcher':
        await target.$disposeLinkPresentationWatcher(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$registerLinkPresentationProvider':
        await target.$registerLinkPresentationProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'extensionId'),
          a.arg(2, decodeString, 'providerId'),
        );
        return null;
      case r'$unregisterLinkPresentationProvider':
        await target.$unregisterLinkPresentationProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$acceptLinkPresentationProviderData':
        await target.$acceptLinkPresentationProviderData(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeObject, 'data'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadDataChannels.$method');
    }
  }
}

// --- MainThreadChatSessions ----------------------------------------------------

/// `MainThreadChatSessionsShape` (`MainThreadChatSessions`).
abstract interface class MainThreadChatSessionsShape {
  /// `$registerChatSessionItemController(controllerHandle: number, chatSessionType: string, supportsResolve: boolean): void`
  FutureOr<void> $registerChatSessionItemController(
    num controllerHandle,
    String chatSessionType,
    bool supportsResolve,
  );

  /// `$updateChatSessionItemControllerCapabilities(controllerHandle: number, supportsResolve: boolean): void`
  FutureOr<void> $updateChatSessionItemControllerCapabilities(
    num controllerHandle,
    bool supportsResolve,
  );

  /// `$unregisterChatSessionItemController(controllerHandle: number): void`
  FutureOr<void> $unregisterChatSessionItemController(num controllerHandle);

  /// `$updateChatSessionItems(controllerHandle: number, change: IChatSessionItemsChange): Promise<void>`
  FutureOr<void> $updateChatSessionItems(
    num controllerHandle,
    Map<String, Object?> change,
  );

  /// `$addOrUpdateChatSessionItem(controllerHandle: number, item: Dto<IChatSessionItem>): Promise<void>`
  FutureOr<void> $addOrUpdateChatSessionItem(
    num controllerHandle,
    Map<String, Object?> item,
  );

  /// `$onDidCommitChatSessionItem(controllerHandle: number, original: UriComponents, modified: UriComponents): void`
  FutureOr<void> $onDidCommitChatSessionItem(
    num controllerHandle,
    VsUri original,
    VsUri modified,
  );

  /// `$registerChatSessionContentProvider(handle: number, chatSessionScheme: string): void`
  FutureOr<void> $registerChatSessionContentProvider(
    num handle,
    String chatSessionScheme,
  );

  /// `$unregisterChatSessionContentProvider(handle: number): void`
  FutureOr<void> $unregisterChatSessionContentProvider(num handle);

  /// `$onDidChangeChatSessionOptions(handle: number, sessionResource: UriComponents, updates: Record<string, string | IChatSessionProviderOptionItem>): void`
  FutureOr<void> $onDidChangeChatSessionOptions(
    num handle,
    VsUri sessionResource,
    Map<String, Object?> updates,
  );

  /// `$onDidChangeChatSessionProviderOptions(handle: number): void`
  FutureOr<void> $onDidChangeChatSessionProviderOptions(num handle);

  /// `$updateChatSessionInputState(controllerHandle: number, sessionResource: UriComponents, optionGroups: readonly IChatSessionProviderOptionGroup[]): void`
  FutureOr<void> $updateChatSessionInputState(
    num controllerHandle,
    VsUri sessionResource,
    List<Map<String, Object?>> optionGroups,
  );

  /// `$handleProgressChunk(handle: number, sessionResource: UriComponents, requestId: string, chunks: (IChatProgressDto | [IChatProgressDto, number])[]): Promise<void>`
  FutureOr<void> $handleProgressChunk(
    num handle,
    VsUri sessionResource,
    String requestId,
    List<Object?> chunks,
  );

  /// `$handleAnchorResolve(handle: number, sessionResource: UriComponents, requestId: string, requestHandle: string, anchor: Dto<IChatContentInlineReference>): void`
  FutureOr<void> $handleAnchorResolve(
    num handle,
    VsUri sessionResource,
    String requestId,
    String requestHandle,
    Map<String, Object?> anchor,
  );

  /// `$handleProgressComplete(handle: number, sessionResource: UriComponents, requestId: string): void`
  FutureOr<void> $handleProgressComplete(
    num handle,
    VsUri sessionResource,
    String requestId,
  );
}

/// [MainThreadChatSessionsShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatSessionsUnsupported
    implements MainThreadChatSessionsShape {
  const MainThreadChatSessionsUnsupported();

  @override
  FutureOr<void> $registerChatSessionItemController(
    num controllerHandle,
    String chatSessionType,
    bool supportsResolve,
  ) => _unsupported(
    'MainThreadChatSessions',
    r'$registerChatSessionItemController',
  );

  @override
  FutureOr<void> $updateChatSessionItemControllerCapabilities(
    num controllerHandle,
    bool supportsResolve,
  ) => _unsupported(
    'MainThreadChatSessions',
    r'$updateChatSessionItemControllerCapabilities',
  );

  @override
  FutureOr<void> $unregisterChatSessionItemController(num controllerHandle) =>
      _unsupported(
        'MainThreadChatSessions',
        r'$unregisterChatSessionItemController',
      );

  @override
  FutureOr<void> $updateChatSessionItems(
    num controllerHandle,
    Map<String, Object?> change,
  ) => _unsupported('MainThreadChatSessions', r'$updateChatSessionItems');

  @override
  FutureOr<void> $addOrUpdateChatSessionItem(
    num controllerHandle,
    Map<String, Object?> item,
  ) => _unsupported('MainThreadChatSessions', r'$addOrUpdateChatSessionItem');

  @override
  FutureOr<void> $onDidCommitChatSessionItem(
    num controllerHandle,
    VsUri original,
    VsUri modified,
  ) => _unsupported('MainThreadChatSessions', r'$onDidCommitChatSessionItem');

  @override
  FutureOr<void> $registerChatSessionContentProvider(
    num handle,
    String chatSessionScheme,
  ) => _unsupported(
    'MainThreadChatSessions',
    r'$registerChatSessionContentProvider',
  );

  @override
  FutureOr<void> $unregisterChatSessionContentProvider(num handle) =>
      _unsupported(
        'MainThreadChatSessions',
        r'$unregisterChatSessionContentProvider',
      );

  @override
  FutureOr<void> $onDidChangeChatSessionOptions(
    num handle,
    VsUri sessionResource,
    Map<String, Object?> updates,
  ) =>
      _unsupported('MainThreadChatSessions', r'$onDidChangeChatSessionOptions');

  @override
  FutureOr<void> $onDidChangeChatSessionProviderOptions(num handle) =>
      _unsupported(
        'MainThreadChatSessions',
        r'$onDidChangeChatSessionProviderOptions',
      );

  @override
  FutureOr<void> $updateChatSessionInputState(
    num controllerHandle,
    VsUri sessionResource,
    List<Map<String, Object?>> optionGroups,
  ) => _unsupported('MainThreadChatSessions', r'$updateChatSessionInputState');

  @override
  FutureOr<void> $handleProgressChunk(
    num handle,
    VsUri sessionResource,
    String requestId,
    List<Object?> chunks,
  ) => _unsupported('MainThreadChatSessions', r'$handleProgressChunk');

  @override
  FutureOr<void> $handleAnchorResolve(
    num handle,
    VsUri sessionResource,
    String requestId,
    String requestHandle,
    Map<String, Object?> anchor,
  ) => _unsupported('MainThreadChatSessions', r'$handleAnchorResolve');

  @override
  FutureOr<void> $handleProgressComplete(
    num handle,
    VsUri sessionResource,
    String requestId,
  ) => _unsupported('MainThreadChatSessions', r'$handleProgressComplete');
}

/// Decodes requests to [MainContext.mainThreadChatSessions] and calls [target].
final class MainThreadChatSessionsActor implements RpcActor {
  MainThreadChatSessionsActor(this.target);

  static const identifier = MainContext.mainThreadChatSessions;

  final MainThreadChatSessionsShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatSessions.$method', args);
    switch (method) {
      case r'$registerChatSessionItemController':
        await target.$registerChatSessionItemController(
          a.arg(0, decodeNum, 'controllerHandle'),
          a.arg(1, decodeString, 'chatSessionType'),
          a.arg(2, decodeBool, 'supportsResolve'),
        );
        return null;
      case r'$updateChatSessionItemControllerCapabilities':
        await target.$updateChatSessionItemControllerCapabilities(
          a.arg(0, decodeNum, 'controllerHandle'),
          a.arg(1, decodeBool, 'supportsResolve'),
        );
        return null;
      case r'$unregisterChatSessionItemController':
        await target.$unregisterChatSessionItemController(
          a.arg(0, decodeNum, 'controllerHandle'),
        );
        return null;
      case r'$updateChatSessionItems':
        await target.$updateChatSessionItems(
          a.arg(0, decodeNum, 'controllerHandle'),
          a.arg(1, decodeMap, 'change'),
        );
        return null;
      case r'$addOrUpdateChatSessionItem':
        await target.$addOrUpdateChatSessionItem(
          a.arg(0, decodeNum, 'controllerHandle'),
          a.arg(1, decodeMap, 'item'),
        );
        return null;
      case r'$onDidCommitChatSessionItem':
        await target.$onDidCommitChatSessionItem(
          a.arg(0, decodeNum, 'controllerHandle'),
          a.arg(1, decodeUri, 'original'),
          a.arg(2, decodeUri, 'modified'),
        );
        return null;
      case r'$registerChatSessionContentProvider':
        await target.$registerChatSessionContentProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'chatSessionScheme'),
        );
        return null;
      case r'$unregisterChatSessionContentProvider':
        await target.$unregisterChatSessionContentProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$onDidChangeChatSessionOptions':
        await target.$onDidChangeChatSessionOptions(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'sessionResource'),
          a.arg(2, decodeMapOf(decodeObject), 'updates'),
        );
        return null;
      case r'$onDidChangeChatSessionProviderOptions':
        await target.$onDidChangeChatSessionProviderOptions(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$updateChatSessionInputState':
        await target.$updateChatSessionInputState(
          a.arg(0, decodeNum, 'controllerHandle'),
          a.arg(1, decodeUri, 'sessionResource'),
          a.arg(2, decodeListOf(decodeMap), 'optionGroups'),
        );
        return null;
      case r'$handleProgressChunk':
        await target.$handleProgressChunk(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'sessionResource'),
          a.arg(2, decodeString, 'requestId'),
          a.arg(3, decodeListOf(decodeObject), 'chunks'),
        );
        return null;
      case r'$handleAnchorResolve':
        await target.$handleAnchorResolve(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'sessionResource'),
          a.arg(2, decodeString, 'requestId'),
          a.arg(3, decodeString, 'requestHandle'),
          a.arg(4, decodeMap, 'anchor'),
        );
        return null;
      case r'$handleProgressComplete':
        await target.$handleProgressComplete(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeUri, 'sessionResource'),
          a.arg(2, decodeString, 'requestId'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadChatSessions.$method');
    }
  }
}

// --- MainThreadChatOutputRenderer ----------------------------------------------

/// `MainThreadChatOutputRendererShape` (`MainThreadChatOutputRenderer`).
abstract interface class MainThreadChatOutputRendererShape {
  /// `$registerChatOutputRenderer(viewType: string, extensionId: ExtensionIdentifier, extensionLocation: UriComponents): void`
  FutureOr<void> $registerChatOutputRenderer(
    String viewType,
    Map<String, Object?> extensionId,
    VsUri extensionLocation,
  );

  /// `$unregisterChatOutputRenderer(viewType: string): void`
  FutureOr<void> $unregisterChatOutputRenderer(String viewType);
}

/// [MainThreadChatOutputRendererShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatOutputRendererUnsupported
    implements MainThreadChatOutputRendererShape {
  const MainThreadChatOutputRendererUnsupported();

  @override
  FutureOr<void> $registerChatOutputRenderer(
    String viewType,
    Map<String, Object?> extensionId,
    VsUri extensionLocation,
  ) => _unsupported(
    'MainThreadChatOutputRenderer',
    r'$registerChatOutputRenderer',
  );

  @override
  FutureOr<void> $unregisterChatOutputRenderer(String viewType) => _unsupported(
    'MainThreadChatOutputRenderer',
    r'$unregisterChatOutputRenderer',
  );
}

/// Decodes requests to [MainContext.mainThreadChatOutputRenderer] and calls [target].
final class MainThreadChatOutputRendererActor implements RpcActor {
  MainThreadChatOutputRendererActor(this.target);

  static const identifier = MainContext.mainThreadChatOutputRenderer;

  final MainThreadChatOutputRendererShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatOutputRenderer.$method', args);
    switch (method) {
      case r'$registerChatOutputRenderer':
        await target.$registerChatOutputRenderer(
          a.arg(0, decodeString, 'viewType'),
          a.arg(1, decodeMap, 'extensionId'),
          a.arg(2, decodeUri, 'extensionLocation'),
        );
        return null;
      case r'$unregisterChatOutputRenderer':
        await target.$unregisterChatOutputRenderer(
          a.arg(0, decodeString, 'viewType'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadChatOutputRenderer.$method');
    }
  }
}

// --- MainThreadChatContext -----------------------------------------------------

/// `MainThreadChatContextShape` (`MainThreadChatContext`).
abstract interface class MainThreadChatContextShape {
  /// `$registerChatWorkspaceContextProvider(handle: number, id: string): void`
  FutureOr<void> $registerChatWorkspaceContextProvider(num handle, String id);

  /// `$registerChatExplicitContextProvider(handle: number, id: string): void`
  FutureOr<void> $registerChatExplicitContextProvider(num handle, String id);

  /// `$registerChatResourceContextProvider(handle: number, id: string, selector: ITabSelectorDto): void`
  FutureOr<void> $registerChatResourceContextProvider(
    num handle,
    String id,
    Map<String, Object?> selector,
  );

  /// `$unregisterChatContextProvider(handle: number): void`
  FutureOr<void> $unregisterChatContextProvider(num handle);

  /// `$updateWorkspaceContextItems(handle: number, items: IChatContextItemDto[]): void`
  FutureOr<void> $updateWorkspaceContextItems(
    num handle,
    List<Map<String, Object?>> items,
  );

  /// `$executeChatContextItemCommand(itemHandle: number): Promise<void>`
  FutureOr<void> $executeChatContextItemCommand(num itemHandle);
}

/// [MainThreadChatContextShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatContextUnsupported
    implements MainThreadChatContextShape {
  const MainThreadChatContextUnsupported();

  @override
  FutureOr<void> $registerChatWorkspaceContextProvider(num handle, String id) =>
      _unsupported(
        'MainThreadChatContext',
        r'$registerChatWorkspaceContextProvider',
      );

  @override
  FutureOr<void> $registerChatExplicitContextProvider(num handle, String id) =>
      _unsupported(
        'MainThreadChatContext',
        r'$registerChatExplicitContextProvider',
      );

  @override
  FutureOr<void> $registerChatResourceContextProvider(
    num handle,
    String id,
    Map<String, Object?> selector,
  ) => _unsupported(
    'MainThreadChatContext',
    r'$registerChatResourceContextProvider',
  );

  @override
  FutureOr<void> $unregisterChatContextProvider(num handle) =>
      _unsupported('MainThreadChatContext', r'$unregisterChatContextProvider');

  @override
  FutureOr<void> $updateWorkspaceContextItems(
    num handle,
    List<Map<String, Object?>> items,
  ) => _unsupported('MainThreadChatContext', r'$updateWorkspaceContextItems');

  @override
  FutureOr<void> $executeChatContextItemCommand(num itemHandle) =>
      _unsupported('MainThreadChatContext', r'$executeChatContextItemCommand');
}

/// Decodes requests to [MainContext.mainThreadChatContext] and calls [target].
final class MainThreadChatContextActor implements RpcActor {
  MainThreadChatContextActor(this.target);

  static const identifier = MainContext.mainThreadChatContext;

  final MainThreadChatContextShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatContext.$method', args);
    switch (method) {
      case r'$registerChatWorkspaceContextProvider':
        await target.$registerChatWorkspaceContextProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
        );
        return null;
      case r'$registerChatExplicitContextProvider':
        await target.$registerChatExplicitContextProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
        );
        return null;
      case r'$registerChatResourceContextProvider':
        await target.$registerChatResourceContextProvider(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeString, 'id'),
          a.arg(2, decodeMap, 'selector'),
        );
        return null;
      case r'$unregisterChatContextProvider':
        await target.$unregisterChatContextProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$updateWorkspaceContextItems':
        await target.$updateWorkspaceContextItems(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeListOf(decodeMap), 'items'),
        );
        return null;
      case r'$executeChatContextItemCommand':
        await target.$executeChatContextItemCommand(
          a.arg(0, decodeNum, 'itemHandle'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadChatContext.$method');
    }
  }
}

// --- MainThreadChatDebug -------------------------------------------------------

/// `MainThreadChatDebugShape` (`MainThreadChatDebug`).
abstract interface class MainThreadChatDebugShape {
  /// `$registerChatDebugLogProvider(handle: number): void`
  FutureOr<void> $registerChatDebugLogProvider(num handle);

  /// `$unregisterChatDebugLogProvider(handle: number): void`
  FutureOr<void> $unregisterChatDebugLogProvider(num handle);

  /// `$acceptChatDebugEvent(handle: number, event: IChatDebugEventDto): void`
  FutureOr<void> $acceptChatDebugEvent(num handle, Map<String, Object?> event);

  /// `$subscribeToCoreDebugEvents(): void`
  FutureOr<void> $subscribeToCoreDebugEvents();

  /// `$unsubscribeFromCoreDebugEvents(): void`
  FutureOr<void> $unsubscribeFromCoreDebugEvents();
}

/// [MainThreadChatDebugShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadChatDebugUnsupported implements MainThreadChatDebugShape {
  const MainThreadChatDebugUnsupported();

  @override
  FutureOr<void> $registerChatDebugLogProvider(num handle) =>
      _unsupported('MainThreadChatDebug', r'$registerChatDebugLogProvider');

  @override
  FutureOr<void> $unregisterChatDebugLogProvider(num handle) =>
      _unsupported('MainThreadChatDebug', r'$unregisterChatDebugLogProvider');

  @override
  FutureOr<void> $acceptChatDebugEvent(
    num handle,
    Map<String, Object?> event,
  ) => _unsupported('MainThreadChatDebug', r'$acceptChatDebugEvent');

  @override
  FutureOr<void> $subscribeToCoreDebugEvents() =>
      _unsupported('MainThreadChatDebug', r'$subscribeToCoreDebugEvents');

  @override
  FutureOr<void> $unsubscribeFromCoreDebugEvents() =>
      _unsupported('MainThreadChatDebug', r'$unsubscribeFromCoreDebugEvents');
}

/// Decodes requests to [MainContext.mainThreadChatDebug] and calls [target].
final class MainThreadChatDebugActor implements RpcActor {
  MainThreadChatDebugActor(this.target);

  static const identifier = MainContext.mainThreadChatDebug;

  final MainThreadChatDebugShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadChatDebug.$method', args);
    switch (method) {
      case r'$registerChatDebugLogProvider':
        await target.$registerChatDebugLogProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$unregisterChatDebugLogProvider':
        await target.$unregisterChatDebugLogProvider(
          a.arg(0, decodeNum, 'handle'),
        );
        return null;
      case r'$acceptChatDebugEvent':
        await target.$acceptChatDebugEvent(
          a.arg(0, decodeNum, 'handle'),
          a.arg(1, decodeMap, 'event'),
        );
        return null;
      case r'$subscribeToCoreDebugEvents':
        await target.$subscribeToCoreDebugEvents();
        return null;
      case r'$unsubscribeFromCoreDebugEvents':
        await target.$unsubscribeFromCoreDebugEvents();
        return null;
      default:
        throw RpcUnsupported('MainThreadChatDebug.$method');
    }
  }
}

// --- MainThreadBrowsers --------------------------------------------------------

/// `MainThreadBrowsersShape` (`MainThreadBrowsers`).
abstract interface class MainThreadBrowsersShape {
  /// `$openBrowserTab(url: string, viewColumn?: EditorGroupColumn, options?: IEditorOptions): Promise<BrowserTabDto>`
  Future<Map<String, Object?>> $openBrowserTab(
    String url,
    num? viewColumn,
    Map<String, Object?>? options,
  );

  /// `$closeBrowserTab(browserId: string): Promise<void>`
  FutureOr<void> $closeBrowserTab(String browserId);

  /// `$startCDPSession(sessionId: string, browserId: string): Promise<void>`
  FutureOr<void> $startCDPSession(String sessionId, String browserId);

  /// `$closeCDPSession(sessionId: string): Promise<void>`
  FutureOr<void> $closeCDPSession(String sessionId);

  /// `$sendCDPMessage(sessionId: string, message: CDPRequest): Promise<void>`
  FutureOr<void> $sendCDPMessage(
    String sessionId,
    Map<String, Object?> message,
  );
}

/// [MainThreadBrowsersShape] with every method rejected as unsupported, and counted in
/// [ExtHostParity]. Implementations extend it and override what they support.
base class MainThreadBrowsersUnsupported implements MainThreadBrowsersShape {
  const MainThreadBrowsersUnsupported();

  @override
  Future<Map<String, Object?>> $openBrowserTab(
    String url,
    num? viewColumn,
    Map<String, Object?>? options,
  ) => _unsupported('MainThreadBrowsers', r'$openBrowserTab');

  @override
  FutureOr<void> $closeBrowserTab(String browserId) =>
      _unsupported('MainThreadBrowsers', r'$closeBrowserTab');

  @override
  FutureOr<void> $startCDPSession(String sessionId, String browserId) =>
      _unsupported('MainThreadBrowsers', r'$startCDPSession');

  @override
  FutureOr<void> $closeCDPSession(String sessionId) =>
      _unsupported('MainThreadBrowsers', r'$closeCDPSession');

  @override
  FutureOr<void> $sendCDPMessage(
    String sessionId,
    Map<String, Object?> message,
  ) => _unsupported('MainThreadBrowsers', r'$sendCDPMessage');
}

/// Decodes requests to [MainContext.mainThreadBrowsers] and calls [target].
final class MainThreadBrowsersActor implements RpcActor {
  MainThreadBrowsersActor(this.target);

  static const identifier = MainContext.mainThreadBrowsers;

  final MainThreadBrowsersShape target;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final a = RpcArgs('MainThreadBrowsers.$method', args);
    switch (method) {
      case r'$openBrowserTab':
        return await target.$openBrowserTab(
          a.arg(0, decodeString, 'url'),
          a.arg(1, decodeNullable(decodeNum), 'viewColumn'),
          a.arg(2, decodeNullable(decodeMap), 'options'),
        );
      case r'$closeBrowserTab':
        await target.$closeBrowserTab(a.arg(0, decodeString, 'browserId'));
        return null;
      case r'$startCDPSession':
        await target.$startCDPSession(
          a.arg(0, decodeString, 'sessionId'),
          a.arg(1, decodeString, 'browserId'),
        );
        return null;
      case r'$closeCDPSession':
        await target.$closeCDPSession(a.arg(0, decodeString, 'sessionId'));
        return null;
      case r'$sendCDPMessage':
        await target.$sendCDPMessage(
          a.arg(0, decodeString, 'sessionId'),
          a.arg(1, decodeMap, 'message'),
        );
        return null;
      default:
        throw RpcUnsupported('MainThreadBrowsers.$method');
    }
  }
}

/// For every main thread shape, by [ProxyIdentifier.nid], an actor whose
/// every method is rejected as unsupported and counted in [ExtHostParity]:
/// register these for the shapes BaoCode does not implement.
Map<int, RpcActor Function()> get unsupportedMainThreadActors => {
  MainContext.mainThreadAuthentication.nid: () => MainThreadAuthenticationActor(
    const MainThreadAuthenticationUnsupported(),
  ),
  MainContext.mainThreadBulkEdits.nid: () =>
      MainThreadBulkEditsActor(const MainThreadBulkEditsUnsupported()),
  MainContext.mainThreadLanguageModels.nid: () => MainThreadLanguageModelsActor(
    const MainThreadLanguageModelsUnsupported(),
  ),
  MainContext.mainThreadEmbeddings.nid: () =>
      MainThreadEmbeddingsActor(const MainThreadEmbeddingsUnsupported()),
  MainContext.mainThreadChatAgents2.nid: () =>
      MainThreadChatAgents2Actor(const MainThreadChatAgents2Unsupported()),
  MainContext.mainThreadCodeMapper.nid: () =>
      MainThreadCodeMapperActor(const MainThreadCodeMapperUnsupported()),
  MainContext.mainThreadLanguageModelTools.nid: () =>
      MainThreadLanguageModelToolsActor(
        const MainThreadLanguageModelToolsUnsupported(),
      ),
  MainContext.mainThreadGitExtension.nid: () =>
      MainThreadGitExtensionActor(const MainThreadGitExtensionUnsupported()),
  MainContext.mainThreadClipboard.nid: () =>
      MainThreadClipboardActor(const MainThreadClipboardUnsupported()),
  MainContext.mainThreadCommands.nid: () =>
      MainThreadCommandsActor(const MainThreadCommandsUnsupported()),
  MainContext.mainThreadComments.nid: () =>
      MainThreadCommentsActor(const MainThreadCommentsUnsupported()),
  MainContext.mainThreadConfiguration.nid: () =>
      MainThreadConfigurationActor(const MainThreadConfigurationUnsupported()),
  MainContext.mainThreadConsole.nid: () =>
      MainThreadConsoleActor(const MainThreadConsoleUnsupported()),
  MainContext.mainThreadDebugService.nid: () =>
      MainThreadDebugServiceActor(const MainThreadDebugServiceUnsupported()),
  MainContext.mainThreadDecorations.nid: () =>
      MainThreadDecorationsActor(const MainThreadDecorationsUnsupported()),
  MainContext.mainThreadDiagnostics.nid: () =>
      MainThreadDiagnosticsActor(const MainThreadDiagnosticsUnsupported()),
  MainContext.mainThreadDialogs.nid: () =>
      MainThreadDialogsActor(const MainThreadDialogsUnsupported()),
  MainContext.mainThreadDocuments.nid: () =>
      MainThreadDocumentsActor(const MainThreadDocumentsUnsupported()),
  MainContext.mainThreadDocumentContentProviders.nid: () =>
      MainThreadDocumentContentProvidersActor(
        const MainThreadDocumentContentProvidersUnsupported(),
      ),
  MainContext.mainThreadTextEditors.nid: () =>
      MainThreadTextEditorsActor(const MainThreadTextEditorsUnsupported()),
  MainContext.mainThreadEditorInsets.nid: () =>
      MainThreadEditorInsetsActor(const MainThreadEditorInsetsUnsupported()),
  MainContext.mainThreadEditorTabs.nid: () =>
      MainThreadEditorTabsActor(const MainThreadEditorTabsUnsupported()),
  MainContext.mainThreadErrors.nid: () =>
      MainThreadErrorsActor(const MainThreadErrorsUnsupported()),
  MainContext.mainThreadTreeViews.nid: () =>
      MainThreadTreeViewsActor(const MainThreadTreeViewsUnsupported()),
  MainContext.mainThreadDownloadService.nid: () =>
      MainThreadDownloadServiceActor(
        const MainThreadDownloadServiceUnsupported(),
      ),
  MainContext.mainThreadLanguageFeatures.nid: () =>
      MainThreadLanguageFeaturesActor(
        const MainThreadLanguageFeaturesUnsupported(),
      ),
  MainContext.mainThreadLanguages.nid: () =>
      MainThreadLanguagesActor(const MainThreadLanguagesUnsupported()),
  MainContext.mainThreadLogger.nid: () =>
      MainThreadLoggerActor(const MainThreadLoggerUnsupported()),
  MainContext.mainThreadMessageService.nid: () => MainThreadMessageServiceActor(
    const MainThreadMessageServiceUnsupported(),
  ),
  MainContext.mainThreadOutputService.nid: () =>
      MainThreadOutputServiceActor(const MainThreadOutputServiceUnsupported()),
  MainContext.mainThreadProgress.nid: () =>
      MainThreadProgressActor(const MainThreadProgressUnsupported()),
  MainContext.mainThreadQuickDiff.nid: () =>
      MainThreadQuickDiffActor(const MainThreadQuickDiffUnsupported()),
  MainContext.mainThreadAgentEditorComments.nid: () =>
      MainThreadAgentEditorCommentsActor(
        const MainThreadAgentEditorCommentsUnsupported(),
      ),
  MainContext.mainThreadDocumentDiff.nid: () =>
      MainThreadDocumentDiffActor(const MainThreadDocumentDiffUnsupported()),
  MainContext.mainThreadQuickOpen.nid: () =>
      MainThreadQuickOpenActor(const MainThreadQuickOpenUnsupported()),
  MainContext.mainThreadStatusBar.nid: () =>
      MainThreadStatusBarActor(const MainThreadStatusBarUnsupported()),
  MainContext.mainThreadSecretState.nid: () =>
      MainThreadSecretStateActor(const MainThreadSecretStateUnsupported()),
  MainContext.mainThreadStorage.nid: () =>
      MainThreadStorageActor(const MainThreadStorageUnsupported()),
  MainContext.mainThreadSpeech.nid: () =>
      MainThreadSpeechActor(const MainThreadSpeechUnsupported()),
  MainContext.mainThreadTelemetry.nid: () =>
      MainThreadTelemetryActor(const MainThreadTelemetryUnsupported()),
  MainContext.mainThreadMeteredConnection.nid: () =>
      MainThreadMeteredConnectionActor(
        const MainThreadMeteredConnectionUnsupported(),
      ),
  MainContext.mainThreadTerminalService.nid: () =>
      MainThreadTerminalServiceActor(
        const MainThreadTerminalServiceUnsupported(),
      ),
  MainContext.mainThreadTerminalShellIntegration.nid: () =>
      MainThreadTerminalShellIntegrationActor(
        const MainThreadTerminalShellIntegrationUnsupported(),
      ),
  MainContext.mainThreadWebviews.nid: () =>
      MainThreadWebviewsActor(const MainThreadWebviewsUnsupported()),
  MainContext.mainThreadWebviewPanels.nid: () =>
      MainThreadWebviewPanelsActor(const MainThreadWebviewPanelsUnsupported()),
  MainContext.mainThreadWebviewViews.nid: () =>
      MainThreadWebviewViewsActor(const MainThreadWebviewViewsUnsupported()),
  MainContext.mainThreadCustomEditors.nid: () =>
      MainThreadCustomEditorsActor(const MainThreadCustomEditorsUnsupported()),
  MainContext.mainThreadUrls.nid: () =>
      MainThreadUrlsActor(const MainThreadUrlsUnsupported()),
  MainContext.mainThreadUriOpeners.nid: () =>
      MainThreadUriOpenersActor(const MainThreadUriOpenersUnsupported()),
  MainContext.mainThreadProfileContentHandlers.nid: () =>
      MainThreadProfileContentHandlersActor(
        const MainThreadProfileContentHandlersUnsupported(),
      ),
  MainContext.mainThreadWorkspace.nid: () =>
      MainThreadWorkspaceActor(const MainThreadWorkspaceUnsupported()),
  MainContext.mainThreadFileSystem.nid: () =>
      MainThreadFileSystemActor(const MainThreadFileSystemUnsupported()),
  MainContext.mainThreadFileSystemEventService.nid: () =>
      MainThreadFileSystemEventServiceActor(
        const MainThreadFileSystemEventServiceUnsupported(),
      ),
  MainContext.mainThreadExtensionService.nid: () =>
      MainThreadExtensionServiceActor(
        const MainThreadExtensionServiceUnsupported(),
      ),
  MainContext.mainThreadSCM.nid: () =>
      MainThreadSCMActor(const MainThreadSCMUnsupported()),
  MainContext.mainThreadSearch.nid: () =>
      MainThreadSearchActor(const MainThreadSearchUnsupported()),
  MainContext.mainThreadShare.nid: () =>
      MainThreadShareActor(const MainThreadShareUnsupported()),
  MainContext.mainThreadTask.nid: () =>
      MainThreadTaskActor(const MainThreadTaskUnsupported()),
  MainContext.mainThreadWindow.nid: () =>
      MainThreadWindowActor(const MainThreadWindowUnsupported()),
  MainContext.mainThreadPower.nid: () =>
      MainThreadPowerActor(const MainThreadPowerUnsupported()),
  MainContext.mainThreadLabelService.nid: () =>
      MainThreadLabelServiceActor(const MainThreadLabelServiceUnsupported()),
  MainContext.mainThreadNotebook.nid: () =>
      MainThreadNotebookActor(const MainThreadNotebookUnsupported()),
  MainContext.mainThreadNotebookDocuments.nid: () =>
      MainThreadNotebookDocumentsActor(
        const MainThreadNotebookDocumentsUnsupported(),
      ),
  MainContext.mainThreadNotebookEditors.nid: () =>
      MainThreadNotebookEditorsActor(
        const MainThreadNotebookEditorsUnsupported(),
      ),
  MainContext.mainThreadNotebookKernels.nid: () =>
      MainThreadNotebookKernelsActor(
        const MainThreadNotebookKernelsUnsupported(),
      ),
  MainContext.mainThreadNotebookRenderers.nid: () =>
      MainThreadNotebookRenderersActor(
        const MainThreadNotebookRenderersUnsupported(),
      ),
  MainContext.mainThreadInteractive.nid: () =>
      MainThreadInteractiveActor(const MainThreadInteractiveUnsupported()),
  MainContext.mainThreadTheming.nid: () =>
      MainThreadThemingActor(const MainThreadThemingUnsupported()),
  MainContext.mainThreadTunnelService.nid: () =>
      MainThreadTunnelServiceActor(const MainThreadTunnelServiceUnsupported()),
  MainContext.mainThreadManagedSockets.nid: () => MainThreadManagedSocketsActor(
    const MainThreadManagedSocketsUnsupported(),
  ),
  MainContext.mainThreadBrowserTunnelProxy.nid: () =>
      MainThreadBrowserTunnelProxyActor(
        const MainThreadBrowserTunnelProxyUnsupported(),
      ),
  MainContext.mainThreadTimeline.nid: () =>
      MainThreadTimelineActor(const MainThreadTimelineUnsupported()),
  MainContext.mainThreadTesting.nid: () =>
      MainThreadTestingActor(const MainThreadTestingUnsupported()),
  MainContext.mainThreadLocalization.nid: () =>
      MainThreadLocalizationActor(const MainThreadLocalizationUnsupported()),
  MainContext.mainThreadMcp.nid: () =>
      MainThreadMcpActor(const MainThreadMcpUnsupported()),
  MainContext.mainThreadAiRelatedInformation.nid: () =>
      MainThreadAiRelatedInformationActor(
        const MainThreadAiRelatedInformationUnsupported(),
      ),
  MainContext.mainThreadAiEmbeddingVector.nid: () =>
      MainThreadAiEmbeddingVectorActor(
        const MainThreadAiEmbeddingVectorUnsupported(),
      ),
  MainContext.mainThreadChatStatus.nid: () =>
      MainThreadChatStatusActor(const MainThreadChatStatusUnsupported()),
  MainContext.mainThreadChatQuota.nid: () =>
      MainThreadChatQuotaActor(const MainThreadChatQuotaUnsupported()),
  MainContext.mainThreadChatInputNotification.nid: () =>
      MainThreadChatInputNotificationActor(
        const MainThreadChatInputNotificationUnsupported(),
      ),
  MainContext.mainThreadAiSettingsSearch.nid: () =>
      MainThreadAiSettingsSearchActor(
        const MainThreadAiSettingsSearchUnsupported(),
      ),
  MainContext.mainThreadDataChannels.nid: () =>
      MainThreadDataChannelsActor(const MainThreadDataChannelsUnsupported()),
  MainContext.mainThreadChatSessions.nid: () =>
      MainThreadChatSessionsActor(const MainThreadChatSessionsUnsupported()),
  MainContext.mainThreadChatOutputRenderer.nid: () =>
      MainThreadChatOutputRendererActor(
        const MainThreadChatOutputRendererUnsupported(),
      ),
  MainContext.mainThreadChatContext.nid: () =>
      MainThreadChatContextActor(const MainThreadChatContextUnsupported()),
  MainContext.mainThreadChatDebug.nid: () =>
      MainThreadChatDebugActor(const MainThreadChatDebugUnsupported()),
  MainContext.mainThreadBrowsers.nid: () =>
      MainThreadBrowsersActor(const MainThreadBrowsersUnsupported()),
};
