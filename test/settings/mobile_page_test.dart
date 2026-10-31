import 'package:bao_link/bao_link.dart';
import 'package:baocode/link/link_host.dart';
import 'package:baocode/link/qr_view.dart';
import 'package:baocode/settings/pages/mobile_page.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../link/fake_link_platform.dart';

void main() {
  testWidgets('shows a code to pair with, then the safety code to compare', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = FakeLinkPlatform();
    final host = LinkHost(workspace: Workspace.mock(), platform: platform);
    addTearDown(host.dispose);
    await host.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileSettingsPage(host: host)),
      ),
    );
    await tester.pump();
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.text('Show QR Code'));
    await tester.pump();
    await tester.pump();
    expect(host.enabled, isTrue);
    expect(find.byType(QrView), findsOneWidget);
    expect(
      find.text('On, reachable through relay-us1.baocode.dev'),
      findsOneWidget,
    );

    // A phone scans it.
    final phone = LinkIdentity.generate();
    final offer = host.offer!;
    var answered = false;
    () async {
      final connection = await platform.phone(phone).connect(offer.address);
      final peer = await LinkPeer.connect(connection);
      await peer.call(LinkMethods.hello, {
        'name': 'iPhone',
        'token': encodeKey(offer.token),
      });
      answered = true;
    }();
    for (var i = 0; i < 20 && !answered; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(answered, isTrue);
    final code = safetyCode(offer.key, phone.publicKey);
    expect(find.text('Compare with iPhone'), findsOneWidget);
    expect(find.text(code.join('  ')), findsOneWidget);

    await tester.tap(find.text("Codes Don't Match"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(host.pending, isNull);
    expect(find.byType(QrView), findsNothing);
    // The phone let go, once told.
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a phone that found it nearby is allowed here', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = FakeLinkPlatform();
    final host = LinkHost(workspace: Workspace.mock(), platform: platform);
    addTearDown(host.dispose);
    await host.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileSettingsPage(host: host)),
      ),
    );
    await tester.pump();
    expect(find.text('Find on the Local Network'), findsOneWidget);
    await tester.tap(find.text('Show QR Code'));
    await tester.pump();
    await tester.pump();

    final phone = LinkIdentity.generate();
    final key = host.offer!.key;
    final address = host.offer!.address;
    Object? confirmed;
    () async {
      final connection = await platform.phone(phone).connect(address);
      final peer = await LinkPeer.connect(connection);
      await peer.call(LinkMethods.hello, {'name': 'Pixel', 'request': true});
      confirmed = await peer.call(LinkMethods.confirm);
    }();
    for (var i = 0; i < 20 && host.pending?.needsApproval != true; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
    expect(find.text('Pixel Wants to Pair'), findsOneWidget);
    expect(
      find.text(safetyCode(key, phone.publicKey).join('  ')),
      findsOneWidget,
    );
    await tester.tap(find.text('Allow'));
    for (var i = 0; i < 20 && confirmed == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(confirmed, isA<Map>());
    expect(host.phones.single.name, 'Pixel');
    await tester.pump();
    expect(find.text('Paired with Pixel.'), findsOneWidget);
    // The path is counted once it has settled.
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('phones paired before the rebuild are shown to pair again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = FakeLinkPlatform()
      ..kept = {
        'version': 1,
        'identity': {'privateKey': 'AAAA', 'publicKey': 'AAAA'},
        'phones': [
          {'key': 'AAAA', 'name': 'Old iPhone', 'system': 'iOS 18'},
        ],
      };
    final host = LinkHost(workspace: Workspace.mock(), platform: platform);
    addTearDown(host.dispose);
    await host.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileSettingsPage(host: host)),
      ),
    );
    await tester.pump();
    expect(find.text('Old iPhone'), findsOneWidget);
    expect(find.textContaining('Needs pairing again'), findsOneWidget);
    await tester.tap(find.text('Pair Again'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(QrView), findsOneWidget);
    host.endPairing();
    await tester.pump();

    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(find.text('Old iPhone'), findsNothing);
    expect(find.text('No phone is paired yet.'), findsOneWidget);
  });

  testWidgets('the relays folded; open, how they are chosen: automatic, '
      'one\'s own added and removed, or one picked', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = FakeLinkPlatform();
    final host = LinkHost(workspace: Workspace.mock(), platform: platform);
    addTearDown(host.dispose);
    await host.load();
    await host.setEnabled(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MobileSettingsPage(host: host)),
      ),
    );
    await tester.pump();
    final us1 = Uri.parse(defaultLinkRelays.first).host;
    final hk1 = Uri.parse(defaultLinkRelays[1]).host;
    // Folded: only how they are chosen.
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text(hk1), findsNothing);

    await tester.tap(find.text('Relays'));
    await tester.pump();
    for (final url in defaultLinkRelays) {
      expect(find.text(Uri.parse(url).host), findsOneWidget);
    }
    expect(find.text("BaoCode's"), findsNWidgets(defaultLinkRelays.length));
    expect(find.text('In use'), findsOneWidget);
    // Automatic: none to add, remove or pick.
    expect(find.text('Add'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.text('Use This One'), findsNothing);

    Future<void> choose(String mode, String now) async {
      await tester.tap(find.text(now));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode).last);
      await tester.pumpAndSettle();
    }

    Future<void> typeIn(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    await choose('Add Your Own', 'Automatic');
    expect(host.relayMode, LinkRelayMode.added);
    // Not an address, or one listed already: said so, nothing added.
    await tester.tap(find.text('Add'));
    await tester.pump();
    await typeIn('not an address');
    expect(find.textContaining('Not a relay address'), findsOneWidget);
    await typeIn(us1);
    expect(find.text('Already in the list'), findsOneWidget);
    expect(host.customRelays, isEmpty);

    // Escape: the field gone, nothing added.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'relay.example.com');
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump();
    expect(host.customRelays, ['https://relay.example.com']);
    expect(host.relays, contains('https://relay.example.com'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('relay.example.com'), findsOneWidget);
    expect(find.text('Your own'), findsOneWidget);

    // Picking one: the one in use picked; another picked by its button.
    await choose('Pick One', 'Add Your Own');
    expect(host.relays, [defaultLinkRelays.first]);
    expect(find.text('Picked'), findsOneWidget);
    expect(find.text('Use This One'), findsNWidgets(3));
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text(hk1),
          matching: find.byType(SettingsRow),
        ),
        matching: find.text('Use This One'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(host.relays, [defaultLinkRelays[1]]);
    // Folded again: the one picked beside how.
    await tester.tap(find.text('Relays'));
    await tester.pump();
    expect(find.text('Pick One · $hk1'), findsOneWidget);
    await tester.tap(find.text('Relays'));
    await tester.pump();

    // One's own removed: gone from the list.
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump();
    expect(host.customRelays, isEmpty);
    expect(find.text('relay.example.com'), findsNothing);
    expect(host.relays, [defaultLinkRelays[1]]);
  });
}
