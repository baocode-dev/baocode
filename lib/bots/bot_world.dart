import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../link/chat_codec.dart';
import '../models/model_providers.dart';
import '../workspace/workspace.dart';
import 'bot.dart';
import 'bot_life.dart';
import 'bot_pacer.dart' show botTime;
import 'bots.dart';

/// The bots' world: one conversation of its own, on the model the user
/// picked for it ([ModelProviders.worldModel]), never seen and never
/// speaking. It keeps the user's world going: what the user says in a
/// group is said to it, and what else happens (a bot spoke, kept quiet, a
/// word in private) it is reminded of, pointed to where it is in the
/// files; it wakes the bots, each when and why, with its one tool
/// ([wakeTool]). Each bot then decides for itself. The app keeps the laws:
/// how much a group says, who may write to the user first.
class BotWorld {
  BotWorld(this.bots);

  final Bots bots;

  /// The folder its conversation is in, in the bots'.
  static const folderName = 'world';

  /// Its one tool, but Read: a bot woken.
  static const wakeTool = 'world_wake';

  /// Where a bot is woken in its chat with the user, as [wakeTool] has it.
  static const inPrivate = ChatCodec.botToUser;

  /// How long the app waits for it to say who answers in a group before
  /// its own rules do.
  Duration waitFor = const Duration(seconds: 30);

  /// How long what it is told gathers before it is told: what is said
  /// together, together.
  Duration gather = const Duration(milliseconds: 800);

  /// How long what needs no answer now (a word in private, who kept quiet)
  /// waits to be told with the next.
  Duration lazily = const Duration(minutes: 2);

  /// Laws: how long a wake in a group, or in private, may be put off.
  static const wakeLatest = Duration(minutes: 10);
  static const reachLatest = Duration(hours: 24);

  /// Under test: its model, in place of the user's pick.
  @visibleForTesting
  String? Function()? modelOf;

  /// Under test: what it is sent (the user's words, if any; the app's
  /// reminder), in place of its conversation; and what a bot is told to
  /// write first.
  @visibleForTesting
  void Function(String said, String reminder)? tell;
  @visibleForTesting
  void Function(Bot bot, String note)? reached;

  String? get model =>
      modelOf != null ? modelOf!() : ModelProviders.current.worldModel;

  /// Whether it runs: a model picked, and somewhere for it.
  bool get on => model != null && folder != null;

  String? get folder => switch (bots.folders.root) {
    final root? => p.join(root, folderName),
    null => null,
  };

  /// The user's words to tell it, by group; what else happened; where in
  /// each bot's timeline its chat with the user went on, by bot id; whether
  /// WORLD.md changed.
  final Map<String, List<String>> _said = {};
  final List<String> _happened = [];
  final Map<String, ({String file, int from})> _private = {};
  bool _worldChanged = false;

  bool get _told =>
      _said.isNotEmpty ||
      _happened.isNotEmpty ||
      _private.isNotEmpty ||
      _worldChanged;

