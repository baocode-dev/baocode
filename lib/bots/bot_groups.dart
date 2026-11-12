import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bao_link/bao_link.dart'
    show
        LinkGroupMessage,
        linkGroupApp,
        linkGroupLeastPasses,
        linkGroupPasses,
        linkGroupUser;
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
/// Who speaks when, as a relay: one at a time holds the group's
/// conversation, and passes it on as it sees fit.
/// - The user speaks: it goes to whom they called on (@), else to the bot
///   that spoke there last, else to one picked at random.
/// - The one who has it is told the latest messages ([recent], each cut at
///   [longest]) and says what it will, if anything; then passes it on
///   (`<bot_next>`), or keeps it, and it stops. It goes [passes] times at
///   most after the user spoke.
/// - One it goes to that cannot take it (at work elsewhere, its turn
///   failed, or not done in [stuck]) has it go to another who is free,
///   told why. The user speaking while one is at work on it here: once it
///   is done, it goes as when they spoke.
class BotGroups extends ChangeNotifier {
  BotGroups(this.bots, {Random? random}) : random = random ?? Random();

  final Bots bots;

  /// What picks who starts, with no one to start; other under test.
  Random random;

  /// How many times the conversation may be passed after the user spoke.
  static const passes = linkGroupPasses;

  /// What a group of no bound may be passed on: more than any will.
  static const unbounded = 1 << 30;

  /// How many of the latest messages the one who has it is told; how long
  /// each may be, past it cut.
  static const recent = 20;
  static const longest = 500;

  /// How long one may take over its turn before it goes to another.
  Duration stuck = const Duration(minutes: 3);

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
    for (final MapEntry(key: session, value: listener) in _followed.entries) {
      session.removeListener(listener);
    }
    _followed.clear();
    for (final room in _rooms.values) {
      room.stuck?.cancel();
      room.waiting?.cancel();
    }
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
  /// they sent; a bot's messages, its narration in italics; the app's
  /// line in brackets. What a message quotes, a line before it.
  List<String> _lines(BotGroup group, LinkGroupMessage message) => [
    if (message.mine) ...[
      if (message.ref case final ref?) _quote(group, ref),
      ...message.text.split('\n'),
    ] else if (message.notice)
      '(${message.text})'
    else
      for (final (:tag, :text, :ref) in ChatCodec.botPartsOf(message.text))
        if (tag == ChatCodec.botNarrateTag)
          '*${ChatCodec.withoutVoiceCues(text).trim()}*'
        else if (tag == ChatCodec.botSayTag) ...[
          if (ref != null) _quote(group, ref),
          ChatCodec.withoutVoiceCues(text).trim(),
        ],
    for (final image in message.images)
      '![picture](${p.join(_folderOf(group.id), 'images', image)})',
  ];

  /// The line before a message quoting [group]'s message [seq]: whose it
  /// is and how it starts.
  String _quote(BotGroup group, int seq) {
    final quoted = _message(group.id, seq);
    if (quoted == null) return '> re #$seq';
    final text = quotedText(
      quoted,
      picture: bots.chinese ? '[图片]' : '[picture]',
    );
    final cut = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    return '> re #$seq · ${_nameOf(quoted.from, group)}: $cut';
  }

