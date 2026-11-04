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
  const KernelOptionGroup(
    this.id,
    this.label, {
    this.warning,
    this.iconBuilder,
  });

  final String id;
  final String label;

  /// What went wrong with it, marked on its heading.
  final String? warning;

  /// Drawn before its heading, at a size and in a color (an upstream's
  /// icon); none when null.
  final Widget Function(double size, Color color)? iconBuilder;

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

/// A thing in the context by name (a tool, a server's tool, a skill, a
/// file…), what it takes.
class ContextItem {
  const ContextItem(
    this.name,
    this.tokens, {
    this.group,
    this.source,
    this.loaded = true,
    this.results = 0,
  });

  final String name;
  final int tokens;

  /// What it is of: an MCP tool's server, a skill's plugin.
  final String? group;

  /// Where it is from: a skill's or an agent's source, a memory file's
  /// type.
  final String? source;

  /// Its schema in the window; else deferred, out of it until needed.
  final bool loaded;

  /// A tool's results in the messages ([tokens] its calls').
  final int results;
}

/// The things in each part of the context, as Claude Code counts them
/// (`get_context_usage`).
class ContextDetail {
  const ContextDetail({
    this.systemPrompt = const [],
    this.systemTools = const [],
    this.deferredTools = const [],
    this.mcpTools = const [],
    this.agents = const [],
    this.memoryFiles = const [],
    this.skills = const [],
    this.toolUses = const [],
    this.attachments = const [],
    this.userMessages = 0,
    this.assistantMessages = 0,
    this.toolCalls = 0,
    this.toolResults = 0,
    this.attachmentTokens = 0,
    this.autoCompactAt,
  });

  final List<ContextItem> systemPrompt;
  final List<ContextItem> systemTools;

  /// Built-in tools out of the window until used.
  final List<ContextItem> deferredTools;

  /// [ContextItem.group] the server, by the name it is configured by.
  final List<ContextItem> mcpTools;
  final List<ContextItem> agents;
  final List<ContextItem> memoryFiles;

  /// [ContextItem.group] a plugin's skill's plugin.
  final List<ContextItem> skills;

  /// The messages' tool calls by tool, [ContextItem.results] their
  /// results.
  final List<ContextItem> toolUses;
  final List<ContextItem> attachments;

  /// The messages by kind, estimated.
  final int userMessages;
  final int assistantMessages;
  final int toolCalls;
  final int toolResults;
  final int attachmentTokens;

  /// Where the conversation is compacted, in tokens; null when it is not.
  final int? autoCompactAt;

  int get messages =>
      userMessages +
      assistantMessages +
      toolCalls +
      toolResults +
      attachmentTokens;

