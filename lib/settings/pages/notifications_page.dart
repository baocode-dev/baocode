import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../notifications/attention_host.dart';
import '../../notifications/attention_settings.dart';
import '../../notifications/notification_sound.dart';
import '../../platform/app_platform.dart';
import '../../theme/codicons.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Notifications: when agents notify, with what sound, and the
/// tray icon (see [AttentionSettings] for the settings.json keys). A choice
/// is written at once; a default is not written.
class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key, this.settings, this.host});

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  /// Plays a sound to hear it, and picks a sound file; the app's by
  /// default.
  final AttentionHost? host;

  static String whenName(BuildContext context, NotifyWhen when) =>
      switch (when) {
        NotifyWhen.unfocused => context.l10n.notificationsWhenUnfocused,
        NotifyWhen.always => context.l10n.notificationsWhenAlways,
      };

  /// [sound] as the dropdown shows it.
  static String soundName(BuildContext context, String sound) {
    final l10n = context.l10n;
    if (sound == NotificationSoundValue.microwave) {
      return l10n.notificationsSoundMicrowave;
    }
    if (sound == NotificationSoundValue.manOhYeah) {
      return l10n.notificationsSoundManOhYeah;
    }
    if (sound == NotificationSoundValue.none) {
      return l10n.notificationsSoundNone;
    }
    return NotificationSoundValue.systemName(sound) ??
        p.basenameWithoutExtension(sound);
  }

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  AttentionHost get _host => widget.host ?? ChannelAttentionHost.instance;

  /// The system's sounds, once listed.
  Map<String, String> _systemSounds = const {};

  @override
  void initState() {
    super.initState();
    unawaited(
      NotificationSound.systemSounds().then((sounds) {
        if (mounted) setState(() => _systemSounds = sounds);
      }),
    );
  }

  void _write(String key, Object? value) {
    final settings = widget.settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  void _setSound(String sound) {
    _write(
      AttentionSettings.soundKey,
      sound == AttentionSettings.defaults.sound ? null : sound,
    );
    unawaited(NotificationSound.play(_host, sound));
  }

  Future<void> _chooseSound() async {
    final path = await _host.pickSound();
    if (path != null) _setSound(path);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return ListenableBuilder(
      listenable: settings ?? Listenable.merge(const []),
      builder: (context, _) =>
          _page(context, AttentionSettings.parse(settings?.values ?? const {})),
    );
  }

  Widget _page(BuildContext context, AttentionSettings current) {
    final l10n = context.l10n;
    final whenName = NotificationsSettingsPage.whenName(context, current.when);
    final soundName = NotificationsSettingsPage.soundName(
      context,
      current.sound,
    );
    final enabled = current.enabled;
    return SettingsPage(
      title: l10n.notificationsSettingsTitle,
      children: [
        SettingsCard(
          children: [
            SettingsSwitchRow(
              label: l10n.notificationsEnabled,
              description: l10n.notificationsEnabledDescription,
              value: enabled,
              onChanged: (value) =>
                  _write(AttentionSettings.enabledKey, value ? null : false),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.notificationsEvents,
          children: [
            for (final (event, label, detail) in [
              (
                AttentionEvent.needsInput,
                l10n.notificationsEventNeedsInput,
                l10n.notificationsEventNeedsInputDetail,
              ),
              (
                AttentionEvent.finished,
                l10n.notificationsEventFinished,
                l10n.notificationsEventFinishedDetail,
              ),
            ])
              SettingsSwitchRow(
                label: label,
                description: detail,
                value: current.events.contains(event),
                enabled: enabled,
                onChanged: (value) => _write(
                  AttentionSettings.eventsKey,
                  AttentionSettings.encodeEvents(
                    value
                        ? {...current.events, event}
                        : ({...current.events}..remove(event)),
                  ),
                ),
              ),
            SettingsRow(
              label: l10n.notificationsWhen,
              description: l10n.notificationsWhenDescription,
              trailing: SettingsDropdown(
                current: whenName,
                semanticLabel: l10n.notificationsWhenLabel(whenName),
                entries: () => [
                  for (final when in NotifyWhen.values)
                    IdeMenuAction(
                      NotificationsSettingsPage.whenName(context, when),
                      checked: when == current.when,
                      onSelected: () => _write(
                        AttentionSettings.whenKey,
                        when == AttentionSettings.defaults.when
                            ? null
                            : when.name,
                      ),
                    ),
                ],
              ),
            ),
            SettingsRow(
              label: l10n.notificationsSound,
              trailing: SettingsButtons(
                children: [
                  SettingsDropdown(
                    current: soundName,
                    semanticLabel: l10n.notificationsSoundLabel(soundName),
                    entries: () => _soundEntries(context, current.sound),
                  ),
                  IdeButton(
                    label: l10n.notificationsSoundPlay,
                    icon: Codicons.play,
                    secondary: true,
                    onPressed: current.sound == NotificationSoundValue.none
                        ? null
                        : () => unawaited(
                            NotificationSound.play(_host, current.sound),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (AppPlatform.isMacOS || AppPlatform.isWindows)
          SettingsGroup(
            title: l10n.traySettings,
            children: [
              SettingsSwitchRow(
                label: AppPlatform.isWindows
                    ? l10n.trayEnabledWindows
                    : l10n.trayEnabledMacOS,
                description: l10n.trayEnabledDescription,
                value: current.tray,
                onChanged: (value) =>
                    _write(AttentionSettings.trayKey, value ? null : false),
              ),
            ],
          ),
      ],
    );
  }

  List<IdeMenuEntry> _soundEntries(BuildContext context, String current) {
    final l10n = context.l10n;
    IdeMenuAction choice(String label, String sound) => IdeMenuAction(
      label,
      checked: sound == current,
      onSelected: () => _setSound(sound),
    );
    return [
      choice(
        l10n.notificationsSoundMicrowave,
        NotificationSoundValue.microwave,
      ),
      choice(
        l10n.notificationsSoundManOhYeah,
        NotificationSoundValue.manOhYeah,
      ),
      choice(l10n.notificationsSoundNone, NotificationSoundValue.none),
      if (_systemSounds.isNotEmpty) const IdeMenuSeparator(),
      for (final name in _systemSounds.keys)
        choice(name, NotificationSoundValue.system(name)),
      const IdeMenuSeparator(),
      if (NotificationSoundValue.isFile(current))
        choice(p.basename(current), current),
      IdeMenuAction(
        l10n.notificationsSoundChoose,
        onSelected: () => unawaited(_chooseSound()),
      ),
    ];
  }
}
