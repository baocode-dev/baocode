import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../models/model_providers.dart';
import '../workspace/workspace.dart';
import 'bot.dart';
import 'bot_life.dart';
import 'bot_pacer.dart' show botTime;
import 'bot_prompt.dart' show botEventMessage;
import 'bots.dart';

/// What the world decided, in its reply's tags ([WorldActs.parse]).
sealed class WorldAct {
  const WorldAct();
}

/// [who] (a bot's id) told, [after] from now, of what is new in [group]:
/// [why], in a few words of fact.
class WorldWake extends WorldAct {
  const WorldWake(this.who, this.group, this.after, this.why);
  final String who;
  final String group;
  final Duration after;
  final String why;
}

/// [who] has something on its mind for the user, [after] from now:
/// [why]. Its to write to them, or not.
class WorldReach extends WorldAct {
  const WorldReach(this.who, this.after, this.why);
  final String who;
  final Duration after;
  final String why;
}

/// How [who] is now: [text].
class WorldState extends WorldAct {
  const WorldState(this.who, this.text);
  final String who;
  final String text;
}

/// When the world looks again of itself, nothing happening: [after].
class WorldLook extends WorldAct {
  const WorldLook(this.after);
  final Duration after;
}

abstract final class WorldActs {
  static final _tag = RegExp(
    r'<(wake|reach|state|next_look)\b([^>]*?)(?:/>|>(.*?)</\1\s*>)',
    dotAll: true,
  );
  static final _attribute = RegExp(r'(\w+)\s*=\s*"([^"]*)"');

  /// How long [text] says: `40s`, `5m`, `2h`, or seconds ([unit] for a
  /// bare number).
  static Duration? duration(String? text, {String unit = 's'}) {
    final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*([smh]?)\s*$')
        .firstMatch(text ?? '');
    if (match == null) return null;
    final n = double.parse(match.group(1)!);
    final seconds = switch (match.group(2)!.isEmpty ? unit : match.group(2)) {
      'h' => n * 3600,
      'm' => n * 60,
      _ => n,
    };
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// The acts [reply] has, its people found by [who] (a name, or an id):
  /// those of no one known left out.
  static List<WorldAct> parse(
    String reply, {
    required Bot? Function(String) who,
  }) {
    final acts = <WorldAct>[];
    for (final match in _tag.allMatches(reply)) {
      final attributes = {
        for (final a in _attribute.allMatches(match.group(2)!))
          a.group(1)!: a.group(2)!.trim(),
      };
      final body = (match.group(3) ?? '').trim();
      final bot = switch (attributes['who']) {
        final String name => who(name),
        null => null,
      };
      switch (match.group(1)) {
        case 'wake':
          final group = attributes['group'];
          if (bot == null || group == null || group.isEmpty) continue;
          acts.add(
            WorldWake(
              bot.id,
              group,
              duration(attributes['after']) ?? Duration.zero,
              body,
            ),
          );
        case 'reach':
          if (bot == null) continue;
          acts.add(
            WorldReach(
              bot.id,
              duration(attributes['after']) ?? Duration.zero,
              body,
            ),
          );
        case 'state':
          if (bot == null || body.isEmpty) continue;
          acts.add(WorldState(bot.id, body));
        case 'next_look':
          if (duration(attributes['after'], unit: 'm') case final after?) {
            acts.add(WorldLook(after));
          }
      }
    }
    return acts;
  }
}

/// The bots' world: one conversation of its own, on the model the user
/// picked for it ([ModelProviders.worldModel]), never seen and never
/// speaking. Told of what happens (what is said in the groups, and to
/// the bots in private, who kept quiet), it keeps how everyone is now
/// (world/now.md), says who in a group answers and when, who has the
/// user on their mind, and when it looks again. It decides; the app
/// keeps the laws ([BotWorld] laws below): the hours of the night, how
/// often one writes first, how much a group says, a group's order.
class BotWorld {
  BotWorld(this.bots);

  final Bots bots;

  /// The folder its conversation is in, in the bots'.
  static const folderName = 'world';

