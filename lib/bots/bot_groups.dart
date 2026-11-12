import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bao_link/bao_link.dart'
    show LinkGroup, LinkGroupMessage, linkGroupUser;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../link/chat_codec.dart';
import '../workspace/workspace.dart';
import 'bot.dart';
import 'bot_group_prompt.dart';
import 'bot_life.dart';
import 'bot_prompt.dart' show botEventMessage;
import 'bots.dart';

/// The user's group chats with their bots: each its messages, kept on the
/// computer as they are said (`groups/<id>/messages.jsonl`), and as the
/// bots read them (`chat.md`). A bot has one conversation, its chat with
/// the user's: it is told there of what is new in a group, with the new
/// messages, and reads the chat as it needs; what it says after, till the
/// user writes to it, is the group's ([ChatCodec.botPlaces]). What it
/// hears and says in each, its timeline keeps ([BotLife]); and the world
/// they share is the bots' WORLD.md.
///
/// Who is told when, as people in a group chat go, by how much each of
/// its bots attends to it ([attention]): from 0 to 1, fading by half each
/// [halfLife], with what it came of. No one decides it: it is worked out
/// of what happens, as it happens.
/// - Each message pulls those who did not say it, as warm as it is: the
///   user's 1; a bot's its group's [BotGroup.lively] times the warmest of
///   what it answered. Their attention comes up to that, less for one that
///   kept quiet (by half for each time running), or overheard (the user
///   called on others).
/// - Pulled, one looks at the group in a while ([glance] at full
///   attention; [glanceSpan] times longer at none), and reads all that is
///   new since; called on (@), at once. At work, here or elsewhere: once
///   it is done.
/// - What is too faint ([faint]) pulls no one: it is read when one next
///   looks. So bots answering bots fade out, in a livelier group later.
class BotGroups extends ChangeNotifier {
  BotGroups(
    this.bots, {
    this.glance = const Duration(seconds: 2),
    this.glanceSpan = 900,
    this.halfLife = const Duration(minutes: 3),
    this.faint = 0.1,
    Random? random,
  }) : random = random ?? Random();

  final Bots bots;

  /// As the class says; other under test.
  Duration glance;
  double glanceSpan;
  Duration halfLife;
  double faint;

  /// How long one looks after, about: from half to one and a half of it;
  /// as worked out, without one.
  Random? random;

  /// How lively a group is at first, and the most and least it may be.
  static const livelyAtFirst = 0.6;
  static const livelyLeast = LinkGroup.livelyLeast;
  static const livelyMost = LinkGroup.livelyMost;

  /// How much what the user said to others pulls the rest.
  static const overheard = 0.5;

  Workspace get _workspace => bots.workspace;

  /// The folder of the groups', in the bots'.
  static const folder = 'groups';

  List<BotGroup> _groups = [];
  List<BotGroup> get groups => List.unmodifiable(_groups);

  final Map<String, List<LinkGroupMessage>> _messages = {};
  final Map<String, _Room> _rooms = {};

  /// The last of each group's messages the user has seen, by its id.
  final Map<String, int> _seen = {};

  /// The members' conversations followed.
  final Map<ChatSession, VoidCallback> _followed = {};

  /// The group each bot was told of last, while it has not answered it;
  /// and since when.
  final Map<String, String> _answering = {};
  final Map<String, DateTime> _answeringSince = {};

  /// How long a bot told of a group, but not at work on it, is waited for
  /// before it is told of another: its turn never came (not sent).
  static const _lost = Duration(seconds: 30);

  /// WORLD.md as last written.
  String? _world;

  /// What the user says to everyone in a group: each of them called on.
  static final rollCall = RegExp(
    r'每个人|每一个人|所有人|你们每|everyone|every one of you|all of you',
    caseSensitive: false,
  );

  bool _started = false;
  bool _disposed = false;

  String? get _root => switch (bots.folders.root) {
    final root? => p.join(root, folder),
    null => null,
  };

  String _folderOf(String group) => p.join(_root!, group);

  /// Where [group]'s chat is, as its bots read it.
  String chatFile(String group) => p.join(_folderOf(group), 'chat.md');

