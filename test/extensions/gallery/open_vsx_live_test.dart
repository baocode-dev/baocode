// Against the real Open VSX: opt in with
// `flutter test --run-skipped -t exthost test/extensions/gallery`.
@Tags(['exthost'])
library;

import 'dart:io';

import 'package:baocode/extensions/capabilities/capability_analysis.dart';
import 'package:baocode/extensions/gallery/gallery_models.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:baocode/extensions/vsix/vsix_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search, resolve, download and read prettier', () async {
    // flutter_test answers every request with 400 otherwise.
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('openvsx-live');
    addTearDown(() => dir.deleteSync(recursive: true));
    final client = OpenVsxClient(cacheDir: dir.path);
    final found = await client.search(
      const GallerySearchQuery(text: 'prettier', size: 5),
    );
    expect(
      found.extensions.map((e) => e.id),
      contains('esbenp.prettier-vscode'),
    );
    final resolved = await client.resolveCompatible('esbenp.prettier-vscode');
    final download = await client.download(resolved.extension);
    expect(download.verified, isTrue);
    final package = await ExtensionPackage.openVsix(download.path);
    addTearDown(package.close);
    expect(package.manifest.id, 'esbenp.prettier-vscode');
    expect(package.manifest.engineCompatible, isTrue);
    // A formatter, not a theme: BaoCode does not take it.
    final report = analyzeExtensionPackage(package);
    expect(report.level, ExtensionCapabilityLevel.unsupported);

    final rust = await client.resolveCompatible(
      'rust-lang.rust-analyzer',
      platform: ExtensionTargetPlatform.linuxX64,
      includePreRelease: true,
    );
    expect(rust.extension.targetPlatform, ExtensionTargetPlatform.linuxX64);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
