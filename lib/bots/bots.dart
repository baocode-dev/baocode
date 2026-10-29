import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import '../link/link_platform.dart';
import '../workspace/preference_store.dart';
import '../workspace/workspace.dart';
import 'bot.dart';
import 'bot_files.dart';
import 'bot_folders.dart';
import 'bot_pacer.dart';
import 'bot_permissions.dart';
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
    Future<String?> Function()? computer,
  }) : folders = folders ?? BotFolders.data(),
       _clock = clock ?? DateTime.now,
       _computerName = computer ?? _thisComputer;

  final Workspace workspace;
  final BotFolders folders;

  /// Where what the app keeps of them besides their files is: the agents
  /// each is told of.
  final PreferenceStore? store;
  final DateTime Function() _clock;

  /// Whether the assistant made at first is named and told in Chinese.
  final bool chinese;

  /// How long an agent runs before the bots are told it does.
  final Duration longRun;

  final Future<String?> Function() _computerName;

  /// The computer the bots live on, as the user named it: for them to know.
  String? computer;

  /// Whether a phone is paired: the bots are the phone's, and with none
  /// they are told of nothing nor come back to anything (each a turn of
  /// the model's, paid for), until one is ([phonesChanged]). Unset, one is.
  bool Function()? hasPhone;

  bool get _hasPhone => hasPhone?.call() ?? true;

  /// A phone was paired or unpaired: what is due, delivered, or held.
  void phonesChanged() {
    if (_started && !_disposed) _schedule();
  }

  static Future<String?> _thisComputer() async =>
      (await LinkPlatform.current()?.device())?.name;

  /// The settings its agent runs with: full access, nothing asked (see
  /// [BotPermissions]); and works as an agent, not in Plan.
  static const settings = {'mode': 'agent', 'permission': 'bypassPermissions'};

  List<Bot> _bots = [];
  List<Bot> get bots => List.unmodifiable(_bots);

  final Map<String, BotPacer> _pacers = {};
  Timer? _timer;

  /// The most a bot may have waiting to come back to.
  static const maxLaters = 5;

  /// The agents each bot started or wrote to, by its id: those it is
  /// told of, the assistant aside (told of all).
  final Map<String, List<String>> _watching = {};

  /// The most agents a bot is told of for having started or written to.
  static const maxWatching = 40;

  /// Who the user is, as they put it on their phone.
  BotUser _me = const BotUser();

  /// The bots to start again once they stop answering: changed meanwhile.
  final Set<String> _restartWhenIdle = {};

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
    try {
      computer = await _computerName();
    } on Object catch (error) {
      debugPrint('bots: no computer name: $error');
    }
    final kept = await store?.read() ?? const {};
    if (kept['watching'] case final Map<String, Object?> watching) {
      for (final MapEntry(:key, :value) in watching.entries) {
        _watching[key] = [
          for (final id in value is List ? value : const []) ?id as String?,
        ];
      }
    }
    _me = _readMe();
    _bots = _readBots();
    if (!_bots.any((bot) => bot.assistant)) {
      _bots.insert(0, _newAssistant(root));
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

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
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
      'watching': {
        for (final MapEntry(:key, :value) in _watching.entries)
          if (value.isNotEmpty) key: value,
      },
    }),
  );

  // --- Their files ------------------------------------------------------

  String _readText(String path) => switch (folders.readFile(path)) {
    final bytes? => utf8.decode(bytes, allowMalformed: true),
    null => '',
  };

  /// [text] at [path], a line's end last, as text files have; none for
  /// nothing.
  void _writeText(String path, String text) {
    if (text.trim().isEmpty) {
      folders.deleteFile(path);
    } else {
      final lines = '${text.trimRight()}\n';
      folders.writeFile(path, Uint8List.fromList(utf8.encode(lines)));
    }
  }

  /// The bots their folders hold, the assistant first, then as they were
  /// made.
  List<Bot> _readBots() {
    final bots = [for (final folder in folders.folders()) ?_readBot(folder)];
    final assistant = bots.where((bot) => bot.assistant).firstOrNull;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [
      ?assistant,
      ...bots.where((bot) => bot != assistant).toList()
        ..sort((a, b) => (a.created ?? epoch).compareTo(b.created ?? epoch)),
    ];
  }

  Bot? _readBot(String folder) {
    final card = folders.readFile(p.join(folder, BotFiles.card));
    if (card == null) return null;
    return BotFiles.read(
      folder,
      utf8.decode(card, allowMalformed: true),
      style: _readText(p.join(folder, BotFiles.style)),
    );
  }

  void _writeBot(Bot bot) {
    folders.make(bot.folder);
    _writeText(p.join(bot.folder, BotFiles.card), BotFiles.cardText(bot));
    _writeText(
      p.join(bot.folder, BotFiles.style),
      bot.style.isEmpty ? '' : '${bot.style}\n',
    );
  }

  /// Whether [a] and [b] are the same as their files say.
  static bool _same(Bot a, Bot b) =>
      a.style == b.style && BotFiles.cardText(a) == BotFiles.cardText(b);

  BotUser _readMe() => switch (folders.root) {
    final root? => BotFiles.readUser(_readText(p.join(root, BotFiles.user))),
    null => const BotUser(),
  };

  /// The bots, and the user, as their files say now: what a bot changed
  /// itself ([by]), with Claude Code's tools, or the user by hand. A bot
  /// changed starts again on it, told (but by itself); one made is added;
  /// one whose folder is gone is gone, its conversation too (the
  /// assistant, as new). What a bot may do is the
  /// user's to set: as it was, a bot changing it. A picture file its card
  /// names (anywhere) is taken as its picture, cut square ([_takePicture]).
  void reload({Bot? by}) {
    final root = folders.root;
    if (root == null || !_started) return;
    var changed = false;
    final next = <Bot>[];
    final taking = <(String, String)>[];
    for (var bot in _readBots()) {
      final had = byId(bot.id);
      if (by != null) {
        final kept = Bot(
          id: bot.id,
          name: bot.name,
          folder: bot.folder,
          avatar: bot.avatar,
          gender: bot.gender,
          signature: bot.signature,
          identity: bot.identity,
          style: bot.style,
          abilities: had?.abilities ?? const {},
          model: bot.model,
          assistant: had?.assistant ?? false,
          created: bot.created ?? had?.created ?? _clock(),
        );
        if (!_same(kept, bot)) _writeBot(kept);
        bot = kept;
      }
      if (_pictureToTake(bot) case final path?) {
        // As it was, till the picture is taken.
        bot = bot.copyWith(
          avatar: had?.avatar,
          clearAvatar: had?.avatar == null,
        );
        _writeBot(bot);
        taking.add((bot.id, path));
      }
      next.add(bot);
      if (had == null) {
        changed = true;
        continue;
      }
      if (_same(had, bot)) continue;
      changed = true;
      _restart(bot);
      if (by?.id != bot.id) {
        _tellChanged(
          had,
          bot,
          had.avatar == bot.avatar ? null : avatarImage(bot),
          by: by,
        );
      }
    }
    for (final had in [..._bots]) {
      if (next.any((bot) => bot.id == had.id)) continue;
      _forget(had);
      changed = true;
      // The assistant's gone: as new, its conversation with it.
      if (had.assistant && !next.any((bot) => bot.assistant)) {
        next.insert(0, _newAssistant(root));
      }
    }
    final added = [
      for (final bot in next)
        if (byId(bot.id) == null) bot,
    ];
    _bots = next;
    added.forEach(threadFor);
    for (final (id, path) in taking) {
      unawaited(_takePicture(id, path, by: by));
    }
    final me = _readMe();
    if (me != _me) {
      _me = me;
      _bots.forEach(_restart);
      changed = true;
    }
    _schedule();
    if (changed) notifyListeners();
  }

  /// The picture file [bot]'s card names, to be taken as its picture: one
  /// not taken yet (not named as [_avatar] names them), in its folder or
  /// by its full path.
  static String? _pictureToTake(Bot bot) {
    final avatar = bot.avatar;
    if (avatar == null || !_pictureFile.hasMatch(avatar)) return null;
    if (_takenPicture.hasMatch(avatar)) return null;
    return p.isAbsolute(avatar) ? avatar : p.join(bot.folder, avatar);
  }

  static final _pictureFile = RegExp(
    r'\.(png|jpe?g|webp|gif)$',
    caseSensitive: false,
  );
  static final _takenPicture = RegExp(
    r'^avatar-[0-9a-f]{12}\.(png|jpg|webp|gif)$',
  );

  /// The picture at [path] as bot [id]'s, cut square and kept in its
  /// folder, by its name; the file it was gone, if one of its folder's. If
  /// it cannot be, the bot is told so.
  Future<void> _takePicture(String id, String path, {Bot? by}) async {
    BotAvatarImage? picture;
    Object? failed;
    try {
      final bytes =
          folders.readFile(path) ??
          (await File(path).exists() ? await File(path).readAsBytes() : null);
      if (bytes == null) throw StateError('there is no such file');
      picture = await BotTools.squarePicture(bytes);
    } on Object catch (error) {
      failed = error;
    }
    final bot = byId(id);
    if (bot == null || _disposed) return;
    if (picture == null) {
      _note(
        bot,
        'Your picture: $path could not be used ($failed). It is as it was.',
      );
      return;
    }
    save(
      id: bot.id,
      name: bot.name,
      gender: bot.gender,
      signature: bot.signature,
      identity: bot.identity,
      style: bot.style,
      abilities: bot.abilities,
      proactive: bot.proactive,
      avatarImage: picture,
      by: by,
    );
    if (p.isWithin(bot.folder, path)) folders.deleteFile(path);
  }

  /// Where the picture the user sent [bot] as `[Image #number]` is kept,
  /// from its folder: as PNG, for its tools to take.
  static String receivedPicture(int number) =>
      p.join('received', 'image-$number.png');

  Future<void> _keepReceived(Bot bot, ImageAttachment image) async {
    final number = image.number;
    if (number == null) return;
    try {
      final png = await BotTools.pngOf(image.bytes);
      folders.writeFile(p.join(bot.folder, receivedPicture(number)), png);
    } on Object catch (error) {
      debugPrint('bots: picture #$number not kept: $error');
    }
  }

  /// A note of the app's to [bot], in its conversation.
  void _note(Bot bot, String text, {List<ImageAttachment> images = const []}) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return;
    thread.session.send(
      ComposerMessage(text: botEventMessage(text), images: images),
    );
  }

  /// The assistant as the app starts it, in [root]: its files written.
  Bot _newAssistant(String root) {
    final defaults = assistantDefaults(chinese: chinese);
    final assistant = Bot(
      id: 'assistant',
      name: defaults.name,
      folder: p.join(root, 'assistant'),
      identity: defaults.identity,
      abilities: BotFiles.assistantAbilities,
      assistant: true,
      created: _clock(),
    );
    _writeBot(assistant);
    return assistant;
  }

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
          user: _me,
          memory: memory(bot),
          self: selfNotes(bot),
          computer: computer,
          now: _clock(),
          imageModel:
              ClaudeSdkTools.called(
                'mcp__${ClaudeSdkTools.server}__${ImageTools.name}',
              ) !=
              null,
        ),
        // Told only who it is and how it talks: no coding agent's prompt.
        ownPrompt: true,
        // Its own tools; the web's; the tool search, for the browser's,
        // which are deferred. All of it unasked: the user is on their
        // phone, not at the computer.
        tools: BotPermissions.tools(bot),
        approvesAll: true,
        // What the user writes while it talks, taken up as it does: as a
        // person hears what is said meanwhile; and shown where they wrote
        // it.
        queuedMessages: QueuedMessages.duringTurn,
        queuedInPlace: true,
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
    if (tool == ImageTools.name) return true;
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
    final thread =
        threadOf(bot) ??
        (() {
          folders.make(bot.folder);
          return workspace.startAgent(workspace.projectAt(bot.folder));
        })();
    // Followed from now: what is sent it, seen.
    thread.session;
    _follow();
    return thread;
  }

  /// Has [bot]'s agent start again on its conversation, to be told what
  /// changed (its identity, abilities, memory) from its next message.
  void _restart(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return;
    final session = thread.session;
    if (session.isStreaming) {
      // Once it is done answering.
      _restartWhenIdle.add(bot.id);
    } else if (session.sessionId != null) {
      session.restart();
    }
  }

  /// How many messages [bot] sent since the user last read it: each of
  /// its messages, stickers, cards and pictures, as a chat app counts.
  int unread(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return 0;
    final session = thread.session;
    final count = session.itemCount;
    final seen = (_seen[bot.id] ??= count).clamp(0, count);
    var unread = 0;
    for (var i = seen; i < count; i++) {
      unread += _shown(session.itemAt(i));
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

  /// How many of a bot's messages [item] shows as in its chat: those of its
  /// reply (see [ChatCodec.botSays]); what it sent with its tools.
  static int _shown(ChatItem item) => switch (item) {
    AssistantTextItem(:final text) => ChatCodec.botSays(text).length,
    _ => ChatCodec.botSent(item) ? 1 : 0,
  };

  /// Whether [bot] is writing to the user: at work.
  bool typing(Bot bot) => threadOf(bot)?.status == ThreadStatus.running;

  /// The last [bot] said: its first line; a picture or a sticker, as a
  /// chat app's list says it.
  String? lastLine(Bot bot) {
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return null;
    final session = thread.session;
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
        case AssistantTextItem(:final text):
          if (ChatCodec.botSays(text).lastOrNull case final said?) {
            if (firstLine(said) case final line?) return line;
          }
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
    Bot? by,
  }) {
    final root = folders.root;
    if (root == null) throw StateError('No bots here');
    name = name.trim();
    if (name.isEmpty) throw ArgumentError('A bot needs a name');
    final Bot bot;
    if (id == null) {
      final newId = _newId();
      final folder = p.join(root, newId);
      bot = Bot(
        id: newId,
        name: name,
        folder: folder,
        avatar: _avatar(folder, avatar, avatarImage),
        gender: gender.trim(),
        signature: signature.trim(),
        identity: identity.trim(),
        style: style.trim(),
        abilities: abilities,
        proactive: proactive,
        created: _clock(),
      );
      _writeBot(bot);
      _bots.add(bot);
      if (_started) threadFor(bot);
      notifyListeners();
      return bot;
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
    // What it was to be told, dropped with being told of the agents.
    if (had.can(BotAbility.proactive) && !bot.can(BotAbility.proactive)) {
      _pacers.remove(bot.id);
    }
    _writeBot(bot);
    _restart(bot);
    // Changed by itself, it knows.
    if (by?.id != bot.id) _tellChanged(had, bot, avatarImage, by: by);
    notifyListeners();
    return bot;
  }

  /// Tells [bot] what the user (or the bot [by]) changed of it ([had]
  /// before): who it is now, its new picture with it to see. Its to react
  /// to, or not.
  void _tellChanged(Bot had, Bot bot, BotAvatarImage? picture, {Bot? by}) {
    String quoted(String text) => text.isEmpty ? '(none)' : '"$text"';
    final lines = [
      if (had.name != bot.name) '- Your name: now ${quoted(bot.name)}.',
      if (picture != null)
        '- Your picture: a new one chosen for you, here. Look at '
            'it, and keep in a line what it shows '
            '(bot_remember, about self).'
      else if (had.avatar != bot.avatar)
        switch (bot.avatar) {
          null => "- Your picture: none now, your name's first letter.",
          final emoji => '- Your picture: now the emoji $emoji.',
        },
      if (had.gender != bot.gender) '- Your gender: now ${quoted(bot.gender)}.',
      if (had.signature != bot.signature)
        '- The line under your name: now ${quoted(bot.signature)}.',
      if (had.identity != bot.identity)
        '- Who you are, in their words, now:\n${bot.identity}',
      if (had.style != bot.style)
        '- How you talk, in their words, now:\n${bot.style}',
      for (final ability in BotAbility.values)
        if (bot.can(ability) != had.can(ability))
          '- ${bot.can(ability) ? 'You may now' : 'You may no longer'}: '
              '${ability.name}.',
    ];
    if (lines.isEmpty) return;
    final thread = threadOf(bot);
    if (thread == null || !thread.isOpen) return;
    thread.session.send(
      ComposerMessage(
        text: botEventMessage(
          [
            by == null
                ? 'The user changed your profile:'
                : '${by.name} (${by.assistant ? 'the assistant, who looks after '
                                "the user's contacts" : 'another contact'}) '
                      'changed your profile:',
            ...lines,
            'Now: ${botTime(_clock())}.',
          ].join('\n'),
        ),
        images: [
          if (picture != null)
            ImageAttachment(bytes: picture.bytes, mediaType: picture.type),
        ],
      ),
    );
  }

  /// What [bot] keeps of itself: what it said it likes, has done, thinks;
  /// to be the same one each time. Empty for nothing.
  String selfNotes(Bot bot) =>
      _readText(p.join(bot.folder, BotFiles.self)).trim();

  /// [bot]'s notes of itself now [text]: by itself, as it goes; else the
  /// user's, which it is told from its next message ([restart]).
  void setSelfNotes(Bot bot, String text, {bool restart = false}) {
    _writeText(p.join(bot.folder, BotFiles.self), text);
    if (!restart) return;
    _restart(bot);
    notifyListeners();
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
    return (bytes: bytes, type: _typeOf(file));
  }

  static String _typeOf(String file) =>
      switch (p.extension(file).toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp',
        '.gif' => 'image/gif',
        _ => 'image/png',
      };

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
    folders.delete(bot.folder);
    _forget(bot);
    notifyListeners();
  }

  /// [bot]'s conversation deleted, and a new one started: it chats again
  /// from nothing said, who it is and what it remembers (MEMORY.md,
  /// SELF.md) kept. What it meant to come back to, and was to be told of,
  /// was of that conversation: gone with it.
  void clearChat(Bot bot) {
    workspace.deleteAll([
      for (final thread in workspace.threads)
        if (thread.project.path == bot.folder) thread,
    ]);
    _followed.removeWhere((session, _) => !_sessionOf(session));
    _pacers.remove(bot.id);
    _restartWhenIdle.remove(bot.id);
    _seen.remove(bot.id);
    _writeLaters(bot, const []);
    threadFor(bot);
    _save();
    _schedule();
    notifyListeners();
  }

  /// Whether [session] is a bot's conversation's still.
  bool _sessionOf(ChatSession session) => workspace.threads.any(
    (thread) => thread.isOpen && identical(thread.session, session),
  );

  /// [bot], its folder gone: its conversation deleted, nothing kept of it.
  void _forget(Bot bot) {
    workspace.deleteAll([
      for (final thread in workspace.threads)
        if (thread.project.path == bot.folder) thread,
    ]);
    _bots.removeWhere((b) => b.id == bot.id);
    _pacers.remove(bot.id);
    _watching.remove(bot.id);
    _seen.remove(bot.id);
    _save();
  }

  /// [bot] runs on [model] from now on: picked on its conversation, for
  /// the next it starts to run on it too.
  void setModel(Bot bot, String model) {
    final index = _bots.indexWhere((b) => b.id == bot.id);
    if (index < 0 || _bots[index].model == model) return;
    _writeBot(_bots[index] = _bots[index].copyWith(model: model));
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

  String memory(Bot bot) =>
      _readText(p.join(bot.folder, BotFiles.memory)).trim();

  // --- The user ---------------------------------------------------------

  /// Who the user is, as they put it on their phone: for the bots to know.
  BotUser get me => _me;

  /// The user's own picture, as their phone sent it; none for none.
  BotAvatarImage? get myPicture {
    final root = folders.root;
    final file = _me.picture;
    if (root == null || file == null) return null;
    final bytes = folders.readFile(p.join(root, file));
    return bytes == null ? null : (bytes: bytes, type: _typeOf(file));
  }

  /// Who the user is now [me], their picture [picture] (none for none):
  /// told the bots from their next message, if it changed.
  void setMe(BotUser me, BotAvatarImage? picture) {
    final root = folders.root;
    if (root == null) return;
    String? file;
    if (picture != null) {
      final hash = sha1.convert(picture.bytes).toString().substring(0, 12);
      file = 'me-$hash${_extensions[picture.type] ?? '.png'}';
      if (file != _me.picture) {
        folders.writeFile(p.join(root, file), picture.bytes);
      }
    }
    final now = me.withPicture(file);
    if (now == _me) return;
    if (_me.picture case final old? when old != file) {
      folders.deleteFile(p.join(root, old));
    }
    _me = now;
    _writeText(p.join(root, BotFiles.user), BotFiles.userText(now));
    _bots.forEach(_restart);
    notifyListeners();
  }

  /// [bot]'s memory of the user now [text]: the user's, which it is told
  /// from its next message; else by itself, as it goes ([restart] false).
  void setMemory(Bot bot, String text, {bool restart = true}) {
    _writeText(p.join(bot.folder, BotFiles.memory), text);
    if (!restart) return;
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
      var streaming = session.isStreaming;
      // The pictures the user sent it, as files for its tools: by their
      // numbers, those it has had already not again.
      final received = <int>{
        for (var i = 0; i < session.itemCount; i++)
          if (session.itemAt(i) case UserMessageItem(:final images))
            for (final image in images) ?image.number,
      };
      var count = session.itemCount;
      void listener() {
        if (session.itemCount != count) {
          count = session.itemCount;
          // A message comes in near the end (before what it shows of the
          // turn), not always last.
          for (var i = math.max(0, count - 4); i < count; i++) {
            if (session.itemAt(i) case UserMessageItem(:final images)) {
              for (final image in images) {
                if (image.number case final number? when received.add(number)) {
                  unawaited(_keepReceived(bot, image));
                }
              }
            }
          }
        }
        // Its turn done: what it changed of its files, taken up.
        if (streaming && !session.isStreaming) {
          scheduleMicrotask(() => reload(by: byId(bot.id) ?? bot));
        }
        streaming = session.isStreaming;
        if (!session.isStreaming && _restartWhenIdle.remove(bot.id)) {
          // Not while its session tells of the turn's end.
          scheduleMicrotask(() => _restart(byId(bot.id) ?? bot));
        }
        final last = session.itemCount - 1;
        final now = (
          session.itemCount,
          session.isStreaming,
          // Each of its messages, as its reply's tags close.
          last >= 0 && session.itemAt(last) is AssistantTextItem
              ? ChatCodec.botSays(
                  (session.itemAt(last) as AssistantTextItem).text,
                ).length
              : null,
        );
        if (now == was) return;
        was = now;
        notifyListeners();
      }

      _followed[session] = listener;
      session.addListener(listener);
    }
  }

  /// [events] for the bots the user lets be told of the agents
  /// ([BotAbility.proactive], off at first: a turn of the model's each),
  /// to tell when it is time; none for the others, not even of the agents
  /// they started or wrote to (off is off), nor without a phone to write
  /// to.
  void _tell(List<BotEvent> events) {
    if (events.isEmpty || !_hasPhone) return;
    for (final bot in _bots) {
      if (!bot.can(BotAbility.proactive)) continue;
      final pacer = _pacers[bot.id] ??= BotPacer();
      events.forEach(pacer.add);
    }
    _schedule();
  }

  /// [bot] started [thread], or wrote to it: told what becomes of it.
  void watch(Bot bot, AgentThread thread) {
    final id = BotTools.idOf(thread);
    final watching = _watching[bot.id] ??= [];
    watching
      ..remove(id)
      ..add(id);
    if (watching.length > maxWatching) {
      watching.removeRange(0, watching.length - maxWatching);
    }
    _save();
  }

  /// The agents [bot] is told of for having started or written to them.
  List<String> watching(Bot bot) => List.unmodifiable(_watching[bot.id] ?? []);

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

  /// [bot] comes back, on its own, to [note] [after] from now: when.
  DateTime later(Bot bot, Duration after, String note) {
    // To the minute, as its file has it.
    final now = _clock().add(after);
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final laters = [...this.laters(bot), BotLater(at: at, note: note.trim())]
      ..sort((a, b) => a.at.compareTo(b.at));
    // The latest dropped, past the most it may have.
    if (laters.length > maxLaters) laters.removeRange(maxLaters, laters.length);
    _writeLaters(bot, laters);
    _schedule();
    return at;
  }

  /// What [bot] meant to come back to, soonest first: its LATER.md.
  List<BotLater> laters(Bot bot) =>
      BotFiles.readLaters(_readText(p.join(bot.folder, BotFiles.later)));

  void _writeLaters(Bot bot, List<BotLater> laters) => _writeText(
    p.join(bot.folder, BotFiles.later),
    BotFiles.laterText(laters),
  );

  /// [bot] no longer comes back to what its notes say [which] of (a part
  /// of one, any case): those it dropped.
  List<BotLater> cancelLaters(Bot bot, String which) {
    final part = which.trim().toLowerCase();
    final laters = this.laters(bot);
    if (part.isEmpty) return const [];
    final dropped = [
      for (final later in laters)
        if (later.note.toLowerCase().contains(part)) later,
    ];
    if (dropped.isEmpty) return const [];
    final path = p.join(bot.folder, BotFiles.later);
    _writeText(path, BotFiles.withoutLaters(_readText(path), dropped));
    _schedule();
    return dropped;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    // Held, with no phone to write to: until one is paired.
    if (!_hasPhone) return;
    final now = _clock();
    DateTime? next;
    for (final bot in _bots) {
      var due = _pacers[bot.id]?.dueAt(now);
      if (laters(bot).firstOrNull case final later?) {
        final at = later.at.isBefore(now) ? now : later.at;
        if (due == null || at.isBefore(due)) due = at;
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
    if (!_hasPhone) return;
    final now = _clock();
    var busy = false;
    for (final bot in _bots) {
      final pacer = _pacers[bot.id];
      final waiting = laters(bot);
      if (pacer == null && waiting.isEmpty) continue;
      final thread = threadFor(bot);
      // Not while it is answering: after.
      if (thread.isOpen && thread.session.isStreaming) {
        busy = true;
        continue;
      }
      final events = pacer?.take(now) ?? const <BotEvent>[];
      final due = [
        for (final later in waiting)
          if (!later.at.isAfter(now)) later,
      ];
      if (events.isEmpty && due.isEmpty) continue;
      if (due.isNotEmpty) {
        // Its lines taken out: what else it wrote there stays.
        final path = p.join(bot.folder, BotFiles.later);
        _writeText(path, BotFiles.withoutLaters(_readText(path), due));
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
