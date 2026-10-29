import 'dart:math' as math;

import '../api/message_accumulator.dart';
import '../api/model_catalog.dart';
import '../api/model_client.dart';
import '../hooks/hooks.dart';
import '../prompts/task_prompts.dart';
import '../util/cancel.dart';
import '../util/json.dart';
import 'session.dart';
import 'session_store.dart';
import 'transcript.dart';

/// Sums the conversation up when it fills the model's context, and goes on
/// from the summary: a boundary in the session's file, then the summary as
/// the conversation's first message.
class Compaction {
  Compaction(this.session);

  final AgentSession session;

  static const _system =
      'You write the summary of a conversation between a user and a coding '
      'agent, for the work to go on from.';

  /// Whether the conversation is compacted when full.
  bool get autoEnabled {
    bool on(String key) {
      final value = session.environment[key];
      return value != null &&
          value.isNotEmpty &&
          value != '0' &&
          value != 'false';
    }

    return session.settings['autoCompactEnabled'] != false &&
        !on('DISABLE_AUTO_COMPACT') &&
        !on('DISABLE_COMPACT');
  }

  /// How full the context is: the last request's, and what was added since.
  int usedTokens(SessionStore store) {
    final messages = store.apiMessages();
    final usage = session.lastUsage;
    if (usage == null) return estimateTokens(messages);
    int count(String key) => asInt(usage[key]) ?? 0;
    final reported =
        count('input_tokens') +
        count('cache_read_input_tokens') +
        count('cache_creation_input_tokens') +
        count('output_tokens');
    final lastAnswer = messages.lastIndexWhere((m) => m['role'] == 'assistant');
    final since = lastAnswer < 0 ? messages : messages.sublist(lastAnswer + 1);
    return reported + estimateTokens(since);
  }

  /// The tokens the context holds before it is compacted.
  int get threshold => session.contextWindow - session.compactBuffer;

  /// Compacts if the conversation has filled the context.
  Future<void> autoCompactIfNeeded(
    SessionStore store,
    CancelToken cancel,
  ) async {
    if (!autoEnabled) return;
    if (usedTokens(store) < threshold) return;
    await compact(store, trigger: 'auto', cancel: cancel);
  }

  /// Sums up the conversation and goes on from the summary. Returns
  /// whether it did ([instructions] say what to keep).
  Future<bool> compact(
    SessionStore store, {
    required String trigger,
    String? instructions,
    required CancelToken cancel,
  }) async {
    final messages = store.apiMessages();
    if (messages.isEmpty) return false;
    final before = usedTokens(store);
    var custom = instructions;
    if (session.hooks.has(HookEvent.preCompact)) {
      final hook = await session.hooks.run(
        HookEvent.preCompact,
        {'trigger': trigger, 'custom_instructions': instructions},
        query: trigger,
        cancel: cancel,
      );
      final added = [...hook.additionalContext, ...hook.outputs];
      if (added.isNotEmpty) {
        custom = [?instructions, ...added].join('\n\n');
      }
    }
    session.emitSystem('status', {'status': 'compacting'});
    final String summary;
    try {
      summary = await _summarize(messages, custom, cancel);
    } on Object {
      session.emitSystem('status', {'status': null});
      rethrow;
    }
    if (summary.trim().isEmpty) {
      session.emitSystem('status', {'status': null});
      return false;
    }
    final boundary = store.append({
      'type': 'system',
      'subtype': 'compact_boundary',
      'content': 'Conversation compacted',
      'isMeta': false,
      'level': 'info',
      'parentUuid': null,
      'logicalParentUuid': store.leaf,
      'compactMetadata': {'trigger': trigger, 'preTokens': before},
    });
    // The session starts over from the summary: its SessionStart hooks
    // run again, what they add kept with it.
    var started = const <String>[];
    if (session.hooks.has(HookEvent.sessionStart)) {
      final hook = await session.hooks.run(
        HookEvent.sessionStart,
        {'source': 'compact', 'model': session.resolvedModel},
        query: 'compact',
        cancel: cancel,
      );
      started = [...hook.additionalContext, ...hook.outputs];
    }
    final text = [
      compactedSummary(summary, transcriptPath: store.file),
      ..._carriedOver(),
      if (started.isNotEmpty)
        '<system-reminder>\nA SessionStart hook adds: '
            '${started.join('\n\n')}\n</system-reminder>',
    ].join('\n\n');
    final after = estimateTokens(text);
    session.emit({
      'type': 'system',
      'subtype': 'compact_boundary',
      'compact_metadata': {
        'trigger': trigger,
        'pre_tokens': before,
        'post_tokens': after,
      },
      'uuid': boundary['uuid'],
    });
    final entry = store.append({
      'type': 'user',
      'message': {'role': 'user', 'content': text},
      'isCompactSummary': true,
      'isVisibleInTranscriptOnly': true,
    });
    session.emit({
      'type': 'user',
      'message': entry['message'],
      'parent_tool_use_id': null,
      'uuid': entry['uuid'],
      'isSynthetic': true,
      'isCompactSummary': true,
    });
    // What the next request reports is the context now.
    session.lastUsage = null;
    session.emitSystem('status', {'status': null});
    session.hooks.notify(HookEvent.postCompact, {
      'trigger': trigger,
      'compact_summary': summary,
    }, query: trigger);
    return true;
  }

