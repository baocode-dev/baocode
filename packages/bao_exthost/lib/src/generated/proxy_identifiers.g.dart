/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// GENERATED FILE - DO NOT EDIT. Regenerate with tool/generate_exthost_protocol.mjs.
//
// The extension host protocol's proxy identifiers (`MainContext`, `ExtHostContext`).
//
// Generated from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/common/extHost.protocol.ts; proxy identifier numbers from the compiled
// out/vs/workbench/api/node/extensionHostProcess.js.

/// A numbered RPC actor (`ProxyIdentifier`): [nid] on the wire, [sid] in
/// logs, [key] its name in `MainContext`/`ExtHostContext`.
final class ProxyIdentifier {
  const ProxyIdentifier(this.nid, this.sid, this.key);

  final int nid;
  final String sid;
  final String key;

  @override
  String toString() => sid;
}

/// `MainContext`: The actors on the main thread (BaoCode), which the extension host calls.
abstract final class MainContext {
  static const mainThreadAuthentication = ProxyIdentifier(
    1,
    'MainThreadAuthentication',
    'MainThreadAuthentication',
  );
  static const mainThreadBulkEdits = ProxyIdentifier(
    2,
    'MainThreadBulkEdits',
    'MainThreadBulkEdits',
  );
  static const mainThreadLanguageModels = ProxyIdentifier(
    3,
    'MainThreadLanguageModels',
    'MainThreadLanguageModels',
  );
  static const mainThreadEmbeddings = ProxyIdentifier(
    4,
    'MainThreadEmbeddings',
    'MainThreadEmbeddings',
  );
  static const mainThreadChatAgents2 = ProxyIdentifier(
    5,
    'MainThreadChatAgents2',
    'MainThreadChatAgents2',
  );
  static const mainThreadCodeMapper = ProxyIdentifier(
    6,
    'MainThreadCodeMapper',
    'MainThreadCodeMapper',
  );
  static const mainThreadLanguageModelTools = ProxyIdentifier(
    7,
    'MainThreadChatSkills',
    'MainThreadLanguageModelTools',
  );
  static const mainThreadGitExtension = ProxyIdentifier(
    8,
    'MainThreadGitExtension',
    'MainThreadGitExtension',
  );
  static const mainThreadClipboard = ProxyIdentifier(
    9,
    'MainThreadClipboard',
    'MainThreadClipboard',
  );
  static const mainThreadCommands = ProxyIdentifier(
    10,
    'MainThreadCommands',
    'MainThreadCommands',
  );
  static const mainThreadComments = ProxyIdentifier(
    11,
    'MainThreadComments',
    'MainThreadComments',
  );
  static const mainThreadConfiguration = ProxyIdentifier(
    12,
    'MainThreadConfiguration',
    'MainThreadConfiguration',
  );
  static const mainThreadConsole = ProxyIdentifier(
    13,
    'MainThreadConsole',
    'MainThreadConsole',
  );
  static const mainThreadDebugService = ProxyIdentifier(
    14,
    'MainThreadDebugService',
    'MainThreadDebugService',
  );
  static const mainThreadDecorations = ProxyIdentifier(
    15,
    'MainThreadDecorations',
    'MainThreadDecorations',
  );
  static const mainThreadDiagnostics = ProxyIdentifier(
    16,
    'MainThreadDiagnostics',
    'MainThreadDiagnostics',
  );
  static const mainThreadDialogs = ProxyIdentifier(
    17,
    'MainThreadDiaglogs',
    'MainThreadDialogs',
  );
  static const mainThreadDocuments = ProxyIdentifier(
    18,
    'MainThreadDocuments',
    'MainThreadDocuments',
  );
  static const mainThreadDocumentContentProviders = ProxyIdentifier(
    19,
    'MainThreadDocumentContentProviders',
    'MainThreadDocumentContentProviders',
  );
  static const mainThreadTextEditors = ProxyIdentifier(
    20,
    'MainThreadTextEditors',
    'MainThreadTextEditors',
  );
  static const mainThreadEditorInsets = ProxyIdentifier(
    21,
    'MainThreadEditorInsets',
    'MainThreadEditorInsets',
  );
  static const mainThreadEditorTabs = ProxyIdentifier(
    22,
    'MainThreadEditorTabs',
    'MainThreadEditorTabs',
  );
  static const mainThreadErrors = ProxyIdentifier(
    23,
    'MainThreadErrors',
    'MainThreadErrors',
  );
  static const mainThreadTreeViews = ProxyIdentifier(
    24,
    'MainThreadTreeViews',
    'MainThreadTreeViews',
  );
  static const mainThreadDownloadService = ProxyIdentifier(
    25,
    'MainThreadDownloadService',
    'MainThreadDownloadService',
  );
  static const mainThreadLanguageFeatures = ProxyIdentifier(
    26,
    'MainThreadLanguageFeatures',
    'MainThreadLanguageFeatures',
  );
  static const mainThreadLanguages = ProxyIdentifier(
    27,
    'MainThreadLanguages',
    'MainThreadLanguages',
  );
  static const mainThreadLogger = ProxyIdentifier(
    28,
    'MainThreadLogger',
    'MainThreadLogger',
  );
  static const mainThreadMessageService = ProxyIdentifier(
    29,
    'MainThreadMessageService',
    'MainThreadMessageService',
  );
  static const mainThreadOutputService = ProxyIdentifier(
    30,
    'MainThreadOutputService',
    'MainThreadOutputService',
  );
  static const mainThreadProgress = ProxyIdentifier(
    31,
    'MainThreadProgress',
    'MainThreadProgress',
  );
  static const mainThreadQuickDiff = ProxyIdentifier(
    32,
    'MainThreadQuickDiff',
    'MainThreadQuickDiff',
  );
  static const mainThreadAgentEditorComments = ProxyIdentifier(
    33,
    'MainThreadAgentEditorComments',
    'MainThreadAgentEditorComments',
  );
  static const mainThreadDocumentDiff = ProxyIdentifier(
    34,
    'MainThreadDocumentDiff',
    'MainThreadDocumentDiff',
  );
  static const mainThreadQuickOpen = ProxyIdentifier(
    35,
    'MainThreadQuickOpen',
    'MainThreadQuickOpen',
  );
  static const mainThreadStatusBar = ProxyIdentifier(
    36,
    'MainThreadStatusBar',
    'MainThreadStatusBar',
  );
  static const mainThreadSecretState = ProxyIdentifier(
    37,
    'MainThreadSecretState',
    'MainThreadSecretState',
  );
  static const mainThreadStorage = ProxyIdentifier(
    38,
    'MainThreadStorage',
    'MainThreadStorage',
  );
  static const mainThreadSpeech = ProxyIdentifier(
    39,
    'MainThreadSpeechProvider',
    'MainThreadSpeech',
  );
  static const mainThreadTelemetry = ProxyIdentifier(
    40,
    'MainThreadTelemetry',
    'MainThreadTelemetry',
  );
  static const mainThreadMeteredConnection = ProxyIdentifier(
    41,
    'MainThreadMeteredConnection',
    'MainThreadMeteredConnection',
  );
  static const mainThreadTerminalService = ProxyIdentifier(
    42,
    'MainThreadTerminalService',
    'MainThreadTerminalService',
  );
  static const mainThreadTerminalShellIntegration = ProxyIdentifier(
    43,
    'MainThreadTerminalShellIntegration',
    'MainThreadTerminalShellIntegration',
  );
  static const mainThreadWebviews = ProxyIdentifier(
    44,
    'MainThreadWebviews',
    'MainThreadWebviews',
  );
  static const mainThreadWebviewPanels = ProxyIdentifier(
    45,
    'MainThreadWebviewPanels',
    'MainThreadWebviewPanels',
  );
  static const mainThreadWebviewViews = ProxyIdentifier(
    46,
    'MainThreadWebviewViews',
    'MainThreadWebviewViews',
  );
  static const mainThreadCustomEditors = ProxyIdentifier(
    47,
    'MainThreadCustomEditors',
    'MainThreadCustomEditors',
  );
  static const mainThreadUrls = ProxyIdentifier(
    48,
    'MainThreadUrls',
    'MainThreadUrls',
  );
  static const mainThreadUriOpeners = ProxyIdentifier(
    49,
    'MainThreadUriOpeners',
    'MainThreadUriOpeners',
  );
  static const mainThreadProfileContentHandlers = ProxyIdentifier(
    50,
    'MainThreadProfileContentHandlers',
    'MainThreadProfileContentHandlers',
  );
  static const mainThreadWorkspace = ProxyIdentifier(
    51,
    'MainThreadWorkspace',
    'MainThreadWorkspace',
  );
  static const mainThreadFileSystem = ProxyIdentifier(
    52,
    'MainThreadFileSystem',
    'MainThreadFileSystem',
  );
  static const mainThreadFileSystemEventService = ProxyIdentifier(
    53,
    'MainThreadFileSystemEventService',
    'MainThreadFileSystemEventService',
  );
  static const mainThreadExtensionService = ProxyIdentifier(
    54,
    'MainThreadExtensionService',
    'MainThreadExtensionService',
  );
  static const mainThreadSCM = ProxyIdentifier(
    55,
    'MainThreadSCM',
    'MainThreadSCM',
  );
  static const mainThreadSearch = ProxyIdentifier(
    56,
    'MainThreadSearch',
    'MainThreadSearch',
  );
  static const mainThreadShare = ProxyIdentifier(
    57,
    'MainThreadShare',
    'MainThreadShare',
  );
  static const mainThreadTask = ProxyIdentifier(
    58,
    'MainThreadTask',
    'MainThreadTask',
  );
  static const mainThreadWindow = ProxyIdentifier(
    59,
    'MainThreadWindow',
    'MainThreadWindow',
  );
  static const mainThreadPower = ProxyIdentifier(
    60,
    'MainThreadPower',
    'MainThreadPower',
  );
  static const mainThreadLabelService = ProxyIdentifier(
    61,
    'MainThreadLabelService',
    'MainThreadLabelService',
  );
  static const mainThreadNotebook = ProxyIdentifier(
    62,
    'MainThreadNotebook',
    'MainThreadNotebook',
  );
  static const mainThreadNotebookDocuments = ProxyIdentifier(
    63,
    'MainThreadNotebookDocumentsShape',
    'MainThreadNotebookDocuments',
  );
  static const mainThreadNotebookEditors = ProxyIdentifier(
    64,
    'MainThreadNotebookEditorsShape',
    'MainThreadNotebookEditors',
  );
  static const mainThreadNotebookKernels = ProxyIdentifier(
    65,
    'MainThreadNotebookKernels',
    'MainThreadNotebookKernels',
  );
  static const mainThreadNotebookRenderers = ProxyIdentifier(
    66,
    'MainThreadNotebookRenderers',
    'MainThreadNotebookRenderers',
  );
  static const mainThreadInteractive = ProxyIdentifier(
    67,
    'MainThreadInteractive',
    'MainThreadInteractive',
  );
  static const mainThreadTheming = ProxyIdentifier(
    68,
    'MainThreadTheming',
    'MainThreadTheming',
  );
  static const mainThreadTunnelService = ProxyIdentifier(
    69,
    'MainThreadTunnelService',
    'MainThreadTunnelService',
  );
  static const mainThreadManagedSockets = ProxyIdentifier(
    70,
    'MainThreadManagedSockets',
    'MainThreadManagedSockets',
  );
  static const mainThreadBrowserTunnelProxy = ProxyIdentifier(
    71,
    'MainThreadBrowserTunnelProxy',
    'MainThreadBrowserTunnelProxy',
  );
  static const mainThreadTimeline = ProxyIdentifier(
    72,
    'MainThreadTimeline',
    'MainThreadTimeline',
  );
  static const mainThreadTesting = ProxyIdentifier(
    73,
    'MainThreadTesting',
    'MainThreadTesting',
  );
  static const mainThreadLocalization = ProxyIdentifier(
    74,
    'MainThreadLocalizationShape',
    'MainThreadLocalization',
  );
  static const mainThreadMcp = ProxyIdentifier(
    75,
    'MainThreadMcpShape',
    'MainThreadMcp',
  );
  static const mainThreadAiRelatedInformation = ProxyIdentifier(
    76,
    'MainThreadAiRelatedInformation',
    'MainThreadAiRelatedInformation',
  );
  static const mainThreadAiEmbeddingVector = ProxyIdentifier(
    77,
    'MainThreadAiEmbeddingVector',
    'MainThreadAiEmbeddingVector',
  );
  static const mainThreadChatStatus = ProxyIdentifier(
    78,
    'MainThreadChatStatus',
    'MainThreadChatStatus',
  );
  static const mainThreadChatQuota = ProxyIdentifier(
    79,
    'MainThreadChatQuota',
    'MainThreadChatQuota',
  );
  static const mainThreadChatInputNotification = ProxyIdentifier(
    80,
    'MainThreadChatInputNotification',
    'MainThreadChatInputNotification',
  );
  static const mainThreadAiSettingsSearch = ProxyIdentifier(
    81,
    'MainThreadAiSettingsSearch',
    'MainThreadAiSettingsSearch',
  );
  static const mainThreadDataChannels = ProxyIdentifier(
    82,
    'MainThreadDataChannels',
    'MainThreadDataChannels',
  );
  static const mainThreadChatSessions = ProxyIdentifier(
    83,
    'MainThreadChatSessions',
    'MainThreadChatSessions',
  );
  static const mainThreadChatOutputRenderer = ProxyIdentifier(
    84,
    'MainThreadChatOutputRenderer',
    'MainThreadChatOutputRenderer',
  );
  static const mainThreadChatContext = ProxyIdentifier(
    85,
    'MainThreadChatContext',
    'MainThreadChatContext',
  );
  static const mainThreadChatDebug = ProxyIdentifier(
    86,
    'MainThreadChatDebug',
    'MainThreadChatDebug',
  );
  static const mainThreadBrowsers = ProxyIdentifier(
    87,
    'MainThreadBrowsers',
    'MainThreadBrowsers',
  );

