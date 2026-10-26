import 'dart:typed_data';

/// UI-only view models for the conversation history.
sealed class ChatItem {
  const ChatItem();
}

/// What the user sent, as text: mentions and commands are echoed in it
/// (`@lib/main.dart`, `/plan`), not kept as structure.
class UserMessageItem extends ChatItem {
  const UserMessageItem({
    required this.text,
    this.queued = false,
    this.images = const [],
    this.worked,
    this.usage,
  });

  final String text;

  /// Pictures sent with it (screenshots, mockups…).
  final List<ImageAttachment> images;

  /// Sent while the agent was busy: waits for its turn, and can be taken
  /// back until then.
  final bool queued;

  /// How long the agent worked on it, once its turn ended as it should
  /// (not stopped): the work before its answer folds into that.
  final Duration? worked;

  /// What its turn spent, kept with [worked], when the kernel said.
  final TurnUsage? usage;

  UserMessageItem copyWith({Duration? worked, TurnUsage? usage}) =>
      UserMessageItem(
        text: text,
        queued: queued,
        images: images,
        worked: worked ?? this.worked,
        usage: usage ?? this.usage,
      );
}

/// What a turn spent, as its kernel reported at its end.
class TurnUsage {
  const TurnUsage({
    this.inputTokens,
    this.outputTokens,
    this.tokensPerSecond,
    this.costUsd,
  });

  /// Tokens the model read, all its requests together, the prompt cache's
  /// among them.
  final int? inputTokens;

  /// Tokens it wrote, all its requests together.
  final int? outputTokens;

  /// How fast it wrote, while it did.
  final double? tokensPerSecond;

  /// What the turn cost, in dollars.
  final double? costUsd;

  /// Read and written, when either is known.
  int? get totalTokens => inputTokens == null && outputTokens == null
      ? null
      : (inputTokens ?? 0) + (outputTokens ?? 0);
}

/// What the model has written so far in the turn under way, and how fast it
/// writes (now while it does, else on average so far; null before it has
/// written long enough to say).
class TurnOutput {
  const TurnOutput({required this.tokens, this.tokensPerSecond});

  final int tokens;
  final double? tokensPerSecond;
}

/// A picture sent with a message.
class ImageAttachment {
  const ImageAttachment({
    required this.bytes,
    required this.mediaType,
    this.name,
    this.number,
  });

  final Uint8List bytes;

  /// `image/png`, `image/jpeg`, `image/gif` or `image/webp`.
  final String mediaType;

  /// The file it came from, if any.
  final String? name;

  /// Its number in the conversation, as its message's text refers to it
  /// (`[Image #3]`): counted on from the last one, never reused. Null for
  /// one sent before images were numbered.
  final int? number;

  ImageAttachment withNumber(int number) => ImageAttachment(
    bytes: bytes,
    mediaType: mediaType,
    name: name,
    number: number,
  );
}

/// How a message's text refers to its image [number], as Claude Code
/// writes it: `[Image #3]`.
String imageReference(int number) => '[Image #$number]';

/// Every `[Image #N]` in a text.
final imageReferencePattern = RegExp(r'\[Image #(\d+)\]');

/// Plain assistant prose. Supports `inline code` and `- ` bullet lines.
class AssistantTextItem extends ChatItem {
  const AssistantTextItem(this.text);

  final String text;
}