  /// Where [bot] had a conversation of [group]'s, before its groups came
  /// to its one conversation: gone as the app starts.
  static String memberFolder(Bot bot, String group) =>
      p.join(bot.folder, folder, group);

  /// The group whose conversation, a bot's of before, is in [cwd].
  static String? groupAt(String cwd) =>
      p.basename(p.dirname(cwd)) == folder ? p.basename(cwd) : null;

  void start() {
    final root = _root;
    if (root == null || _started) return;
    _started = true;
    _groups = [
      for (final json in _readJson(p.join(root, 'groups.json')))
        if (json case final Map<String, Object?> map) BotGroup.fromJson(map),
    ];
    for (final group in _groups) {
      final messages = _messages[group.id] = [
        for (final line in _readText(
          p.join(_folderOf(group.id), 'messages.jsonl'),
        ).split('\n'))
          if (line.trim().isNotEmpty)
            LinkGroupMessage.fromJson(jsonDecode(line) as Map<String, Object?>),
      ];
      final room = _room(group.id);
      // What came before this run, theirs to read: not told again.
      for (final member in group.members) {
        room.told[member] = messages.length;
      }
      _seen[group.id] = messages.lastOrNull?.seq ?? 0;
    }
    // The conversations each bot had of its groups, before: its one now.
    for (final group in _groups) {
      for (final member in group.members) {
        if (bots.byId(member) case final bot?) _dropOld(bot, group.id);
      }
    }
    bots.addListener(_botsChanged);
    _writeWorld();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) bots.removeListener(_botsChanged);
    for (final room in _rooms.values) {
      room.cancel();
    }
    for (final MapEntry(key: session, value: listener) in _followed.entries) {
      session.removeListener(listener);
    }
    _followed.clear();
    super.dispose();
  }

  // --- Its files --------------------------------------------------------

  String _readText(String path) => switch (bots.folders.readFile(path)) {
    final bytes? => utf8.decode(bytes, allowMalformed: true),
    null => '',
  };

  List<Object?> _readJson(String path) {
    final text = _readText(path);
    if (text.trim().isEmpty) return const [];
    try {
      return jsonDecode(text) as List<Object?>;
    } on FormatException {
      return const [];
    }
  }

  void _write(String path, String text) =>
      bots.folders.writeFile(path, Uint8List.fromList(utf8.encode(text)));

  void _saveGroups() => _write(
    p.join(_root!, 'groups.json'),
    '${const JsonEncoder.withIndent('  ').convert([for (final group in _groups) group.toJson()])}\n',
  );

  /// [group]'s messages kept, and its chat as its bots read it.
  void _saveMessages(BotGroup group) {
    final messages = _messages[group.id] ?? const [];
    _write(
      p.join(_folderOf(group.id), 'messages.jsonl'),
      [for (final message in messages) '${jsonEncode(message.toJson())}\n']
          .join(),
    );
    _write(chatFile(group.id), _chat(group).text);
  }

  /// [group]'s chat as its bots read it, and the line each message starts
  /// at, by its number.
  ({String text, Map<int, int> lines}) _chat(BotGroup group) {
    final out = <String>['# ${group.name}', ''];
    final lines = <int, int>{};
    for (final message in _messages[group.id] ?? const <LinkGroupMessage>[]) {
      lines[message.seq] = out.length + 1;
      out
        ..add(
          '## #${message.seq} · ${_nameOf(message.from, group)} · ${botTimeOf(message.at)}',
        )
        ..addAll(_lines(group, message))
        ..add('');
    }
    return (text: out.join('\n'), lines: lines);
  }

  /// [message] as the bots read it: what the user wrote and the pictures
  /// they sent; a bot's messages, its narration in italics.
  List<String> _lines(BotGroup group, LinkGroupMessage message) => [
    if (message.mine)
      ...message.text.split('\n')
    else
      for (final (tag, text) in ChatCodec.botParts(message.text))
        if (tag == ChatCodec.botNarrateTag)
          '*${ChatCodec.withoutVoiceCues(text).trim()}*'
        else if (tag == ChatCodec.botSayTag)
          ChatCodec.withoutVoiceCues(text).trim(),
    for (final image in message.images)
      '![picture](${p.join(_folderOf(group.id), 'images', image)})',
  ];

  static String botTimeOf(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  /// Who [from] is, by name: the user, a bot, or one gone from the group,
  /// by the name it had there.
  String _nameOf(String from, [BotGroup? group]) => from == linkGroupUser
      ? (bots.me.name.isEmpty ? (bots.chinese ? '用户' : 'User') : bots.me.name)
      : bots.byId(from)?.name ?? group?.names[from] ?? from;

  // --- The groups -------------------------------------------------------

  BotGroup? byId(String id) => _groups.where((g) => g.id == id).firstOrNull;

  List<LinkGroupMessage> messages(String group) =>
      List.unmodifiable(_messages[group] ?? const <LinkGroupMessage>[]);

  /// [id]'s group changed as given, or a new one (no [id]): of the bots
  /// [members] names, those there are.
  BotGroup save({
    String? id,
    required String name,
    required List<String> members,
  }) {
    if (_root == null) throw StateError('No bots here');
    final kept = [
      for (final member in {...members})
        if (bots.byId(member) != null) member,
    ];
    name = name.trim();
    if (name.isEmpty) {
      name = [for (final m in kept) bots.byId(m)!.name].join('、');
    }
    final names = {for (final member in kept) member: bots.byId(member)!.name};
    final BotGroup group;
    if (id == null) {
      group = BotGroup(
        id: _newId(),
        name: name,
        members: kept,
        created: bots.now,
        names: names,
      );
      _groups.add(group);
      _messages[group.id] = [];
    } else {
      final at = _groups.indexWhere((g) => g.id == id);
      if (at < 0) throw StateError('No group $id');
      final had = _groups[at];
      group = _groups[at] = had.copyWith(
        name: name,
        members: kept,
        names: {...had.names, ...names},
      );
      for (final gone in had.members.where((m) => !kept.contains(m))) {
        _leave(group.id, gone);
      }
    }
    final room = _room(group.id);
    final count = _messages[group.id]!.length;
    for (final member in kept) {
      room.told.putIfAbsent(member, () => count);
    }
    _saveGroups();
    _saveMessages(group);
    _writeWorld();
    notifyListeners();
    return group;
  }

  String _newId() {
    final now = bots.now.microsecondsSinceEpoch.toRadixString(36);
    var id = 'g$now';
    for (var n = 2; byId(id) != null; n++) {
      id = 'g$now-$n';
    }
    return id;
  }

  /// Deletes [id]'s group: its messages, and its bots' conversations of it.
  void delete(String id) {
    final group = byId(id);
    if (group == null) return;
    for (final member in group.members) {
      _leave(id, member);
    }
    _rooms.remove(id)?.cancel();
    _groups.removeWhere((g) => g.id == id);
    _messages.remove(id);
    _seen.remove(id);
    bots.folders.delete(_folderOf(id));
    _saveGroups();
    _writeWorld();
    notifyListeners();
  }

  /// [member] out of [group]: not told of it any more.
  void _leave(String group, String member) {
    _rooms[group]?.forget(member);
    if (_answering[member] == group) _answering.remove(member);
    final bot = bots.byId(member);
    if (bot != null) _dropOld(bot, group);
  }

  /// [bot]'s conversation of [group] from before, gone, if it had one.
  void _dropOld(Bot bot, String group) {
    final path = memberFolder(bot, group);
    final threads = [
      for (final thread in _workspace.threads)
        if (thread.project.path == path) thread,
    ];
    for (final thread in threads) {
      if (thread.isOpen) {
        final session = thread.session;
        if (_followed.remove(session) case final listener?) {
          session.removeListener(listener);
        }
      }
    }
    if (threads.isNotEmpty) _workspace.deleteAll(threads);
    bots.folders.delete(path);
    unawaited(bots.forgetSessions(path));
  }

  /// The bots gone: out of their groups, their names kept for what they
  /// said there. The world as it is now.
  void _botsChanged() {
    _writeWorld();
    var changed = false;
    for (final (at, group) in _groups.indexed.toList()) {
      final names = {
        ...group.names,
        for (final member in group.members)
          if (bots.byId(member) case final bot?) member: bot.name,
      };
      if (!mapEquals(names, group.names)) {
        _groups[at] = group.copyWith(names: names);
        changed = true;
      }
    }
    for (final (at, group) in _groups.indexed.toList()) {
      final kept = [
        for (final member in group.members)
          if (bots.byId(member) != null) member,
      ];
      if (kept.length == group.members.length) continue;
      _groups[at] = group.copyWith(members: kept);
      _answering.removeWhere(
        (member, id) => id == group.id && !kept.contains(member),
      );
      for (final gone in group.members.where((m) => !kept.contains(m))) {
        _rooms[group.id]?.forget(gone);
      }
      changed = true;
    }
    if (!changed) return;
    _saveGroups();
    notifyListeners();
  }

  /// The user's messages of [group] since they last read it.
  int unread(String group) {
    final seen = _seen[group] ?? 0;
    return [
      for (final message in _messages[group] ?? const <LinkGroupMessage>[])
        if (message.seq > seen && !message.mine) message,
    ].length;
  }

  /// The user has read all [group] said.
  void seen(String group) {
    final last = _messages[group]?.lastOrNull?.seq ?? 0;
    if (_seen[group] == last) return;
    _seen[group] = last;
    notifyListeners();
  }

  /// Those of [group]'s bots at work on it now: whatever comes of it, as
  /// it is.
  List<String> typing(String group) {
    final found = byId(group);
    if (found == null) return const [];
    return [
      for (final member in found.members)
        if (bots.byId(member) case final bot?)
          if (_answering[member] == group)
            if (bots.threadOf(bot) case final thread?)
              if (thread.isOpen && thread.session.isStreaming) member,
    ];
  }

  // --- Its bots' conversations -----------------------------------------

  /// [bot]'s conversation, followed: the one it has.
  ChatSession _sessionOf(Bot bot) {
    final session = bots.threadFor(bot).session;
    _follow(bot.id, session);
    return session;
  }

  /// [member]'s conversation followed: the end of a turn it was told of a
  /// group in is its reply there, or its keeping quiet; what came while it
  /// was at work, told it after; and while it is at work on a group, it
  /// is typing there.
  void _follow(String member, ChatSession session) {
    if (_followed.containsKey(session)) return;
    var streaming = session.isStreaming;
    var typing = false;
    void listener() {
      if (streaming && !session.isStreaming) {
        scheduleMicrotask(() => _turnEnded(member, session));
      }
      streaming = session.isStreaming;
      final now = streaming && _answering[member] != null;
      if (now != typing) {
        typing = now;
        notifyListeners();
      }
    }

    _followed[session] = listener;
    session.addListener(listener);
  }

  /// What a bot's conversation's [items] said to [group] last: its
  /// messages and narration after the group's last note to it, till the
  /// user wrote to it, in their tags; empty for nothing.
  @visibleForTesting
  static String replyTo(List<ChatItem> items, String group) {
    final places = ChatCodec.botPlaces(items);
    final from = items.lastIndexWhere(
      (item) => item is UserMessageItem && ChatCodec.botGroupOf(item) == group,
    );
    if (from < 0) return '';
    // Till what it heard next; what it sent the user meanwhile, not.
    final texts = [
      for (
        var i = from + 1;
        i < items.length && items[i] is! UserMessageItem;
        i++
      )
        if (places[i] == group)
          if (items[i] case AssistantTextItem(:final text)) text,
    ];
    return [
      for (final (tag, text) in ChatCodec.botParts(texts.join('\n')))
        if ((tag == ChatCodec.botSayTag || tag == ChatCodec.botNarrateTag) &&
            text.trim().isNotEmpty)
          '<$tag>${text.trim()}</$tag>',
    ].join();
  }

  /// The pictures a bot's conversation's [items] made for [group] in its
  /// turn there ([replyTo]'s): an image model's, as they came.
  @visibleForTesting
  static List<ImageAttachment> picturesTo(List<ChatItem> items, String group) {
    final places = ChatCodec.botPlaces(items);
    final from = items.lastIndexWhere(
      (item) => item is UserMessageItem && ChatCodec.botGroupOf(item) == group,
    );
    if (from < 0) return const [];
    return [
      for (
        var i = from + 1;
        i < items.length && items[i] is! UserMessageItem;
        i++
      )
        if (places[i] == group)
          if (items[i]
              case ToolCallItem(
                kind: ToolKind.image,
                :final images,
                :final status,
              )
              when status != ToolStatus.failed)
            ...images,
    ];
  }

  // --- The world ----------------------------------------------------------

  /// The bots' WORLD.md, written if it changed: who the user is, everyone,
  /// the groups.
  void _writeWorld() {
    final root = bots.folders.root;
    if (root == null || !_started) return;
    final text = botWorld(
      user: _nameOf(linkGroupUser),
      bots: bots.bots,
      groups: [
        for (final group in _groups) (group: group, chat: chatFile(group.id)),
      ],
    );
    if (text == _world) return;
    _world = text;
    _write(p.join(root, BotLife.world), text);
  }

  // --- What is said ------------------------------------------------------

  _Room _room(String group) => _rooms[group] ??= _Room();

  /// The user's [text] (and [images], as files' bytes) to [group]: its
  /// number.
  int send(
    String group, {
    required String text,
    List<ImageAttachment> images = const [],
  }) {
    final found = byId(group);
    if (found == null) throw StateError('No group $group');
    final seq = _nextSeq(group);
    final names = _keepImages(group, seq, images);
    final message = LinkGroupMessage(
      seq: seq,
      at: bots.now,
      from: linkGroupUser,
      text: text.trim(),
      images: names,
    );
    _add(found, message);
    _seen[group] = seq;
    bots.heardUser();
    _pull(found, message, 1);
    return seq;
  }

  static const _extensions = {
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/webp': '.webp',
    'image/gif': '.gif',
  };

  /// [group]'s picture [name]: its bytes and media type.
  ({Uint8List bytes, String type})? image(String group, String name) {
    if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
      return null;
    }
    final bytes = bots.folders.readFile(
      p.join(_folderOf(group), 'images', name),
    );
    if (bytes == null) return null;
    final type =
        _extensions.entries
            .where((e) => name.endsWith(e.value))
            .firstOrNull
            ?.key ??
        'image/png';
    return (bytes: bytes, type: type);
  }

  int _nextSeq(String group) => (_messages[group]?.lastOrNull?.seq ?? 0) + 1;

  /// [images], of message [seq] of [group], kept in its folder: their
  /// names there.
  List<String> _keepImages(
    String group,
    int seq,
    List<ImageAttachment> images,
  ) => [
    for (final (n, image) in images.indexed)
      () {
        final name = '$seq-${n + 1}${_extensions[image.mediaType] ?? '.png'}';
        bots.folders.writeFile(
          p.join(_folderOf(group), 'images', name),
          image.bytes,
        );
        return name;
      }(),
  ];

  /// Pictures a bot sent in its turn at a group, from the web
  /// ([ChatCodec.botImageTool]) or its files: to go with its reply, by its
  /// id.
  final Map<String, List<ImageAttachment>> _webPictures = {};

  /// [member] sent [picture] in its turn at the group it is answering: it
  /// goes with its reply.
  void sentPicture(String member, ImageAttachment picture) =>
      (_webPictures[member] ??= []).add(picture);

  void _add(BotGroup group, LinkGroupMessage message) {
    (_messages[group.id] ??= []).add(message);
    _saveMessages(group);
    _live(group, message);
    notifyListeners();
  }

  /// [message] in the timeline of each of [group]'s bots: heard, or said.
  void _live(BotGroup group, LinkGroupMessage message) {
    final text = message.mine
        ? [
            message.text,
            if (message.images.isNotEmpty) bots.chinese ? '[图片]' : '[picture]',
          ].where((t) => t.trim().isNotEmpty).join(' ')
        : BotLife.saysOf(message.text);
    for (final member in group.members) {
      final bot = bots.byId(member);
      if (bot == null) continue;
      bots.live(
        bot,
        place: '${bots.chinese ? '群' : 'group'}·${group.name} #${message.seq}',
        who: _nameOf(message.from, group),
        text: text,
        mine: message.from == member,
      );
    }
  }

  // --- Attention ------------------------------------------------------------

  /// How lively [group] is: how warm what a bot says is of what it answers.
  void setLively(String group, double lively) {
    final at = _groups.indexWhere((g) => g.id == group);
    if (at < 0) throw StateError('No group $group');
    lively = lively.clamp(livelyLeast, livelyMost).toDouble();
    if (_groups[at].lively == lively) return;
    _groups[at] = _groups[at].copyWith(lively: lively);
    _saveGroups();
    notifyListeners();
  }

  /// How much each of [group]'s bots attends to it, as of [BotAttention.at]
  /// ([BotAttention.now] for now); when it looks next, if it will.
  List<BotAttention> attention(String group) {
    final found = byId(group);
    final room = _rooms[group];
    if (found == null) return const [];
    return [
      for (final member in found.members)
        if (bots.byId(member) != null)
          (room?.attention[member] ??
                  BotAttention(member: member, value: 0, at: bots.now))
              .copyWith(glance: room?.glances[member]?.at),
    ];
  }

  /// [member]'s attention to [room]'s group now: faded since.
  double _attentionOf(_Room room, String member) =>
      room.attention[member]?.now(bots.now, halfLife) ?? 0;

  /// [member]'s attention up to [value], if it is less now, for [why].
  void _attend(_Room room, String member, double value, String why) {
    if (value <= _attentionOf(room, member)) return;
    room.attention[member] = BotAttention(
      member: member,
      value: value,
      at: bots.now,
      why: why,
    );
  }

  /// How long one with [attention] takes to look at a group.
  Duration _glanceAfter(double attention) {
    final spread = switch (random) {
      final random? => 0.5 + random.nextDouble(),
      null => 1.0,
    };
    final ms =
        glance.inMilliseconds *
        pow(glanceSpan, 1 - attention.clamp(0, 1)) *
        spread;
    return Duration(milliseconds: ms.round());
  }

  /// Whether [text] calls on [member] (@its name).
  bool _calls(String text, String member) => switch (bots.byId(member)) {
    final bot? => text.contains('@${bot.name}'),
    null => false,
  };

  String _warmth(double warmth) => warmth.toStringAsFixed(2);

  /// [message], said in [group] as [warmth] as it is, pulls those who did
  /// not say it: each to look at the group in a while, or at once if
  /// called on; not one it would pull too faintly.
  void _pull(BotGroup group, LinkGroupMessage message, double warmth) {
    final room = _room(group.id);
    room.warmth[message.seq] = warmth;
    final zh = bots.chinese;
    final user = message.mine;
    final who = _nameOf(message.from, group);
    final words = message.text;
    final everyone = user && rollCall.hasMatch(words);
    final called = {
      for (final member in group.members)
        if (member != message.from && (everyone || _calls(words, member)))
          member,
    };
    final where = user
        ? '#${message.seq}'
        : '#${message.seq}${zh ? '，热度 ' : ', warmth '}${_warmth(warmth)}';
    for (final member in group.members) {
      if (member == message.from || bots.byId(member) == null) continue;
      final call = called.contains(member);
      var pull = warmth;
      var why = switch ((call, everyone, user && called.isNotEmpty)) {
        (true, true, _) =>
          zh ? '$who叫了所有人（$where）' : '$who asked everyone ($where)',
        (true, false, _) =>
          zh ? '被$who @（$where）' : 'called on by $who ($where)',
        (false, _, true) =>
          zh
              ? '旁听：$who @ 了别人（$where）'
              : 'overheard: $who called on others ($where)',
        _ => zh ? '$who说话了（$where）' : '$who spoke ($where)',
      };
      if (!call) {
        if (user && called.isNotEmpty) pull *= overheard;
        final passes = room.passes[member] ?? 0;
        if (passes > 0) {
          pull *= pow(0.5, passes);
          why += zh
              ? '，连续 $passes 次没说话，被吸引的程度 ×${_warmth(pow(0.5, passes).toDouble())}'
              : ', quiet $passes times running, pulled ×${_warmth(pow(0.5, passes).toDouble())}';
        }
      }
      if (pull < faint) continue;
      if (call) room.called.add(member);
      _attend(room, member, pull, why);
      _lookAt(
        group.id,
        member,
        call ? Duration.zero : _glanceAfter(_attentionOf(room, member)),
      );
    }
    notifyListeners();
  }

  /// [member] to look at [group] [after] from now, unless it will sooner.
  void _lookAt(String group, String member, Duration after) {
    final room = _room(group);
    final at = bots.now.add(after);
    if (room.glances[member] case final had? when !had.at.isAfter(at)) return;
    room.glances.remove(member)?.timer.cancel();
    room.glances[member] = (
      timer: Timer(after, () {
        room.glances.remove(member);
        _wake(group, member);
        notifyListeners();
      }),
      at: at,
    );
  }

  /// [member] told of what is new in [group], if there is: later, if it is
  /// at work.
  void _wake(String group, String member) {
    final found = byId(group);
    final bot = bots.byId(member);
    if (found == null || bot == null || !found.members.contains(member)) {
      return;
    }
    final room = _room(group);
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    final told = (room.told[member] ?? 0).clamp(0, messages.length);
    final unseen = [
      for (final message in messages.skip(told))
        if (message.from != member) message,
    ];
    if (unseen.isEmpty) return;
    final session = tell == null ? _sessionOf(bot) : null;
    // At work, here or elsewhere, or about to be: told once it is done.
    final other = _answering[member];
    final since = _answeringSince[member];
    if (session != null && (session.isStreaming || !session.canSend) ||
        other != null && since != null && bots.now.difference(since) < _lost) {
      room.dirty.add(member);
      return;
    }
    final chat = _chat(found);
    final first = unseen.first.seq;
    final last = unseen.last.seq;
    final end = chat.lines[last + 1] ?? chat.text.split('\n').length;
    room.told[member] = messages.length;
    // What it answers as warm as the warmest of what it reads.
    room.drive[member] = unseen
        .map((message) => room.warmth[message.seq] ?? 0)
        .fold(0.0, max);
    _answering[member] = group;
    _answeringSince[member] = bots.now;
    final note = botGroupWake(
      group: found,
      chat: chatFile(group),
      from: first,
      to: last,
      lines: (chat.lines[first] ?? 1, end - 1),
      messages: [
        for (final message in unseen)
          (
            heading:
                '#${message.seq} · ${_nameOf(message.from, found)} · ${botTimeOf(message.at)}',
            lines: _lines(found, message),
          ),
      ],
      members: [
        for (final id in found.members)
          if (id != member) ?bots.byId(id)?.name,
      ],
      user: _nameOf(linkGroupUser),
      called: room.called.remove(member),
    );
    if (tell case final tell?) return tell(group, member, note);
    session!.send(ComposerMessage(text: botEventMessage(note)));
  }

  /// The group [member] is answering now, if it is.
  String? answering(String member) => _answering[member];

  /// [member] says [text] to [group], of itself (not answering it): a bot's
  /// message, which the others hear as they would another's. Not the group
  /// it is answering: that is its reply's, in its turn.
  LinkGroupMessage say(
    String group,
    String member,
    String text, {
    List<ImageAttachment> images = const [],
  }) {
    final found = byId(group);
    if (found == null || !found.members.contains(member)) {
      throw StateError('Not in the group $group');
    }
    if (_answering[member] == group) {
      throw StateError(
        'You are answering this group now: say it in your reply, in '
        '<bot_say>, not with this tool.',
      );
    }
    final seq = _nextSeq(group);
    final message = LinkGroupMessage(
      seq: seq,
      at: bots.now,
      from: member,
      text: text.trim().isEmpty
          ? ''
          : '<${ChatCodec.botSayTag}>${text.trim()}</${ChatCodec.botSayTag}>',
      images: _keepImages(group, seq, images),
    );
    _add(found, message);
    _spoke(found, member, message, found.lively);
    return message;
  }

  /// [member] said [message] in [group], as warm as [warmth]: it attends
  /// to it as much, and the others are pulled. What came while it wrote,
  /// it has not read: a reply may cross another.
  void _spoke(
    BotGroup group,
    String member,
    LinkGroupMessage message,
    double warmth,
  ) {
    final room = _room(group.id)..passes.remove(member);
    _attend(
      room,
      member,
      warmth,
      bots.chinese ? '刚说过话（#${message.seq}）' : 'just spoke (#${message.seq})',
    );
    _pull(group, message, warmth);
  }

  /// Under test: where what a bot is told goes, in place of its
  /// conversation.
  @visibleForTesting
  void Function(String group, String member, String note)? tell;

  /// [member]'s turn in [group] done: what it said sent to the group, as
  /// it is; or it kept quiet, and attends to it the less.
  @visibleForTesting
  void turnEnded(
    String group,
    String member,
    String reply, {
    List<ImageAttachment> images = const [],
  }) {
    final found = byId(group);
    if (found == null || !found.members.contains(member)) return;
    final room = _room(group);
    if (_answering[member] == group) _answering.remove(member);
    final drive = room.drive.remove(member) ?? 0;
    // With those it sent from files or the web meanwhile.
    images = [...images, ...?_webPictures.remove(member)];
    if (reply.isEmpty && images.isEmpty) {
      final passes = room.passes[member] = (room.passes[member] ?? 0) + 1;
      room.attention[member] = BotAttention(
        member: member,
        value: _attentionOf(room, member) / 2,
        at: bots.now,
        why: bots.chinese
            ? '看了没说话（连续 $passes 次）'
            : 'read it and kept quiet ($passes times running)',
      );
      notifyListeners();
      return _caughtUp(member);
    }
    final seq = _nextSeq(group);
    final message = LinkGroupMessage(
      seq: seq,
      at: bots.now,
      from: member,
      text: reply,
      images: _keepImages(group, seq, images),
    );
    _add(found, message);
    _spoke(found, member, message, found.lively * drive);
    _caughtUp(member);
  }

  /// [member]'s turn done: its reply to the group it was told of, if it
  /// was; then the groups that went on meanwhile, told it.
  void _turnEnded(String member, ChatSession session) {
    if (_disposed || session.isStreaming) return;
    if (_answering[member] case final group?) {
      final items = [
        for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
      ];
      turnEnded(
        group,
        member,
        replyTo(items, group),
        images: picturesTo(items, group),
      );
    }
    _caughtUp(member);
  }

  /// [member] free: told of a group that went on while it was at work.
  void _caughtUp(String member) {
    for (final group in [..._groups]) {
      if (_answering.containsKey(member)) return;
      if (_rooms[group.id]?.dirty.remove(member) ?? false) {
        _wake(group.id, member);
      }
    }
  }
}

