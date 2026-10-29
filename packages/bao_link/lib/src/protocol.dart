import 'bots.dart';

/// What a phone asks a desktop ([LinkPeer.call]).
abstract final class LinkMethods {
  /// The first request: `{"name", "system", "token"?, "request"?}`;
  /// answered with `{"device": DeviceInfo}`. Turned down (`unpaired`) for a
  /// phone the desktop does not know, unless it pairs: with the QR code's
  /// token (base64url), or, found nearby ([LinkAdvert]), asking to
  /// (`"request": true`) while the desktop pairs (else `notPairing`).
  /// Pairing, the answer has `"pairing": true`; asked for, `"approval":
  /// true` too: the desktop's user has to allow it.
  static const hello = 'hello';

  /// While pairing, the safety codes matched on the phone: the desktop keeps
  /// it from then on. One that asked to pair is answered once the desktop's
  /// user allowed it (`rejected` when they did not).
  static const confirm = 'confirm';

  /// The phone unpairs itself.
  static const unpair = 'unpair';

  /// `{}`: the [LinkState] now; [LinkEvents.state] follows each change.
  static const state = 'state';

  /// `{"session", "window"?}`: follows the session, [LinkEvents.session]
  /// bringing all of it at once, then what changes. With `window` (an
  /// int N), only the last N items at first, and more as it asks
  /// ([earlier]); `start` and `count` of every update are then counted
  /// from the first item the phone has, not the session's first.
  static const open = 'open';

  /// `{"session", "count"?}` -> `{"items": [...], "earlier"}`: up to
  /// `count` (50 if none) items before the first the phone has, oldest
  /// first, read from the desktop's history first when it has no more in
  /// memory. The phone puts them before its own; `earlier` tells whether
  /// there are yet more. Only for a session [open]ed with `window`.
  static const earlier = 'earlier';

  /// `{"session"}`: no longer followed.
  static const close = 'close';

  /// `{"session"?, "project"?, "bot"?, "text", "images"?, "mentions"?,
  /// "now"?}`: a message to the bot's conversation ([LinkBot.id]), started
  /// if it has none; else to the session; with neither, to a new one in the
  /// project.
  /// Images are `{"data" (base64), "type", "name"?}`; mentions, the
  /// project's files the text names (`@path`), from its root. With `now`,
  /// taken up at once, the turn running stopped for it, rather than queued
  /// behind it. Answered with `{"session"}`.
  static const send = 'send';

  /// `{"session", "index", "text", "images"?, "mentions"?}`: the user's
  /// message at `index` (counted from the phone's first item, as an
  /// update's `start` is) sent again as this, as the desktop's edit of a
  /// message: everything after it is discarded, and the turn runs again
  /// from there. `notFound` where there is no message of the user's;
  /// `unsupported` where the agent cannot go back.
  static const edit = 'edit';

  /// `{"session"}`: stops the turn under way.
  static const stop = 'stop';

  /// `{"session", "request", "answer"}`: answers what the agent asked (see
  /// [LinkSessionUpdate.interaction]).
  static const answer = 'answer';

  /// `{"session"}`: starts the plan the agent put to the user (its
  /// history's plan item awaiting), as the desktop's Start: `notFound`
  /// when none awaits, `busy` while the turn that put it runs.
  static const startPlan = 'startPlan';

  /// `{"session", "kind", "option"}`: picks a model, a mode, a permission
  /// mode, an effort or a context size (see [LinkChoice]).
  static const choose = 'choose';

  /// `{"session", "title"}`.
  static const rename = 'rename';

  /// `{"session", "pinned"}`.
  static const pin = 'pin';

  /// `{"session"}`: off the list (archived on the desktop).
  static const archive = 'archive';

  /// `{"session", "paths"?}`: keeps the changes to those files (all of
  /// them, with no paths), as the desktop's Keep.
  static const keep = 'keep';

  /// `{"session", "paths"?}`: undoes them, as the desktop's Undo.
  static const undo = 'undo';