/// [text] (what an agent said, or asks) on one line, its markup's marks
/// dropped, at most [max] characters: for a notification, a card.
String oneLineExcerpt(String text, {int max = 140}) {
  final line = text
      .replaceAll(RegExp(r'[`*_#>]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (line.length <= max) return line;
  return '${line.substring(0, max - 1).trimRight()}…';
}

class ThinkingItem extends ChatItem {
  const ThinkingItem({
    required this.text,
    required this.tokens,
    this.seconds,
    this.startedAt,
  });

  final String text;

  /// Tokens thought so far (all of them, once done).
  final int tokens;

  /// How long the thought took; null while it is still streaming.
  final int? seconds;

  /// When it began, while it streams: its time so far shows live.
  final DateTime? startedAt;

  bool get streaming => seconds == null;
}

enum ToolKind {
  read,
  grep,
  listDir,
  search,
  edit,
  command,
  web,
  agent,
  mcp,
  todo,

  /// A message to another agent.
  message,

  /// A question for the user.
  question,

  /// A goal proposed for the session (its condition the item's output).
  goal,

  /// Something done in the user's browser (see lib/browser): its [tool]
  /// says what.
  browser,

  /// Pictures an image model made (see lib/images): shown as they come.
  image,
  other,
}

enum ToolStatus { running, succeeded, failed, denied }

class ToolCallItem extends ChatItem {
  const ToolCallItem({
    required this.kind,
    required this.target,
    this.detail,
    this.path,
    this.results = const [],
    this.label,
    this.status = ToolStatus.succeeded,
    this.output,
    this.tool,
    this.callId,
    this.input = const {},
    this.images = const [],
    this.imageFiles = const [],
  });

  final ToolKind kind;
  final String target;
  final String? detail;

  /// Full path of the file read, when [target] is its name.
  final String? path;

  /// Matches found (`path:line`), for searches.
  final List<String> results;

  /// What it did, when not said by [kind] (e.g. an MCP tool's name).
  final String? label;
  final ToolStatus status;

  /// What it returned, shown on demand.
  final String? output;

  /// The tool's own name (an MCP tool's, without its server's), for a
  /// kind each of whose tools shows its own way.
  final String? tool;

  /// Its tool use's id, for one of the app's own tools (see
  /// claude_sdk_tools.dart): what the call under way is known by, to answer
  /// what it asks of the user.
  final String? callId;

  /// What it was called with, for those.
  final Map<String, Object?> input;

  /// The pictures it returned (a screenshot, say).
  final List<ImageAttachment> images;

  /// Where they were saved (absolute, on the project's host), as the CLI
  /// told the agent: files of the session, which its text may link to.
  final List<String> imageFiles;
}

/// A subagent at work: its own conversation, one card in the history that
/// opens to it.
class AgentItem extends ChatItem {
  const AgentItem({
    required this.description,
    this.id,
    this.agentType,
    this.prompt,
    this.status = CommandStatus.running,
    this.tokens,
    this.toolUses,
    this.lastTool,
    this.activity,
    this.startedAt,
    this.duration,
    this.model,
    this.children = const [],
    this.result,
    this.background = false,
  });

  final String description;

  /// The tool call that started it, to find it again and act on it.
  final String? id;
  final String? agentType;

  /// What the agent that started it asked of it.
  final String? prompt;
  final CommandStatus status;
  final int? tokens;
  final int? toolUses;
  final String? lastTool;

  /// What it is doing now, e.g. "Reading a.txt".
  final String? activity;

  /// When it started, while it runs (live sessions only).
  final DateTime? startedAt;

  /// How long it took, once done.
  final Duration? duration;
  final String? model;
  final List<ChatItem> children;

  /// Its final report.
  final String? result;

  /// Left to run on its own while the agent goes on: it reports when done.
  final bool background;

  AgentItem copyWith({
    String? description,
    String? agentType,
    String? prompt,
    CommandStatus? status,
    int? tokens,
    int? toolUses,
    String? lastTool,
    String? activity,
    Duration? duration,
    String? model,
    List<ChatItem>? children,
    String? result,
    bool? background,
  }) => AgentItem(
    description: description ?? this.description,
    id: id,
    agentType: agentType ?? this.agentType,
    prompt: prompt ?? this.prompt,
    status: status ?? this.status,
    tokens: tokens ?? this.tokens,
    toolUses: toolUses ?? this.toolUses,
    lastTool: lastTool ?? this.lastTool,
    activity: activity ?? this.activity,
    startedAt: startedAt,
    duration: duration ?? this.duration,
    model: model ?? this.model,
    children: children ?? this.children,
    result: result ?? this.result,
    background: background ?? this.background,
  );
}

enum NoticeKind {
  /// The conversation was summarized to free the context.
  compaction,

  /// A request failed and will be retried.
  retry,
  error,
  info,
  warning,

  /// Output of a command run in the session (e.g. `/context`), markdown.
  command,
}

/// Where a round of planning stands.
enum PlanStatus {
  /// Being written.
  drafting,

  /// Put to the user, who has not answered yet.
  awaiting,
  approved,

  /// The user wants it changed: another round follows.
  sentBack,
}

/// A round of planning, as one card: the plan the agent wrote in its file
/// (written once or many times) and what became of it. A plan sent back and
/// written again is a new round, and a new card.
class PlanItem extends ChatItem {
  const PlanItem({
    required this.path,
    required this.round,
    this.title,
    this.text,
    this.status = PlanStatus.drafting,
    this.writes = 0,
    this.feedback,
  });

  /// The plan's file; empty when the plan was sent rather than written.
  final String path;

  /// Which round of the conversation's planning it is, from 1.
  final int round;

  /// The plan's first heading, when it has one.
  final String? title;

  /// The plan as written last (markdown), when known: a session resumed
  /// may only have the edits made to it.
  final String? text;
  final PlanStatus status;

  /// How many times the agent wrote its file this round.
  final int writes;

  /// What the user said should change, when they sent it back.
  final String? feedback;

  /// Its name: [title], else its file's.
  String get name => title ?? path.split(RegExp(r'[/\\]')).last;

  PlanItem copyWith({
    String? title,
    String? text,
    PlanStatus? status,
    int? writes,
    String? feedback,
  }) => PlanItem(
    path: path,
    round: round,
    title: title ?? this.title,
    text: text ?? this.text,
    status: status ?? this.status,
    writes: writes ?? this.writes,
    feedback: feedback ?? this.feedback,
  );

  /// The first `# heading` of [markdown], if any.
  static String? titleOf(String? markdown) {
    if (markdown == null) return null;
    for (final line in markdown.split('\n')) {
      if (RegExp(r'^#{1,2}\s+(.+?)\s*#*\s*$').firstMatch(line) case final m?) {
        return m.group(1);
      }
    }
    return null;
  }
}

/// A line from the runtime, not the agent: shown apart from its messages.
class NoticeItem extends ChatItem {
  const NoticeItem(this.kind, this.text);

  final NoticeKind kind;
  final String text;
}

enum CommandStatus { running, succeeded, failed }

class TerminalItem extends ChatItem {
  const TerminalItem({
    required this.command,
    required this.output,
    this.description,
    this.status = CommandStatus.succeeded,
    this.background = false,
    this.startedAt,
  });

  final String command;

  /// What it is for, in words (e.g. "Check the Flutter version"), when the
  /// agent said.
  final String? description;
  final String output;
  final CommandStatus status;

  /// Left running after its turn: shown as a background task too.
  final bool background;
  final DateTime? startedAt;

  bool get succeeded => status != CommandStatus.failed;
}

enum DiffLineType { added, removed, context }

class DiffLine {
  const DiffLine(this.type, this.lineNumber, this.text);

  final DiffLineType type;
  final int lineNumber;
  final String text;
}

class CodeDiffItem extends ChatItem {
  const CodeDiffItem({
    required this.fileName,
    required this.directory,
    required this.lines,
    this._added,
    this._removed,
  });

  final String fileName;
  final String directory;

  /// The file's path, as the agent gave it.
  String get path => directory.isEmpty ? fileName : '$directory/$fileName';

  /// The first line added or removed, numbered as in the file now.
  int? get firstChangedLine {
    for (final line in lines) {
      if (line.type != DiffLineType.context) return line.lineNumber;
    }
    return null;
  }

  /// The changed lines, perhaps only the first of them.
  final List<DiffLine> lines;
  final int? _added;
  final int? _removed;

  /// Lines added and removed in all, [lines] shown or not.
  int get added =>
      _added ?? lines.where((l) => l.type == DiffLineType.added).length;
  int get removed =>
      _removed ?? lines.where((l) => l.type == DiffLineType.removed).length;
}

/// Row at the end of a live turn, all through it: the agent at work, e.g.
/// "Planning next move", or "Compacting conversation". Hidden at times.
class LiveStatusItem extends ChatItem {
  const LiveStatusItem(
    this.label, {
    this.whimsical = false,
    this.visible = true,
    this.output,
    this.startedAt,
    this.cue,
  });

  final String label;

  /// Whether the wait has nothing to name (the model yet to answer, not a
  /// chore like compacting): the row may muse rather than say [label].
  final bool whimsical;

  /// Whether it shows now: it stays through the turn, and comes and goes.
  final bool visible;

  /// What the model has written so far, shown where the turn's footer
  /// will be; null before it has written anything.
  final TurnOutput? output;

  /// When the turn began, for the time it has taken so far.
  final DateTime? startedAt;

  /// What the agent did last, for a [whimsical] row to muse on as well.
  final MusingCue? cue;
}

/// The kinds of step done that a status row muses on (see [MusingCue]).
enum MusingTopic {
  command,
  commandFailed,
  read,
  edit,
  search,
  folder,
  web,
  agent,
  mcp,
  browser,
  image,
  denied,
}

/// A step the agent has done, as a status row muses on it: what kind, and
/// what it was done to ("flutter test", "chat_session.dart", "12"), short.
class MusingCue {
  const MusingCue(this.topic, [this.name = '']);

  final MusingTopic topic;
  final String name;

  /// The cue of [item], when a step done: none for one under way, which
  /// the model is not yet mulling over, nor for others.
  static MusingCue? after(ChatItem? item) => switch (item) {
    TerminalItem(:final command, :final status, background: false)
        when status != CommandStatus.running =>
      switch (commandName(command)) {
        '' => null,
        final name => MusingCue(
          status == CommandStatus.failed
              ? MusingTopic.commandFailed
              : MusingTopic.command,
          name,
        ),
      },
    CodeDiffItem(:final fileName) => MusingCue(
      MusingTopic.edit,
      _short(fileName),
    ),
    AgentItem(:final agentType?, :final status, background: false)
        when status != CommandStatus.running =>
      MusingCue(MusingTopic.agent, _short(agentType)),
    ToolCallItem(status: ToolStatus.denied) => const MusingCue(
      MusingTopic.denied,
    ),
    ToolCallItem(
      :final kind,
      :final target,
      :final label,
      :final status,
      :final results,
    )
        when status == ToolStatus.succeeded =>
      switch (kind) {
        ToolKind.read when target.isNotEmpty => MusingCue(
          MusingTopic.read,
          _short(target),
        ),
        ToolKind.edit when target.isNotEmpty => MusingCue(
          MusingTopic.edit,
          _short(target),
        ),
        ToolKind.grep || ToolKind.search when results.isNotEmpty => MusingCue(
          MusingTopic.search,
          '${results.length}',
        ),
        ToolKind.listDir when target.isNotEmpty => MusingCue(
          MusingTopic.folder,
          _short(target),
        ),
        ToolKind.web => switch (Uri.tryParse(target)?.host) {
          final host? when host.isNotEmpty => MusingCue(
            MusingTopic.web,
            _short(host.startsWith('www.') ? host.substring(4) : host),
          ),
          _ => null,
        },
        ToolKind.mcp => switch (label) {
          final label? => MusingCue(
            MusingTopic.mcp,
            _short(label.split(' · ').last),
          ),
          null => null,
        },
        ToolKind.browser => const MusingCue(MusingTopic.browser),
        ToolKind.image => const MusingCue(MusingTopic.image),
        _ => null,
      },
    _ => null,
  };

  /// What [command] runs, in a word or two: the last of its chained
  /// commands but a `cd`, before any pipe, its program's name and a
  /// subcommand if it has one ("flutter test", "git commit").
  static String commandName(String command) {
    final line = command.trimLeft().split('\n').first;
    final chained = [
      for (final part in line.split(RegExp(r'&&|\|\||;')))
        if (part.trim().isNotEmpty && !part.trim().startsWith('cd ')) part,
    ];
    if (chained.isEmpty) return '';
    final words = [
      for (final word
          in chained.last.split('|').first.trim().split(RegExp(r'\s+')))
        if (word.isNotEmpty) word,
    ].skipWhile((word) => word.contains('=') || word == 'sudo').toList();
    if (words.isEmpty) return '';
    final program = words.first.split('/').last;
    final sub = words.length > 1 ? words[1] : null;
    return _short(
      sub != null && RegExp(r'^[a-z][a-z-]{1,11}$').hasMatch(sub)
          ? '$program $sub'
          : program,
    );
  }

  /// [name], cut to fit in the row's line.
  static String _short(String name) =>
      name.length <= 24 ? name : '${name.substring(0, 23)}…';
}

enum FileChangeKind { added, modified, deleted }

/// What a file was before an edit, as the agent tells it: what Undo puts
/// back.
sealed class FileOriginal {
  const FileOriginal();
}

/// Its text; null where there was no file.
final class OriginalText extends FileOriginal {
  const OriginalText(this.text);

  final String? text;
}

/// The edit as a unified diff: taken back out of the file as it left it.
final class OriginalByPatch extends FileOriginal {
  const OriginalByPatch(this.diff);

  final String diff;
}

/// The edits made, in order, each a text put in place of another once (an
/// Edit's, a MultiEdit's, as their input tells them): taken back out of the
/// file as they left it, the last first, where each text put in is there
/// once (else what it was is not known).
final class OriginalByEdits extends FileOriginal {
  const OriginalByEdits(this.edits);

  final List<({String before, String after})> edits;

  /// The text before them, from [text] as they left it; null where it
  /// cannot be told.
  String? undo(String text) {
    for (final edit in edits.reversed) {
      if (edit.after.isEmpty) return null;
      final at = text.indexOf(edit.after);
      if (at < 0 || text.indexOf(edit.after, at + 1) >= 0) return null;
      text = text.replaceRange(at, at + edit.after.length, edit.before);
    }
    return text;
  }
}

/// A file an agent changed, with its line counts.
class FileChange {
  const FileChange({
    required this.path,
    required this.added,
    required this.removed,
    this.kind = FileChangeKind.modified,
    this.binary = false,
    this.tracked = true,
    this.shared = false,
    this.conflict = false,
  });

  final String path;
  final int added;
  final int removed;
  final FileChangeKind kind;

  /// No line counts: a binary file.
  final bool binary;

  /// Whether what it was before is known, to be undone; not when it is
  /// in no snapshot (ignored, too large, outside the project) and the
  /// agent did not tell.
  final bool tracked;

  /// Another agent was at work in the project at the same time: some of
  /// it may be theirs.
  final bool shared;

  /// It changed again since the agent left it, and Undo could not carry
  /// that over.
  final bool conflict;

  String get fileName => path.split('/').last;
  String get directory {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }
}
