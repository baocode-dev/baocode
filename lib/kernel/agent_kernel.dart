import 'dart:async';

import 'package:flutter/widgets.dart';

import 'kernel_event.dart';
import 'kernel_types.dart';

/// An agent runtime (Claude Code, Codex, …) behind one interface: the
/// Target of its adapter. What else it can do, it declares by implementing
/// the capability interfaces below; the UI shows only what is declared.
abstract interface class AgentKernel {
  KernelDescriptor get descriptor;

  /// Everything it reports, in order, for as long as it lives.
  Stream<KernelEvent> get events;

  /// Whether it can run: starting, ready, or failed and why.
  KernelHealth get health;

  /// The id its [KernelDescriptor.catalog] keeps the conversation under,
  /// once known (e.g. after the first message); null for kernels that keep
  /// none.
  String? get sessionId;

  /// Runs [turn]; a turn id already sent is ignored.
  void send(KernelTurn turn);

  /// Answers the pending request [requestId] (once; later answers are
  /// ignored).
  void answer(String requestId, InteractionAnswer answer);

  /// Stops the running turn, if any.
  void cancel();

  /// Tries again after [KernelHealthStatus.failed].
  void restart();

  /// Gets ready ahead of use, e.g. when its conversation is shown: a
  /// runtime may start and report its options.
  void prepare();

  /// Frees what it holds while idle and out of view; it starts again when
  /// next used.
  void release();

  void dispose();

  /// Completes once what it ran has stopped (e.g. its process, after
  /// [dispose]): nothing of it writes to its session any more.
  Future<void> get stopped;
}

/// Where a kernel works and what it picks up from.
class KernelContext {
  const KernelContext({this.cwd, this.resume, this.settings = const {}});

  /// The project directory.
  final String? cwd;

  /// An earlier session to continue, as its catalog listed it.
  final SessionRecord? resume;

  /// Initial choices by [KernelChoiceKind] name, e.g. the permission mode
  /// new agents start in.
  final Map<String, String> settings;
}

// --- Capabilities -----------------------------------------------------------

/// A setting the kernel offers a choice for. What is in effect is what the
/// kernel reports, not what was last asked for.
abstract interface class KernelChoiceSource {
  List<KernelOption> get options;
  String? get selected;
  void select(String id);
}

enum KernelChoiceKind { model, mode, permission, effort }

abstract interface class SelectsModel {
  KernelChoiceSource get model;
}

/// What the agent does with a message: e.g. act on it, only discuss it,
/// or plan first.
abstract interface class SelectsMode {
  KernelChoiceSource get mode;
}

/// How the agent's actions are approved: e.g. ask each time, accept
/// edits, or no checks. Apart from [SelectsMode]: a plan, once approved,
/// is carried out with these approvals.
abstract interface class SelectsPermission {
  KernelChoiceSource get permission;
}

abstract interface class SelectsEffort {
  /// Null for models without effort levels.
  KernelChoiceSource? get effort;
}

abstract interface class ProvidesCommands {
  List<KernelCommand> get commands;
}

abstract interface class SuggestsFiles {
  Future<List<FileSuggestion>> suggestFiles(String query);
}

abstract interface class ReportsContext {
  int get contextWindow;
}

/// Reports cost and account limits (see [StatsReported]).
abstract interface class ReportsUsage {
  /// The account's limits as last known, from any session: what a session
  /// shows before it reports its own.
  List<RateLimitWindow> get accountLimits;

  /// Asks for the account's usage now, rather than wait for a reply to
  /// report it; the limits come as [StatsReported], in every session.
  Future<void> refreshUsage();
}

/// Runs tasks beside the conversation (see [TasksReported]).
abstract interface class RunsBackgroundTasks {
  void stopTask(String taskId);

  /// Moves the running command or subagent started by [toolUseId] to the
  /// background, so the turn goes on.
  void moveToBackground(String toolUseId);
}

/// Takes messages while busy, and runs them in turn.
abstract interface class QueuesMessages {
  /// Takes back a queued message not yet started.
  void cancelQueued(String turnId);
}

