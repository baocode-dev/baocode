import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/window_controls.dart';

const _window = MethodChannel('baocode/window');

/// The native open and save panels the IDE asks for, and the macOS File
/// menu it names and fills: what goes to the window, and what comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  Object? answer;

  setUp(() {
    calls = [];
    answer = null;
    messenger.setMockMethodCallHandler(_window, (call) async {
      calls.add(call);
      return answer;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(_window, null);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    group(platform.name, () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test('open panel: the folder and how many, the paths chosen', () async {
        answer = ['/a/one.dart', '/a/two.dart'];
        final paths = await WindowControls.pickOpenFiles(directory: '/a');
        expect(paths, ['/a/one.dart', '/a/two.dart']);
        expect(calls.single.method, 'pickOpenFiles');
        expect(calls.single.arguments, {'directory': '/a', 'multiple': true});

        answer = null;
        expect(await WindowControls.pickOpenFiles(multiple: false), isEmpty);
        expect(calls.last.arguments, {'multiple': false});
      });

      test('save panel: the folder and name, the path chosen', () async {
        answer = '/a/new.txt';
        final path = await WindowControls.pickSaveFile(
          directory: '/a',
          name: 'Untitled-1.txt',
        );
        expect(path, '/a/new.txt');
        expect(calls.single.method, 'pickSaveFile');
        expect(calls.single.arguments, {
          'directory': '/a',
          'name': 'Untitled-1.txt',
        });

        answer = null;
        expect(await WindowControls.pickSaveFile(), isNull);
        expect(calls.last.arguments, isEmpty);
      });

      test('no host for the channel: nothing chosen', () async {
        messenger.setMockMethodCallHandler(_window, null);
        expect(await WindowControls.pickOpenFiles(), isEmpty);
        expect(await WindowControls.pickSaveFile(), isNull);
      });
    });
  }

  test('the File menu is the macOS menu bar\'s', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await WindowControls.setFileMenuTitles({'file': 'Datei'});
    await WindowControls.setRecentItems(['/a', '/b']);
    expect(calls.map((call) => call.method), [
      'setFileMenuTitles',
      'setRecentItems',
    ]);
    expect(calls.first.arguments, {'file': 'Datei'});
    expect(calls.last.arguments, ['/a', '/b']);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await WindowControls.setFileMenuTitles({'file': 'Datei'});
    await WindowControls.setRecentItems(['/a']);
    expect(calls, hasLength(2));
  });

  test('no panels where there is no window (the web, others)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(await WindowControls.pickOpenFiles(), isEmpty);
    expect(await WindowControls.pickSaveFile(), isNull);
    expect(calls, isEmpty);
  });
}
