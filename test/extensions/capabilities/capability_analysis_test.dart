import 'dart:io';

import 'package:baocode/extensions/capabilities/capability_analysis.dart';
import 'package:baocode/extensions/vsix/vsix_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../vsix/zip_writer.dart';

const _fixtures = 'test/fixtures/extensions/capabilities';

Future<CapabilityReport> _analyze(
  String path, {
  CapabilityScanLimits limits = const CapabilityScanLimits(),
}) async {
  final package = await ExtensionPackage.open(path);
  try {
    return await analyzeExtensionPackage(package, limits: limits);
  } finally {
    await package.close();
  }
}

/// Every file under [dir], by its relative path.
Map<String, Object> _read(String dir) => {
  for (final file in Directory(dir).listSync(recursive: true).whereType<File>())
    file.path.substring(dir.length + 1): file.readAsBytesSync(),
};

void main() {
  test('a language extension is fully usable', () async {
    final report = await _analyze('$_fixtures/language');
    expect(report.level, ExtensionCapabilityLevel.full);
    expect(report.findings, isEmpty);
    expect(
      report.coreFeatures,
      containsAll([
        CoreFeature.languageFeatures,
        CoreFeature.languageServer,
        CoreFeature.syntaxHighlighting,
      ]),
    );
    expect(report.scannedFiles, ['out/extension.js']);
  });

  test('a declarative theme is fully usable without code', () async {
    final report = await _analyze('$_fixtures/theme');
    expect(report.level, ExtensionCapabilityLevel.full);
    expect(report.coreFeatures, {CoreFeature.themes});
    expect(report.scannedFiles, isEmpty);
  });

  test(
    'a preview needs webviews: commands and completion alone do not count',
    () async {
      final report = await _analyze('$_fixtures/preview');
      expect(report.level, ExtensionCapabilityLevel.needsWebview);
      expect(
        report.findings,
        containsAll(const [
          CapabilityFinding(
            CapabilityFindingKind.customEditor,
            'Fancy Preview',
          ),
          CapabilityFinding(
            CapabilityFindingKind.webviewPanelCode,
            'dist/extension.js',
          ),
          CapabilityFinding(
            CapabilityFindingKind.customEditorCode,
            'dist/extension.js',
          ),
        ]),
      );
      expect(report.coreFeatures, isEmpty);
    },
  );

  test('tree views beside a webview view: partially usable', () async {
    final report = await _analyze('$_fixtures/tree-and-panel');
    expect(report.level, ExtensionCapabilityLevel.partial);
    expect(
      report.findings,
      containsAll(const [
        CapabilityFinding(CapabilityFindingKind.webviewView, 'Home'),
        CapabilityFinding(
          CapabilityFindingKind.webviewViewCode,
          'dist/main.js',
        ),
      ]),
    );
    expect(report.coreFeatures, {CoreFeature.treeViews});
  });

  test('notebooks need webviews', () async {
    final report = await _analyze('$_fixtures/notebooks');
    expect(report.level, ExtensionCapabilityLevel.needsWebview);
    expect(report.findings.map((finding) => finding.kind).toSet(), {
      CapabilityFindingKind.notebook,
      CapabilityFindingKind.notebookRenderer,
      CapabilityFindingKind.notebookCode,
    });
  });

  test('a web worker only extension is partially usable', () async {
    final report = await _analyze('$_fixtures/web-only');
    expect(report.level, ExtensionCapabilityLevel.partial);
    expect(report.findings, [
      const CapabilityFinding(CapabilityFindingKind.browserOnly),
    ]);
    expect(report.scannedFiles, ['dist/web.js']);
  });

  test('webviews in another chunk of the bundle are found', () async {
    final report = await _analyze('$_fixtures/split-bundle');
    expect(report.level, ExtensionCapabilityLevel.needsWebview);
    expect(report.findings, [
      const CapabilityFinding(
        CapabilityFindingKind.webviewPanelCode,
        'dist/chunks/ui.js',
      ),
    ]);
  });

  group('with node_modules', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('capabilities'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a module mentioning webviews is not scanned; a language client '
        'module counts', () async {
      writeFolder(dir.path, {
        ..._read('$_fixtures/theme'),
        'package.json': {
          'name': 'mod',
          'publisher': 'fixture',
          'version': '1.0.0',
          'engines': {'vscode': '^1.90.0'},
          'main': 'main.js',
        },
        'main.js': 'exports.activate = () => {};',
        'node_modules/lib/index.js': 'x.createWebviewPanel()',
        'node_modules/vscode-languageclient/lib/node/main.js': '//',
      });
      final report = await _analyze(dir.path);
      expect(report.level, ExtensionCapabilityLevel.full);
      expect(report.coreFeatures, contains(CoreFeature.languageServer));
      expect(report.scannedFiles, ['main.js']);
    });

    test('a .vsix is scanned as its folder would be', () async {
      final path = '${dir.path}/preview.vsix';
      File(path).writeAsBytesSync(buildVsix(_read('$_fixtures/preview')));
      final report = await _analyze(path);
      expect(report.level, ExtensionCapabilityLevel.needsWebview);
      expect(report.scannedFiles, ['dist/extension.js']);
    });

    test('what the limits leave out is reported', () async {
      final report = await _analyze(
        '$_fixtures/split-bundle',
        limits: const CapabilityScanLimits(maxFiles: 1),
      );
      expect(report.scannedFiles, ['dist/main.js']);
      expect(report.findings, [
        const CapabilityFinding(CapabilityFindingKind.scanIncomplete),
      ]);
      expect(report.level, ExtensionCapabilityLevel.full);
    });
  });
}
