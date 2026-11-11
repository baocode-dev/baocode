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
import 'bot_prompt.dart' show botEventMessage;
import 'bots.dart';

/// The user's group chats with their bots: each its messages, kept on the
/// computer as they are said (`groups/<id>/messages.jsonl`), and as the
/// bots read them (`chat.md`). Each bot in one has a conversation of its
/// own for it, apart from its chat with the user, in which it is told of
/// what is new and reads the chat as it needs; its reply, if it makes
/// one, is the group's.
///
/// Who is told when, as people in a group chat go:
/// - What the user says is taken up once they stop for [quiet]: what they
///   say together is one.
/// - The bots are told one after another, [stagger] apart: those called
///   on (@name) first, then those named, the one the user answered, the
///   quietest. Each sees what those before it said, and mostly need not
///   say more.
/// - A reply is sent once the bot is done: if others spoke meanwhile, it is
///   held and the bot told of them, to send it still, change it, or not.
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

  /// The members' conversations followed, by group and bot.
  final Map<ChatSession, VoidCallback> _followed = {};

  bool _started = false;
  bool _disposed = false;

  String? get _root => switch (bots.folders.root) {
    final root? => p.join(root, folder),
    null => null,
  };

  String _folderOf(String group) => p.join(_root!, group);

  /// Where [group]'s chat is, as its bots read it.
  String chatFile(String group) => p.join(_folderOf(group), 'chat.md');

  /// [bot]'s conversation's folder for [group].
  static String memberFolder(Bot bot, String group) =>
      p.join(bot.folder, folder, group);

  /// The group whose conversation, a bot's, is in [cwd].
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
    bots.groupPrompt = _prompt;
    bots.addListener(_botsChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) {
      bots.removeListener(_botsChanged);
      if (bots.groupPrompt == _prompt) bots.groupPrompt = null;
    }
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
          '## #${message.seq} · ${_nameOf(message.from)} · ${botTimeOf(message.at)}',
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

  String _nameOf(String from) => from == linkGroupUser
      ? (bots.me.name.isEmpty ? (bots.chinese ? '用户' : 'User') : bots.me.name)
      : bots.byId(from)?.name ?? from;

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
    final BotGroup group;
    if (id == null) {
      group = BotGroup(
        id: _newId(),
        name: name,
        members: kept,
        created: bots.now,
      );
      _groups.add(group);
      _messages[group.id] = [];
    } else {
      final at = _groups.indexWhere((g) => g.id == id);
      if (at < 0) throw StateError('No group $id');
      final had = _groups[at];
      group = _groups[at] = had.copyWith(name: name, members: kept);
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
    notifyListeners();
  }

  /// [member] out of [group]: its conversation of it gone.
  void _leave(String group, String member) {
    _rounds[group]?.forget(member);
    final bot = bots.byId(member);
    if (bot == null) return;
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
    _workspace.deleteAll(threads);
    bots.folders.delete(path);
  }

  /// The bots gone: out of their groups.
  void _botsChanged() {
    var changed = false;
    for (final (at, group) in _groups.indexed.toList()) {
      final kept = [
        for (final member in group.members)
          if (bots.byId(member) != null) member,
      ];
      if (kept.length == group.members.length) continue;
      _groups[at] = group.copyWith(members: kept);
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

  /// Those of [group]'s bots writing to it now.
  List<String> typing(String group) {
    final found = byId(group);
    if (found == null) return const [];
    return [
      for (final member in found.members)
        if (bots.byId(member) case final bot?)
          if (_threadOf(bot, group) case final thread?)
            if (thread.isOpen && thread.session.isStreaming)
              if (_reply(thread.session).isNotEmpty) member,
    ];
  }

  // --- Its bots' conversations -----------------------------------------

  /// What [bot] is told of [cwd]'s group, in its conversation there.
  String? _prompt(Bot bot, String cwd) {
    final id = groupAt(cwd);
    final group = id == null ? null : byId(id);
    if (group == null) return null;
    return botGroupSection(
      bot,
      group: group,
      others: [
        for (final member in group.members)
          if (member != bot.id) ?bots.byId(member),
      ],
      user: _nameOf(linkGroupUser),
      chat: chatFile(group.id),
    );
  }

  AgentThread? _threadOf(Bot bot, String group) {
    final path = memberFolder(bot, group);
    AgentThread? latest;
    for (final thread in _workspace.threads) {
      if (thread.project.path != path || thread.archived) continue;
      if (latest == null || thread.updatedAt.isAfter(latest.updatedAt)) {
        latest = thread;
      }
    }
    return latest;
  }

  AgentThread _threadFor(Bot bot, String group) {
    final thread =
        _threadOf(bot, group) ??
        (() {
          final path = memberFolder(bot, group);
          bots.folders.make(path);
          return _workspace.startAgent(_workspace.projectAt(path));
        })();
    _follow(bot.id, group, thread.session);
    return thread;
  }

  /// [member]'s conversation of [group] followed: its turn's end is its
  /// reply, or its keeping quiet; and while it writes, it is typing.
  void _follow(String member, String group, ChatSession session) {
    if (_followed.containsKey(session)) return;
    var streaming = session.isStreaming;
    var typing = false;
    void listener() {
      if (streaming && !session.isStreaming) {
        scheduleMicrotask(() => _turnEnded(group, member, session));
      }
      streaming = session.isStreaming;
      final now = streaming && _reply(session).isNotEmpty;
      if (now != typing) {
        typing = now;
        notifyListeners();
      }
    }

    _followed[session] = listener;
    session.addListener(listener);
  }

  /// What [session]'s last turn said to the group: its messages and
  /// narration, in their tags; empty for nothing.
  static String _reply(ChatSession session) {
    final texts = <String>[];
    for (var i = session.itemCount - 1; i >= 0; i--) {
      switch (session.itemAt(i)) {
        case UserMessageItem():
          i = -1;
        case AssistantTextItem(:final text):
          texts.insert(0, text);
        default:
      }
    }
    return [
      for (final (tag, text) in ChatCodec.botParts(texts.join('\n')))
        if ((tag == ChatCodec.botSayTag || tag == ChatCodec.botNarrateTag) &&
            text.trim().isNotEmpty)
          '<$tag>${text.trim()}</$tag>',
    ].join();
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
    final names = <String>[];
    for (final (n, image) in images.indexed) {
      final name = '$seq-${n + 1}${_extensions[image.mediaType] ?? '.png'}';
      bots.folders.writeFile(
        p.join(_folderOf(group), 'images', name),
        image.bytes,
      );
      names.add(name);
    }
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

  void _add(BotGroup group, LinkGroupMessage message) {
    (_messages[group.id] ??= []).add(message);
    _saveMessages(group);
    notifyListeners();
  }

  /// Wakes [group]'s bots one after another, from [after] on, for what
  /// [by] [said]: not [by], nor one already to be woken.
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
      round.waking[bot.id] = Timer(after + stagger * next++, () {
        round.waking.remove(bot.id);
        _wake(group, bot.id);
      });
    }
  }

  /// [member] told of what is new in [group], if there is, and the group
  /// may still hear from the bots: later, if it is at work.
  void _wake(String group, String member, {bool again = false}) {
    final found = byId(group);
    final bot = bots.byId(member);
    if (found == null || bot == null || !found.members.contains(member)) {
      return;
    }
    final round = _round(group);
    if (round.left <= 0 && !again) return;
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    final told = (round.told[member] ?? 0).clamp(0, messages.length);
    final unseen = [
      for (final message in messages.skip(told))
        if (message.from != member) message,
    ];
    if (unseen.isEmpty) return;
    final session = tell == null ? _threadFor(bot, group).session : null;
    if (session != null && session.isStreaming) {
      round.dirty.add(member);
      return;
    }
    final chat = _chat(found);
    final first = unseen.first.seq;
    final last = unseen.last.seq;
    final end = chat.lines[last + 1] ?? chat.text.split('\n').length;
    round.told[member] = messages.length;
    final note = botGroupWake(
      chat: chatFile(group),
      from: first,
      to: last,
      lines: (chat.lines[first] ?? 1, end - 1),
      senders: {for (final m in unseen) _nameOf(m.from)}.toList(),
      called: round.called.remove(member),
      again: again,
    );
    if (tell case final tell?) return tell(group, member, note);
    session!.send(ComposerMessage(text: botEventMessage(note)));
  }

  /// Under test: where what a bot is told goes, in place of its
  /// conversation.
  @visibleForTesting
  void Function(String group, String member, String note)? tell;

  /// [member]'s turn in [group] done: what it said sent to the group, or
  /// held if the group went on meanwhile; or it kept quiet.
  @visibleForTesting
  void turnEnded(String group, String member, String reply) {
    final found = byId(group);
    if (found == null || !found.members.contains(member)) return;
    final round = _round(group);
    if (reply.isEmpty) {
      round.passes[member] = (round.passes[member] ?? 0) + 1;
      round.held.remove(member);
      if (round.dirty.remove(member)) _wake(group, member);
      return;
    }
    final messages = _messages[group] ?? const <LinkGroupMessage>[];
    final told = (round.told[member] ?? 0).clamp(0, messages.length);
    final missed = messages.skip(told).any((m) => m.from != member);
    final held = round.held[member] ?? 0;
    if (missed && held < 2) {
      round.held[member] = held + 1;
      round.dirty.remove(member);
      _wake(group, member, again: true);
      return;
    }
    round
      ..held.remove(member)
      ..dirty.remove(member)
      ..passes[member] = 0
      ..left -= 1;
    _add(
      found,
      LinkGroupMessage(
        seq: _nextSeq(group),
        at: bots.now,
        from: member,
        text: reply,
      ),
    );
    if (round.left <= 0) {
      round.cancelWaking();
      return;
    }
    _plan(group, said: reply, by: member, after: stagger ~/ 3);
  }

  void _turnEnded(String group, String member, ChatSession session) {
    if (_disposed) return;
    turnEnded(group, member, _reply(session));
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

  /// The bots to be woken, each when.
  final Map<String, Timer> waking = {};

  /// How many of the messages each bot was told of.
  final Map<String, int> told = {};

  /// How many times running each kept quiet.
  final Map<String, int> passes = {};

  /// Of those quiet a while, how many times running the user spoke and
  /// they were let be.
  final Map<String, int> skipped = {};

  /// Those with something new while at work: woken again after.
  final Set<String> dirty = {};

  /// How many times each one's reply was held, this turn of it.
  final Map<String, int> held = {};

  /// Those called on (@), till they are told.
  final Set<String> called = {};

  void cancelWaking() {
    for (final timer in waking.values) {
      timer.cancel();
    }
    waking.clear();
  }

  void cancel() {
    cancelWaking();
    quiet?.cancel();
  }

  void forget(String member) {
    waking.remove(member)?.cancel();
    told.remove(member);
    passes.remove(member);
    skipped.remove(member);
    dirty.remove(member);
    held.remove(member);
    called.remove(member);
  }
}
