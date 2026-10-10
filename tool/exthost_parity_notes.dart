// Why the shapes EXTHOST_PARITY.md lists as not (fully) supported are not,
// and which supported ones only accept what they are told (see
// tool/generate_exthost_parity.dart, which warns when a shape with
// unsupported methods has no reason here, or a reason is left for a shape
// that is done). "Proposed" means upstream checks `enabledApiProposals`
// (`checkProposedApiEnabled`) before the extension can call it.

const _chat =
    "VS Code's chat and AI features: BaoCode's workbench has no chat view, "
    'language model service, chat participants or MCP host of VS Code\'s '
    '(its agents are its own, outside the extension host). What extensions '
    'register here is answered as unsupported; their other features work.';

const _remoteResolvers =
    "Proposed `resolvers`: a remote reached through an extension's resolver. "
    "BaoCode's SSH remote is built in (its own connection and runtime "
    'install), not an extension resolver.';

/// Why a shape's unsupported methods are not implemented.
const exthostUnsupportedReasons = <String, String>{
  'MainThreadLanguageModels': _chat,
  'MainThreadEmbeddings': _chat,
  'MainThreadChatAgents2': _chat,
  'MainThreadCodeMapper': _chat,
  'MainThreadLanguageModelTools':
      '`\$countTokensForInvocation` is asked while a chat invokes a tool; '
      'there is no chat (the tools are accepted, see below).',
  'MainThreadGitExtension':
      "Repository changes for the workbench's Git extension service, which "
      "upstream's chat reads; BaoCode has no such service. The built-in Git "
      "extension's source control works (MainThreadSCM).",
  'MainThreadComments':
      'The stable `vscode.comments` API (comment threads in the editor, e.g. '
      "GitHub Pull Requests' review comments): BaoCode's editor has no "
      'comment thread widget (a zone between lines with its own editor and '
      'reply box). Not ported.',
  'MainThreadEditorInsets':
      'Proposed `editorInsets`: a webview inside the editor. BaoCode has no '
      'webviews (九.5).',
  'MainThreadTreeViews':
      "`\$resolveDropFileData`: files dropped on an extension's tree view. "
      "BaoCode's tree views have no drag and drop.",
  'MainThreadLanguages':
      '`\$computeFullSyntaxHighlighting`: proposed '
      '`documentSyntaxHighlighting`.',
  'MainThreadQuickDiff':
      "A source control's `quickDiffProvider` (the original of a file for "
      "the editor's change markers): BaoCode's editor does not take quick "
      "diffs from extensions; its Git views come from its own Git (lib/ide/git).",
  'MainThreadAgentEditorComments': _chat,
  'MainThreadDocumentDiff': 'Proposed `documentDiff`.',
  'MainThreadSpeech': 'Proposed `speech`: BaoCode has no voice input.',
  'MainThreadUriOpeners':
      'Proposed `externalUriOpener`: links open in the system browser.',
  'MainThreadShare': 'Proposed `shareProvider`: BaoCode has no Share menu.',
  'MainThreadNotebookKernels':
      'Cell executions: BaoCode has no notebook editor (九.5), so no cell is '
      'run. Kernels are accepted so that Jupyter and the like activate.',
  'MainThreadTunnelService':
      'Proposed `tunnels` and port forwarding: BaoCode has no Ports view or '
      'port forwarding. Port attributes are accepted (see below).',
  'MainThreadManagedSockets': _remoteResolvers,
  'MainThreadBrowserTunnelProxy': _remoteResolvers,
  'MainThreadMcp': _chat,
  'MainThreadAiRelatedInformation': _chat,
  'MainThreadAiEmbeddingVector': _chat,
  'MainThreadChatStatus': _chat,
  'MainThreadChatQuota': _chat,
  'MainThreadChatInputNotification': _chat,
  'MainThreadAiSettingsSearch': _chat,
  'MainThreadChatSessions': _chat,
  'MainThreadChatOutputRenderer': _chat,
  'MainThreadChatContext': _chat,
  'MainThreadChatDebug': _chat,
  'MainThreadBrowsers':
      'Proposed `browser` (browser tabs and their DevTools protocol): '
      'BaoCode has no browser tabs.',
};

/// Shapes implemented in full that only accept what extensions register:
/// what they would show has no place in BaoCode.
const exthostDegradedShapes = <String, String>{
  'MainThreadWebviews':
      'Webviews (九.5): none is shown; a placeholder names the extension, '
      'with a line in the "Extension Host" output; its other features work '
      '(lib/extensions/main_thread/main_thread_webviews.dart).',
  'MainThreadWebviewPanels': 'As MainThreadWebviews.',
  'MainThreadWebviewViews': 'As MainThreadWebviews.',
  'MainThreadCustomEditors':
      "As MainThreadWebviews; the documents open in BaoCode's own editors.",
  'MainThreadNotebook':
      'Notebooks (九.5): serializers are recorded, never asked for a '
      'notebook (the files open as text); opening or showing one fails with '
      'a notice (lib/extensions/main_thread/main_thread_notebook.dart).',
  'MainThreadNotebookDocuments': 'As MainThreadNotebook.',
  'MainThreadNotebookEditors': 'As MainThreadNotebook.',
  'MainThreadNotebookRenderers': 'As MainThreadNotebook.',
  'MainThreadLanguageModelTools':
      'Tools are kept, none listed or invoked: there is no chat.',
  'MainThreadProfileContentHandlers': 'No profile export to share.',
  'MainThreadTimeline': 'No Timeline view.',
  'MainThreadDataChannels': 'Link presentation: no chat to present links in.',
  'MainThreadTunnelService':
      'Port attributes and the remote port finder are kept: no Ports view.',
};
