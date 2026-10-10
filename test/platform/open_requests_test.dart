import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/open_requests.dart';
import 'package:baocode/window/code_args.dart';

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
    OpenRequests.onUri = null;
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

  test('requests of the `code` command go each as they came, after the '
      'paths kept', () async {
    const marker = OpenRequests.codeRequestMarker;
    pending = [
      r'C:\notes.md',
      marker,
      r'C:\work',
      '-n',
      '.',
      marker,
      r'C:\other',
    ];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [r'C:\notes.md'],
      [marker, r'C:\work', '-n', '.'],
      [marker, r'C:\other'],
    ]);

    await send([marker, r'C:\work', '-g', 'a.dart:3']);
    expect(opened.last, [marker, r'C:\work', '-g', 'a.dart:3']);
  });

  test('Open with BaoCode goes as a request of its own, beside those of '
      'the `code` command', () async {
    const code = OpenRequests.codeRequestMarker;
    const agent = CodeArgs.agentRequestMarker;
    pending = [agent, r'C:\work\a.dart', code, r'C:\work', '.', agent, r'C:\x'];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [agent, r'C:\work\a.dart'],
      [code, r'C:\work', '.'],
      [agent, r'C:\x'],
    ]);
  });

  test("an extension's URI goes to the URI receiver, not the listener",
      () async {
    const uri = CodeArgs.uriRequestMarker;
    const agent = CodeArgs.agentRequestMarker;
    pending = [uri, 'baocode://a.b/cb?code=1', agent, r'C:\x'];
    final opened = <List<String>>[];
    final uris = <List<String>>[];
    OpenRequests.onUri = uris.add;
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(uris, [
      [uri, 'baocode://a.b/cb?code=1'],
    ]);
    expect(opened, [
      [agent, r'C:\x'],
    ]);

    await send([uri, 'baocode://a.b/again']);
    expect(uris.last, [uri, 'baocode://a.b/again']);
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
    expect(await OpenRequests.launchRequest(), LaunchRequest.none);
  });

  test('what the macOS app was launched for, as the window says (Finder\'s '
      'Open with BaoCode, an agent; anything else, the IDE)', () async {
    for (final (answer, request) in [
      ('agent', LaunchRequest.agent),
      ('ide', LaunchRequest.ide),
      (null, LaunchRequest.none),
    ]) {
      messenger.setMockMethodCallHandler(_open, (call) async {
        calls.add(call.method);
        return answer;
      });
      expect(await OpenRequests.launchRequest(), request);
    }
    expect(calls, everyElement('launchRequest'));
  });
}
