import 'dart:async';

import 'package:flutter/foundation.dart';

import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../settings/user_settings.dart';
import 'ide_menu.dart';

/// Whether long lines wrap at the editor's width: settings.json's
/// `editor.wordWrap`, as VS Code keeps it (`"on"`; anything but `"off"`
/// wraps here), one choice for every editor. Settings → Appearance turns
/// it on, Toggle Word Wrap (Alt+Z, the editors' context menus) toggles it,
/// and the file edited by hand applies at once.
abstract final class EditorWordWrap {
  static const settingKey = 'editor.wordWrap';
  static const commandId = 'editor.action.toggleWordWrap';

  /// Whether lines wrap now.
  static final ValueNotifier<bool> on = ValueNotifier(false);

  static UserSettings? _settings;

  /// [value] as settings.json has it.
  static bool parse(Object? value) => value is String && value != 'off';

  /// [wrap] as settings.json keeps it; null (not written) for off.
  static String? setting(bool wrap) => wrap ? 'on' : null;

  /// Sets [on] from [settings] now and whenever it changes, and keeps
  /// what is chosen there.
  static void follow(UserSettings settings) {
    _settings = settings;
    void update() => on.value = parse(settings[settingKey]);
    update();
    settings.addListener(update);
  }

  /// Wraps lines, or not, and keeps the choice.
  static void set(bool wrap) {
    on.value = wrap;
    final settings = _settings;
    if (settings == null) return;
    unawaited(
      settings.update(settingKey, setting(wrap)).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown, and the choice holds for the run.
        debugPrint('$settingKey not kept: $error');
      }),
    );
  }

  static void toggle() => set(!on.value);
}

/// Word Wrap in an editor's context menu: checked while lines wrap.
IdeMenuAction wordWrapMenuAction(AppLocalizations l10n) => IdeMenuAction(
  l10n.menuWordWrap,
  checked: EditorWordWrap.on.value,
  keybinding: KeybindingService.instance.labelFor(EditorWordWrap.commandId),
  onSelected: EditorWordWrap.toggle,
);