  /// What of [message] shows quoted: its words (a bot's messages, else its
  /// narration), on one line; else that it is a [picture].
  static String quotedText(LinkGroupMessage message, {String picture = ''}) {
    final words = message.mine || message.notice
        ? message.text
        : [
            for (final (tag, text) in ChatCodec.botParts(message.text))
              if (tag == ChatCodec.botSayTag) ChatCodec.withoutVoiceCues(text),
          ].join(' ');
    final line = words.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isNotEmpty) return line;
    return message.images.isNotEmpty ? picture : '';
  }

  /// [group]'s [seq]th message, if it has it.
  LinkGroupMessage? _message(String group, int seq) =>
      (_messages[group] ?? const <LinkGroupMessage>[])
          .where((m) => m.seq == seq)
          .firstOrNull;

  static String botTimeOf(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// Who [from] is, by name: the user, a bot, or one gone from the group,
  /// by the name it had there.
  String _nameOf(String from, [BotGroup? group]) => switch (from) {
    linkGroupUser =>
      bots.me.name.isEmpty ? (bots.chinese ? '用户' : 'User') : bots.me.name,
    linkGroupApp => bots.chinese ? '群通知' : 'Notice',
    _ => bots.byId(from)?.name ?? group?.names[from] ?? from,
  };

  // --- The groups -------------------------------------------------------

  BotGroup? byId(String id) => _groups.where((g) => g.id == id).firstOrNull;

  List<LinkGroupMessage> messages(String group) =>
      List.unmodifiable(_messages[group] ?? const <LinkGroupMessage>[]);

  /// [id]'s group changed as given, or a new one (no [id]): of the bots
  /// [members] names, those there are; its conversation passed on at most
  /// [passes] times (0, unbounded; none, as it was), each bot handed it
  /// waiting [gap] seconds before it answers. Who joined or left, and a
  /// new name, said in it, as done [by] (a bot's id; none, the user).
  BotGroup save({
    String? id,
    required String name,
    required List<String> members,
    int? passes,
    String? rules,
    int? gap,
    String by = linkGroupUser,
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
    if (passes != null && passes != 0) {
      passes = passes.clamp(linkGroupLeastPasses, 1 << 20);
    }
    if (gap != null && gap < 0) gap = 0;
    final BotGroup group;
    final List<String> joined;
    final List<String> left;
    String? renamed;
    var rulesChanged = false;
    if (id == null) {
      group = BotGroup(
        id: _newId(),
        name: name,
        members: kept,
        created: bots.now,
        names: names,
        passes: passes ?? linkGroupPasses,
        rules: rules?.trim() ?? '',
        gap: gap ?? 0,
      );
      _groups.add(group);
      _messages[group.id] = [];
      // The user knows whom they asked in; whom a bot did, said.
      (joined, left) = (
        by == linkGroupUser ? const <String>[] : kept,
        const [],
      );
    } else {
      final at = _groups.indexWhere((g) => g.id == id);
      if (at < 0) throw StateError('No group $id');
      final had = _groups[at];
      group = _groups[at] = had.copyWith(
        name: name,
        members: kept,
        names: {...had.names, ...names},
        passes: passes,
        rules: rules?.trim(),
        gap: gap,
      );
      if (rules != null && rules.trim() != had.rules) rulesChanged = true;
      joined = [
        for (final m in kept)
          if (!had.members.contains(m)) m,
      ];
      left = [
        for (final m in had.members)
          if (!kept.contains(m)) m,
      ];
      if (had.name != name) renamed = name;
      for (final gone in left) {
        _leave(group.id, gone);
      }
    }
    for (final notice in _notices(
      group,
      by,
      joined,
      left,
      renamed,
      rulesChanged: rulesChanged,
    )) {
      _add(
        group,
        LinkGroupMessage(
          seq: _nextSeq(group.id),
          at: bots.now,
          from: linkGroupApp,
          text: notice,
        ),
      );
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

  /// What is said in [group] of who [by] had join it ([joined]) or leave
  /// it ([left]), and of its new name ([renamed]): in the user's language.
  List<String> _notices(
    BotGroup group,
    String by,
    List<String> joined,
    List<String> left,
    String? renamed, {
    bool rulesChanged = false,
  }) {
    final who = _nameOf(by, group);
    String list(List<String> ids) =>
        [for (final id in ids) _nameOf(id, group)]
            .join(bots.chinese ? '、' : ', ');
    final zh = bots.chinese;
    return [
      if (joined.isNotEmpty)
        zh
            ? '$who 邀请 ${list(joined)} 加入了群聊'
            : '$who added ${list(joined)} to the group',
      if (left.isNotEmpty)
        zh
            ? '$who 将 ${list(left)} 移出了群聊'
            : '$who removed ${list(left)} from the group',
      if (renamed != null)
        zh ? '$who 修改群名为「$renamed」' : '$who renamed the group "$renamed"',
      if (rulesChanged) zh ? '$who 修改了群规' : '$who changed the group rules',
    ];
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
    _rooms.remove(id);
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
      for (final (:tag, :text, :ref) in ChatCodec.botPartsOf(texts.join('\n')))
        if ((tag == ChatCodec.botSayTag || tag == ChatCodec.botNarrateTag) &&
            text.trim().isNotEmpty)
          '<$tag${ref != null && tag == ChatCodec.botSayTag ? ' ${ChatCodec.botRefAttribute}="$ref"' : ''}>'
              '${text.trim()}</$tag>',
    ].join();
  }

  /// Whether a bot's turn at [group] in its conversation's [items] failed:
  /// an error, or the API's.
  @visibleForTesting
  static bool failedIn(List<ChatItem> items, String group) {
    final from = items.lastIndexWhere(
      (item) => item is UserMessageItem && ChatCodec.botGroupOf(item) == group,
    );
    if (from < 0) return false;
    for (
      var i = from + 1;
      i < items.length && items[i] is! UserMessageItem;
      i++
    ) {
      switch (items[i]) {
        case NoticeItem(kind: NoticeKind.error):
          return true;
        case AssistantTextItem(:final text)
            when text.trimLeft().startsWith('API Error'):
          return true;
        default:
      }
    }
    return false;
  }

  /// Whom a bot's conversation's [items] passed [group]'s conversation to
  /// in its turn there ([replyTo]'s), by name: the last it named.
  @visibleForTesting
  static String? nextTo(List<ChatItem> items, String group) {
    final places = ChatCodec.botPlaces(items);
    final from = items.lastIndexWhere(
      (item) => item is UserMessageItem && ChatCodec.botGroupOf(item) == group,
    );
    if (from < 0) return null;
    String? next;
    for (
      var i = from + 1;
      i < items.length && items[i] is! UserMessageItem;
      i++
    ) {
      if (places[i] != group) continue;
      if (items[i] case AssistantTextItem(:final text)) {
        next = ChatCodec.botNext(text) ?? next;
      }
    }
    return next;
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
    int? ref,
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
      ref: ref != null && ref < seq ? ref : null,
    );
    _add(found, message);
    _seen[group] = seq;
    bots.heardUser();
    _heard(found, message);
    return seq;
  }

  /// The user's [message] to [group]: the conversation theirs again,
  /// given on to whom it goes ([_firstOf]); once the one at work on it now
  /// is done, if one is.
  void _heard(BotGroup group, LinkGroupMessage message) {
    final room = _room(group.id);
    if (room.holder case final holder? when _answering[holder] == group.id) {
      room.again = true;
      return;
    }
    _start(group, message);
  }

  /// [message], the user's, starts the relay again: given to whom it calls
  /// on, else the bot that spoke last, else one at random.
  void _start(BotGroup group, LinkGroupMessage message) {
    final members = [
      for (final id in group.members)
        if (bots.byId(id) != null) id,
    ];
    if (members.isEmpty) return;
    final called = _called(message.text, members);
    final quoted = switch (message.ref) {
      final ref? => _message(group.id, ref)?.from,
      null => null,
    };
    final last = (_messages[group.id] ?? const <LinkGroupMessage>[])
        .lastWhere(
          (m) => members.contains(m.from),
          orElse: () =>
              LinkGroupMessage(seq: 0, at: DateTime(0), from: linkGroupUser),
        )
        .from;
    final (first, by) = switch ((called, last)) {
      (final called?, _) => (called, _By.called),
      _ when quoted != null && members.contains(quoted) => (quoted, _By.quoted),
      (null, final last) when last != linkGroupUser => (last, _By.last),
      _ => (members[random.nextInt(members.length)], _By.picked),
    };
    _room(group.id).left = group.passes == 0 ? unbounded : group.passes;
    _give(group, first, by: by);
  }

  /// The first of [members] [text] calls on (@its name), if it does.
  String? _called(String text, List<String> members) {
    String? first;
    var at = -1;
    for (final id in members) {
      final name = bots.byId(id)?.name;
      if (name == null) continue;
      final found = text.indexOf('@$name');
      if (found >= 0 && (at < 0 || found < at)) {
        (first, at) = (id, found);
      }
    }
    return first;
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

  // --- The relay ------------------------------------------------------------

  /// Who has [group]'s conversation now, if anyone, and how many times it
  /// may still be passed; whether it waits for them to be done elsewhere.
  ({String? holder, int left, bool waiting}) relay(String group) {
    final room = _rooms[group];
    final holder = room?.holder;
    return (
      holder: holder,
      left: room?.left ?? 0,
      waiting: holder != null && _answering[holder] != group,
    );
  }

  /// [member] has [group]'s conversation, as [by] has it: told now, or
  /// once it is done elsewhere.
  /// Handed it by another, [member] is told after the group's
  /// [BotGroup.gap]: the user speaking meanwhile, it goes as they say.
  void _give(BotGroup group, String member, {required _By by, String? from}) {
    final room = _room(group.id)
      ..holder = member
      ..by = by
      ..from = from;
    room.waiting?.cancel();
    room.waiting = null;
    notifyListeners();
    if (by == _By.passed && group.gap > 0) {
      room.waiting = Timer(Duration(seconds: group.gap), () {
        room.waiting = null;
        _wake(group.id, member);
      });
      return;
    }
    _wake(group.id, member);
  }

  /// [member], who has [group]'s conversation, told of it: the latest
  /// messages, whose turn it is. Later, if it is at work.
  void _wake(String group, String member) {
    final found = byId(group);
    final bot = bots.byId(member);
    final room = _rooms[group];
    if (found == null ||
        bot == null ||
        room == null ||
        room.holder != member ||
        !found.members.contains(member)) {
      return;
    }
    final session = tell == null ? _sessionOf(bot) : null;
    // At work, here or elsewhere, or about to be: another has it.
    if (_busy(member, session) case final busy?) {
      return _instead(found, member, 'is $busy');
    }
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    final told = (room.told[member] ?? 0).clamp(0, messages.length);
    final chat = _chat(found);
    final total = chat.text.split('\n').length;
    final shown = messages.skip(
      messages.length > recent ? messages.length - recent : 0,
    );
    final looked = room.looked[member];
    room.told[member] = messages.length;
    room.looked[member] = bots.now;
    _answering[member] = group;
    _answeringSince[member] = bots.now;
    room.stuck?.cancel();
    room.stuck = Timer(stuck, () {
      room.stuck = null;
      if (room.holder == member && _answering[member] == group) {
        _instead(
          found,
          member,
          'did not answer in ${stuck.inMinutes > 0 ? '${stuck.inMinutes} minutes' : '${stuck.inSeconds} seconds'}',
        );
      }
    });
    notifyListeners();
    final user = _nameOf(linkGroupUser);
    final note = botGroupTurn(
      group: found,
      chat: chatFile(group),
      me: bot.name,
      members: [
        for (final id in found.members)
          if (id != member) ?bots.byId(id)?.name,
      ],
      user: user,
      now: botTimeOf(bots.now),
      looked: looked == null ? null : botTimeOf(looked),
      messages: [
        for (final message in shown)
          () {
            final from = chat.lines[message.seq] ?? 1;
            final to = (chat.lines[message.seq + 1] ?? total) - 1;
            return (
              heading:
                  '#${message.seq} · ${_nameOf(message.from, found)} · '
                  '${botTimeOf(message.at)}',
              lines: _lines(found, message),
              lineRange: (from, to),
              fresh: messages.indexOf(message) >= told,
            );
          }(),
      ],
      longest: longest,
      by: switch (room.by) {
        _By.called => '$user called on you (@)',
        _By.quoted => '$user answered your message (quoted it)',
        _By.last => '$user spoke, and you were the last to speak here',
        _By.picked => '$user spoke, and no one here has yet: you start',
        _By.passed =>
          '${_nameOf(room.from ?? '', found)} handed the conversation to you',
        _By.instead => '${room.instead}; so it is yours',
        _By.missed => room.instead,
      },
      left: room.left,
      chinese: bots.chinese,
    );
    if (tell case final tell?) return tell(group, member, note);
    session!.send(ComposerMessage(text: botEventMessage(note)));
  }

  /// The group [member] is answering now, if it is.
  String? answering(String member) => _answering[member];

  /// Where [member] is at work, if it is, or about to be: none if free.
  String? _busy(String member, [ChatSession? session]) {
    final other = _answering[member];
    final since = _answeringSince[member];
    final where = other == null
        ? 'busy in their chat with ${_nameOf(linkGroupUser)}'
        : 'busy in "${byId(other)?.name ?? other}"';
    if (session != null && (session.isStreaming || !session.canSend)) {
      return where;
    }
    if (other != null && since != null && bots.now.difference(since) < _lost) {
      return where;
    }
    return null;
  }

  /// [member] cannot take [group]'s conversation ([why]): it goes to one
  /// of the others who is free, not the one who passed it if another is,
  /// told why; to no one, with none free or no passes left.
  void _instead(BotGroup group, String member, String why) {
    final room = _room(group.id);
    if (room.holder != member) return;
    room
      ..holder = null
      ..stuck?.cancel()
      ..stuck = null;
    final who = _nameOf(member, group);
    final meant = switch (room.by) {
      _By.called => '${_nameOf(linkGroupUser)} called on $who',
      _By.passed => '${_nameOf(room.from ?? '', group)} passed it to $who',
      _ => 'it was $who\'s turn',
    };
    final free = [
      for (final id in group.members)
        if (id != member && bots.byId(id) != null)
          if (_busy(id, tell == null ? _sessionOf(bots.byId(id)!) : null) ==
              null)
            id,
    ];
    final others = [
      for (final id in free)
        if (id != room.from) id,
    ];
    final pick = others.isNotEmpty ? others : free;
    if (pick.isEmpty || room.left <= 0) return notifyListeners();
    room
      ..left -= 1
      ..instead = '$meant, but $who $why';
    _give(
      group,
      pick[random.nextInt(pick.length)],
      by: _By.instead,
      from: room.from,
    );
  }

  /// [member] says [text] to [group], of itself (not answering it): a bot's
  /// message, there for whoever has the conversation next. Not the group
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
    return message;
  }

  /// Under test: where what a bot is told goes, in place of its
  /// conversation.
  @visibleForTesting
  void Function(String group, String member, String note)? tell;

  /// [member]'s turn in [group] done: what it said sent to the group, if
  /// anything; the conversation passed to [next] (a name), if it named one
  /// of the others and it may still go; else it stops. The user having
  /// spoken meanwhile, it goes as when they spoke.
  @visibleForTesting
  void turnEnded(
    String group,
    String member,
    String reply, {
    List<ImageAttachment> images = const [],
    String? next,
    bool failed = false,
  }) {
    final found = byId(group);
    if (found == null || !found.members.contains(member)) return;
    final room = _room(group);
    if (room.holder == member) {
      room.stuck?.cancel();
      room.stuck = null;
    }
    if (_answering[member] == group) _answering.remove(member);
    // With those it sent from files or the web meanwhile.
    images = [...images, ...?_webPictures.remove(member)];
    if (reply.isNotEmpty || images.isNotEmpty) {
      final seq = _nextSeq(group);
      _add(
        found,
        LinkGroupMessage(
          seq: seq,
          at: bots.now,
          from: member,
          text: reply,
          images: _keepImages(group, seq, images),
        ),
      );
    }
    if (room.holder == member && failed && !room.again) {
      _instead(found, member, 'ran into an error');
    } else if (room.holder == member) {
      room.holder = null;
      final named = next?.trim().replaceFirst(RegExp('^@'), '') ?? '';
      final to = named.isEmpty ? null : _memberNamed(found, member, named);
      // Whom it named not there (not the user, nor itself): it picks
      // again, told who is.
      final missed =
          to == null &&
          named.isNotEmpty &&
          !_sameName(named, _nameOf(linkGroupUser)) &&
          !_sameName(named, _nameOf(member, found));
      if (room.again) {
        room.again = false;
        final said = (_messages[group] ?? const <LinkGroupMessage>[]).lastWhere(
          (m) => m.mine,
          orElse: () => _none,
        );
        if (said != _none) _start(found, said);
      } else if (to != null && room.left > 0) {
        room.left -= 1;
        _give(found, to, by: _By.passed, from: member);
      } else if (missed && room.left > 0) {
        room.left -= 1;
        final others = [
          for (final id in found.members)
            if (id != member) _nameOf(id, found),
        ];
        room.instead =
            'you wrote <${ChatCodec.botNextTag}>$named</${ChatCodec.botNextTag}>, '
            'but there is no $named in this group, so it reached no one. '
            'You have spoken already: say nothing more unless you want to. '
            'Hand it to one of ${others.join(', ')} if they should answer '
            'now, or to no one';
        _give(found, member, by: _By.missed, from: member);
      }
    }
    notifyListeners();
    _caughtUp(member);
  }

  /// The member of [group] other than [member] that [name] names: by its
  /// name; else by it without what is in brackets ("小包" for "小包（私人
  /// 助理）"), or as the start of one name only.
  String? _memberNamed(BotGroup group, String member, String name) {
    final others = [
      for (final id in group.members)
        if (id != member) (id: id, name: _nameOf(id, group)),
    ];
    for (final other in others) {
      if (other.name == name) return other.id;
    }
    final bare = [
      for (final other in others)
        if (_sameName(other.name, name)) other.id,
    ];
    if (bare.length == 1) return bare.single;
    final starting = [
      for (final other in others)
        if (other.name.startsWith(name) || name.startsWith(other.name))
          other.id,
    ];
    return starting.length == 1 ? starting.single : null;
  }

  /// Whether [a] and [b] are one name, what is in brackets aside.
  static bool _sameName(String a, String b) => _bare(a) == _bare(b);

  static String _bare(String name) =>
      name.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '').trim();

  static final _none = LinkGroupMessage(
    seq: 0,
    at: DateTime(0),
    from: linkGroupUser,
  );

  /// [member]'s turn done: its reply to the group it was told of, if it
  /// was, and whom it passed the conversation to; then a group's it has
  /// that waited for it, told it.
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
        next: nextTo(items, group),
        failed: failedIn(items, group),
      );
    }
    _caughtUp(member);
  }

  /// [member] free: told of a group's conversation it has, that waited;
  /// not before its time ([_Room.waiting]).
  void _caughtUp(String member) {
    for (final group in [..._groups]) {
      if (_answering.containsKey(member)) return;
      final room = _rooms[group.id];
      if (room?.holder == member && room?.waiting == null) {
        _wake(group.id, member);
      }
    }
  }
}

/// How one came to have a group's conversation.
enum _By {
  called,
  quoted,
  last,
  picked,
  passed,
  instead,

  /// Its own again: whom it named is not in the group ([_Room.instead]).
  missed,
}

/// Where a group's conversation is: who has it, and what each was told.
class _Room {
  /// Who has it, how it came to them ([from]: who passed it), and how many
  /// times it may still be passed.
  String? holder;
  _By by = _By.picked;
  String? from;
  int left = 0;

  /// The user spoke while the one who has it was at work on it.
  bool again = false;

  /// Why it went to whom it did, not to whom it was meant for.
  String instead = '';

  /// Past it, the one who has it took too long: another has it.
  Timer? stuck;

  /// Till it, the one who has it waits ([BotGroup.gap]) before it is told.
  Timer? waiting;

  /// How many of the messages each was shown as new.
  final Map<String, int> told = {};

  /// When each last looked at the group, this run.
  final Map<String, DateTime> looked = {};

  void forget(String member) {
    told.remove(member);
    looked.remove(member);
    if (holder == member) {
      holder = null;
      stuck?.cancel();
      waiting?.cancel();
    }
  }
}
