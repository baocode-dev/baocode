/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See packages/bao_editor/lib/monaco/LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// The workbench's color theme (`workbench.colorTheme`): which bundled VS Code
// theme is current, its colors as widgets read them, and keeping the choice.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/services/themes/browser/workbenchThemeService.ts (the
// constructor's restore from storage, `setColorTheme`, `applyTheme`,
// `restoreColorTheme`) and common/workbenchThemeService.ts
// (`ThemeSettingDefaults`, `COLOR_THEME_*_INITIAL_COLORS`,
// `migrateThemeSettingsId`). The themes are the ones bundled under
// packages/bao_editor/assets/textmate (textmate_manifest.dart).
//
// Deviations: settings and storage are two preference entries the app keeps
// (`ColorThemeStorage`), read once at startup; no customizations, transient
// colors, theme watching, telemetry, file or product icon themes, or
// automatic color scheme detection. Themes are named by their settings id.
// Widgets read colors through [WorkbenchThemeService.colors] and are all
// rebuilt when the theme changes ([WorkbenchThemeScope]), as a theme change
// restyles the whole workbench upstream.

import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:bao_editor/monaco/vs/base/common/color.dart' as vs;
import 'package:bao_editor/monaco/vs/platform/theme/common/color_utils.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/workbench_theme_service.dart'
    show IThemeExtensionPoint;
import 'package:path/path.dart' as p;
import 'package:bao_editor/textmate/textmate_manifest.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart'
    show TextMateThemeSource;
import 'package:bao_editor/textmate/textmate_worker.dart'
    show decodeTextMateResource;

import '../ide/ide_color_theme_picker.dart';
import 'workbench_theme_initial_colors.dart';

export 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart'
    show
        ColorScheme,
        ThemeTypeSelector,
        getThemeTypeSelector,
        isDark,
        isHighContrast;

/// `ThemeSettingDefaults`: the default theme of each color scheme. Ours are
/// Monokai and Quiet Light, not upstream's Dark 2026 and Light 2026.
abstract final class ThemeSettingDefaults {
  static const colorThemeDark = 'Monokai';
  static const colorThemeLight = 'Quiet Light';
  static const colorThemeHcDark = 'Default High Contrast';
  static const colorThemeHcLight = 'Default High Contrast Light';
}

/// `migrateThemeSettingsId`: the current id of a theme once named
/// [settingsId].
String migrateThemeSettingsId(String settingsId) => switch (settingsId) {
  'Default Dark Modern' => 'Dark Modern',
  'Default Light Modern' => 'Light Modern',
  'Default Dark+' => 'Dark+',
  'Default Light+' => 'Light+',
  'Experimental Dark' || 'VS Code Dark' => 'Dark 2026',
  'Experimental Light' || 'VS Code Light' => 'Light 2026',
  _ => settingsId,
};

/// Where the app keeps the theme between runs: the `workbench.colorTheme`
/// setting and the storage entry that restores it without reading the theme
/// file (`ColorThemeData.toStorage`).
abstract interface class ColorThemeStorage {
  String? get colorThemeSetting;
  String? get colorThemeData;
  void storeColorTheme({required String setting, String? data});
}

/// A color theme's colors as widgets read them: what the theme sets, else
/// the color registry's default for its type (`IColorTheme.getColor`).
class WorkbenchColors {
  WorkbenchColors(this.theme);

  final ColorThemeData theme;
  final Map<String, ui.Color?> _colors = {};

  ColorScheme get type => theme.type;
  bool get dark => isDark(type);
  bool get highContrast => isHighContrast(type);

  /// The color [id] names; null when neither the theme nor the registry
  /// gives it one.
  ui.Color? get(String id) => _colors.putIfAbsent(id, () {
    final color = theme.getColor(id);
    return color == null ? null : toFlutterColor(color);
  });

  /// [get], else what the element would inherit upstream: a text color
  /// without one (`sideBar.foreground`, `list.hoverForeground`…) leaves CSS
  /// `color` inherited, ending at the workbench's `foreground`; any other
  /// color (a background, a border) is none, so transparent.
  ui.Color operator [](String id) =>
      get(id) ??
      (id != 'foreground' && id.endsWith('oreground')
          ? get('foreground')
          : null) ??
      const ui.Color(0x00000000);

  /// A VS Code color as Flutter paints it.
  static ui.Color toFlutterColor(vs.Color color) {
    final rgba = color.rgba;
    return ui.Color.fromARGB((rgba.a * 255).round(), rgba.r, rgba.g, rgba.b);
  }
}

