// The baocode:// URL protocol (goal 五.8: OAuth callbacks to the
// extensions' URI handlers), from the system to the extension: what the
// window hands Flutter over `baocode/open` reaches the handler, and the
// native ends (Info.plist, AppDelegate.swift, the Windows runner and
// installer), which no test here can run, agree with what Flutter reads.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/window/url_service.dart';
import 'package:baocode/platform/open_requests.dart';
import 'package:baocode/window/code_args.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'window/fakes.dart';

const _open = MethodChannel('baocode/open');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    OpenRequests.onUri = null;
    OpenRequests.stop();
    messenger.setMockMethodCallHandler(_open, null);
  });

  test('a URI the system opens reaches the extension, kept from launch and '
      'as it comes', () async {
    var pending = <Object?>[
      CodeArgs.uriRequestMarker,
      'baocode://vscode.github-authentication/did-authenticate?code=1',
    ];
    messenger.setMockMethodCallHandler(_open, (call) async {
      if (call.method != 'takePending') return null;
      final taken = pending;
      pending = [];
      return taken;
    });
    final urls = ExtensionUrlService();
    final host = FakeUrlHost('ws-1');
    urls.addHost(host);
    final handled = <String>[];
    urls.registerExtensionHandler(
      host,
      'vscode.github-authentication',
      'GitHub Authentication',
      (uri) async => handled.add('${uri.path}?${uri.query}'),
    );
    OpenRequests.onUri = urls.handleOpenRequest;
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(handled, ['/did-authenticate?code=1']);

    await messenger.handlePlatformMessage(
      _open.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('open', [
          CodeArgs.uriRequestMarker,
          'baocode://vscode.github-authentication/did-authenticate?code=2',
        ]),
      ),
      (_) {},
    );
    await pumpEventQueue();
    expect(handled, ['/did-authenticate?code=1', '/did-authenticate?code=2']);
    expect(opened, isEmpty);
    expect(ExtensionUrlService.requestMarker, CodeArgs.uriRequestMarker);
    expect(VsUri.parse('baocode://a.b/c').scheme, urls.scheme);
  });

  test(
    'macOS registers the scheme and hands its URIs over with the marker',
    () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      expect(
        RegExp(
          r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>baocode</string>',
        ).hasMatch(plist),
        isTrue,
      );
      final delegate = File('macos/Runner/AppDelegate.swift')
          .readAsStringSync();
      expect(delegate, contains(r'static let uriMarker = "\u{0}uri"'));
      expect(CodeArgs.uriRequestMarker, '\u0000uri');
    },
  );

  test('the Windows installer registers the scheme with the flag the runner '
      'reads', () {
    final installer = File('tool/baocode.iss').readAsStringSync();
    expect(installer, contains(r'Subkey: "Software\Classes\baocode";'));
    expect(installer, contains('ValueName: "URL Protocol"'));
    expect(
      installer,
      contains('"""{app}\\baocode.exe"" ${CodeArgs.windowsUrlFlag} -- ""%1"""'),
    );
    final header = File('windows/runner/open_requests.h').readAsStringSync();
    expect(
      header,
      contains('kUrlRequestFlag[] = "${CodeArgs.windowsUrlFlag}"'),
    );
    final runner = File('windows/runner/open_requests.cpp').readAsStringSync();
    expect(runner, contains(r'marker("\0uri", 4)'));
  });
}
