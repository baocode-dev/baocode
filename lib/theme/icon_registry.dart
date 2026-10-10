// Icons by id: the codicons, and those extensions contribute
// (`contributes.icons`), with the fonts they come in.
//
// Adapted from VS Code 1.135.0 (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5):
// src/vs/workbench/services/themes/common/iconExtensionPoint.ts
// (`IconExtensionPoint`, `getFontId`) and
// src/vs/platform/theme/common/iconRegistry.ts (`registerIcon`,
// `registerIconFont`, `deregisterIcon`; a default naming another icon is
// that icon).
//
// Deviations: a font is loaded through Flutter's font loader under its font
// id and stays loaded (Flutter cannot unload one); its icons go with their
// extension. An invalid entry skips the rest of its extension's (upstream
// it ends the whole delta's handling).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'codicons.dart';

/// An icon of a font an extension contributes: [codePoint] in
/// [fontFamily]. Not an [IconData], whose values must be constants.
@immutable
final class ExtensionGlyph {
  const ExtensionGlyph(this.codePoint, this.fontFamily);

  final int codePoint;
  final String fontFamily;

  @override
  bool operator ==(Object other) =>
      other is ExtensionGlyph &&
      other.codePoint == codePoint &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(codePoint, fontFamily);
}

/// The icon [id] names, at [size] in [color] (the [IconTheme]'s when
/// null): a codicon, an extension's icon, else [fallback] (nothing when
/// that is null). Follows [IconRegistry.instance] as extensions come and go.
class ThemeIcon extends StatelessWidget {
  const ThemeIcon(this.id, {super.key, this.size, this.color, this.fallback});

  final String id;
  final double? size;
  final Color? color;
  final IconData? fallback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: IconRegistry.instance,
    builder: (context, _) => switch (IconRegistry.instance.lookup(id) ??
        fallback) {
      final IconData icon => Icon(icon, size: size, color: color),
      final ExtensionGlyph glyph => _GlyphIcon(glyph, size: size, color: color),
      _ => SizedBox.square(dimension: size ?? IconTheme.of(context).size),
    },
  );
}

/// [glyph] as [Icon] paints a font icon.
class _GlyphIcon extends StatelessWidget {
  const _GlyphIcon(this.glyph, {this.size, this.color});

  final ExtensionGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = this.color ?? theme.color;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: RichText(
            overflow: TextOverflow.visible,
            textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
            text: TextSpan(
              text: String.fromCharCode(glyph.codePoint),
              style: TextStyle(
                inherit: false,
                color: color,
                fontSize: size,
                fontFamily: glyph.fontFamily,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One extension's `contributes.icons`: its id, folder and the object.
typedef ExtensionIconContribution = ({
  String extensionId,
  String location,
  Map<String, Object?> icons,
});

/// The icons by id; extensions' icons are [setExtensionIcons]'. Listeners
/// hear when they change, and when a font has loaded.
class IconRegistry extends ChangeNotifier {
  /// The app's registry; tests replace it.
  static IconRegistry instance = IconRegistry();

  /// `ThemeIcon.iconNameSegment`, twice or more.
  static final _idPattern = RegExp(r'^[A-Za-z0-9]+(-[A-Za-z0-9]+)+$');

  static const _formats = {'ttf', 'woff', 'woff2'};

  /// What an extension's icon is: an [IconData], or the id of another.
  final Map<String, Object> _icons = {};
  final Set<String> _fonts = {};
  String? _key;

  /// Loads a font's bytes as [family]; Flutter's font loader by default.
  @visibleForTesting
  Future<void> Function(String family, Uint8List bytes) loadFont =
      (family, bytes) => (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();

  /// The icon [id] names: a codicon's [IconData], an extension's
  /// [ExtensionGlyph], or null.
  Object? lookup(String id) {
    Object? icon = Codicons.byName[id] ?? _icons[id];
    // A default naming another icon, followed a few times at most.
    for (var hops = 0; icon is String && hops < 8; hops++) {
      icon = Codicons.byName[icon] ?? _icons[icon];
    }
    return icon is String ? null : icon;
  }

  /// Whether [id] is an icon [lookup] finds.
  bool contains(String id) => lookup(id) != null;

  /// The running extensions' `contributes.icons`: each id with a
  /// description and a default, another icon's id or `{fontPath,
  /// fontCharacter}` in a `ttf`/`woff`/`woff2` inside the extension's
  /// folder. Those no longer contributed go.
  void setExtensionIcons(List<ExtensionIconContribution> contributions) {
    final key = [
      for (final c in contributions) [c.extensionId, c.location, c.icons],
    ].toString();
    if (key == _key) return;
    _key = key;
    _icons.clear();
    final fonts = <String, String>{};
    for (final (:extensionId, :location, :icons) in contributions) {
      for (final MapEntry(key: id, value: contribution) in icons.entries) {
        if (!_idPattern.hasMatch(id)) break;
        if (contribution is! Map) break;
        final description = contribution['description'];
        if (description is! String || description.isEmpty) break;
        final defaultIcon = contribution['default'];
        if (defaultIcon is String) {
          _icons[id] = defaultIcon;
        } else if (defaultIcon case {
          'fontPath': final String fontPath,
          'fontCharacter': final String fontCharacter,
        }) {
          final extension = p.extension(fontPath).replaceFirst('.', '');
          if (!_formats.contains(extension)) break;
          final file = p.normalize(p.join(location, fontPath));
          if (!p.isWithin(location, file)) break;
          final codePoint = _codePoint(fontCharacter);
          if (codePoint == null) continue;
          // `getFontId`.
          final fontId = p.posix.join(extensionId, fontPath);
          fonts[fontId] = file;
          _icons[id] = ExtensionGlyph(codePoint, fontId);
        }
      }
    }
    for (final MapEntry(key: family, value: file) in fonts.entries) {
      if (_fonts.add(family)) unawaited(_load(family, file));
    }
    notifyListeners();
  }

  Future<void> _load(String family, String file) async {
    try {
      await loadFont(family, await File(file).readAsBytes());
    } on Object {
      // Not readable or not a font: its icons show nothing, as a font that
      // fails to load upstream.
      return;
    }
    notifyListeners();
  }

  /// A CSS `content` string's character: `\f101` (a CSS escape, as the
  /// string goes into the rule) or the character itself.
  static int? _codePoint(String fontCharacter) {
    final escape = RegExp(r'^\\([0-9a-fA-F]{1,6})').firstMatch(fontCharacter);
    if (escape != null) return int.parse(escape[1]!, radix: 16);
    return fontCharacter.isEmpty ? null : fontCharacter.runes.first;
  }
}
