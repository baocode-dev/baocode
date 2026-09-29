import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/theme_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const assets = MonacoThemeAssets();

  test('loads pinned built-in Monaco dark and light token colors', () async {
    final dark = await assets.load('vs-dark');
    expect(dark.background, const Color(0xff1e1e1e));
    expect(dark.foreground, const Color(0xffd4d4d4));
    expect(dark.styleForToken('keyword.dart').color, const Color(0xff569cd6));
    expect(dark.styleForToken('comment.dart').color, const Color(0xff608b4e));

    final light = await assets.load('vs');
    expect(light.styleForToken('keyword.dart').color, const Color(0xff0000ff));
    expect(light.styleForToken('comment.dart').color, const Color(0xff008000));
    expect((await assets.load('hc-black')).id, 'hc-black');
    expect((await assets.load('hc-light')).id, 'hc-light');
  });

  test('rejects an unsupported built-in theme', () async {
    await expectLater(assets.load('not-a-theme'), throwsArgumentError);
  });
}
