import 'dart:convert';
import 'dart:math' as math;

import '../../chat/chat_models.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import '../output_meter.dart';
import 'claude_goal.dart';
import 'claude_numbers.dart';
import 'claude_sdk_tools.dart';
import 'turn_stats.dart';

/// Translates Claude Code's conversation messages (stream-json output, or
/// the lines of a kept session) into [KernelEvent]s: text, thoughts, tool
/// calls and their results, subagents, tasks and runtime notices.
///
/// Turns, settings and control requests are the kernel's; this only knows
/// the conversation. Items are addressed by the CLI's own ids (message id
/// and block, tool use id, message uuid), so translating a message twice,
/// e.g. streamed and then whole, lands on the same items.
class ClaudeTranslator {
  ClaudeTranslator({required this.emit, required this.nextSeq, this.goalSaid});

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// Claude Code said something of the goal, live: how it stands is to be
  /// asked afresh (see claude_goal.dart).
  final void Function()? goalSaid;

  /// What a question was answered with in full access, the user not asked,
  /// as earlier versions did: a question so answered shows as skipped.
  static const unattendedAnswer =
      'The user has given full access and is not here to answer questions. '
      'Do not ask again: go with what seems best, say what you assumed, '
      'and carry on.';

  /// The turn changes belong to (the user message uuid that began it).
  String? turnId;

  /// What the agent is busy with out of sight (see [ActivityReported]).
  KernelActivity? _activity;

  void _report(KernelActivity? activity) {
    if (replaying || (activity == null && _activity == null)) return;
    _activity = activity;
    emit(ActivityReported(nextSeq(), activity));
  }

  /// A turn was sent: the agent is at work from now, before the CLI says so.
  void begin() {
    _resetUsage();
    _report(_waiting());
  }

  KernelActivity _waiting() =>
      KernelActivity(KernelActivityKind.waiting, DateTime.now());

  /// Replaying a kept session: nothing is pending or running any more.
  bool replaying = false;

  /// What the kept session's turns took and spent, as their footers showed
  /// it, by prompt: given to a turn replayed instead of its time guessed.
  Map<String, TurnRecord> keptTurns = const {};

  // Streamed blocks of the current message.
  String? _messageId;
  final Map<int, String> _streamed = {};

  /// Since when the model has been at the next block: its message's start,
  /// else the last block's end.
  DateTime? _blockSince;

  /// The current message's usage, as its start and its last delta said;
  /// whether its delta counted what it wrote, and its thought's tokens;
  /// whether it thought.
  Map<String, Object?> _messageUsage = {};
  bool _messageCounted = false;
  int? _messageThinking;
  bool _messageThought = false;

  /// The turn's requests so far (the agent's own, not its subagents'):
  /// tokens read and written.
  int _turnInput = 0;
  int _turnOutput = 0;

  /// What the agent's own requests write as they stream, and when that was
  /// last reported.
  final OutputMeter _meter = OutputMeter();
  DateTime? _outputReported;

  /// How often what is written is reported, at most, while it streams.
  static const _outputEvery = Duration(milliseconds: 250);

  /// Streamed text and thought blocks, per message and kind, in order,
  /// until the whole message claims them.
  final Map<String, List<String>> _unclaimed = {};

  /// The item each block of a whole message landed on, by the message's
  /// uuid and the block's place: delivered again, it lands there again.
  final Map<String, String> _blockIds = {};
  final Map<String, StringBuffer> _thoughts = {};
  final Map<String, DateTime> _thinkingStarted = {};
  final Map<String, int> _thinkingTokens = {};
  final Map<String, int> _textLength = {};

  final Map<String, _Tool> _tools = {};
  final Map<String, _Agent> _agents = {};

  /// The call that started each subagent, by the CLI's id of it (its
  /// task's): one continued (`SendMessage`) runs again on a call of its
  /// own, and goes on in the card of the first.
  final Map<String, String> _agentCalls = {};
  final Set<String> _denied = {};

  /// Calls made and not answered yet: those of a stopped turn never are.
  final Set<String> _unanswered = {};

  final Map<String, KernelTask> _tasks = {};
  final Map<String, String> _taskOutputs = {};

  /// The subjects of the todos created (TaskCreate), by their ids.
  final Map<String, String> _taskSubjects = {};

  /// The session's goal (`/goal`), as last reported.
  KernelGoal? _goal;

  /// What a kept session being replayed kept of its goal.
  final List<Map<String, Object?>> _goalRecords = [];

  /// The plan file the agent last wrote, in plan mode (see [isPlanPath]).
  String? _planPath;

  /// Whether [path] is a plan file: one in a `plans` folder, where Claude
  /// Code keeps them (`~/.claude/plans/`, or the `plansDirectory` set).
  static bool isPlanPath(String path) =>
      path.split(RegExp(r'[/\\]')).contains('plans');

  /// The round of planning under way: the id its card is at. Over once
  /// the plan is put to the user.
  String? _planRound;
  int _planRounds = 0;

  /// Each round's card, by its id.
  final Map<String, PlanItem> _plans = {};

  /// The card of the plan put to the user and not yet started nor sent
  /// back: the next message does one or the other.
  String? _awaitingPlan;

  /// The plan put to the user, for them to start; null when none is.
  PlanItem? get awaitingPlan => _plans[_awaitingPlan];

  /// What the CLI is told when the model puts its plan to the user (by
  /// `ClaudeCodeKernel`, at once): the user starts it, or says what should
  /// change, in a message of their own.
  static const planPresented =
      'Your plan is now shown to the user, who will start it or say what '
      'should change in their next message. End your turn here without '
      'repeating the plan: do not start implementing it, and do not call '
      'ExitPlanMode again.';

  /// Marks the note sent with the message that starts a plan.
  static const _planStarted = 'The user has started your plan';

  /// The note sent with the message that starts the plan in [path]: not
  /// shown, it tells the model planning is over.
  static String planStartedNote(String path) =>
      '<system-reminder>$_planStarted: plan mode is over. Carry out the '
      '${path.isEmpty ? 'plan you put to them' : 'plan in $path'} now.'
      '</system-reminder>';

  /// Whether [text] says the plan is started (see [planStartedNote]).
  static bool startsPlan(String text) => text.contains(_planStarted);

  /// The card each call that wrote the plan or put it to the user is on.
  final Map<String, String> _planCalls = {};

  /// Whether a call of [name] with [input] is one of a round of planning:
  /// it writes the plan, or puts the plan written to the user.
  bool _isPlanCall(String name, Map<String, Object?> input) => switch (name) {
    'Edit' ||
    'MultiEdit' ||
    'Write' => isPlanPath(_string(input['file_path']) ?? ''),
    // Its plan sent rather than written (no file named): the plan all the
    // same, to start.
    'ExitPlanMode' =>
      _planPath != null ||
          _string(input['planFilePath']) != null ||
          _string(input['plan']) != null,
    _ => false,
  };

  /// [id], a call of [name] that writes the plan or puts it to the user,
  /// on the card of the round under way (a new round's if none is).
  void _planCall(String id, String name, Map<String, Object?> input) {
    final proposes = name == 'ExitPlanMode';
    final known = _planCalls[id];
    final card = known ?? _planRound ?? id;
    var plan =
        _plans[card] ??
        PlanItem(
          // Put to the user, the CLI names its file; none when it was
          // sent rather than written.
          path:
              _string(input['file_path']) ??
              _string(input['planFilePath']) ??
              _planPath ??
              '',
          round: ++_planRounds,
        );
    // An edit changes the text once; written whole, it is the text.
    var text = _string(input[proposes ? 'plan' : 'content']);
    if (known == null) {
      _planCalls[id] = card;
      _planRound = card;
      if (!proposes) plan = plan.copyWith(writes: plan.writes + 1);
      if (name == 'Edit' || name == 'MultiEdit') {
        text = _planEdited(_planText, input);
      }
      // Its own row (its streamed start's) gives way to the card.
      if (card != id) emit(ItemRemoved(nextSeq(), id));
    }
    if (text != null) _planText = text;
    final putToUser = proposes && plan.status == PlanStatus.drafting;
    plan = plan.copyWith(
      title: PlanItem.titleOf(text),
      text: text,
      status: putToUser ? PlanStatus.awaiting : null,
    );
    if (putToUser) _awaitingPlan = card;
    _plans[card] = plan;
    _put(card, plan);
  }

