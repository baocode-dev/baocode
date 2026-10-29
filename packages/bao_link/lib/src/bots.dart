// The desktop's bots, as the phone lists and edits them (see
// LinkMethods.saveBot and the others of theirs).

/// What a bot may do, each turned on by the user: none for a new bot, all
/// for the assistant the desktop starts with.
enum BotAbility {
  /// Sees the agents and what they said.
  viewChats,

  /// Stops an agent, has it try again, archives it.
  manageTasks,

  /// Writes to an agent, as the user would.
  sendToChats,

  /// Starts an agent in a project.
  newChat,

  /// Reads the projects' files.
  readFiles,

  /// Uses the user's browser, as the agents may.
  browser,

  /// Makes pictures, with the image model the desktop has set up.
  images,

  /// Writes first, of what happened (an agent waits, fails).
  proactive,
}

/// When a bot may write first ([BotAbility.proactive]): at most [perDay]
/// times a day (none for 0), never from [quietFrom] to [quietTo] (minutes
/// into the day, the desktop's time; the same for no quiet hours).
class BotProactive {
  const BotProactive({
    this.perDay = 6,
    this.quietFrom = 23 * 60,
    this.quietTo = 8 * 60,
  });

  factory BotProactive.fromJson(Map<String, Object?> json) => BotProactive(
    perDay: (json['perDay'] as num?)?.toInt() ?? 6,
    quietFrom: (json['quietFrom'] as num?)?.toInt() ?? 23 * 60,
    quietTo: (json['quietTo'] as num?)?.toInt() ?? 8 * 60,
  );

  final int perDay;
  final int quietFrom;
  final int quietTo;

  /// Whether [minute] (into the day) is in the quiet hours, which may span
  /// midnight.
  bool isQuiet(int minute) {
    if (quietFrom == quietTo) return false;
    return quietFrom < quietTo
        ? minute >= quietFrom && minute < quietTo
        : minute >= quietFrom || minute < quietTo;
  }

  Map<String, Object?> toJson() => {
    'perDay': perDay,
    'quietFrom': quietFrom,
    'quietTo': quietTo,
  };

  @override
  bool operator ==(Object other) =>
      other is BotProactive &&
      other.perDay == perDay &&
      other.quietFrom == quietFrom &&
      other.quietTo == quietTo;

  @override
  int get hashCode => Object.hash(perDay, quietFrom, quietTo);
}

/// A bot: an agent of the user's own making that talks as a person does,
/// who it is ([gender], [signature], [identity], [style]) all the user's
/// words; what it may do, its
/// [abilities]. Its conversation is [session] (none until the first
/// message), on the desktop, its memory there too.
class LinkBot {
  const LinkBot({
    required this.id,
    required this.name,
    this.avatar,
    this.gender = '',
    this.signature = '',
    this.identity = '',
    this.style = '',
    this.abilities = const {},
    this.proactive = const BotProactive(),
    this.model,
    this.assistant = false,
    this.session,
    this.status = BotStatus.idle,
    this.unread = 0,
    this.last,
    this.updatedAt,
  });

  factory LinkBot.fromJson(Map<String, Object?> json) => LinkBot(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    avatar: json['avatar'] as String?,
    gender: json['gender'] as String? ?? '',
    signature: json['signature'] as String? ?? '',
    identity: json['identity'] as String? ?? '',
    style: json['style'] as String? ?? '',
    abilities: {
      for (final name in (json['abilities'] as List?) ?? const [])
        ?BotAbility.values.asNameMap()[name],
    },
    proactive: switch (json['proactive']) {
      final Map<String, Object?> proactive => BotProactive.fromJson(proactive),
      _ => const BotProactive(),
    },
    model: json['model'] as String?,
    assistant: json['assistant'] == true,
    session: json['session'] as String?,
    status: BotStatus.values.asNameMap()[json['status']] ?? BotStatus.idle,
    unread: (json['unread'] as num?)?.toInt() ?? 0,
    last: json['last'] as String?,
    updatedAt: switch (json['updated']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => null,
    },
  );

