import 'dart:async';

import 'package:baocode/ide/terminal/terminal_render_metrics.dart';
import 'package:baocode/ide/terminal/terminal_render_theme.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/linux_code_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux draws code in the families as loaded, without rewriting '
      'settings', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('baocode/window');
    final requests = <List<String>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'codeFontFiles');
      final families = (call.arguments as List).cast<String>();
      requests.add(families);
      return {
        for (final family in families)
          family: switch (family) {
            'Installed Font' || 'Courier New' || 'DejaVu Sans Mono' => {
              'files': ['assets/codicons/codicon.ttf'],
              'installed': true,
            },
            // In a collection, not its first face: none to load.
            'Collection Font' => {'files': <String>[], 'installed': true},
            _ => {'files': <String>[], 'installed': false},
          },
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    /// Sets the families, and waits for them as loaded.
    Future<void> set(List<String> families) async {
      final changed = Completer<void>();
      void onChange() => changed.complete();
      LinuxCodeFonts.resolved.addListener(onChange);
      CodeFont.families.value = families;
      try {
        await changed.future.timeout(const Duration(seconds: 5));
      } finally {
        LinuxCodeFonts.resolved.removeListener(onChange);
      }
    }

    // Before the first frame: only those set and the fallbacks.
    CodeFont.families.value = ['Unavailable Font'];
    await LinuxCodeFonts.start();
    expect(requests.single, ['Unavailable Font', ...LinuxCodeFonts.fallbacks]);
    final fallback = AppFonts.mono;
    expect(fallback, startsWith('BaoCodeCodeFont'));
    expect(AppFonts.monoFallbacks, isEmpty);

    // The menu opened: what it offers, not asked for yet.
    await LinuxCodeFonts.preloadPresets();
    expect(requests, hasLength(2));
    expect(requests.last, contains('Courier New'));
    expect(requests.last, isNot(contains('DejaVu Sans Mono')));

    // Picked from it: loaded already.
    await set(['Courier New']);
    expect(requests, hasLength(2));
    expect(LinuxCodeFonts.resolved.value, [isNot(fallback), fallback]);

    await set(['Installed Font', 'Unavailable Font']);
    expect(requests.last, ['Installed Font']);
    expect(LinuxCodeFonts.resolved.value, [AppFonts.mono, fallback]);
    expect(
      parseFontFamilies(vscodeTerminalFontFamily()).take(2),
      LinuxCodeFonts.resolved.value,
    );

    // Installed where it cannot be loaded: by its own name, as before.
    await set(['Collection Font']);
    expect(LinuxCodeFonts.resolved.value, ['Collection Font', fallback]);
    expect(CodeFont.families.value, ['Collection Font']);
  });
}
