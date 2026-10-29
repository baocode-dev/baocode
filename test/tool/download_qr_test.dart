import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/make_download_qr.dart';

void main() {
  group('download_qr', () {
    test('the codes in site/ are what the tool makes', () {
      final made = downloadQrSvgs();
      expect(made.keys, containsAll(['site/qr/android.svg', 'site/qr/ios.svg']));
      for (final MapEntry(key: path, value: svg) in made.entries) {
        expect(
          File(path).readAsStringSync(),
          svg,
          reason: '$path: run dart run tool/make_download_qr.dart',
        );
      }
    });

    test('each card on both pages shows the code of its own button', () {
      // The two go together: a code that leads somewhere but the button
      // leading elsewhere would be a download page that lies.
      for (final page in ['site/download.html', 'site/zh/download.html']) {
        final html = File(page).readAsStringSync();
        expect(html, contains('data-os="android"'), reason: page);
        expect(html, contains('data-os="ios"'), reason: page);
        for (final MapEntry(key: os, value: target) in downloadQrTargets.entries) {
          if (!html.contains('data-os="$os"')) continue;
          final card = _cardOf(html, os);
          expect(
            _attribute(card, 'img', 'src'),
            endsWith('qr/$os.svg'),
            reason: '$page, the $os card',
          );
          expect(
            _attribute(card, 'a', 'href'),
            target,
            reason: '$page, the $os card links elsewhere',
          );
        }
      }
    });

    test('a code is a whole number of modules, quiet margin and all', () {
      // The viewBox is what the page scales; a stray fraction would blur it.
      final viewBox = RegExp(r'viewBox="0 0 (\d+) (\d+)"');
      for (final svg in downloadQrSvgs().values) {
        final match = viewBox.firstMatch(svg)!;
        final side = int.parse(match[1]!);
        expect(int.parse(match[2]!), side);
        expect((side - 8) % 4, 1, reason: 'a QR code is 4n+17 modules');
      }
    });
  });
}

/// The `<section>` of [html] that is the phone app's [os] card.
String _cardOf(String html, String os) {
  final start = html.indexOf('data-os="$os"');
  expect(start, greaterThan(-1), reason: 'no $os card');
  final section = html.lastIndexOf('<section', start);
  return html.substring(section, html.indexOf('</section>', start));
}

/// The first [tag] in [card], by its [attribute].
String _attribute(String card, String tag, String attribute) {
  final match = RegExp('<$tag [^>]*$attribute="([^"]*)"').firstMatch(card);
  expect(match, isNotNull, reason: 'no <$tag $attribute> in the card');
  return match![1]!;
}