/// How much [member] attends to a group: [value] as of [at], fading by
/// half each [BotGroups.halfLife]; [why], what it came of; when it looks at
/// the group next ([glance]), if it will.
class BotAttention {
  const BotAttention({
    required this.member,
    required this.value,
    required this.at,
    this.why = '',
    this.glance,
  });

  final String member;
  final double value;
  final DateTime at;
  final String why;
  final DateTime? glance;

  /// As of [time]: faded since [at].
  double now(DateTime time, Duration halfLife) {
    final since = time.difference(at).inMilliseconds;
    if (since <= 0 || halfLife <= Duration.zero) return value;
    return value * pow(0.5, since / halfLife.inMilliseconds);
  }

  BotAttention copyWith({DateTime? glance}) => BotAttention(
    member: member,
    value: value,
    at: at,
    why: why,
    glance: glance,
  );
}

/// Where a group is at: what its bots were told, and how much they attend
/// to it.
class _Room {
  /// How many of the messages each bot was told of.
  final Map<String, int> told = {};

  /// How much each attends to the group, and why.
  final Map<String, BotAttention> attention = {};

  /// How many times running each kept quiet.
  final Map<String, int> passes = {};

  /// When each is to look at the group.
  final Map<String, ({Timer timer, DateTime at})> glances = {};

  /// Those with something new while at work: told once done.
  final Set<String> dirty = {};

  /// Those called on (@), till they are told.
  final Set<String> called = {};

  /// How warm each message of this run was, by its number.
  final Map<int, double> warmth = {};

  /// How warm what each answers now was: the warmest it read.
  final Map<String, double> drive = {};

  void cancel() {
    for (final glance in glances.values) {
      glance.timer.cancel();
    }
    glances.clear();
  }

  void forget(String member) {
    glances.remove(member)?.timer.cancel();
    told.remove(member);
    attention.remove(member);
    passes.remove(member);
    dirty.remove(member);
    called.remove(member);
    drive.remove(member);
  }
}
