/// What an agent is notified for.
enum AttentionEvent {
  /// It stopped on a question, or for leave to use a tool.
  needsInput,

  /// It ended a turn.
  finished,
}

/// When an agent's news is notified.
enum NotifyWhen {
  /// Unless the user is looking at it: the window in front, the agent in
  /// view.
  unfocused,
  always,
}

/// The notification and tray settings, from settings.json:
///
/// * `notifications.enabled`: whether agents notify at all (true);
/// * `notifications.sound`: [NotificationSoundValue]s (`microwave`);
/// * `notifications.when`: `unfocused` or `always` (`unfocused`);
/// * `notifications.events`: of `needsInput` and `finished` (both);
/// * `tray.enabled`: the menu bar / system tray icon, which the window's
///   close button hides the window to (true).
class AttentionSettings {
  const AttentionSettings({
    this.enabled = true,
    this.sound = NotificationSoundValue.microwave,
    this.when = NotifyWhen.unfocused,
    this.events = const {AttentionEvent.needsInput, AttentionEvent.finished},
    this.tray = true,
  });

  static const enabledKey = 'notifications.enabled';
  static const soundKey = 'notifications.sound';
  static const whenKey = 'notifications.when';
  static const eventsKey = 'notifications.events';
  static const trayKey = 'tray.enabled';

  static const defaults = AttentionSettings();

  /// From settings.json's [values]; what is missing or not understood is
  /// the default.
  factory AttentionSettings.parse(Map<String, Object?> values) {
    final events = values[eventsKey];
    return AttentionSettings(
      enabled: switch (values[enabledKey]) {
        final bool enabled => enabled,
        _ => defaults.enabled,
      },
      sound: switch (values[soundKey]) {
        final String sound when sound.trim().isNotEmpty => sound.trim(),
        _ => defaults.sound,
      },
      when: switch (values[whenKey]) {
        'always' => NotifyWhen.always,
        _ => defaults.when,
      },
      events: events is List
          ? {
              for (final event in AttentionEvent.values)
                if (events.contains(event.name)) event,
            }
          : defaults.events,
      tray: switch (values[trayKey]) {
        final bool tray => tray,
        _ => defaults.tray,
      },
    );
  }

  final bool enabled;
  final String sound;
  final NotifyWhen when;
  final Set<AttentionEvent> events;
  final bool tray;

  /// Whether [event] is notified.
  bool notifies(AttentionEvent event) => enabled && events.contains(event);

  /// [events] as settings.json keeps them; null for the default.
  static List<String>? encodeEvents(Set<AttentionEvent> events) =>
      events.length == defaults.events.length &&
          events.containsAll(defaults.events)
      ? null
      : [
          for (final event in AttentionEvent.values)
            if (events.contains(event)) event.name,
        ];
}

/// What `notifications.sound` holds: [microwave], [manOhYeah], [none], a
/// system sound ([system]) or a sound file's path.
abstract final class NotificationSoundValue {
  /// The app's own, a microwave timer's "ding" (assets/sounds/microwave.wav).
  static const microwave = 'microwave';

  /// The bundled "man-oh-yeah" sound (assets/sounds/man-oh-yeah.wav).
  static const manOhYeah = 'man-oh-yeah';

  /// No sound.
  static const none = 'none';

  static const _systemPrefix = 'system:';

  /// The system's sound named [name] (macOS's Glass, Windows's Notify…).
  static String system(String name) => '$_systemPrefix$name';

  /// The system sound's name in [value], when it names one.
  static String? systemName(String value) => value.startsWith(_systemPrefix)
      ? value.substring(_systemPrefix.length)
      : null;

  /// Whether [value] is a sound file of the user's.
  static bool isFile(String value) =>
      value != microwave &&
      value != manOhYeah &&
      value != none &&
      systemName(value) == null;
}
