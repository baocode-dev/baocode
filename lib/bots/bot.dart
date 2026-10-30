import 'package:bao_link/bao_link.dart'
    show BotAbility, BotProactive, isAvatarImage;
import 'package:path/path.dart' as p;

export 'package:bao_link/bao_link.dart'
    show BotAbility, BotProactive, isAvatarImage;

/// A bot as the user made it: who it is ([identity], [gender], [style],
/// their words) and what it may do ([abilities]). It is a folder of its own ([folder]): its
/// conversation runs there, and all of it is kept there in files (see
/// bot_files.dart). [proactive] is the phone's: unused, it judges for
/// itself.
class Bot {
  const Bot({
    required this.id,
    required this.name,
    required this.folder,
    this.avatar,
    this.gender = '',
    this.signature = '',
    this.identity = '',
    this.style = '',
    this.abilities = const {},
    this.proactive = const BotProactive(),
    this.model,
    this.assistant = false,
    this.created,
  });

  final String id;
  final String name;

  /// Where its conversation runs, and its memory is kept.
  final String folder;

  /// An emoji, or its picture: the name of its file in [folder]
  /// ([isAvatarImage]); none for its name's first letter.
  final String? avatar;

  /// Its picture's file, if it has one.
  String? get avatarFile =>
      isAvatarImage(avatar) ? p.join(folder, avatar) : null;

  /// As the user put it: a word, or none.
  final String gender;

  /// A line under its name, as the user wrote it.
  final String signature;

  /// Who it is, as the user wrote it.
  final String identity;

  /// How it talks, as the user wrote it.
  final String style;
  final Set<BotAbility> abilities;
  final BotProactive proactive;

  /// The model it runs on; none for the app's.
  final String? model;

  /// The one the app starts with, which is not deleted.
  final bool assistant;

  /// When the user made it, where known.
  final DateTime? created;

  bool can(BotAbility ability) => abilities.contains(ability);

  Bot copyWith({
    String? name,
    String? avatar,
    bool clearAvatar = false,
    String? gender,
    String? signature,
    String? identity,
    String? style,
    Set<BotAbility>? abilities,
    BotProactive? proactive,
    String? model,
  }) => Bot(
    id: id,
    name: name ?? this.name,
    folder: folder,
    avatar: clearAvatar ? null : avatar ?? this.avatar,
    gender: gender ?? this.gender,
    signature: signature ?? this.signature,
    identity: identity ?? this.identity,
    style: style ?? this.style,
    abilities: abilities ?? this.abilities,
    proactive: proactive ?? this.proactive,
    model: model ?? this.model,
    assistant: assistant,
    created: created,
  );
}

/// Who the user is, as they put it on their phone (its profile): for
/// their bots to know them by. [picture] is the file in the bots' folder
/// their picture is kept in.
class BotUser {
  const BotUser({
    this.name = '',
    this.gender = '',
    this.signature = '',
    this.picture,
  });

  final String name;
  final String gender;

  /// The line under their name.
  final String signature;
  final String? picture;

  bool get isEmpty =>
      name.isEmpty && gender.isEmpty && signature.isEmpty && picture == null;

  BotUser withPicture(String? picture) => BotUser(
    name: name,
    gender: gender,
    signature: signature,
    picture: picture,
  );

  Map<String, Object?> toJson() => {
    if (name.isNotEmpty) 'name': name,
    if (gender.isNotEmpty) 'gender': gender,
    if (signature.isNotEmpty) 'signature': signature,
    'picture': ?picture,
  };

  static BotUser fromJson(Object? json) {
    if (json is! Map) return const BotUser();
    String text(String key) => switch (json[key]) {
      final String value => value.trim(),
      _ => '',
    };
    return BotUser(
      name: text('name'),
      gender: text('gender'),
      signature: text('signature'),
      picture: switch (json['picture']) {
        final String file when file.isNotEmpty => file,
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BotUser &&
      other.name == name &&
      other.gender == gender &&
      other.signature == signature &&
      other.picture == picture;

  @override
  int get hashCode => Object.hash(name, gender, signature, picture);
}