  static const all = [
    mainThreadAuthentication,
    mainThreadBulkEdits,
    mainThreadLanguageModels,
    mainThreadEmbeddings,
    mainThreadChatAgents2,
    mainThreadCodeMapper,
    mainThreadLanguageModelTools,
    mainThreadGitExtension,
    mainThreadClipboard,
    mainThreadCommands,
    mainThreadComments,
    mainThreadConfiguration,
    mainThreadConsole,
    mainThreadDebugService,
    mainThreadDecorations,
    mainThreadDiagnostics,
    mainThreadDialogs,
    mainThreadDocuments,
    mainThreadDocumentContentProviders,
    mainThreadTextEditors,
    mainThreadEditorInsets,
    mainThreadEditorTabs,
    mainThreadErrors,
    mainThreadTreeViews,
    mainThreadDownloadService,
    mainThreadLanguageFeatures,
    mainThreadLanguages,
    mainThreadLogger,
    mainThreadMessageService,
    mainThreadOutputService,
    mainThreadProgress,
    mainThreadQuickDiff,
    mainThreadAgentEditorComments,
    mainThreadDocumentDiff,
    mainThreadQuickOpen,
    mainThreadStatusBar,
    mainThreadSecretState,
    mainThreadStorage,
    mainThreadSpeech,
    mainThreadTelemetry,
    mainThreadMeteredConnection,
    mainThreadTerminalService,
    mainThreadTerminalShellIntegration,
    mainThreadWebviews,
    mainThreadWebviewPanels,
    mainThreadWebviewViews,
    mainThreadCustomEditors,
    mainThreadUrls,
    mainThreadUriOpeners,
    mainThreadProfileContentHandlers,
    mainThreadWorkspace,
    mainThreadFileSystem,
    mainThreadFileSystemEventService,
    mainThreadExtensionService,
    mainThreadSCM,
    mainThreadSearch,
    mainThreadShare,
    mainThreadTask,
    mainThreadWindow,
    mainThreadPower,
    mainThreadLabelService,
    mainThreadNotebook,
    mainThreadNotebookDocuments,
    mainThreadNotebookEditors,
    mainThreadNotebookKernels,
    mainThreadNotebookRenderers,
    mainThreadInteractive,
    mainThreadTheming,
    mainThreadTunnelService,
    mainThreadManagedSockets,
    mainThreadBrowserTunnelProxy,
    mainThreadTimeline,
    mainThreadTesting,
    mainThreadLocalization,
    mainThreadMcp,
    mainThreadAiRelatedInformation,
    mainThreadAiEmbeddingVector,
    mainThreadChatStatus,
    mainThreadChatQuota,
    mainThreadChatInputNotification,
    mainThreadAiSettingsSearch,
    mainThreadDataChannels,
    mainThreadChatSessions,
    mainThreadChatOutputRenderer,
    mainThreadChatContext,
    mainThreadChatDebug,
    mainThreadBrowsers,
  ];
}