  /// `{"session", "task"?, "agent"?}`: stops a task left running (see
  /// [LinkTask]), or the subagent the tool call `agent` started.
  static const stopTask = 'stopTask';

  /// `{"session", "task"}`: a command task's output, its last
  /// [LinkLimits.output] characters: `{"text"}`.
  static const output = 'output';

  /// `{"project"}`: the project's files, `/`-separated from its root:
  /// `{"paths", "truncated"?, "changes": {path: "added" | "modified"}}`, the
  /// changes being its agents' not kept yet.
  static const files = 'files';

  /// `{"project", "path"}`: a file of the project: `{"text", "original"?}`
  /// (`original`, what it was before its agents changed it: empty when they
  /// added it), or `{"binary": true}`, or `{"tooLarge": true, "size"}`.
  static const read = 'read';

  /// `{}`: Claude Code's customizations on the desktop, the user's and
  /// its projects': `{"items": [LinkExtension]}`.
  static const extensions = 'extensions';

  /// `{"project"}`: the new agent the project's next conversation starts,
  /// as the desktop's New Chat has it ready: `{"session"}`. Not listed
  /// until a message is sent to it; [open]ed, it tells the models, modes
  /// and permissions it may start with ([choose] picks them), and [send]
  /// to it starts it.
  static const draft = 'draft';

  /// `{"id"}`: a picture a project shows as its icon ([ProjectInfo.icon]'s
  /// `{"type": "image", "id"}`): `{"kind": "png"|"gif"|"svg", "data"}`
  /// (base64). The id is of its content: the same id, the same picture.
  static const icon = 'icon';

  /// `{"project", "path"}`: a picture of the project (PNG, JPEG, GIF,
  /// WebP), as a reply names it: `{"type", "data"}` (its media type, and
  /// base64), or `{"tooLarge": true, "size"}` past [LinkLimits.image].
  /// `bad` for a file that is not a picture.
  static const image = 'image';

  /// `{"bot"?, "name", "avatar"?, "avatarImage"?, "identity", "abilities",
  /// "proactive"}` (as [LinkBot]'s JSON): the bot changed, or a new one (no
  /// `bot`): `{"bot": LinkBot}`. `avatarImage`, `{"data" (base64), "type"}`
  /// (at most [LinkLimits.avatar]), is a new picture for it; else `avatar`
  /// is an emoji, or the picture it has, kept.
  static const saveBot = 'saveBot';

  /// `{"bot"}`: its picture ([LinkBot.avatar], [isAvatarImage]):
  /// `{"type", "data"}` (its media type, and base64); `notFound` when it
  /// has none.
  static const botAvatar = 'botAvatar';

  /// `{"bot"}`: the bot deleted, its conversation and memory with it;
  /// `unsupported` for the assistant.
  static const deleteBot = 'deleteBot';

  /// `{"bot"}`: what the bot remembers of the user, as it keeps it (kept
  /// on the desktop, never sent elsewhere): `{"text"}`.
  static const botMemory = 'botMemory';

  /// `{"bot", "text"}`: its memory as the user wrote it; empty clears it.
  static const setBotMemory = 'setBotMemory';
}

/// How much of what a phone asks for it gets, at most.
abstract final class LinkLimits {
  /// A file's text, in bytes.
  static const file = 512 * 1024;

  /// A task's output, in characters: the end of it.
  static const output = 64 * 1024;

  /// A project's files listed.
  static const files = 20000;

  /// A picture's bytes.
  static const image = 8 * 1024 * 1024;

  /// A bot's picture's bytes.
  static const avatar = 1024 * 1024;
}

/// A task an agent left running beside the conversation: a command, a
/// subagent.
class LinkTask {
  const LinkTask({
    required this.id,
    required this.kind,
    required this.description,
    required this.status,
    required this.startedAt,
    this.toolUseId,
    this.command,
    this.summary,
    this.output = false,
  });

