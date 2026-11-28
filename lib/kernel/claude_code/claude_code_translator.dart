import 'dart:convert';
import 'dart:math' as math;

import '../../chat/chat_models.dart';
import '../../chat/compaction_text.dart';
import '../../l10n/l10n.dart';
import '../../swarm/swarm_model.dart';
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
  ClaudeTranslator({
    required this.emit,
    required this.nextSeq,
    this.goalSaid,
    this.ownModel,
  });

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// A subagent's model, as its upstream answered it (a bare id), as the
  /// session's upstream's [modelRef] where that upstream has it: another
  /// upstream of a model of that id is not the one it ran on.
  final String Function(String model)? ownModel;

  /// Claude Code said something of the goal, live: how it stands is to be
  /// asked afresh (see claude_goal.dart).
  final void Function()? goalSaid;

  /// What a question was answered with in full access, the user not asked,
  /// as earlier versions did: a question so answered shows as skipped.
  /// A workflow's card's [AgentItem.agentType] (see [_workflowProgress]).
  static const workflowAgentType = 'workflow';

  /// Prefix of synthetic [AgentItem.id] and [KernelTask.id] entries that back
  /// Antigravity native `/swarm` workers as first-class subagents.
  static const swarmWorkerPrefix = 'swarm-worker:';

  /// Whether [id] identifies a swarm worker's subagent card or task.
  static bool isSwarmWorkerId(String? id) =>
      id != null && id.startsWith(swarmWorkerPrefix);

  static const unattendedAnswer =
      'The user has given full access and is not here to answer questions. '
      'Do not ask again: go with what seems best, say what you assumed, '
      'and carry on.';

  /// The turn changes belong to (the user message uuid that began it).
  String? turnId;

  String _ownModel(String model) => ownModel?.call(model) ?? model;

  String? _ownModelOf(String? model) => model == null ? null : _ownModel(model);

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

  /// Every block the current message streamed, by its index, ended or not:
  /// those Claude Code abandons (its stream cut short, asked again) go.
  final Map<int, String> _messageBlocks = {};

  /// Calls whose start streamed, that no whole message has brought yet.
  final Set<String> _streamedCalls = {};

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

  /// What a text block streaming has said while it is only blank, not
  /// shown yet: some models write a line break or two before a tool call,
  /// which would show as an empty row and break a run of steps.
  final Map<String, String> _blankText = {};

  final Map<String, _Tool> _tools = {};
  final Map<String, _Agent> _agents = {};

  /// The call that started each subagent, by the CLI's id of it (its
  /// task's): one continued (`SendMessage`) runs again on a call of its
  /// own, and goes on in the card of the first.
  final Map<String, String> _agentCalls = {};

  /// Workers created by each `swarm(action: "add")` tool call, by call id.
  final Map<String, List<String>> _swarmAddCalls = {};

  /// When each swarm worker was first seen active, by worker item id.
  final Map<String, DateTime> _swarmStartedAt = {};

  /// The card of each skill run from a slash command in a subagent of its
  /// own (`context: fork`), by the id its messages give as their parent
  /// (`forked-command-<name>`): no call started it (see [_forkedSkill]).
  final Map<String, String> _forkedCommands = {};

  /// Told of a skill run from a slash command as it starts, and as it ends,
  /// by its messages' parent (`forked-command-<name>`): its messages may be
  /// read as it goes ([forkedLine]), the CLI sending them only once done.
  void Function(String command)? onForkedCommand;
  void Function(String command)? onForkedCommandEnded;

  /// Those whose messages came as they went ([forkedLine]): the same, sent
  /// all at once at the end, are not shown again.
  final Set<String> _followed = {};
  final Set<String> _denied = {};

  /// Calls made and not answered yet: those of a stopped turn never are.
  final Set<String> _unanswered = {};

  final Map<String, KernelTask> _tasks = {};
  final Map<String, String> _taskOutputs = {};

  /// The subjects of the todos created (TaskCreate), by their ids.
  final Map<String, String> _taskSubjects = {};

  /// What the user answered to questions asked (AskUserQuestion), by the
  /// call's id: each answer by its question's text.
  final Map<String, Map<String, String>> _answers = {};

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
      'ExitPlanMode again. Approval does not go through this tool: the user '
      'starts the plan in the app, and their message then tells you plan '
      'mode is over.';

  /// Marks the note sent with the message that starts a plan.
  static const _planStarted = 'The user has started your plan';

  /// The note sent with the message that starts the plan in [path]: not
  /// shown, it tells the model planning is over. It says outright that the
  /// plan-mode reminders earlier on no longer hold, and that ExitPlanMode
  /// is not to be called: a model that took the read-only ones as standing
  /// called it again and again for an approval it already had.
  static String planStartedNote(String path) =>
      '<system-reminder>$_planStarted: plan mode is over and the plan is '
      'approved. The plan-mode instructions earlier in this conversation '
      '(read-only, superseding other instructions) no longer apply: you may '
      'edit files, run commands and use any tool. Do not call ExitPlanMode: '
      'there is nothing left to approve, and it would only fail. Carry out '
      'the ${path.isEmpty ? 'plan you put to them' : 'plan in $path'} now, '
      'from its first step.</system-reminder>';

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
    final given = message['parent_tool_use_id'] as String?;
    if (_followed.contains(given) &&
        (message['type'] == 'assistant' || message['type'] == 'user')) {
      return;
    }
    final parent = _forkedCommands[given] ?? given;
    switch (message['type']) {
      case 'stream_event' when parent == null:
        _streamEvent(
          _map(message['event']),
          abandoned: _map(message['abandoned_blocks']),
        );
      // A message shown that Claude Code took back (its stream failed, and
      // it asked again): what it showed goes.
      case 'tombstone' when parent == null:
        _tombstone(_map(message['message']));
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

  /// The user stopped the replayed turn: timed all the same, to where it
  /// stopped, and marked so (see [UserMessageItem.stopped]).
  bool _replayedStopped = false;

  /// What is replayed is still of a turn whose prompt is on an earlier page:
  /// no prompt yet, nor the agent taking up a notice of its own.
  bool _headOpen = true;
  DateTime? _headUntil;
  bool _headStopped = false;

  /// Of a page that begins within a turn (see [_headOpen]): when what it
  /// shows of that turn last showed anything, and whether the user stopped
  /// it; for the page before, which has its prompt, to time it by (see
  /// [endPage]).
  ({DateTime? until, bool stopped}) get head =>
      (until: _headUntil, stopped: _headStopped);

  /// A page of the kept session is replayed, not all of it: times its last
  /// turn, nothing else. Where the page after it begins within that turn,
  /// its [head] says how the turn went on: it is timed to where that ends.
  void endPage({({DateTime? until, bool stopped})? after}) {
    if (after != null) {
      if (_headOpen) {
        // All of this page within the turn: the head goes on to the next.
        _headUntil = after.until ?? _headUntil;
        _headStopped |= after.stopped;
      }
      if (after.until case final until?) _replayedUntil = until;
      if (after.stopped) _replayedStopped = true;
    }
    final open = _headOpen;
    _timeReplayed();
    _headOpen = open;
  }

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
    if (!replaying) return;
    final at = DateTime.tryParse('${message['timestamp']}');
    if (_replayed == null) {
      if (_headOpen && at != null) _headUntil = at;
      return;
    }
    if (message['uuid'] == _replayed!.id) return;
    if (at != null) _replayedUntil = at;
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
    _headOpen = false;
    _replayed = null;
    _replayedUntil = null;
    _replayedStopped = false;
    if (turn == null) return;
    // As its footer showed it when it ended, where that was kept.
    if (keptTurns[turn.id] case (:final worked, :final usage)) {
      _put(
        turn.id,
        turn.item.copyWith(worked: worked, usage: usage, stopped: stopped),
      );
      return;
    }
    final at = turn.at;
    if (until == null || at == null) return;
    final worked = until.difference(at);
    if (worked > Duration.zero) {
      _put(turn.id, turn.item.copyWith(worked: worked, stopped: stopped));
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
      if (_blankText.remove(id) == null) emit(ItemCompleted(nextSeq(), id));
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

  void _streamEvent(
    Map<String, Object?> event, {
    Map<String, Object?> abandoned = const {},
  }) {
    switch (event['type']) {
      case 'message_start':
        final message = _map(event['message']);
        _messageId = message['id'] as String?;
        _streamed.clear();
        _messageBlocks.clear();
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
        if (claudeInt(abandoned['from_block_index']) case final from?) {
          _abandon(abandoned['api_message_id'] as String?, from);
        }
        _endMessage();
      case 'content_block_start':
        final index = claudeInt(event['index']) ?? 0;
        final block = _map(event['content_block']);
        final id = '$_messageId:$index';
        switch (block['type']) {
          case 'thinking' || 'redacted_thinking':
            _messageThought = true;
            _streamed[index] = id;
            _messageBlocks[index] = id;
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
            _messageBlocks[index] = id;
            (_unclaimed['$_messageId:text'] ??= []).add(id);
            _textLength[id] = 0;
            _blankText[id] = '';
          case 'tool_use':
            // Its input may come all at once as it ends: timed from here.
            if (!replaying) _meter.startBlock();
            final toolId = block['id'] as String;
            final name = block['name'] as String;
            _messageBlocks[index] = toolId;
            if (!_tools.containsKey(toolId)) {
              _streamedCalls.add(toolId);
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
            if (_blankText[id] case final blank?) {
              final written = blank + text;
              if (written.trim().isEmpty) {
                _blankText[id] = written;
              } else {
                _blankText.remove(id);
                _put(id, AssistantTextItem(written), streaming: true);
              }
            } else {
              emit(TextDelta(nextSeq(), id, offset, text));
            }
        }
      case 'content_block_stop':
        _blockSince = DateTime.now();
        final id = _streamed.remove(claudeInt(event['index']) ?? 0);
        if (id == null) return;
        if (_thoughts.containsKey(id)) {
          _completeThought(id, null);
        } else if (_textLength.remove(id) != null &&
            _blankText.remove(id) == null) {
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
        _meter.streamed(json, timed: delta['timed'] != false);
      case {'type': 'thinking_delta', 'thinking': final String thought}:
        _meter.streamed(thought, timed: delta['timed'] == true);
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

  /// How fast the turn wrote, on average, as streamed: for a turn whose
  /// messages told no usage (Antigravity's), whose result alone counts it.
  double? get averageSpeed => _meter.averageSpeed;

  /// Fallback estimated output speed for turns that never reached timed warm-up.
  double? get estimatedSpeed => _meter.estimatedSpeed;

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
    // A subagent's: the model it runs on, as the upstream answered.
    if (_agents[parent] case final agent? when !synthetic) {
      if (_string(body['model']) case final answered?
          when answered.isNotEmpty) {
        final model = _ownModel(answered);
        if (model != agent.item.model) {
          agent.item = agent.item.copyWith(model: model);
          _putAgent(parent!);
        }
      }
    }
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
          } else if (_textLength.remove(id) != null &&
              _blankText.remove(id) == null) {
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
          _streamedCalls.remove(block['id']);
          _toolUse(
            block['id'] as String,
            block['name'] as String,
            _map(block['input']),
            parent,
          );
      }
    }
  }

  /// The blocks of [messageId] (the current message) from [from] on, which
  /// Claude Code gave up on: shown as they streamed, no whole message will
  /// bring them. They go, unless one did bring them; what it asks next may
  /// say them again.
  void _abandon(String? messageId, int from) {
    if (messageId != null && messageId != _messageId) return;
    for (final MapEntry(key: index, value: id) in [..._messageBlocks.entries]) {
      if (index < from) continue;
      _messageBlocks.remove(index);
      _streamed.remove(index);
      final unclaimed =
          (_unclaimed['$_messageId:text']?.remove(id) ?? false) ||
          (_unclaimed['$_messageId:thinking']?.remove(id) ?? false);
      if (unclaimed) {
        _thoughts.remove(id);
        _thinkingStarted.remove(id);
        _thinkingTokens.remove(id);
        _textLength.remove(id);
        _blankText.remove(id);
        emit(ItemRemoved(nextSeq(), id));
      } else if (_streamedCalls.remove(id)) {
        _dropCall(id);
      }
    }
  }

  /// The whole message [message] (as Claude Code keeps it) taken back:
  /// what it brought goes.
  void _tombstone(Map<String, Object?> message) {
    final uuid = message['uuid'] as String?;
    if (uuid == null) return;
    final body = _map(message['message']);
    for (final (index, raw) in _list(body['content']).indexed) {
      final block = _map(raw);
      if (block['type'] == 'tool_use') {
        if (block['id'] case final String id when _tools.containsKey(id)) {
          _streamedCalls.remove(id);
          _dropCall(id);
        }
        continue;
      }
      final id = _blockIds.remove('$uuid:$index');
      if (id == null) continue;
      _thoughts.remove(id);
      _thinkingStarted.remove(id);
      _thinkingTokens.remove(id);
      _textLength.remove(id);
      _blankText.remove(id);
      emit(ItemRemoved(nextSeq(), id));
    }
  }

  /// The call [id], never made: its card goes.
  void _dropCall(String id) {
    _tools.remove(id);
    _agents.remove(id);
    _unanswered.remove(id);
    emit(ItemRemoved(nextSeq(), id));
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
      if (replaying) {
        _replayedStopped = true;
        if (_replayed == null && _headOpen) _headStopped = true;
      }
      return;
    }
    // A subagent's message to the agent (SendMessage), not the user's: by
    // what it was given to do.
    if (agentMessage(trimmed) case (:final from, :final session, :final text)) {
      final item = UserMessageItem(
        text: text,
        sentAt: _sentAt(message),
        fromAgent: _agents[_agentCalls[from]]?.item.description ?? from,
        fromSession: session,
      );
      _put(id, item);
      if (replaying) _replayPrompt(id, item, message);
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
      // A workflow (a script running subagents, in the background): a
      // card as a subagent's, the ones it runs in it (see
      // [_workflowProgress]).
      case 'Workflow':
        final agent = _agents[id] ??= _Agent(
          AgentItem(
            description: _workflowTitle(input) ?? 'Workflow',
            id: id,
            agentType: workflowAgentType,
            status: replaying ? CommandStatus.succeeded : CommandStatus.running,
            startedAt: replaying ? null : tool.startedAt,
            background: true,
          ),
        );
        // The streamed start has no input: the whole message fills it in.
        if (agent.item.prompt == null) {
          agent.item = agent.item.copyWith(
            description: _workflowTitle(input),
            prompt: _string(input['script']) ?? _string(input['name']),
          );
        }
        _putAgent(id);
        return;
      // Each swarm worker added becomes a native subagent card in the chat.
      case 'Swarm' when _string(input['action']) == 'add':
        final added = _swarmAddedWorkers(input);
        if (added.isNotEmpty) {
          _swarmAddCalls[id] = [for (final w in added) w.name];
          final model = _ownModelOf(_string(input['model']));
          for (final worker in added) {
            final workerId = '$swarmWorkerPrefix${worker.name}';
            _swarmStartedAt.putIfAbsent(workerId, () => tool.startedAt);
            final existing = _agents[workerId];
            if (existing == null) {
              _agents[workerId] = _Agent(
                AgentItem(
                  description: '@${worker.name}',
                  id: workerId,
                  agentType: 'Swarm',
                  prompt: worker.prompt,
                  status: replaying
                      ? CommandStatus.succeeded
                      : CommandStatus.running,
                  startedAt: replaying ? null : _swarmStartedAt[workerId],
                  model: model,
                  background: true,
                ),
              );
            } else {
              existing.item = existing.item.copyWith(
                prompt: existing.item.prompt ?? worker.prompt,
                model: existing.item.model ?? model,
              );
            }
            _putAgent(workerId);
          }
          return;
        }
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
    String base(String? path) =>
        path == null ? '' : path.split(RegExp(r'[/\\]')).last;
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
        tool: name,
        label: tense('Read output', 'Reading output'),
        target: _summary(input),
        input: input,
        status: status,
        output: output,
      ),
      'KillShell' || 'KillBash' || 'TaskStop' => ToolCallItem(
        kind: ToolKind.command,
        tool: name,
        label: tense('Stopped', 'Stopping'),
        target: _summary(input),
        input: input,
        status: status,
        output: output,
      ),
      // Its verb the web kind's, in the app's language.
      'WebFetch' => ToolCallItem(
        kind: ToolKind.web,
        tool: name,
        target: _string(input['url']) ?? '',
        status: status,
        output: output,
      ),
      'WebSearch' => ToolCallItem(
        kind: ToolKind.web,
        tool: name,
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
      // Loads tools' definitions, MCP tools' mostly: drawn with their mark.
      'ToolSearch' => ToolCallItem(
        kind: ToolKind.search,
        tool: name,
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
      // The questions, and once answered, the answers (see [_answers]),
      // for the history to show what was asked and said.
      'AskUserQuestion' => ToolCallItem(
        kind: ToolKind.question,
        target: [
          for (final q in _list(input['questions']))
            _string(_map(q)['header']) ?? _string(_map(q)['question']) ?? '',
        ].join(' · '),
        status: status,
        output: output,
        tool: name,
        input: {'questions': input['questions'], 'answers': ?_answers[tool.id]},
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
      'ManageTask' => _manageTaskToolItem(input, status: status, output: output),
      'Schedule' => _scheduleToolItem(input, status: status, output: output),
      'ManageSubagents' => _manageSubagentsToolItem(
        input,
        status: status,
        output: output,
      ),
      'DefineSubagent' => _defineSubagentToolItem(
        input,
        status: status,
        output: output,
      ),
      'McpResource' => _mcpResourceToolItem(
        input,
        status: status,
        output: output,
      ),
      'Swarm' => _swarmToolItem(input, status: status, output: output),
      'SwarmBoard' => _swarmBoardToolItem(input, status: status, output: output),
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

  ToolCallItem _swarmToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final action = _string(input['action']) ?? '';
    final name = _string(input['name']);
    final title = _string(input['title']);
    final model = _string(input['model']);
    final label = switch (action) {
      'title' => running ? 'Naming swarm' : 'Named swarm',
      'add' => running ? 'Adding swarm worker' : 'Added swarm worker',
      'kill' => running ? 'Removing swarm worker' : 'Removed swarm worker',
      'model' => running ? 'Switching worker model' : 'Switched worker model',
      'status' => running ? 'Checking swarm status' : 'Checked swarm status',
      'models' => running ? 'Listing swarm models' : 'Listed swarm models',
      'channel' => running ? 'Updating swarm channel' : 'Updated swarm channel',
      _ => running ? 'Running swarm' : 'Swarm',
    };
    final target = switch (action) {
      'title' => title ?? '',
      'add' => [
        if (name != null) '@$name',
        if (input['n'] case final num n when n > 1) '×${n.toInt()}',
        if (input['tasks'] case final List t when t.isNotEmpty)
          '(${t.length})',
        if (model != null) '· $model',
      ].join(' '),
      'kill' => name != null ? '@$name' : '',
      'model' => [if (name != null) '@$name', if (model != null) '→ $model'].join(' '),
      'channel' => [
        ?_string(input['op']),
        if (_string(input['channel']) case final ch?) '#$ch',
      ].join(' '),
      _ => '',
    };
    return ToolCallItem(
      kind: ToolKind.agent,
      tool: 'Swarm',
      label: label,
      target: target,
      input: input,
      status: status,
      output: output,
    );
  }

  ToolCallItem _swarmBoardToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final action = _string(input['action']) ?? 'read';
    final since = input['since'];
    final channel = _string(input['channel']);
    final label = action == 'wait'
        ? (running ? 'Waiting on swarm board' : 'Waited on swarm board')
        : (running ? 'Reading swarm board' : 'Read swarm board');
    final target = [
      if (channel != null && channel != 'main') '#$channel',
      if (since != null) '#$since+',
    ].join(' ');
    return ToolCallItem(
      kind: ToolKind.message,
      tool: 'SwarmBoard',
      label: label,
      target: target,
      input: input,
      status: status,
      output: output,
    );
  }

  ToolCallItem _manageTaskToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final action = _string(input['action']) ?? '';
    final taskId = _string(input['task_id'])?.trim();
    final sent = _string(
      input['input'],
    )?.trim().replaceAll(RegExp(r'\s+'), ' ');
    final label = switch (action) {
      'list' => running ? 'Listing background tasks' : 'Listed background tasks',
      'send_input' => running ? 'Sending input to task' : 'Sent input to task',
      _ => running ? 'Managing task' : 'Managed task',
    };
    final target = switch (action) {
      'list' => '',
      'send_input' => [
        if (taskId != null && taskId.isNotEmpty) taskId,
        if (sent != null && sent.isNotEmpty)
          sent.length > 60 ? '${sent.substring(0, 60)}…' : sent,
      ].join(' · '),
      _ => taskId ?? _summary(input),
    };
    return ToolCallItem(
      kind: ToolKind.command,
      tool: 'ManageTask',
      label: label,
      target: target,
      input: input,
      status: status,
      output: output,
    );
  }

  ToolCallItem _scheduleToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final cron = _string(input['cron'])?.trim();
    final durationSeconds = claudeInt(input['duration_seconds']);
    final isDaemon = input['is_daemon'] == true;
    final prompt = _string(input['prompt'])?.trim();
    final String label;
    final String target;
    if (cron != null && cron.isNotEmpty) {
      label = running ? 'Scheduling cron' : 'Scheduled cron';
      target = isDaemon ? '$cron · daemon' : cron;
    } else if (durationSeconds != null) {
      label = running ? 'Setting timer' : 'Set timer';
      target = _formatDurationSeconds(durationSeconds);
    } else {
      label = running ? 'Scheduling' : 'Scheduled';
      target = _summary(input);
    }
    return ToolCallItem(
      kind: ToolKind.other,
      tool: 'Schedule',
      label: label,
      target: target,
      input: input,
      status: status,
      output: status == ToolStatus.failed
          ? output
          : (prompt != null && prompt.isNotEmpty ? prompt : output),
    );
  }

  static String _formatDurationSeconds(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return [
      if (hours > 0) '${hours}h',
      if (minutes > 0) '${minutes}m',
      if (secs > 0) '${secs}s',
    ].join();
  }

  ToolCallItem _manageSubagentsToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final action = _string(input['action']) ?? '';
    final ids = [
      for (final raw in _list(input['conversation_ids']))
        if ('$raw'.trim().isNotEmpty) '$raw'.trim(),
    ];
    final label = switch (action) {
      'list' => running ? 'Listing subagents' : 'Listed subagents',
      'kill' => running ? 'Stopping subagent' : 'Stopped subagent',
      'kill_all' =>
        running ? 'Stopping all subagents' : 'Stopped all subagents',
      _ => running ? 'Managing subagents' : 'Managed subagents',
    };
    final target = switch (action) {
      'kill' when ids.length == 1 => ids.single,
      'kill' when ids.length > 1 => '${ids.length} subagents',
      _ => '',
    };
    return ToolCallItem(
      kind: ToolKind.agent,
      tool: 'ManageSubagents',
      label: label,
      target: target,
      input: input,
      status: status,
      output: output,
    );
  }

  ToolCallItem _defineSubagentToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final name = _string(input['name'])?.trim() ?? '';
    final description = _string(input['description'])?.trim();
    return ToolCallItem(
      kind: ToolKind.agent,
      tool: 'DefineSubagent',
      label: running ? 'Defining subagent' : 'Defined subagent',
      target: name,
      input: input,
      status: status,
      output: status == ToolStatus.failed
          ? output
          : (description != null && description.isNotEmpty
                ? description
                : output),
    );
  }

  ToolCallItem _mcpResourceToolItem(
    Map<String, Object?> input, {
    required ToolStatus status,
    String? output,
  }) {
    final running = status == ToolStatus.running;
    final action = _string(input['action']) ?? '';
    final server = _string(input['server'])?.trim();
    final uri = _string(input['uri'])?.trim();
    final label = switch (action) {
      'read' => running ? 'Reading MCP resource' : 'Read MCP resource',
      'list' => running ? 'Listing MCP resources' : 'Listed MCP resources',
      _ => running ? 'Accessing MCP resource' : 'Accessed MCP resource',
    };
    final target = switch (action) {
      'read' => (uri != null && uri.isNotEmpty) ? uri : (server ?? ''),
      'list' => server ?? '',
      _ => (uri != null && uri.isNotEmpty) ? uri : (server ?? ''),
    };
    return ToolCallItem(
      kind: ToolKind.read,
      tool: 'McpResource',
      label: label,
      target: target,
      input: input,
      status: status,
      output: output,
    );
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
            // What the CLI resolved, if its messages did not say.
            model: agent.item.model == null
                ? _ownModelOf(_string(structured?['resolvedModel']))
                : null,
            background: true,
          );
          _putAgent(id);
          return;
        }
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
          model: agent.item.model == null
              ? _ownModelOf(_string(structured?['resolvedModel']))
              : null,
        );
        _putAgent(id);
        return;
      // A skill run in a subagent of its own: its card (a kept session's
      // has none yet), with what the subagent answered.
      case 'Skill'
          when _agents.containsKey(id) || structured?['status'] == 'forked':
        final agent = _agents[id] ??= _Agent(
          AgentItem(
            description: '/${_string(tool.input['skill']) ?? ''}',
            id: id,
          ),
        );
        agent.item = agent.item.copyWith(
          status: outcome == _Outcome.done
              ? CommandStatus.succeeded
              : CommandStatus.failed,
          result: _string(structured?['result']) ?? text,
        );
        _putAgent(id);
        return;
      // Launched, it reports in a notification; one that failed to start
      // says why.
      case 'Workflow':
        final agent = _agents[id];
        if (agent == null) return;
        if (outcome != _Outcome.done) {
          agent.item = agent.item.copyWith(
            status: CommandStatus.failed,
            result: text,
          );
          _putAgent(id);
        }
        return;
      case 'Swarm' when _swarmAddCalls.containsKey(id):
        final names = _swarmAddCalls.remove(id)!;
        if (outcome != _Outcome.done) {
          for (final name in names) {
            final workerId = '$swarmWorkerPrefix$name';
            final agent = _agents[workerId];
            if (agent == null) continue;
            agent.item = agent.item.copyWith(
              status: CommandStatus.failed,
              result: text,
            );
            _putAgent(workerId);
          }
        }
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
      case 'AskUserQuestion' when outcome == _Outcome.done:
        _answers[id] = questionAnswers(structured?['answers'], text);
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
        output: outcome != _Outcome.done
            ? _tail(text)
            : tool.name == 'WebSearch'
            ? _searchOutput(text)
            : _short(text),
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
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
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
        // As it came, else as the transcript keeps it.
        final meta = _map(message['compact_metadata']);
        final kept = _map(message['compactMetadata']);
        final auto = (meta['trigger'] ?? kept['trigger']) == 'auto';
        final note = CompactionNote(
          auto: auto,
          // Refused by the API before the window set was full.
          tooLong:
              auto && (meta['reason'] ?? kept['reason']) == 'prompt_too_long',
          before: claudeInt(meta['pre_tokens']) ?? claudeInt(kept['preTokens']),
          after: claudeInt(meta['post_tokens']),
          window:
              claudeInt(meta['context_window']) ??
              claudeInt(kept['contextWindow']),
        );
        _put(
          uuid,
          NoticeItem(
            NoticeKind.compaction,
            note.describe(englishLocalizations),
            compaction: note,
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
      // The model's safeguards flagged a message, answered on another: as
      // the CLI says, which and until when.
      case 'model_refusal_fallback':
        if (_string(message['content']) case final text? when text.isNotEmpty) {
          _put(uuid, NoticeItem(NoticeKind.warning, text));
        }
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
        final workflow = message['task_type'] == 'local_workflow';
        final call = message['tool_use_id'] as String?;
        // A subagent's task is its card's, continued or not; a workflow's
        // too; a skill's run in a subagent of its own, a card of its own.
        final card = agent || workflow
            ? _agentCard(taskId, call) ??
                  (agent ? _forkedSkill(taskId, call, message) : null)
            : null;
        if (card != null) _agentCalls[taskId] = card;
        if (_agents[card] case final run? when workflow) {
          run.item = run.item.copyWith(
            description: _string(message['description']),
          );
          _putAgent(card!);
        }
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
          // A workflow runs in the background, whatever it says.
          background: workflow || message['is_backgrounded'] == true,
          outputFile: _string(message['output_file']) ?? _taskOutputs[taskId],
        );
        _reportTasks();
        // Continued: at work again, in its card.
        if (_agents[card] case final continued? when card != call) {
          continued.item = continued.item.status == CommandStatus.running
              ? continued.item
              : continued.item.continuedAt(DateTime.now());
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
        if (agent != null && agent.item.agentType == workflowAgentType) {
          _workflowProgress(agent, message);
          _putAgent(toolUseId!);
        } else if (agent != null) {
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
            summary: _string(patch['error']) ?? _string(patch['summary']),
            outputFile: _string(patch['output_file']),
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

  /// A skill run in a subagent of its own (`context: fork`), as the task
  /// [started] says: a subagent's card, the one of the Skill call [call]
  /// that ran it, else (run from a slash command, `/code-review`) one of
  /// its own, which its messages go in once it is done (the CLI gives
  /// them only then). Null for a task that is no such skill's.
  String? _forkedSkill(
    String taskId,
    String? call,
    Map<String, Object?> started,
  ) {
    final skill = call == null ? null : _tools[call];
    final description = _string(started['description']);
    final String id;
    if (call == null) {
      if (description == null || !description.startsWith('/')) return null;
      id = taskId;
      final command = 'forked-command-${description.substring(1)}';
      _forkedCommands[command] = id;
      if (!replaying) onForkedCommand?.call(command);
    } else if (skill?.name == 'Skill') {
      id = call;
    } else {
      return null;
    }
    _agents[id] = _Agent(
      AgentItem(
        description: description ?? '/${_string(skill?.input['skill']) ?? ''}',
        id: id,
        agentType: _string(started['subagent_type']),
        prompt: _string(started['prompt']),
        startedAt: skill?.startedAt ?? DateTime.now(),
      ),
    );
    _putAgent(id);
    return id;
  }

  /// A line the subagent of the skill run from a slash command [command]
  /// wrote, as it went (see [onForkedCommand]): into its card.
  void forkedLine(String command, Map<String, Object?> line) {
    final card = _forkedCommands[command];
    if (card == null) return;
    switch (line['type']) {
      case 'assistant':
        _followed.add(command);
        _assistant(line, card);
      case 'user':
        _followed.add(command);
        _user(line, card);
    }
  }

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
    for (final MapEntry(key: command, value: card) in _forkedCommands.entries) {
      if (card == taskId) onForkedCommandEnded?.call(command);
    }
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
      // A workflow's subagents still at work when it ended end with it.
      if (agent.item.agentType == workflowAgentType) {
        for (final MapEntry(:key, :value) in [...agent.children.entries]) {
          if (value is AgentItem && value.status == CommandStatus.running) {
            agent.children[key] = value.copyWith(status: status);
          }
        }
      }
      agent.item = agent.item.copyWith(
        status: status,
        result:
            agent.item.result == null && summary != null && summary.isNotEmpty
            ? summary
            : null,
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

  /// Projects an Antigravity native [SwarmSnapshot] onto BaoCode's native
  /// subagent primitives: each worker becomes an [AgentItem] card (opening into
  /// a [SubagentFeed] with its `brief`, live `transcript.jsonl` steps, and
  /// board report), running workers appear in [ActivityStrip] as background
  /// agent [KernelTask]s, and non-brief worker board posts appear in the chat
  /// as [AgentMessageCard] bubbles (`UserMessageItem(fromAgent: ...)`).
  void applySwarm(SwarmSnapshot snapshot) {
    final now = DateTime.now();
    final activeWorkerIds = <String>{};
    var tasksChanged = false;

    // Group non-brief messages by sender so each worker's subagent view shows
    // its board reports cleanly.
    final postsByMember = <String, List<SwarmMessage>>{};
    for (final msg in snapshot.messages) {
      if (msg.isBrief || msg.text.trim().isEmpty) continue;
      (postsByMember[msg.agent] ??= []).add(msg);
    }

    for (final member in snapshot.members) {
      if (member.role == SwarmMemberRole.coordinator) continue;
      final workerId = '$swarmWorkerPrefix${member.name}';
      final existing = _agents[workerId];
      final status = switch (member.status) {
        SwarmMemberStatus.working when !replaying => CommandStatus.running,
        _ when member.failure != null && !member.isKilled =>
          CommandStatus.failed,
        _ => CommandStatus.succeeded,
      };
      final startedAt =
          _swarmStartedAt[workerId] ??= existing?.item.startedAt ?? now;
      final duration = status == CommandStatus.running
          ? null
          : existing?.item.duration ??
                (replaying ? null : now.difference(startedAt));

      final posts = postsByMember[member.name] ?? const <SwarmMessage>[];
      final latestPost = posts.lastOrNull?.text.trim();
      final result = switch (status) {
        CommandStatus.failed => member.failure ?? latestPost,
        CommandStatus.succeeded => latestPost ?? existing?.item.result,
        CommandStatus.running => existing?.item.result,
      };

      final agent = _agents[workerId] ??= _Agent(
        AgentItem(
          description: '@${member.name}',
          id: workerId,
          agentType: 'Swarm',
          prompt: member.brief,
          status: status,
          startedAt: replaying ? null : startedAt,
          background: true,
        ),
      );

      // Rebuild the worker's child items from its transcript.jsonl steps using
      // BaoCode's native item types (ThinkingItem, ToolCallItem, TerminalItem,
      // AssistantTextItem, NoticeItem) plus incoming board messages.
      agent.children.clear();
      for (final msg in snapshot.messages) {
        if (msg.isBrief ||
            msg.agent == member.name ||
            msg.text.trim().isEmpty) {
          continue;
        }
        if (msg.mentions.contains(member.name) || msg.isAll) {
          agent.children['incoming:${msg.seq}'] = UserMessageItem(
            text: msg.text.trim(),
            sentAt: msg.timestamp,
            fromAgent: '@${msg.agent}',
          );
        }
      }
      for (final (i, step) in member.steps.indexed) {
        final stepKey = 'step:${step.index}:$i';
        final live =
            status == CommandStatus.running && i == member.steps.length - 1;
        agent.children[stepKey] = _swarmStepToChatItem(step, live: live);
      }
      // Include earlier board posts in children when the worker posted more
      // than once (the latest post is shown as `result`).
      if (posts.length > 1) {
        for (final post in posts.take(posts.length - 1)) {
          agent.children['post:${post.seq}'] = AssistantTextItem(
            post.text.trim(),
          );
        }
      }

      agent.item = agent.item.copyWith(
        description: '@${member.name}',
        agentType: 'Swarm',
        prompt: existing?.item.prompt ?? member.brief,
        status: status,
        model: _ownModelOf(member.model) ?? existing?.item.model,
        toolUses: member.stepsCount > 0 ? member.stepsCount : null,
        tokens: member.totalTokens > 0 ? member.totalTokens : null,
        activity: member.currentActivity,
        duration: duration,
        result: result,
        background: true,
      );
      _putAgent(workerId);

      // Sync running workers into ActivityStrip via native KernelTask.
      if (!replaying && status == CommandStatus.running) {
        activeWorkerIds.add(workerId);
        final prev = _tasks[workerId];
        if (prev == null || prev.status != CommandStatus.running) {
          _tasks[workerId] = KernelTask(
            id: workerId,
            kind: KernelTaskKind.agent,
            description: '@${member.name}',
            status: CommandStatus.running,
            startedAt: startedAt,
            toolUseId: workerId,
            background: true,
          );
          tasksChanged = true;
        }
      } else if (_tasks[workerId] case final prev?
          when prev.status == CommandStatus.running) {
        _tasks[workerId] = prev.copyWith(status: status);
        tasksChanged = true;
      }
    }

    // Settle any swarm worker tasks no longer reported as working.
    for (final MapEntry(:key, :value) in [..._tasks.entries]) {
      if (!isSwarmWorkerId(key) || value.status != CommandStatus.running) {
        continue;
      }
      if (!activeWorkerIds.contains(key)) {
        _tasks[key] = value.copyWith(status: CommandStatus.succeeded);
        tasksChanged = true;
      }
    }
    if (tasksChanged) _reportTasks();

    // Surface non-brief worker board posts in the main conversation as native
    // AgentMessageCard bubbles.
    for (final msg in snapshot.messages) {
      if (msg.isBrief ||
          msg.agent == 'coordinator' ||
          msg.text.trim().isEmpty) {
        continue;
      }
      _put(
        'swarm-msg:${snapshot.swarmId}:${msg.seq}',
        UserMessageItem(
          text: msg.text.trim(),
          sentAt: msg.timestamp,
          fromAgent: '@${msg.agent}',
        ),
      );
    }
  }

  /// Populates a subagent's [AgentItem] card (created by an `Agent` or `Task`
  /// tool call) with parsed `transcript.jsonl` steps from Antigravity.
  ///
  /// Existing non-`substep:` children are preserved, and calls with an unknown
  /// [toolUseId] or empty [steps] are ignored.
  void applySubagentTranscript(String toolUseId, List<SwarmWorkerStep> steps) {
    final agent = _agents[toolUseId];
    if (agent == null || steps.isEmpty) return;
    agent.children.removeWhere((key, _) => key.startsWith('substep:'));
    var toolUses = 0;
    var tokens = 0;
    final isRunning = agent.item.status == CommandStatus.running;
    for (final (i, step) in steps.indexed) {
      final live = isRunning && i == steps.length - 1;
      agent.children['substep:${step.index}:$i'] = _swarmStepToChatItem(
        step,
        live: live,
      );
      if (step.kind == 'tool') toolUses++;
      tokens += step.inputTokens + step.outputTokens;
    }
    agent.item = agent.item.copyWith(
      toolUses: toolUses > 0 ? toolUses : null,
      tokens: tokens > 0 ? tokens : null,
    );
    _putAgent(toolUseId);
  }

  static ChatItem _swarmStepToChatItem(
    SwarmWorkerStep step, {
    bool live = false,
  }) {
    final toolStatus = step.isError ? ToolStatus.failed : ToolStatus.succeeded;
    switch (step.kind) {
      case 'thought':
        return ThinkingItem(
          text: step.detail ?? step.title,
          seconds: live ? null : 0,
          tokens: 0,
        );
      case 'reply':
        return AssistantTextItem(step.detail ?? step.title);
      case 'error':
        return NoticeItem(NoticeKind.error, step.detail ?? step.title);
      case 'tool':
        switch (step.toolName) {
          case 'read_file':
            return ToolCallItem(
              kind: ToolKind.read,
              target: step.target ?? step.title,
              path: step.path,
              detail: step.range,
              status: toolStatus,
              output: step.detail,
            );
          case 'edit_file' || 'write_file':
            return ToolCallItem(
              kind: ToolKind.edit,
              target: step.target ?? step.title,
              path: step.path,
              status: toolStatus,
              output: step.detail,
            );
          case 'grep_search' || 'find_by_name' || 'list_dir':
            return ToolCallItem(
              kind: ToolKind.search,
              target: step.target ?? step.title,
              path: step.path,
              status: toolStatus,
              output: step.detail,
            );
          case 'run_command':
            final cmd = step.target ?? step.title;
            return TerminalItem(
              command: cmd,
              description: step.title == cmd ? null : step.title,
              output: step.detail ?? '',
              status: step.isError
                  ? CommandStatus.failed
                  : CommandStatus.succeeded,
            );
          case 'post_message' || 'send_message':
            return ToolCallItem(
              kind: ToolKind.message,
              label: 'Sent message',
              target: step.target ?? '',
              status: toolStatus,
              output: step.detail,
            );
          default:
            return ToolCallItem(
              kind: ToolKind.other,
              label: step.title,
              target: step.target ?? '',
              status: toolStatus,
              output: step.detail,
            );
        }
      default:
        return ToolCallItem(
          kind: ToolKind.other,
          label: step.title,
          target: step.target ?? '',
          status: toolStatus,
          output: step.detail,
        );
    }
  }

  static List<({String name, String? prompt})> _swarmAddedWorkers(
    Map<String, Object?> input,
  ) {
    final name = _string(input['name'])?.trim();
    if (name == null || name.isEmpty) return const [];
    final brief = _string(input['brief'])?.trim();
    final tasks = input['tasks'];
    if (tasks is List && tasks.isNotEmpty) {
      return [
        for (var i = 0; i < tasks.length; i++)
          (
            name: '$name-${i + 1}',
            prompt: [
              '${tasks[i]}'.trim(),
              if (brief != null && brief.isNotEmpty) brief,
            ].where((s) => s.isNotEmpty).join('\n\n'),
          ),
      ];
    }
    final count = input['n'];
    if (count is num && count.toInt() > 1) {
      return [
        for (var i = 1; i <= count.toInt(); i++)
          (name: '$name-$i', prompt: brief),
      ];
    }
    return [(name: name, prompt: brief)];
  }

  /// What a workflow's card says it is: the workflow's name, else its
  /// script's `meta` description.
  static String? _workflowTitle(Map<String, Object?> input) {
    if (_string(input['name']) case final name? when name.isNotEmpty) {
      return name;
    }
    final script = _string(input['script']);
    if (script == null) return null;
    return RegExp(r'''description\s*:\s*(['"`])((?:(?!\1).)+)\1''')
        .firstMatch(script)
        ?.group(2);
  }

  /// A workflow's progress on its card: what it does now, and its
  /// subagents as the CLI lists them (each time all of them), each as a
  /// subagent's card in it.
  void _workflowProgress(_Agent workflow, Map<String, Object?> message) {
    final usage = _map(message['usage']);
    workflow.item = workflow.item.copyWith(
      tokens: claudeInt(usage['total_tokens']),
      toolUses: claudeInt(usage['tool_uses']),
      activity: _string(message['description']),
    );
    final listed = _list(message['workflow_progress']);
    if (listed.isEmpty) return;
    DateTime? at(Object? ms) => switch (claudeInt(ms)) {
      final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    };
    workflow.children.clear();
    for (final raw in listed) {
      final agent = _map(raw);
      if (agent['type'] != 'workflow_agent') continue;
      final state = _string(agent['state']);
      final startedAt = at(agent['startedAt']);
      final ended = state == 'done' || state == 'error';
      final last = at(agent['lastProgressAt']);
      final id = '${workflow.item.id}/${agent['index']}';
      workflow.children[id] = AgentItem(
        description: _string(agent['label']) ?? 'Subagent',
        id: id,
        agentType: _string(agent['agentType']),
        prompt: _string(agent['promptPreview']),
        status: switch (state) {
          'done' => CommandStatus.succeeded,
          'error' => CommandStatus.failed,
          _ => CommandStatus.running,
        },
        // Queued until it starts.
        activity: startedAt == null && !ended
            ? 'Queued'
            : _string(agent['phaseTitle']),
        startedAt: ended ? null : startedAt,
        duration: ended && startedAt != null && last != null
            ? last.difference(startedAt)
            : null,
        model: _ownModelOf(_string(agent['model'])),
        result: _string(agent['resultPreview']) ?? _string(agent['error']),
        background: true,
      );
    }
  }

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

  /// A subagent's message as the agent is given it: its id, and what it
  /// says.
  /// Another conversation's has its session too (`session="…"`).
  static final _agentMessage = RegExp(
    r'^<agent-message from="([^"]*)"(?: session="([^"]*)")?>'
    r'([\s\S]*)</agent-message>$',
  );

  /// [text] as a message another agent sent (`<agent-message from="…">`,
  /// a subagent's or another conversation's): who from (and that one's
  /// session, another conversation's), and what it says; null for any
  /// other.
  static ({String from, String? session, String text})? agentMessage(
    String text,
  ) => switch (_agentMessage.firstMatch(text.trim())) {
    final match? => (
      from: match[1]!,
      session: match[2],
      text: match[3]!.trim(),
    ),
    null => null,
  };

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

  /// A web search's output shortened as [_short], but its `Links: [...]`
  /// line kept whole however long: the sites' icons are read from it, and
  /// fifteen results with redirect URLs run past 2000 characters.
  static String? _searchOutput(String text) {
    if (text.isEmpty) return null;
    if (text.length <= 2000) return text;
    final lines = text.split('\n');
    final at = lines.indexWhere((line) => line.startsWith('Links:'));
    if (at < 0) return _short(text);
    final links = lines[at];
    final rest = _short([...lines.take(at), ...lines.skip(at + 1)].join('\n'));
    return rest == null ? links : '$rest\n$links';
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

/// What the user answered to questions asked (AskUserQuestion), each
/// answer by its question's text: from the call's result ([structured]'s
/// `answers`, the CLI's and BaoCode's own core's alike), else read from
/// what it said to the model (`"question"="answer", …`).
Map<String, String> questionAnswers(Object? structured, String text) {
  if (structured is Map && structured.isNotEmpty) {
    return {
      for (final MapEntry(:key, :value) in structured.entries)
        if (key is String && value != null) key: '$value',
    };
  }
  return {
    for (final match in _answered.allMatches(text))
      _unquote(match[1]!): _unquote(match[2]!),
  };
}

final _answered = RegExp(r'"((?:[^"\\]|\\.)*)"="((?:[^"\\]|\\.)*)"');

String _unquote(String text) =>
    text.replaceAllMapped(RegExp(r'\\(.)'), (match) => match[1]!);
