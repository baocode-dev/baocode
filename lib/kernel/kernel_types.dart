import 'package:flutter/widgets.dart';

import '../chat/chat_models.dart';

/// One entry of a kernel's choice, e.g. a model or a mode.
class KernelOption {
  const KernelOption(
    this.id,
    this.label,
    this.icon,
    this.description, {
    this.caution = false,
    this.iconBuilder,
    this.group,
  });

  /// What the kernel is told (a model name, a permission mode, …).
  final String id;
  final String label;
  final IconData icon;
  final String description;

  /// Risky to pick (e.g. no permission checks): shown as a warning.
  final bool caution;

  /// Drawn in place of [icon], at a size and in a color (a project's own
  /// icon).
  final Widget Function(double size, Color color)? iconBuilder;

  /// What it is listed under, e.g. the provider of a model.
  final KernelOptionGroup? group;

  @override
  bool operator ==(Object other) =>
      other is KernelOption &&
      other.id == id &&
      other.label == label &&
      other.description == description &&
      other.caution == caution &&
      other.group == group;

  @override
  int get hashCode => Object.hash(id, label, description, caution, group);
}

/// Options listed together under a heading, e.g. a provider's models.
class KernelOptionGroup {
  const KernelOptionGroup(this.id, this.label, {this.warning});

  final String id;
  final String label;

  /// What went wrong with it, marked on its heading.
  final String? warning;

  @override
  bool operator ==(Object other) =>
      other is KernelOptionGroup &&
      other.id == id &&
      other.label == label &&
      other.warning == warning;

  @override
  int get hashCode => Object.hash(id, label, warning);
}

/// A `/command` a kernel understands.
class KernelCommand {
  const KernelCommand(
    this.name,
    this.description,
    this.icon, {
    this.argumentHint = '',
  });

  final String name;
  final String description;
  final IconData icon;

  /// What may follow it, e.g. `[low|medium|high]`.
  final String argumentHint;
}

/// A file the kernel offers for an `@mention`, relative to the project.
class FileSuggestion {
  const FileSuggestion(this.path);

  final String path;

  bool get isDirectory => path.endsWith('/');
}

enum ContextKind {
  /// Occupies the window.
  used,

  /// Left to fill.
  free,

  /// Kept back for compaction.
  buffer,

  /// Out of the window until needed (e.g. deferred tool schemas).
  deferred,
}

class ContextSegment {
  const ContextSegment(this.label, this.tokens, {this.kind = ContextKind.used});

  final String label;
  final int tokens;
  final ContextKind kind;
}

/// How full the context window is, as last reported: a snapshot that
/// replaces the one before.
class ContextUsage {
  const ContextUsage({
    required this.window,
    required this.used,
    this.segments = const [],
  });

  final int window;
  final int used;

  /// What the tokens are spent on, when the kernel says; else empty.
  final List<ContextSegment> segments;

  double get fraction => window == 0 ? 0 : used / window;
}

/// A usage limit of the account, e.g. its five-hour window.
class RateLimitWindow {
  const RateLimitWindow(this.label, this.utilization, {this.resetsAt});

  final String label;

  /// 0 to 1.
  final double utilization;
  final DateTime? resetsAt;
}

/// Where asking for the account's limits stands.
enum LimitsState {
  /// Not being asked for; or they do not apply (e.g. an API key).
  idle,
  checking,

  /// Asked for, and not told.
  unavailable,

  /// Not to be asked for: the user has turned that off (see
  /// [UsageStats.limitsOffBy]). Replies may still tell them.
  off,
}

/// What the session has cost so far, and the account's limits.
class UsageStats {
  const UsageStats({
    this.costUsd,
    this.limits = const [],
    this.limitsState = LimitsState.idle,
    this.limitsOffBy,
  });

  final double? costUsd;
  final List<RateLimitWindow> limits;
  final LimitsState limitsState;

  /// The setting that turned asking for the limits [LimitsState.off].
  final String? limitsOffBy;
}

/// What the agent is busy with while nothing of it shows: waiting on its
/// model, or compacting the conversation.
enum KernelActivityKind { waiting, compacting }

class KernelActivity {
  const KernelActivity(this.kind, this.since);

  final KernelActivityKind kind;
  final DateTime since;
}

/// Where an MCP server stands, as its kernel reports it.
enum McpServerStatus { connected, pending, failed, needsAuth, disabled }

/// An MCP server a kernel uses: tools it adds, and whether it is up.
class McpServer {
  const McpServer({
    required this.name,
    required this.status,
    this.error,
    this.scope,
    this.version,
    this.tools = const [],
  });

  final String name;
  final McpServerStatus status;

  /// Why it failed.
  final String? error;

  /// Where it is configured (user, project, …).
  final String? scope;
  final String? version;

  /// The names of its tools, once connected.
  final List<String> tools;

  bool get needsAttention =>
      status == McpServerStatus.failed || status == McpServerStatus.needsAuth;
}

/// Where a kernel's runtime is: it may need installing, logging in, or
/// restarting after a crash.
enum KernelHealthStatus { idle, starting, ready, failed }

class KernelHealth {
  const KernelHealth(this.status, {this.message, this.detail});

  static const idle = KernelHealth(KernelHealthStatus.idle);
  static const ready = KernelHealth(KernelHealthStatus.ready);

  final KernelHealthStatus status;

  /// For [KernelHealthStatus.failed]: what went wrong, for the user.
  final String? message;

