// File icon themes of extensions (`contributes.iconThemes`): the explorer's,
// tabs' and quick open's file and folder icons, where `workbench.iconTheme`
// names one. Without, the bundled Material Icon Theme
// (material_file_icons.dart) draws them.
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/themes/browser/fileIconThemeData.ts (the
// theme file's shape, `light` and `highContrast` sections over the base,
// font definitions) and src/vs/editor/common/services/getIconClasses.ts
// (a file by its name and its dotted extensions, longest first, then its
// language, then `file`; a folder by its name, then `folder`; the project's
// own by `rootFolderNames`, then `rootFolder`).
//
// Deviations: a font glyph needs the font as TTF or OTF (Flutter loads no
// WOFF); `hidesExplorerArrows` and `showLanguageModeIcons` are not read.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../platform/svg_file.dart';
import '../settings/jsonc.dart';

/// One icon of a theme: an image file, or a font's glyph.
@immutable
class FileIconDefinition {
  const FileIconDefinition({
    this.iconPath,
    this.fontCharacter,
    this.fontColor,
    this.fontFamily,
    this.fontSize,
  });

  /// An absolute path to an .svg or .png.
  final String? iconPath;
  final String? fontCharacter;
  final Color? fontColor;

  /// The loaded font's family (see [FileIconThemeData.load]).
  final String? fontFamily;

  /// A size relative to the icon's (`150%`); null for the icon's.
  final double? fontSize;
}

/// The mappings of one section (the base, `light` or `highContrast`).
class _Associations {
  _Associations(Map<String, Object?> json)
    : file = json['file'] as String?,
      folder = json['folder'] as String?,
      folderExpanded = json['folderExpanded'] as String?,
      rootFolder = json['rootFolder'] as String?,
      rootFolderExpanded = json['rootFolderExpanded'] as String?,
      fileExtensions = _lowerKeys(json['fileExtensions']),
      fileNames = _lowerKeys(json['fileNames']),
      folderNames = _lowerKeys(json['folderNames']),
      folderNamesExpanded = _lowerKeys(json['folderNamesExpanded']),
      rootFolderNames = _lowerKeys(json['rootFolderNames']),
      rootFolderNamesExpanded = _lowerKeys(json['rootFolderNamesExpanded']),
      languageIds = _lowerKeys(json['languageIds'], lower: false);

  final String? file;
  final String? folder;
  final String? folderExpanded;
  final String? rootFolder;
  final String? rootFolderExpanded;
  final Map<String, String> fileExtensions;
  final Map<String, String> fileNames;
  final Map<String, String> folderNames;
  final Map<String, String> folderNamesExpanded;
  final Map<String, String> rootFolderNames;
  final Map<String, String> rootFolderNamesExpanded;
  final Map<String, String> languageIds;

  static Map<String, String> _lowerKeys(Object? json, {bool lower = true}) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is String)
          (lower ? key.toLowerCase() : key): value,
  };
}

/// A file icon theme, read from its file.
class FileIconThemeData {
  FileIconThemeData._(
    this.id,
    this._definitions,
    this._base,
    this._light,
    this._highContrast,
  );

  /// The settings id (`workbench.iconTheme`).
  final String id;
  final Map<String, FileIconDefinition> _definitions;
  final _Associations _base;
  final _Associations? _light;
  final _Associations? _highContrast;

  static int _fonts = 0;