  /// How long the app waits for it to say who answers in a group before
  /// its own rules do.
  Duration waitFor = const Duration(seconds: 30);

  /// How long what it is told gathers before it is told: what is said
  /// together, together.
  Duration gather = const Duration(milliseconds: 800);

  /// How long what needs no answer now (what was said in private, who
  /// kept quiet) waits to be told with the next.
  Duration lazily = const Duration(minutes: 2);

  /// Laws: the night, when no one writes first; how many times a day each
  /// may; how soon and how late the world looks again; how long a wake or
  /// a reach may be put off.
  static const nightFrom = 23, nightTo = 8;
  static const reachesADay = 3;
  static const lookSoonest = Duration(minutes: 1);
  static const lookLatest = Duration(hours: 2);
  static const wakeLatest = Duration(minutes: 10);
  static const reachLatest = Duration(hours: 6);

  /// Under test: its model, in place of the user's pick.
  @visibleForTesting
  String? Function()? modelOf;

  /// Under test: where what it is told goes, in place of its conversation;
  /// and what a bot is told to write first.
  @visibleForTesting
  void Function(String text)? tell;
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

  /// How everyone is now, as it keeps it.
  String? get nowFile => switch (folder) {
    final folder? => p.join(folder, 'now.md'),
    null => null,
  };

  /// How each is now, by bot id; and since when.
  final Map<String, ({String text, DateTime at})> _states = {};

  final List<String> _told = [];
  final Set<String> _asking = {};
  Set<String> _deciding = {};
  Timer? _flush;
  DateTime _flushAt = DateTime(0);
  Timer? _look;
  final List<Timer> _timers = [];
  final Map<String, ({String day, int count})> _reaches = {};
  ChatSession? _followed;
  VoidCallback? _listener;
  bool _disposed = false;

  void start() {
    _readStates();
  }

  void dispose() {
    _disposed = true;
    _flush?.cancel();
    _look?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    if ((_followed, _listener) case (final session?, final listener?)) {
      session.removeListener(listener);
    }
  }

  // --- How everyone is ---------------------------------------------------

  /// How [bot] is now, as the world has it; none if it said nothing yet.
  String? stateOf(Bot bot) => _states[bot.id]?.text;

  void _readStates() {
    final path = nowFile;
    if (path == null) return;
    final bytes = bots.folders.readFile(path);
    if (bytes == null) return;
    final line = RegExp(r'^- (.+?): (.*) \((\d\d):(\d\d)\)$');
    final now = bots.now;
    for (final text in utf8.decode(bytes, allowMalformed: true).split('\n')) {
      final match = line.firstMatch(text);
      if (match == null) continue;
      final bot = bots.bots.where((b) => b.name == match.group(1)).firstOrNull;
      if (bot == null) continue;
      _states[bot.id] = (
        text: match.group(2)!,
        at: DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(match.group(3)!),
          int.parse(match.group(4)!),
        ),
      );
    }
  }

  void _writeStates() {
    final path = nowFile;
    if (path == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final lines = [
      '# Now',
      '',
      'How everyone is, as the world keeps it.',
      '',
      for (final bot in bots.bots)
        if (_states[bot.id] case final state?)
          '- ${bot.name}: ${state.text} (${two(state.at.hour)}:${two(state.at.minute)})',
    ];
    bots.folders.writeFile(
      path,
      Uint8List.fromList(utf8.encode('${lines.join('\n')}\n')),
    );
  }

  // --- What it is told ---------------------------------------------------

  /// [lines] happened in [group]: who answers, and when, is the world's to
  /// say ([decided] once it did).
  void ask(String group, List<String> lines) {
    _told.addAll(lines);
    _asking.add(group);
    _schedule(gather);
  }

  /// [line] happened: told with what comes next, or a while after.
  void note(String line) {
    if (!on) return;
    _told.add(line);
    _schedule(lazily);
  }

  /// What became of the groups asked last: told the groups, for those it
  /// said nothing of to be let be.
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
    if (_disposed || _told.isEmpty || !on) return;
    final session = tell == null ? _session() : null;
    if (session != null && session.isStreaming) return;
    final text = _batch(_told);
    _told.clear();
    _deciding = {..._asking};
    _asking.clear();
    if (tell case final tell?) return tell(text);
    session!.send(ComposerMessage(text: botEventMessage(text)));
  }

