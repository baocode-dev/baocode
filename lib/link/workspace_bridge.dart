import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:path/path.dart' as p;

import '../bots/bot.dart';
import '../bots/bots.dart';
import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../chat/composer/composer_files.dart' show fileReferenceText;
import '../customize/customization_store.dart';
import '../customize/customizations.dart';
import '../ide/file_service.dart';
import '../kernel/agent_kernel.dart' show KernelChoiceKind;
import '../kernel/kernel_types.dart';
import '../remote/project_host.dart';
import '../workspace/workspace.dart';
import 'chat_codec.dart';
import 'interaction_codec.dart';

/// A project's files, on its host, and how it spells their paths.
typedef ProjectFiles = ({IdeFileService files, p.Context paths});

/// [project]'s files on its host: this machine's, or one over SSH.
ProjectFiles hostFilesOf(Project project) {
  final host = ProjectHost.of(project.path);
  return (files: host.files(host.pathOf(project.path)), paths: host.paths);
}

/// A paired phone's view of the [Workspace], over its [LinkPeer]: the
/// projects and agents, as the sidebar lists them; the agents it follows,
/// item by item as they change; the projects' files, and Claude Code's
/// customizations; and what it asks (send, stop, answer, …), done as the
/// window would.
class WorkspaceBridge {
  WorkspaceBridge({
    required this.workspace,
    required this.peer,
    required this.device,
    this.branchOf,
    this.filesOf = hostFilesOf,
    this.customizations,
    this.bots,
    this.throttle = const Duration(milliseconds: 150),
  });

  final Workspace workspace;
  final LinkPeer peer;

  /// This desktop, as the phone lists it.
  final DeviceInfo Function() device;

  /// A project's Git branch, if it is a repository and it can be told.
  final String? Function(Project project)? branchOf;

  /// A project's files: none but the projects listed are given out.
  final ProjectFiles Function(Project project) filesOf;

  /// Claude Code's customizations on this machine; none told without.
  final CustomizationStore? customizations;

  /// The user's bots; none told without.
  final Bots? bots;

  /// How often a phone hears of changes at most: a turn's text streams in
  /// many more times than that.
  final Duration throttle;

  /// How many agents the phone gets listed, the most recent first.
  static const maxSessions = 300;

  final Map<String, _Follow> _follows = {};
  Timer? _stateTimer;
  String? _stateSent;
  bool _disposed = false;

  /// Starts telling the phone of changes; what it asks goes to [handle].
  void start() {
    workspace.addListener(_stateChanged);
    bots?.addListener(_stateChanged);
    unawaited(peer.done.then((_) => dispose()));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    workspace.removeListener(_stateChanged);
    bots?.removeListener(_stateChanged);
    _stateTimer?.cancel();
    for (final follow in _follows.values) {
      follow.dispose();
    }
    _follows.clear();
  }

  // --- Ids ------------------------------------------------------------------

  /// Each agent's id for the phones: its session's, else one given here
  /// (a new agent's, until it has one), kept for the run.
  static final Expando<String> _ids = Expando('link id');
  static int _nextId = 0;

  static String idOf(AgentThread thread) =>
      _ids[thread] ??= thread.id ?? 'new-${_nextId++}';

  AgentThread _thread(Object? id) {
    if (id is String) {
      for (final thread in workspace.threads) {
        if (idOf(thread) == id) return thread;
      }
    }
    throw LinkRemoteException(LinkErrors.notFound, 'No agent $id');
  }

  /// The project [id] (its path), one of those the phone is told of: no
  /// other folder of the machine is.
  Project _project(Object? id) {
    if (id is String) {
      for (final project in workspace.sidebarProjects) {
        if (project.path == id) return project;
      }
    }
    throw LinkRemoteException(LinkErrors.notFound, 'No project $id');
  }

  final Map<String, ProjectFiles> _files = {};

  ProjectFiles _filesOf(Project project) =>
      _files[project.path] ??= filesOf(project);

  // --- State ----------------------------------------------------------------

