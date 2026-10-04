import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/update/version.dart';

AppVersion v(String text) => AppVersion.parse(text);

void main() {
  group('AppVersion', () {
    test('reads pubspec.yaml\'s form', () {
      final version = v('1.2.3+45');
      expect(
        (version.major, version.minor, version.patch, version.build),
        (1, 2, 3, 45),
      );
      expect(version.marketing, '1.2.3');
      expect('$version', '1.2.3+45');
      expect('${v('1.2.3')}', '1.2.3');
    });

    test('reads pre-releases, a leading v and missing parts', () {
      expect(v('1.2.0-beta.1').preRelease, ['beta', '1']);
      expect(v('1.2.0-beta.1+7').build, 7);
      expect(v('v2.0.1'), v('2.0.1'));
      expect(v('1.2'), v('1.2.0'));
      expect(v('3'), v('3.0.0'));
    });

    test('is not anything else', () {
      for (final text in [
        '',
        'x',
        '1.2.3.4',
        '1..2',
        '1.2.3+',
        '1.2.3-',
        '1.2.3-a..b',
        '1.2.3+abc',
        'latest',
      ]) {
        expect(AppVersion.tryParse(text), isNull, reason: text);
      }
      expect(() => AppVersion.parse('nope'), throwsFormatException);
    });

    test('orders by semver, then by build number', () {
      final ordered = [
        '0.9.9',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
        '1.0.0+1',
        '1.0.0+2',
        '1.0.0+10',
        '1.0.1',
        '1.1.0',
        '1.10.0',
        '2.0.0',
      ].map(v).toList();
      for (var i = 0; i < ordered.length; i++) {
        for (var j = 0; j < ordered.length; j++) {
          expect(
            ordered[i].compareTo(ordered[j]).sign,
            i.compareTo(j).sign,
            reason: '${ordered[i]} vs ${ordered[j]}',
          );
        }
      }
      expect(v('1.2.0+12') > v('1.2.0+11'), isTrue);
      expect(v('1.2.0') <= v('1.2.0+0'), isTrue);
      expect(v('1.2.0') == v('1.2.0+0'), isTrue);
    });

    test("is pubspec.yaml's version", () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(
        appVersionString,
        version,
        reason:
            'lib/update/version.dart says which version the app is: '
            'change it with pubspec.yaml',
      );
      expect(currentAppVersion, v(version!));
    });
  });
}