  /// The plan's text as last written, across rounds; null until written
  /// whole.
  String? _planText;

  /// [text] with the edit (or a MultiEdit's edits) of [input] made to it;
  /// null when [text] is unknown, or an edit's text is not in it.
  static String? _planEdited(String? text, Map<String, Object?> input) {
    final edits = switch (input['edits']) {
      final List<Object?> edits => [for (final edit in edits) _map(edit)],
      _ => [input],
    };
    var edited = text;
    for (final edit in edits) {
      final old = _string(edit['old_string']);
      final replacement = _string(edit['new_string']) ?? '';
      if (edited == null || old == null || !edited.contains(old)) return null;
      edited = edit['replace_all'] == true
          ? edited.replaceAll(old, replacement)
          : edited.replaceFirst(old, replacement);
    }
    return edited;
  }

  /// What a call of a round of planning on [card] returned: the plan
  /// written, or put to the user. (A session kept from before plans were
  /// put to the user without waiting has their answer here.)
  void _planResult(String card, _Tool tool, _Outcome outcome, String text) {
    final plan = _plans[card]!;
    if (tool.name == 'ExitPlanMode') {
      if (_planRound == card) _planRound = null;
      // Put to the user: it awaits their next message.
      if (text.contains(planPresented)) return;
      _resolvePlan(
        card,
        outcome == _Outcome.done
            ? plan.copyWith(status: PlanStatus.approved)
            : plan.copyWith(
                status: PlanStatus.sentBack,
                feedback: _planFeedback(text),
              ),
      );
      return;
    }
    if (outcome != _Outcome.done) return;
    final path = _string(tool.input['file_path'])!;
    _planPath = path;
    if (!replaying) emit(PlanWritten(nextSeq(), path));
  }

  /// [card] as [plan], its round over.
  void _resolvePlan(String card, PlanItem plan) {
    if (_awaitingPlan == card) _awaitingPlan = null;
    _plans[card] = plan;
    _put(card, plan);
  }

  /// The plan awaiting the user, started ([feedback] null) or sent back
  /// with what they said.
  void _answerPlan({String? feedback}) {
    final card = _awaitingPlan;
    if (card == null) return;
    final plan = _plans[card]!;
    _resolvePlan(
      card,
      feedback == null
          ? plan.copyWith(status: PlanStatus.approved)
          : plan.copyWith(status: PlanStatus.sentBack, feedback: feedback),
    );
  }

  /// What the user said should change in a plan sent back, as the kernel
  /// told the CLI when it waited on them.
  static String? _planFeedback(String text) {
    const said = 'keep planning: ';
    final at = text.indexOf(said);
    if (at < 0) return null;
    final feedback = text.substring(at + said.length).trim();
    return feedback.isEmpty ? null : feedback;
  }

  void translate(Map<String, Object?> message) {
    final parent = message['parent_tool_use_id'] as String?;
    switch (message['type']) {
      case 'stream_event' when parent == null:
        _streamEvent(_map(message['event']));
      case 'assistant':
        _assistant(message, parent);
        _replayedAt(message);
      case 'user':
        _user(message, parent);
        _replayedAt(message);
      case 'system':
        _system(message);
      // Kept beside a session's messages: how its goal stood.
      case 'attachment' when replaying:
        if (_map(message['attachment'])['type'] == 'goal_status') {
          _goalRecords.add(message);
        }
    }
  }

  // --- Turn times, replaying ------------------------------------------------------
  //
  // A kept session says nothing of its turns: one is timed from its prompt
  // to the last thing it showed before the next one (or the end).

  /// The prompt whose turn is being replayed, and when it was sent.
  ({String id, UserMessageItem item, DateTime? at})? _replayed;

  /// When the replayed turn last showed anything.
  DateTime? _replayedUntil;

  /// The user stopped the replayed turn: it is not timed.
  bool _replayedStopped = false;

  /// A page of the kept session is replayed, not all of it: times its last
  /// turn, nothing else.
  void endPage() => _timeReplayed();

  /// The kept session is all replayed: times its last turn, and has its
  /// goal as it stood (one met or given up on, nothing to show any more).
  void endReplay() {
    endPage();
    reportGoal(keptGoal(_goalRecords, seen: _goalRecords.length));
    _goalRecords.clear();
  }

  /// When [message] (the user's) was sent: as kept; live, now.
  DateTime? _sentAt(Map<String, Object?> message) =>
      DateTime.tryParse('${message['timestamp']}')?.toLocal() ??
      (replaying ? null : DateTime.now());

  void _replayedAt(Map<String, Object?> message) {
    if (!replaying || _replayed == null) return;
    if (message['uuid'] == _replayed!.id) return;
    if (DateTime.tryParse('${message['timestamp']}') case final at?) {
      _replayedUntil = at;
    }
  }

  /// Replaying [id], a prompt: times the turn before it.
  void _replayPrompt(
    String id,
    UserMessageItem item,
    Map<String, Object?> message,
  ) {
    _timeReplayed();
    _replayed = (
      id: id,
      item: item,
      at: DateTime.tryParse('${message['timestamp']}'),
    );
  }

  void _timeReplayed() {
    final turn = _replayed;
    final until = _replayedUntil;
    final stopped = _replayedStopped;
    _replayed = null;
    _replayedUntil = null;
    _replayedStopped = false;
    if (turn == null || stopped) return;
    // As its footer showed it when it ended, where that was kept.
    if (keptTurns[turn.id] case (:final worked, :final usage)) {
      _put(turn.id, turn.item.copyWith(worked: worked, usage: usage));
      return;
    }
    final at = turn.at;
    if (until == null || at == null) return;
    final worked = until.difference(at);
    if (worked > Duration.zero) {
      _put(turn.id, turn.item.copyWith(worked: worked));
    }
  }

  /// Settles whatever still streams, e.g. when the turn is interrupted: a
  /// call left unanswered shows as failed, unless a subagent at work in the
  /// background (which goes on) made it.
  void settle() {
    // A message cut off: what it had used still counts.
    if (_messageUsage.isNotEmpty) _endMessage();
    for (final id in [..._thoughts.keys]) {
      _completeThought(id, null);
    }
    for (final id in [..._textLength.keys]) {
      _textLength.remove(id);
      emit(ItemCompleted(nextSeq(), id));
    }
    for (final id in [..._unanswered]) {
      if (_inBackground(id)) continue;
      _toolResult({'tool_use_id': id, 'is_error': true}, null);
    }
    _streamed.clear();
    _activity = null;
  }

  /// Whether the call [id] is, or is made by, a subagent at work in the
  /// background.
  bool _inBackground(String id) {
    for (String? at = id; at != null; at = _tools[at]?.parent) {
      if (_agents[at]?.item.background ?? false) return true;
    }
    return false;
  }

  // --- Items -------------------------------------------------------------------

  /// Adds or replaces [id], at the top level or in the subagent [parent].
  void _put(
    String id,
    ChatItem item, {
    String? parent,
    bool streaming = false,
  }) {
    if (parent != null) {
      final agent = _agents[parent];
      if (agent == null) return; // A subagent's message we cannot place.
      agent.children[id] = item;
      _putAgent(parent);
      return;
    }
    emit(ItemUpserted(nextSeq(), id, item, streaming: streaming));
  }

  void _putAgent(String id) {
    final agent = _agents[id]!;
    agent.item = agent.item.copyWith(children: [...agent.children.values]);
    _put(id, agent.item, parent: _tools[id]?.parent);
  }

  // --- Streaming ---------------------------------------------------------------

