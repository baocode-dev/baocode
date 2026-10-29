import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/browser/browser_bridge.dart';
import 'package:baocode/l10n/app_localizations_en.dart';
import 'package:baocode/settings/pages/browser_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final bridge = BrowserBridge.instance;
  late Directory home;
  late File manifest;

  setUp(() {
    // Short: a socket's path has a hundred bytes or so.
    final temp = (Platform.isWindows ? Directory.systemTemp : Directory('/tmp'))
        .createTempSync('bao-');
    addTearDown(() => temp.deleteSync(recursive: true));
    BrowserBridge.socketFolder = temp.path;
    home = Directory(p.join(temp.path, 'home'));
    BrowserBridge.home = home.path;
    manifest = File(
      p.join(
        home.path,
        Platform.isLinux
            ? '.config/google-chrome/NativeMessagingHosts'
            : 'Library/Application Support/Google/Chrome/NativeMessagingHosts',
        '${BrowserBridge.hostName}.json',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      bridge.enabled = true;
      await bridge.stop();
      BrowserBridge.home = null;
      BrowserBridge.socketFolder = null;
    });
  });

  void send(Socket socket, Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    socket
      ..add(
        (ByteData(
          4,
        )..setUint32(0, body.length, Endian.little)).buffer.asUint8List(),
      )
      ..add(body);
  }

  /// A host of the browser's, as host.c is: its hello with the extension's
  /// origin, then the extension's. Over loopback, as host.cpp is: at the
  /// port the bridge's file says, the token in its hello ([token] instead,
  /// when given).
  Future<Socket> connect(Map<String, Object?> hello, {String? token}) async {
    final Socket socket;
    String? said;
    if (BrowserBridge.loopback) {
      final [port, written] = File(BrowserBridge.portPath)
          .readAsStringSync()
          .split(' ');
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        int.parse(port),
      );
      said = token ?? written;
    } else {
      socket = await Socket.connect(
        InternetAddress(
          BrowserBridge.socketPath,
          type: InternetAddressType.unix,
        ),
        0,
      );
    }
    send(socket, {
      'type': 'hello',
      'origin': 'chrome-extension://${BrowserBridge.extensionIds.first}/',
      'token': ?said,
    });
    send(socket, {'type': 'hello', ...hello});
    await socket.flush();
    return socket;
  }

  Future<void> until(bool Function() done) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!done() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('an extension of another protocol is kept apart, and said so', () async {
    await bridge.start();
    final current = await connect({
      'browser': 'Google Chrome',
      'version': '0.1.0',
    });
    addTearDown(current.destroy);
    await until(() => bridge.browsers.isNotEmpty);
    expect(bridge.browsers.single.browser, 'Google Chrome');
    expect(bridge.browsers.single.protocol, BrowserBridge.protocol);

    final newer = await connect({
      'browser': 'Microsoft Edge',
      'version': '9.0.0',
      'protocol': BrowserBridge.protocol + 1,
    });
    addTearDown(newer.destroy);
    await until(() => bridge.mismatched.isNotEmpty);
    expect(bridge.browsers.single.browser, 'Google Chrome');
    expect(bridge.mismatched.single.browser, 'Microsoft Edge');

    final l10n = AppLocalizationsEn();
    expect(BrowserSettingsPage.status(l10n, bridge), [
      (
        l10n.browserSettingsConnected('Google Chrome'),
        l10n.browserSettingsExtensionVersion('0.1.0'),
      ),
      (
        l10n.browserSettingsIncompatible('Microsoft Edge'),
        l10n.browserSettingsAppOld,
      ),
    ]);
  }, skip: Platform.isWindows);

  test('a big answer, in many chunks, is read whole', () async {
    await bridge.start();
    final host = await connect({
      'browser': 'Google Chrome',
      'version': '0.1.0',
    });
    addTearDown(host.destroy);
    final asked = BytesBuilder();
    host.listen(asked.add);
    await until(() => bridge.browsers.isNotEmpty);

    final big = 'x' * (20 << 20);
    final answer = bridge.browsers.single.request('screenshot');
    int length() => asked.length < 4
        ? 1 << 30
        : ByteData.sublistView(asked.toBytes()).getUint32(0, Endian.little);
    await until(() => asked.length >= 4 + length());
    final request = asked.toBytes();
    final {'id': id} = jsonDecode(
      utf8.decode(request.sublist(4, 4 + length())),
    );
    final body = utf8.encode(jsonEncode({'id': id, 'result': big}));
    final message = Uint8List(4 + body.length)
      ..buffer.asByteData().setUint32(0, body.length, Endian.little)
      ..setRange(4, 4 + body.length, body);
    // The header itself split, then the rest as a socket hands it on.
    for (var at = 0; at < message.length; at += at == 0 ? 2 : 64 << 10) {
      final end = at == 0 ? 2 : at + (64 << 10);
      host.add(
        Uint8List.sublistView(message, at, end.clamp(0, message.length)),
      );
    }
    await host.flush();

    expect(await answer, big);
  }, skip: Platform.isWindows);

  test('on Linux, a browser from Snap or Flatpak is said to be kept out', () {
    final l10n = AppLocalizationsEn();
    final sandboxed = (
      l10n.browserSettingsSandboxed,
      l10n.browserSettingsSandboxedDescription,
    );
    expect(bridge.sandboxedBrowsers, isFalse);
    expect(
      BrowserSettingsPage.status(l10n, bridge),
      isNot(contains(sandboxed)),
    );

    Directory(p.join(home.path, 'snap', 'chromium'))
        .createSync(recursive: true);
    expect(bridge.sandboxedBrowsers, isTrue);
    expect(BrowserSettingsPage.status(l10n, bridge), contains(sandboxed));
  }, skip: !Platform.isLinux);

  test('turned off, it lets the browsers go and takes the host away; on, it '
      'listens again', () async {
    await bridge.start();
    final socket = await connect({'browser': 'Google Chrome'});
    addTearDown(socket.destroy);
    await until(() => bridge.browsers.isNotEmpty);
    expect(bridge.used, isTrue);

    var told = 0;
    void listener() => told++;
    bridge.addListener(listener);
    addTearDown(() => bridge.removeListener(listener));

    final settings = ValueNotifier<Object?>(false);
    bridge.follow(settings, () => settings.value);
    expect(bridge.enabled, isFalse);
    expect(told, greaterThan(0));
    expect(bridge.used, isFalse, reason: 'no tools, no side panel page');
    await until(() => bridge.browsers.isEmpty);
    expect(bridge.browsers, isEmpty);
    await until(() => !manifest.existsSync());
    expect(manifest.existsSync(), isFalse);
    expect(File(BrowserBridge.socketPath).existsSync(), isFalse);

    settings.value = null;
    expect(bridge.enabled, isTrue);
    await until(() => File(BrowserBridge.socketPath).existsSync());
    final again = await connect({'browser': 'Google Chrome'});
    addTearDown(again.destroy);
    await until(() => bridge.browsers.isNotEmpty);
    expect(bridge.used, isTrue);
  }, skip: Platform.isWindows);

  group('over loopback (Windows)', () {
    setUp(() {
      final was = BrowserBridge.loopback;
      BrowserBridge.loopback = true;
      addTearDown(() => BrowserBridge.loopback = was);
    });

    test('a host saying the token is let in; the port\'s file goes with '
        'the bridge', () async {
      await bridge.start();
      expect(
        File(BrowserBridge.portPath).readAsStringSync(),
        matches(RegExp(r'^\d+ [0-9a-f]{64}$')),
      );
      final socket = await connect({'browser': 'Microsoft Edge'});
      addTearDown(socket.destroy);
      await until(() => bridge.browsers.isNotEmpty);
      expect(bridge.browsers.single.browser, 'Microsoft Edge');

      await bridge.stop();
      expect(File(BrowserBridge.portPath).existsSync(), isFalse);
      expect(bridge.browsers, isEmpty);
    });

    test('a connection without the token is let go, never listed', () async {
      await bridge.start();
      final wrong = await connect({'browser': 'Google Chrome'}, token: 'abc');
      addTearDown(wrong.destroy);
      final none = await Socket.connect(
        InternetAddress.loopbackIPv4,
        int.parse(
          File(BrowserBridge.portPath).readAsStringSync().split(' ').first,
        ),
      );
      addTearDown(none.destroy);
      send(none, {'type': 'hello', 'browser': 'Google Chrome'});
      await none.flush();

      // Each ends as the bridge lets it go.
      await wrong.drain<void>().timeout(const Duration(seconds: 5));
      await none.drain<void>().timeout(const Duration(seconds: 5));
      expect(bridge.browsers, isEmpty);
      expect(bridge.mismatched, isEmpty);
    });
  });

  test('the Windows manifest names the host beside it, for the extension '
      'alone', () {
    final manifest = jsonDecode(
      File('windows/BrowserBridge/dev.baocode.browser.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(manifest, {
      'name': BrowserBridge.hostName,
      'description': 'BaoCode',
      'path': 'baocode-browser-host.exe',
      'type': 'stdio',
      'allowed_origins': [
        for (final id in BrowserBridge.extensionIds) 'chrome-extension://$id/',
      ],
    });
  });
}