  final Set<String> _asking = {};
  Set<String> _deciding = {};
  Timer? _flush;
  DateTime _flushAt = DateTime(0);
  final List<Timer> _timers = [];
  ChatSession? _followed;
  VoidCallback? _listener;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _flush?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    if ((_followed, _listener) case (final session?, final listener?)) {
      session.removeListener(listener);
    }
  }

  // --- What it is told ---------------------------------------------------

  /// Something new in [group], where [line] says: who answers, and when,
  /// is the world's to say ([decided] once it did). [said]: the user's
  /// words, said to it.
  void ask(String group, {String? said, required String line}) {
    if (said != null) (_said[group] ??= []).add(said);
    _happened.add(line);
    _asking.add(group);
    _schedule(gather);
  }

  /// [line] happened: told with what comes next, or a while after.
  void note(String line) {
    if (!on) return;
    _happened.add(line);
    _schedule(lazily);
  }

  /// [bot]'s chat with the user went on, at [line] of its timeline [file].
  void private(Bot bot, String file, int line) {
    if (!on) return;
    final had = _private[bot.id];
    _private[bot.id] = (
      file: file,
      from: had != null && had.file == file ? had.from : line,
    );
    _schedule(lazily);
  }

  /// WORLD.md changed: who is who, the groups.
  void worldChanged() {
    if (!on) return;
    _worldChanged = true;
    _schedule(lazily);
  }

  /// The groups it was asked of, the last time: told the groups, their own
  /// rules not needed.
  void Function(Set<String> groups)? decided;

  /// When what it was told is sent it: the sooner of what is due.
  void _schedule(Duration after) {
    final at = DateTime.now().add(after);
    if (_flush?.isActive == true && !at.isBefore(_flushAt)) return;
    _flush?.cancel();
    _flushAt = at;
    _flush = Timer(after, _send);
  }

  /// What it was told since, sent it: now, unless it is at work, then once
  /// it is done.
  void _send() {
    if (_disposed || !_told || !on) return;
    final session = tell == null ? _session() : null;
    if (session != null && session.isStreaming) return;
    final groups = _said.length;
    final said = [
      for (final MapEntry(key: group, value: words) in _said.entries)
        for (final text in words)
          groups == 1
              ? text
              : '[${bots.groups.byId(group)?.name ?? group}] $text',
    ].join('\n');
    final reminder = _reminder();
    _said.clear();
    _happened.clear();
    _private.clear();
    _worldChanged = false;
    _deciding = {..._asking};
    _asking.clear();
    if (tell case final tell?) return tell(said, reminder);
    final note = '<system-reminder>\n$reminder\n</system-reminder>';
    // The user's words the message, the app's reminder with them; alone,
    // when they said nothing.
    if (said.isEmpty) {
      session!.send(ComposerMessage(text: note));
    } else {
      session!.send(ComposerMessage(text: said), notes: [note]);
    }
  }

  /// What it is reminded of: the time, what is new and where, who is to be
  /// woken already, what the groups may still say.
  String _reminder() {
    final now = bots.now;
    final groups = bots.groups;
    final waiting = groups.waiting;
    final names = {for (final bot in bots.bots) bot.id: bot.name};
    final busy = [
      for (final bot in bots.bots)
        if (bots.atWork(bot) case (:final group, :final since))
          '- ${bot.name}, '
              '${group == null ? 'in private with ${bots.userName}' : 'for "${groups.byId(group)?.name ?? group}"'}'
              '${since == null ? '' : ' since ${_clock(since)}'}.',
    ];
    final asked = [for (final group in _asking) ?groups.byId(group)];
    return [
      'Now: ${botTime(now, seconds: true)}.',
      if (_said.isNotEmpty)
        'The message is ${bots.userName}\'s, in a group, said to you.',
      'What is new:',
      ..._happened,
      for (final MapEntry(key: id, :value) in _private.entries)
        if (names[id] case final name?)
          '- ${bots.userName} and $name, in private: from line ${value.from} '
              'of ${value.file}.',
      if (_worldChanged)
        '- ${BotLife.world} changed (who is who, the groups): read it again.',
      if (busy.isNotEmpty) ...['At work now:', ...busy],
      if (waiting.isNotEmpty) ...[
        'To be woken already:',
        for (final w in waiting)
          '- ${names[w.member] ?? w.member} in "${w.group.name}" at '
              '${_clock(w.at)}${w.why.isEmpty ? '' : ' (${w.why})'}.',
      ],
      for (final group in asked)
        '"${group.name}" may have ${groups.answersLeft(group.id)} more '
            'answers to the user\'s last message.',
    ].join('\n');
  }

  /// How long [text] says: `40s`, `5m`, `2h`, or seconds for a bare
  /// number; null for what is none of these.
  static Duration? duration(String text) {
    final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*([smh]?)\s*$')
        .firstMatch(text);
    if (match == null) return null;
    final n = double.parse(match.group(1)!);
    final seconds = switch (match.group(2)) {
      'h' => n * 3600,
      'm' => n * 60,
      _ => n,
    };
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// [at]'s time of day, to the second.
  static String _clock(DateTime at) =>
      botTime(at, seconds: true).split(' ').last;

  // --- Its conversation --------------------------------------------------

  ChatSession _session() {
    final workspace = bots.workspace;
    final path = folder!;
    AgentThread? latest;
    for (final thread in workspace.threads) {
      if (thread.project.path != path || thread.archived) continue;
      if (latest == null || thread.updatedAt.isAfter(latest.updatedAt)) {
        latest = thread;
      }
    }
    final thread =
        latest ??
        (() {
          bots.folders.make(path);
          return workspace.startAgent(workspace.projectAt(path));
        })();
    final session = thread.session;
    // On the model picked now, if it was on another.
    if ((model, session.models) case (final model?, final models?)
        when models.selected.id != model && !session.isStreaming) {
      if (models.options.where((o) => o.id == model).firstOrNull
          case final option?) {
        models.onSelected(option);
      }
    }
    if (!identical(session, _followed)) {
      if ((_followed, _listener) case (final old?, final listener?)) {
        old.removeListener(listener);
      }
      var streaming = session.isStreaming;
      void listener() {
        if (streaming && !session.isStreaming) {
          scheduleMicrotask(() => _ended(session));
        }
        streaming = session.isStreaming;
      }

      _followed = session;
      _listener = listener;
      session.addListener(listener);
    }
    return session;
  }

  void _ended(ChatSession session) {
    if (_disposed || session.isStreaming) return;
    var failed = false;
    for (var i = session.itemCount - 1; i >= 0; i--) {
      switch (session.itemAt(i)) {
        case UserMessageItem():
          i = -1;
        case NoticeItem(kind: NoticeKind.error):
          failed = true;
        case AssistantTextItem(:final text)
            when text.trimLeft().startsWith('API Error'):
          failed = true;
        default:
      }
    }
    ended(failed: failed);
  }

  /// Its turn done: those it woke no one in let be, unless it [failed]
  /// (an error, cut short): then theirs are the app's own rules. Then what
  /// came meanwhile.
  @visibleForTesting
  void ended({bool failed = false}) {
    final deciding = _deciding;
    _deciding = {};
    if (!failed) decided?.call(deciding);
    if (_told) _schedule(_asking.isEmpty ? lazily : gather);
  }

  // --- What it does --------------------------------------------------------

  /// [who] (a bot's name or id) woken [where] (a group's id or name, or
  /// [inPrivate]) [after] from now, for [why]: what came of it, or why not
  /// ([StateError]).
  String wake({
    required String who,
    required String where,
    required Duration after,
    required String why,
  }) {
    final bot =
        bots.byId(who) ??
        bots.bots.where((bot) => bot.name == who).firstOrNull ??
        (throw StateError('No one is called $who (${BotLife.world}).'));
    String at(Duration after) => _clock(bots.now.add(after));
    if (where == inPrivate) {
      if (refusesFirst(bot) case final why?) {
        throw StateError('Not woken: $why.');
      }
      final wait = after > reachLatest ? reachLatest : after;
      _reach(bot.id, wait, why);
      return 'Waking ${bot.name} in private at ${at(wait)}.';
    }
    final groups = bots.groups;
    final group =
        groups.byId(where) ??
        groups.groups.where((group) => group.name == where).firstOrNull ??
        (throw StateError('No group $where (${BotLife.world}).'));
    final wait = after > wakeLatest ? wakeLatest : after;
    final woken = groups.wakeFor(group.id, bot.id, after: wait, why: why);
    decided?.call({group.id});
    final time = _clock(woken.at);
    return woken.already
        ? '${bot.name} was to be woken in "${group.name}" already, at $time.'
        : 'Waking ${bot.name} in "${group.name}" at $time.';
  }

  /// When the user last said something, in a group or in private.
  DateTime? _userSaidAt;

  /// The user said something: what they asked for (a word in private) is
  /// theirs for a while ([askedWithin]).
  void heardUser() => _userSaidAt = bots.now;

  /// How long after the user last spoke a bot may write to them in
  /// private as they asked, whatever the laws of writing first.
  static const askedWithin = Duration(minutes: 10);

  /// Why [bot] may not write first to the user: the user turned it off
  /// ([Bot.writesFirst]); none when it may.
  String? refusesFirst(Bot bot) => bot.writesFirst
      ? null
      : 'the user turned off ${bot.name} writing to them first';

  /// Why [bot] may not write to the user in private now, from a group's
  /// turn ([ChatCodec.botSendTool]); none when it may: as they asked (they
  /// spoke lately), or first, if it may ([refusesFirst]).
  String? sendsPrivately(Bot bot) {
    final said = _userSaidAt;
    if (said != null && bots.now.difference(said) <= askedWithin) return null;
    return refusesFirst(bot);
  }

  /// [who] woken in its chat with the user, [after] from now, for [why]:
  /// to write to them, or not.
  void _reach(String who, Duration after, String why) {
    late final Timer timer;
    timer = Timer(after, () {
      _timers.remove(timer);
      final now = bots.byId(who);
      if (now == null || _disposed) return;
      final note =
          'Something is on your mind (the world, not the user, brings it '
          'up): $why\n'
          'If it is worth it, write to the user now, as you would, in your '
          'own words; if not, end your turn with nothing.';
      if (reached case final reached?) return reached(now, note);
      bots.reach(now, note);
    });
    _timers.add(timer);
  }

  // --- Its setup ---------------------------------------------------------

  /// What its conversation is told it is ([worldInstructions]).
  String instructions() => worldInstructions(
    world: p.join(bots.folders.root ?? '', BotLife.world),
    user: bots.userName,
    time: bots.now,
  );
}

