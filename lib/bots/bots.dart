import 'dart:async';

import 'package:bao_link/bao_link.dart' show builtInSticker;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../images/image_tools.dart' show ImageTools;
import '../kernel/agent_kernel.dart';
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../kernel/kernel_registry.dart';
import '../kernel/queued_messages.dart';
import '../link/chat_codec.dart';
import '../workspace/preference_store.dart';
import '../workspace/workspace.dart';
import 'bot.dart';
import 'bot_folders.dart';
import 'bot_pacer.dart';
import 'bot_prompt.dart';
import 'bot_tools.dart';

/// A bot's picture: its bytes, and their media type.
typedef BotAvatarImage = ({Uint8List bytes, String type});

/// The user's bots: agents of their own making that chat as a person does
/// (see bot.dart), each a conversation in a folder of its own, which the
/// sidebar does not list. Their tools are theirs ([ClaudeSdkGate]): those
/// of the abilities the user turned on; and they write first of what
/// happens to the agents, paced ([BotPacer]).
class Bots extends ChangeNotifier implements ClaudeSdkGate {
  Bots({
    required this.workspace,
    BotFolders? folders,
    this.store,
    DateTime Function()? clock,
    this.chinese = false,
    this.longRun = const Duration(minutes: 30),
  }) : folders = folders ?? BotFolders.data(),
       _clock = clock ?? DateTime.now;

  final Workspace workspace;
  final BotFolders folders;

  /// Where the list of them is kept.
  final PreferenceStore? store;
  final DateTime Function() _clock;

  /// Whether the assistant made at first is named and told in Chinese.
  final bool chinese;

  /// How long an agent runs before the bots are told it does.
  final Duration longRun;

  /// The settings its agent runs with: it asks nothing (its tools are
  /// allowed, all else refused), and works as an agent, not in Plan.
  static const settings = {'mode': 'agent', 'permission': 'dontAsk'};

  List<Bot> _bots = [];
  List<Bot> get bots => List.unmodifiable(_bots);

  final Map<String, BotPacer> _pacers = {};
  Timer? _timer;

  /// What each bot meant to come back to, by its id, soonest first.
  final Map<String, List<BotLater>> _laters = {};

  /// The most a bot may have waiting to come back to.
  static const maxLaters = 5;

  /// The last turn end of each bot's the user has seen, by its id.
  final Map<String, int> _seen = {};

  /// How each agent stood when last looked at, to tell what changed.
  final Map<AgentThread, ThreadStatus> _statuses = {};

  /// Since when each agent at work has run; and those told of already.
  final Map<AgentThread, DateTime> _runningSince = {};
  final Set<AgentThread> _toldRunning = {};
  Timer? _runningTimer;

  bool _started = false;

  /// Each bot's conversation followed, for the phones to hear of each of
  /// its messages (not only of its turns' ends): what it was at last.
  final Map<ChatSession, VoidCallback> _followed = {};