  final String id;
  final String name;

  /// An emoji, or a picture ([isAvatarImage]: the name of its file on the
  /// desktop, asked for with [LinkMethods.botAvatar]); none for its name's
  /// first letter.
  final String? avatar;

  /// Whether its [avatar] is a picture.
  bool get hasAvatarImage => isAvatarImage(avatar);

  /// As the user put it: a word, or none.
  final String gender;

  /// A line under its name.
  final String signature;

  /// Who it is, as the user wrote it.
  final String identity;

  /// How it talks, as the user wrote it.
  final String style;
  final Set<BotAbility> abilities;
  final BotProactive proactive;

  /// The model its conversation runs on, as the model picker names it;
  /// it is picked there ([LinkMethods.choose]).
  final String? model;

  /// The one the desktop starts with: not deleted.
  final bool assistant;

  /// Its conversation's id ([SessionSummary.id]'s kind).
  final String? session;
  final BotStatus status;

  /// Its messages since the user last read it.
  final int unread;

  /// The last it said, one line.
  final String? last;
  final DateTime? updatedAt;

  bool can(BotAbility ability) => abilities.contains(ability);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatar': ?avatar,
    if (gender.isNotEmpty) 'gender': gender,
    if (signature.isNotEmpty) 'signature': signature,
    'identity': identity,
    if (style.isNotEmpty) 'style': style,
    'abilities': [
      for (final ability in BotAbility.values)
        if (abilities.contains(ability)) ability.name,
    ],
    'proactive': proactive.toJson(),
    'model': ?model,
    if (assistant) 'assistant': true,
    'session': ?session,
    'status': status.name,
    if (unread > 0) 'unread': unread,
    'last': ?last,
    'updated': ?updatedAt?.millisecondsSinceEpoch,
  };
}

/// Whether a bot is writing.
enum BotStatus { idle, typing }

/// Whether [avatar] (a bot's) is a picture, by its file's name, rather
/// than an emoji. Its name changes with what it shows.
bool isAvatarImage(String? avatar) =>
    avatar != null && _avatarFile.hasMatch(avatar);

final _avatarFile = RegExp(r'^[\w-]+\.(png|jpe?g|webp|gif)$');

/// One of the stickers the app comes with: its [id], as a message names it
/// (`[Sticker: id]`, see the chat codec) and the phone's picture of it;
/// what it says, in English ([en]) and Chinese ([zh]).
class LinkSticker {
  const LinkSticker(this.id, this.en, this.zh);

  final String id;
  final String en;
  final String zh;
}

/// The stickers the app comes with, as the phone shows them to pick.
const builtInStickers = [
  LinkSticker('hi', 'hi', '嗨'),
  LinkSticker('ok', 'OK, thumbs up', '好的'),
  LinkSticker('happy', 'happy', '开心'),
  LinkSticker('laugh', 'laughing', '哈哈'),
  LinkSticker('love', 'love it', '喜欢'),
  LinkSticker('thanks', 'thank you', '谢谢'),
  LinkSticker('thinking', 'thinking', '想想'),
  LinkSticker('confused', 'confused', '疑惑'),
  LinkSticker('surprised', 'surprised', '惊讶'),
  LinkSticker('sad', 'sad', '难过'),
  LinkSticker('cry', 'crying', '哭哭'),
  LinkSticker('angry', 'angry', '生气'),
  LinkSticker('sleepy', 'sleepy', '困了'),
  LinkSticker('awkward', 'awkward', '尴尬'),
  LinkSticker('cool', 'cool', '酷'),
  LinkSticker('party', 'celebrating', '庆祝'),
];

/// The built-in sticker [id], if there is one.
LinkSticker? builtInSticker(String id) {
  for (final sticker in builtInStickers) {
    if (sticker.id == id) return sticker;
  }
  return null;
}
