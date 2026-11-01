import 'dart:async';

import 'package:flutter/foundation.dart';

import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../settings/user_settings.dart';
import 'ide_menu.dart';

/// Whether the code editors show their minimap: settings.json's
/// `editor.minimap.enabled`, as VS Code keeps it (anything but `false`
/// shows it), one choice for every editor. Settings → Appearance turns it
/// off, Toggle Minimap (Alt+M, an editor tab's context menu) toggles it,
/// and the file edited by hand applies at once.
abstract final class EditorMinimap {
  static const settingKey = 'editor.minimap.enabled';
  static const commandId = 'editor.action.toggleMinimap';

  /// Whether the minimap shows now.
  static final ValueNotifier<bool> on = ValueNotifier(true);

  static UserSettings? _settings;

  /// [value] as settings.json has it.
  static bool parse(Object? value) => value != false;

  /// [show] as settings.json keeps it; null (not written) for on.
  static bool? setting(bool show) => show ? null : false;

  /// Sets [on] from [settings] now and whenever it changes, and keeps
  /// what is chosen there.
  static void follow(UserSettings settings) {
    _settings = settings;
    void update() => on.value = parse(settings[settingKey]);
    update();
    settings.addListener(update);
  }

  /// Shows the minimap, or not, and keeps the choice.
  static void set(bool show) {
    on.value = show;
    final settings = _settings;
    if (settings == null) return;
    unawaited(
      settings.update(settingKey, setting(show)).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown, and the choice holds for the run.
        debugPrint('$settingKey not kept: $error');
      }),
    );
  }

  static void toggle() => set(!on.value);
}

/// Minimap in an editor tab's context menu: checked while it shows.
IdeMenuAction minimapMenuAction(AppLocalizations l10n) => IdeMenuAction(
  l10n.menuMinimap,
  checked: EditorMinimap.on.value,
  keybinding: KeybindingService.instance.labelFor(EditorMinimap.commandId),
  onSelected: EditorMinimap.toggle,
);