  factory LinkTask.fromJson(Map<String, Object?> json) => LinkTask(
    id: json['id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'other',
    description: json['description'] as String? ?? '',
    status: json['status'] as String? ?? 'running',
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['startedAt'] as num?)?.toInt() ?? 0,
    ),
    toolUseId: json['toolUseId'] as String?,
    command: json['command'] as String?,
    summary: json['summary'] as String?,
    output: json['output'] == true,
  );

  final String id;

  /// `command`, `agent` or `other`.
  final String kind;
  final String description;

  /// `running`, `succeeded` or `failed`.
  final String status;
  final DateTime startedAt;

  /// The tool call that started it: a subagent's id in the history.
  final String? toolUseId;

  /// The command a command task runs.
  final String? command;

  /// Its last progress line, or how it ended.
  final String? summary;

  /// It has output to ask for ([LinkMethods.output]).
  final bool output;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'description': description,
    'status': status,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'toolUseId': ?toolUseId,
    'command': ?command,
    'summary': ?summary,
    if (output) 'output': true,
  };
}

/// One of Claude Code's customizations on a desktop: a skill, an MCP
/// server, a plugin, a subagent.
class LinkExtension {
  const LinkExtension({
    required this.kind,
    required this.scope,
    required this.name,
    this.description = '',
    this.project,
    this.enabled,
  });

  factory LinkExtension.fromJson(Map<String, Object?> json) => LinkExtension(
    kind: json['kind'] as String? ?? '',
    scope: json['scope'] as String? ?? 'user',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    project: json['project'] as String?,
    enabled: json['enabled'] as bool?,
  );

  /// `skill`, `mcp`, `plugin` or `agent`.
  final String kind;

  /// `user`, `project`, `local` or `plugin`.
  final String scope;
  final String name;
  final String description;

  /// The project's id ([ProjectInfo.id]), for one of a project's.
  final String? project;

  /// False when turned off (a plugin not enabled, a server disabled).
  final bool? enabled;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'scope': scope,
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'project': ?project,
    'enabled': ?enabled,
  };
}

/// What a desktop tells a phone, unasked ([LinkPeer.emit]).
abstract final class LinkEvents {
  /// A [LinkState], whenever it changes.
  static const state = 'state';

  /// A [LinkSessionUpdate] of a session followed.
  static const session = 'session';

  /// The desktop unpaired the phone; the connection ends.
  static const unpaired = 'unpaired';
}

/// Error codes of [LinkRemoteException].
abstract final class LinkErrors {
  static const unpaired = 'unpaired';
  static const badToken = 'badToken';
  static const notFound = 'notFound';

  /// Asked to pair while the desktop does not.
  static const notPairing = 'notPairing';

  /// Another phone is pairing.
  static const busy = 'busy';

  /// The desktop's user turned the pairing down.
  static const rejected = 'rejected';

  /// The desktop cannot do that here (an agent that cannot go back).
  static const unsupported = 'unsupported';

  /// The request was not one the desktop knows: one from before it could.
  static const unknown = 'unknown';
}

/// The desktop, as the phone lists it.
class DeviceInfo {
  const DeviceInfo({
    required this.name,
    required this.kind,
    required this.system,
    this.laptop = true,
    this.endpoints = const [],
  });

  factory DeviceInfo.fromJson(Map<String, Object?> json) => DeviceInfo(
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? 'mac',
    system: json['system'] as String? ?? '',
    laptop: json['laptop'] as bool? ?? true,
    endpoints: [...?(json['endpoints'] as List?)?.whereType<String>()],
  );

  final String name;

  /// `mac`, `windows` or `linux`.
  final String kind;

  /// Its OS and version, e.g. `macOS 26.1`.
  final String system;
  final bool laptop;

  /// Where it can be reached now (see [DirectEndpoint.parse]): the phone
  /// keeps them, for next time.
  final List<String> endpoints;

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'system': system,
    'laptop': laptop,
    'endpoints': endpoints,
  };
}

/// A project open on the desktop.
class ProjectInfo {
  const ProjectInfo({
    required this.id,
    required this.name,
    required this.path,
    this.branch,
    this.icon,
  });

