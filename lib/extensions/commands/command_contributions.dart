/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Extensions' `contributes.commands`: titles, categories, icons and
// `enablement` clauses.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/actions/common/menusExtensionPoint.ts
// (`schema.isValidCommand`, `isValidIcon`, `isValidLocalizedString`,
// `commandsExtensionPoint`'s handler) and src/vs/base/common/themables.ts
// (`ThemeIcon.fromString`).
//
// Deviations: messages for extension authors are collected in
// [CommandContributions.messages] (English) instead of an extension
// message collector; a localized title (`{value, original}`) shows its
// `value`.

import 'package:bao_exthost/bao_exthost.dart';

import '../contextkey/contextkey.dart';

/// A command's or submenu's icon: a codicon (`$(name)`) or images.
sealed class ExtensionIcon {
  const ExtensionIcon();

  /// `ThemeIcon.fromString` when [icon] is `$(name)` (or `$(name~spin)`),
  /// else image paths under [location] (`{light, dark}` or one path for
  /// both).
  static ExtensionIcon? parse(Object? icon, VsUri? location) {
    if (icon is String) {
      final theme = ThemeIconRef.fromString(icon);
      if (theme != null) return theme;
      if (location == null) return null;
      final uri = location.joinPath([icon]);
      return ImageIcon(dark: uri, light: uri);
    }
    if (icon is Map && icon['dark'] is String && icon['light'] is String) {
      if (location == null) return null;
      return ImageIcon(
        dark: location.joinPath(['${icon['dark']}']),
        light: location.joinPath(['${icon['light']}']),
      );
    }
    return null;
  }
}

/// `ThemeIcon`: a codicon by its name.
final class ThemeIconRef extends ExtensionIcon {
  const ThemeIconRef(this.id, {this.modifier});

  static final _pattern = RegExp(r'^\$\(([a-zA-Z0-9-]+)(?:~([a-zA-Z]+))?\)$');

  static ThemeIconRef? fromString(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    return ThemeIconRef(match[1]!, modifier: match[2]);
  }

  /// `symbol-class`, `refresh`…
  final String id;

  /// `spin`, `disabled`…
  final String? modifier;

  @override
  bool operator ==(Object other) =>
      other is ThemeIconRef && other.id == id && other.modifier == modifier;
  @override
  int get hashCode => Object.hash(id, modifier);
  @override
  String toString() => '\$($id${modifier == null ? '' : '~$modifier'})';
}

/// Image icons for light and dark themes.
final class ImageIcon extends ExtensionIcon {
  const ImageIcon({required this.dark, this.light});

  final VsUri dark;
  final VsUri? light;
}

/// One extension, as the extension host's scan gives it.
final class ExtensionSource {
  const ExtensionSource({
    required this.id,
    required this.name,
    this.location,
    this.isBuiltin = false,
    this.description = const {},
  });

  factory ExtensionSource.fromDescription(Map<String, Object?> description) {
    final identifier = description['identifier'];
    final id = identifier is Map
        ? '${identifier['value']}'
        : '${description['publisher']}.${description['name']}';
    final location = description['extensionLocation'];
    return ExtensionSource(
      id: id,
      name: '${description['displayName'] ?? description['name'] ?? id}',
      location: location is Map ? VsUri.tryRevive(location) : null,
      isBuiltin: description['isBuiltin'] == true,
      description: description,
    );
  }

  /// `publisher.name`.
  final String id;

  /// Its display name.
  final String name;
  final VsUri? location;
  final bool isBuiltin;
  final Map<String, Object?> description;

  Map<String, Object?> get contributes => switch (description['contributes']) {
    final Map<Object?, Object?> c => c.cast<String, Object?>(),
    _ => const {},
  };
}

/// One `contributes.commands` entry.
final class ExtensionCommandContribution {
  const ExtensionCommandContribution({
    required this.id,
    required this.title,
    required this.source,
    this.shortTitle,
    this.category,
    this.icon,
    this.enablement,
  });

  final String id;
  final String title;
  final String? shortTitle;
  final String? category;
  final ExtensionIcon? icon;

  /// `precondition`: the command is disabled when it does not hold.
  final ContextKeyExpression? enablement;
  final ExtensionSource source;

  /// `Category: Title`, as the Command Palette lists it.
  String get paletteTitle => category == null ? title : '$category: $title';
}

/// A localized string (`string | {value, original}`); null when invalid.
String? _localized(Object? value) => switch (value) {
  final String s when s.trim().isNotEmpty => s,
  {'value': final String v, 'original': final String o}
      when v.trim().isNotEmpty && o.trim().isNotEmpty =>
    v,
  _ => null,
};

/// Every extension's commands, by id: an id contributed twice keeps the
/// later extension's, as `MenuRegistry.addCommand` does.
final class CommandContributions {
  CommandContributions(List<ExtensionSource> extensions) {
    for (final extension in extensions) {
      final value = extension.contributes['commands'];
      final list = value is List ? value : value == null ? const [] : [value];
      for (final command in list) {
        _handle(command, extension);
      }
    }
  }

  final Map<String, ExtensionCommandContribution> byId = {};

  /// Problems in the manifests, for extension authors.
  final List<String> messages = [];

  void _handle(Object? raw, ExtensionSource extension) {
    void error(String message) =>
        messages.add('${extension.id}: contributes.commands: $message');
    if (raw is! Map) {
      error('expected non-empty value.');
      return;
    }
    final command = raw['command'];
    if (command is! String || command.trim().isEmpty) {
      error('property `command` is mandatory and must be of type `string`');
      return;
    }
    final title = _localized(raw['title']);
    if (title == null) {
      error('property `title` is mandatory and must be of type `string` or `object`');
      return;
    }
    final shortTitle = raw['shortTitle'] == null
        ? null
        : _localized(raw['shortTitle']);
    if (raw['shortTitle'] != null && shortTitle == null) {
      error('invalid `shortTitle`');
      return;
    }
    final enablement = raw['enablement'];
    if (enablement != null && enablement is! String) {
      error('property `precondition` can be omitted or must be of type `string`');
      return;
    }
    final category = raw['category'] == null ? null : _localized(raw['category']);
    if (raw['category'] != null && category == null) {
      error('invalid `category`');
      return;
    }
    final icon = raw['icon'];
    if (icon != null &&
        icon is! String &&
        !(icon is Map && icon['dark'] is String && icon['light'] is String)) {
      error(
        'property `icon` can be omitted or must be either a string or a '
        'literal like `{dark, light}`',
      );
      return;
    }
    if (byId[command] case final existing?) {
      messages.add(
        '${extension.id}: Command `$command` already registered by '
        '${existing.source.name} (${existing.source.id})',
      );
    }
    byId[command] = ExtensionCommandContribution(
      id: command,
      title: title,
      shortTitle: shortTitle,
      category: category,
      icon: ExtensionIcon.parse(icon, extension.location),
      enablement: enablement is String
          ? ContextKeyExpr.deserialize(enablement)
          : null,
      source: extension,
    );
  }
}