  /// More, e.g. the last lines the process printed.
  final String? detail;
}

/// A task the kernel runs beside the conversation: a background command, a
/// subagent. Reported whole by the kernel.
class KernelTask {
  const KernelTask({
    required this.id,
    required this.description,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.toolUseId,
    this.background = true,
    this.summary,
  });

  final String id;
  final String description;
  final KernelTaskKind kind;
  final CommandStatus status;
  final DateTime startedAt;

  /// The tool call that started it.
  final String? toolUseId;
  final bool background;

  /// Its last progress line, or how it ended.
  final String? summary;

  KernelTask copyWith({
    CommandStatus? status,
    String? summary,
    bool? background,
    String? description,
  }) => KernelTask(
    id: id,
    description: description ?? this.description,
    kind: kind,
    status: status ?? this.status,
    startedAt: startedAt,
    toolUseId: toolUseId,
    background: background ?? this.background,
    summary: summary ?? this.summary,
  );
}

enum KernelTaskKind { command, agent, other }

enum TodoStatus { pending, inProgress, completed }

class TodoEntry {
  const TodoEntry(this.content, this.status, {this.activeForm});

  final String content;
  final TodoStatus status;

  /// How it reads while in progress, e.g. "Running tests".
  final String? activeForm;
}

// --- Interactions -------------------------------------------------------------

/// Something the agent waits on the user for.
sealed class InteractionRequest {
  const InteractionRequest({required this.id, required this.title});

  final String id;
  final String title;
}

class QuestionOption {
  const QuestionOption(this.label, {this.description = '', this.preview});

  final String label;
  final String description;

  /// Shown while the option is focused, e.g. a mockup.
  final String? preview;
}

class Question {
  const Question({
    required this.prompt,
    required this.options,
    this.header = '',
    this.allowMultiple = false,
    this.allowOther = true,
  });

  final String prompt;

  /// A short tag for the question, e.g. "Library".
  final String header;
  final List<QuestionOption> options;
  final bool allowMultiple;

  /// Whether the user may answer in their own words.
  final bool allowOther;
}

/// The agent asks the user to choose.
class QuestionRequest extends InteractionRequest {
  const QuestionRequest({
    required super.id,
    required super.title,
    required this.questions,
  });

  final List<Question> questions;
}

/// What an approval is for, as the user should see it.
sealed class ApprovalPreview {
  const ApprovalPreview();
}

class CommandPreview extends ApprovalPreview {
  const CommandPreview(this.command, {this.description});

  final String command;
  final String? description;
}

class DiffPreview extends ApprovalPreview {
  const DiffPreview(this.path, this.lines);

  final String path;
  final List<DiffLine> lines;
}

class TextPreview extends ApprovalPreview {
  const TextPreview(this.text);

  final String text;
}

/// The agent asks leave to use a tool.
class ApprovalRequest extends InteractionRequest {
  const ApprovalRequest({
    required super.id,
    required super.title,
    required this.toolName,
    this.reason,
    this.preview,
    this.alwaysAllowLabel,
  });

  final String toolName;

  /// Why it asks, when the kernel says.
  final String? reason;
  final ApprovalPreview? preview;

  /// What "always allow" would allow, when the kernel offers it (e.g.
  /// "Auto-accept edits"); null for no such option.
  final String? alwaysAllowLabel;
}

/// The agent proposes a plan before it edits.
class PlanReviewRequest extends InteractionRequest {
  const PlanReviewRequest({
    required super.id,
    required super.title,
    required this.plan,
    this.approvals,
    this.approveLabel = 'Yes, start building',
  });

  /// Markdown.
  final String plan;

  /// The approvals it is carried out with, when the kernel picks them
  /// (one of its permission options).
  final KernelOption? approvals;

  /// The choice to go ahead, saying how it will (e.g. with what approvals).
  final String approveLabel;
}

sealed class InteractionAnswer {
  const InteractionAnswer();
}

/// For each question, the labels picked (an answer of their own included).
class QuestionAnswer extends InteractionAnswer {
  const QuestionAnswer(this.picks, {this.skipped = false});

  final List<List<String>> picks;

  /// Dismissed without answering.
  final bool skipped;

  /// One line, e.g. for a kernel that takes text.
  String get summary => skipped
      ? '用户跳过了问题，按默认方案继续'
      : [for (final pick in picks) pick.isEmpty ? '（跳过）' : pick.join('、')]
            .join('；');
}

enum ApprovalDecision { allowOnce, allowAlways, deny }

class ApprovalAnswer extends InteractionAnswer {
  const ApprovalAnswer(this.decision, {this.message});

  final ApprovalDecision decision;

  /// With a denial: what to do instead.
  final String? message;
}

enum PlanDecision {
  /// Go ahead, as [PlanReviewRequest.approveLabel] says.
  approve,

  /// Stay in planning, with [PlanAnswer.feedback].
  keepPlanning,
}

class PlanAnswer extends InteractionAnswer {
  const PlanAnswer(this.decision, {this.feedback});

  final PlanDecision decision;
  final String? feedback;
}

/// One message to send, with the settings it runs under.
class KernelTurn {
  const KernelTurn({
    required this.id,
    required this.text,
    this.mentions = const [],
    this.images = const [],
  });

  /// Made by the client: sending the same turn twice runs it once.
  final String id;
  final String text;
  final List<String> mentions;

  /// Only for kernels that accept images.
  final List<ImageAttachment> images;
}
