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

  test(
    'Linux resolves code and terminal fonts without rewriting settings',
    () async {
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
              'Unavailable Font' => <String>[],
              'Installed Font' ||
              'Courier New' ||
              'DejaVu Sans Mono' => ['assets/codicons/codicon.ttf'],
              _ => <String>[],
            },
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      CodeFont.families.value = ['Unavailable Font'];
      await LinuxCodeFonts.start();
      final fallback = AppFonts.mono;
      expect(fallback, startsWith('BaoCodeCodeFont'));
      expect(AppFonts.monoFallbacks, isEmpty);
      expect(requests.single.first, 'Unavailable Font');
      expect(requests.single, containsAll(CodeFont.familyPresets));

      final changed = LinuxCodeFonts.resolved;
      final preset = Completer<void>();
      void onPreset() => preset.complete();
      changed.addListener(onPreset);
      CodeFont.families.value = ['Courier New'];
      try {
        await preset.future.timeout(const Duration(seconds: 5));
      } finally {
        changed.removeListener(onPreset);
      }
      expect(requests, hasLength(1));
      expect(changed.value, [isNot(fallback), fallback]);
      final next = Completer<void>();
      void onChange() => next.complete();
      changed.addListener(onChange);
      addTearDown(() => changed.removeListener(onChange));
      CodeFont.families.value = ['Installed Font', 'Unavailable Font'];
      await next.future.timeout(const Duration(seconds: 5));
      expect(requests.last, ['Installed Font']);
      expect(changed.value, [AppFonts.mono, fallback]);
      expect(
        parseFontFamilies(vscodeTerminalFontFamily()).take(2),
        changed.value,
      );
      expect(CodeFont.families.value, ['Installed Font', 'Unavailable Font']);
    },
  );
}
