import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart' show LinkGroupMessage, linkGroupUser;
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
/// Who is told when, as people in a group chat go:
/// - What the user says is taken up once they stop for [quiet]: what they
///   say together is one.
/// - The bots are told one after another, [stagger] apart: those called
///   on (@name) first, then those named, the one the user answered, the
///   quietest. Each sees what those before it said, and mostly need not
///   say more.
/// - A reply is sent once the bot is done, as it is: if others spoke
///   meanwhile, they crossed, as messages do in any chat.
/// - Each thing the user says lets the bots say [budget] things at most
///   before it is theirs again: what a bot says tells the others, while
///   there is some left.
/// - One that kept quiet [lurk] times running is told every third time,
///   unless called on, till it speaks.
class BotGroups extends ChangeNotifier {
  BotGroups(
    this.bots, {
    this.quiet = const Duration(seconds: 2),
    this.stagger = const Duration(seconds: 3),
    this.budget = 4,
    this.lurk = 3,
  });

  final Bots bots;

  /// As the class says; shorter under test.
  Duration quiet;
  Duration stagger;
  int budget;
  int lurk;

  Workspace get _workspace => bots.workspace;

  /// The folder of the groups', in the bots'.
  static const folder = 'groups';

  List<BotGroup> _groups = [];
  List<BotGroup> get groups => List.unmodifiable(_groups);

  final Map<String, List<LinkGroupMessage>> _messages = {};
  final Map<String, _Round> _rounds = {};

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

  /// How many of each group's messages the world was told of.
  final Map<String, int> _worldTold = {};

  /// The most of a group's messages the world is told of at first.
  static const _worldFirst = 8;

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
      final round = _round(group.id);
      // What came before this run, theirs to read: not told again.
      for (final member in group.members) {
        round.told[member] = messages.length;
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
    for (final round in _rounds.values) {
      round.cancel();
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
    final round = _round(group.id);
    final count = _messages[group.id]!.length;
    for (final member in kept) {
      round.told.putIfAbsent(member, () => count);
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
    _rounds.remove(id)?.cancel();
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
    _rounds[group]?.forget(member);
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
        _rounds[group.id]?.forget(gone);
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
    // Changed this run: the world told to read it again.
    if (_world != null) bots.world.worldChanged();
    _world = text;
    _write(p.join(root, BotLife.world), text);
  }

  // --- What is said, and who is told -----------------------------------

  _Round _round(String group) => _rounds[group] ??= _Round();

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
    _add(
      found,
      LinkGroupMessage(
        seq: seq,
        at: bots.now,
        from: linkGroupUser,
        text: text.trim(),
        images: names,
      ),
    );
    _seen[group] = seq;
    final round = _round(group)
      ..left = budget
      ..number += 1
      ..cancelWaking()
      ..asked.write('\n$text');
    round.quiet?.cancel();
    round.quiet = Timer(quiet, () {
      round.quiet = null;
      final asked = round.asked.toString();
      round.asked.clear();
      _plan(found.id, said: asked, by: linkGroupUser, after: Duration.zero);
    });
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

  /// Who in [group] is told of what [by] [said], and when: the world's to
  /// say, while there is one ([BotWorld]), but for those the user called
  /// on, told at once; its own rules if it says nothing in time.
  void _plan(
    String group, {
    required String said,
    required String by,
    required Duration after,
  }) {
    final found = byId(group);
    if (found == null) return;
    final round = _round(group);
    if (round.left <= 0) return;
    final world = bots.world;
    if (by == linkGroupUser) world.heardUser();
    if (!world.on) return _planByRules(group, said: said, by: by, after: after);
    if (by == linkGroupUser) {
      // Asked of everyone: each told, one after another, as if called on;
      // the group's answers enough for all.
      final everyone = rollCall.hasMatch(said);
      if (everyone && round.left < found.members.length) {
        round.left = found.members.length;
      }
      var next = after;
      for (final id in found.members) {
        final bot = bots.byId(id);
        if (bot == null) continue;
        final named = said.contains('@${bot.name}');
        if (!named && !everyone) continue;
        if (named) round.called.add(id);
        wakeFor(
          group,
          id,
          after: next,
          why: named
              ? '${_nameOf(by)} called on you'
              : '${_nameOf(by)} asked everyone',
        );
        if (everyone) next += stagger;
      }
    }
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    // What is new to it since it was last told of the group, this run (the
    // latest few the first time): where it is in the chat's file, the
    // user's words themselves.
    final from = (_worldTold[group] ?? messages.length - _worldFirst).clamp(
      0,
      messages.length,
    );
    _worldTold[group] = messages.length;
    final news = messages.skip(from).toList();
    if (news.isNotEmpty) {
      final chat = _chat(found);
      final end = chat.lines[news.last.seq + 1] ?? chat.text.split('\n').length;
      final user = by == linkGroupUser;
      world.ask(
        group,
        said: user ? said.trim() : null,
        line:
            '- In "${found.name}" (group $group; its chat: ${chatFile(group)}, '
            'lines ${chat.lines[news.first.seq] ?? 1}–${end - 1}): '
            '${[for (final message in news) '#${message.seq} ${_nameOf(message.from, found)}'
                  '${user && message.mine ? ' (the words above)' : ''}'].join(', ')}.',
      );
    }
    round.fallback?.cancel();
    round.fallback = Timer(world.waitFor, () {
      round.fallback = null;
      _planByRules(group, said: said, by: by, after: Duration.zero);
    });
  }

