import 'dart:math' as math;

/// The widths across the IDE: the side bar and the chat either side of the
/// editor, which has the rest. A hidden one is 0 wide.
///
/// As VS Code's grid sizes its side bars (`splitview.ts`): no widths but
/// the others' minimums hold a sash back, so one dragged past the editor's
/// minimum goes on into the view beyond it, and on past that one's minimum
/// by [snap] of it snaps that shut; one dragged below its own minimum by
/// [snap] of it snaps it shut. Either opens again as the pointer comes
/// back. The chat's, past the side bar's snapping, snaps the editor shut
/// in turn: the chat is then [chatMaximized].
class IdeColumns {
  const IdeColumns({
    required this.sidebar,
    required this.chat,
    this.chatMaximized = false,
  });

  final double sidebar;
  final double chat;

  /// Whether the chat has the editor's place, the side bar hidden: VS
  /// Code's maximized secondary side bar (`setAuxiliaryBarMaximized`).
  /// [chat] is then all the room.
  final bool chatMaximized;

  static const minSidebar = 170.0;
  static const minEditor = 320.0;
  static const minChat = 360.0;

  /// What a sash's double click restores.
  static const defaultSidebar = 240.0;
  static const defaultChat = 420.0;

  /// How far past a view's [minimum] a sash goes before the view snaps
  /// shut: a sixth of it, where splitview.ts' is half (a deviation; half
  /// was too far to drag).
  static double snap(double minimum) => minimum / 6;

  /// Whether [room] has the side bar and the chat both beside the editor,
  /// at their minimums.
  static bool roomForBoth(double room) =>
      minSidebar + minChat + minEditor <= room;

  /// The widths asked for ([sidebar], [chat]; null when hidden) in [room],
  /// all the three have: the editor keeps its minimum, taken first from the
  /// chat down to its minimum, then from the side bar down to its minimum,
  /// then the side bar hides beside the chat. With too little room even
  /// so, the editor and the one left share it by their minimums.
  static IdeColumns fit(
    double room, {
    required double? sidebar,
    required double? chat,
    bool chatMaximized = false,
  }) {
    if (chatMaximized && chat != null) {
      return IdeColumns(
        sidebar: 0,
        chat: math.max(0, room),
        chatMaximized: true,
      );
    }
    var side = sidebar == null ? 0.0 : math.max(sidebar, minSidebar);
    var talk = chat == null ? 0.0 : math.max(chat, minChat);
    double over() => side + talk + minEditor - room;
    if (over() > 0 && talk > 0) talk -= math.min(over(), talk - minChat);
    if (over() > 0 && side > 0) side -= math.min(over(), side - minSidebar);
    if (over() > 0 && talk > 0) side = 0;
    if (over() > 0 && talk > 0) {
      talk = math.max(0, room) * minChat / (minChat + minEditor);
    }
    if (over() > 0 && side > 0) {
      side = math.max(0, room) * minSidebar / (minSidebar + minEditor);
    }
    return IdeColumns(sidebar: side, chat: talk);
  }

  double editor(double room) => room - sidebar - chat;

  /// The widest the side bar may be in [room]: the others at their minimums.
  double mostSidebar(double room) =>
      room - minEditor - (chat > 0 ? minChat : 0);

  double mostChat(double room) =>
      room - minEditor - (sidebar > 0 ? minSidebar : 0);

  /// Whether the side bar's sash can go right: the side bar is not as wide
  /// as it may be, or, hidden, has room to open.
  bool canGrowSidebar(double room) => sidebar > 0
      ? mostSidebar(room) > sidebar + _slack
      : mostSidebar(room) >= minSidebar;

  bool canGrowChat(double room) =>
      !chatMaximized &&
      (chat > 0 ? mostChat(room) > chat + _slack : mostChat(room) >= minChat);

  /// Less than a pixel is at the limit.
  static const _slack = 0.5;

  /// How narrow [width] (0 when hidden) gets before it snaps shut: [snap]
  /// short of [minimum], or of [width] where there is too little room for
  /// even that.
  static double _shutBelow(double width, double minimum) =>
      (width > 0 ? math.min(width, minimum) : minimum) - snap(minimum);

  /// These widths, from when a drag began, with the side bar's sash [dx]
  /// further right: the editor gives way first, then the chat, then the
  /// chat snaps shut and the side bar follows the pointer.
  IdeColumns dragSidebar(double room, double dx) {
    final target = sidebar + dx;
    if (target < _shutBelow(sidebar, minSidebar)) {
      return IdeColumns(sidebar: 0, chat: chat);
    }
    final alone = room - minEditor;
    if (chat > 0 &&
        target >= mostSidebar(room) + snap(minChat) &&
        alone >= minSidebar) {
      return IdeColumns(
        sidebar: target.clamp(minSidebar, alone).toDouble(),
        chat: 0,
      );
    }
    final most = mostSidebar(room);
    if (most < minSidebar) return this;
    final side = target.clamp(minSidebar, most).toDouble();
    return IdeColumns(
      sidebar: side,
      chat: chat > 0 ? math.min(chat, room - minEditor - side) : 0,
    );
  }

  /// With the chat's sash [dx] further right: growing, the editor gives
  /// way first, then the side bar, which then snaps shut, then the editor
  /// snaps shut, and the chat is maximized. From maximized, the editor
  /// comes back as the pointer does.
  IdeColumns dragChat(double room, double dx) {
    final target = chat - dx;
    if (target < _shutBelow(chat, minChat)) {
      return IdeColumns(sidebar: sidebar, chat: 0);
    }
    // The editor as it would be, the side bar snapped shut first.
    final editorShutBelow = chatMaximized
        ? minEditor - snap(minEditor)
        : _shutBelow(editor(room), minEditor);
    if (room - target < editorShutBelow) {
      return IdeColumns(sidebar: 0, chat: room, chatMaximized: true);
    }
    final alone = room - minEditor;
    if (sidebar > 0 &&
        target >= mostChat(room) + snap(minSidebar) &&
        alone >= minChat) {
      return IdeColumns(
        sidebar: 0,
        chat: target.clamp(minChat, alone).toDouble(),
      );
    }
    final most = mostChat(room);
    if (most < minChat) return this;
    final talk = target.clamp(minChat, most).toDouble();
    return IdeColumns(
      sidebar: sidebar > 0 ? math.min(sidebar, room - minEditor - talk) : 0,
      chat: talk,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdeColumns &&
      other.sidebar == sidebar &&
      other.chat == chat &&
      other.chatMaximized == chatMaximized;

  @override
  int get hashCode => Object.hash(sidebar, chat, chatMaximized);

  @override
  String toString() => chatMaximized
      ? 'IdeColumns(chat maximized: $chat)'
      : 'IdeColumns(sidebar: $sidebar, chat: $chat)';
}