  /// From Claude Code's `get_context_usage` answer; null without one
  /// thing in it.
  static ContextDetail? parse(Map<Object?, Object?> usage) {
    int tokens(Object? raw) => raw is num ? raw.toInt() : 0;
    String? text(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;
    List<ContextItem> items(
      Object? raw,
      ContextItem? Function(Map<Object?, Object?> item) read,
    ) => [
      if (raw is List)
        for (final item in raw)
          if (item is Map) ?read(item),
    ];
    ContextItem? named(Map<Object?, Object?> item) =>
        switch (text(item['name'])) {
          final name? => ContextItem(
            name,
            tokens(item['tokens']),
            loaded: item['isLoaded'] != false,
          ),
          null => null,
        };
    final skills = usage['skills'];
    final messages = usage['messageBreakdown'];
    final breakdown = messages is Map ? messages : const {};
    final detail = ContextDetail(
      systemPrompt: items(usage['systemPromptSections'], named),
      systemTools: items(usage['systemTools'], named),
      deferredTools: items(usage['deferredBuiltinTools'], named),
      mcpTools: items(usage['mcpTools'], (item) {
        final name = text(item['name']);
        if (name == null) return null;
        final server = text(item['serverName']);
        // As Claude Code names it to the model: `mcp__server__tool`.
        final prefix = server == null ? null : 'mcp__';
        var tool = name;
        if (prefix != null && name.startsWith(prefix)) {
          final rest = name.substring(prefix.length);
          final at = rest.indexOf('__');
          if (at >= 0) tool = rest.substring(at + 2);
        }
        return ContextItem(
          tool,
          tokens(item['tokens']),
          group: server,
          loaded: item['isLoaded'] != false,
        );
      }),
      agents: items(
        usage['agents'],
        (item) => switch (text(item['agentType'])) {
          final name? => ContextItem(
            name,
            tokens(item['tokens']),
            source: text(item['source']),
          ),
          null => null,
        },
      ),
      memoryFiles: items(
        usage['memoryFiles'],
        (item) => switch (text(item['path'])) {
          final path? => ContextItem(
            path,
            tokens(item['tokens']),
            source: text(item['type']),
          ),
          null => null,
        },
      ),
      skills: items(
        skills is Map ? skills['skillFrontmatter'] : null,
        (item) => switch (text(item['name'])) {
          final name? => ContextItem(
            name,
            tokens(item['tokens']),
            group: text(item['pluginName']),
            source: text(item['source']),
          ),
          null => null,
        },
      ),
      toolUses: items(
        breakdown['toolCallsByType'],
        (item) => switch (text(item['name'])) {
          final name? => ContextItem(
            name,
            tokens(item['callTokens']),
            results: tokens(item['resultTokens']),
          ),
          null => null,
        },
      ),
      attachments: items(breakdown['attachmentsByType'], named),
      userMessages: tokens(breakdown['userMessageTokens']),
      assistantMessages: tokens(breakdown['assistantMessageTokens']),
      toolCalls: tokens(breakdown['toolCallTokens']),
      toolResults: tokens(breakdown['toolResultTokens']),
      attachmentTokens: tokens(breakdown['attachmentTokens']),
      autoCompactAt: usage['isAutoCompactEnabled'] == false
          ? null
          : switch (usage['autoCompactThreshold']) {
              final num at => at.toInt(),
              _ => null,
            },
    );
    final empty =
        detail.systemPrompt.isEmpty &&
        detail.systemTools.isEmpty &&
        detail.mcpTools.isEmpty &&
        detail.agents.isEmpty &&
        detail.memoryFiles.isEmpty &&
        detail.skills.isEmpty &&
        detail.toolUses.isEmpty &&
        detail.messages == 0 &&
        detail.autoCompactAt == null;
    return empty ? null : detail;
  }
}

/// How full the context window is, as last reported: a snapshot that
/// replaces the one before.
class ContextUsage {
  const ContextUsage({
    required this.window,
    required this.used,
    this.segments = const [],
    this.detail,
  });

  final int window;
  final int used;

  /// What the tokens are spent on, when the kernel says; else empty.
  final List<ContextSegment> segments;

  /// Each part's things by name, where the kernel tells them.
  final ContextDetail? detail;

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

/// The input of requests to the model by what the prompt cache made of it.
class CacheTokens {
  const CacheTokens({this.read = 0, this.written = 0, this.uncached = 0});

  /// Read from the cache.
  final int read;

  /// Written to it, for the requests after.
  final int written;

  /// Neither: past the last cache breakpoint, or on a model without one.
  final int uncached;

  int get total => read + written + uncached;

  /// What of the input was read from the cache, 0 to 1.
  double get hitRate => total == 0 ? 0 : read / total;

  CacheTokens operator +(CacheTokens other) => CacheTokens(
    read: read + other.read,
    written: written + other.written,
    uncached: uncached + other.uncached,
  );
}

/// How the prompt cache served the conversation: its last request, and
/// all of them.
class PromptCache {
  const PromptCache({required this.last, required this.conversation});

  final CacheTokens last;
  final CacheTokens conversation;
}

/// What the session has cost so far, and the account's limits.
class UsageStats {
  const UsageStats({
    this.costUsd,
    this.limits = const [],
    this.limitsState = LimitsState.idle,
    this.limitsOffBy,
    this.cache,
  });

  final double? costUsd;
  final List<RateLimitWindow> limits;
  final LimitsState limitsState;

  /// The setting that turned asking for the limits [LimitsState.off].
  final String? limitsOffBy;

  /// Null until a request to the model is known.
  final PromptCache? cache;
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
  const KernelHealth(
    this.status, {
    this.message,
    this.detail,
    this.missingFolder,
    this.noModel = false,
  });

  static const idle = KernelHealth(KernelHealthStatus.idle);
  static const ready = KernelHealth(KernelHealthStatus.ready);

  final KernelHealthStatus status;