  String _batch(List<String> happened) {
    final now = bots.now;
    return [
      'Now: ${botTime(now)}.',
      'Everyone, as you have them now:',
      for (final bot in bots.bots)
        '- ${bot.name}${bot.assistant ? ' (the assistant)' : ''}: '
            '${_states[bot.id]?.text ?? '(nothing said yet)'}',
      '',
      'What happened:',
      ...happened,
    ].join('\n');
  }

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
    answered(texts.join('\n'));
  }

  /// Its reply [text]: what it decided, done as the laws let it.
  @visibleForTesting
  void answered(String text) {
    final acts = WorldActs.parse(
      text,
      who: (name) =>
          bots.byId(name) ??
          bots.bots.where((bot) => bot.name == name).firstOrNull,
    );
    var states = false;
    for (final act in acts) {
      switch (act) {
        case WorldState(:final who, :final text):
          _states[who] = (text: text, at: bots.now);
          states = true;
        case WorldWake(:final who, :final group, :final after, :final why):
          bots.groups.wakeFor(
            group,
            who,
            after: after > wakeLatest ? wakeLatest : after,
            why: why,
          );
        case WorldReach(:final who, :final after, :final why):
          _reach(who, after > reachLatest ? reachLatest : after, why);
        case WorldLook(:final after):
          _lookIn(after);
      }
    }
    if (states) _writeStates();
    final deciding = _deciding;
    _deciding = {};
    // Nothing said (an error, a reply cut short): its groups left to the
    // app's own rules.
    if (acts.isNotEmpty) decided?.call(deciding);
    // What came meanwhile.
    if (_told.isNotEmpty) _schedule(_asking.isEmpty ? lazily : gather);
  }

  void _lookIn(Duration after) {
    final clamped = after < lookSoonest
        ? lookSoonest
        : after > lookLatest
        ? lookLatest
        : after;
    _look?.cancel();
    _look = Timer(clamped, () {
      if (!on || !bots.hasPhoneNow) return;
      _told.add('- Time passes; nothing else.');
      _schedule(Duration.zero);
    });
  }

  /// When the user last said something, in a group or in private.
  DateTime? _userSaidAt;

  /// The user said something: what they asked for (a word in private) is
  /// theirs for a while ([askedWithin]).
  void heardUser() => _userSaidAt = bots.now;

  /// How long after the user last spoke a bot may write to them in
  /// private as they asked, whatever the laws of writing first.
  static const askedWithin = Duration(minutes: 10);

  /// Why [bot] may not write first to the user at [at] (now): not let
  /// ([BotAbility.proactive]), at night, past [reachesADay] times today;
  /// none when it may.
  String? refusesFirst(Bot bot, {DateTime? at}) {
    at ??= bots.now;
    if (!bot.can(BotAbility.proactive)) {
      return 'the user has not let you write to them first (in your '
          'profile, it is off)';
    }
    if (at.hour >= nightFrom || at.hour < nightTo) {
      return 'it is night ($worldNight): no one writes first to the user '
          'then';
    }
    final had = _reaches[bot.id];
    if (had?.day == _day(at) && had!.count >= reachesADay) {
      return 'you wrote first to the user $reachesADay times today already';
    }
    return null;
  }

  static String _day(DateTime at) => '${at.year}-${at.month}-${at.day}';

  void _wroteFirst(Bot bot, DateTime at) {
    final had = _reaches[bot.id];
    final count = had?.day == _day(at) ? had!.count : 0;
    _reaches[bot.id] = (day: _day(at), count: count + 1);
  }

  /// Why [bot] may not write to the user in private now, from a group's
  /// turn ([ChatCodec.botSendTool]); none when it may: as they asked (they
  /// spoke lately), or first, as the laws let it, counted.
  String? sendsPrivately(Bot bot) {
    final said = _userSaidAt;
    if (said != null && bots.now.difference(said) <= askedWithin) return null;
    final why = refusesFirst(bot);
    if (why != null) return why;
    _wroteFirst(bot, bots.now);
    return null;
  }

  /// [who] writes first to the user, [after] from now, of [why], as the
  /// laws let it ([refusesFirst]).
  void _reach(String who, Duration after, String why) {
    final bot = bots.byId(who);
    if (bot == null) return;
    final at = bots.now.add(after);
    if (refusesFirst(bot, at: at) != null) return;
    _wroteFirst(bot, at);
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
    now: nowFile ?? '',
    user: bots.userName,
    time: bots.now,
  );
}

