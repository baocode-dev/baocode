import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/app_platform.dart';
import 'code_font.dart';

/// Code drawn on Linux in the families set ([CodeFont.families]), each
/// loaded from the files Fontconfig matches for it, under a name of the
/// app's own.
///
/// By their own names, Skia may draw them in another face under a CJK
/// locale (#1304): its Fontconfig lookup gathers the faces of every family
/// the configuration puts with the name (a CJK one, first, for `zh`), then
/// picks among them by style and the locale's language, not by family, and
/// the CJK face comes out, proportional at times. Skia keeps the family
/// since a4d18ba482 (flutter/flutter#195102); with a Flutter whose Skia has
/// it, this can go. `FC_LANG=en` works around it too, but for the whole app
/// and what it starts, and the language is not the app's to change.
abstract final class LinuxCodeFonts {
  /// What code falls back on after the families set: monospaced ones most
  /// Linux systems have, then whichever Fontconfig calls monospaced.
  static const fallbacks = [
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Noto Sans Mono',
    'monospace',
  ];

  /// The window's channel (WindowControls'), whose Linux host answers
  /// `codeFontFiles` (see my_application.cc).
  static const _channel = MethodChannel('baocode/window');

  /// Each family asked for: the name to draw it by (the one it was loaded
  /// under; its own, installed where it cannot be loaded), or null, not
  /// installed.
  static final _faces = <String, Future<String?>>{};

  static int _aliases = 0;

  static final _resolved = ValueNotifier<List<String>?>(null);

  /// The families code is drawn in, by the names to draw them by: those set,
  /// then [fallbacks], the ones not installed left out. Null off Linux, and
  /// while none is known.
  static ValueListenable<List<String>?> get resolved => _resolved;

  /// Loads the families set, before the first frame, and those set later.
  static Future<void> start() async {
    if (!AppPlatform.isLinux) return;
    CodeFont.families.addListener(_refresh);
    await _refresh();
  }

  /// Loads the families the Appearance page's menu offers, as it opens: a
  /// font loaded has Flutter lay all its text out again, which picked from
  /// the menu left the old glyphs on screen a long while.
  static Future<void> preloadPresets() async {
    if (!AppPlatform.isLinux) return;
    await _load({...CodeFont.defaultFamilies, ...CodeFont.familyPresets});
  }

  static Future<void> _refresh() async {
    final configured = CodeFont.families.value;
    final families = {...configured, ...fallbacks};
    await _load(families);
    final faces = [for (final name in families) ?await _faces[name]];
    // Set again meanwhile: that one's to tell.
    if (!identical(configured, CodeFont.families.value)) return;
    final next = faces.isEmpty ? null : faces;
    if (!listEquals(_resolved.value, next)) _resolved.value = next;
  }

  /// Asks for the files of those of [families] not asked for yet, and loads
  /// them. Asked again later where the host could not answer.
  static Future<void> _load(Set<String> families) async {
    final asking = [
      for (final name in families)
        if (!_faces.containsKey(name)) name,
    ];
    if (asking.isNotEmpty) {
      final Map<String, Object?>? answer;
      try {
        answer = await _channel.invokeMapMethod<String, Object?>(
          'codeFontFiles',
          asking,
        );
      } on PlatformException catch (error) {
        debugPrint('Code fonts could not be resolved: $error');
        return;
      } on MissingPluginException {
        // A host without the Linux runner's channel.
        return;
      }
      for (final name in asking) {
        final entry = answer?[name];
        final (files, installed) = entry is Map
            ? (
                [...?(entry['files'] as List?)?.cast<String>()],
                entry['installed'] == true,
              )
            : (const <String>[], false);
        _faces.putIfAbsent(name, () => _register(name, files, installed));
      }
    }
    await Future.wait([for (final name in families) ?_faces[name]]);
  }

  /// The name to draw [family] by: its [files] loaded under one of the
  /// app's own; where none could be and it is [installed] (in a font
  /// collection but its first face), its own name, Skia's to find as before.
  static Future<String?> _register(
    String family,
    List<String> files,
    bool installed,
  ) async {
    final alias = 'BaoCodeCodeFont${_aliases++}';
    var loaded = false;
    for (final path in files.toSet()) {
      try {
        await ui.loadFontFromList(
          await File(path).readAsBytes(),
          fontFamily: alias,
        );
        loaded = true;
      } on FileSystemException {
        // Removed since, or not readable.
      }
    }
    if (loaded) return alias;
    return installed ? family : null;
  }
}
