import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_editor_placeholder.dart';
import 'package:baocode/theme/codicons.dart';

import 'fake_files.dart';

void main() {
  testWidgets('a binary file opens as VS Code\'s placeholder, then anyway', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'app.bin': 'MZ\x00\x01', 'a.txt': 'a'},
      open: ['app.bin'],
    );
    // A tab like any other, and no error banner: the editor says why.
    expect(workspace.active!.openError, isA<IdeBinaryFileException>());
    expect(find.text('app.bin'), findsWidgets);
    expect(
      find.text(
        'The file is not displayed in the text editor because it is either '
        'binary or uses an unsupported text encoding.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Codicons.warning), findsOneWidget);
    expect(find.byType(IdeEditor), findsNothing);

    await tester.tap(find.text('Open Anyway'));
    await tester.pumpAndSettle();
    expect(workspace.active!.openError, isNull);
    expect(workspace.active!.text, 'MZ\x00\x01');
    expect(workspace.documents, hasLength(1));
    expect(find.byType(IdeEditorPlaceholder), findsNothing);
    expect(find.byType(IdeEditor), findsOneWidget);
  });

  testWidgets('a missing file offers to try again', (tester) async {
    final workspace = await pumpWorkbench(tester, {'a.txt': 'a'});
    await workspace.open(inRoot('gone.txt'));
    await tester.pump();
    expect(
      find.text(
        'The editor could not be opened because the file was not found.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Codicons.error), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    // Nothing to save or sync.
    await workspace.save(workspace.active!);
  });

  test('sizes are written as VS Code writes them', () {
    expect(ideFormatSize(512), '512B');
    expect(ideFormatSize(133734), '130.60KB');
    expect(ideFormatSize(6 * 1024 * 1024), '6.00MB');
  });
}
