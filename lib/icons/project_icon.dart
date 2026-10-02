import 'package:flutter/widgets.dart';

import '../theme/codicons.dart';

/// What a project shows in place of its folder icon: an emoji, one of VS
/// Code's icons in a color of the theme, or a picture of the user's
/// [IconLibrary]. Kept as [toJson] (state.json's `projectIcons`).
@immutable
sealed class ProjectIcon {
  const ProjectIcon();

  /// Null for what is not one (kept by another version, or broken).
  static ProjectIcon? fromJson(Object? json) => switch (json) {
    {'type': 'emoji', 'emoji': final String emoji} when emoji.isNotEmpty =>
      EmojiIcon(emoji),
    {'type': 'codicon', 'name': final String name}
        when Codicons.byName.containsKey(name) =>
      CodiconIcon(name, color: json['color'] as String?),
    {'type': 'image', 'id': final String id} when id.isNotEmpty => LibraryIcon(
      id,
    ),
    _ => null,
  };

  Map<String, Object?> toJson();
}

final class EmojiIcon extends ProjectIcon {
  const EmojiIcon(this.emoji);

  final String emoji;

  @override
  Map<String, Object?> toJson() => {'type': 'emoji', 'emoji': emoji};

  @override
  bool operator ==(Object other) => other is EmojiIcon && other.emoji == emoji;

  @override
  int get hashCode => emoji.hashCode;

  @override
  String toString() => 'EmojiIcon($emoji)';
}

/// A codicon by its VS Code name (`folder`), drawn in the theme's [color]
/// (a color id, `charts.red`; the text's when null) so that it follows
/// the theme.
final class CodiconIcon extends ProjectIcon {
  const CodiconIcon(this.name, {this.color});

  final String name;
  final String? color;

  IconData get icon => Codicons.byName[name] ?? Codicons.folder;

  @override
  Map<String, Object?> toJson() => {
    'type': 'codicon',
    'name': name,
    'color': ?color,
  };

  @override
  bool operator ==(Object other) =>
      other is CodiconIcon && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(name, color);

  @override
  String toString() => 'CodiconIcon($name, $color)';
}

/// A picture of the [IconLibrary], by its id.
final class LibraryIcon extends ProjectIcon {
  const LibraryIcon(this.id);

  final String id;

  @override
  Map<String, Object?> toJson() => {'type': 'image', 'id': id};

  @override
  bool operator ==(Object other) => other is LibraryIcon && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LibraryIcon($id)';
}