  /// What the model is to keep in view after the summary: the plan it was
  /// writing.
  List<String> _carriedOver() {
    final out = <String>[];
    if (session.planSlug != null && session.planExists) {
      out.add(
        '<system-reminder>\nThe plan of this session is in '
        '${session.planFilePath}.\n</system-reminder>',
      );
    }
    return out;
  }

  /// The model's summary of [messages]: the oldest left out for as long
  /// as they do not fit.
  Future<String> _summarize(
    List<Map<String, Object?>> messages,
    String? instructions,
    CancelToken cancel,
  ) async {
    var kept = messages;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _ask(kept, instructions, cancel);
      } on ApiError catch (error) {
        if (!error.promptTooLong || attempt >= 4 || kept.length < 4) rethrow;
        // A fifth of it left out, from the start: still from the user.
        var from = math.max(1, kept.length ~/ 5);
        while (from < kept.length && kept[from]['role'] != 'user') {
          from++;
        }
        if (from >= kept.length - 1) rethrow;
        kept = kept.sublist(from);
        // Results whose calls were left out are refused.
        kept = toApiMessages([
          for (final m in kept) {'type': m['role'], 'message': m},
        ]);
      }
    }
  }

  Future<String> _ask(
    List<Map<String, Object?>> messages,
    String? instructions,
    CancelToken cancel,
  ) async {
    final model = session.resolvedModel;
    final info = session.catalog.info(model);
    final conversation = [...messages];
    final ask = {'type': 'text', 'text': compactPrompt(instructions)};
    if (conversation.isNotEmpty && conversation.last['role'] == 'user') {
      final last = conversation.removeLast();
      conversation.add({
        'role': 'user',
        'content': [...asList(last['content']), ask],
      });
    } else {
      conversation.add({
        'role': 'user',
        'content': [ask],
      });
    }
    final maxTokens = info.known ? math.min(20000, info.maxOutput) : 16000;
    var accumulator = MessageAccumulator();
    await for (final event in session.client.stream(
      ModelRequest({
        'model': model,
        'max_tokens': maxTokens,
        'system': [
          {'type': 'text', 'text': _system},
        ],
        'messages': conversation,
        if (info.known &&
            info.canDisableThinking &&
            info.thinking != ThinkingStyle.none)
          'thinking': {'type': 'disabled'},
      }),
      cancel: cancel,
    )) {
      if (event['type'] == 'stream_restart') {
        accumulator = MessageAccumulator();
        continue;
      }
      accumulator.add(event);
    }
    session.addUsage(accumulator.model ?? model, accumulator.usage);
    return [
      for (final block in accumulator.content)
        if (block['type'] == 'text') '${block['text']}',
    ].join().trim();
  }
}
