@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/data_dir_service.dart';
import 'package:baocode/settings/data_dir_startup.dart';
import 'package:path/path.dart' as p;

/// A data folder that cannot be used is reported before the app shows,
/// and the user decides; the old folder's data is removed only when they
/// say so. Every folder is a temporary one; no picker opens.
void main() {
  late Directory root;
  late String home;
  late String pointerFile;

  setUp(() {
    root = Directory.systemTemp.createTempSync('baocode-startup');
    home = p.join(root.path, 'home');
    pointerFile = DataDirectoryPointer.fileIn(home);
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Pumps, letting real file work finish, until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  DataDirectoryResolution missing({
    DataDirectorySource source = DataDirectorySource.pointer,
  }) => DataDirectoryResolution(
    path: p.join(root.path, 'Volumes', 'D', 'BaoCode'),
    source: source,
    defaultPath: p.join(root.path, 'default'),
    pointerFile: pointerFile,
    problem: DataDirectoryProblem.missing,
    error: 'The folder is not there.',
  );

  group('a data folder that cannot be used', () {
    testWidgets('Retry goes on once it is back', (tester) async {
      final resolved = <DataDirectory>[];
      final attempts = [
        missing(),
        DataDirectoryResolution(
          path: '/back',
          source: DataDirectorySource.pointer,
          defaultPath: '/default',
          pointerFile: pointerFile,
        ),
      ];
      await tester.pumpWidget(
        DataDirectoryRecoveryApp(
          problem: missing(),
          onResolved: resolved.add,
          resolve: () => attempts.removeAt(0),
          pickDirectory: () async => fail('no picker'),
        ),
      );
      expect(
        find.text("BaoCode's data folder is not available"),
        findsOneWidget,
      );
      expect(find.text(missing().path), findsOneWidget);
      expect(find.textContaining(pointerFile), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(resolved, isEmpty);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(resolved, [
        const DataDirectory('/back', source: DataDirectorySource.pointer),
      ]);
    });

    testWidgets('the default folder, this time only: the pointer stays', (
      tester,
    ) async {
      File(pointerFile)
        ..createSync(recursive: true)
        ..writeAsStringSync('{"dataDir": "${missing().path}"}');
      final resolved = <DataDirectory>[];
      await tester.pumpWidget(
        DataDirectoryRecoveryApp(problem: missing(), onResolved: resolved.add),
      );
      await tester.tap(find.text('Use the Default Folder This Time'));
      await tester.pump();
      expect(resolved, [
        DataDirectory(
          p.join(root.path, 'default'),
          source: DataDirectorySource.temporaryDefault,
        ),
      ]);
      expect(
        File(pointerFile).readAsStringSync(),
        '{"dataDir": "${missing().path}"}',
      );
    });

    testWidgets('another folder is checked, then written to the pointer', (
      tester,
    ) async {
      File(pointerFile)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'dataDir': missing().path, 'previousDataDir': '/old'}),
        );
      final chosen = Directory(p.join(root.path, 'E', 'BaoCode'))
        ..createSync(recursive: true);
      final picks = [p.join(root.path, 'nowhere'), chosen.path];
      final resolved = <DataDirectory>[];
      await tester.pumpWidget(
        DataDirectoryRecoveryApp(
          problem: missing(),
          onResolved: resolved.add,
          pickDirectory: () async => picks.removeAt(0),
        ),
      );

      await tester.tap(find.text('Choose Another Folder…'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('nowhere is not there'), findsOneWidget);
      expect(resolved, isEmpty);

      await tester.tap(find.text('Choose Another Folder…'));
      await settle(tester, () => resolved.isNotEmpty);
      expect(resolved, [
        DataDirectory(chosen.path, source: DataDirectorySource.pointer),
      ]);
      expect(jsonDecode(File(pointerFile).readAsStringSync()), {
        'dataDir': chosen.path,
        'previousDataDir': '/old',
      });
    });

    testWidgets('an invalid pointer is named; a folder set by the variable '
        'is not chosen here', (tester) async {
      await tester.pumpWidget(
        DataDirectoryRecoveryApp(
          problem: DataDirectoryResolution(
            path: '/default',
            source: DataDirectorySource.pointer,
            defaultPath: '/default',
            pointerFile: pointerFile,
            problem: DataDirectoryProblem.invalidPointer,
            error: '$pointerFile is not JSON',
          ),
          onResolved: (_) {},
        ),
      );
      expect(
        find.text("BaoCode's data folder setting cannot be read"),
        findsOneWidget,
      );
      expect(find.textContaining('Fix or delete'), findsOneWidget);

      await tester.pumpWidget(
        DataDirectoryRecoveryApp(
          problem: missing(source: DataDirectorySource.environment),
          onResolved: (_) {},
        ),
      );
      expect(find.textContaining('BAOCODE_DATA_DIR'), findsOneWidget);
      expect(find.text('Choose Another Folder…'), findsNothing);
    });
  });

  group('the old folder, after a move', () {
    late String old;
    late String current;

    setUp(() {
      old = p.join(root.path, 'old');
      current = p.join(root.path, 'current');
      for (final path in [
        'User/settings.json',
        'state/state.json',
        'argv.json',
        'Cookies',
        'GPUCache/data_0',
      ]) {
        File(p.join(old, path))
          ..createSync(recursive: true)
          ..writeAsStringSync('');
      }
      Directory(current).createSync();
      File(pointerFile)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'dataDir': current, 'previousDataDir': old}),
        );
    });

    DataDirectoryService service() => DataDirectoryService(
      current: DataDirectory(current, source: DataDirectorySource.pointer),
      environment: {'HOME': home},
      home: home,
    );

    Future<void> ask(WidgetTester tester, {required String answer}) async {
      var asked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => offerOldDataDirRemoval(
                context,
                service: service(),
              ).whenComplete(() => asked = true),
              child: const Text('start'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pump();
      expect(
        find.text('Remove the data BaoCode left in its previous folder?'),
        findsOneWidget,
      );
      expect(find.textContaining('User, argv.json, state'), findsOneWidget);
      await tester.tap(find.text(answer));
      await settle(tester, () => asked);
    }

    List<String> left() =>
        [for (final e in Directory(old).listSync()) p.basename(e.path)]..sort();

    testWidgets('Remove takes only the app\'s entries', (tester) async {
      await ask(tester, answer: 'Remove');
      expect(left(), ['Cookies', 'GPUCache']);
      expect(jsonDecode(File(pointerFile).readAsStringSync()), {
        'dataDir': current,
      });
    });

    testWidgets('Keep leaves them, and does not ask again', (tester) async {
      await ask(tester, answer: 'Keep');
      expect(left(), ['Cookies', 'GPUCache', 'User', 'argv.json', 'state']);
      expect(service().previousDirectory, isNull);
    });

    testWidgets('Later asks again next time', (tester) async {
      await ask(tester, answer: 'Later');
      expect(service().previousDirectory, old);
    });
  });
}
