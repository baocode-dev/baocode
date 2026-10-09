import 'dart:async';

import 'package:flutter/widgets.dart';

import '../keybindings/import_dialog.dart';
import '../keybindings/keybinding_service.dart';
import '../keybindings/keybindings_editing.dart';
import '../keybindings/keybindings_sync.dart';
import '../keybindings/keymap.dart';
import '../keybindings/vscode_import.dart';
import '../models/model_providers.dart';
import '../theme/workbench_theme.dart' show WorkbenchThemeService;
import '../tips/builtin_tips.dart';
import '../tips/feature_tip.dart';
import '../tips/feature_tips_controller.dart';
import '../update/update_controller.dart';
import 'app_locale.dart';
import 'pages/appearance_page.dart';
import 'pages/data_dir_page.dart';
import 'pages/general_page.dart';
import 'pages/keybindings_page.dart';
import 'pages/models_page.dart';
import 'pages/language_page.dart';
import 'pages/network_page.dart';
import 'pages/notifications_page.dart';
import 'pages/updates_page.dart';
import 'settings_dialog.dart';
import 'user_settings.dart';

/// What the settings dialog shows and changes, made once in main(): the
/// general settings, the display language, the keybindings, the data
/// directory.
class AppSettings {
  AppSettings({
    required this.locale,
    KeybindingService? keybindings,
    this.files,
    this.catalog,
    this.sync,
    this.installs,
    this.updates,
  }) : keybindings = keybindings ?? KeybindingService.instance;

  final AppLocale locale;
  final KeybindingService keybindings;

  /// The settings files in the data directory; none under test.
  final SettingsFiles? files;

  /// The keymaps to pick from.
  final KeymapCatalog? catalog;

  /// Follows keybindings.json and the selected keymap into [keybindings].
  final KeybindingsSync? sync;

  /// Where VS Code, Cursor and the like keep their keybindings, to import
  /// them from; none under test.
  final VsCodeInstalls? installs;

  /// Updating the app: Settings → Updates, Check for Updates; none where
  /// the build does not update itself.
  final UpdateController? updates;

  /// The feature tips (the setup checklist, the update's and the scenarios'
  /// notifications); none without settings files.
  late final FeatureTipsController? tips = switch (files?.storage) {
    final storage? => FeatureTipsController(
      tips: builtInFeatureTips(this),
      storage: _TipStorage(storage),
      enabled: () =>
          files?.settings[FeatureTipsController.enabledSetting] != false,
      settingsChanges: files?.settings,
    ),
    null => null,
  };

  /// Writes the keyboard page's changes into keybindings.json: one for
  /// the app, so they are made one at a time.
  late final KeybindingsEditingService editing = KeybindingsEditingService(
    (files ?? SettingsFiles.instance).keybindings,
  );

  /// The keymaps to pick from, read when the keyboard page shows and after
  /// an import.
  final ValueNotifier<List<KeymapChoice>> keymaps = ValueNotifier(const []);

  Future<void> refreshKeymaps() async {
    final catalog = this.catalog;
    if (catalog == null) return;
    keymaps.value = [
      for (final keymap in await catalog.list())
        (id: keymap.id, name: keymap.name),
    ];
  }

  /// [section]'s page of the settings dialog.
  Widget buildPage(BuildContext context, SettingsSection section) {
    switch (section) {
      case SettingsSection.general:
        return GeneralSettingsPage(settings: files?.settings, tips: tips);
      case SettingsSection.appearance:
        final themes = WorkbenchThemeService.instance;
        return AppearanceSettingsPage(
          themes: themes,
          changes: themes,
          settings: files?.settings,
        );
      case SettingsSection.models:
        return ModelsSettingsPage(providers: ModelProviders.current);
      case SettingsSection.network:
        return NetworkSettingsPage(settings: files?.settings);
      case SettingsSection.notifications:
        return NotificationsSettingsPage(settings: files?.settings);
      case SettingsSection.language:
        return LanguageSettingsPage(locale: locale);
      case SettingsSection.keyboard:
        unawaited(refreshKeymaps());
        final sync = this.sync;
        return ValueListenableBuilder(
          valueListenable: keymaps,
          builder: (context, keymaps, _) => KeybindingsSettingsPage(
            keybindings: keybindings,
            editing: editing,
            keymaps: keymaps,
            onSelectKeymap: sync?.selectKeymap,
            onImport: installs == null
                ? null
                : () => unawaited(showImport(context)),
          ),
        );
      case SettingsSection.updates:
        return UpdatesSettingsPage(updates: updates, settings: files?.settings);
      case SettingsSection.dataDirectory:
        return const DataDirectoryPage();
    }
  }

  /// Imports another editor's keybindings (and keymap), as the user picks
  /// them in [showKeybindingsImportDialog].
  Future<void> showImport(BuildContext context) async {
    final installs = this.installs;
    if (installs == null) return;
    final detection = await installs.detect();
    if (!context.mounted) return;
    await _showImport(context, detection);
  }

  Future<void> _showImport(
    BuildContext context,
    KeybindingsDetection detection,
  ) {
    final files = this.files;
    final catalog = this.catalog;
    return showKeybindingsImportDialog(
      context,
      detection: detection,
      importKeybindings: (source, mode) async {
        if (files == null) throw StateError('No keybindings.json');
        final report = await importKeybindings(
          source: source.path,
          target: files.keybindings.path,
          mode: mode,
          isSupported: keybindings.isSupported,
        );
        // At once, rather than when the watcher hears of it.
        await files.keybindings.load();
        return report;
      },
      importKeymap: (extension) {
        if (catalog == null) throw StateError('No keymaps folder');
        return importKeymapExtension(extension, catalog);
      },
      selectKeymap: (id) => sync?.selectKeymap(id),
    ).whenComplete(refreshKeymaps);
  }
}

/// The app's global storage, as the tips remember themselves in it.
class _TipStorage implements TipStorage {
  _TipStorage(this.storage);

  final GlobalStorage storage;

  @override
  Object? get(String key) => storage.get<Object>(key);

  @override
  Future<void> set(String key, Object? value) => storage.set(key, value);
}
