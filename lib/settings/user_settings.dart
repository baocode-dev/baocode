import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/data_dir.dart';
import '../theme/workbench_theme.dart';
import 'app_locale.dart';
import 'jsonc_file.dart';

/// `User/settings.json`: the user's settings as VS Code keeps them, one
/// object of dotted keys (`"workbench.colorTheme": "Monokai"`).
class UserSettings extends JsoncFile {
  UserSettings(super.path, {super.debounce});

  /// All of them; none while the file is missing or not an object.
  Map<String, Object?> get values => switch (value) {
    final Map<String, Object?> values => values,
    _ => const {},
  };

  /// The setting [key]; null when it is not set.
  Object? operator [](String key) => values[key];

  /// Sets [key] to [value] in the file; null removes it. Throws a
  /// [JsoncFileException] while the file does not parse.
  Future<void> update(String key, Object? value) =>
      edit([key], value, remove: value == null);
}

/// `argv.json`: what VS Code reads before its window opens; here the
/// display language (`locale`: `en`, `zh-cn`…). Loaded before the first
/// frame, so the app starts in it.
class ArgvSettings extends JsoncFile implements LocaleStorage {
  ArgvSettings(super.path, {super.debounce});

  /// The `locale` set; null follows the system.
  String? get locale => switch (value) {
    {'locale': final String locale} when locale.trim().isNotEmpty =>
      locale.trim(),
    _ => null,
  };

  /// Sets `locale`; null (or empty) removes it, to follow the system.
  Future<void> setLocale(String? locale) =>
      edit(['locale'], locale, remove: locale == null || locale.trim().isEmpty);

  @override
  String? read() => locale;

  @override
  Future<void> write(String? locale) => setLocale(locale);
}

/// `state/storage.json`: small values the app keeps for itself across
/// windows and runs (VS Code's global storage), e.g. whether importing
/// another editor's keybindings was offered.
class GlobalStorage extends JsoncFile {
  GlobalStorage(super.path, {super.debounce});

  /// The value kept as [key], when it is a [T].
  T? get<T extends Object>(String key) => switch (value) {
    final Map<Object?, Object?> values => switch (values[key]) {
      final T value => value,
      _ => null,
    },
    _ => null,
  };

  /// Keeps [value] as [key]; null removes it.
  Future<void> set(String key, Object? value) =>
      edit([key], value, remove: value == null);
}

/// The files in the data directory ([DataDirectory]) the user edits, and
/// the app's global storage: made once as the app starts (main.dart),
/// loaded before the first frame and watched while it runs.
class SettingsFiles {
  SettingsFiles(DataDirectory directory)
    : settings = UserSettings(directory.settingsFile),
      keybindings = JsoncFile(directory.keybindingsFile),
      argv = ArgvSettings(directory.argvFile),
      storage = GlobalStorage(directory.storageFile);

  /// The app's, in [DataDirectory.current]; main.dart (or a test) sets it.
  static SettingsFiles get instance =>
      _instance ??= SettingsFiles(DataDirectory.current);
  static set instance(SettingsFiles value) => _instance = value;
  static SettingsFiles? _instance;

  /// `User/settings.json`.
  final UserSettings settings;

  /// `User/keybindings.json`: VS Code's array of keybinding entries.
  final JsoncFile keybindings;

  /// `argv.json`.
  final ArgvSettings argv;

  /// `state/storage.json`.
  final GlobalStorage storage;

  /// Those the user edits: what [watch] follows, and whose [JsoncFile.error]
  /// the workbench shows.
  List<JsoncFile> get userFiles => [settings, keybindings, argv];

  List<JsoncFile> get all => [...userFiles, storage];

  /// The files that do not parse (or cannot be read) now.
  List<JsoncFile> get broken => [
    for (final file in all)
      if (file.error != null) file,
  ];

  /// Notifies whenever a file's value or error changes.
  Listenable get changes => Listenable.merge(all);

  Future<void> load() => Future.wait([for (final file in all) file.load()]);

  /// Follows the files the user edits as they change on disk.
  void watch() {
    for (final file in userFiles) {
      file.watch();
    }
  }

  void dispose() {
    for (final file in all) {
      file.dispose();
    }
  }
}

/// The color theme kept as VS Code keeps it: the `workbench.colorTheme`
/// setting in settings.json, and the theme's colors for a quick restore
/// (`colorThemeData`) in [state] (the Workspace's store, state/state.json).
/// A setting changed in the file is applied ([follow]).
class ColorThemeSettings implements ColorThemeStorage {
  ColorThemeSettings({required this.settings, required this.state});

  final UserSettings settings;
  final ColorThemeStorage state;

  static const key = 'workbench.colorTheme';

  @override
  String? get colorThemeSetting => switch (settings[key]) {
    final String id when id.trim().isNotEmpty => id.trim(),
    _ => null,
  };

  @override
  String? get colorThemeData => state.colorThemeData;

  @override
  void storeColorTheme({required String setting, String? data}) {
    state.storeColorTheme(setting: setting, data: data);
    // Unset is the default theme: the file is not written for it.
    final current = colorThemeSetting ?? ThemeSettingDefaults.colorThemeDark;
    if (migrateThemeSettingsId(current) == setting) return;
    unawaited(
      settings.update(key, setting).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('workbench.colorTheme not kept: $error');
      }),
    );
  }

  WorkbenchThemeService? _themes;

  /// Applies to [themes] the theme the setting names whenever the file
  /// changes (the default one when it is removed), until [dispose].
  void follow(WorkbenchThemeService themes) {
    _themes = themes;
    settings.addListener(_changed);
  }

  void _changed() {
    final themes = _themes;
    if (themes == null) return;
    final id = migrateThemeSettingsId(
      colorThemeSetting ?? ThemeSettingDefaults.colorThemeDark,
    );
    if (id != themes.colorThemeId) unawaited(themes.setColorTheme(id));
  }

  void dispose() {
    settings.removeListener(_changed);
    _themes = null;
  }
}