/// `ExtHostContext`: The actors in the extension host, which the main thread calls.
abstract final class ExtHostContext {
  static const extHostCodeMapper = ProxyIdentifier(
    88,
    'ExtHostCodeMapper',
    'ExtHostCodeMapper',
  );
  static const extHostCommands = ProxyIdentifier(
    89,
    'ExtHostCommands',
    'ExtHostCommands',
  );
  static const extHostConfiguration = ProxyIdentifier(
    90,
    'ExtHostConfiguration',
    'ExtHostConfiguration',
  );
  static const extHostDiagnostics = ProxyIdentifier(
    91,
    'ExtHostDiagnostics',
    'ExtHostDiagnostics',
  );
  static const extHostDebugService = ProxyIdentifier(
    92,
    'ExtHostDebugService',
    'ExtHostDebugService',
  );
  static const extHostDecorations = ProxyIdentifier(
    93,
    'ExtHostDecorations',
    'ExtHostDecorations',
  );
  static const extHostDocumentsAndEditors = ProxyIdentifier(
    94,
    'ExtHostDocumentsAndEditors',
    'ExtHostDocumentsAndEditors',
  );
  static const extHostDocuments = ProxyIdentifier(
    95,
    'ExtHostDocuments',
    'ExtHostDocuments',
  );
  static const extHostDocumentContentProviders = ProxyIdentifier(
    96,
    'ExtHostDocumentContentProviders',
    'ExtHostDocumentContentProviders',
  );
  static const extHostDocumentSaveParticipant = ProxyIdentifier(
    97,
    'ExtHostDocumentSaveParticipant',
    'ExtHostDocumentSaveParticipant',
  );
  static const extHostEditors = ProxyIdentifier(
    98,
    'ExtHostEditors',
    'ExtHostEditors',
  );
  static const extHostTreeViews = ProxyIdentifier(
    99,
    'ExtHostTreeViews',
    'ExtHostTreeViews',
  );
  static const extHostFileSystem = ProxyIdentifier(
    100,
    'ExtHostFileSystem',
    'ExtHostFileSystem',
  );
  static const extHostFileSystemInfo = ProxyIdentifier(
    101,
    'ExtHostFileSystemInfo',
    'ExtHostFileSystemInfo',
  );
  static const extHostFileSystemEventService = ProxyIdentifier(
    102,
    'ExtHostFileSystemEventService',
    'ExtHostFileSystemEventService',
  );
  static const extHostLanguages = ProxyIdentifier(
    103,
    'ExtHostLanguages',
    'ExtHostLanguages',
  );
  static const extHostLanguageFeatures = ProxyIdentifier(
    104,
    'ExtHostLanguageFeatures',
    'ExtHostLanguageFeatures',
  );
  static const extHostQuickOpen = ProxyIdentifier(
    105,
    'ExtHostQuickOpen',
    'ExtHostQuickOpen',
  );
  static const extHostQuickDiff = ProxyIdentifier(
    106,
    'ExtHostQuickDiff',
    'ExtHostQuickDiff',
  );
  static const extHostAgentEditorComments = ProxyIdentifier(
    107,
    'ExtHostAgentEditorComments',
    'ExtHostAgentEditorComments',
  );
  static const extHostStatusBar = ProxyIdentifier(
    108,
    'ExtHostStatusBar',
    'ExtHostStatusBar',
  );
  static const extHostShare = ProxyIdentifier(
    109,
    'ExtHostShare',
    'ExtHostShare',
  );
  static const extHostExtensionService = ProxyIdentifier(
    110,
    'ExtHostExtensionService',
    'ExtHostExtensionService',
  );
  static const extHostLogLevelServiceShape = ProxyIdentifier(
    111,
    'ExtHostLogLevelServiceShape',
    'ExtHostLogLevelServiceShape',
  );
  static const extHostTerminalService = ProxyIdentifier(
    112,
    'ExtHostTerminalService',
    'ExtHostTerminalService',
  );
  static const extHostTerminalShellIntegration = ProxyIdentifier(
    113,
    'ExtHostTerminalShellIntegration',
    'ExtHostTerminalShellIntegration',
  );
  static const extHostSCM = ProxyIdentifier(114, 'ExtHostSCM', 'ExtHostSCM');
  static const extHostSearch = ProxyIdentifier(
    115,
    'ExtHostSearch',
    'ExtHostSearch',
  );
  static const extHostTask = ProxyIdentifier(116, 'ExtHostTask', 'ExtHostTask');
  static const extHostWorkspace = ProxyIdentifier(
    117,
    'ExtHostWorkspace',
    'ExtHostWorkspace',
  );
  static const extHostWindow = ProxyIdentifier(
    118,
    'ExtHostWindow',
    'ExtHostWindow',
  );
  static const extHostPower = ProxyIdentifier(
    119,
    'ExtHostPower',
    'ExtHostPower',
  );
  static const extHostWebviews = ProxyIdentifier(
    120,
    'ExtHostWebviews',
    'ExtHostWebviews',
  );
  static const extHostWebviewPanels = ProxyIdentifier(
    121,
    'ExtHostWebviewPanels',
    'ExtHostWebviewPanels',
  );
  static const extHostCustomEditors = ProxyIdentifier(
    122,
    'ExtHostCustomEditors',
    'ExtHostCustomEditors',
  );
  static const extHostWebviewViews = ProxyIdentifier(
    123,
    'ExtHostWebviewViews',
    'ExtHostWebviewViews',
  );
  static const extHostEditorInsets = ProxyIdentifier(
    124,
    'ExtHostEditorInsets',
    'ExtHostEditorInsets',
  );
  static const extHostEditorTabs = ProxyIdentifier(
    125,
    'ExtHostEditorTabs',
    'ExtHostEditorTabs',
  );
  static const extHostProgress = ProxyIdentifier(
    126,
    'ExtHostProgress',
    'ExtHostProgress',
  );
  static const extHostComments = ProxyIdentifier(
    127,
    'ExtHostComments',
    'ExtHostComments',
  );
  static const extHostSecretState = ProxyIdentifier(
    128,
    'ExtHostSecretState',
    'ExtHostSecretState',
  );
  static const extHostStorage = ProxyIdentifier(
    129,
    'ExtHostStorage',
    'ExtHostStorage',
  );
  static const extHostUrls = ProxyIdentifier(130, 'ExtHostUrls', 'ExtHostUrls');
  static const extHostUriOpeners = ProxyIdentifier(
    131,
    'ExtHostUriOpeners',
    'ExtHostUriOpeners',
  );
  static const extHostChatOutputRenderer = ProxyIdentifier(
    132,
    'ExtHostChatOutputRenderer',
    'ExtHostChatOutputRenderer',
  );
  static const extHostProfileContentHandlers = ProxyIdentifier(
    133,
    'ExtHostProfileContentHandlers',
    'ExtHostProfileContentHandlers',
  );
  static const extHostOutputService = ProxyIdentifier(
    134,
    'ExtHostOutputService',
    'ExtHostOutputService',
  );
  static const extHostLabelService = ProxyIdentifier(
    135,
    'ExtHostLabelService',
    'ExtHostLabelService',
  );
  static const extHostNotebook = ProxyIdentifier(
    136,
    'ExtHostNotebook',
    'ExtHostNotebook',
  );
  static const extHostNotebookDocuments = ProxyIdentifier(
    137,
    'ExtHostNotebookDocuments',
    'ExtHostNotebookDocuments',
  );
  static const extHostNotebookEditors = ProxyIdentifier(
    138,
    'ExtHostNotebookEditors',
    'ExtHostNotebookEditors',
  );
  static const extHostNotebookKernels = ProxyIdentifier(
    139,
    'ExtHostNotebookKernels',
    'ExtHostNotebookKernels',
  );
  static const extHostNotebookRenderers = ProxyIdentifier(
    140,
    'ExtHostNotebookRenderers',
    'ExtHostNotebookRenderers',
  );
  static const extHostNotebookDocumentSaveParticipant = ProxyIdentifier(
    141,
    'ExtHostNotebookDocumentSaveParticipant',
    'ExtHostNotebookDocumentSaveParticipant',
  );
  static const extHostInteractive = ProxyIdentifier(
    142,
    'ExtHostInteractive',
    'ExtHostInteractive',
  );
  static const extHostChatAgents2 = ProxyIdentifier(
    143,
    'ExtHostChatAgents',
    'ExtHostChatAgents2',
  );
  static const extHostLanguageModelTools = ProxyIdentifier(
    144,
    'ExtHostChatSkills',
    'ExtHostLanguageModelTools',
  );
  static const extHostChatProvider = ProxyIdentifier(
    145,
    'ExtHostChatProvider',
    'ExtHostChatProvider',
  );
  static const extHostChatContext = ProxyIdentifier(
    146,
    'ExtHostChatContext',
    'ExtHostChatContext',
  );
  static const extHostChatDebug = ProxyIdentifier(
    147,
    'ExtHostChatDebug',
    'ExtHostChatDebug',
  );
  static const extHostSpeech = ProxyIdentifier(
    148,
    'ExtHostSpeech',
    'ExtHostSpeech',
  );
  static const extHostEmbeddings = ProxyIdentifier(
    149,
    'ExtHostEmbeddings',
    'ExtHostEmbeddings',
  );
  static const extHostAiRelatedInformation = ProxyIdentifier(
    150,
    'ExtHostAiRelatedInformation',
    'ExtHostAiRelatedInformation',
  );
  static const extHostAiEmbeddingVector = ProxyIdentifier(
    151,
    'ExtHostAiEmbeddingVector',
    'ExtHostAiEmbeddingVector',
  );
  static const extHostAiSettingsSearch = ProxyIdentifier(
    152,
    'ExtHostAiSettingsSearch',
    'ExtHostAiSettingsSearch',
  );
  static const extHostTheming = ProxyIdentifier(
    153,
    'ExtHostTheming',
    'ExtHostTheming',
  );
  static const extHostTunnelService = ProxyIdentifier(
    154,
    'ExtHostTunnelService',
    'ExtHostTunnelService',
  );
  static const extHostManagedSockets = ProxyIdentifier(
    155,
    'ExtHostManagedSockets',
    'ExtHostManagedSockets',
  );
  static const extHostBrowserTunnelProxy = ProxyIdentifier(
    156,
    'ExtHostBrowserTunnelProxy',
    'ExtHostBrowserTunnelProxy',
  );
  static const extHostAuthentication = ProxyIdentifier(
    157,
    'ExtHostAuthentication',
    'ExtHostAuthentication',
  );
  static const extHostTimeline = ProxyIdentifier(
    158,
    'ExtHostTimeline',
    'ExtHostTimeline',
  );
  static const extHostTesting = ProxyIdentifier(
    159,
    'ExtHostTesting',
    'ExtHostTesting',
  );
  static const extHostTelemetry = ProxyIdentifier(
    160,
    'ExtHostTelemetry',
    'ExtHostTelemetry',
  );
  static const extHostMeteredConnection = ProxyIdentifier(
    161,
    'ExtHostMeteredConnection',
    'ExtHostMeteredConnection',
  );
  static const extHostLocalization = ProxyIdentifier(
    162,
    'ExtHostLocalization',
    'ExtHostLocalization',
  );
  static const extHostMcp = ProxyIdentifier(163, 'ExtHostMcp', 'ExtHostMcp');
  static const extHostDataChannels = ProxyIdentifier(
    164,
    'ExtHostDataChannels',
    'ExtHostDataChannels',
  );
  static const extHostChatSessions = ProxyIdentifier(
    165,
    'ExtHostChatSessions',
    'ExtHostChatSessions',
  );
  static const extHostChatQuota = ProxyIdentifier(
    166,
    'ExtHostChatQuota',
    'ExtHostChatQuota',
  );
  static const extHostGitExtension = ProxyIdentifier(
    167,
    'ExtHostGitExtension',
    'ExtHostGitExtension',
  );
  static const extHostBrowsers = ProxyIdentifier(
    168,
    'ExtHostBrowsers',
    'ExtHostBrowsers',
  );