  /// The world said what became of [groups]: their own rules not needed.
  void decided(Set<String> groups) {
    for (final group in groups) {
      final round = _rounds[group];
      round?.fallback?.cancel();
      round?.fallback = null;
    }
  }

  /// [member] of [group] told of what is new there [after] from now, as
  /// the world has it, for [why]: when it will be, or when it was to be
  /// [already]. Not while the group may hear no more from the bots
  /// ([StateError], saying why).
  ({DateTime at, bool already}) wakeFor(
    String group,
    String member, {
    Duration after = Duration.zero,
    String why = '',
  }) {
    final found = byId(group);
    if (found == null) throw StateError('No group $group.');
    if (!found.members.contains(member)) {
      throw StateError('${_nameOf(member)} is not in "${found.name}".');
    }
    final round = _round(group);
    if (round.waking[member] case final waking?) {
      return (at: waking.at, already: true);
    }
    if (round.left <= 0) {
      throw StateError(
        '"${found.name}" has had all its answers to the user\'s last '
        'message; no one more till they speak again.',
      );
    }
    round.waking[member] = (
      timer: Timer(after, () {
        round.waking.remove(member);
        _wake(group, member, why: why);
      }),
      at: bots.now.add(after),
      why: why,
    );
    return (at: round.waking[member]!.at, already: false);
  }

  /// Who in the groups is to be told of what is new there, and when.
  List<({BotGroup group, String member, DateTime at, String why})>
  get waiting => [
    for (final group in _groups)
      if (_rounds[group.id] case final round?)
        for (final MapEntry(key: member, :value) in round.waking.entries)
          (group: group, member: member, at: value.at, why: value.why),
  ];

  /// What the bots may still say in [group] before the user speaks again.
  int answersLeft(String group) => _rounds[group]?.left ?? 0;

