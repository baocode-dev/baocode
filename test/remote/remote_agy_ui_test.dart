import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/acp.dart' show AgyRelease, ManagedAgy;
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:baocode/remote/remote_agy.dart';
import 'package:baocode/remote/remote_agy_card.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/remote_status.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('Remote Antigravity status bar indicator', () {
    late Directory dataDir;
    late MemoryConnector connector;
    late SshHosts hosts;

    setUp(() async {
      dataDir = Directory.systemTemp.createTempSync('baocode-agy-ui-');
      connector = MemoryConnector(dataDir.path);
      hosts = SshHosts(connect: connector.call);
      await hosts['dev'].ready;
    });

    tearDown(() async {
      await hosts.closeAll();
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    });

    testWidgets(
      'SshStatusIndicator shows unsized, downloading 42%, and uploading 75% without duplicating in ClaudeInstallBanner',
      (tester) async {
        final host = hosts['dev'];
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                ClaudeInstallBanner(
                  location: RemoteLocation.of('dev', '/work/app'),
                  hosts: hosts,
                ),
              ],
            ),
          ),
        );

        final context = tester.element(find.byType(Column).first);

        // 1. Unknown size.
        host.installingAgy = const ClaudeInstallProgress(0, null);
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final unsizedItem = SshStatusIndicator(host).item(context);
        expect(
          unsizedItem.text,
          'SSH: dev (installing Antigravity CLI...)',
        );
        expect(unsizedItem.tooltip, 'Installing Antigravity CLI on dev…');

        // 2. Downloading 42%.
        host.installingAgy = const ClaudeInstallProgress(42, 100);
        await tester.pump();
        final downloadingItem = SshStatusIndicator(host).item(context);
        expect(
          downloadingItem.text,
          'SSH: dev (installing Antigravity CLI 42%)',
        );
        expect(
          downloadingItem.tooltip,
          'Installing Antigravity CLI on dev… 42%',
        );

        // 3. Uploading 75%.
        host.installingAgy = const ClaudeInstallProgress(
          75,
          100,
          uploading: true,
        );
        await tester.pump();
        final uploadingItem = SshStatusIndicator(host).item(context);
        expect(
          uploadingItem.text,
          'SSH: dev (installing Antigravity CLI 75%)',
        );
        expect(
          uploadingItem.tooltip,
          'Sending Antigravity CLI to dev… 75%',
        );
      },
    );
  });

  group('RemoteAgySetupCard inline in-conversation flow', () {
    late Directory dataDir;
    late Directory home;
    late MemoryConnector connector;
    late SshHosts hosts;
    late HttpServer feedServer;
    late File archiveFile;
    late String archiveSha;
    late String target;
    final previousProxy = NetworkProxy.instance;

    const mockAgyScript = r'''#!/bin/sh
if [ "$1" = "models" ]; then
  if [ -f "$HOME/.mock-agy-authed" ]; then
    printf 'gemini-3-pro\tGemini 3 Pro\n'
    exit 0
  fi
  echo "Please sign in first" >&2
  exit 1
fi
if [ "$1" = "acp" ] && [ "$2" = "--login" ]; then
  echo "Open this link in a browser to log in with Google:"
  echo "  https://accounts.google.com/o/oauth2/auth?client_id=test&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback&state=abc"
  read code
  if [ -n "$code" ]; then
    touch "$HOME/.mock-agy-authed"
    echo "Signed in!"
    exit 0
  fi
  exit 1
fi
exit 0
''';

    setUp(() async {
      HttpOverrides.global = null;
      NetworkProxy.instance = NetworkProxy(
        system: () async => const ProxyRoute.direct(),
        environment: () async => const {},
      );
      dataDir = Directory.systemTemp.createTempSync('baocode-agy-card-data-');
      home = Directory.systemTemp.createTempSync('baocode-agy-card-home-');
      ManagedAgy.systemCandidatesOverride = (_) => const [];
      ClaudeEnvironment.use({'PATH': '/usr/bin:/bin', 'HOME': home.path});
      connector = MemoryConnector(dataDir.path);
      hosts = SshHosts(connect: connector.call);
      final client = await hosts['dev'].ready;
      target = AgyRelease.targetOf(client.hello!.platform);

      // Build a real .tar.gz archive for the fake release feed.
      final src = Directory(p.join(home.path, 'pkg'))..createSync();
      final bin = File(p.join(src.path, 'antigravity'))
        ..writeAsStringSync(mockAgyScript);
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['755', bin.path]);
      }
      archiveFile = File(p.join(home.path, 'antigravity-$target.tar.gz'));
      Process.runSync('tar', [
        '-czf',
        archiveFile.path,
        '-C',
        src.path,
        'antigravity',
      ]);
      archiveSha = sha512.convert(archiveFile.readAsBytesSync()).toString();

      feedServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${feedServer.port}';
      feedServer.listen((req) async {
        if (req.uri.path == '/manifests/$target.json') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'version': '2.5.0',
              'url': '$base/downloads/antigravity-$target.tar.gz',
              'sha512': archiveSha,
            }),
          );
          await req.response.close();
          return;
        }
        if (req.uri.path == '/downloads/antigravity-$target.tar.gz') {
          req.response.headers.contentLength = archiveFile.lengthSync();
          req.response.add(archiveFile.readAsBytesSync());
          await req.response.close();
          return;
        }
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });

      AgyRelease.feedOverride = '$base/manifests';
      AgyRelease.downloadsPrefixOverride = '$base/downloads/';
    });

    tearDown(() async {
      NetworkProxy.instance = previousProxy;
      ManagedAgy.systemCandidatesOverride = null;
      AgyRelease.feedOverride = null;
      AgyRelease.downloadsPrefixOverride = null;
      ClaudeEnvironment.use(null);
      await feedServer.close(force: true);
      await hosts.closeAll();
      for (final dir in [dataDir, home]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'confirms install, installs directly, opens inline OAuth paste card, submits code, and fires onReady',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final openedUrls = <Uri>[];
        var readyCalls = 0;
        final controller = RemoteAgySetupController(
          hosts['dev'],
          openUrl: (uri) async => openedUrls.add(uri),
        );
        addTearDown(controller.dispose);

        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(
          _app(
            Padding(
              padding: const EdgeInsets.all(16),
              child: RemoteAgySetupCard(
                location: RemoteLocation.of('dev', '/work/app'),
                model: 'agy/gemini-3-pro',
                controller: controller,
                onReady: () => readyCalls++,
              ),
            ),
          ),
        );

        Future<void> waitUntil(bool Function() condition) async {
          for (var i = 0; i < 120; i++) {
            if (condition()) return;
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump();
          }
        }

        // Wait for initial check to surface the install confirmation card.
        await waitUntil(
          () => controller.stage == RemoteAgySetupStage.needsInstall,
        );
        expect(find.text('Install Antigravity CLI on dev'), findsOneWidget);
        expect(find.text('Install'), findsOneWidget);

        // Confirm install -> installs -> transitions straight into signingIn with URL.
        await tester.tap(find.text('Install'));
        await tester.pump();
        await waitUntil(
          () =>
              controller.stage == RemoteAgySetupStage.signingIn &&
              controller.authUrl != null,
        );

        expect(controller.stage, RemoteAgySetupStage.signingIn);
        expect(openedUrls, hasLength(1));
        expect(openedUrls.single.host, 'accounts.google.com');
        expect(find.text('Sign in to Antigravity on dev'), findsOneWidget);
        expect(find.text('Open Link'), findsOneWidget);
        expect(find.text('Copy Link'), findsOneWidget);
        expect(find.text('Finish Sign In'), findsOneWidget);

        // Copy Link works inline.
        await tester.tap(find.text('Copy Link'));
        await tester.pump();
        expect(copied, hasLength(1));
        expect(find.text('Copied'), findsOneWidget);

        // Paste auth code and finish sign in.
        await tester.enterText(find.byType(IdeInputBox), '  oauth-code-xyz  ');
        await tester.pump();
        await tester.tap(find.text('Finish Sign In'));
        await tester.pump();

        await waitUntil(() => controller.stage == RemoteAgySetupStage.ready);

        expect(controller.stage, RemoteAgySetupStage.ready);
        expect(readyCalls, 1);
        expect(find.text('Sign in to Antigravity on dev'), findsNothing);
      },
    );
  });
}
