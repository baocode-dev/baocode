// A few cases from VS Code src/vs/base/test/common/uri.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971, plus the Dart Uri adaptation
// (URI.fromUri) and its documented deviations.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/platform.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/uri.dart';

void main() {
  tearDown(() => debugOperatingSystemOverride = null);

  test('URI.file and fsPath follow the platform', () {
    debugOperatingSystemOverride = OperatingSystem.windows;
    expect(URI.file(r'c:\win\path').toString(), 'file:///c%3A/win/path');
    expect(URI.file(r'C:\win\path').fsPath, r'c:\win\path');
    expect(URI.file(r'\\server\share\x').authority, 'server');
    expect(URI.file(r'\\server\share\x').fsPath, r'\\server\share\x');

    debugOperatingSystemOverride = OperatingSystem.linux;
    expect(URI.file(r'c:\win\path').path, r'/c:\win\path');
    expect(URI.file('/a/b.ts').fsPath, '/a/b.ts');
    expect(URI.file('/c:/x').fsPath, 'c:/x');
  });

  test('parse and toString', () {
    expect(
      URI.parse('http://a-test-site.com/#test=true').fragment,
      'test=true',
    );
    expect(URI.parse('file:///c:/test/me').path, '/c:/test/me');
    expect(URI.parse('untitled:Untitled-1').path, 'Untitled-1');
    expect(
      URI
          .from(scheme: 'http', authority: 'www.example.com', path: '/my/path')
          .toString(),
      'http://www.example.com/my/path',
    );
    expect(() => URI.from(scheme: 'fi:le'), throwsFormatException);
  });

  group('URI.fromUri', () {
    test('file URIs match URI.file', () {
      debugOperatingSystemOverride = OperatingSystem.windows;
      final windows = URI.fromUri(Uri.file(r'C:\Work\A B.ts', windows: true));
      expect(windows.toString(), URI.file(r'C:\Work\A B.ts').toString());
      expect(windows.fsPath, r'c:\Work\A B.ts');
      final unc = URI.fromUri(Uri.file(r'\\srv\share\x.md', windows: true));
      expect(unc.authority, 'srv');
      expect(unc.fsPath, r'\\srv\share\x.md');

      debugOperatingSystemOverride = OperatingSystem.macintosh;
      final posix = URI.fromUri(Uri.file('/a/%b #c.ts', windows: false));
      expect(posix.toString(), URI.file('/a/%b #c.ts').toString());
      expect(posix.fsPath, '/a/%b #c.ts');
    });

    test('a relative Dart file URI gets a leading slash', () {
      final uri = URI.fromUri(Uri.file('foo.ts', windows: false));
      expect(uri.scheme, 'file');
      expect(uri.path, '/foo.ts');
    });

    test('other schemes keep their decoded components', () {
      final uri = URI.fromUri(
        Uri.parse('vscode-remote://ssh%2Bhost/x/y%20z.py?q#f'),
      );
      expect(uri.scheme, 'vscode-remote');
      expect(uri.authority, 'ssh+host');
      expect(uri.path, '/x/y z.py');
      expect(uri.query, 'q');
      expect(uri.fragment, 'f');
      expect(URI.fromUri(Uri.parse('untitled:Untitled-1')).path, 'Untitled-1');
    });

    test('deviation: Dart Uri normalizes before conversion', () {
      // VS Code keeps dot segments and the case of scheme and host.
      expect(URI.parse('file:///a/../b.ts').path, '/a/../b.ts');
      expect(URI.fromUri(Uri.parse('file:///a/../b.ts')).path, '/b.ts');
      expect(URI.parse('HTTPS://Example.COM/X').scheme, 'HTTPS');
      final dart = URI.fromUri(Uri.parse('HTTPS://Example.COM/X'));
      expect(dart.scheme, 'https');
      expect(dart.authority, 'example.com');
      expect(dart.path, '/X');
    });
  });
}
