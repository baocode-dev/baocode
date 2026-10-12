// The few sizes the UI is drawn in, so screens share one rhythm: what text
// is set in, how round corners are, and the steps space comes in. Colors
// stay the theme's (see AppColors); code keeps CodeFont's sizes, and the
// whole is scaled by window.uiScale.

/// Text sizes, smallest first.
abstract final class UiText {
  /// Timestamps, counts, badges: "2d", "+12 -3".
  static const double caption = 11;

  /// What is said about something: a step's line ("Ran …", "Thought 2s"),
  /// hints, secondary lines.
  static const double secondary = 12;

  /// The UI's own text: lists, menus, buttons, inputs.
  static const double body = 13;

  /// What is there to be read at length: the agent's replies, the user's
  /// messages.
  static const double reading = 14;

  /// A line reading text is set in, as a multiple of its size.
  static const double readingHeight = 1.55;

  /// Titles: a chat's, a dialog's, a card's.
  static const double title = 15;
}

/// Corner radii.
abstract final class UiRadius {
  /// Tags, inline code, thumbnails' insets.
  static const double small = 4;

  /// Buttons, rows' hover, chips.
  static const double medium = 6;

  /// Cards, inputs, popups, bubbles.
  static const double large = 10;
}

/// Spacing comes in steps of 4.
abstract final class UiSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Between paragraphs of reading text.
  static const double paragraph = md;
}
