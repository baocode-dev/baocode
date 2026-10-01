// Tests of the link resolver (terminal_link_resolver.dart): upstream has
// no test of terminalLinkResolver.ts. The dart:io stat runs on a temporary
// folder; the rest on a fake stat.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/terminal_link_parsing.dart';
import 'package:baocode/ide/terminal/links/terminal_link_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('TerminalFileLinkResolver on the file system', () {
    late Directory dir;
    late String file;
    late String folder;
    late TerminalFileLinkResolver resolver;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('baocode_links_');
      file = p.join(dir.path, 'a.txt');
      File(file).writeAsStringSync('a');
      folder = p.join(dir.path, 'sub');
      Directory(folder).createSync();
      resolver = TerminalFileLinkResolver(userHome: dir.path);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('resolves files and folders relative to the cwd', () async {
      expect(await resolver.resolve('a.txt', dir.path), (
        path: file,
        isDirectory: false,
      ));
      expect(await resolver.resolve('./sub', dir.path), (
        path: folder,
        isDirectory: true,
      ));
    });

    test('resolves absolute paths without a cwd', () async {
      expect(await resolver.resolve(file, ''), (
        path: file,
        isDirectory: false,
      ));
    });

    test('does not resolve relative paths without a cwd', () async {
      expect(await resolver.resolve('a.txt', ''), isNull);
    });

    test('does not resolve what is not there', () async {
      expect(await resolver.resolve('b.txt', dir.path), isNull);
    });

    test('drops the line and column suffix and the query', () async {
      expect(await resolver.resolve('a.txt:12:3', dir.path), (
        path: file,
        isDirectory: false,
      ));
      expect(await resolver.resolve('"a.txt", line 12', dir.path), isNull);
      expect(await resolver.resolve('a.txt?x=1', dir.path), (
        path: file,
        isDirectory: false,
      ));
    });

    test('resolves ~ against the user home', () async {
      expect(await resolver.resolve('~/a.txt', ''), (
        path: file,
        isDirectory: false,
      ));
      final homeless = TerminalFileLinkResolver(userHome: '');
      expect(await homeless.resolve('~/a.txt', ''), isNull);
    });

    test('resolves file URIs', () async {
      final uri = pathToFileUri(file, hostOperatingSystem);
      expect(await resolver.resolve(uri.toString(), ''), (
        path: file,
        isDirectory: false,
      ));
    });
  });

  group('TerminalFileLinkResolver', () {
    test('caches results per cwd and link', () async {
      final stats = <String>[];
      final resolver = TerminalFileLinkResolver(
        os: OperatingSystem.linux,
        userHome: '/home',
        stat: (path) async {
          stats.add(path);
          return path == '/a/foo' ? false : null;
        },
      );
      expect(await resolver.resolve('foo', '/a'), (
        path: '/a/foo',
        isDirectory: false,
      ));
      expect(await resolver.resolve('foo', '/a'), (
        path: '/a/foo',
        isDirectory: false,
      ));
      expect(await resolver.resolve('foo', '/b'), isNull);
      expect(await resolver.resolve('foo', '/b'), isNull);
      expect(stats, ['/a/foo', '/b/foo']);
    });

    test('joins and normalizes Windows paths', () async {
      final stats = <String>[];
      final resolver = TerminalFileLinkResolver(
        os: OperatingSystem.windows,
        userHome: r'C:\Home',
        stat: (path) async {
          stats.add(path);
          return null;
        },
      );
      await resolver.resolve(r'..\foo', r'C:\Parent\Cwd');
      await resolver.resolve('~/foo', '');
      await resolver.resolve(r'\\?\C:\foo', '');
      await resolver.resolve('file:///c:/foo/bar%20baz', '');
      expect(stats, [
        r'C:\Parent\foo',
        r'C:\Home\foo',
        r'C:\foo',
        r'c:\foo\bar baz',
      ]);
    });
  });

  group('file URIs', () {
    test('round trip POSIX paths', () {
      for (final path in ['/foo/bar baz', '/a/100%/b', r'/f\oo/ba\r.txt']) {
        final uri = pathToFileUri(path, OperatingSystem.linux);
        expect(fileUriToPath(uri, OperatingSystem.linux), path);
      }
      expect(
        pathToFileUri('/foo/bar baz', OperatingSystem.linux).toString(),
        'file:///foo/bar%20baz',
      );
    });

    test('round trip Windows paths', () {
      for (final path in [
        r'C:\foo\bar',
        r'C:\Parent\test-2025-04-28T11:03:09+02:00.log',
        r'\\wsl$\Debian\home',
      ]) {
        final uri = pathToFileUri(path, OperatingSystem.windows);
        expect(fileUriToPath(uri, OperatingSystem.windows), path);
      }
      expect(
        pathToFileUri(r'C:\foo\bar', OperatingSystem.windows).toString(),
        'file:///C:/foo/bar',
      );
    });

    test('an authority is a UNC host', () {
      expect(
        fileUriToPath(
          Uri.parse('file://shares/foo.bar'),
          OperatingSystem.linux,
        ),
        '//shares/foo.bar',
      );
      expect(
        fileUriToPath(
          Uri.parse('file://shares/foo.bar'),
          OperatingSystem.windows,
        ),
        r'\\shares\foo.bar',
      );
    });

    test('other schemes have no path', () {
      expect(
        fileUriToPath(Uri.parse('http://foo/bar'), OperatingSystem.linux),
        isNull,
      );
    });
  });
}