abstract interface class RevertsChanges {
  /// Puts back the files changed since turn [turnId] began.
  void revertChanges({required String sinceTurn});
}

abstract interface class RewindsConversation {
  /// Drops the conversation from the user message [itemId] (item [index],
  /// with [turns] turns after it) on, to go on from there.
  void rewind({required String itemId, required int index, required int turns});
}

abstract interface class RenamesSession {
  void rename(String title);
}

/// Takes pictures with a message ([KernelTurn.images]).
abstract interface class AcceptsImages {}

/// Offers what the user would likely send next, after a turn.
abstract interface class SuggestsPrompts {
  /// Null while there is none, e.g. once the user sends something.
  String? get promptSuggestion;
}

/// Uses MCP servers, and lets the user see and manage them.
abstract interface class ManagesMcpServers {
  /// As last reported; null until first asked for.
  List<McpServer>? get mcpServers;

  /// Asks for their current state.
  void refreshMcpServers();

  void setMcpServerEnabled(String name, bool enabled);

  /// Connects a failed or disconnected server again.
  void reconnectMcpServer(String name);

  /// Signs in to a server that needs it: the page where the user does,
  /// or null when there is nothing for them to do.
  Future<Uri?> authenticateMcpServer(String name);
}

// --- Sessions ------------------------------------------------------------------

/// A conversation a kernel kept, to list and continue.
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.cwd,
    this.path,
  });

  final String id;
  final String title;
  final DateTime updatedAt;

  /// The project directory it ran in.
  final String cwd;

  /// Where the kernel keeps it.
  final String? path;
}

/// A project directory and its sessions, newest first.
class ProjectRecord {
  const ProjectRecord({required this.path, required this.sessions});

  final String path;
  final List<SessionRecord> sessions;

  String get name {
    final parts = path.split('/')..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  DateTime? get updatedAt => sessions.isEmpty ? null : sessions.first.updatedAt;
}

/// The sessions a kernel has kept, by project.
abstract interface class SessionCatalog {
  Future<List<ProjectRecord>> projects();

  /// The sessions of one directory (e.g. one just opened).
  Future<List<SessionRecord>> sessionsIn(String cwd);

  /// Deletes the session [id] and everything kept with it, for good.
  /// Deleting one that is gone (or never was) does nothing.
  Future<void> delete(String id);
}

// --- Registration -----------------------------------------------------------

/// A kernel the user can pick, and how to make one.
class KernelDescriptor {
  const KernelDescriptor({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
    required this.create,
    this.catalog,
  });

  final String id;
  final String label;
  final IconData icon;
  final String description;
  final AgentKernel Function(KernelContext context) create;

  /// Its kept sessions, when it keeps any.
  final SessionCatalog? catalog;

  KernelOption get option => KernelOption(id, label, icon, description);
}

/// The event plumbing adapters share: sequence numbers and a synchronous
/// stream, so what a call causes is applied before it returns.
mixin KernelEventSource {
  final StreamController<KernelEvent> _events = StreamController.broadcast(
    sync: true,
  );
  int _seq = 0;

  Stream<KernelEvent> get events => _events.stream;

  int get nextSeq => ++_seq;

  void emit(KernelEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Tells listeners the kernel's own state changed.
  void emitInfoChanged() => emit(KernelInfoChanged(nextSeq));

  void closeEvents() => _events.close();
}

/// A [KernelChoiceSource] over a list the kernel keeps, for kernels that
/// hold the choice themselves.
class LocalChoice implements KernelChoiceSource {
  LocalChoice(this.options, {this._selected, this.onChanged});

  @override
  List<KernelOption> options;
  String? _selected;
  final void Function(String id)? onChanged;

  @override
  String? get selected => _selected ?? options.firstOrNull?.id;

  @override
  void select(String id) {
    if (id == selected) return;
    _selected = id;
    onChanged?.call(id);
  }

  /// What the kernel reports in effect, without asking for a change.
  set reported(String? id) => _selected = id;
}
