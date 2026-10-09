import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/gallery/gallery_models.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'fixture_http.dart';

const _mac = ExtensionTargetPlatform.darwinArm64;

OpenVsxClient _client(FixtureHttp http, {String? cacheDir, String? engine}) =>
    OpenVsxClient(
      http: http,
      cacheDir: cacheDir,
      targetPlatform: _mac,
      versionPageSize: 50,
      engineVersion: engine ?? '1.135.0',
    );

/// A version entry of `/api/v2/-/query`.
Map<String, Object?> _version(
  String version, {
  String platform = 'universal',
  bool preRelease = false,
  String engine = '^1.80.0',
}) => {
  'namespace': 'acme',
  'name': 'tool',
  'version': version,
  'targetPlatform': platform,
  'preRelease': preRelease,
  'engines': {'vscode': engine},
  'files': {'download': 'https://example.test/acme.tool-$version.vsix'},
};

void main() {
  group('search', () {
    test('reads a page of results', () async {
      final http = FixtureHttp();
      final result = await _client(http)
          .search(const GallerySearchQuery(text: 'python', size: 5));
      expect(result.totalSize, greaterThan(100));
      expect(result.extensions, hasLength(5));
      final python = result.extensions.first;
      expect(python.id, 'ms-python.python');
      expect(python.label, 'Python');
      expect(python.verified, isTrue);
      expect(python.downloadCount, greaterThan(1000000));
      expect(python.iconUrl, endsWith('/icon.png'));
      expect(result.hasMore, isTrue);
    });

    test('sends the category and the order', () async {
      final http = FixtureHttp();
      final result = await _client(http).search(
        const GallerySearchQuery(
          text: 'yaml',
          category: 'Programming Languages',
          sortBy: GallerySortBy.downloads,
          size: 3,
        ),
      );
      expect(http.requests.single, contains('sortBy=downloadCount'));
      expect(http.requests.single, contains('category=Programming Languages'));
      expect(result.extensions, hasLength(3));
    });
  });

  group('details', () {
    test('an extension with its files and versions', () async {
      final prettier = await _client(FixtureHttp())
          .getExtension('esbenp.prettier-vscode');
      expect(prettier.id, 'esbenp.prettier-vscode');
      expect(prettier.version, '12.4.0');
      expect(prettier.engine, '^1.101.0');
      expect(prettier.targetPlatform, ExtensionTargetPlatform.universal);
      expect(prettier.verified, isTrue);
      expect(prettier.license, 'MIT');
      expect(prettier.publisherLabel, 'Prettier');
      expect(prettier.files.sha256, endsWith('.sha256'));
      expect(prettier.files.readme, endsWith('readme.md'));
      expect(prettier.files.changelog, endsWith('changelog.md'));
      expect(prettier.versionNames.first, '12.4.0');
      expect(prettier.versionNames, contains('12.3.0'));
      expect(prettier.hasPreRelease, isFalse);
    });

    test('platform-specific packages and dependencies', () async {
      final client = _client(FixtureHttp());
      final rust = await client.getExtension('rust-lang.rust-analyzer');
      expect(
        rust.targetPlatforms,
        containsAll([_mac, ExtensionTargetPlatform.linuxX64]),
      );
      expect(rust.hasPreRelease, isTrue);
      final python = await client.getExtension('ms-python.python');
      expect(
        python.bundledExtensions,
        containsAll(['ms-python.vscode-pylance', 'ms-python.debugpy']),
      );
    });

    test('an unknown extension is not found', () async {
      final client = _client(FixtureHttp());
      await expectLater(
        client.getExtension('github.copilot'),
        throwsA(
          isA<GalleryException>().having(
            (e) => e.kind,
            'kind',
            GalleryErrorKind.notFound,
          ),
        ),
      );
      expect(await client.findExtension('ms-python.vscode-pylance'), isNull);
    });

    test('README and changelog', () async {
      final client = _client(FixtureHttp());
      final prettier = await client.getExtension('esbenp.prettier-vscode');
      expect(
        await client.fetchText(prettier.files.readme!),
        contains('Prettier'),
      );
      expect(await client.fetchText(prettier.files.changelog!), isNotEmpty);
    });

    test('answers are cached', () async {
      final http = FixtureHttp();
      final client = _client(http);
      await client.getExtension('esbenp.prettier-vscode');
      await client.getExtension('esbenp.prettier-vscode');
      expect(http.requests, hasLength(1));
      client.clearCache();
      await client.getExtension('esbenp.prettier-vscode');
      expect(http.requests, hasLength(2));
    });
  });

  group('resolveCompatible', () {
    test('falls back to the universal package', () async {
      final resolved = await _client(FixtureHttp())
          .resolveCompatible('esbenp.prettier-vscode');
      expect(resolved.extension.version, '12.4.0');
      expect(
        resolved.extension.targetPlatform,
        ExtensionTargetPlatform.universal,
      );
      expect(resolved.preReleaseFallback, isFalse);
    });

    test("prefers this platform's package", () async {
      final resolved = await _client(
        FixtureHttp(),
      ).resolveCompatible('rust-lang.rust-analyzer', includePreRelease: true);
      expect(resolved.extension.targetPlatform, _mac);
      expect(resolved.extension.version, '0.4.3077');
      expect(
        resolved.extension.files.download,
        endsWith('rust-lang.rust-analyzer-0.4.3077@darwin-arm64.vsix'),
      );
    });

    test('skips pre-releases for the newest release', () async {
      final http = FixtureHttp();
      final resolved = await _client(http)
          .resolveCompatible('redhat.vscode-yaml');
      // The latest (1.25.x) is a pre-release; 1.24.0 is the newest release.
      expect(resolved.extension.version, '1.24.0');
      expect(resolved.extension.preRelease, isFalse);
      expect(resolved.preReleaseFallback, isFalse);
      expect(http.requests, contains(contains('/api/v2/-/query')));
    });

    test('takes the pre-release when asked to', () async {
      final resolved = await _client(FixtureHttp())
          .resolveCompatible('redhat.vscode-yaml', includePreRelease: true);
      expect(resolved.extension.version, '1.25.2026100808');
      expect(resolved.extension.preRelease, isTrue);
    });

    test('an extension of pre-releases only gets one, flagged', () async {
      final http = FixtureHttp(recorded: false)
        ..add('/api/acme/tool/darwin-arm64/latest', const [], status: 404)
        ..addJson(
          '/api/acme/tool/universal/latest',
          _version('2.0.0', preRelease: true),
        )
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=universal'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 2,
            'extensions': [
              _version('2.0.0', preRelease: true),
              _version('1.9.0', preRelease: true),
            ],
          },
        )
        ..addJson(
          '/api/acme/tool/universal/2.0.0',
          _version('2.0.0', preRelease: true),
        );
      final resolved = await _client(http).resolveCompatible('acme.tool');
      expect(resolved.extension.version, '2.0.0');
      expect(resolved.preReleaseFallback, isTrue);
      await expectLater(
        _client(http)
            .resolveCompatible('acme.tool', allowPreReleaseFallback: false),
        throwsA(isA<GalleryException>()),
      );
    });

    test('an older version for an older VS Code', () async {
      final http = FixtureHttp(recorded: false)
        ..add('/api/acme/tool/darwin-arm64/latest', const [], status: 404)
        ..addJson(
          '/api/acme/tool/universal/latest',
          _version('3.0.0', engine: '^1.200.0'),
        )
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=universal'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 3,
            'extensions': [
              _version('3.0.0', engine: '^1.200.0'),
              _version('2.5.0', engine: '^1.140.0'),
              _version('2.4.0', engine: '^1.130.0'),
            ],
          },
        )
        ..addJson('/api/acme/tool/universal/2.4.0', _version('2.4.0'));
      final resolved = await _client(http).resolveCompatible('acme.tool');
      expect(resolved.extension.version, '2.4.0');

      final none = FixtureHttp(recorded: false)
        ..add('/api/acme/tool/darwin-arm64/latest', const [], status: 404)
        ..addJson(
          '/api/acme/tool/universal/latest',
          _version('3.0.0', engine: '^2.0.0'),
        )
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=universal'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 1,
            'extensions': [_version('3.0.0', engine: '^2.0.0')],
          },
        );
      await expectLater(
        _client(none).resolveCompatible('acme.tool'),
        throwsA(
          isA<GalleryException>().having(
            (e) => e.kind,
            'kind',
            GalleryErrorKind.incompatibleEngine,
          ),
        ),
      );
    });

    test("this platform's package of a release found past its pages", () async {
      // rust-analyzer: over a thousand pre-releases per platform before the
      // releases; the universal list reaches one first.
      final http = FixtureHttp(recorded: false)
        ..addJson(
          '/api/acme/tool/darwin-arm64/latest',
          _version('2.1.0', platform: 'darwin-arm64', preRelease: true),
        )
        ..addJson(
          '/api/acme/tool/universal/latest',
          _version('2.1.0', preRelease: true),
        )
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=darwin-arm64'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 1000,
            'extensions': [
              _version('2.1.0', platform: 'darwin-arm64', preRelease: true),
            ],
          },
        )
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=universal'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 2,
            'extensions': [
              _version('2.1.0', preRelease: true),
              _version('2.0.0'),
            ],
          },
        )
        ..addJson(
          '/api/acme/tool/darwin-arm64/2.0.0',
          _version('2.0.0', platform: 'darwin-arm64'),
        );
      final client = OpenVsxClient(
        http: http,
        targetPlatform: _mac,
        versionPageSize: 50,
        maxVersionPages: 1,
        engineVersion: '1.135.0',
      );
      final resolved = await client.resolveCompatible('acme.tool');
      expect(resolved.extension.version, '2.0.0');
      expect(resolved.extension.targetPlatform, _mac);
    });

    test('no package for this platform', () async {
      final http = FixtureHttp(recorded: false)
        ..add('/api/acme/tool/darwin-arm64/latest', const [], status: 404)
        ..add('/api/acme/tool/universal/latest', const [], status: 404)
        ..addJson('/api/acme/tool', _version('1.0.0', platform: 'win32-x64'));
      await expectLater(
        _client(http).resolveCompatible('acme.tool'),
        throwsA(
          isA<GalleryException>().having(
            (e) => e.kind,
            'kind',
            GalleryErrorKind.noCompatiblePlatform,
          ),
        ),
      );
    });

    test('lists versions of both platforms, newest first', () async {
      final http = FixtureHttp(recorded: false)
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=darwin-arm64'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 1,
            'extensions': [_version('2.0.0', platform: 'darwin-arm64')],
          },
        )
        ..addJson(
          '/api/v2/-/query?extensionId=acme.tool&targetPlatform=universal'
          '&includeAllVersions=true&size=50&offset=0',
          {
            'offset': 0,
            'totalSize': 2,
            'extensions': [
              _version('2.0.0'),
              _version('1.0.0-next.1', preRelease: true),
            ],
          },
        );
      final versions = await _client(http).listVersions('acme.tool');
      expect([for (final v in versions) v.version], ['2.0.0', '1.0.0-next.1']);
      expect(versions.first.targetPlatform, _mac);
      expect(versions.last.preRelease, isTrue);
    });
  });

  group('download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vsix-cache'));
    tearDown(() => dir.deleteSync(recursive: true));

    GalleryExtension extension({bool sha = true}) => GalleryExtension.fromJson({
      ..._version('1.0.0'),
      'files': {
        'download': 'https://example.test/acme.tool-1.0.0.vsix',
        if (sha) 'sha256': 'https://example.test/acme.tool-1.0.0.sha256',
      },
    });

    test('checks the SHA-256 and caches', () async {
      final bytes = List.generate(100000, (i) => i % 251);
      final hash = crypto.sha256.convert(bytes).toString();
      final http = FixtureHttp(recorded: false)
        ..add('/acme.tool-1.0.0.vsix', bytes)
        ..add('/acme.tool-1.0.0.sha256', utf8.encode('$hash  x.vsix\n'));
      final client = _client(http, cacheDir: dir.path);
      final progress = <int>[];
      final first = await client.download(
        extension(),
        onProgress: (received, total) => progress.add(received),
      );
      expect(first.verified, isTrue);
      expect(first.fromCache, isFalse);
      expect(first.sha256, hash);
      expect(File(first.path).readAsBytesSync(), bytes);
      expect(first.path, endsWith('acme.tool-1.0.0.vsix'));
      expect(progress.last, bytes.length);

      final second = await client.download(extension());
      expect(second.fromCache, isTrue);
      expect(second.path, first.path);
    });

    test('a mismatch fails and leaves nothing', () async {
      final http = FixtureHttp(recorded: false)
        ..add('/acme.tool-1.0.0.vsix', [1, 2, 3])
        ..add('/acme.tool-1.0.0.sha256', utf8.encode('0' * 64));
      await expectLater(
        _client(http, cacheDir: dir.path).download(extension()),
        throwsA(
          isA<GalleryException>().having(
            (e) => e.kind,
            'kind',
            GalleryErrorKind.checksumMismatch,
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('without a hash it is not verified', () async {
      final http = FixtureHttp(recorded: false)
        ..add('/acme.tool-1.0.0.vsix', [1, 2, 3]);
      final result = await _client(
        http,
        cacheDir: dir.path,
      ).download(extension(sha: false));
      expect(result.verified, isFalse);
    });

    test('cancelled before it starts', () async {
      final source = CancellationTokenSource()..cancel();
      final http = FixtureHttp(recorded: false)
        ..add('/acme.tool-1.0.0.vsix', [1, 2, 3]);
      await expectLater(
        _client(
          http,
          cacheDir: dir.path,
        ).download(extension(sha: false), cancel: source.token),
        throwsA(isA<CancellationException>()),
      );
    });

    test("the recorded prettier hash is the registry's format", () {
      final text = File('$openVsxFixtures/esbenp.prettier-vscode-12.4.0.sha256')
          .readAsStringSync();
      expect(RegExp(r'^[0-9a-f]{64}').hasMatch(text), isTrue);
    });
  });
}
