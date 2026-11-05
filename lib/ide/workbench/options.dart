// What the app gives a window that its parts show or call back (the
// IdeWorkbench widget's options, which it implements): the project and
// its chat, the editor it may build, the app's callbacks. The parts take
// them from the window as it is built, the services from
// WorkbenchEnvironment.

import 'package:flutter/widgets.dart';

import '../../chat/composer/composer_files.dart' show ComposerFile;
import '../../workspace/workspace.dart' show Project;
import '../git/commit_message.dart' show IdeCommitMessageModel;
import '../ide_agent_edits.dart' show IdeAgentEdits;
import '../ide_status_bar.dart' show IdeRemoteIndicator;
import '../ide_welcome.dart' show IdeRecentWorkspace;
import '../ide_workspace.dart';
import '../terminal/terminal_hosts.dart' show TerminalHosts;
import '../terminal/terminal_tasks.dart' show TerminalTasks;

abstract interface class WorkbenchOptions {
  /// Create Workspace...: the host's command, which asks for a workspace's
  /// name and folders.
  static const createWorkspaceCommandId = 'baocode.workspace.create';

  IdeWorkspace get workspace;
  Project get project;

  /// Whether the window is the one in front (another's keys and frames
  /// are not its).
  bool get visible;

  /// The chat beside the editor, kept as it moves.
  Widget get chat;
  ValueChanged<List<ComposerFile>>? get onAddToChat;

  /// Back to Chat's label; the default without.
  String? get backLabel;
  bool get pinned;
  ValueChanged<bool>? get onPinnedChanged;

  /// The editor, where the app builds its own (tests); the text editor
  /// natively drawn where on.
  Widget Function(BuildContext, IdeWorkspace)? get editorBuilder;
  bool get nativeEditorEnabled;

  IdeCommitMessageModel get commitMessage;
  IdeAgentEdits? get agentEdits;
  TerminalTasks? get terminalTasks;
  TerminalHosts? get terminalHosts;

  /// The start page's recent folders and workspaces.
  List<String> get recentFolders;
  ValueChanged<String>? get onOpenRecent;
  IdeRecentWorkspace? Function(String path)? get recentWorkspaceOf;

  /// A multi-folder workspace's folders added and removed.
  VoidCallback? get onAddFolder;
  ValueChanged<String>? get onRemoveFolder;

  /// The remote connection's status bar item.
  IdeRemoteIndicator? get remote;
}