  /// Wakes [group]'s bots one after another, from [after] on, for what
  /// [by] [said]: not [by], nor one already to be woken. The app's own
  /// rules, with no world to say.
  void _planByRules(
    String group, {
    required String said,
    required String by,
    required Duration after,
  }) {
    final found = byId(group);
    if (found == null) return;
    final round = _round(group);
    if (round.left <= 0) return;
    final members = [
      for (final id in found.members)
        if (id != by) ?bots.byId(id),
    ];
    bool calls(Bot bot) => said.contains('@${bot.name}');
    bool names(Bot bot) => said.contains(bot.name);
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    // When each last spoke: the one the user answers, the latest.
    int spoke(Bot bot) =>
        messages.lastIndexWhere((message) => message.from == bot.id);
    final answered = by == linkGroupUser
        ? messages
              .lastWhere(
                (m) => !m.mine,
                orElse: () => LinkGroupMessage(
                  seq: 0,
                  at: DateTime(0),
                  from: linkGroupUser,
                ),
              )
              .from
        : null;
    int rank(Bot bot) => calls(bot)
        ? 0
        : names(bot)
        ? 1
        : bot.id == answered
        ? 2
        : 3;
    final order = [...members]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        // The quietest first, so all have a say.
        return spoke(a).compareTo(spoke(b));
      });
    var next = 0;
    for (final bot in order) {
      final called = calls(bot);
      if (called) round.called.add(bot.id);
      if (round.waking.containsKey(bot.id)) continue;
      // Quiet a while: now and then, unless called on or named.
      if ((round.passes[bot.id] ?? 0) >= lurk && rank(bot) > 1) {
        // Of the user's words, every third; of the bots', none.
        final skipped = round.skipped[bot.id] ?? 0;
        if (by != linkGroupUser || skipped < 2) {
          if (by == linkGroupUser) round.skipped[bot.id] = skipped + 1;
          continue;
        }
        round.skipped.remove(bot.id);
      }
      final wait = after + stagger * next++;
      round.waking[bot.id] = (
        timer: Timer(wait, () {
          round.waking.remove(bot.id);
          _wake(group, bot.id);
        }),
        at: bots.now.add(wait),
        why: '',
      );
    }
  }

  /// [member] told of what is new in [group], if there is, and the group
  /// may still hear from the bots: later, if it is at work.
  void _wake(String group, String member, {String why = ''}) {
    final found = byId(group);
    final bot = bots.byId(member);
    if (found == null || bot == null || !found.members.contains(member)) {
      return;
    }
    final round = _round(group);
    if (round.left <= 0) return;
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    final told = (round.told[member] ?? 0).clamp(0, messages.length);
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
        other != null &&
            other != group &&
            since != null &&
            bots.now.difference(since) < _lost) {
      round.dirty.add(member);
      return;
    }
    final chat = _chat(found);
    final first = unseen.first.seq;
    final last = unseen.last.seq;
    final end = chat.lines[last + 1] ?? chat.text.split('\n').length;
    round.told[member] = messages.length;
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
      called: round.called.remove(member),
      why: why,
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
    final round = _round(group)
      ..told[member] = (_messages[group] ?? const []).length
      ..passes[member] = 0;
    if (round.left < budget ~/ 2) round.left = budget ~/ 2;
    _plan(group, said: message.text, by: member, after: stagger ~/ 3);
    return message;
  }

  /// Under test: where what a bot is told goes, in place of its
  /// conversation.
  @visibleForTesting
  void Function(String group, String member, String note)? tell;

  /// [member]'s turn in [group] done: what it said sent to the group, as
  /// it is; or it kept quiet. Told of what came meanwhile if it is to be
  /// woken for it.
  @visibleForTesting
  void turnEnded(
    String group,
    String member,
    String reply, {
    List<ImageAttachment> images = const [],
  }) {
    final found = byId(group);
    if (found == null || !found.members.contains(member)) return;
    final round = _round(group);
    if (_answering[member] == group) _answering.remove(member);
    // With those it sent from files or the web meanwhile.
    images = [...images, ...?_webPictures.remove(member)];
    if (reply.isEmpty && images.isEmpty) {
      bots.world.note(
        '- ${_nameOf(member, found)} read "${found.name}" (group $group) '
        'and kept quiet.',
      );
      round.passes[member] = (round.passes[member] ?? 0) + 1;
      if (round.dirty.remove(member)) _wake(group, member);
      return;
    }
    round
      ..passes[member] = 0
      ..left -= 1;
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
    if (round.left <= 0) {
      round.cancelWaking();
      return;
    }
    _plan(group, said: reply, by: member, after: stagger ~/ 3);
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
    for (final group in [..._groups]) {
      if (_answering.containsKey(member)) return;
      if (_rounds[group.id]?.dirty.remove(member) ?? false) {
        _wake(group.id, member);
      }
    }
  }
}

/// Where a group is at, since the user last spoke.
class _Round {
  /// What the bots may still say before the user speaks again.
  int left = 0;

  /// How many times the user spoke, this run.
  int number = 0;

  /// The user's words while they still write ([BotGroups.quiet]).
  final asked = StringBuffer();
  Timer? quiet;

  /// The bots to be woken, each when, and why.
  final Map<String, ({Timer timer, DateTime at, String why})> waking = {};

  /// How many of the messages each bot was told of.
  final Map<String, int> told = {};

  /// How many times running each kept quiet.
  final Map<String, int> passes = {};

  /// Of those quiet a while, how many times running the user spoke and
  /// they were let be.
  final Map<String, int> skipped = {};

  /// Those with something new while at work: woken again after.
  final Set<String> dirty = {};

  /// Those called on (@), till they are told.
  final Set<String> called = {};

  /// The app's own rules, if the world says nothing of it in time.
  Timer? fallback;

  void cancelWaking() {
    for (final waking in waking.values) {
      waking.timer.cancel();
    }
    waking.clear();
  }

  void cancel() {
    cancelWaking();
    quiet?.cancel();
    fallback?.cancel();
  }

  void forget(String member) {
    waking.remove(member)?.timer.cancel();
    told.remove(member);
    passes.remove(member);
    skipped.remove(member);
    dirty.remove(member);
    called.remove(member);
  }
}