  static const all = [
    extHostCodeMapper,
    extHostCommands,
    extHostConfiguration,
    extHostDiagnostics,
    extHostDebugService,
    extHostDecorations,
    extHostDocumentsAndEditors,
    extHostDocuments,
    extHostDocumentContentProviders,
    extHostDocumentSaveParticipant,
    extHostEditors,
    extHostTreeViews,
    extHostFileSystem,
    extHostFileSystemInfo,
    extHostFileSystemEventService,
    extHostLanguages,
    extHostLanguageFeatures,
    extHostQuickOpen,
    extHostQuickDiff,
    extHostAgentEditorComments,
    extHostStatusBar,
    extHostShare,
    extHostExtensionService,
    extHostLogLevelServiceShape,
    extHostTerminalService,
    extHostTerminalShellIntegration,
    extHostSCM,
    extHostSearch,
    extHostTask,
    extHostWorkspace,
    extHostWindow,
    extHostPower,
    extHostWebviews,
    extHostWebviewPanels,
    extHostCustomEditors,
    extHostWebviewViews,
    extHostEditorInsets,
    extHostEditorTabs,
    extHostProgress,
    extHostComments,
    extHostSecretState,
    extHostStorage,
    extHostUrls,
    extHostUriOpeners,
    extHostChatOutputRenderer,
    extHostProfileContentHandlers,
    extHostOutputService,
    extHostLabelService,
    extHostNotebook,
    extHostNotebookDocuments,
    extHostNotebookEditors,
    extHostNotebookKernels,
    extHostNotebookRenderers,
    extHostNotebookDocumentSaveParticipant,
    extHostInteractive,
    extHostChatAgents2,
    extHostLanguageModelTools,
    extHostChatProvider,
    extHostChatContext,
    extHostChatDebug,
    extHostSpeech,
    extHostEmbeddings,
    extHostAiRelatedInformation,
    extHostAiEmbeddingVector,
    extHostAiSettingsSearch,
    extHostTheming,
    extHostTunnelService,
    extHostManagedSockets,
    extHostBrowserTunnelProxy,
    extHostAuthentication,
    extHostTimeline,
    extHostTesting,
    extHostTelemetry,
    extHostMeteredConnection,
    extHostLocalization,
    extHostMcp,
    extHostDataChannels,
    extHostChatSessions,
    extHostChatQuota,
    extHostGitExtension,
    extHostBrowsers,
  ];
}