  /// For [KernelHealthStatus.failed]: what went wrong, for the user.
  final String? message;

  /// More, e.g. the last lines the process printed.
  final String? detail;

  /// The project folder it was to work in, when that is what is not there:
  /// said in the user's language rather than [message].
  final String? missingFolder;

  /// Whether what it lacks is a model to run on (BaoCode's own core with
  /// no upstream turned on): offered setting one up rather than a retry.
  final bool noModel;
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
    this.outputFile,
  });

  final String id;
  final String description;
  final KernelTaskKind kind;
  final CommandStatus status;
  final DateTime startedAt;

  /// The tool call that started it; a subagent's, even when continued (on a
  /// call of its own): where its card is.
  final String? toolUseId;
  final bool background;

  /// Its last progress line, or how it ended.
  final String? summary;

  /// The command's output on the project's host, reported by the CLI.
  final String? outputFile;

  KernelTask copyWith({
    CommandStatus? status,
    String? summary,
    bool? background,
    String? description,
    String? outputFile,
  }) => KernelTask(
    id: id,
    description: description ?? this.description,
    kind: kind,
    status: status ?? this.status,
    startedAt: startedAt,
    toolUseId: toolUseId,
    background: background ?? this.background,
    summary: summary ?? this.summary,
    outputFile: outputFile ?? this.outputFile,
  );
}

enum KernelTaskKind { command, agent, other }

// --- Goal -----------------------------------------------------------------------

enum GoalState {
  /// Being worked toward: the agent does not stop until it is met.
  active,

  /// Met, as the evaluator judged.
  met,

  /// Given up on: the evaluator judged it cannot be met.
  failed,
}

/// The session's goal (Claude Code's `/goal`): a condition the agent works
/// toward, checked by an evaluator each time it would stop.
class KernelGoal {
  const KernelGoal(
    this.condition, {
    this.state = GoalState.active,
    this.checks = 0,
    this.lastReason,
    this.setAt,
    this.duration,
    this.tokens,
  });

  final String condition;
  final GoalState state;

  /// How many times it was checked and found not met yet.
  final int checks;

  /// Why the last check found it not met (or, once met, why it is).
  final String? lastReason;

  /// When it was set, as far as is known.
  final DateTime? setAt;

  /// How long it took to meet, once met.
  final Duration? duration;

  /// The tokens spent meeting it, once met (as Claude Code counts them).
  final int? tokens;

  KernelGoal copyWith({
    GoalState? state,
    int? checks,
    String? lastReason,
    Duration? duration,
    int? tokens,
  }) => KernelGoal(
    condition,
    state: state ?? this.state,
    checks: checks ?? this.checks,
    lastReason: lastReason ?? this.lastReason,
    setAt: setAt,
    duration: duration ?? this.duration,
    tokens: tokens ?? this.tokens,
  );

  @override
  bool operator ==(Object other) =>
      other is KernelGoal &&
      other.condition == condition &&
      other.state == state &&
      other.checks == checks &&
      other.lastReason == lastReason &&
      other.setAt == setAt &&
      other.duration == duration &&
      other.tokens == tokens;

  @override
  int get hashCode => Object.hash(
    condition,
    state,
    checks,
    lastReason,
    setAt,
    duration,
    tokens,
  );
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
    this.otherLabel,
  });

  final String prompt;

  /// A short tag for the question, e.g. "Library".
  final String header;
  final List<QuestionOption> options;
  final bool allowMultiple;

  /// Whether the user may answer in their own words.
  final bool allowOther;

  /// The option to answer in their own words, as it shows ("Other" when
  /// null); left empty, the answer is this label.
  final String? otherLabel;
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

/// One message to send, with the settings it runs under.
class KernelTurn {
  const KernelTurn({
    required this.id,
    required this.text,
    this.mentions = const [],
    this.images = const [],
    this.now = false,
    this.notes = const [],
  });

  /// Made by the client: sending the same turn twice runs it once.
  final String id;
  final String text;
  final List<String> mentions;

  /// Told the model after [text], not shown: what the client adds of its
  /// own (e.g. the file open in the editor), as system reminders.
  final List<String> notes;

  /// Taken up at once rather than after the turn running, which is stopped
  /// for it (where a kernel queues messages).
  final bool now;

  /// Only for kernels that accept images.
  final List<ImageAttachment> images;
}
