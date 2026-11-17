// What a conversation shows of the user's others it works with (the
// `session_*` tools, see workspace/session_tools.dart): their names in its
// steps and cards, opened with a click, and those it handed work to over
// its composer, as each stands. The workspace answers (see
// workspace/session_links_host.dart); without it, none of it links.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'chat_session.dart';

/// How a conversation handed work stands.
enum HandedStatus { running, waiting, done, failed }

/// A conversation another handed work to, as it stands.
@immutable
class HandedConversation {
  const HandedConversation({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;
  final HandedStatus status;

  @override
  bool operator ==(Object other) =>
      other is HandedConversation &&
      other.id == id &&
      other.title == title &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, title, status);
}

/// The user's conversations, by their ids as the `session_*` tools give
/// them.
abstract interface class SessionLinkHost {
  /// Its title; null for none there is.
  String? titleOf(String id);

  /// How it stands; null for none there is.
  HandedStatus? statusOf(String id);

  /// Told as how they stand changes.
  Listenable get statuses;

  /// Shows it.
  void open(String id);

  /// Those [session] handed work to, as they stand: told as that changes.
  ValueListenable<List<HandedConversation>> handedFrom(ChatSession session);
}

/// The [SessionLinkHost] for what is under it.
class SessionLinks extends InheritedWidget {
  const SessionLinks({super.key, required this.host, required super.child});

  final SessionLinkHost host;

  static SessionLinkHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionLinks>()?.host;

  @override
  bool updateShouldNotify(SessionLinks oldWidget) =>
      !identical(oldWidget.host, host);
}

/// Whether [tool] (a step's) is one of the `session_*` tools.
bool isSessionTool(String? tool) => tool != null && tool.startsWith('session_');
