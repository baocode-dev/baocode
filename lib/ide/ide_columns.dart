import 'dart:math' as math;

/// The widths across the IDE: the side bar and the chat either side of the
/// editor, which has the rest. A hidden one is 0 wide.
///
/// As VS Code's grid sizes its side bars (`splitview.ts`): no widths but
/// the others' minimums hold a sash back, so one dragged past the editor's
/// minimum goes on into the view beyond it, and on past that one's minimum
/// by half of it snaps that shut; one dragged below half its own minimum
/// snaps it shut. Either opens again as the pointer comes back.
class IdeColumns {
  const IdeColumns({required this.sidebar, required this.chat});

  final double sidebar;
  final double chat;

  static const minSidebar = 170.0;
  static const minEditor = 320.0;
  static const minChat = 360.0;

  /// What a sash's double click restores.
  static const defaultSidebar = 240.0;
  static const defaultChat = 420.0;

  /// The widths asked for ([sidebar], [chat]; null when hidden) in [room],
  /// all the three have: the editor keeps its minimum, taken first from the
  /// chat down to its minimum, then from the side bar down to its minimum,
  /// then the side bar hides. With too little room even so, the editor and
  /// the chat share it by their minimums.
  static IdeColumns fit(
    double room, {
    required double? sidebar,
    required double? chat,
  }) {
    var side = sidebar == null ? 0.0 : math.max(sidebar, minSidebar);
    var talk = chat == null ? 0.0 : math.max(chat, minChat);
    double over() => side + talk + minEditor - room;
    if (over() > 0 && talk > 0) talk -= math.min(over(), talk - minChat);
    if (over() > 0 && side > 0) side -= math.min(over(), side - minSidebar);
    if (over() > 0) side = 0;
    if (over() > 0 && talk > 0) {
      talk = math.max(0, room) * minChat / (minChat + minEditor);
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
      chat > 0 ? mostChat(room) > chat + _slack : mostChat(room) >= minChat;

  /// Less than a pixel is at the limit.
  static const _slack = 0.5;

  /// These widths, from when a drag began, with the side bar's sash [dx]
  /// further right: the editor gives way first, then the chat, then the
  /// chat snaps shut and the side bar follows the pointer.
  IdeColumns dragSidebar(double room, double dx) {
    final target = sidebar + dx;
    if (target < minSidebar / 2) return IdeColumns(sidebar: 0, chat: chat);
    final alone = room - minEditor;
    if (chat > 0 &&
        target >= mostSidebar(room) + minChat / 2 &&
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
  /// way first, then the side bar, which then snaps shut.
  IdeColumns dragChat(double room, double dx) {
    final target = chat - dx;
    if (target < minChat / 2) return IdeColumns(sidebar: sidebar, chat: 0);
    final alone = room - minEditor;
    if (sidebar > 0 &&
        target >= mostChat(room) + minSidebar / 2 &&
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
      other is IdeColumns && other.sidebar == sidebar && other.chat == chat;

  @override
  int get hashCode => Object.hash(sidebar, chat);

  @override
  String toString() => 'IdeColumns(sidebar: $sidebar, chat: $chat)';
}
