/// settings.json's `update.mode`, as VS Code's: whether the app looks for
/// new versions by itself.
enum UpdateMode {
  /// Looks at launch and every few hours, downloads what it finds, and
  /// offers to restart into it.
  automatic('default'),

  /// Only when asked (Check for Updates).
  manual('manual'),

  /// Never, not even when asked.
  none('none');

  const UpdateMode(this.value);

  /// As settings.json writes it.
  final String value;

  static const settingKey = 'update.mode';

  static const defaultMode = UpdateMode.automatic;

  /// [setting] as a mode: the default where it is unset or not one.
  static UpdateMode parse(Object? setting) => switch (setting) {
    final String value => UpdateMode.values.firstWhere(
      (mode) => mode.value == value.trim(),
      orElse: () => defaultMode,
    ),
    _ => defaultMode,
  };
}
