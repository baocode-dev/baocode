/// Who the commits and pull requests an agent writes credit: the
/// `chat.commitAttribution` setting. Read as each agent starts, so a change
/// applies to the agents started after it.
enum CommitAttribution {
  /// BaoCode: a `Co-Authored-By` trailer for its GitHub account, and a line
  /// naming it under a pull request.
  baocode,

  /// What the agent adds of its own (Claude Code: itself), as its own
  /// settings have it.
  agent,

  /// None.
  none;

  static const settingKey = 'chat.commitAttribution';

  /// When the setting is unset, or not one of these.
  static const fallback = baocode;

  static const baoCodeCommit = 'Co-Authored-By: BaoCode <noreply@baocode.dev>';
  static const baoCodePullRequest =
      '🤖 Generated with [BaoCode](https://baocode.dev)';

  static CommitAttribution parse(Object? setting) =>
      values.where((value) => value.name == setting).firstOrNull ?? fallback;

  /// The setting as it is now; main() points it at settings.json.
  static CommitAttribution Function() current = () => fallback;
}
