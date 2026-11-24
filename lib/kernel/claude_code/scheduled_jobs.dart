/// What the session has scheduled itself, as its messages say: jobs
/// (`CronCreate`, until `CronDelete`) and a loop's next round
/// (`ScheduleWakeup`, until it comes or is stopped). They live in the
/// process, which keeps them only while it runs: a conversation with any
/// is not let go of when no view shows it, or they would not come (#994).
class ScheduledJobs {
  /// The jobs scheduled, by their ids (or their calls', where the result
  /// gave none).
  final Set<String> _jobs = {};

  /// The calls made and not answered yet, by their ids: the tool, its
  /// input.
  final Map<String, (String, Map<String, Object?>)> _calls = {};

  bool _wakeup = false;

  /// Whether anything is to come.
  bool get pending => _jobs.isNotEmpty || _wakeup;

  /// A message of the CLI's: the agent's own calls and their results (not
  /// a subagent's).
  void receive(Map<String, Object?> message) {
    if (message['parent_tool_use_id'] != null) return;
    final body = message['message'];
    if (body is! Map) return;
    final content = body['content'];
    if (content is! List) return;
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'tool_use'
            when message['type'] == 'assistant' &&
                const {
                  'CronCreate',
                  'CronDelete',
                  'ScheduleWakeup',
                }.contains(block['name']):
          final id = block['id'];
          final input = block['input'];
          if (id is String) {
            _calls[id] = (
              block['name'] as String,
              input is Map ? input.cast<String, Object?>() : const {},
            );
          }
        case 'tool_result' when message['type'] == 'user':
          final call = _calls.remove(block['tool_use_id']);
          if (call == null || block['is_error'] == true) continue;
          final (tool, input) = call;
          final result = message['tool_use_result'] ?? message['toolUseResult'];
          switch (tool) {
            case 'CronCreate':
              _jobs.add(switch (result) {
                {'id': final String id} => id,
                _ => block['tool_use_id'] as String,
              });
            case 'CronDelete':
              _jobs.remove('${input['id']}'.trim());
            case 'ScheduleWakeup':
              _wakeup = input['stop'] != true;
          }
      }
    }
  }

  /// The CLI took up a prompt of its own: a loop's round come, if one was.
  void woke() => _wakeup = false;
}