  LinkState state() {
    final projects = workspace.sidebarProjects;
    final listed = projects.toSet();
    final threads = [
      for (final thread in workspace.threads)
        if (!thread.archived &&
            listed.contains(thread.project) &&
            workspace.listsInSidebar(thread))
          thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final l10n = workspace.l10n();
    return LinkState(
      device: device(),
      projects: [
        for (final project in projects)
          ProjectInfo(
            id: project.path,
            name: project.name,
            path: project.root,
            branch: branchOf?.call(project),
            icon: workspace.iconOf(project)?.toJson(),
          ),
      ],
      sessions: [
        for (final thread in threads.take(maxSessions))
          SessionSummary(
            id: idOf(thread),
            project: thread.project.path,
            title: thread.localizedTitle(l10n),
            updatedAt: thread.updatedAt,
            status: switch (thread.shownStatus) {
              ThreadStatus.needsInput => LinkSessionStatus.needsInput,
              ThreadStatus.running => LinkSessionStatus.running,
              ThreadStatus.unread ||
              ThreadStatus.idle => LinkSessionStatus.idle,
            },
            unread: thread.status == ThreadStatus.unread,
            pinned: thread.pinned,
            model: thread.isOpen
                ? thread.session.selected(KernelChoiceKind.model)
                : null,
            mode: thread.isOpen
                ? thread.session.selected(KernelChoiceKind.mode)
                : null,
            permission: thread.isOpen
                ? thread.session.selected(KernelChoiceKind.permission)
                : null,
          ),
      ],
      bots: [
        if (bots case final bots?)
          for (final bot in bots.bots) _linkBot(bots, bot),
      ],
    );
  }

  LinkBot _linkBot(Bots bots, Bot bot) {
    final thread = bots.threadOf(bot);
    final session = thread == null ? null : idOf(thread);
    // Read as it comes, while the phone follows it.
    if (session != null && _follows.containsKey(session)) bots.seen(bot);
    return LinkBot(
      id: bot.id,
      name: bot.name,
      avatar: bot.avatar,
      gender: bot.gender,
      signature: bot.signature,
      identity: bot.identity,
      style: bot.style,
      abilities: bot.abilities,
      proactive: bot.proactive,
      model: bots.modelOf(bot),
      assistant: bot.assistant,
      session: session,
      status: bots.typing(bot) ? BotStatus.typing : BotStatus.idle,
      unread: bots.unread(bot),
      last: bots.lastLine(bot),
      updatedAt: thread?.updatedAt,
    );
  }

  Bots _bots() =>
      bots ??
      (throw const LinkRemoteException(LinkErrors.unsupported, 'No bots'));

  Bot _bot(Object? id) =>
      switch (id) {
        final String id => _bots().byId(id),
        _ => null,
      } ??
      (throw LinkRemoteException(LinkErrors.notFound, 'No bot $id'));

  void _stateChanged() {
    if (_disposed || _stateTimer != null) return;
    _stateTimer = Timer(throttle, () {
      _stateTimer = null;
      if (_disposed) return;
      final json = state().toJson();
      final text = jsonEncode(json);
      if (text == _stateSent) return;
      _stateSent = text;
      peer.emit(LinkEvents.state, json);
    });
  }

  // --- Requests -------------------------------------------------------------

  Future<Object?> handle(String method, Map<String, Object?> params) async {
    switch (method) {
      case LinkMethods.state:
        final json = state().toJson();
        _stateSent = jsonEncode(json);
        return json;
      case LinkMethods.open:
        final thread = _thread(params['session']);
        final id = idOf(thread);
        if (bots?.botAt(thread.project.path) case final bot?) {
          bots!.seen(bot);
        }
        _follows.remove(id)?.dispose();
        final follow = _follows[id] = _Follow(
          id: id,
          session: thread.session,
          peer: peer,
          throttle: throttle,
          window: params['window'] as int?,
          pathOf: (full) => _phonePath(thread.project, full),
        );
        return follow.start();
      case LinkMethods.earlier:
        final follow = _follows[params['session']];
        if (follow == null) {
          throw LinkRemoteException(
            LinkErrors.notFound,
            'No agent ${params['session']} followed',
          );
        }
        return follow.earlier(params['count'] as int? ?? 50);
      case LinkMethods.close:
        if (params['session'] case final String id) {
          _follows.remove(id)?.dispose();
        }
        return null;
      case LinkMethods.send:
        final text = (params['text'] as String? ?? '').trim();
        if (text.isEmpty && _images(params['images']).isEmpty) return null;
        final AgentThread thread;
        if (params['bot'] case final Object id) {
          // Its conversation, whichever it is now.
          thread = _bots().threadFor(_bot(id));
        } else if (params['session'] case final Object id) {
          thread = _thread(id);
        } else if (params['project'] case final String path) {
          thread = workspace.startAgent(_project(path));
        } else {
          throw const LinkRemoteException(
            LinkErrors.notFound,
            'No agent nor project',
          );
        }
        final session = thread.session;
        if (!session.canSend) {
          throw const LinkRemoteException('busy', 'The agent is at work');
        }
        session.send(_message(thread, params), now: params['now'] == true);
        return {'session': idOf(thread)};
      case LinkMethods.edit:
        final thread = _thread(params['session']);
        final session = thread.session;
        if (!session.canEditMessages) {
          throw const LinkRemoteException(
            LinkErrors.unsupported,
            'This agent cannot go back',
          );
        }
        // Counted from the phone's first item, as its updates are.
        final index =
            (_follows[idOf(thread)]?.from ?? 0) +
            (params['index'] as int? ?? -1);
        if (index < 0 ||
            index >= session.itemCount ||
            session.itemAt(index) is! UserMessageItem) {
          throw const LinkRemoteException(
            LinkErrors.notFound,
            'No message there',
          );
        }
        final message = _message(thread, params);
        if (message.isEmpty) return null;
        session.editMessage(index, message);
        return null;
      case LinkMethods.stop:
        _thread(params['session']).session.stop();
        return null;
      case LinkMethods.answer:
        final session = _thread(params['session']).session;
        final pending = session.pendingInteraction;
        final answer = InteractionCodec.decodeAnswer(params['answer']);
        if (pending == null || pending.id != params['request']) {
          throw const LinkRemoteException(
            LinkErrors.notFound,
            'Nothing is asked',
          );
        }
        if (answer == null) {
          throw const LinkRemoteException('bad', 'Not an answer');
        }
        session.answer(answer);
        return null;
      case LinkMethods.startPlan:
        final session = _thread(params['session']).session;
        if (session.awaitingPlan == null) {
          throw const LinkRemoteException(
            LinkErrors.notFound,
            'No plan awaits',
          );
        }
        if (!session.canStartPlan) {
          throw const LinkRemoteException('busy', 'The agent is at work');
        }
        session.startPlan(workspace.l10n().planStartMessage);
        return null;
      case LinkMethods.choose:
        final thread = _thread(params['session']);
        final kind = params['kind'] as String? ?? '';
        final option = params['option'] as String? ?? '';
        final bot = bots?.botAt(thread.project.path);
        // A bot's agent asks nothing and works as one: only its model,
        // and how it thinks, are the user's to pick.
        if (bot != null && (kind == 'mode' || kind == 'permission')) {
          throw const LinkRemoteException(
            LinkErrors.unsupported,
            'A bot works as it does',
          );
        }
        _choose(thread.session, kind, option);
        if (bot != null && kind == 'model') {
          if (thread.session.models?.selected.id case final model?) {
            bots!.setModel(bot, model);
          }
        }
        return null;
      case LinkMethods.rename:
        workspace.rename(
          _thread(params['session']),
          params['title'] as String? ?? '',
        );
        return null;
      case LinkMethods.pin:
        workspace.setPinned(
          _thread(params['session']),
          params['pinned'] == true,
        );
        return null;
      case LinkMethods.archive:
        workspace.setArchived(_thread(params['session']), true);
        return null;
      case LinkMethods.keep:
        final session = _thread(params['session']).session;
        switch (_paths(params, session)) {
          case null:
            session.keepAllChanges();
          case final paths:
            session.keepChanges([
              for (final change in session.fileChanges)
                if (paths.contains(change.path)) change,
            ]);
        }
        return null;
      case LinkMethods.undo:
        final session = _thread(params['session']).session;
        switch (_paths(params, session)) {
          case null:
            session.undoAllChanges?.call();
          case final paths:
            session.undoChanges?.call([
              for (final change in session.fileChanges)
                if (paths.contains(change.path)) change,
            ]);
        }
        return null;
      case LinkMethods.stopTask:
        final session = _thread(params['session']).session;
        if (params['agent'] case final String agent) {
          session.stopOf(agent)?.call();
          return null;
        }
        final task = _task(session, params['task']);
        if (task != null) session.stopTask(task);
        return null;
      case LinkMethods.output:
        final thread = _thread(params['session']);
        final path = _task(thread.session, params['task'])?.outputFile;
        if (path == null) return {'text': ''};
        try {
          final text = await _filesOf(thread.project).files
              .read(path, force: true);
          return {
            'text': text.length <= LinkLimits.output
                ? text
                : text.substring(text.length - LinkLimits.output),
          };
        } on Object {
          return {'text': ''};
        }
      case LinkMethods.files:
        return _listFiles(_project(params['project']));
      case LinkMethods.read:
        return _readFile(
          _project(params['project']),
          params['path'] as String? ?? '',
        );
      case LinkMethods.image:
        return _readImage(
          _project(params['project']),
          params['path'] as String? ?? '',
        );
      case LinkMethods.extensions:
        return {
          'items': [for (final item in await _extensions()) item.toJson()],
        };
      case LinkMethods.draft:
        return {
          'session': idOf(workspace.startAgent(_project(params['project']))),
        };
      case LinkMethods.saveBot:
        final bots = _bots();
        final saved = bots.save(
          id: params['bot'] as String?,
          name: params['name'] as String? ?? '',
          avatar: params['avatar'] as String?,
          gender: params['gender'] as String? ?? '',
          signature: params['signature'] as String? ?? '',
          identity: params['identity'] as String? ?? '',
          style: params['style'] as String? ?? '',
          abilities: {
            for (final name in (params['abilities'] as List?) ?? const [])
              ?BotAbility.values.asNameMap()[name],
          },
          proactive: switch (params['proactive']) {
            final Map<String, Object?> json => BotProactive.fromJson(json),
            _ => const BotProactive(),
          },
          avatarImage: _avatarImage(params['avatarImage']),
        );
        return {'bot': _linkBot(bots, saved).toJson()};
      case LinkMethods.botAvatar:
        final image = _bots().avatarImage(_bot(params['bot']));
        if (image == null) {
          throw const LinkRemoteException(LinkErrors.notFound, 'No picture');
        }
        return {'type': image.type, 'data': base64Encode(image.bytes)};
      case LinkMethods.deleteBot:
        final bot = _bot(params['bot']);
        if (bot.assistant) {
          throw const LinkRemoteException(
            LinkErrors.unsupported,
            'The assistant stays',
          );
        }
        _bots().delete(bot.id);
        return null;
      case LinkMethods.clearBotChat:
        _bots().clearChat(_bot(params['bot']));
        return null;
      case LinkMethods.botMemory:
        final bot = _bot(params['bot']);
        return {'text': _bots().memory(bot), 'self': _bots().selfNotes(bot)};
      case LinkMethods.setBotMemory:
        _bots().setMemory(_bot(params['bot']), params['text'] as String? ?? '');
        return null;
      case LinkMethods.setBotSelf:
        _bots().setSelfNotes(
          _bot(params['bot']),
          params['text'] as String? ?? '',
          restart: true,
        );
        return null;
      case LinkMethods.setMe:
        String text(String key) => switch (params[key]) {
          final String value => value.trim(),
          _ => '',
        };
        _bots().setMe(
          BotUser(
            name: text('name'),
            gender: text('gender'),
            signature: text('signature'),
          ),
          _avatarImage(params['picture']),
        );
        return null;
      case LinkMethods.icon:
        final id = params['id'];
        final image = id is String ? workspace.icons[id] : null;
        if (image == null) {
          throw LinkRemoteException(LinkErrors.notFound, 'No icon $id');
        }
        return {'kind': image.kind.name, 'data': base64Encode(image.bytes)};
    }
    throw LinkRemoteException('unknown', 'No such request: $method');
  }

  static KernelTask? _task(ChatSession session, Object? id) {
    for (final task in session.terminalTasks) {
      if (task.id == id) return task;
    }
    for (final task in session.tasks ?? const <KernelTask>[]) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// What the phone sent ([LinkMethods.send], [LinkMethods.edit]) as the
  /// composer would send it to [thread]: its files named by their paths as
  /// the agent finds them, its pictures numbered on from the
  /// conversation's and named in the text.
  ComposerMessage _message(AgentThread thread, Map<String, Object?> params) {
    var text = (params['text'] as String? ?? '').trim();
    final images = _images(params['images']);
    final named = [
      for (final mention in (params['mentions'] as List?) ?? const [])
        if (mention is String && mention.isNotEmpty) mention,
    ];
    // A workspace's files named from its folders' names: by their
    // paths, as its agent finds them.
    final mentions = <String>[];
    final multiRoot = _rootsOf(thread.project).first.$1.isNotEmpty;
    for (final mention in named) {
      final full = _fullPath(thread.project, mention);
      if (full == null || !multiRoot) {
        mentions.add(mention);
        continue;
      }
      text = text.replaceAll(
        fileReferenceText(mention),
        fileReferenceText(full),
      );
      mentions.add(full);
    }
    // Numbered on from the conversation's, as the composer numbers what
    // is pasted, and named in the text as it names them.
    var next = thread.session.lastImageNumber + 1;
    final numbered = [for (final image in images) image.withNumber(next++)];
    if (numbered.isNotEmpty) {
      final references = [
        for (final image in numbered) '[Image #${image.number}]',
      ].join(' ');
      text = text.isEmpty ? references : '$text\n$references';
    }
    return ComposerMessage(text: text, mentions: mentions, images: numbered);
  }

  /// A picture of [project] the phone shows, as a reply names it.
  Future<Map<String, Object?>> _readImage(Project project, String path) async {
    final (:files, :paths) = _filesOf(project);
    final full =
        _fullPath(project, path) ??
        _changesIn(project).keys
            .where((c) => paths.equals(c, path))
            .firstOrNull;
    final type = switch (paths.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      _ => null,
    };
    if (full == null) {
      throw LinkRemoteException(LinkErrors.notFound, 'No file $path');
    }
    if (type == null) {
      throw LinkRemoteException('bad', 'Not a picture: $path');
    }
    try {
      final bytes = await readBytesThrough(files, full);
      if (bytes.length > LinkLimits.image) {
        return {'tooLarge': true, 'size': bytes.length};
      }
      return {'type': type, 'data': base64Encode(bytes)};
    } on Object {
      throw LinkRemoteException(LinkErrors.notFound, 'No file $path');
    }
  }

  static const _imageTypes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  };

  static List<ImageAttachment> _images(Object? json) => [
    for (final image in (json as List?) ?? const [])
      if (image case {'data': final String data, 'type': final String type}
          when _imageTypes.contains(type))
        ?_image(data, type, image['name'] as String?),
  ];

  /// A bot's new picture, as [LinkMethods.saveBot] sends it; none for
  /// none, `bad` for what is not one.
  static BotAvatarImage? _avatarImage(Object? json) {
    if (json == null) return null;
    if (json case {'data': final String data, 'type': final String type}
        when _imageTypes.contains(type)) {
      if (_image(data, type, null) case final image?
          when image.bytes.isNotEmpty &&
              image.bytes.length <= LinkLimits.avatar) {
        return (bytes: image.bytes, type: type);
      }
    }
    throw const LinkRemoteException('bad', 'Not a picture, or too large');
  }

  static ImageAttachment? _image(String data, String type, String? name) {
    try {
      return ImageAttachment(
        bytes: base64.decode(data),
        mediaType: type,
        name: name,
      );
    } on FormatException {
      return null;
    }
  }

  /// The changes not kept yet of [project]'s agents open, by path.
  Map<String, FileChange> _changesIn(Project project) => {
    for (final thread in workspace.threads)
      if (thread.project == project && thread.isOpen)
        for (final change in thread.session.fileChanges) change.path: change,
  };

  /// The folders [project]'s files are in, each with the name the phone
  /// gives it: a folder's project, its own, unnamed; a workspace's, each of
  /// its folders under its name, as VS Code's Explorer has them (not the
  /// workspace's own folder, which holds only its settings).
  List<(String, String)> _rootsOf(Project project) {
    final folders = workspace.workspaceOf(project)?.folders ?? const [];
    if (folders.isEmpty) return [('', project.root)];
    final paths = _filesOf(project).paths;
    final taken = <String>{};
    return [
      for (final folder in folders)
        (_unique(paths.basename(folder), taken), folder),
    ];
  }

  static String _unique(String name, Set<String> taken) {
    var unique = name.isEmpty ? 'folder' : name;
    for (var i = 2; !taken.add(unique); i++) {
      unique = '$name ($i)';
    }
    return unique;
  }

  /// [full] as the phone names it in [project] (POSIX, from its roots);
  /// null when it is in none of them.
  String? _phonePath(Project project, String full) {
    final paths = _filesOf(project).paths;
    for (final (name, root) in _rootsOf(project)) {
      if (!paths.isWithin(root, full)) continue;
      final relative = paths.relative(full, from: root).replaceAll(r'\', '/');
      return name.isEmpty ? relative : '$name/$relative';
    }
    return null;
  }

  /// The file the phone names [path] in [project]: in one of its roots,
  /// `..` getting no further; null for none.
  String? _fullPath(Project project, String path) {
    final paths = _filesOf(project).paths;
    for (final (name, root) in _rootsOf(project)) {
      final rest = name.isEmpty
          ? path
          : path.startsWith('$name/')
          ? path.substring(name.length + 1)
          : null;
      if (rest == null || rest.isEmpty) continue;
      final full = paths.normalize(paths.join(root, rest));
      if (paths.isWithin(root, full)) return full;
    }
    return null;
  }

  Future<Map<String, Object?>> _listFiles(Project project) async {
    final (:files, :paths) = _filesOf(project);
    final listed = <String>[];
    var truncated = false;
    for (final (name, root) in _rootsOf(project)) {
      final left = LinkLimits.files - listed.length;
      if (left <= 0) {
        truncated = true;
        break;
      }
      final IdeFileListing listing;
      try {
        listing = await listProjectFiles(files, root, limit: left);
      } on Object {
        continue; // A folder gone: the others still are.
      }
      for (final path in listing.paths) {
        final relative = paths.relative(path, from: root).replaceAll(r'\', '/');
        listed.add(name.isEmpty ? relative : '$name/$relative');
      }
      truncated |= listing.truncated;
    }
    return {
      'paths': listed,
      if (truncated) 'truncated': true,
      'changes': {
        for (final change in _changesIn(project).values)
          if (change.kind != FileChangeKind.deleted)
            ?_phonePath(project, change.path): change.kind.name,
      },
    };
  }

  Future<Map<String, Object?>> _readFile(Project project, String path) async {
    final (:files, :paths) = _filesOf(project);
    // In its folders; else one its agents changed elsewhere, as the
    // phone is told of it (by its full path).
    final full =
        _fullPath(project, path) ??
        _changesIn(project).keys
            .where((c) => paths.equals(c, path))
            .firstOrNull;
    if (full == null) {
      throw LinkRemoteException(LinkErrors.notFound, 'No file $path');
    }
    final String text;
    try {
      text = await files.read(full);
    } on IdeBinaryFileException {
      return {'binary': true};
    } on IdeFileTooLargeException catch (error) {
      return {'tooLarge': true, 'size': error.size};
    } on Object {
      throw LinkRemoteException(LinkErrors.notFound, 'No file $path');
    }
    if (text.length > LinkLimits.file) {
      return {'tooLarge': true, 'size': text.length};
    }
    String? original;
    for (final thread in workspace.threads) {
      if (thread.project != project || !thread.isOpen) continue;
      final session = thread.session;
      final change = session.fileChanges
          .where((c) => paths.equals(c.path, full))
          .firstOrNull;
      if (change == null) continue;
      if (change.kind == FileChangeKind.added) {
        original = '';
        break;
      }
      try {
        original = await session.originalOf(change)?.call();
      } on Object {
        // Not known: shown as it is.
      }
      if (original != null) break;
    }
    return {
      'text': text,
      if (original != null && original.length <= LinkLimits.file)
        'original': original,
    };
  }

  /// The skills, servers, plugins and subagents: the user's, and those of
  /// the projects on this machine.
  Future<List<LinkExtension>> _extensions() async {
    final store = customizations;
    if (store == null || !store.supported) return const [];
    const kinds = {
      CustomizationKind.skills: 'skill',
      CustomizationKind.mcps: 'mcp',
      CustomizationKind.plugins: 'plugin',
      CustomizationKind.subagents: 'agent',
    };
    final local = [
      for (final project in workspace.sidebarProjects)
        if (project.host == null) project,
    ];
    Future<List<LinkExtension>> of(
      CustomizationKind kind,
      Project? project,
    ) async {
      final List<Customization> items;
      try {
        items = await store.list(kind, project: project?.root);
      } on Object {
        return const [];
      }
      return [
        for (final item in items)
          // A project's own; the user's come once, with no project.
          if ((project == null) ==
              (item.scope != CustomizationScope.project &&
                  item.scope != CustomizationScope.local))
            LinkExtension(
              kind: kinds[kind]!,
              scope: item.scope.name,
              name: item.name,
              description: item.description,
              project: project?.path,
              enabled: item.enabled,
            ),
      ];
    }

    final lists = await Future.wait([
      for (final kind in kinds.keys) ...[
        of(kind, null),
        for (final project in local) of(kind, project),
      ],
    ]);
    return [for (final list in lists) ...list];
  }

  /// The changes' paths [params] names, absolute as [session] has them;
  /// null for all of them.
  static Set<String>? _paths(Map<String, Object?> params, ChatSession session) {
    final paths = params['paths'];
    if (paths is! List) return null;
    return {
      for (final path in paths.whereType<String>())
        session.paths.isAbsolute(path) || session.root == null
            ? path
            : session.paths.join(session.root!, path),
    };
  }

  static void _choose(ChatSession session, String kind, String id) {
    final KernelChoice? choice = switch (kind) {
      'model' => session.models,
      'mode' => session.modes,
      'permission' => session.permissions,
      _ => null,
    };
    if (choice != null) {
      final option = choice.options.where((o) => o.id == id).firstOrNull;
      if (option != null) choice.onSelected(option);
      return;
    }
    final model = session.models?.selected.id;
    if (model == null) return;
    for (final setting in session.modelSettings(model)) {
      if (setting.kind?.name != kind) continue;
      final option = setting.options.where((o) => o.id == id).firstOrNull;
      if (option != null) setting.onSelected(option);
    }
  }
}

/// An agent a phone follows: everything at first, then what changed, at
/// most every [throttle].
class _Follow {
  _Follow({
    required this.id,
    required this.session,
    required this.peer,
    required this.throttle,
    required this.pathOf,
    this.window,
  });

  final String id;
  final ChatSession session;
  final LinkPeer peer;
  final Duration throttle;

  /// How many of the last items the phone follows at first, if it pages
  /// back through the rest (see [earlier]); null for all of them.
  final int? window;

  /// A changed file's path as the phone names it in the project; null for
  /// one outside it, given as it is.
  final String? Function(String full) pathOf;

  /// The session's index of the phone's first item: 0 unless it has a
  /// [window].
  int _from = 0;

  /// [_from], as it is now (items put before the first move it).
  int get from {
    _syncFrom();
    return _from;
  }

  /// The session's [ChatSession.prependedCount] as last seen, to move
  /// [_from] along with items put before the first.
  int _prependedSeen = 0;

  /// The items as last sent, from [_from]: what is still the same object
  /// was not changed (items are not changed in place).
  List<ChatItem> _sent = const [];

  /// [_sent]'s items as JSON text, to tell one read afresh from a change.
  List<String> _sentJson = const [];
  String? _restSent;
  Timer? _timer;
  bool _disposed = false;

  Map<String, Object?> start() {
    _prependedSeen = session.prependedCount;
    if (window case final window?) {
      _from = math.max(0, session.itemCount - window);
    }
    session
      ..attach()
      ..addListener(_changed);
    return _update(full: true)!.toJson();
  }

  void _changed() {
    if (_disposed || _timer != null) return;
    _timer = Timer(throttle, () {
      _timer = null;
      if (_disposed) return;
      final update = _update();
      if (update != null) peer.emit(LinkEvents.session, update.toJson());
    });
  }

  /// What changed since last sent; everything when [full]. Null when
  /// nothing did.
  LinkSessionUpdate? _update({bool full = false}) {
    _syncFrom();
    final total = session.itemCount;
    if (total < _from) {
      // Rewound to before the window.
      _from = total;
      full = true;
    }
    final count = total - _from;
    final items = [for (var i = _from; i < total; i++) session.itemAt(i)];
    final encoded = List<Map<String, Object?>?>.filled(count, null);
    var start = 0;
    if (!full) {
      // The same object, or another of the same JSON (a history read
      // afresh), is what was sent.
      while (start < _sent.length && start < count) {
        if (!identical(_sent[start], items[start])) {
          final json = encoded[start] = ChatCodec.encode(items[start]);
          if (jsonEncode(json) != _sentJson[start]) break;
        }
        start++;
      }
    }
    final interaction = switch (session.pendingInteraction) {
      final request? => InteractionCodec.encode(request),
      null => null,
    };
    final choices = _choices();
    final changes = [for (final change in session.fileChanges) _change(change)];
    final tasks = _tasks();
    final earlier = window == null
        ? null
        : _from > 0 || session.hasEarlierHistory || session.loadingEarlier;
    final goal = _goal(session.goal);
    final restText = jsonEncode([
      earlier,
      goal,
      session.isStreaming,
      interaction,
      [for (final choice in choices) choice.toJson()],
      changes,
      [for (final task in tasks) task.toJson()],
    ]);
    if (!full &&
        start == count &&
        _sent.length == count &&
        restText == _restSent) {
      return null;
    }
    final json = [
      for (var i = start; i < count; i++)
        encoded[i] ?? ChatCodec.encode(items[i]),
    ];
    _sentJson = [
      ..._sentJson.take(start),
      for (final item in json) jsonEncode(item),
    ];
    _sent = items;
    _restSent = restText;
    return LinkSessionUpdate(
      session: id,
      start: start,
      count: count,
      items: json,
      live: session.isStreaming,
      interaction: interaction,
      choices: choices,
      changes: changes,
      tasks: tasks,
      earlier: earlier,
      goal: goal,
    );
  }

  /// [goal] as the phone reads it (see [LinkSessionUpdate.goal]).
  static Map<String, Object?>? _goal(KernelGoal? goal) => switch (goal) {
    null => null,
    final goal => {
      'condition': goal.condition,
      'state': goal.state.name,
      if (goal.checks > 0) 'checks': goal.checks,
      'reason': ?goal.lastReason,
      'setAt': ?goal.setAt?.millisecondsSinceEpoch,
      'duration': ?goal.duration?.inMilliseconds,
      'tokens': ?goal.tokens,
    },
  };

  /// Moves [_from] along with the items put before the session's first
  /// (the phone's own first is still the same one).
  void _syncFrom() {
    final moved = session.prependedCount - _prependedSeen;
    _prependedSeen = session.prependedCount;
    if (window != null) _from += moved;
  }

  /// Up to [count] items before the phone's first, oldest first, read from
  /// the history first if the session has no more in memory.
  Future<Map<String, Object?>> earlier(int count) async {
    if (window == null) {
      throw const LinkRemoteException('bad', 'Not opened with a window');
    }
    _syncFrom();
    if (_from == 0 && session.hasEarlierHistory) await session.loadEarlier();
    if (_disposed) return {'items': const [], 'earlier': false};
    // No await from here on: no update comes between taking the items and
    // telling of them.
    _syncFrom();
    final n = math.min(math.max(count, 0), _from);
    final items = [for (var i = _from - n; i < _from; i++) session.itemAt(i)];
    final json = [for (final item in items) ChatCodec.encode(item)];
    _sent = [...items, ..._sent];
    _sentJson = [for (final item in json) jsonEncode(item), ..._sentJson];
    _from -= n;
    return {'items': json, 'earlier': _from > 0 || session.hasEarlierHistory};
  }

  /// Those running, and the commands that ended, for their output.
  List<LinkTask> _tasks() {
    final tasks = <String, KernelTask>{
      for (final task in session.tasks ?? const <KernelTask>[]) task.id: task,
      for (final task in session.terminalTasks) task.id: task,
    };
    return [
      for (final task in tasks.values)
        LinkTask(
          id: task.id,
          kind: task.kind.name,
          description: task.description,
          status: task.status.name,
          startedAt: task.startedAt,
          toolUseId: task.toolUseId,
          command: task.kind == KernelTaskKind.command
              ? session.commandOf(task.toolUseId)
              : null,
          summary: task.summary,
          output: task.outputFile != null,
        ),
    ];
  }

  Map<String, Object?> _change(FileChange change) {
    final path = pathOf(change.path) ?? change.path;
    return {
      // POSIX on the phone, whatever the desktop.
      'path': path.replaceAll(r'\', '/'),
      'added': change.added,
      'removed': change.removed,
      if (change.kind != FileChangeKind.modified) 'kind': change.kind.name,
      if (change.binary) 'binary': true,
      if (!change.tracked) 'tracked': false,
      if (change.conflict) 'conflict': true,
    };
  }

  List<LinkChoice> _choices() {
    LinkChoice? of(String kind, KernelChoice? choice) => switch (choice) {
      final choice? => LinkChoice(
        kind: kind,
        selected: choice.selected.id,
        options: [for (final option in choice.options) _option(option)],
      ),
      null => null,
    };
    final model = session.models;
    return [
      ?of('model', model),
      ?of('mode', session.modes),
      ?of('permission', session.permissions),
      if (model != null)
        for (final setting in session.modelSettings(model.selected.id))
          if (setting.kind case final kind?)
            LinkChoice(
              kind: kind.name,
              selected: setting.selected?.id,
              options: [for (final option in setting.options) _option(option)],
            ),
    ];
  }

  static LinkOption _option(KernelOption option) => LinkOption(
    id: option.id,
    label: option.label,
    description: option.description,
    group: option.group?.id,
    groupLabel: option.group?.label,
    caution: option.caution,
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    session.removeListener(_changed);
    session.detach();
  }
}