/// Every proxy identifier's [ProxyIdentifier.sid], by [ProxyIdentifier.nid].
const Map<int, String> proxyIdentifierNames = {
  1: 'MainThreadAuthentication',
  2: 'MainThreadBulkEdits',
  3: 'MainThreadLanguageModels',
  4: 'MainThreadEmbeddings',
  5: 'MainThreadChatAgents2',
  6: 'MainThreadCodeMapper',
  7: 'MainThreadChatSkills',
  8: 'MainThreadGitExtension',
  9: 'MainThreadClipboard',
  10: 'MainThreadCommands',
  11: 'MainThreadComments',
  12: 'MainThreadConfiguration',
  13: 'MainThreadConsole',
  14: 'MainThreadDebugService',
  15: 'MainThreadDecorations',
  16: 'MainThreadDiagnostics',
  17: 'MainThreadDiaglogs',
  18: 'MainThreadDocuments',
  19: 'MainThreadDocumentContentProviders',
  20: 'MainThreadTextEditors',
  21: 'MainThreadEditorInsets',
  22: 'MainThreadEditorTabs',
  23: 'MainThreadErrors',
  24: 'MainThreadTreeViews',
  25: 'MainThreadDownloadService',
  26: 'MainThreadLanguageFeatures',
  27: 'MainThreadLanguages',
  28: 'MainThreadLogger',
  29: 'MainThreadMessageService',
  30: 'MainThreadOutputService',
  31: 'MainThreadProgress',
  32: 'MainThreadQuickDiff',
  33: 'MainThreadAgentEditorComments',
  34: 'MainThreadDocumentDiff',
  35: 'MainThreadQuickOpen',
  36: 'MainThreadStatusBar',
  37: 'MainThreadSecretState',
  38: 'MainThreadStorage',
  39: 'MainThreadSpeechProvider',
  40: 'MainThreadTelemetry',
  41: 'MainThreadMeteredConnection',
  42: 'MainThreadTerminalService',
  43: 'MainThreadTerminalShellIntegration',
  44: 'MainThreadWebviews',
  45: 'MainThreadWebviewPanels',
  46: 'MainThreadWebviewViews',
  47: 'MainThreadCustomEditors',
  48: 'MainThreadUrls',
  49: 'MainThreadUriOpeners',
  50: 'MainThreadProfileContentHandlers',
  51: 'MainThreadWorkspace',
  52: 'MainThreadFileSystem',
  53: 'MainThreadFileSystemEventService',
  54: 'MainThreadExtensionService',
  55: 'MainThreadSCM',
  56: 'MainThreadSearch',
  57: 'MainThreadShare',
  58: 'MainThreadTask',
  59: 'MainThreadWindow',
  60: 'MainThreadPower',
  61: 'MainThreadLabelService',
  62: 'MainThreadNotebook',
  63: 'MainThreadNotebookDocumentsShape',
  64: 'MainThreadNotebookEditorsShape',
  65: 'MainThreadNotebookKernels',
  66: 'MainThreadNotebookRenderers',
  67: 'MainThreadInteractive',
  68: 'MainThreadTheming',
  69: 'MainThreadTunnelService',
  70: 'MainThreadManagedSockets',
  71: 'MainThreadBrowserTunnelProxy',
  72: 'MainThreadTimeline',
  73: 'MainThreadTesting',
  74: 'MainThreadLocalizationShape',
  75: 'MainThreadMcpShape',
  76: 'MainThreadAiRelatedInformation',
  77: 'MainThreadAiEmbeddingVector',
  78: 'MainThreadChatStatus',
  79: 'MainThreadChatQuota',
  80: 'MainThreadChatInputNotification',
  81: 'MainThreadAiSettingsSearch',
  82: 'MainThreadDataChannels',
  83: 'MainThreadChatSessions',
  84: 'MainThreadChatOutputRenderer',
  85: 'MainThreadChatContext',
  86: 'MainThreadChatDebug',
  87: 'MainThreadBrowsers',
  88: 'ExtHostCodeMapper',
  89: 'ExtHostCommands',
  90: 'ExtHostConfiguration',
  91: 'ExtHostDiagnostics',
  92: 'ExtHostDebugService',
  93: 'ExtHostDecorations',
  94: 'ExtHostDocumentsAndEditors',
  95: 'ExtHostDocuments',
  96: 'ExtHostDocumentContentProviders',
  97: 'ExtHostDocumentSaveParticipant',
  98: 'ExtHostEditors',
  99: 'ExtHostTreeViews',
  100: 'ExtHostFileSystem',
  101: 'ExtHostFileSystemInfo',
  102: 'ExtHostFileSystemEventService',
  103: 'ExtHostLanguages',
  104: 'ExtHostLanguageFeatures',
  105: 'ExtHostQuickOpen',
  106: 'ExtHostQuickDiff',
  107: 'ExtHostAgentEditorComments',
  108: 'ExtHostStatusBar',
  109: 'ExtHostShare',
  110: 'ExtHostExtensionService',
  111: 'ExtHostLogLevelServiceShape',
  112: 'ExtHostTerminalService',
  113: 'ExtHostTerminalShellIntegration',
  114: 'ExtHostSCM',
  115: 'ExtHostSearch',
  116: 'ExtHostTask',
  117: 'ExtHostWorkspace',
  118: 'ExtHostWindow',
  119: 'ExtHostPower',
  120: 'ExtHostWebviews',
  121: 'ExtHostWebviewPanels',
  122: 'ExtHostCustomEditors',
  123: 'ExtHostWebviewViews',
  124: 'ExtHostEditorInsets',
  125: 'ExtHostEditorTabs',
  126: 'ExtHostProgress',
  127: 'ExtHostComments',
  128: 'ExtHostSecretState',
  129: 'ExtHostStorage',
  130: 'ExtHostUrls',
  131: 'ExtHostUriOpeners',
  132: 'ExtHostChatOutputRenderer',
  133: 'ExtHostProfileContentHandlers',
  134: 'ExtHostOutputService',
  135: 'ExtHostLabelService',
  136: 'ExtHostNotebook',
  137: 'ExtHostNotebookDocuments',
  138: 'ExtHostNotebookEditors',
  139: 'ExtHostNotebookKernels',
  140: 'ExtHostNotebookRenderers',
  141: 'ExtHostNotebookDocumentSaveParticipant',
  142: 'ExtHostInteractive',
  143: 'ExtHostChatAgents',
  144: 'ExtHostChatSkills',
  145: 'ExtHostChatProvider',
  146: 'ExtHostChatContext',
  147: 'ExtHostChatDebug',
  148: 'ExtHostSpeech',
  149: 'ExtHostEmbeddings',
  150: 'ExtHostAiRelatedInformation',
  151: 'ExtHostAiEmbeddingVector',
  152: 'ExtHostAiSettingsSearch',
  153: 'ExtHostTheming',
  154: 'ExtHostTunnelService',
  155: 'ExtHostManagedSockets',
  156: 'ExtHostBrowserTunnelProxy',
  157: 'ExtHostAuthentication',
  158: 'ExtHostTimeline',
  159: 'ExtHostTesting',
  160: 'ExtHostTelemetry',
  161: 'ExtHostMeteredConnection',
  162: 'ExtHostLocalization',
  163: 'ExtHostMcp',
  164: 'ExtHostDataChannels',
  165: 'ExtHostChatSessions',
  166: 'ExtHostChatQuota',
  167: 'ExtHostGitExtension',
  168: 'ExtHostBrowsers',
};
