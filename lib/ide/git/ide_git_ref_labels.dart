// A commit's references in the log as JetBrains IDEs draw them: a colored
// icon and the name, no box; a local branch and its remote's of the same
// name, both pointing at the commit, as one (JetBrains' "origin & main",
// here the name with a cloud by its icon).

import 'package:flutter/widgets.dart';

import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart';
import '../ide_hover.dart';
import '../ide_list.dart';
import 'git_model.dart';

/// One label of a commit's references: [ref], with the remote branches of
/// its name that point at the commit too ([remotes]).
class IdeGitRefLabel {
  const IdeGitRefLabel(this.ref, [this.remotes = const []]);

  final IdeGitRef ref;
  final List<IdeGitRef> remotes;

  /// The local name alone: a cloud by its icon says it is on a remote too.
  String get text => ref.name;

  /// Each reference's whole name, a line each.
  String get tooltip => [ref.name, for (final r in remotes) r.name].join('\n');

  bool get current => ref.kind == IdeGitRefKind.head;
}

/// [refs]' labels in their order: each local branch with the remote ones
/// of its name, which go from where they were.
List<IdeGitRefLabel> ideGitRefLabels(List<IdeGitRef> refs) {
  final local = {
    for (final ref in refs)
      if (ref.kind == IdeGitRefKind.head || ref.kind == IdeGitRefKind.branch)
        ref.name,
  };
  String? localOf(IdeGitRef ref) {
    if (ref.kind != IdeGitRefKind.remote) return null;
    final slash = ref.name.indexOf('/');
    if (slash < 0) return null;
    final name = ref.name.substring(slash + 1);
    return local.contains(name) ? name : null;
  }

  return [
    for (final ref in refs)
      if (ref.kind != IdeGitRefKind.remote || localOf(ref) == null)
        IdeGitRefLabel(ref, [
          if (ref.kind == IdeGitRefKind.head ||
              ref.kind == IdeGitRefKind.branch)
            for (final remote in refs)
              if (localOf(remote) == ref.name) remote,
        ]),
  ];
}

/// [label] drawn: its icon in its kind's color and its name, the current
/// branch's in [foreground] and bold, the others' quieter; [compact], the
/// icon alone. [trailing] after the name.
class IdeGitRefLabelView extends StatelessWidget {
  const IdeGitRefLabelView(
    this.label, {
    super.key,
    this.compact = false,
    this.foreground,
    this.trailing = const [],
  });

  final IdeGitRefLabel label;
  final bool compact;
  final Color? foreground;
  final List<Widget> trailing;

  static IconData icon(IdeGitRefKind kind) => switch (kind) {
    IdeGitRefKind.head || IdeGitRefKind.branch => Codicons.gitBranch,
    IdeGitRefKind.remote => Codicons.cloud,
    IdeGitRefKind.tag => Codicons.tag,
  };

  /// The current branch gold, branches green, remote ones purple, tags
  /// blue.
  static Color color(IdeGitRefKind kind) =>
      themeColors[switch (kind) {
        IdeGitRefKind.head => 'charts.yellow',
        IdeGitRefKind.branch => 'charts.green',
        IdeGitRefKind.remote => 'charts.purple',
        IdeGitRefKind.tag => 'charts.blue',
      }];

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final kind = label.ref.kind;
    final mark = Icon(icon(kind), size: 14, color: color(kind));
    // A branch on its remote too: a cloud by its own icon.
    final synced = label.remotes.isNotEmpty;
    final icons = synced
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              Icon(
                Codicons.cloud,
                size: 12,
                color: color(IdeGitRefKind.remote),
              ),
            ],
          )
        : mark;
    return IdeHover(
      message: label.tooltip,
      child: compact
          ? icons
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icons,
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    label.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: label.current
                          ? foreground ?? IdeListColors.foreground
                          : IdeListColors.description,
                      fontWeight: label.current ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                ...trailing,
              ],
            ),
    );
  }
}