/// What the world is told: what it is, what it is sent, what it does.
String worldInstructions({
  required String world,
  required String user,
  required DateTime time,
}) =>
    '''
You keep the world of $user's bots going. You are not one of them: no one sees you, and you never say anything to anyone. You do one thing: wake a bot, at the right time, with a few words of fact on why, so that their world goes on as $user means it to. What the bot then says, and whether it says anything, is its own to decide.

Who is who is in $world: $user, the bots, what each may do, who is in which group. Read it at the start, and again when you are told it changed. All else is in files too: each group's chat, and each bot's timeline (all it heard and said, a file a day, in its folder's timeline/). Read them, at the lines you are pointed to, whenever you need what was said.

What you are sent:
- What $user says in a group is said to you: it is the message. Work out what they want, and of whom.
- With it, and alone when $user said nothing, a <system-reminder> from the app: the time, what is new and where it is (a bot spoke in a group, read it and kept quiet, a chat in private went on), who is at work now and on what, who is to be woken already, how many more answers a group may have.

What you do: call ${BotWorld.wakeTool} for each one to wake, all at once, then end your turn with nothing else. Waking no one is a choice too: end your turn without.
- When $user speaks in a group, settle then who answers them: everyone it is for, all at once. Asked of everyone, or of each, or a roll call: each of them, the assistant too. Asked of someone, by name or @: that one. Otherwise, those it is plainly for, as people in a chat would.
- Soon, as people in a chat: the first within a few seconds (0–3s), the rest a few seconds apart. Later only one who is plainly busy or away.
- One at work reads what is new only once done. Asked of them by name, wake them all the same; what anyone may answer, wake one who is free.
- When a bot speaks in a group, read what it said; wake another only if it is theirs (asked, named, answered back).
- In private ("${BotWorld.inPrivate}"): someone has a reason to write to $user first: a promise come due, news that concerns them. Rarely, and at a time that suits. What $user asked of someone in a group (to write to them in private, say) is not this: wake them in the group; they do it themselves.
- "why" is what happened, in a few words: "$user asked everyone to reply 收到", "老火 said 阿川 was wrong", "she promised to report at 3". Never what to say, nor whether to; never what they can or cannot do: the app knows, and tells them when they try.
- The tool tells you when a wake does not go, and why.
<world_started>${botTime(time)}</world_started>''';
