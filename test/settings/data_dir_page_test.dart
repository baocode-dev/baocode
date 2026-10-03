import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_button.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/data_dir_service.dart';
import 'package:baocode/settings/pages/data_dir_page.dart';

/// Moves as the page asks for them: nothing is copied, no file touched.
class _FakeService extends DataDirectoryService {
  _FakeService({
    DataDirectorySource source = DataDirectorySource.pointer,
    super.environment = const {'HOME': '/home/me'},
    this.targets = const {},
  }) : super(
         current: DataDirectory('/data/baocode', source: source),
         home: '/home/me',
       );

  final Map<String, DataDirectoryTarget> targets;
  final List<String> migrated = [];
  final List<String> usedAsIs = [];
  final List<String> checked = [];
  String? pending;

  @override
  String? get pendingPath => pending;

  @override
  Future<DataDirectoryTarget> check(String path, {bool create = false}) async {
    checked.add('$path${create ? ' (made)' : ''}');
    return targets[path] ??
        DataDirectoryTarget(path, contents: DataDirectoryContents.empty);
  }

  @override
  Future<void> migrate(
    String target, {
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(0, 2);
    onProgress?.call(2, 2);
    migrated.add(target);
    pending = target;
  }

  @override
  Future<void> useAsIs(String target) async {
    usedAsIs.add(target);
    pending = target;
  }
}

void main() {
  Future<({List<String> revealed, List<String> quits})> pumpPage(
    WidgetTester tester,
    _FakeService service, {
    List<String?> picks = const [],
  }) async {
    final revealed = <String>[];
    final quits = <String>[];
    final pending = [...picks];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DataDirectoryPage(
            service: service,
            pickDirectory: () async => pending.removeAt(0),
            reveal: (path) async => revealed.add(path),
            quit: () async => quits.add('quit'),
          ),
        ),
      ),
    );
    return (revealed: revealed, quits: quits);
  }

  IdeButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(IdeButton)),
  );

  testWidgets('shows the folder and where it was set; reveals it', (
    tester,
  ) async {
    final (:revealed, quits: _) = await pumpPage(tester, _FakeService());
    expect(find.text('/data/baocode'), findsOneWidget);
    expect(
      find.text('Set in /home/me/.baocode/config-dir.json.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reveal in Finder'));
    expect(revealed, ['/data/baocode']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Change shows the folder picked; Save copies the data there, '
      'then offers to quit', (tester) async {
    final service = _FakeService();
    final (revealed: _, :quits) = await pumpPage(
      tester,
      service,
      picks: ['/Volumes/D/BaoCode'],
    );
    await tester.tap(find.text('Change…'));
    await tester.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('/Volumes/D/BaoCode'), findsOneWidget);
    expect(find.text('Change…'), findsNothing);
    expect(service.migrated, isEmpty);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.migrated, ['/Volumes/D/BaoCode']);
    expect(
      find.text('Restart BaoCode to use the new data folder'),
      findsOneWidget,
    );
    await tester.tap(find.text('Quit Now').last);
    await tester.pumpAndSettle();
    expect(quits, ['quit']);
    expect(find.text('After a restart: /Volumes/D/BaoCode'), findsOneWidget);
  });

  testWidgets('on Windows, Quit Now quits as the tray icon\'s Quit does '
      '(the close button hides the window to it)', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('baocode/attention'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DataDirectoryPage(
            service: _FakeService()..pending = '/Volumes/D/BaoCode',
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Quit Now'));
    await tester.pump();
    await tester.tap(find.text('Quit Now'));
    await tester.pump();
    expect(calls.map((call) => call.method), ['quit']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a folder with BaoCode data is used as it is; Later keeps '
      'running', (tester) async {
    final service = _FakeService(
      targets: {
        '/other': const DataDirectoryTarget(
          '/other',
          contents: DataDirectoryContents.baocodeData,
        ),
      },
    );
    final (revealed: _, :quits) = await pumpPage(
      tester,
      service,
      picks: ['/other'],
    );
    await tester.tap(find.text('Change…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('uses the data there as it is'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.usedAsIs, ['/other']);
    expect(service.migrated, isEmpty);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(quits, isEmpty);
  });

  testWidgets('a folder that cannot be used says why; Cancel changes '
      'nothing', (tester) async {
    final service = _FakeService(
      targets: {
        '/data': const DataDirectoryTarget(
          '/data',
          error: 'The new folder cannot contain the one in use.',
        ),
      },
    );
    await pumpPage(tester, service, picks: ['/data', '/empty', null]);
    await tester.tap(find.text('Change…'));
    await tester.pumpAndSettle();
    expect(
      find.text('The new folder cannot contain the one in use.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Change…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('/data/baocode'), findsOneWidget);
    expect(find.text('/empty'), findsNothing);
    // A picker closed without a folder.
    await tester.tap(find.text('Change…'));
    await tester.pumpAndSettle();
    expect(service.migrated, isEmpty);
    expect(service.checked, ['/data', '/empty']);
  });

  testWidgets('Reset to Default moves the data back, the folder made', (
    tester,
  ) async {
    final service = _FakeService();
    await pumpPage(tester, service);
    await tester.tap(find.text('Reset to Default'));
    await tester.pumpAndSettle();
    expect(find.text(service.defaultPath), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.checked, ['${service.defaultPath} (made)']);
    expect(service.migrated, [service.defaultPath]);
  });

  testWidgets('set by BAOCODE_DATA_DIR: nothing to change here', (
    tester,
  ) async {
    await pumpPage(
      tester,
      _FakeService(
        source: DataDirectorySource.environment,
        environment: const {'HOME': '/home/me', 'BAOCODE_DATA_DIR': '/env'},
      ),
    );
    expect(button(tester, 'Change…').onPressed, isNull);
    expect(button(tester, 'Reset to Default').onPressed, isNull);
    expect(
      find.text('Set by the BAOCODE_DATA_DIR environment variable.'),
      findsOneWidget,
    );
  });
}
