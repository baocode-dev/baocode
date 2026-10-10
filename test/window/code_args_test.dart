import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/window/code_args.dart';

void main() {
  group('CodeArgs.parse', () {
    test('paths are made absolute from the working directory', () {
      final args = CodeArgs.parse(['.', 'src/a.dart', '/abs'], cwd: '/work');
      expect(args.paths, const [
        CodeTarget('/work'),
        CodeTarget('/work/src/a.dart'),
        CodeTarget('/abs'),
      ]);
      expect(args.newWindow, isFalse);
      expect(args.reuseWindow, isFalse);
      expect(args.goto, isFalse);
    });

    test('-n, -r and their long names; -n wins over -r', () {
      expect(CodeArgs.parse(['-n'], cwd: '/w').newWindow, isTrue);
      expect(CodeArgs.parse(['--new-window'], cwd: '/w').newWindow, isTrue);
      expect(CodeArgs.parse(['-r'], cwd: '/w').reuseWindow, isTrue);
      expect(CodeArgs.parse(['--reuse-window'], cwd: '/w').reuseWindow, isTrue);
      final both = CodeArgs.parse(['-r', '-n'], cwd: '/w');
      expect(both.newWindow, isTrue);
      expect(both.reuseWindow, isFalse);
    });

    test('-g reads file:line[:col]', () {
      final args = CodeArgs.parse([
        '-g',
        'a.dart:12',
        'b.dart:3:7',
        'c.dart',
      ], cwd: '/w');
      expect(args.goto, isTrue);
      expect(args.paths, const [
        CodeTarget('/w/a.dart', line: 12),
        CodeTarget('/w/b.dart', line: 3, column: 7),
        CodeTarget('/w/c.dart'),
      ]);
    });

    test('without -g, a colon is part of the name', () {
      expect(CodeArgs.parse(['a.dart:12'], cwd: '/w').paths, const [
        CodeTarget('/w/a.dart:12'),
      ]);
    });

    test('options it does not know are left out; -- ends the options', () {
      final args = CodeArgs.parse(['--wait', '-x', 'a', '--', '-n'], cwd: '/w');
      expect(args.paths, const [CodeTarget('/w/a'), CodeTarget('/w/-n')]);
      expect(args.newWindow, isFalse);
    });

    test('Windows paths: a drive\'s colon is no line', () {
      final args = CodeArgs.parse([
        '-g',
        r'C:\src\a.dart:4:2',
        r'b.dart:9',
        r'D:\x',
      ], cwd: r'C:\work');
      expect(args.paths, const [
        CodeTarget(r'C:\src\a.dart', line: 4, column: 2),
        CodeTarget(r'C:\work\b.dart', line: 9),
        CodeTarget(r'D:\x'),
      ]);
    });
  });

  test('a request: the marker, the working directory, the arguments', () {
    final request = [CodeArgs.requestMarker, '/w', '-n', 'x'];
    expect(CodeArgs.isRequest(request), isTrue);
    expect(CodeArgs.isRequest(['/w/x']), isFalse);
    expect(CodeArgs.isRequest(const []), isFalse);
    final args = CodeArgs.fromRequest(request);
    expect(args.newWindow, isTrue);
    expect(args.paths, const [CodeTarget('/w/x')]);
    expect(CodeArgs.fromRequest([CodeArgs.requestMarker]).paths, isEmpty);
  });

  test('a request file: the working directory, then an argument a line', () {
    final args = CodeArgs.fromRequestFile('/home/me\n-g\nmain.dart:5\n');
    expect(args.goto, isTrue);
    expect(args.paths, const [CodeTarget('/home/me/main.dart', line: 5)]);
    expect(CodeArgs.fromRequestFile('').paths, isEmpty);
    // `code` alone: the working directory only.
    final none = CodeArgs.fromRequestFile('/home/me\n');
    expect(none.paths, isEmpty);
  });

  test('what the app was started for, by its command line', () {
    expect(LaunchRequest.of(const []), LaunchRequest.none);
    expect(LaunchRequest.of(const ['--some-flag']), LaunchRequest.none);
    expect(
      LaunchRequest.of(const [CodeArgs.windowsAgentFlag, r'C:\w\a.dart']),
      LaunchRequest.agent,
    );
    expect(
      LaunchRequest.of(const [CodeArgs.windowsRequestFlag, r'C:\w']),
      LaunchRequest.ide,
    );
    expect(LaunchRequest.of(const [r'C:\w']), LaunchRequest.ide);
    // An extension's URI (the baocode:// protocol): the last run's windows.
    expect(
      LaunchRequest.of(const [
        CodeArgs.windowsUrlFlag,
        '--',
        'baocode://vscode.github-authentication/did-authenticate',
      ]),
      LaunchRequest.none,
    );
  });
}
