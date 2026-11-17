@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/remote/remote_browser.dart';
import 'package:baocode/remote/remote_browser_view.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// The remote browser's window: a host's folders, read again at Refresh,
/// the hidden ones shown when asked, one walked into and opened.
void main() {
  late Directory dataDir;
  late Directory home;
  late String root;
  late SshHosts hosts;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('baocode-remote-data-');
    home = Directory.systemTemp.createTempSync('baocode-remote-home-');
    root = home.resolveSymbolicLinksSync();
    hosts = SshHosts(connect: MemoryConnector(dataDir.path).call);
  });
  tearDown(() async {
    await hosts.closeAll();
    dataDir.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  /// Pumps until [finder] finds something, the host's replies let in.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(finder, findsWidgets);
  }

  testWidgets('a folder walked into and opened; read again at Refresh; '
      'the hidden ones shown when asked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Directory(p.join(root, 'app', 'lib')).createSync(recursive: true);
    Directory(p.join(root, '.cache')).createSync();
    final views = <RemoteBrowserView>[];
    final locations = <List<String>>[];
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () async {
                picked = await showRemoteBrowser(
                  context,
                  RemoteBrowseRequest(
                    host: 'dev',
                    directory: root,
                    connect: hosts['dev'].reconnect,
                  ),
                  hostLabel: 'dev',
                  onView: views.add,
                  locations: ['/srv/old'],
                  onLocations: locations.add,
                );
              },
              child: const Text('browse'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('browse'));
    await tester.pump();
    expect(find.text('Open Folder'), findsOneWidget);
    // Folders only, the hidden one left out; the recent one at the left.
    const list = RemoteBrowserDialog.entriesKey;
    await pumpUntil(
      tester,
      find.descendant(of: find.byKey(list), matching: find.text('app')),
    );
    expect(find.text('.cache'), findsNothing);

    // One made in a terminal since: read again at Refresh.
    Directory(p.join(root, 'api')).createSync();
    expect(
      find.descendant(of: find.byKey(list), matching: find.text('api')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Refresh'));
    await pumpUntil(
      tester,
      find.descendant(of: find.byKey(list), matching: find.text('api')),
    );

    // Asked for, the hidden ones; the view kept.
    await tester.tap(find.byTooltip('View Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden Items'));
    await tester.pumpAndSettle();
    expect(find.text('.cache'), findsOneWidget);
    expect(views.single.hidden, isTrue);

    // Double-clicked, walked into; Open takes where it is.
    final app = find.descendant(
      of: find.byKey(list),
      matching: find.text('app'),
    );
    await tester.tap(app);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(app);
    await pumpUntil(tester, find.text('lib'));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(picked, p.join(root, 'app'));
    // What was picked, the latest of the recent locations.
    expect(locations.single, [p.join(root, 'app'), '/srv/old']);
  });

  testWidgets('saving: a folder by the name walked into; a file there '
      'written over once agreed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Directory(p.join(root, 'src')).createSync();
    File(p.join(root, 'notes.md')).writeAsStringSync('');
    String? picked;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () async {
                picked = await showRemoteBrowser(
                  context,
                  RemoteBrowseRequest(
                    host: 'dev',
                    saveName: 'Untitled-1',
                    directory: root,
                    connect: hosts['dev'].reconnect,
                  ),
                  hostLabel: 'dev',
                );
                closed = true;
              },
              child: const Text('save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pump();
    const list = RemoteBrowserDialog.entriesKey;
    await pumpUntil(
      tester,
      find.descendant(of: find.byKey(list), matching: find.text('notes.md')),
    );
    expect(find.text('Save As:'), findsOneWidget);
    expect(find.text('Untitled-1'), findsOneWidget);

    // The name of a folder there: walked into, the name as offered again.
    await tester.enterText(find.text('Untitled-1'), 'src');
    await tester.tap(find.text('Save'));
    await pumpUntil(tester, find.text('This folder is empty.'));
    expect(find.text('Untitled-1'), findsOneWidget);
    expect(closed, isFalse);
    await tester.tap(find.byTooltip('Back'));
    await pumpUntil(
      tester,
      find.descendant(of: find.byKey(list), matching: find.text('notes.md')),
    );

    // A file clicked: its name; saved over once Replace is chosen.
    await tester.tap(
      find.descendant(of: find.byKey(list), matching: find.text('notes.md')),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('“notes.md” already exists. Replace it?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked, p.join(root, 'notes.md'));
  });
}
