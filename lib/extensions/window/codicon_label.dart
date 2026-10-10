// Text with `$(codicon)`s in it, as extensions give labels (a status
// item's text, an SCM action button's title): VS Code's
// `renderLabelWithIcons` (src/vs/base/browser/ui/iconLabel/iconLabels.ts)
// at 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0).

import 'package:flutter/material.dart';

import '../../theme/codicons.dart';
import '../../theme/icon_registry.dart';

/// A label with `$(codicon)`s in it, as a button's title has.
final class ExtensionLabel {
  ExtensionLabel._(this.parts);

  static final _icon = RegExp(r'\$\(([a-zA-Z0-9-]+)(?:~[a-zA-Z]+)?\)');

  factory ExtensionLabel.parse(String text) {
    final parts = <Object>[];
    var index = 0;
    for (final match in _icon.allMatches(text)) {
      if (match.start > index) parts.add(text.substring(index, match.start));
      parts.add(ExtensionLabelIcon(match[1]!));
      index = match.end;
    }
    if (index < text.length) parts.add(text.substring(index));
    return ExtensionLabel._(parts);
  }

  /// Text and [ExtensionLabelIcon]s.
  final List<Object> parts;

  Widget build({required double fontSize, required Color color}) => Text.rich(
    TextSpan(
      children: [
        for (final part in parts)
          if (part case ExtensionLabelIcon(:final id))
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ThemeIcon(
                id,
                size: fontSize + 2,
                color: color,
                fallback: Codicons.circleOutline,
              ),
            )
          else
            TextSpan(text: '$part'),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fontSize, color: color),
  );
}

/// An icon in an [ExtensionLabel], by id: a codicon or an extension's.
final class ExtensionLabelIcon {
  const ExtensionLabelIcon(this.id);

  final String id;

  @override
  bool operator ==(Object other) =>
      other is ExtensionLabelIcon && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
