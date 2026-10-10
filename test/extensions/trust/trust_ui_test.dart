import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/trust/trust_ui.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart' show themeColors;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/main_thread_harness.dart';

void main() {
  testWidgets('the startup dialog asks about the folder and its parent', (
    tester,
  ) async {
    final harness = harnessFor();
    addTearDown(harness.dispose);
    await harness.initialize();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final prompt = IdeWorkspaceTrustPrompt(contextOf: () => context);

    final future = prompt.startup(
      workspace: false,
      label: '`BaoCode` /work/project',
      parentFolderName: 'work',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Do you trust the authors of the files in this folder?'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'BaoCode provides features that may automatically execute files',
      ),
      findsOneWidget,
    );
    expect(find.text('Yes, I trust the authors'), findsOneWidget);
    expect(find.text("No, I don't trust the authors"), findsOneWidget);
    expect(
      find.textContaining('Trust the authors of all files in the parent'),
      findsOneWidget,
    );

    await tester.tap(find.text('Yes, I trust the authors'));
    await tester.pumpAndSettle();
    final answer = await future;
    expect(answer.trust, isTrue);
    expect(answer.trustParent, isFalse);
  });

  testWidgets('the parent checkbox is reported back', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final future = IdeWorkspaceTrustPrompt(
      contextOf: () => context,
    ).startup(workspace: true, label: 'w', parentFolderName: 'work');
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('Trust the authors of all files in the parent'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, I trust the authors'));
    await tester.pumpAndSettle();
    expect((await future).trustParent, isTrue);
  });

  testWidgets('an extension\'s request offers Trust and Manage', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    var managed = false;
    final prompt = IdeWorkspaceTrustPrompt(
      contextOf: () => context,
      onManage: () => managed = true,
    );
    expect(prompt.canManage, isTrue);

    final future = prompt.request(
      workspace: false,
      message: 'Run tests?',
      buttons: const [
        (label: '', type: 'ContinueWithTrust'),
        (label: '', type: 'Manage'),
        (label: 'Cancel', type: 'Cancel'),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Run tests?'), findsOneWidget);
    expect(find.text('Trust Folder & Continue'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    // The button's type is answered; the service opens the settings with
    // `manage()` (see WorkspaceTrustService._showRequest).
    expect(await future, 'Manage');
    prompt.manage();
    expect(managed, isTrue);
  });

  testWidgets('the service trusts the folder through the dialog', (
    tester,
  ) async {
    final harness = harnessFor();
    addTearDown(harness.dispose);
    await harness.initialize();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    harness.trust.prompt = IdeWorkspaceTrustPrompt(contextOf: () => context);
    final future = harness.trust.requestWorkspaceTrust();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trust Folder & Continue'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
    expect(harness.trust.isWorkspaceTrusted, isTrue);
  });

  testWidgets('a resource trust request asks for the folder', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final future = IdeWorkspaceTrustPrompt(contextOf: () => context).resource(
      VsUri.file('/elsewhere/data'),
      message: 'Open the data folder?',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Open the data folder?'), findsOneWidget);
    expect(find.text('Trust Folder & Continue'), findsOneWidget);
    await tester.tap(find.text('Trust Folder & Continue'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });

  testWidgets('the Restricted Mode status item shows while untrusted', (
    tester,
  ) async {
    final harness = harnessFor();
    addTearDown(harness.dispose);
    await harness.initialize();
    expect(harness.trust.isWorkspaceTrusted, isFalse);
    final item = workspaceTrustStatusItem(
      harness.trust,
      englishLocalizations,
      onTrust: () {},
    );
    expect(item, isNotNull);
    expect(item!.text, 'Restricted Mode');
    expect(item.icon, Codicons.shield);
    await harness.trust.setWorkspaceTrust(true);
    expect(
      workspaceTrustStatusItem(
        harness.trust,
        englishLocalizations,
        onTrust: () {},
      ),
      isNull,
    );
  });

  test('the status item is in Chinese too', () async {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final harness = harnessFor();
    addTearDown(harness.dispose);
    await harness.initialize();
    final item = workspaceTrustStatusItem(
      harness.trust,
      zh,
      onTrust: () {},
    );
    expect(item!.text, '受限模式');
  });

  testWidgets('the trust dialog renders (screenshot)', (tester) async {
    final screens = Platform.environment['BAOCODE_EXTHOST_SCREENS'];
    await loadScreenshotFonts();
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: themeColors['editor.background'],
          fontFamily: screens == null ? null : 'Snapshot',
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => IdeWorkspaceTrustPrompt(
                    contextOf: () => context,
                  ).startup(
                    workspace: false,
                    label: '`BaoCode` /work/project',
                    parentFolderName: 'work',
                  ),
                  child: const Text('Trust'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Trust'));
    await tester.pumpAndSettle();
    expect(
      find.text('Do you trust the authors of the files in this folder?'),
      findsOneWidget,
    );
    if (screens == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(screens, 'workspace_trust.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
  });
}

/// Loads the screenshot fonts when `BAOCODE_EXTHOST_SCREENS` is set.
Future<void> loadScreenshotFonts() async {
  if (Platform.environment['BAOCODE_EXTHOST_SCREENS'] == null) return;
  for (final (family, path) in [
    ('Snapshot', '/System/Library/Fonts/Supplemental/Arial.ttf'),
    (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
  ]) {
    if (!File(path).existsSync()) continue;
    await (FontLoader(family)
          ..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
        .load();
  }
}

MainThreadHarness harnessFor() =>
    MainThreadHarness(folder: Directory('/work/project'));