  factory ProjectInfo.fromJson(Map<String, Object?> json) => ProjectInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    branch: json['branch'] as String?,
    icon: switch (json['icon']) {
      final Map<String, Object?> icon => icon,
      _ => null,
    },
  );

  final String id;
  final String name;
  final String path;
  final String? branch;

  /// What it shows in place of its folder, as the desktop keeps it:
  /// `{"type": "emoji", "emoji"}`, `{"type": "codicon", "name", "color"?}`
  /// (a VS Code icon, in a theme's color id), `{"type": "image", "id"}`
  /// (read by [LinkMethods.icon]) or `{"type": "brand", "name"}` (a
  /// model maker's logo). Null for its folder.
  final Map<String, Object?>? icon;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'branch': ?branch,
    'icon': ?icon,
  };
}

/// Where an agent stands.
enum LinkSessionStatus { running, needsInput, idle }

/// An agent, as the desktop's sidebar lists it.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.project,
    required this.title,
    required this.updatedAt,
    this.status = LinkSessionStatus.idle,
    this.unread = false,
    this.pinned = false,
    this.model,
    this.mode,
    this.permission,
  });

  factory SessionSummary.fromJson(Map<String, Object?> json) => SessionSummary(
    id: json['id'] as String? ?? '',
    project: json['project'] as String? ?? '',
    title: json['title'] as String? ?? '',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      json['updated'] as int? ?? 0,
    ),
    status:
        LinkSessionStatus.values.asNameMap()[json['status']] ??
        LinkSessionStatus.idle,
    unread: json['unread'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    model: json['model'] as String?,
    mode: json['mode'] as String?,
    permission: json['permission'] as String?,
  );

  final String id;

  /// Its project's [ProjectInfo.id].
  final String project;
  final String title;
  final DateTime updatedAt;
  final LinkSessionStatus status;
  final bool unread;
  final bool pinned;
  final String? model;
  final String? mode;
  final String? permission;

  Map<String, Object?> toJson() => {
    'id': id,
    'project': project,
    'title': title,
    'updated': updatedAt.millisecondsSinceEpoch,
    'status': status.name,
    'unread': unread,
    'pinned': pinned,
    'model': ?model,
    'mode': ?mode,
    'permission': ?permission,
  };
}

/// The desktop's projects and agents.
class LinkState {
  const LinkState({
    required this.device,
    this.projects = const [],
    this.sessions = const [],
    this.bots = const [],
  });

  factory LinkState.fromJson(Map<String, Object?> json) => LinkState(
    device: DeviceInfo.fromJson(_map(json['device'])),
    projects: [
      for (final project in (json['projects'] as List?) ?? const [])
        ProjectInfo.fromJson(_map(project)),
    ],
    sessions: [
      for (final session in (json['sessions'] as List?) ?? const [])
        SessionSummary.fromJson(_map(session)),
    ],
    bots: [
      for (final bot in (json['bots'] as List?) ?? const [])
        LinkBot.fromJson(_map(bot)),
    ],
  );

  final DeviceInfo device;
  final List<ProjectInfo> projects;
  final List<SessionSummary> sessions;

  /// The bots, the assistant first; their conversations are not among
  /// [sessions].
  final List<LinkBot> bots;

  Map<String, Object?> toJson() => {
    'device': device.toJson(),
    'projects': [for (final project in projects) project.toJson()],
    'sessions': [for (final session in sessions) session.toJson()],
    if (bots.isNotEmpty) 'bots': [for (final bot in bots) bot.toJson()],
  };
}

/// One of an agent's choices: its options and the one in effect.
class LinkChoice {
  const LinkChoice({required this.kind, required this.options, this.selected});

  factory LinkChoice.fromJson(Map<String, Object?> json) => LinkChoice(
    kind: json['kind'] as String? ?? '',
    selected: json['selected'] as String?,
    options: [
      for (final option in (json['options'] as List?) ?? const [])
        LinkOption.fromJson(_map(option)),
    ],
  );