/// What the world is told: what it is, the laws it keeps to, what it says.
String worldInstructions({
  required String world,
  required String now,
  required String user,
  required DateTime time,
}) =>
    '''
You are the world the user's bots live in. Not one of them, not a narrator: no one sees you, and you never say anything to anyone. You keep how everyone is, and you decide what happens next: who in a group chat would answer and when, who has the user on their mind, when you look again. Each of them then decides for themselves what to say, and whether to.

The people: $user (the user, on their phone) and the bots, as $world says (who they are, what they may do, who is in which group). Read it at the start, and when someone new comes up. The groups' chats and each bot's timeline are files you may read too, with Read, when you need what came before.

How it goes:
- The app tells you what happened, in a note (<bao-event>): the time, everyone as you have them now, then what happened (messages in groups, what was said in private, who read and kept quiet; "Time passes" when you look of yourself).
- You answer with tags only, nothing else:
  <state who="NAME">how they are now, in a few words: what they are doing, their mood</state> for those who changed.
  <wake who="NAME" group="GROUP_ID" after="40s">why, in a few words of fact</wake> for each in a group who would read and answer now; none if no one would.
  <reach who="NAME" after="20m">why they would write to the user, in a few words of fact</reach>, rarely: someone has a real reason to write first.
  <next_look after="30m"/>: when to look again with nothing happening (1 minute to 2 hours).
- "why" is what happened, never what to say: "板板 asked her to change their pictures", "someone said she was wrong", "he promised to report at 3". Never put words in their mouths.

What is natural:
- People have lives: they sleep at night, work, eat, go out, according to who they are. Keep their state true to the time of day and to what happened to them. Someone asleep or busy reads later, or not at all.
- In a group most messages need one answer or none. When the user speaks to someone by name or @, that one answers; others only if it is plainly theirs too. A message between two of them is theirs. A closed topic, a "收到", a joke that landed: no one. Not everyone, nor the same one again and again; but when the user asks everyone ("大家", "everyone", a roll call), everyone answers, the user's assistant too, each in their own time.
- Not all at once, but not slow: when the user speaks in a group, the first answer comes within a few seconds (after 0–5s), the next ones within a minute; the busy, asleep or away later. Between the bots, the same pace as people chatting. Use after.
- What the user asks of someone (to write to them in private, to look something up) is that one's to do when they wake: wake them; never <reach> for it.
- A person who was just told off, ignored, praised or proven wrong feels it: say so in their state.
- Writing first to the user is rare and has a reason: a promise come due, something that happened that concerns them, a long silence with someone close. Not at night.
- Look again sooner while a conversation is alive, later when all is quiet, in the morning when it is night.

The laws, which the app keeps whatever you say: no one writes first at night ($worldNight), nor more than ${BotWorld.reachesADay} times a day; a group has only so many answers for each of the user's messages; an answer is held while the group moves on.

How everyone is now is kept in $now from your states.
<world_started>${botTime(time)}</world_started>''';

/// The night of the laws, as the world is told it.
const worldNight =
    '${BotWorld.nightFrom}:00–${BotWorld.nightTo < 10 ? '0' : ''}${BotWorld.nightTo}:00';
