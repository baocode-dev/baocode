import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/version.dart';

final _signature = base64.encode(List.filled(64, 7));

Map<String, Object?> _asset({
  String url = 'https://baocode.dev/releases/1.2.0/BaoCode-1.2.0-setup.exe',
  Object? size = 1000,
  Object? sha256,
  Object? signature,
}) => {
  'url': url,
  'size': ?size,
  'sha256': sha256 ?? 'a' * 64,
  'signature': signature ?? _signature,
};

String _manifest({
  Object? version = '1.2.0+12',
  Map<String, Object?>? platforms,
  Object? notes,
  Object? minimumVersion,
}) => jsonEncode({
  'version': ?version,
  'pubDate': '2026-10-04T00:00:00Z',
  'notes': ?notes,
  'minimumVersion': ?minimumVersion,
  'platforms':
      platforms ??
      {
        'windows-x64': _asset(),
        'macos-universal': _asset(
          url: 'https://baocode.dev/releases/1.2.0/BaoCode-1.2.0-mac.zip',
        ),
      },
});

Matcher _invalid(String part) => throwsA(
  isA<UpdateManifestException>().having(
    (e) => e.message,
    'message',
    contains(part),
  ),
);

void main() {
  group('UpdateManifest', () {
    test('reads the release, its notes and downloads', () {
      final manifest = UpdateManifest.parse(
        _manifest(notes: {'en': 'Fixes', 'zh': '修复'}, minimumVersion: '1.0.0'),
      );
      expect(manifest.version, AppVersion.parse('1.2.0+12'));
      expect(manifest.pubDate, DateTime.utc(2026, 10, 4));
      expect(manifest.minimumVersion, AppVersion.parse('1.0.0'));
      expect(manifest.notesFor('zh'), '修复');
      expect(manifest.notesFor('fr'), 'Fixes');
      final asset = manifest.assetFor('windows-x64')!;
      expect(asset.size, 1000);
      expect(asset.sha256, 'a' * 64);
      expect(asset.fileName, 'BaoCode-1.2.0-setup.exe');
      expect(
        manifest.platforms,
        containsAll(['windows-x64', 'macos-universal']),
      );
    });

    test('a platform it has no download for has none', () {
      final manifest = UpdateManifest.parse(
        _manifest(platforms: {'windows-x64': _asset()}),
      );
      expect(manifest.assetFor('macos-universal'), isNull);
    });

    test('notes may be one text, or none', () {
      expect(
        UpdateManifest.parse(_manifest(notes: 'Fixes')).notesFor('zh'),
        'Fixes',
      );
      expect(UpdateManifest.parse(_manifest()).notesFor('en'), isNull);
    });

    test('is refused without what it needs', () {
      expect(() => UpdateManifest.parse('not json'), _invalid('not JSON'));
      expect(() => UpdateManifest.parse('[]'), _invalid('not an object'));
      expect(
        () => UpdateManifest.parse(_manifest(version: null)),
        _invalid('version'),
      );
      expect(
        () => UpdateManifest.parse(_manifest(version: 'latest')),
        _invalid('version'),
      );
      expect(
        () => UpdateManifest.parse(_manifest(minimumVersion: 'soon')),
        _invalid('minimumVersion'),
      );
      expect(
        () => UpdateManifest.parse(jsonEncode({'version': '1.0.0'})),
        _invalid('platforms'),
      );
    });

    test("a platform's wrong entry keeps only that platform's users", () {
      final manifest = UpdateManifest.parse(
        _manifest(
          platforms: {
            'windows-x64': _asset(size: null),
            'macos-universal': _asset(
              url: 'https://baocode.dev/releases/1.2.0/BaoCode-1.2.0-mac.zip',
            ),
          },
        ),
      );
      expect(manifest.assetFor('macos-universal'), isNotNull);
      expect(() => manifest.assetFor('windows-x64'), _invalid('size'));
    });

    test('a field missing or wrong in a download is refused', () {
      UpdateManifest entry(Map<String, Object?> asset) =>
          UpdateManifest.parse(_manifest(platforms: {'windows-x64': asset}));
      for (final (asset, field) in [
        (_asset(size: 0), 'size'),
        (_asset(size: '1000'), 'size'),
        (_asset(sha256: 'abc'), 'sha256'),
        (_asset(sha256: 'g' * 64), 'sha256'),
        (_asset(signature: 'not base64!'), 'signature'),
        (_asset(signature: base64.encode([1, 2, 3])), 'signature'),
        ({..._asset()}..remove('url'), 'url'),
      ]) {
        expect(
          () => entry(asset).assetFor('windows-x64'),
          _invalid(field),
          reason: '$asset',
        );
      }
    });

    test('downloads have to be https links on baocode.dev', () {
      UpdateManifest at(String url) => UpdateManifest.parse(
        _manifest(platforms: {'windows-x64': _asset(url: url)}),
      );
      for (final url in [
        'http://baocode.dev/releases/x.exe',
        'https://evil.example/x.exe',
        'https://baocode.dev.evil.example/x.exe',
        'https://notbaocode.dev/x.exe',
        'https://baocode.dev:8443/x.exe',
        'https://user@baocode.dev/x.exe',
        'ftp://baocode.dev/x.exe',
        'file:///tmp/x.exe',
        '/releases/x.exe',
      ]) {
        expect(
          () => at(url).assetFor('windows-x64'),
          _invalid('https'),
          reason: url,
        );
      }
      for (final url in [
        'https://baocode.dev/releases/x.exe',
        'https://BAOCODE.dev/releases/x.exe',
        'https://cdn.baocode.dev/x.exe',
      ]) {
        expect(at(url).assetFor('windows-x64'), isNotNull, reason: url);
      }
    });

    test("a manifest from elsewhere may link to its own origin", () {
      final policy = UpdateUrlPolicy.forManifest(
        Uri.parse('http://127.0.0.1:8080/latest.json'),
      );
      UpdateManifest at(String url) => UpdateManifest.parse(
        _manifest(platforms: {'windows-x64': _asset(url: url)}),
        policy: policy,
      );
      expect(
        at('http://127.0.0.1:8080/x.exe').assetFor('windows-x64'),
        isNotNull,
      );
      expect(
        at('https://baocode.dev/x.exe').assetFor('windows-x64'),
        isNotNull,
      );
      expect(
        () => at('http://127.0.0.1:9090/x.exe').assetFor('windows-x64'),
        _invalid('https'),
      );
      expect(
        UpdateUrlPolicy.forManifest(Uri.parse(defaultManifestUrl)).extraOrigins,
        isEmpty,
      );
    });

    test('writes itself back as it reads', () {
      final manifest = UpdateManifest.parse(
        _manifest(notes: {'en': 'Fixes'}, minimumVersion: '1.0.0'),
      );
      final again = UpdateManifest.parse(jsonEncode(manifest.toJson()));
      expect(again.version, manifest.version);
      expect(again.minimumVersion, manifest.minimumVersion);
      expect(again.notes, manifest.notes);
      expect(again.pubDate, manifest.pubDate);
      expect(
        again.assetFor('macos-universal')!.toJson(),
        manifest.assetFor('macos-universal')!.toJson(),
      );
    });
  });
}
