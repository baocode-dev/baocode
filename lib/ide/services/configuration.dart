// The settings as the window reads and toggles them (upstream
// `IConfigurationService`, src/vs/platform/configuration/common/
// configuration.ts): settings.json's, with those toggled here before the
// file is written (or with none to write to, under test).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../settings/user_settings.dart';

class ConfigurationService extends ChangeNotifier {
  ConfigurationService({required this._settings});

  /// settings.json, where the app has one.
  final UserSettings? Function() _settings;
  UserSettings? get settings => _settings();

  /// The settings toggled here not written to settings.json yet.
  final Map<String, bool> _set = {};

  /// [key] as a flag; [fallback] where it is not one.
  bool flag(String key, bool fallback) =>
      _set[key] ??
      switch (settings?[key]) {
        final bool value => value,
        _ => fallback,
      };

  /// [key] set to [value], here at once and in settings.json after.
  void setFlag(String key, bool value) {
    _set[key] = value;
    notifyListeners();
    unawaited(
      settings?.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  /// settings.json read again: what it says now, written here or not.
  void reloaded() {
    _set.clear();
    notifyListeners();
  }

  /// `editor.formatOnSave`, kept in settings.json as VS Code keeps it.
  bool get formatOnSave => flag('editor.formatOnSave', false);
  set formatOnSave(bool value) => setFlag('editor.formatOnSave', value);

  /// The editor's Git blame (`git.blame.editorDecoration.enabled`).
  bool get gitBlame => flag('git.blame.editorDecoration.enabled', true);
  set gitBlame(bool value) =>
      setFlag('git.blame.editorDecoration.enabled', value);
}
