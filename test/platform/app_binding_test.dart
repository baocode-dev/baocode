import 'package:baocode/platform/app_binding.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what reaches the engine, answering each with [answer].
class _Engine extends BinaryMessenger {
  final List<String> methods = [];
  Object? answer = true;

  static const _codec = JSONMethodCodec();

  @override
  Future<ByteData?>? send(String channel, ByteData? message) async {
    methods.add(_codec.decodeMethodCall(message).method);
    return _codec.encodeSuccessEnvelope(answer);
  }

  @override
  // ignore: deprecated_member_use
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Object?> ask(BinaryMessenger messenger, String method) async {
    const codec = JSONMethodCodec();
    final reply = await messenger.send(
      SystemChannels.platform.name,
      codec.encodeMethodCall(MethodCall(method)),
    );
    return codec.decodeEnvelope(reply!);
  }

  test("a text field's Paste is asked of the window, not the engine", () async {
    final engine = _Engine();
    var asked = 0;
    final messenger = ClipboardProbeMessenger(
      engine,
      hasText: () async {
        asked++;
        return true;
      },
    );
    expect(await ask(messenger, 'Clipboard.hasStrings'), {'value': true});
    expect(asked, 1);
    expect(engine.methods, isEmpty);
  });

  test('the rest of the platform channel reaches the engine', () async {
    final engine = _Engine();
    final messenger = ClipboardProbeMessenger(
      engine,
      hasText: () async => fail('not the clipboard'),
    );
    await ask(messenger, 'Clipboard.getData');
    await ask(messenger, 'HapticFeedback.vibrate');
    expect(engine.methods, ['Clipboard.getData', 'HapticFeedback.vibrate']);
  });

  test('without the window the engine answers', () async {
    final engine = _Engine()..answer = {'value': false};
    final messenger = ClipboardProbeMessenger(
      engine,
      hasText: () async => throw MissingPluginException(),
    );
    expect(await ask(messenger, 'Clipboard.hasStrings'), {'value': false});
    expect(engine.methods, ['Clipboard.hasStrings']);
  });
}
