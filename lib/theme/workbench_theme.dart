/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt for license information.
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
// assets/textmate (textmate_manifest.dart).
//
// Deviations: settings and storage are two preference entries the app keeps
// (`ColorThemeStorage`), read once at startup; no customizations, transient
// colors, theme watching, telemetry, file or product icon themes, or
// automatic color scheme detection. Themes are named by their settings id.
// Widgets read colors through [WorkbenchThemeService.colors] and are all
// rebuilt when the theme changes ([WorkbenchThemeScope]), as a theme change
// restyles the whole workbench upstream.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ide/editor/monaco/vs/base/common/color.dart' as vs;
import '../ide/editor/monaco/vs/platform/theme/common/theme.dart';
import '../ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import '../ide/editor/textmate/textmate_manifest.dart';
import '../ide/editor/textmate/textmate_worker.dart'
    show decodeTextMateResource;
import '../ide/ide_color_theme_picker.dart';
import 'workbench_theme_initial_colors.dart';

export '../ide/editor/monaco/vs/platform/theme/common/theme.dart'
    show
        ColorScheme,
        ThemeTypeSelector,
        getThemeTypeSelector,
        isDark,
        isHighContrast;

/// `ThemeSettingDefaults`: the default theme of each color scheme.
abstract final class ThemeSettingDefaults {
  static const colorThemeDark = 'Dark 2026';
  static const colorThemeLight = 'Light 2026';
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
  'Experimental Dark' || 'VS Code Dark' => ThemeSettingDefaults.colorThemeDark,
  'Experimental Light' ||
  'VS Code Light' => ThemeSettingDefaults.colorThemeLight,
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
    implements IdeColorThemeController {
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
  ];

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
        ThemeSettingDefaults.colorThemeLight => colorThemeLightInitialColors,
        ThemeSettingDefaults.colorThemeDark => colorThemeDarkInitialColors,
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
      // A theme gone (or no longer bundled): the default of the kept
      // theme's type, as `initializeColorTheme` falls back.
      await _setColorTheme(
        _current.type == ColorScheme.light
            ? ThemeSettingDefaults.colorThemeLight
            : ThemeSettingDefaults.colorThemeDark,
        preview: false,
      );
      return;
    }
    final data = _themeData(theme);
    await data.ensureLoaded(_read);
    if (!identical(data, _current)) _apply(data, preview: false);
  });

  /// The current theme, loaded; the setting's when none is.
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
    if (theme == null) return;
    final data = _themeData(theme);
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
/// from [WorkbenchThemeService.instance] without depending on it.
class WorkbenchThemeScope extends StatefulWidget {
  const WorkbenchThemeScope({super.key, this.service, required this.builder});

  /// [WorkbenchThemeService.instance] when null.
  final WorkbenchThemeService? service;
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
  }

  @override
  void didUpdateWidget(WorkbenchThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final service = widget.service ?? WorkbenchThemeService.instance;
    if (!identical(service, _service)) {
      _service.removeListener(_changed);
      _service = service..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
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
