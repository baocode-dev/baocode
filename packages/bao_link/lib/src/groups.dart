// The desktop's group chats: the user and some of their bots, together
// (see LinkMethods.saveGroup and the others of theirs).

/// Who sent a group's message that is the user's.
const linkGroupUser = 'user';

/// Who sent a group's message that is the app's: who joined or left, as
/// a line of its own ([LinkGroupMessage.text], plain).
const linkGroupApp = '@app';

/// How many times a group's conversation may be passed on after each of
/// the user's messages, unless it says ([LinkGroup.passes]).
const linkGroupPasses = 8;

/// The fewest it may be set to.
const linkGroupLeastPasses = 2;

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
    this.holder,
    this.passesLeft = 0,
    this.passes = linkGroupPasses,
    this.rules = '',
    this.gap = 0,
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
    holder: json['holder'] as String?,
    passesLeft: (json['passesLeft'] as num?)?.toInt() ?? 0,
    passes: (json['passes'] as num?)?.toInt() ?? linkGroupPasses,
    rules: json['rules'] as String? ?? '',
    gap: (json['gap'] as num?)?.toInt() ?? 0,
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

  /// The bot that has its conversation now, if one does: one speaks at
  /// a time, and passes it on; and how many times it may still be passed.
  final String? holder;
  final int passesLeft;

  /// How many times its conversation may be passed on after each of the
  /// user's messages: [linkGroupLeastPasses] at least; 0, as many as the
  /// bots like.
  final int passes;

  /// Its rules, as the user (or the assistant) wrote them: what its bots
  /// keep to there.
  final String rules;

  /// How many seconds a bot waits, handed the conversation by another,
  /// before it answers: 0, at once.
  final int gap;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    if (typing.isNotEmpty) 'typing': typing,
    if (unread > 0) 'unread': unread,
    'last': ?last?.toJson(),
    'updated': ?updatedAt?.millisecondsSinceEpoch,
    'holder': ?holder,
    if (passesLeft > 0) 'passesLeft': passesLeft,
    if (passes != linkGroupPasses) 'passes': passes,
    if (rules.isNotEmpty) 'rules': rules,
    if (gap > 0) 'gap': gap,
  };
}

/// One of a group's messages: the [seq]th, sent at [at] by [from] (a bot's
/// id, [linkGroupUser], or [linkGroupApp]). The user's [text] as they wrote it; a bot's as
/// its reply has it, its messages and narration in their tags (see the
/// chat codec's bot parts). [images], the names of its pictures' files,
/// asked for with [LinkMethods.groupImage]. The user's may quote one
/// before it ([ref], its number); a bot's quote in its tags.
class LinkGroupMessage {
  const LinkGroupMessage({
    required this.seq,
    required this.at,
    required this.from,
    this.text = '',
    this.images = const [],
    this.ref,
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
        ref: (json['ref'] as num?)?.toInt(),
      );

  final int seq;
  final DateTime at;
  final String from;
  final String text;
  final List<String> images;
  final int? ref;

  bool get mine => from == linkGroupUser;

  /// A line of the app's: who joined or left.
  bool get notice => from == linkGroupApp;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'at': at.millisecondsSinceEpoch,
    'from': from,
    if (text.isNotEmpty) 'text': text,
    if (images.isNotEmpty) 'images': images,
    'ref': ?ref,
  };
}
