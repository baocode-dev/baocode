import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart' show AppColors;
import '../theme/workbench_theme.dart' show themeColors;
import 'workspace.dart';

/// Builds with [thread]'s status, again as it changes: a session not
/// opened has none to change; one that is may start, stop or ask while
/// shown.
class ThreadStatusBuilder extends StatelessWidget {
  const ThreadStatusBuilder(this.thread, this.builder, {super.key});

  final AgentThread thread;
  final Widget Function(BuildContext context, ThreadStatus status) builder;

  @override
  Widget build(BuildContext context) {
    if (!thread.isOpen) return builder(context, thread.shownStatus);
    return ListenableBuilder(
      listenable: thread.session,
      builder: (context, _) => builder(context, thread.shownStatus),
    );
  }
}

/// What an agent needs, as the sidebar shows it: a spinner while it runs,
/// an amber dot when it waits on a question, a blue dot when it finished
/// unseen; nothing when idle.
class ThreadStatusMark extends StatelessWidget {
  const ThreadStatusMark(this.status, {super.key});

  final ThreadStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    ThreadStatus.running => _dot(AppColors.accent),
    ThreadStatus.needsInput => _dot(themeColors['list.warningForeground']),
    ThreadStatus.unread => _dot(AppColors.accent),
    ThreadStatus.idle => const SizedBox.shrink(),
  };

  static Widget _dot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
