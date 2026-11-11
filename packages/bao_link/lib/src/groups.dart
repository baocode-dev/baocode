// The desktop's group chats: the user and some of their bots, together
// (see LinkMethods.saveGroup and the others of theirs).

/// Who sent a group's message that is the user's.
const linkGroupUser = 'user';

/// A group chat of the user and some of their bots ([members], by their
/// ids). Its messages are the desktop's, sent as they come
/// ([LinkEvents.group]).
class LinkGroup {
  const LinkGroup({
    required this.id,
    required this.name,
    this.members = const [],
    this.typing = const [],
    this.unread = 0,
    this.last,
    this.updatedAt,
  });

  factory LinkGroup.fromJson(Map<String, Object?> json) => LinkGroup(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    members: [
      for (final member in (json['members'] as List?) ?? const [])
        if (member is String) member,
    ],
    typing: [
      for (final member in (json['typing'] as List?) ?? const [])
        if (member is String) member,
    ],
    unread: (json['unread'] as num?)?.toInt() ?? 0,
    last: switch (json['last']) {
      final Map<String, Object?> last => LinkGroupMessage.fromJson(last),
      _ => null,
    },
    updatedAt: switch (json['updated']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => null,
    },
  );

  final String id;
  final String name;

  /// Its bots, by their ids, in the order they joined.
  final List<String> members;

  /// Those of its bots writing now.
  final List<String> typing;

  /// Its messages since the user last read it.
  final int unread;

  /// Its last message.
  final LinkGroupMessage? last;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    if (typing.isNotEmpty) 'typing': typing,
    if (unread > 0) 'unread': unread,
    'last': ?last?.toJson(),
    'updated': ?updatedAt?.millisecondsSinceEpoch,
  };
}

/// One of a group's messages: the [seq]th, sent at [at] by [from] (a bot's
/// id, or [linkGroupUser]). The user's [text] as they wrote it; a bot's as
/// its reply has it, its messages and narration in their tags (see the
/// chat codec's bot parts). [images], the names of its pictures' files,
/// asked for with [LinkMethods.groupImage].
class LinkGroupMessage {
  const LinkGroupMessage({
    required this.seq,
    required this.at,
    required this.from,
    this.text = '',
    this.images = const [],
  });

  factory LinkGroupMessage.fromJson(Map<String, Object?> json) =>
      LinkGroupMessage(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch(
          (json['at'] as num?)?.toInt() ?? 0,
        ),
        from: json['from'] as String? ?? linkGroupUser,
        text: json['text'] as String? ?? '',
        images: [
          for (final image in (json['images'] as List?) ?? const [])
            if (image is String) image,
        ],
      );

  final int seq;
  final DateTime at;
  final String from;
  final String text;
  final List<String> images;

  bool get mine => from == linkGroupUser;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'at': at.millisecondsSinceEpoch,
    'from': from,
    if (text.isNotEmpty) 'text': text,
    if (images.isNotEmpty) 'images': images,
  };
}