  Future<void> start() async {
    final root = folders.root;
    if (root == null || _started) return;
    _started = true;
    final kept = await store?.read() ?? const {};
    _bots = [
      for (final json in (kept['bots'] as List?) ?? const [])
        ?Bot.fromJson(json, root: root),
    ];
    if (kept['later'] case final Map<String, Object?> laters) {
      for (final MapEntry(:key, :value) in laters.entries) {
        _laters[key] = [
          for (final json in value is List ? value : const [])
            ?BotLater.fromJson(json),
        ];
      }
    }
    if (!_bots.any((bot) => bot.assistant)) {
      final defaults = assistantDefaults(chinese: chinese);
      _bots.insert(
        0,
        Bot(
          id: 'assistant',
          name: defaults.name,
          folder: p.join(root, 'assistant'),
          identity: defaults.identity,
          abilities: BotAbility.values.toSet(),
          assistant: true,
        ),
      );
      _save();
    }
    for (final bot in _bots) {
      folders.make(bot.folder);
    }
    workspace.agentSetup = _setup;
    ClaudeSdkTools.gate = this;
    BotTools.register(this);
    // Each with its conversation, for the phones to open from the first.
    _bots.forEach(threadFor);
    workspace.addListener(_watch);
    _watch();
    _schedule();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_started) {
      workspace.removeListener(_watch);
      if (identical(ClaudeSdkTools.gate, this)) ClaudeSdkTools.gate = null;
      BotTools.unregister();
      workspace.agentSetup = null;
    }
    for (final MapEntry(key: session, value: listener) in _followed.entries) {
      session.removeListener(listener);
    }
    _followed.clear();
    _timer?.cancel();
    _runningTimer?.cancel();
    super.dispose();
  }

  void _save() => unawaited(
    store?.write({
      'bots': [for (final bot in _bots) bot.toJson()],
      'later': {
        for (final MapEntry(:key, :value) in _laters.entries)
          if (value.isNotEmpty)
            key: [for (final later in value) later.toJson()],
      },
    }),
  );

  /// The time, as the bots have it.
  DateTime get now => _clock();

  Bot? byId(String id) => _bots.where((bot) => bot.id == id).firstOrNull;

  /// The bot whose folder [cwd] is.
  Bot? botAt(String cwd) => _bots.where((bot) => bot.folder == cwd).firstOrNull;

  AgentSetup? _setup(String path) => switch (botAt(path)) {
    final bot? => AgentSetup(
      workspace: () => KernelWorkspace(
        folders: const [],
        instructions: botInstructions(
          bot,
          memory: folders.readMemory(bot.folder),
          now: _clock(),
          imageModel:
              ClaudeSdkTools.called(
                'mcp__${ClaudeSdkTools.server}__${ImageTools.name}',
              ) !=
              null,
        ),
        // Told only who it is and how it talks: no coding agent's prompt.
        ownPrompt: true,
        // Its own tools only; the tool search, for the browser's, which
        // are deferred.
        tools: bot.can(BotAbility.browser) ? const ['ToolSearch'] : const [],
        // What the user writes while it talks, taken up as it does: as a
        // person hears what is said meanwhile.
        queuedMessages: QueuedMessages.duringTurn,
      ),
      settings: {...settings, 'model': ?bot.model},
      kernel: KernelRegistry.claudeCode.id,
    ),
    null => null,
  };

  // --- What a bot is offered -------------------------------------------------

  @override
  bool offersTool(String cwd, String tool) {
    final bot = botAt(cwd);
    final ability = BotTools.abilityOf(tool);
    if (bot == null) return ability == null;
    if (ability != null) return ability.allows(bot);
    // The app's other tools: pictures made, if it may make them; the
    // browser's, if it may use it.
    if (tool == ImageTools.name) return bot.can(BotAbility.images);
    return bot.can(BotAbility.browser) &&
        ClaudeSdkTools.called('mcp__${ClaudeSdkTools.server}__$tool')?.kind ==
            ToolKind.browser;
  }

  /// Not a bot's: there is no one at the computer to ask, its user on the
  /// phone.
  @override
  bool asksUser(String cwd) => botAt(cwd) == null;

  @override
  bool tellsFeature(String cwd, String feature) => switch (botAt(cwd)) {
    null => true,
    final bot => feature == 'browser' && bot.can(BotAbility.browser),
  };

  // --- Its conversation --------------------------------------------------

  /// [bot]'s conversation, if it has one.
  AgentThread? threadOf(Bot bot) {
    AgentThread? latest;
    for (final thread in workspace.threads) {
      if (thread.project.path != bot.folder || thread.archived) continue;
      if (latest == null || thread.updatedAt.isAfter(latest.updatedAt)) {
        latest = thread;
      }
    }
    return latest;
  }

  /// [bot]'s conversation, started if it has none.
  AgentThread threadFor(Bot bot) {
    if (threadOf(bot) case final thread?) return thread;
    folders.make(bot.folder);
    return workspace.startAgent(workspace.projectAt(bot.folder));
  }

  /// Has [bot]'s agent start again on its conversation, to be told what
  /// changed (its identity, abilities, memory) from its next message.
  void _restart(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return;
    final session = thread.session;
    if (!session.isStreaming && session.sessionId != null) session.restart();
  }

  /// How many messages [bot] sent since the user last read it: each of
  /// its messages, stickers, cards and pictures, as a chat app counts.
  int unread(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return 0;
    final session = thread.session;
    final count = session.itemCount;
    final seen = (_seen[bot.id] ??= count).clamp(0, count);
    final quiet = ChatCodec.botQuiet(count, session.itemAt);
    var unread = 0;
    for (var i = seen; i < count; i++) {
      if (_shown(session.itemAt(i), quiet.contains(i))) unread++;
    }
    return unread;
  }

  /// The user has read all [bot] said.
  void seen(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return;
    _seen[bot.id] = thread.session.itemCount;
    notifyListeners();
  }

  /// Whether [item] shows in a bot's chat as one of its messages: what it
  /// sent; a text of its own, unless [quiet] (see [ChatCodec.botQuiet]).
  static bool _shown(ChatItem item, bool quiet) => switch (item) {
    AssistantTextItem(:final text) => !quiet && text.trim().isNotEmpty,
    _ => ChatCodec.botSent(item),
  };

  /// Whether [bot] is writing to the user: at work, not on a note to
  /// itself at the end of a turn it talked in (see [ChatCodec.botQuiet]).
  bool typing(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || thread.status != ThreadStatus.running) return false;
    if (!thread.isOpen) return true;
    final session = thread.session;
    final last = session.itemCount - 1;
    return last < 0 ||
        session.itemAt(last) is! AssistantTextItem ||
        !ChatCodec.botQuiet(session.itemCount, session.itemAt).contains(last);
  }

  /// The last [bot] said: its first line; a picture or a sticker, as a
  /// chat app's list says it.
  String? lastLine(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return null;
    final session = thread.session;
    final quiet = ChatCodec.botQuiet(session.itemCount, session.itemAt);
    String? firstLine(String text) {
      final line = text
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      if (line.isEmpty) return null;
      return line.length > 120 ? '${line.substring(0, 120)}…' : line;
    }

    for (var i = session.itemCount - 1; i >= 0; i--) {
      switch (session.itemAt(i)) {
        case AssistantTextItem(:final text) when !quiet.contains(i):
          if (firstLine(text) case final line?) return line;
        case final ToolCallItem item when ChatCodec.botSay(item) != null:
          if (firstLine(ChatCodec.botSay(item)!) case final line?) return line;
        case final ToolCallItem item when ChatCodec.botSticker(item) != null:
          final sticker = builtInSticker(ChatCodec.botSticker(item)!);
          final said = sticker == null
              ? ''
              : ' ${chinese ? sticker.zh : sticker.en}';
          return '${chinese ? '[表情]' : '[Sticker]'}$said';
        case final ToolCallItem item
            when item.status != ToolStatus.failed &&
                (item.images.isNotEmpty || ChatCodec.botImageUrl(item) != null):
          return chinese ? '[图片]' : '[Picture]';
        default:
      }
    }
    return null;
  }

  // --- Made, changed, deleted -----------------------------------------------

  /// [id]'s bot changed as given, or a new one (no [id]).
  Bot save({
    String? id,
    required String name,
    String? avatar,
    String gender = '',
    String signature = '',
    required String identity,
    String style = '',
    required Set<BotAbility> abilities,
    BotProactive proactive = const BotProactive(),
    BotAvatarImage? avatarImage,
  }) {
    final root = folders.root;
    if (root == null) throw StateError('No bots here');
    name = name.trim();
    if (name.isEmpty) throw ArgumentError('A bot needs a name');
    final Bot bot;
    if (id == null) {
      final newId = _newId();
      bot = Bot(
        id: newId,
        name: name,
        folder: '',
        avatar: _avatar(p.join(root, newId), avatar, avatarImage),
        gender: gender.trim(),
        signature: signature.trim(),
        identity: identity.trim(),
        style: style.trim(),
        abilities: abilities,
        proactive: proactive,
      );
      final made = Bot.fromJson(bot.toJson(), root: root)!;
      folders.make(made.folder);
      _bots.add(made);
      if (_started) threadFor(made);
      _save();
      notifyListeners();
      return made;
    }
    final index = _bots.indexWhere((b) => b.id == id);
    if (index < 0) throw StateError('No bot $id');
    final had = _bots[index];
    final picked = _avatar(had.folder, avatar, avatarImage, had: had.avatar);
    if (had.avatarFile case final file? when picked != had.avatar) {
      folders.deleteFile(file);
    }
    bot = _bots[index] = had.copyWith(
      name: name,
      avatar: picked,
      clearAvatar: picked == null,
      gender: gender.trim(),
      signature: signature.trim(),
      identity: identity.trim(),
      style: style.trim(),
      abilities: abilities,
      proactive: proactive,
    );
    if (proactive.perDay <= 0 || !bot.can(BotAbility.proactive)) {
      _pacers.remove(bot.id);
    }
    _save();
    _restart(bot);
    notifyListeners();
    return bot;
  }

  /// The avatar a bot in [folder] is saved with: [image], kept there as
  /// a file named after what it shows; else [asked], an emoji, or the
  /// picture it [had].
  String? _avatar(
    String folder,
    String? asked,
    BotAvatarImage? image, {
    String? had,
  }) {
    if (image != null) {
      final hash = sha1.convert(image.bytes).toString().substring(0, 12);
      final name = 'avatar-$hash${_extensions[image.type] ?? '.png'}';
      folders.writeFile(p.join(folder, name), image.bytes);
      return name;
    }
    final avatar = asked?.trim();
    if (avatar == null || avatar.isEmpty) return null;
    // A picture only by the name of the one it has.
    if (isAvatarImage(avatar)) return avatar == had ? avatar : null;
    return avatar;
  }

  static const _extensions = {
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/webp': '.webp',
    'image/gif': '.gif',
  };

  /// [bot]'s picture, if it has one there.
  BotAvatarImage? avatarImage(Bot bot) {
    final file = bot.avatarFile;
    if (file == null) return null;
    final bytes = folders.readFile(file);
    if (bytes == null) return null;
    final type = switch (p.extension(file).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/png',
    };
    return (bytes: bytes, type: type);
  }

  String _newId() {
    final now = _clock().microsecondsSinceEpoch.toRadixString(36);
    var id = 'b$now';
    for (var n = 2; byId(id) != null; n++) {
      id = 'b$now-$n';
    }
    return id;
  }

  /// Deletes [id]'s bot, its conversation and memory: not the assistant's.
  void delete(String id) {
    final bot = byId(id);
    if (bot == null) return;
    if (bot.assistant) throw StateError('The assistant stays');
    workspace.deleteAll([
      for (final thread in workspace.threads)
        if (thread.project.path == bot.folder) thread,
    ]);
    folders.delete(bot.folder);
    _bots.remove(bot);
    _pacers.remove(id);
    _laters.remove(id);
    _seen.remove(id);
    _save();
    notifyListeners();
  }

  /// [bot] runs on [model] from now on: picked on its conversation, for
  /// the next it starts to run on it too.
  void setModel(Bot bot, String model) {
    final index = _bots.indexWhere((b) => b.id == bot.id);
    if (index < 0 || _bots[index].model == model) return;
    _bots[index] = _bots[index].copyWith(model: model);
    _save();
    notifyListeners();
  }

  /// The model [bot]'s conversation runs on, as the picker names it.
  String? modelOf(Bot bot) {
    final thread = threadOf(bot);
    if (thread != null && thread.isOpen) {
      if (thread.session.models?.selected case final model?) {
        return model.label;
      }
    }
    return bot.model;
  }

  String memory(Bot bot) => folders.readMemory(bot.folder);

  void setMemory(Bot bot, String text) {
    folders.writeMemory(bot.folder, text.trim().isEmpty ? '' : text);
    _restart(bot);
    notifyListeners();
  }

  // --- Writing first ------------------------------------------------------

  /// What changed for the agents the sidebar lists, told the bots that
  /// write first.
  void _watch() {
    _follow();
    final gone = {..._statuses.keys};
    final events = <BotEvent>[];
    for (final thread in workspace.threads) {
      if (thread.archived || isBotThread(thread)) continue;
      if (!workspace.listsInSidebar(thread)) continue;
      gone.remove(thread);
      final now = thread.status;
      final was = _statuses[thread];
      _statuses[thread] = now;
      if (now == ThreadStatus.running) {
        _runningSince[thread] ??= _clock();
      } else {
        _runningSince.remove(thread);
        _toldRunning.remove(thread);
      }
      if (was == null || was == now) continue;
      final kind = switch ((was, now)) {
        (_, ThreadStatus.needsInput) => BotEventKind.waiting,
        (ThreadStatus.running, ThreadStatus.idle || ThreadStatus.unread)
            when _failed(thread) =>
          BotEventKind.failed,
        (ThreadStatus.running, ThreadStatus.idle || ThreadStatus.unread) =>
          BotEventKind.done,
        _ => null,
      };
      if (kind == null) continue;
      events.add(
        _event(
          thread,
          kind,
          detail: kind == BotEventKind.failed ? _error(thread) : null,
        ),
      );
    }
    for (final thread in gone) {
      _statuses.remove(thread);
      _runningSince.remove(thread);
      _toldRunning.remove(thread);
    }
    _tell(events);
    _checkRunning();
  }

  BotEvent _event(AgentThread thread, BotEventKind kind, {String? detail}) =>
      BotEvent(
        chat: BotTools.idOf(thread),
        title: thread.title,
        project: thread.project.name,
        kind: kind,
        at: _clock(),
        detail: detail,
      );

  /// Follows each bot's conversation open: tells, as it changes, when a
  /// message comes or it starts or stops writing ([typing]).
  void _follow() {
    for (final bot in _bots) {
      final thread = threadOf(bot);
      if (thread == null || !thread.isOpen) continue;
      final session = thread.session;
      if (_followed.containsKey(session)) continue;
      Object? was;
      void listener() {
        final last = session.itemCount - 1;
        final now = (
          session.itemCount,
          session.isStreaming,
          last >= 0 && session.itemAt(last) is AssistantTextItem,
        );
        if (now == was) return;
        was = now;
        notifyListeners();
      }

      _followed[session] = listener;
      session.addListener(listener);
    }
  }

  /// [events] for the bots that write first, to tell when it is time.
  void _tell(List<BotEvent> events) {
    if (events.isEmpty) return;
    for (final bot in _bots) {
      if (!bot.can(BotAbility.proactive) || bot.proactive.perDay <= 0) {
        continue;
      }
      final pacer = _pacers[bot.id] ??= BotPacer();
      events.forEach(pacer.add);
    }
    _schedule();
  }

  /// The agents at work for [longRun] and more, told of once a run; and
  /// a look again when the next of them will be.
  @visibleForTesting
  void checkRunning() => _checkRunning();

  void _checkRunning() {
    _runningTimer?.cancel();
    _runningTimer = null;
    final now = _clock();
    final events = <BotEvent>[];
    DateTime? next;
    for (final MapEntry(key: thread, value: since) in _runningSince.entries) {
      if (_toldRunning.contains(thread)) continue;
      final due = since.add(longRun);
      if (!due.isAfter(now)) {
        _toldRunning.add(thread);
        events.add(
          _event(
            thread,
            BotEventKind.running,
            detail:
                'running for ${(now.difference(since).inSeconds / 60).round()} min',
          ),
        );
      } else if (next == null || due.isBefore(next)) {
        next = due;
      }
    }
    _tell(events);
    if (next != null) {
      _runningTimer = Timer(next.difference(now), _checkRunning);
    }
  }

  bool isBotThread(AgentThread thread) => botAt(thread.project.path) != null;

  static bool _failed(AgentThread thread) => _error(thread) != null;

  static String? _error(AgentThread thread) {
    if (!thread.isOpen) return null;
    final session = thread.session;
    for (var i = session.itemCount - 1; i >= 0; i--) {
      switch (session.itemAt(i)) {
        case NoticeItem(kind: NoticeKind.error, :final text):
          return text.split('\n').first;
        case UserMessageItem() || AssistantTextItem():
          return null;
        default:
      }
    }
    return null;
  }

  /// [bot] comes back, on its own, to [note] [after] from now (out of
  /// its quiet hours): when.
  DateTime later(Bot bot, Duration after, String note) {
    final at = BotPacer.outOfQuiet(bot.proactive, _clock().add(after));
    final laters = _laters[bot.id] ??= [];
    laters
      ..add(BotLater(at: at, note: note.trim()))
      ..sort((a, b) => a.at.compareTo(b.at));
    // The latest dropped, past the most it may have.
    if (laters.length > maxLaters) laters.removeRange(maxLaters, laters.length);
    _save();
    _schedule();
    return at;
  }

  /// What [bot] meant to come back to, soonest first.
  List<BotLater> laters(Bot bot) => List.unmodifiable(_laters[bot.id] ?? []);

  /// Whether [bot] writes first: of the agents, and of what it meant to.
  static bool _writesFirst(Bot bot) =>
      bot.can(BotAbility.proactive) && bot.proactive.perDay > 0;

  void _schedule() {
    _timer?.cancel();
    final now = _clock();
    DateTime? next;
    for (final bot in _bots) {
      var due = _pacers[bot.id]?.dueAt(bot.proactive, now);
      if (_laters[bot.id]?.firstOrNull case final later?
          when _writesFirst(bot)) {
        final at = BotPacer.outOfQuiet(bot.proactive, later.at);
        if (due == null || at.isBefore(due)) due = at.isBefore(now) ? now : at;
      }
      if (due != null && (next == null || due.isBefore(next))) next = due;
    }
    if (next == null) return;
    _timer = Timer(next.difference(now), deliver);
  }

  /// Tells each bot what is due: a message of the app's in its
  /// conversation, which it answers as it writes first.
  @visibleForTesting
  void deliver() {
    final now = _clock();
    var busy = false;
    for (final bot in _bots) {
      final pacer = _pacers[bot.id];
      final waiting = _laters[bot.id] ?? const <BotLater>[];
      if (pacer == null && waiting.isEmpty) continue;
      final thread = threadFor(bot);
      // Not while it is answering: after.
      if (thread.isOpen && thread.session.isStreaming) {
        busy = true;
        continue;
      }
      final events = pacer?.take(bot.proactive, now) ?? const <BotEvent>[];
      final due = _writesFirst(bot)
          ? [
              for (final later in waiting)
                if (!BotPacer.outOfQuiet(bot.proactive, later.at).isAfter(now))
                  later,
            ]
          : const <BotLater>[];
      if (events.isEmpty && due.isEmpty) continue;
      if (due.isNotEmpty) {
        waiting.removeWhere(due.contains);
        _save();
      }
      thread.session.send(
        ComposerMessage(
          text: botEventMessage(botWakeText(now, events: events, laters: due)),
        ),
      );
    }
    if (busy || _pacers.values.any((p) => p.hasPending)) {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 30), _schedule);
    } else {
      _schedule();
    }
  }
}