  void _streamEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'message_start':
        final message = _map(event['message']);
        _messageId = message['id'] as String?;
        _streamed.clear();
        _blockSince = DateTime.now();
        _messageUsage = {..._map(message['usage'])};
        _messageCounted = false;
        _messageThinking = null;
        _messageThought = false;
        _meter.startMessage();
      case 'message_delta':
        final usage = _map(event['usage']);
        for (final MapEntry(:key, :value) in usage.entries) {
          if (claudeNumber(value) != null) _messageUsage[key] = value;
        }
        if (claudeNumber(usage['output_tokens']) != null) {
          _messageCounted = true;
        }
        if (claudeInt(_map(usage['output_tokens_details'])['thinking_tokens'])
            case final tokens?) {
          _messageThinking = tokens;
        }
      case 'message_stop':
        _endMessage();
      case 'content_block_start':
        final index = claudeInt(event['index']) ?? 0;
        final block = _map(event['content_block']);
        final id = '$_messageId:$index';
        switch (block['type']) {
          case 'thinking' || 'redacted_thinking':
            _messageThought = true;
            _streamed[index] = id;
            (_unclaimed['$_messageId:thinking'] ??= []).add(id);
            _thoughts[id] = StringBuffer();
            // A proxy may hold a whole thought back until it is done.
            _thinkingStarted[id] = _blockSince ?? DateTime.now();
            _put(
              id,
              ThinkingItem(
                text: '',
                tokens: 0,
                startedAt: _thinkingStarted[id],
              ),
              streaming: true,
            );
          case 'text':
            if (!replaying) _meter.startBlock();
            _streamed[index] = id;
            (_unclaimed['$_messageId:text'] ??= []).add(id);
            _textLength[id] = 0;
            _put(id, const AssistantTextItem(''), streaming: true);
          case 'tool_use':
            // Its input may come all at once as it ends: timed from here.
            if (!replaying) _meter.startBlock();
            final toolId = block['id'] as String;
            final name = block['name'] as String;
            if (!_tools.containsKey(toolId)) {
              _toolUse(toolId, name, const {}, null);
            }
          default:
            return;
        }
        // The model answers: what it does shows from here. Not from its
        // message's start, which a proxy may send minutes before the first
        // block (holding back a thought until it is done).
        _report(null);
      case 'content_block_delta':
        final delta = _map(event['delta']);
        _meterDelta(delta);
        final id = _streamed[claudeInt(event['index']) ?? 0];
        if (id == null) return;
        switch (delta['type']) {
          case 'thinking_delta':
            final thought = _thoughts[id];
            if (thought == null) return;
            final text = delta['thinking'] as String? ?? '';
            final offset = thought.length;
            thought.write(text);
            emit(
              TextDelta(
                nextSeq(),
                id,
                offset,
                text,
                tokens: math.max(_thinkingTokens[id] ?? 0, thought.length ~/ 4),
              ),
            );
          case 'text_delta':
            final offset = _textLength[id];
            if (offset == null) return;
            final text = delta['text'] as String? ?? '';
            _textLength[id] = offset + text.length;
            emit(TextDelta(nextSeq(), id, offset, text));
        }
      case 'content_block_stop':
        _blockSince = DateTime.now();
        final id = _streamed.remove(claudeInt(event['index']) ?? 0);
        if (id == null) return;
        if (_thoughts.containsKey(id)) {
          _completeThought(id, null);
        } else if (_textLength.remove(id) != null) {
          emit(ItemCompleted(nextSeq(), id));
        }
    }
  }

  /// Meters [delta]'s text, and reports what is written now and then.
  void _meterDelta(Map<String, Object?> delta) {
    if (replaying) return;
    switch (delta) {
      case {'type': 'text_delta', 'text': final String text}:
        _meter.streamed(text);
      case {'type': 'input_json_delta', 'partial_json': final String json}:
        _meter.streamed(json);
      case {'type': 'thinking_delta', 'thinking': final String thought}:
        _meter.streamed(thought, timed: false);
      default:
        return;
    }
    final now = DateTime.now();
    if (_outputReported case final at? when now.difference(at) < _outputEvery) {
      return;
    }
    _reportOutput(now);
  }

  void _reportOutput([DateTime? now]) {
    if (replaying) return;
    _outputReported = now ?? DateTime.now();
    emit(OutputReported(nextSeq(), _meter.output));
  }

  /// Adds the message ended to the turn's usage.
  void _endMessage() {
    int count(String key) => claudeInt(_messageUsage[key]) ?? 0;
    final output = count('output_tokens');
    _turnInput +=
        count('input_tokens') +
        count('cache_creation_input_tokens') +
        count('cache_read_input_tokens');
    _turnOutput += output;
    _meter.endMessage(
      // Cut off before its count: as guessed.
      tokens: _messageCounted ? output : null,
      // Its text's and calls', told apart from its thoughts'.
      written: switch (_messageThinking) {
        final thinking? => output - thinking,
        null when !_messageThought => output,
        null => null,
      },
    );
    _messageUsage = {};
    _messageCounted = false;
    _messageThinking = null;
    _messageThought = false;
    _reportOutput();
  }

  void _resetUsage() {
    _messageUsage = {};
    _messageCounted = false;
    _messageThinking = null;
    _messageThought = false;
    _turnInput = _turnOutput = 0;
    _meter.begin();
    _outputReported = null;
  }

  /// What the turn's requests spent, as streamed; null when none streamed.
  /// Its speed the average of that shown while it wrote.
  TurnUsage? get turnUsage => _turnInput == 0 && _turnOutput == 0
      ? null
      : TurnUsage(
          inputTokens: _turnInput,
          outputTokens: _turnOutput,
          tokensPerSecond: _meter.averageSpeed,
        );

  void _completeThought(String id, String? whole) {
    final streamed = _thoughts.remove(id)?.toString() ?? '';
    final started = _thinkingStarted.remove(id);
    final text = (whole == null || whole.isEmpty) ? streamed : whole;
    final tokens = math.max(_thinkingTokens.remove(id) ?? 0, text.length ~/ 4);
    emit(
      ItemCompleted(
        nextSeq(),
        id,
        item: ThinkingItem(
          text: text,
          tokens: tokens,
          seconds: math.max(
            1,
            started == null
                ? 0
                : (DateTime.now().difference(started).inMilliseconds / 1000)
                      .round(),
          ),
        ),
      ),
    );
  }

  // --- Whole messages -----------------------------------------------------------

  void _assistant(Map<String, Object?> message, String? parent) {
    final body = _map(message['message']);
    final messageId = body['id'] as String? ?? '${message['uuid']}';
    final eventId = message['uuid'] as String? ?? messageId;
    final synthetic = body['model'] == '<synthetic>';
    for (final (index, raw) in _list(body['content']).indexed) {
      final block = _map(raw);
      final kind = block['type'] == 'text' ? 'text' : 'thinking';
      final key = '$eventId:$index';
      final id = _blockIds[key] ??= switch (_unclaimed['$messageId:$kind']) {
        final ids? when ids.isNotEmpty => ids.removeAt(0),
        _ => key,
      };
      switch (block['type']) {
        case 'text':
          final text = block['text'] as String? ?? '';
          if (synthetic) {
            if (parent == null && _goalReply(text)) continue;
            if (text.isNotEmpty) {
              _put(id, NoticeItem(NoticeKind.command, text), parent: parent);
            }
          } else if (_textLength.remove(id) != null) {
            emit(ItemCompleted(nextSeq(), id, item: AssistantTextItem(text)));
          } else if (text.trim().isNotEmpty) {
            _put(id, AssistantTextItem(text), parent: parent);
          }
        case 'thinking' || 'redacted_thinking':
          final text = block['thinking'] as String? ?? '';
          if (_thoughts.containsKey(id)) {
            _completeThought(id, text);
          } else if (parent == null && text.trim().isNotEmpty) {
            _put(
              id,
              ThinkingItem(text: text, tokens: text.length ~/ 4, seconds: 1),
            );
          }
        case 'tool_use':
          _toolUse(
            block['id'] as String,
            block['name'] as String,
            _map(block['input']),
            parent,
          );
      }
    }
  }

  void _user(Map<String, Object?> message, String? parent) {
    final body = _map(message['message']);
    final content = body['content'];
    final result = message['tool_use_result'] ?? message['toolUseResult'];
    if (content is String) {
      _prompt(message, content, parent);
      return;
    }
    final texts = <String>[];
    final images = <ImageAttachment>[];
    final blocks = [for (final raw in _list(content)) _map(raw)];
    // Numbered as Claude Code numbered them when pasted in it.
    final pasted = _list(message['imagePasteIds']);
    int? label;
    var pictures = 0;
    var startsPlan = false;
    for (final (index, block) in blocks.indexed) {
      switch (block['type']) {
        case 'tool_result':
          _toolResult(block, result);
        case 'text':
          final text = block['text'] as String? ?? '';
          // A note for the model sent along (e.g. by the host), not typed.
          if (text.trimLeft().startsWith('<system-reminder>')) {
            if (ClaudeTranslator.startsPlan(text)) startsPlan = true;
            continue;
          }
          // An image's name before it (as this client sends them).
          if (imageReferencePattern.matchAsPrefix(text.trim()) case final match?
              when match.end == text.trim().length &&
                  index + 1 < blocks.length &&
                  blocks[index + 1]['type'] == 'image') {
            label = int.parse(match[1]!);
            continue;
          }
          texts.add(text);
        case 'image':
          final number =
              label ??
              switch (pasted.elementAtOrNull(pictures)) {
                final int id => id,
                _ => null,
              };
          pictures++;
          label = null;
          if (_image(_map(block['source'])) case final image?) {
            images.add(number == null ? image : image.withNumber(number));
          }
      }
    }
    if (startsPlan && parent == null) _answerPlan();
    if (texts.isNotEmpty || images.isNotEmpty) {
      _prompt(message, texts.join('\n'), parent, images: images);
    }
  }

  static ImageAttachment? _image(Map<String, Object?> source) {
    if (source['type'] != 'base64') return null;
    try {
      return ImageAttachment(
        bytes: base64Decode(source['data'] as String? ?? ''),
        mediaType: source['media_type'] as String? ?? 'image/png',
      );
    } on FormatException {
      return null;
    }
  }

  /// A message the user sent (or the CLI sent for them).
  void _prompt(
    Map<String, Object?> message,
    String text,
    String? parent, {
    List<ImageAttachment> images = const [],
  }) {
    if (parent != null) return;
    // The goal checked and not met yet (a note for the model).
    if (text.startsWith(_goalFeedback)) {
      if (!replaying) goalSaid?.call();
      return;
    }
    if (message['isMeta'] == true) return;
    final id = message['uuid'] as String?;
    if (id == null) return;
    final trimmed = text.trim();
    if (trimmed.startsWith('<task-notification>')) {
      // What the agent does about it is a turn of its own.
      if (replaying) _timeReplayed();
      _agentNotified(trimmed);
      return;
    }
    // Written by the CLI, not typed: e.g. the summary a compacted
    // conversation goes on from. Live it is marked synthetic; kept, by
    // what it is.
    if (message['isSynthetic'] == true ||
        message['isCompactSummary'] == true ||
        message['isVisibleInTranscriptOnly'] == true) {
      return;
    }
    if (trimmed.startsWith('<local-command-caveat>') ||
        trimmed.startsWith('<system-reminder>')) {
      return;
    }
    if (trimmed.contains('<command-name>')) {
      final name = _tag(trimmed, 'command-name') ?? '';
      final args = _tag(trimmed, 'command-args') ?? '';
      final command = name.startsWith('/') ? name : '/$name';
      // Asking how the goal stands (as this client does after a turn): the
      // answer shows in the goal's bar, not here.
      if (command == '/goal' && args.trim().isEmpty) return;
      // Images sent with it ride along (e.g. `/goal [Image #1] …`).
      final item = UserMessageItem(
        text: args.isEmpty ? command : '$command $args',
        images: images,
        sentAt: _sentAt(message),
      );
      _answerPlan(feedback: item.text);
      _put(id, item);
      if (replaying) _replayPrompt(id, item, message);
      return;
    }
    if (_tag(trimmed, 'local-command-stdout') case final output?) {
      if (_goalReply(output)) return;
      if (output.trim().isNotEmpty) {
        _put(id, NoticeItem(NoticeKind.command, output.trim()));
      }
      return;
    }
    // The CLI's note to the model that the user stopped it: not shown.
    if (trimmed.startsWith('[Request interrupted by user')) {
      if (replaying) _replayedStopped = true;
      return;
    }
    final item = UserMessageItem(
      text: trimmed,
      images: images,
      sentAt: _sentAt(message),
    );
    // Said with a plan awaiting: what should change in it.
    _answerPlan(feedback: trimmed);
    _put(id, item);
    if (replaying) _replayPrompt(id, item, message);
  }

  // --- Tools ----------------------------------------------------------------------

  void _toolUse(
    String id,
    String name,
    Map<String, Object?> input,
    String? parent,
  ) {
    final known = _tools[id];
    // The streamed start has no input yet; the whole message fills it in.
    final tool = _Tool(
      id,
      name,
      input,
      known?.parent ?? parent,
      known?.startedAt,
    );
    _tools[id] = tool;
    if (tool.parent == null && _isPlanCall(name, input)) {
      return _planCall(id, name, input);
    }
    if (known == null && !replaying) _unanswered.add(id);
    switch (name) {
      case 'Agent' || 'Task':
        final agent = _agents[id] ??= _Agent(
          AgentItem(
            description: _string(input['description']) ?? 'Subagent',
            id: id,
            agentType: _string(input['subagent_type']),
            prompt: _string(input['prompt']),
            status: replaying ? CommandStatus.succeeded : CommandStatus.running,
            startedAt: replaying ? null : tool.startedAt,
            background: input['run_in_background'] == true,
          ),
        );
        // The streamed start has no input: the whole message fills it in.
        if (agent.item.description == 'Subagent' || agent.item.prompt == null) {
          agent.item = agent.item.copyWith(
            description: _string(input['description']),
            agentType: _string(input['subagent_type']),
            prompt: _string(input['prompt']),
          );
        }
        _putAgent(id);
        return;
      // Not written to a file (see [_planCall]): the plan is said.
      case 'ExitPlanMode':
        if (_string(input['plan']) case final plan?) {
          _put(id, AssistantTextItem(plan), parent: tool.parent);
          return;
        }
    }
    _put(
      id,
      _toolItem(tool, replaying ? _Outcome.done : _Outcome.running),
      parent: tool.parent,
    );
  }

  ChatItem _toolItem(
    _Tool tool,
    _Outcome outcome, {
    String? output,
    List<ImageAttachment> images = const [],
    List<String> imageFiles = const [],
  }) {
    final input = tool.input;
    final status = switch (outcome) {
      _Outcome.running => ToolStatus.running,
      _Outcome.done => ToolStatus.succeeded,
      _Outcome.failed => ToolStatus.failed,
      _Outcome.denied => ToolStatus.denied,
    };
    // What it did, or does while it runs.
    String tense(String done, String doing) =>
        outcome == _Outcome.running ? doing : done;
    String? path(String key) => _string(input[key]);
    String base(String? path) => path == null ? '' : path.split('/').last;
    final name = tool.name;
    // The app's own, shown as it says.
    if (ClaudeSdkTools.called(name) case ClaudeSdkTool(
      :final name,
      :final kind?,
      :final summary,
      :final files,
    )) {
      final said = _string(input['description'])?.trim() ?? '';
      return ToolCallItem(
        kind: kind,
        tool: name,
        callId: tool.id,
        input: input,
        // Said by the agent, it is the line, whole.
        label: said.isEmpty ? null : '',
        target: said.isNotEmpty ? said : summary?.call(input, output) ?? '',
        status: status,
        output: output,
        images: images,
        imageFiles: switch ((files, output)) {
          (final files?, final output?) => files(output),
          _ => imageFiles,
        },
      );
    }
    if (name.startsWith('mcp__')) {
      final parts = name.split('__');
      return ToolCallItem(
        kind: ToolKind.mcp,
        label: parts.length > 2
            ? '${parts[1]} · ${parts.sublist(2).join('__')}'
            : name,
        target: _summary(input),
        status: status,
        output: output,
        images: images,
        imageFiles: imageFiles,
      );
    }
    return switch (name) {
      'Read' => ToolCallItem(
        kind: ToolKind.read,
        target: base(path('file_path')),
        path: path('file_path'),
        detail: switch ((input['offset'], input['limit'])) {
          (final int offset, final int limit) => 'L$offset-${offset + limit}',
          _ => null,
        },
        status: status,
        output: outcome == _Outcome.done ? null : output,
        // An image file, as the agent saw it.
        images: images,
        imageFiles: imageFiles,
      ),
      'Grep' => ToolCallItem(
        kind: ToolKind.grep,
        target: _string(input['pattern']) ?? '',
        status: status,
        output: output,
      ),
      'Glob' => ToolCallItem(
        kind: ToolKind.search,
        label: tense('Globbed', 'Globbing'),
        target: _string(input['pattern']) ?? '',
        status: status,
        output: output,
      ),
      'LS' => ToolCallItem(
        kind: ToolKind.listDir,
        target: base(path('path')),
        path: path('path'),
        status: status,
      ),
      'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit' => ToolCallItem(
        kind: ToolKind.edit,
        label: name == 'Write'
            ? tense('Wrote', 'Writing')
            : tense('Edited', 'Editing'),
        target: base(path('file_path') ?? path('notebook_path')),
        path: path('file_path') ?? path('notebook_path'),
        status: status,
        output: output,
      ),
      'Bash' => TerminalItem(
        command: _string(input['command']) ?? '',
        description: _string(input['description']),
        output: output ?? '',
        status: switch (outcome) {
          _Outcome.running => CommandStatus.running,
          _Outcome.done => CommandStatus.succeeded,
          _ => CommandStatus.failed,
        },
        background: input['run_in_background'] == true,
        startedAt: tool.startedAt,
      ),
      'BashOutput' || 'TaskOutput' => ToolCallItem(
        kind: ToolKind.command,
        label: tense('Read output', 'Reading output'),
        target: _summary(input),
        status: status,
      ),
      'KillShell' || 'KillBash' || 'TaskStop' => ToolCallItem(
        kind: ToolKind.command,
        label: tense('Stopped', 'Stopping'),
        target: _summary(input),
        status: status,
      ),
      'WebFetch' => ToolCallItem(
        kind: ToolKind.web,
        label: tense('Fetched', 'Fetching'),
        target: _string(input['url']) ?? '',
        status: status,
        output: output,
      ),
      'WebSearch' => ToolCallItem(
        kind: ToolKind.web,
        label: tense('Searched the web', 'Searching the web'),
        target: _string(input['query']) ?? '',
        status: status,
        output: output,
      ),
      'Skill' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Used skill', 'Using skill'),
        target: _string(input['skill']) ?? _string(input['command']) ?? '',
        status: status,
      ),
      'ToolSearch' => ToolCallItem(
        kind: ToolKind.search,
        label: tense('Looked up tools', 'Looking up tools'),
        target: _string(input['query']) ?? '',
        status: status,
      ),
      // The list written, as text: not kept anywhere else. Its line says
      // what is in progress; what it does, by [tool] and [input] (see
      // todoStep).
      'TodoWrite' => ToolCallItem(
        kind: ToolKind.todo,
        tool: name,
        input: input,
        target:
            [
              for (final raw in _list(input['todos']))
                if (_map(raw)['status'] == 'in_progress')
                  _string(_map(raw)['content']) ?? '',
            ].firstOrNull ??
            '',
        status: status,
        output: status == ToolStatus.failed
            ? output
            : _todoList(input['todos']),
      ),
      // One item a call: named by its subject, the one it was created
      // with when the call gives only its id.
      'TaskCreate' || 'TaskUpdate' || 'TaskList' || 'TaskGet' => ToolCallItem(
        kind: ToolKind.todo,
        tool: name,
        input: input,
        target:
            _string(input['subject']) ??
            switch (_string(input['taskId'])) {
              final id? => _taskSubjects[id] ?? '#$id',
              null => '',
            },
        status: status,
        output: output,
      ),
      'AskUserQuestion' => ToolCallItem(
        kind: ToolKind.question,
        target: [
          for (final q in _list(input['questions']))
            _string(_map(q)['header']) ?? _string(_map(q)['question']) ?? '',
        ].join(' · '),
        status: status,
        output: output,
      ),
      // "Said …": what it says, on a line; opened, all of it (what sending
      // it returned only if it failed).
      'SendMessage' => switch (_string(input['message'])?.trim()) {
        final message? when message.isNotEmpty => ToolCallItem(
          kind: ToolKind.message,
          target: message.replaceAll(RegExp(r'\s+'), ' '),
          status: status,
          output: status == ToolStatus.failed ? output : message,
        ),
        // Not words (e.g. a request to shut down): what it is for.
        _ => ToolCallItem(
          kind: ToolKind.message,
          target: _string(input['summary']) ?? _summary(input),
          status: status,
          output: output,
        ),
      },
      // A goal the model proposes, for the user to set (Claude Code asks
      // only in its terminal: here, the step's button sets it).
      'ProposeGoal' => ToolCallItem(
        kind: ToolKind.goal,
        target: (_string(input['condition']) ?? '').trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        ),
        status: outcome == _Outcome.running
            ? ToolStatus.running
            : ToolStatus.succeeded,
        output: _string(input['condition'])?.trim(),
      ),
      'EnterPlanMode' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Entered plan mode', 'Entering plan mode'),
        target: '',
        status: status,
      ),
      'ExitPlanMode' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Proposed a plan', 'Proposing a plan'),
        target: '',
        status: status,
      ),
      _ => ToolCallItem(
        kind: ToolKind.other,
        label: name,
        target: _summary(input),
        status: status,
        output: output,
        images: images,
        imageFiles: imageFiles,
      ),
    };
  }

  void _toolResult(Map<String, Object?> block, Object? result) {
    final id = block['tool_use_id'] as String?;
    final tool = id == null ? null : _tools[id];
    if (id == null || tool == null) return;
    _unanswered.remove(id);
    final error = block['is_error'] == true;
    final text = _resultText(block['content']);
    final structured = result is Map ? result.cast<String, Object?>() : null;
    final outcome =
        _denied.contains(id) ||
            (tool.name == 'AskUserQuestion' && text.contains(unattendedAnswer))
        ? _Outcome.denied
        : error
        ? _Outcome.failed
        : _Outcome.done;
    if (_planCalls[id] case final card?) {
      return _planResult(card, tool, outcome, text);
    }
    switch (tool.name) {
      case 'Agent' || 'Task':
        final agent = _agents[id];
        if (agent == null) return;
        if (_string(structured?['agentId']) case final agentId?) {
          _agentCalls[agentId] = id;
        }
        if (structured?['status'] == 'async_launched') {
          // Launched in the background: what it says is for the agent (its
          // id, where its output goes). It reports in a notification.
          agent.item = agent.item.copyWith(
            prompt: _string(structured?['prompt']),
            model: _string(structured?['resolvedModel']),
            background: true,
          );
          _putAgent(id);
          return;
        }
        // What it did by commands, or edits whose patches it did not
        // send, is looked for.
        if (!replaying) emit(FilesMayHaveChanged(nextSeq()));
        agent.item = agent.item.copyWith(
          status: outcome == _Outcome.done
              ? CommandStatus.succeeded
              : CommandStatus.failed,
          result: _agentReport(structured, text),
          prompt: _string(structured?['prompt']),
          tokens: claudeInt(structured?['totalTokens']),
          toolUses: claudeInt(structured?['totalToolUseCount']),
          duration: switch (claudeInt(structured?['totalDurationMs'])) {
            final ms? => Duration(milliseconds: ms),
            _ => null,
          },
          model: _string(structured?['resolvedModel']),
        );
        _putAgent(id);
        return;
      case 'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit'
          when outcome == _Outcome.done && structured != null:
        if (_diff(id, tool, structured)) return;
      // A subagent's: its result has no patch, the input says what it did.
      case 'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit'
          when outcome == _Outcome.done && !replaying:
        if (_editOf(tool) case final change?) {
          emit(
            FileEdited(
              nextSeq(),
              change,
              turnId: turnId,
              original: _originalOf(tool),
            ),
          );
        }
      case 'Grep' || 'Glob' when outcome == _Outcome.done:
        final matches = _matches(tool.name, structured, text);
        final item = _toolItem(tool, outcome) as ToolCallItem;
        _put(
          id,
          ToolCallItem(
            kind: item.kind,
            label: item.label,
            target: item.target,
            detail:
                '${matches.length} ${tool.name == 'Glob' ? 'files' : 'results'}',
            results: matches,
            status: item.status,
          ),
          parent: tool.parent,
        );
        return;
      case 'Bash':
        final taskId = structured?['backgroundTaskId'] as String?;
        if (taskId != null && !replaying) {
          final outputFile =
              _string(structured?['outputFile']) ??
              RegExp(r'Output is being written to: (.+?\.output)(?:\.|\s|$)')
                  .firstMatch(text)
                  ?.group(1);
          if (outputFile != null) {
            _taskOutputs[taskId] = outputFile;
            if (_tasks[taskId] case final task?) {
              _tasks[taskId] = task.copyWith(outputFile: outputFile);
              _reportTasks();
            }
          }
          _put(
            id,
            TerminalItem(
              command: _string(tool.input['command']) ?? '',
              description: _string(tool.input['description']),
              output: 'Running in the background ($taskId)…',
              status: CommandStatus.running,
              background: true,
              startedAt: tool.startedAt,
            ),
            parent: tool.parent,
          );
          return;
        }
        if (!replaying) emit(FilesMayHaveChanged(nextSeq()));
        final stdout = _string(structured?['stdout']) ?? '';
        final stderr = _string(structured?['stderr']) ?? '';
        final output = structured == null
            ? text
            : [stdout, stderr].where((s) => s.isNotEmpty).join('\n');
        final interrupted = structured?['interrupted'] == true;
        _put(
          id,
          _toolItem(
            tool,
            interrupted ? _Outcome.failed : outcome,
            output: _tail(output),
          ),
          parent: tool.parent,
        );
        return;
      case 'ExitPlanMode':
        if (_string(tool.input['plan']) != null) return;
      case 'TaskCreate':
        if ((structured?['task'], _string(tool.input['subject'])) case (
          final Map<Object?, Object?> task,
          final subject?,
        )) {
          _taskSubjects['${task['id']}'] = subject;
        }
    }
    _put(
      id,
      _toolItem(
        tool,
        outcome,
        output: outcome == _Outcome.done ? _short(text) : _tail(text),
        images: _resultImages(block['content']),
        imageFiles: _savedImages(block['content']),
      ),
      parent: tool.parent,
    );
  }

  /// An edit as its input tells it, for one whose result has no patch (a
  /// subagent's): the file, and its lines as the input has them (the
  /// review counts them again from the files).
  static FileChange? _editOf(_Tool tool) {
    final input = tool.input;
    final path = _string(input['file_path']) ?? _string(input['notebook_path']);
    if (path == null) return null;
    int lines(Object? text) => switch (text) {
      final String text when text.isNotEmpty =>
        '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1),
      _ => 0,
    };
    var added = 0;
    var removed = 0;
    switch (tool.name) {
      case 'Write':
        added = lines(input['content']);
      case 'Edit':
        added = lines(input['new_string']);
        removed = lines(input['old_string']);
      case 'MultiEdit':
        for (final edit in _list(input['edits']).whereType<Map>()) {
          added += lines(edit['new_string']);
          removed += lines(edit['old_string']);
        }
    }
    return FileChange(path: path, added: added, removed: removed);
  }

  /// What a subagent's edit's file was before, as its input tells: an
  /// Edit's or a MultiEdit's texts put back (not one that replaced every
  /// match); a Write's is not known.
  static FileOriginal? _originalOf(_Tool tool) {
    final input = tool.input;
    ({String before, String after})? edit(Object? raw) => switch (raw) {
      {'old_string': final String before, 'new_string': final String after}
          when raw['replace_all'] != true =>
        (before: before, after: after),
      _ => null,
    };
    final edits = switch (tool.name) {
      'Edit' => [edit(input)],
      'MultiEdit' => [for (final raw in _list(input['edits'])) edit(raw)],
      _ => const <({String before, String after})?>[],
    };
    if (edits.isEmpty || edits.contains(null)) return null;
    return OriginalByEdits(edits.nonNulls.toList());
  }

  /// An edit's result as a diff card and a pending change; false when it
  /// carries no patch to show.
  bool _diff(String id, _Tool tool, Map<String, Object?> result) {
    final path =
        _string(result['filePath']) ??
        _string(tool.input['file_path']) ??
        _string(tool.input['notebook_path']);
    if (path == null) return false;
    final lines = <DiffLine>[];
    var added = 0;
    var removed = 0;
    final hunks = _list(result['structuredPatch']);
    if (hunks.isEmpty && tool.name == 'NotebookEdit') {
      // A notebook edit tells the cell's source before and after, not a
      // patch (the file is JSON): its lines, compared.
      String source(String key) => _string(result[key]) ?? '';
      for (final line in _lineDiff(
        source('old_source'),
        source('new_source'),
      )) {
        switch (line.type) {
          case DiffLineType.added:
            added++;
          case DiffLineType.removed:
            removed++;
          case DiffLineType.context:
        }
        if (lines.length < _maxDiffLines) lines.add(line);
      }
    } else if (hunks.isEmpty && result['type'] == 'create') {
      final content = _string(result['content']) ?? '';
      final created = content.isEmpty ? <String>[] : content.split('\n');
      for (final (i, line) in created.take(_maxDiffLines).indexed) {
        lines.add(DiffLine(DiffLineType.added, i + 1, line));
      }
      added = created.length;
    } else {
      for (final raw in hunks) {
        final hunk = _map(raw);
        var oldLine = claudeInt(hunk['oldStart']) ?? 1;
        var newLine = claudeInt(hunk['newStart']) ?? 1;
        for (final line in _list(hunk['lines']).whereType<String>()) {
          if (line.isEmpty) continue;
          final text = line.substring(1);
          switch (line[0]) {
            case '+':
              added++;
              if (lines.length < _maxDiffLines) {
                lines.add(DiffLine(DiffLineType.added, newLine, text));
              }
              newLine++;
            case '-':
              removed++;
              if (lines.length < _maxDiffLines) {
                lines.add(DiffLine(DiffLineType.removed, oldLine, text));
              }
              oldLine++;
            case '\\':
              break;
            default:
              if (lines.length < _maxDiffLines) {
                lines.add(DiffLine(DiffLineType.context, newLine, text));
              }
              oldLine++;
              newLine++;
          }
        }
      }
    }
    if (lines.isEmpty) return false;
    final slash = path.lastIndexOf('/');
    _put(
      id,
      CodeDiffItem(
        fileName: path.substring(slash + 1),
        directory: slash < 0 ? '' : path.substring(0, slash),
        lines: lines,
        added: added,
        removed: removed,
      ),
      parent: tool.parent,
    );
    // A subagent's too: what it edits is in the review as the agent's.
    if (!replaying) {
      emit(
        FileEdited(
          nextSeq(),
          FileChange(path: path, added: added, removed: removed),
          turnId: turnId,
          original: _original(result),
        ),
      );
    }
    return true;
  }

  /// What an edit's file was before, as its result tells: a file written
  /// anew was not there, one edited is in `originalFile`.
  static FileOriginal? _original(Map<String, Object?> result) {
    if (result['type'] == 'create') return const OriginalText(null);
    if (_string(result['originalFile']) case final text?) {
      return OriginalText(text);
    }
    // An Edit that made the file.
    if (result.containsKey('originalFile') && result['oldString'] == '') {
      return const OriginalText(null);
    }
    return null;
  }

  static const _maxDiffLines = 400;

  /// [before] to [after], line by line: kept lines as context, numbered as
  /// in the text they are from. Past a size, all of one replaced by the
  /// other.
  static List<DiffLine> _lineDiff(String before, String after) {
    List<String> split(String text) => text.isEmpty ? [] : text.split('\n');
    final a = split(before);
    final b = split(after);
    // The longest common subsequence, from the end.
    final common = a.length * b.length <= 250000
        ? List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0))
        : null;
    if (common != null) {
      for (var i = a.length - 1; i >= 0; i--) {
        for (var j = b.length - 1; j >= 0; j--) {
          common[i][j] = a[i] == b[j]
              ? common[i + 1][j + 1] + 1
              : math.max(common[i + 1][j], common[i][j + 1]);
        }
      }
    }
    final lines = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < a.length || j < b.length) {
      if (common != null && i < a.length && j < b.length && a[i] == b[j]) {
        lines.add(DiffLine(DiffLineType.context, j + 1, b[j]));
        i++;
        j++;
      } else if (i < a.length &&
          (j == b.length ||
              common == null ||
              common[i + 1][j] >= common[i][j + 1])) {
        lines.add(DiffLine(DiffLineType.removed, i + 1, a[i]));
        i++;
      } else {
        lines.add(DiffLine(DiffLineType.added, j + 1, b[j]));
        j++;
      }
    }
    return lines;
  }

  // --- Runtime messages ------------------------------------------------------------

  /// Whether the CLI's [content] is a notice not shown: the one on auto
  /// mode's classifier billing, which it gives each session whose requests
  /// go through a gateway (ours, on this machine), nothing the user can do.
  static bool _unshownNotice(String content) =>
      content.contains('auto-mode-classifier-billing');

  void _system(Map<String, Object?> message) {
    final uuid = message['uuid'] as String? ?? '${nextSeq()}';
    switch (message['subtype']) {
      // A request to the model is out (until its answer starts), or the
      // conversation is being compacted (until the status clears).
      case 'status':
        switch (message['status']) {
          // Still waiting since the turn was sent: keep its clock.
          case 'requesting' when _activity?.kind != KernelActivityKind.waiting:
            _report(_waiting());
          case 'compacting':
            _report(
              KernelActivity(KernelActivityKind.compacting, DateTime.now()),
            );
          case null when _activity?.kind == KernelActivityKind.compacting:
            _report(null);
        }
      case 'compact_boundary':
        if (_activity?.kind == KernelActivityKind.compacting) _report(null);
        final meta = _map(message['compact_metadata']);
        final before = claudeInt(meta['pre_tokens']);
        final after = claudeInt(meta['post_tokens']);
        _put(
          uuid,
          NoticeItem(
            NoticeKind.compaction,
            [
              meta['trigger'] == 'auto'
                  ? 'Conversation compacted automatically'
                  : 'Conversation compacted',
              if (before != null)
                '${_tokens(before)}${after == null ? '' : ' → ${_tokens(after)}'} tokens',
            ].join(' · '),
          ),
        );
      case 'api_retry' when !replaying:
        final attempt = message['attempt'];
        final max = message['max_retries'];
        final delay = ((claudeInt(message['retry_delay_ms']) ?? 0) / 1000)
            .ceil();
        final status = message['error_status'];
        _put(
          'retry:$turnId',
          NoticeItem(
            NoticeKind.retry,
            'Request failed${status == null ? '' : ' ($status)'}; '
            'retrying in ${delay}s (attempt $attempt of $max)',
          ),
        );
      case 'informational':
        final level = message['level'];
        final content = _string(message['content']);
        if (level == 'info' || content == null || content.isEmpty) return;
        if (_unshownNotice(content)) return;
        _put(
          uuid,
          NoticeItem(
            level == 'warning' ? NoticeKind.warning : NoticeKind.info,
            content,
          ),
        );
      case 'notification' when !replaying:
        if (_string(message['text']) case final text? when text.isNotEmpty) {
          _put(
            'notification:${message['key'] ?? uuid}',
            NoticeItem(NoticeKind.info, text),
          );
        }
      case 'local_command_output':
        if (_string(message['content']) case final text? when text.isNotEmpty) {
          _put(uuid, NoticeItem(NoticeKind.command, text));
        }
      case 'permission_denied':
        final id = message['tool_use_id'] as String?;
        final tool = id == null ? null : _tools[id];
        if (id == null || tool == null) return;
        _denied.add(id);
        // A round of planning's card says what became of it.
        if (_planCalls.containsKey(id)) return;
        _put(id, _toolItem(tool, _Outcome.denied), parent: tool.parent);
      case 'thinking_tokens':
        final estimate = claudeInt(message['estimated_tokens']);
        final id = _thoughts.keys.lastOrNull;
        if (estimate == null || id == null) return;
        _thinkingTokens[id] = estimate;
        emit(
          ItemUpserted(
            nextSeq(),
            id,
            ThinkingItem(
              text: _thoughts[id].toString(),
              tokens: estimate,
              startedAt: _thinkingStarted[id],
            ),
            streaming: true,
          ),
        );
      case 'task_started' when !replaying:
        final taskId = message['task_id'] as String;
        final agent = message['task_type'] == 'local_agent';
        final call = message['tool_use_id'] as String?;
        // A subagent's task is its card's, continued or not.
        final card = agent ? _agentCard(taskId, call) : null;
        if (card != null) _agentCalls[taskId] = card;
        _tasks[taskId] = KernelTask(
          id: taskId,
          description: _string(message['description']) ?? '',
          kind: agent
              ? KernelTaskKind.agent
              : message['task_type'] == 'local_bash'
              ? KernelTaskKind.command
              : KernelTaskKind.other,
          status: CommandStatus.running,
          startedAt: DateTime.now(),
          toolUseId: card ?? call,
          background: message['is_backgrounded'] == true,
          outputFile: _string(message['output_file']) ?? _taskOutputs[taskId],
        );
        _reportTasks();
        // Continued: at work again, in its card.
        if (_agents[card] case final continued? when card != call) {
          continued.item = continued.item.copyWith(
            status: CommandStatus.running,
          );
          _putAgent(card!);
        }
        if (message['is_backgrounded'] == true) {
          _agentToBackground(card ?? call);
        }
      case 'task_progress' when !replaying:
        final taskId = message['task_id'] as String;
        final usage = _map(message['usage']);
        final summary =
            _string(message['summary']) ?? _string(message['description']);
        if (_tasks[taskId] case final task?) {
          _tasks[taskId] = task.copyWith(summary: summary);
          _reportTasks();
        }
        final toolUseId = _agentCard(taskId, message['tool_use_id'] as String?);
        final agent = toolUseId == null ? null : _agents[toolUseId];
        if (agent != null) {
          agent.item = agent.item.copyWith(
            tokens: claudeInt(usage['total_tokens']),
            toolUses: claudeInt(usage['tool_uses']),
            lastTool: _string(message['last_tool_name']),
            activity: _string(message['description']),
          );
          _putAgent(toolUseId!);
        }
      case 'task_updated' when !replaying:
        final taskId = message['task_id'] as String;
        final patch = _map(message['patch']);
        if (_tasks[taskId] case final task?) {
          _tasks[taskId] = task.copyWith(
            status: _taskStatus(patch['status']) ?? task.status,
            background: patch['is_backgrounded'] as bool?,
            description: _string(patch['description']),
            summary: _string(patch['error']),
          );
          _reportTasks();
          if (patch['is_backgrounded'] == true) {
            _agentToBackground(task.toolUseId);
          }
        }
      case 'task_notification' when !replaying:
        _taskEnded(
          message['task_id'] as String,
          _taskStatus(message['status']) ?? CommandStatus.succeeded,
          toolUseId: message['tool_use_id'] as String?,
          summary: _string(message['summary']),
          outputFile: _string(message['output_file']),
          usage: _map(message['usage']),
        );
      case 'background_tasks_changed' when !replaying:
        final live = {
          for (final raw in _list(message['tasks']))
            _map(raw)['task_id'] as String,
        };
        var changed = false;
        for (final id in live) {
          final task = _tasks[id];
          if (task != null && !task.background) {
            _tasks[id] = task.copyWith(background: true);
            _agentToBackground(task.toolUseId);
            changed = true;
          }
        }
        if (changed) _reportTasks();
    }
  }

  /// The card of the subagent the task [taskId] runs, started or continued
  /// by the call [toolUseId]; null when it runs none we know of.
  String? _agentCard(String? taskId, String? toolUseId) =>
      _agents.containsKey(toolUseId) ? toolUseId : _agentCalls[taskId];

  /// The subagent [toolUseId] started, if one did, now runs on its own.
  void _agentToBackground(String? toolUseId) {
    final agent = toolUseId == null ? null : _agents[toolUseId];
    if (agent == null || agent.item.background) return;
    agent.item = agent.item.copyWith(background: true);
    _putAgent(toolUseId!);
  }

  /// Whether a task sent to the background is at work still: the CLI
  /// takes up its notice when it ends, as a turn of its own.
  bool get workingInBackground => _tasks.values.any(
    (task) => task.background && task.status == CommandStatus.running,
  );

  /// The CLI is gone, and the tasks it ran with it.
  void endTasks() {
    for (final task in [..._tasks.values]) {
      if (task.status != CommandStatus.running) continue;
      _taskEnded(
        task.id,
        CommandStatus.failed,
        toolUseId: task.toolUseId,
        summary: 'Claude Code stopped',
      );
    }
  }

  void _taskEnded(
    String taskId,
    CommandStatus status, {
    String? toolUseId,
    String? summary,
    String? outputFile,
    Map<String, Object?> usage = const {},
  }) {
    if (_tasks[taskId] case final task?) {
      _tasks[taskId] = task.copyWith(
        status: status,
        summary: summary,
        outputFile: outputFile,
      );
      _reportTasks();
    }
    // A background command's row in the history settles too, and a
    // subagent's card (its report comes in the notification to the agent,
    // see _agentNotified).
    final tool = toolUseId == null ? null : _tools[toolUseId];
    final card = _agentCard(taskId, toolUseId);
    if (_agents[card] case final agent?) {
      agent.item = agent.item.copyWith(
        status: status,
        tokens: claudeInt(usage['total_tokens']),
        toolUses: claudeInt(usage['tool_uses']),
        duration: switch (claudeInt(usage['duration_ms'])) {
          final ms? => Duration(milliseconds: ms),
          _ => null,
        },
      );
      _putAgent(card!);
    }
    if (tool != null && tool.name == 'Bash') {
      _put(
        toolUseId!,
        TerminalItem(
          command: _string(tool.input['command']) ?? '',
          description: _string(tool.input['description']),
          output: summary ?? '',
          status: status,
          background: true,
          startedAt: tool.startedAt,
        ),
        parent: tool.parent,
      );
    }
  }

  void _reportTasks() => emit(TasksReported(nextSeq(), [..._tasks.values]));

  // --- Helpers ------------------------------------------------------------------------

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};

  static List<Object?> _list(Object? value) =>
      value is List ? value.cast<Object?>() : const [];

  static String? _string(Object? value) => value is String ? value : null;

  /// A background subagent stopped, as the CLI tells its agent: how, and
  /// its report.
  void _agentNotified(String notification) {
    final id = _agentCard(
      _tag(notification, 'task-id'),
      _tag(notification, 'tool-use-id'),
    );
    final agent = id == null ? null : _agents[id];
    if (agent == null) return;
    final status = _taskStatus(_tag(notification, 'status'));
    final failed = status == CommandStatus.failed;
    agent.item = agent.item.copyWith(
      status: status,
      result:
          _tag(notification, 'result')?.trim() ??
          (failed ? _tag(notification, 'summary') : null),
    );
    _putAgent(id!);
  }

  // --- Goal ------------------------------------------------------------------------
  //
  // Not read from what Claude Code says of it (see claude_goal.dart): the
  // kernel asks how it stands whenever Claude Code says anything of it.

  /// The goal as it now stands; reported only once it is otherwise.
  void reportGoal(KernelGoal? goal) {
    if (goal == _goal) return;
    _goal = goal;
    emit(GoalReported(nextSeq(), goal));
  }

  /// The note a check of the goal that finds it not met gives the model
  /// (`Stop hook feedback:\n[condition]: why not`).
  static const _goalFeedback = 'Stop hook feedback:\n[';

  /// Whether [text] is an answer to `/goal` ("Goal set: …", "Goal active:
  /// …", "Goal cleared: …", "No goal set"): shown in the goal's bar, not
  /// here.
  bool _goalReply(String text) {
    final reply = text.trimLeft();
    if (!(reply.startsWith('Goal set: ') ||
        reply.startsWith('Goal active: ') ||
        reply.startsWith('Goal cleared') ||
        reply.startsWith('No goal set'))) {
      return false;
    }
    if (!replaying) goalSaid?.call();
    return true;
  }

  static String? _tag(String text, String tag) {
    final start = text.indexOf('<$tag>');
    final end = text.indexOf('</$tag>');
    if (start < 0 || end < start) return null;
    return text.substring(start + tag.length + 2, end);
  }

  static String _resultText(Object? content) => switch (content) {
    final String text => text,
    final List<Object?> blocks => [
      for (final block in blocks)
        if (_map(block)['text'] case final String text)
          ?_withoutImageSaved(text),
    ].join('\n'),
    _ => '',
  };

  /// [text] without the lines where the CLI says it saved a picture a tool
  /// returned (`[Image: source: /…/tool-results/….png]`, for the agent):
  /// the picture shows. Null when that is all it says.
  static String? _withoutImageSaved(String text) {
    if (!text.contains('[Image: source: ')) return text;
    final lines = text.split('\n').where((line) => !_imageSaved.hasMatch(line));
    return lines.isEmpty ? null : lines.join('\n');
  }

  static final _imageSaved = RegExp(r'^\s*\[Image: source: ([^\]\n]*)\]\s*$');

  /// Where the CLI saved the pictures in a tool's result (see
  /// [_withoutImageSaved]).
  static List<String> _savedImages(Object? content) => [
    if (content is List)
      for (final block in content.map(_map))
        if (block['text'] case final String text
            when text.contains('[Image: source: '))
          for (final line in text.split('\n'))
            if (_imageSaved.firstMatch(line)?[1]?.trim() case final path?
                when path.isNotEmpty)
              path,
  ];

  /// The pictures in a tool's result: as the CLI has them (an MCP tool's
  /// made image blocks), or as the tool gave them.
  static List<ImageAttachment> _resultImages(Object? content) => [
    if (content is List)
      for (final block in content.map(_map))
        if (block['type'] == 'image')
          ?_image(switch (block['source']) {
            final Map<Object?, Object?> source => source.cast(),
            _ => {
              'type': 'base64',
              'data': block['data'],
              'media_type': block['mimeType'],
            },
          }),
  ];

  static String _summary(Map<String, Object?> input) {
    for (final value in input.values) {
      if (value is String && value.trim().isNotEmpty) {
        final line = value.trim().split('\n').first;
        return line.length > 80 ? '${line.substring(0, 80)}…' : line;
      }
    }
    return input.isEmpty ? '' : _short(jsonEncode(input)) ?? '';
  }

  static String? _short(String text) {
    if (text.isEmpty) return null;
    return text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
  }

  /// The end of a long output, where errors are.
  static String _tail(String text) {
    const max = 4000;
    if (text.length <= max) return text;
    return '…${text.substring(text.length - max)}';
  }

  static List<String> _matches(
    String tool,
    Map<String, Object?>? result,
    String text,
  ) {
    if (tool == 'Glob') {
      final names = _list(result?['filenames']).whereType<String>();
      if (names.isNotEmpty) return names.toList();
    }
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty &&
            !line.startsWith('Found ') &&
            !line.startsWith('No files found') &&
            !line.startsWith('No matches'))
          line.split(':').take(2).join(':'),
    ];
  }

  static String? _agentReport(Map<String, Object?>? result, String text) {
    final content = _resultText(result?['content']);
    final report = content.isNotEmpty ? content : text;
    return report.isEmpty ? null : report;
  }

  /// A todo list written, one line an item marked by its status.
  static String _todoList(Object? todos) => [
    for (final raw in _list(todos))
      '${switch (_map(raw)['status']) {
        'completed' => '☒',
        'in_progress' => '◐',
        _ => '☐',
      }} ${_string(_map(raw)['content']) ?? ''}',
  ].join('\n');

  static CommandStatus? _taskStatus(Object? status) => switch (status) {
    'running' || 'pending' => CommandStatus.running,
    'completed' => CommandStatus.succeeded,
    'failed' || 'killed' || 'stopped' => CommandStatus.failed,
    _ => null,
  };

  static String _tokens(int tokens) =>
      tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens';
}

enum _Outcome { running, done, failed, denied }

class _Tool {
  _Tool(this.id, this.name, this.input, this.parent, DateTime? startedAt)
    : startedAt = startedAt ?? DateTime.now();

  /// Its tool use's.
  final String id;
  final String name;
  final Map<String, Object?> input;

  /// The subagent's tool use id, for a subagent's tool.
  final String? parent;
  final DateTime startedAt;
}

class _Agent {
  _Agent(this.item);

  AgentItem item;
  final Map<String, ChatItem> children = {};
}
