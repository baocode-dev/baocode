import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/open_requests.dart';

const _open = MethodChannel('baocode/open');

/// What the system asks the app to open comes to the one listener: first
/// what the window kept, then each as the window sends it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<Object?> pending;

  setUp(() {
    calls = [];
    pending = [];
    messenger.setMockMethodCallHandler(_open, (call) async {
      calls.add(call.method);
      if (call.method == 'takePending') {
        final taken = pending;
        pending = [];
        return taken;
      }
      return null;
    });
  });
  tearDown(() {
    OpenRequests.stop();
    messenger.setMockMethodCallHandler(_open, null);
  });

  /// The window sending [paths], as it does once the app is ready.
  Future<void> send(Object? paths) async {
    await messenger.handlePlatformMessage(
      _open.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('open', paths)),
      (_) {},
    );
  }

  test('takes what came before it listened, then what comes', () async {
    pending = ['/Users/me/project', '/Users/me/notes.md'];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(calls, ['takePending']);
    expect(opened, [
      ['/Users/me/project', '/Users/me/notes.md'],
    ]);

    await send([r'C:\work\app', r'\\server\share\file.txt']);
    expect(opened.last, [r'C:\work\app', r'\\server\share\file.txt']);
  });

  test('nothing kept, nothing delivered', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, isEmpty);
  });

  test('passes over what is not an absolute path', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    await send(['relative/file', '', 42, '/abs/file']);
    expect(opened, [
      ['/abs/file'],
    ]);
    await send(['relative']);
    await send('not a list');
    expect(opened, hasLength(1));
  });

  test('stopped, it delivers nothing and tells the window', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    OpenRequests.stop();
    await pumpEventQueue();
    expect(calls, ['takePending', 'stop']);
    await send(['/abs/file']);
    expect(opened, isEmpty);
  });

  test('a host without the channel is no error', () async {
    messenger.setMockMethodCallHandler(_open, null);
    OpenRequests.listen((_) => fail('nothing to open'));
    await pumpEventQueue();
  });
}