  /// Reads the theme at [path] (absolute), loading its TTF/OTF fonts.
  static Future<FileIconThemeData> load(String id, String path) async {
    final json = switch (parseJsonc(await File(path).readAsString())) {
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => throw FormatException('Not an icon theme: $path'),
    };
    final folder = p.dirname(path);
    final families = <String, ({String family, double? size})>{};
    for (final font in switch (json['fonts']) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    }) {
      if (font case {
        'id': final String fontId,
        'src': final List<Object?> sources,
      }) {
        for (final source in sources) {
          if (source case {'path': final String fontPath}) {
            final file = p.normalize(p.join(folder, fontPath));
            final extension = p.extension(file).toLowerCase();
            if (extension != '.ttf' && extension != '.otf') continue;
            try {
              final family = 'baocode-file-icons-${_fonts++}';
              final bytes = await File(file).readAsBytes();
              await (FontLoader(
                family,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
              families[fontId] = (family: family, size: _percent(font['size']));
              break;
            } on Object {
              // A font that does not load: its glyphs show nothing.
            }
          }
        }
      }
    }
    final defaultFont = families.values.firstOrNull;
    final definitions = <String, FileIconDefinition>{};
    if (json['iconDefinitions'] case final Map<Object?, Object?> icons) {
      for (final MapEntry(:key, :value) in icons.entries) {
        if (key is! String || value is! Map) continue;
        final font = switch (value['fontId']) {
          final String fontId => families[fontId],
          _ => defaultFont,
        };
        definitions[key] = FileIconDefinition(
          iconPath: switch (value['iconPath']) {
            final String icon => p.normalize(p.join(folder, icon)),
            _ => null,
          },
          fontCharacter: switch (value['fontCharacter']) {
            final String character => _character(character),
            _ => null,
          },
          fontColor: _color(value['fontColor']),
          fontFamily: font?.family,
          fontSize: _percent(value['fontSize']) ?? font?.size,
        );
      }
    }
    _Associations? section(String key) => switch (json[key]) {
      final Map<Object?, Object?> map => _Associations(map.cast()),
      _ => null,
    };
    return FileIconThemeData._(
      id,
      definitions,
      _Associations(json),
      section('light'),
      section('highContrast'),
    );
  }

  /// `\E001` (CSS escapes) as the character.
  static String _character(String value) {
    if (!value.startsWith(r'\')) return value;
    final code = int.tryParse(value.substring(1), radix: 16);
    return code == null ? value : String.fromCharCode(code);
  }

  static double? _percent(Object? value) {
    if (value is! String || !value.endsWith('%')) return null;
    final number = double.tryParse(value.substring(0, value.length - 1));
    return number == null ? null : number / 100;
  }

  static Color? _color(Object? value) {
    if (value is! String || !value.startsWith('#')) return null;
    var hex = value.substring(1);
    if (hex.length == 3 || hex.length == 4) {
      hex = [for (final c in hex.split('')) '$c$c'].join();
    }
    final number = int.tryParse(hex, radix: 16);
    if (number == null) return null;
    return switch (hex.length) {
      6 => Color(0xff000000 | number),
      8 => Color(((number & 0xff) << 24) | (number >> 8)),
      _ => null,
    };
  }

  List<_Associations> _sections({required bool light, bool contrast = false}) =>
      [?(contrast ? _highContrast : null), ?(light ? _light : null), _base];

  FileIconDefinition? _definition(String? id) =>
      id == null ? null : _definitions[id];

  /// The icon of the file at [path] (`languageId` its language, when
  /// known); null when the theme has none.
  FileIconDefinition? fileIcon(
    String path, {
    String? languageId,
    bool light = false,
  }) {
    final sections = _sections(light: light);
    final name = _baseName(path);
    final normalized = path.replaceAll(r'\', '/').toLowerCase();
    // By name, its folder's names before it (`.vscode/settings.json`)...
    for (final section in sections) {
      if (section.fileNames[name] case final id?) return _definition(id);
      for (final MapEntry(:key, :value) in section.fileNames.entries) {
        if (key.contains('/') && normalized.endsWith('/$key')) {
          return _definition(value);
        }
      }
    }
    // ...its dotted extensions, longest first...
    var dot = name.indexOf('.');
    while (dot >= 0 && dot < name.length - 1) {
      final extension = name.substring(dot + 1);
      for (final section in sections) {
        if (section.fileExtensions[extension] case final id?) {
          return _definition(id);
        }
      }
      dot = name.indexOf('.', dot + 1);
    }
    // ...its language, then any file's.
    if (languageId != null) {
      for (final section in sections) {
        if (section.languageIds[languageId] case final id?) {
          return _definition(id);
        }
      }
    }
    for (final section in sections) {
      if (section.file case final id?) return _definition(id);
    }
    return null;
  }

  /// The icon of the folder at [path]; [root] for a project's own.
  FileIconDefinition? folderIcon(
    String path, {
    bool expanded = false,
    bool root = false,
    bool light = false,
  }) {
    final sections = _sections(light: light);
    final name = _baseName(path);
    for (final section in sections) {
      final names = root
          ? (expanded
                ? section.rootFolderNamesExpanded
                : section.rootFolderNames)
          : (expanded ? section.folderNamesExpanded : section.folderNames);
      if (names[name] case final id?) return _definition(id);
      if (expanded && !root) {
        if (section.folderNames[name] case final id?) return _definition(id);
      }
    }
    for (final section in sections) {
      final id = root
          ? (expanded
                ? section.rootFolderExpanded ?? section.folderExpanded
                : section.rootFolder ?? section.folder)
          : (expanded ? section.folderExpanded : section.folder);
      if (id != null) return _definition(id);
    }
    return null;
  }

  static String _baseName(String path) {
    final trimmed = path.endsWith('/') || path.endsWith(r'\')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return trimmed.substring(slash + 1).toLowerCase();
  }
}

/// An icon theme an extension contributes.
typedef FileIconThemeContribution = ({
  String id,
  String label,
  String path,
  String extensionId,
});

/// The file icon themes, and the one in use (`workbench.iconTheme`). One
/// per app: [instance].
class FileIconThemeService extends ChangeNotifier {
  FileIconThemeService();

  static FileIconThemeService instance = FileIconThemeService();

  /// The bundled theme's id: the Material Icon Theme's icons.
  static const bundledId = 'material-icon-theme';

  final Map<String, FileIconThemeContribution> _themes = {};
  String? _setting;
  FileIconThemeData? _active;
  int _generation = 0;

  /// The language of a file, for themes that map languages.
  String? Function(String path)? languageIdOf;

  /// The extensions' icon themes.
  List<FileIconThemeContribution> get themes => _themes.values.toList();

  /// The theme in use; null for the bundled one.
  FileIconThemeData? get active => _active;

  /// `workbench.iconTheme`; null (or [bundledId]) for the bundled theme.
  String? get setting => _setting;

  /// The installed extensions' `contributes.iconThemes`, each with its
  /// extension's id and folder.
  Future<void> setExtensionThemes(
    Iterable<
      ({String extensionId, String location, Map<String, Object?> theme})
    >
    contributions,
  ) async {
    _themes.clear();
    for (final (:extensionId, :location, :theme) in contributions) {
      if (theme case {'id': final String id, 'path': final String path}) {
        _themes[id] = (
          id: id,
          label: theme['label'] as String? ?? id,
          path: p.normalize(p.join(location, path)),
          extensionId: extensionId,
        );
      }
    }
    await _apply();
  }

  /// Uses the theme [id] (`workbench.iconTheme`); null for the bundled one.
  Future<void> select(String? id) async {
    if (id == _setting && (_active?.id == id || id == null)) return;
    _setting = id;
    await _apply();
  }

  Future<void> _apply() async {
    final generation = ++_generation;
    final theme = _themes[_setting];
    if (theme == null) {
      if (_active == null) return;
      _active = null;
      notifyListeners();
      return;
    }
    if (_active?.id == theme.id) return;
    try {
      final data = await FileIconThemeData.load(theme.id, theme.path);
      if (generation != _generation) return;
      _active = data;
    } on Object {
      _active = null;
    }
    notifyListeners();
  }
}

/// [definition] drawn at [size].
class FileIconThemeIcon extends StatelessWidget {
  const FileIconThemeIcon(this.definition, {super.key, required this.size});

  final FileIconDefinition definition;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = definition.iconPath;
    if (path != null) {
      return path.toLowerCase().endsWith('.svg')
          ? svgFile(path, width: size, height: size)
          : Image.file(
              File(path),
              width: size,
              height: size,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
    }
    final character = definition.fontCharacter;
    if (character != null && definition.fontFamily != null) {
      return Center(
        child: Text(
          character,
          style: TextStyle(
            fontFamily: definition.fontFamily,
            fontSize: size * (definition.fontSize ?? 1),
            height: 1,
            color: definition.fontColor,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