  /// `model`, `mode`, `permission`, `effort` or `context`.
  final String kind;
  final List<LinkOption> options;
  final String? selected;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'selected': ?selected,
    'options': [for (final option in options) option.toJson()],
  };
}

class LinkOption {
  const LinkOption({
    required this.id,
    required this.label,
    this.description = '',
    this.group,
    this.groupLabel,
    this.caution = false,
  });

  factory LinkOption.fromJson(Map<String, Object?> json) => LinkOption(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    description: json['description'] as String? ?? '',
    group: json['group'] as String?,
    groupLabel: json['groupLabel'] as String?,
    caution: json['caution'] as bool? ?? false,
  );

  final String id;
  final String label;
  final String description;

  /// What it is listed under, e.g. a model's provider.
  final String? group;
  final String? groupLabel;
  final bool caution;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (description.isNotEmpty) 'description': description,
    'group': ?group,
    'groupLabel': ?groupLabel,
    if (caution) 'caution': true,
  };
}

/// What changed in a session followed: its items from [start] on (those
/// before are as sent already), and where it stands.
///
/// The items are the desktop's chat items as JSON (each app's
/// `chat_codec.dart`): this package does not know them.
class LinkSessionUpdate {
  const LinkSessionUpdate({
    required this.session,
    required this.start,
    required this.items,
    required this.count,
    this.live = false,
    this.interaction,
    this.choices = const [],
    this.changes = const [],
    this.tasks = const [],
    this.earlier,
    this.goal,
  });

  factory LinkSessionUpdate.fromJson(Map<String, Object?> json) =>
      LinkSessionUpdate(
        session: json['session'] as String? ?? '',
        start: json['start'] as int? ?? 0,
        count: json['count'] as int? ?? 0,
        items: [...?(json['items'] as List?)],
        live: json['live'] as bool? ?? false,
        interaction: switch (json['interaction']) {
          final Map<String, Object?> map => map,
          _ => null,
        },
        choices: [
          for (final choice in (json['choices'] as List?) ?? const [])
            LinkChoice.fromJson(_map(choice)),
        ],
        changes: [
          for (final change in (json['changes'] as List?) ?? const [])
            _map(change),
        ],
        tasks: [
          for (final task in (json['tasks'] as List?) ?? const [])
            LinkTask.fromJson(_map(task)),
        ],
        earlier: json['earlier'] as bool?,
        goal: switch (json['goal']) {
          final Map<String, Object?> map => map,
          _ => null,
        },
      );

  final String session;
  final int start;

  /// The items from [start] on, as JSON.
  final List<Object?> items;

  /// How many items there are in all.
  final int count;

  /// A turn is under way.
  final bool live;

  /// What the agent waits on the user for, as JSON, if anything.
  final Map<String, Object?>? interaction;
  final List<LinkChoice> choices;

  /// The files changed and not kept yet: `{"path", "added", "removed"}`.
  final List<Map<String, Object?>> changes;

  /// The tasks left running, and the commands' that ended (for their
  /// output).
  final List<LinkTask> tasks;

  /// Whether there is more before the first item, for a session followed
  /// with a window; null if not (the desktop does not page, or it is not
  /// asked to).
  final bool? earlier;

  /// The goal the agent works toward (Claude Code's `/goal`), as JSON,
  /// if any: `{"condition", "state", "checks", "reason", "setAt",
  /// "duration", "tokens"}`, its times in milliseconds.
  final Map<String, Object?>? goal;

  Map<String, Object?> toJson() => {
    'session': session,
    'start': start,
    'count': count,
    'items': items,
    'live': live,
    'interaction': ?interaction,
    'choices': [for (final choice in choices) choice.toJson()],
    'changes': changes,
    if (tasks.isNotEmpty) 'tasks': [for (final task in tasks) task.toJson()],
    'earlier': ?earlier,
    'goal': ?goal,
  };
}

Map<String, Object?> _map(Object? json) =>
    json is Map<String, Object?> ? json : const {};
