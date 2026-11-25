import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/app_platform.dart';
import 'code_font.dart';

/// Linux's Skia family lookup can pick a different face under a CJK locale.
/// Register the exact Fontconfig matches under private names, so the fix
/// applies only to code and never changes the window's font matching locale.
abstract final class LinuxCodeFonts {
  static const fallbacks = [
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Noto Sans Mono',
    'monospace',
  ];
  static const _channel = MethodChannel('baocode/window');
  static final _loaded = <String, Future<String?>>{};
  static final _resolved = ValueNotifier<List<String>?>(null);
  static ValueListenable<List<String>?> get resolved => _resolved;

  static Future<void> start() async {
    if (!AppPlatform.isLinux) return;
    CodeFont.families.addListener(_refresh);
    await _refresh(preloadPresets: true);
  }

  static Future<void> _refresh({bool preloadPresets = false}) async {
    final configured = CodeFont.families.value;
    final families = {...configured, ...fallbacks};
    // Register the picker fonts before the first frame. Loading font bytes
    // clears Flutter's font caches, including those for unrelated UI text.
    final requested = {
      ...families,
      if (preloadPresets) ...CodeFont.defaultFamilies,
      if (preloadPresets) ...CodeFont.familyPresets,
    };
    try {
      final uncached = requested.where((name) => !_loaded.containsKey(name));
      final paths = uncached.isEmpty
          ? null
          : await _channel.invokeMapMethod<String, Object?>(
              'codeFontFiles',
              uncached.toList(),
            );
      for (final MapEntry(:key, :value)
          in paths?.entries ?? const <MapEntry<String, Object?>>[]) {
        _loaded.putIfAbsent(
          key,
          () => _register((value as List).cast<String>()),
        );
      }
      if (preloadPresets) {
        await Future.wait(_loaded.values);
      }
      final aliases = [
        for (final name in families)
          if (await _loaded[name] case final String alias) alias,
      ];
      if (identical(configured, CodeFont.families.value)) {
        final next = aliases.isEmpty ? null : aliases;
        if (!listEquals(_resolved.value, next)) _resolved.value = next;
      }
    } on PlatformException catch (error) {
      debugPrint('Code fonts could not be resolved: $error');
    } on MissingPluginException {
      // Non-desktop Flutter hosts have no Linux runner.
    }
  }

  static int _nextAlias = 0;

  static Future<String?> _register(List<String> files) async {
    final alias = 'BaoCodeCodeFont${_nextAlias++}';
    var loaded = false;
    for (final path in files.toSet()) {
      try {
        await ui.loadFontFromList(
          await File(path).readAsBytes(),
          fontFamily: alias,
        );
        loaded = true;
      } on FileSystemException {
        // The font was removed or is no longer readable.
      }
    }
    return loaded ? alias : null;
  }
}
