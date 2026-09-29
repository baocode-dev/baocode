import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// File and folder icons from the Material Icon Theme (the icons of
/// material-icons-browser-extension), bundled by
/// `tool/generate_material_icons.mjs` under `assets/material_icons/`.
///
/// Icons resolve as the theme does in VS Code: a file by its name, then by
/// its longest dotted extension (`a.test.ts` tries `test.ts`, then `ts`);
/// a folder by its name, open or closed.
class MaterialFileIcons {
  MaterialFileIcons._();

  static final instance = MaterialFileIcons._();

  static const _root = 'assets/material_icons';

  /// Whether the mappings are loaded; icons show once they are.
  final ValueNotifier<bool> loaded = ValueNotifier(false);

  Future<void>? _loading;
  late String _file;
  late String _folder;
  late String _folderExpanded;
  late String _rootFolder;
  late String _rootFolderExpanded;
  Map<String, String> _fileNames = const {};
  Map<String, String> _fileExtensions = const {};
  Map<String, String> _folderNames = const {};
  Map<String, String> _folderNamesExpanded = const {};

  /// File names given with a folder (`.config/stylelintrc`), matched
  /// against the end of a path.
  List<String> _pathNames = const [];

  /// Loads the mappings, once.
  Future<void> load([AssetBundle? bundle]) =>
      _loading ??= _load(bundle ?? rootBundle);

  Future<void> _load(AssetBundle bundle) async {
    final manifest = jsonDecode(
      await bundle.loadString('$_root/manifest.json'),
    ) as Map<String, Object?>;
    Map<String, String> map(String key) =>
        (manifest[key] as Map<String, Object?>).cast<String, String>();
    _file = manifest['file']! as String;
    _folder = manifest['folder']! as String;
    _folderExpanded = manifest['folderExpanded']! as String;
    _rootFolder = manifest['rootFolder']! as String;
    _rootFolderExpanded = manifest['rootFolderExpanded']! as String;
    _fileNames = map('fileNames');
    _fileExtensions = map('fileExtensions');
    _folderNames = map('folderNames');
    _folderNamesExpanded = map('folderNamesExpanded');
    _pathNames = [
      for (final name in _fileNames.keys)
        if (name.contains('/')) name,
    ];
    loaded.value = true;
  }

  static String _baseName(String path) {
    final trimmed = path.endsWith('/') || path.endsWith(r'\')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return trimmed.substring(slash + 1).toLowerCase();
  }

  /// The icon id for the file at [path] (or a bare file name).
  String fileIcon(String path) {
    if (!loaded.value) return 'file';
    final name = _baseName(path);
    if (_fileNames[name] case final id?) return id;
    if (_pathNames.isNotEmpty) {
      final normalized = path.replaceAll(r'\', '/').toLowerCase();
      for (final key in _pathNames) {
        if (normalized == key || normalized.endsWith('/$key')) {
          return _fileNames[key]!;
        }
      }
    }
    // The longest dotted extension first; a leading dot is not one.
    var dot = name.indexOf('.', 1);
    while (dot >= 0 && dot < name.length - 1) {
      if (_fileExtensions[name.substring(dot + 1)] case final id?) return id;
      dot = name.indexOf('.', dot + 1);
    }
    return _file;
  }

  /// The icon id for the folder at [path]; [root] for a project's own.
  String folderIcon(String path, {bool expanded = false, bool root = false}) {
    if (!loaded.value) return 'folder';
    if (root) return expanded ? _rootFolderExpanded : _rootFolder;
    final name = _baseName(path);
    return (expanded ? _folderNamesExpanded[name] : _folderNames[name]) ??
        (expanded ? _folderExpanded : _folder);
  }

  /// The bundled asset for icon [id].
  static String asset(String id) => '$_root/icons/$id.svg';
}

/// The Material Icon Theme icon for the file at [path].
class FileIcon extends StatelessWidget {
  const FileIcon(this.path, {super.key, this.size = 16});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) => _ThemeIcon(
    size: size,
    id: () => MaterialFileIcons.instance.fileIcon(path),
  );
}

/// The Material Icon Theme icon for the folder at [path].
class FolderIcon extends StatelessWidget {
  const FolderIcon(
    this.path, {
    super.key,
    this.size = 16,
    this.expanded = false,
    this.root = false,
  });

  final String path;
  final double size;
  final bool expanded;
  final bool root;

  @override
  Widget build(BuildContext context) => _ThemeIcon(
    size: size,
    id: () => MaterialFileIcons.instance.folderIcon(
      path,
      expanded: expanded,
      root: root,
    ),
  );
}

class _ThemeIcon extends StatelessWidget {
  const _ThemeIcon({required this.size, required this.id});

  final double size;
  final String Function() id;

  @override
  Widget build(BuildContext context) {
    final icons = MaterialFileIcons.instance;
    // Loaded on first use; the space is kept meanwhile, so rows do not move.
    icons.load(DefaultAssetBundle.of(context)).ignore();
    return ValueListenableBuilder<bool>(
      valueListenable: icons.loaded,
      builder: (context, loaded, _) => SizedBox.square(
        dimension: size,
        child: loaded
            // No `bundle:`: the loader is sent to the isolate that decodes
            // the SVG, and a bundle (its cache holds futures) cannot be,
            // in release builds. The loader finds the context's bundle.
            ? SvgPicture.asset(
                MaterialFileIcons.asset(id()),
                width: size,
                height: size,
              )
            : null,
      ),
    );
  }
}
