// JetBrains IDEs' Local History, as far as saves go: each file's text
// before a save and as saved, kept apart from Git; looked at from the
// explorer, a version picked opens against the file.

import 'package:baocode/ide/ide_local_history.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workbench/fake_files.dart';

void main() {
  test('a text kept once; the oldest dropped past the limits', () async {
    var now = DateTime(2026, 10, 1, 12);
    final history = IdeLocalHistory(
      IdeMemoryLocalHistoryStore(),
      versions: 3,
      now: () => now,
    );
    for (final text in ['a', 'a', 'b', 'c', 'd']) {
      await history.record('/p/x.txt', text);
      now = now.add(const Duration(minutes: 1));
    }
    final versions = await history.versionsOf('/p/x.txt');
    expect([for (final v in versions) await history.read(v)], ['d', 'c', 'b']);
    expect(await history.versionsOf('/p/y.txt'), isEmpty);

    // A week on, those kept before are gone.
    now = now.add(const Duration(days: 8));
    await history.record('/p/x.txt', 'e');
    expect(await history.versionsOf('/p/x.txt'), hasLength(1));
  });

  test("kept in the data folder's files", () async {
    final history = IdeLocalHistory.inDataDirectory()!;
    final path = '/p/${DateTime.now().microsecondsSinceEpoch}.txt';
    await history.record(path, 'kept\n');
    final versions = await history.versionsOf(path);
    expect(await history.read(versions.single), 'kept\n');
  });

  testWidgets('saved, then a version picked from the explorer opens against '
      'the file', (tester) async {
    final workspace = await pumpWorkbench(tester, const {'a.txt': 'one\n'});
    workspace.localHistory = IdeLocalHistory(IdeMemoryLocalHistoryStore());
    await tester.pumpAndSettle();
    await workspace.open(inRoot('a.txt'));
    workspace.edit(inRoot('a.txt'), 'two\n');
    await workspace.save(workspace.active!);
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.text('a.txt').first),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Local History'));
    await tester.pumpAndSettle();
    // Before the save and as saved: the latest first.
    final versions = find.textContaining(RegExp(r'^\d{4}-\d\d-\d\d '));
    expect(versions, findsNWidgets(2));
    await tester.tap(versions.last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('a.txt (Local History,', findRichText: true),
      findsWidgets,
    );
  });
}