/// The current color theme's colors, as widgets read them
/// ([WorkbenchThemeService.instance]'s).
WorkbenchColors get themeColors => WorkbenchThemeService.instance.colors;

/// The workbench's color theme service (upstream `IWorkbenchThemeService`,
/// color themes only). One per app: [instance]. Preferences: Color Theme
/// picks from it ([IdeColorThemeController]).
class WorkbenchThemeService extends ChangeNotifier
    implements IdeColorThemeController, TextMateThemeSource {
  WorkbenchThemeService({this.bundle, ColorThemeData? initial})
    : _current =
          initial ??
          ColorThemeData.createUnloadedThemeForThemeType(
            ColorScheme.dark,
            colorThemeDarkInitialColors,
          );

  /// The app's service; tests replace it.
  static WorkbenchThemeService instance = WorkbenchThemeService();

  /// Where the themes are read; [rootBundle] when null.
  final AssetBundle? bundle;
  AssetBundle get _assets => bundle ?? rootBundle;

  ColorThemeData _current;
  WorkbenchColors? _colors;

  /// Where the choice is kept; none under test.
  ColorThemeStorage? storage;

  /// The `workbench.colorTheme` setting: what [restoreColorTheme] loads.
  String _setting = ThemeSettingDefaults.colorThemeDark;

  /// The current theme: from storage or a type's initial colors until the
  /// theme file is loaded ([ColorThemeData.isLoaded]).
  @override
  ColorThemeData get colorTheme => _current;

  /// The settings id of the theme the workbench shows.
  @override
  String get colorThemeId =>
      _current.settingsId.startsWith('__') ? _setting : _current.settingsId;

  WorkbenchColors get colors => _colors ??= WorkbenchColors(_current);

  // --- The bundled themes -------------------------------------------------

  TextMateManifest? _manifest;
  final Map<String, ColorThemeData> _themes = {};

  Future<String> _read(String path) async {
    // An extension's theme: its file on disk.
    if (p.isAbsolute(path)) {
      return decodeTextMateResource(await File(path).readAsBytes());
    }
    final data = await _assets.load('$textMateAssetRoot/$path');
    return decodeTextMateResource(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  Future<TextMateManifest> _loadManifest() async =>
      _manifest ??= await TextMateManifest.load(_read);

  /// The installed themes (`getColorThemes`), by settings id, once
  /// [initialize] has read them.
  @override
  List<IdeColorThemeEntry> get colorThemes => [
    for (final theme
        in _manifest?.themes ?? const <TextMateThemeContribution>[])
      IdeColorThemeEntry(
        id: theme.id,
        label: theme.label,
        type: _themeData(theme).type,
      ),
    for (final theme in _extensionThemes.values)
      IdeColorThemeEntry(
        id: theme.settingsId,
        label: theme.label,
        type: theme.type,
        description: theme.description,
      ),
  ];

  // --- Extensions' colors (`contributes.colors`) ---------------------------

  /// The color ids the running extensions registered.
  final Set<String> _extensionColorIds = {};
  String? _extensionColorsKey;

  static final _colorIdPattern = RegExp(r'^\w+[.\w+]*$');

  /// The running extensions' `contributes.colors` (colorExtensionPoint.ts
  /// `ColorExtensionPoint`): each `{id, description, defaults}` registered
  /// in the color registry with its defaults, a '#' string a color and
  /// anything else the color it names; those no longer contributed are
  /// deregistered. [colors] are each extension's entries, in order.
  ///
  /// Deviation: an invalid entry skips the rest of its extension's
  /// (upstream it ends the whole delta's handling).
  void setExtensionColors(Iterable<List<Map<String, Object?>>> colors) {
    final key = jsonEncode(colors.toList());
    if (key == _extensionColorsKey) return;
    _extensionColorsKey = key;
    final registry = getColorRegistry();
    for (final id in _extensionColorIds) {
      registry.deregisterColor(id);
    }
    _extensionColorIds.clear();
    // `parseColorValue`: an empty value is an error, and red.
    ColorValue? value(String s) => s.isEmpty
        ? const ColorLiteral('#ff0000')
        : s.startsWith('#')
        ? (vs.ColorFormatCSS.parseHex(s) == null ? null : ColorLiteral(s))
        : ColorReference(s);
    for (final entries in colors) {
      for (final entry in entries) {
        final id = entry['id'];
        final defaults = entry['defaults'];
        if (id is! String || !_colorIdPattern.hasMatch(id)) break;
        if (entry['description'] is! String) break;
        if (defaults is! Map ||
            defaults['light'] is! String ||
            defaults['dark'] is! String) {
          break;
        }
        final highContrast = defaults['highContrast'];
        final highContrastLight = defaults['highContrastLight'];
        if (highContrast is! String? || highContrastLight is! String?) break;
        final light = defaults['light'] as String;
        final dark = defaults['dark'] as String;
        registry.registerColor(
          id,
          ColorDefaults(
            light: value(light),
            dark: value(dark),
            hcDark: value(highContrast ?? dark),
            hcLight: value(highContrastLight ?? light),
          ),
        );
        _extensionColorIds.add(id);
      }
    }
    // Colors are read again, through the registry's new defaults.
    _current.clearCaches();
    _colors = null;
    notifyListeners();
  }

  // --- Extensions' themes (`contributes.themes`) ---------------------------

  /// The installed extensions' themes, by settings id.
  final Map<String, ColorThemeData> _extensionThemes = {};

  /// Whether the extensions' themes were told once: until then, a setting
  /// that is not a bundled theme may be one of theirs, and waits (where
  /// [waitsForExtensionThemes]).
  bool _extensionThemesKnown = false;

  /// Whether extensions will tell their themes ([setExtensionThemes]):
  /// the app with extensions.
  bool waitsForExtensionThemes = false;

  /// The installed extensions' `contributes.themes`: [themes] are each
  /// extension's id, its folder and its contribution (`id`, `label`,
  /// `uiTheme`, `path`). The setting's theme applies once it is among them.
  Future<void> setExtensionThemes(
    Iterable<
      ({String extensionId, String location, Map<String, Object?> theme})
    >
    themes,
  ) => _queue(() async {
    final next = <String, ColorThemeData>{};
    for (final (:extensionId, :location, :theme) in themes) {
      final path = theme['path'];
      if (path is! String || path.isEmpty) continue;
      final label = theme['label'] is String ? theme['label']! as String : null;
      final id = theme['id'] is String ? theme['id']! as String : label ?? path;
      final point = IThemeExtensionPoint(
        id: id,
        label: label,
        description: theme['description'] as String?,
        path: path,
        uiTheme: theme['uiTheme'] as String?,
      );
      final file = p.normalize(p.join(location, path)).replaceAll(r'\', '/');
      // Kept when unchanged: a loaded theme stays loaded.
      final kept = _extensionThemes[id];
      next[id] = kept != null && kept.location == file
          ? kept
          : ColorThemeData.fromExtensionTheme(
              point,
              file,
              extensionId: extensionId,
            );
    }
    _extensionThemes
      ..clear()
      ..addAll(next);
    final first = !_extensionThemesKnown;
    _extensionThemesKnown = true;
    // The setting's theme, waiting for them (or gone with an extension).
    if (_current.settingsId != _setting || !_current.isLoaded || first) {
      if (_extensionThemes[_setting] case final theme?) {
        await theme.ensureLoaded(_read);
        _apply(theme, preview: false);
      } else if ((await _loadManifest()).themeById(_setting) == null) {
        await _setColorTheme(_defaultSetting, preview: false);
      }
    }
    notifyListeners();
  });

  String get _defaultSetting => _current.type == ColorScheme.light
      ? ThemeSettingDefaults.colorThemeLight
      : ThemeSettingDefaults.colorThemeDark;

  ColorThemeData _themeData(TextMateThemeContribution theme) =>
      _themes[theme.id] ??= ColorThemeData.fromExtensionTheme(
        theme,
        theme.assetPath,
        extensionId: theme.extensionId,
      );

  // --- Startup ------------------------------------------------------------

  /// The constructor's restore: the kept theme, painted from storage when it
  /// is still the setting's, until [initialize] loads it.
  void restore({String? setting, String? data}) {
    if (setting != null && setting.isNotEmpty) {
      _setting = migrateThemeSettingsId(setting);
    }
    var theme = ColorThemeData.fromStorageData(data);
    if (theme != null && theme.settingsId != _setting) theme = null;
    theme ??= ColorThemeData.createUnloadedThemeForThemeType(
      ColorScheme.dark,
      switch (_setting) {
        'Light 2026' => colorThemeLightInitialColors,
        'Dark 2026' => colorThemeDarkInitialColors,
        _ => null,
      },
    );
    _apply(theme, silent: true);
  }

  /// Reads the bundled themes and applies the setting's theme, loaded
  /// (`restoreColorTheme`); the default theme when it is gone.
  Future<void> initialize() => _queue(() async {
    final manifest = await _loadManifest();
    final theme = manifest.themeById(_setting);
    if (theme == null) {
      if (_extensionThemes[_setting] case final extension?) {
        await extension.ensureLoaded(_read);
        if (!identical(extension, _current)) _apply(extension, preview: false);
        return;
      }
      // An extension's, maybe: the restored colors show until the
      // extensions say ([setExtensionThemes]).
      if (waitsForExtensionThemes && !_extensionThemesKnown) return;
      // A theme gone (or no longer bundled): the default of the kept
      // theme's type, as `initializeColorTheme` falls back.
      await _setColorTheme(_defaultSetting, preview: false);
      return;
    }
    final data = _themeData(theme);
    await data.ensureLoaded(_read);
    if (!identical(data, _current)) _apply(data, preview: false);
  });

  /// The current theme, loaded; the setting's when none is.
  @override
  Future<ColorThemeData> loadedColorTheme() async {
    if (!_current.isLoaded) await initialize();
    return _current;
  }

  // --- Changing it ----------------------------------------------------------

  Future<void> _pending = Future.value();

  /// `colorThemeSequencer`: one change at a time, in order.
  Future<T> _queue<T>(Future<T> Function() change) {
    final result = _pending.then((_) => change());
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// `setColorTheme(settingsId, preview ? 'preview' : 'auto')`: shows the
  /// theme; unless [preview], keeps it as the setting and in storage.
  @override
  Future<void> setColorTheme(String settingsId, {bool preview = false}) =>
      _queue(() => _setColorTheme(settingsId, preview: preview));

  Future<void> _setColorTheme(
    String settingsId, {
    required bool preview,
  }) async {
    if (_current.isLoaded && settingsId == _current.settingsId) {
      if (!preview) _keep(_current);
      return;
    }
    final manifest = await _loadManifest();
    final theme = manifest.themeById(settingsId);
    final data = theme != null
        ? _themeData(theme)
        : _extensionThemes[settingsId];
    if (data == null) return;
    await data.ensureLoaded(_read);
    _apply(data, preview: preview);
  }

  void _apply(
    ColorThemeData theme, {
    bool silent = false,
    bool preview = true,
  }) {
    _current.clearCaches();
    _current = theme;
    _colors = null;
    if (silent) return;
    notifyListeners();
    // Remember theme data for a quick restore.
    if (!preview && theme.isLoaded) _keep(theme);
  }

  void _keep(ColorThemeData theme) {
    _setting = theme.settingsId;
    storage?.storeColorTheme(
      setting: theme.settingsId,
      data: theme.toStorage(),
    );
  }
}

/// Rebuilds everything under it when the workbench theme changes, as a
/// theme change restyles the whole workbench upstream: widgets read colors
/// from [WorkbenchThemeService.instance] without depending on it. So, too,
/// when [restyle] notifies.
class WorkbenchThemeScope extends StatefulWidget {
  const WorkbenchThemeScope({
    super.key,
    this.service,
    this.restyle,
    required this.builder,
  });

  /// [WorkbenchThemeService.instance] when null.
  final WorkbenchThemeService? service;

  /// What else restyles everything (the code's font), read as widgets
  /// build without depending on it.
  final Listenable? restyle;

  final WidgetBuilder builder;

  @override
  State<WorkbenchThemeScope> createState() => _WorkbenchThemeScopeState();
}

class _WorkbenchThemeScopeState extends State<WorkbenchThemeScope> {
  late WorkbenchThemeService _service =
      widget.service ?? WorkbenchThemeService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    widget.restyle?.addListener(_changed);
  }

  @override
  void didUpdateWidget(WorkbenchThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final service = widget.service ?? WorkbenchThemeService.instance;
    if (!identical(service, _service)) {
      _service.removeListener(_changed);
      _service = service..addListener(_changed);
    }
    if (!identical(widget.restyle, oldWidget.restyle)) {
      oldWidget.restyle?.removeListener(_changed);
      widget.restyle?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    widget.restyle?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    setState(() {});
    // Painters may keep the colors they were made with.
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    for (final view in WidgetsBinding.instance.renderViews) {
      repaint(view);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
