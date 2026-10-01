/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/network.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: the `Schemas` namespace.

/// Upstream `Schemas`.
abstract final class Schemas {
  /// Models that exist in memory only, with no counterpart on a server.
  static const String inMemory = 'inmemory';

  /// Setting files.
  static const String vscode = 'vscode';

  /// Internal private files.
  static const String internal = 'private';

  /// A walk-through document.
  static const String walkThrough = 'walkThrough';

  /// An embedded code snippet.
  static const String walkThroughSnippet = 'walkThroughSnippet';
  static const String vscodeOnboardingSample = 'vscode-onboarding-sample';

  static const String http = 'http';
  static const String https = 'https';
  static const String file = 'file';
  static const String mailto = 'mailto';
  static const String untitled = 'untitled';
  static const String data = 'data';
  static const String command = 'command';
  static const String vscodeRemote = 'vscode-remote';
  static const String vscodeRemoteResource = 'vscode-remote-resource';
  static const String vscodeManagedRemoteResource =
      'vscode-managed-remote-resource';
  static const String vscodeUserData = 'vscode-userdata';
  static const String vscodeCustomEditor = 'vscode-custom-editor';
  static const String vscodeNotebookCell = 'vscode-notebook-cell';
  static const String vscodeNotebookCellMetadata =
      'vscode-notebook-cell-metadata';
  static const String vscodeNotebookCellMetadataDiff =
      'vscode-notebook-cell-metadata-diff';
  static const String vscodeNotebookCellOutput = 'vscode-notebook-cell-output';
  static const String vscodeNotebookCellOutputDiff =
      'vscode-notebook-cell-output-diff';
  static const String vscodeNotebookMetadata = 'vscode-notebook-metadata';
  static const String vscodeInteractiveInput = 'vscode-interactive-input';
  static const String vscodeSettings = 'vscode-settings';
  static const String vscodeWorkspaceTrust = 'vscode-workspace-trust';
  static const String vscodeTerminal = 'vscode-terminal';

  /// The image carousel editor.
  static const String vscodeImageCarousel = 'vscode-image-carousel';

  /// Code blocks in chat.
  static const String vscodeChatCodeBlock = 'vscode-chat-code-block';

  /// The left side of code compare (diff) blocks in chat.
  static const String vscodeChatCodeCompareBlock =
      'vscode-chat-code-compare-block';

  /// The chat input editor.
  static const String vscodeChatEditor = 'vscode-chat-editor';

  /// The chat input part.
  static const String vscodeChatInput = 'chatSessionInput';

  /// The Agents window new-session composer input.
  static const String sessionsChatInput = 'sessions-chat';

  /// Local chat session content.
  static const String vscodeLocalChatSession = 'vscode-chat-session';

  /// Read-only resources owned by a chat response or attachment.
  static const String vscodeChatResponseResource =
      'vscode-chat-response-resource';

  /// Agent Host terminal channels.
  static const String agentHostTerminal = 'agenthost-terminal';

  /// Subscription-backed Agent Host terminal output editors.
  static const String vscodeChatTerminalOutput = 'vscode-chat-terminal-output';

  /// Webviews not linked to a resource (not custom editors).
  static const String webviewPanel = 'webview-panel';

  /// Loading the wrapper html and script in webviews.
  static const String vscodeWebview = 'vscode-webview';

  /// Integrated browser tabs using WebContentsView.
  static const String vscodeBrowser = 'vscode-browser';

  /// Extension pages.
  static const String extension = 'extension';

  /// Replaces `file` to load files with the custom protocol handler.
  static const String vscodeFileResource = 'vscode-file';

  /// Temporary resources.
  static const String tmp = 'tmp';

  /// Live Share.
  static const String vsls = 'vsls';

  /// The Source Control commit input's text document.
  static const String vscodeSourceControl = 'vscode-scm';

  /// The input box for creating comments.
  static const String commentsInput = 'comment';

  /// Special rendering of settings in the release notes.
  static const String codeSetting = 'code-setting';

  /// Output panel resources.
  static const String outputChannel = 'output';

  /// The accessible view.
  static const String accessibleView = 'accessible-view';

  /// Snapshots of chat edits.
  static const String chatEditingSnapshotScheme =
      'chat-editing-snapshot-text-model';
  static const String chatEditingModel = 'chat-editing-text-model';

  /// Multi-diffs in copilot agent sessions.
  static const String copilotPr = 'copilot-pr';
}
