import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/extensions/window/secrets/credential_manager_backend.dart';
import 'package:baocode/extensions/window/secrets/encrypted_file_backend.dart';
import 'package:baocode/extensions/window/secrets/keychain_backend.dart';
import 'package:baocode/extensions/window/secrets/secret_backend.dart';
import 'package:baocode/extensions/window/secrets/secret_tool_backend.dart';
import 'package:baocode/extensions/window/secrets/secrets_fallback_notice.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A recorded command and what it answers.
typedef _Call = ({String executable, List<String> arguments, String? input});

final class _Commands {
  _Commands(this.answer);

  final ProcessResult Function(_Call call) answer;
  final calls = <_Call>[];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? input,
  }) async {
    final call = (executable: executable, arguments: arguments, input: input);
    calls.add(call);
    return answer(call);
  }
}

ProcessResult _result(int code, {String stdout = '', String stderr = ''}) =>
    ProcessResult(0, code, stdout, stderr);

/// Generic credentials in memory.
final class _Credentials implements CredentialStore {
  final items = <String, StoredCredential>{};

  @override
  StoredCredential? read(String target) => items[target];

  @override
  void write(String target, Uint8List blob, String? comment) =>
      items[target] = (blob: Uint8List.fromList(blob), comment: comment);

  @override
  bool delete(String target) => items.remove(target) != null;
}

void main() {
  group('secretAccount', () {
    test('is <id>/<key> with what no store takes escaped', () {
      expect(secretAccount('pub.ext', 'token'), 'pub.ext/token');
      expect(secretAccount('pub.ext', 'a/b c"d'), 'pub.ext/a/b c"d');
      expect(
        secretAccount('pub.ext', '50%\n\r\x00\x7f'),
        'pub.ext/50%25%0A%0D%00%7F',
      );
      expect(secretAccount('a/b', 'c'), 'a%2Fb/c');
      expect(secretAccount('pub.ext', '中文'), 'pub.ext/中文');
    });
  });

  group('KeychainBackend', () {
    test('adds through `security -i`, the value in hex on stdin', () async {
      final commands = _Commands((_) => _result(0));
      final backend = KeychainBackend(run: commands.run);
      await backend.write('pub.ext/a "b"', 'pä\nss');
      final call = commands.calls.single;
      expect(call.executable, '/usr/bin/security');
      expect(call.arguments, ['-i']);
      expect(
        call.input,
        'add-generic-password -U -s "BaoCode Extension Secrets" '
        r'-a "pub.ext/a \"b\"" -X 70c3a40a7373'
        '\n',
      );
      expect(call.input, isNot(contains('pä')));
      expect(KeychainBackend.addCommand('x', ''), contains('-w ""'));
      expect(KeychainBackend.quote(r'a\b'), r'"a\\b"');
    });

    test('a failing add throws', () async {
      final backend = KeychainBackend(
        run: _Commands(
          (_) => _result(0, stderr: 'add-generic-password: returned 2'),
        ).run,
      );
      await expectLater(
        backend.write('a', 'b'),
        throwsA(isA<SecretBackendException>()),
      );
    });

    test('reads with -g, text or hex', () async {
      var stderr = '';
      var code = 0;
      final commands = _Commands((_) => _result(code, stderr: stderr));
      final backend = KeychainBackend(run: commands.run);

      stderr = 'password: "a"b"\nkeychain: "/x"\n';
      expect(await backend.read('pub.ext/k'), 'a"b');
      expect(commands.calls.last.arguments, [
        'find-generic-password',
        '-s',
        'BaoCode Extension Secrets',
        '-a',
        'pub.ext/k',
        '-g',
      ]);
      // What `-w` would print as "e4b8ade69687" too.
      stderr = 'password: 0xE4B8ADE69687 \n';
      expect(await backend.read('pub.ext/k'), '中文');
      stderr = 'password: 0x6C696E65310A6C696E6532  "line1\\012line2"\n';
      expect(await backend.read('pub.ext/k'), 'line1\nline2');
      stderr = 'password: \nkeychain: "/x"\n';
      expect(await backend.read('pub.ext/k'), '');
      stderr = 'password: "610a62"\n';
      expect(await backend.read('pub.ext/k'), '610a62');

      code = 44;
      expect(await backend.read('pub.ext/k'), isNull);
      code = 51;
      stderr = 'User interaction is not allowed.';
      await expectLater(
        backend.read('pub.ext/k'),
        throwsA(isA<SecretBackendException>()),
      );
    });

    test('deletes; nothing there is no error', () async {
      var code = 0;
      final commands = _Commands((_) => _result(code));
      final backend = KeychainBackend(run: commands.run);
      await backend.delete('pub.ext/k');
      expect(commands.calls.last.arguments, [
        'delete-generic-password',
        '-s',
        'BaoCode Extension Secrets',
        '-a',
        'pub.ext/k',
      ]);
      code = 44;
      await backend.delete('pub.ext/k');
      code = 1;
      await expectLater(
        backend.delete('x'),
        throwsA(isA<SecretBackendException>()),
      );
    });
  });

  group('SecretToolBackend', () {
    test('stores with the value on stdin, looks up, clears', () async {
      var result = _result(0);
      final commands = _Commands((_) => result);
      final backend = SecretToolBackend(run: commands.run);
      await backend.write('pub.ext/k', 'v\n');
      expect(commands.calls.last.executable, 'secret-tool');
      expect(commands.calls.last.arguments, [
        'store',
        '--label=BaoCode Extension Secrets: pub.ext/k',
        'service',
        'BaoCode Extension Secrets',
        'account',
        'pub.ext/k',
      ]);
      expect(commands.calls.last.input, 'v\n');

      result = _result(0, stdout: 'v\n');
      expect(await backend.read('pub.ext/k'), 'v\n');
      expect(commands.calls.last.arguments, [
        'lookup',
        'service',
        'BaoCode Extension Secrets',
        'account',
        'pub.ext/k',
      ]);
      result = _result(1);
      expect(await backend.read('pub.ext/k'), isNull);
      result = _result(1, stderr: 'Cannot autolaunch D-Bus');
      await expectLater(
        backend.read('pub.ext/k'),
        throwsA(isA<SecretBackendException>()),
      );

      result = _result(0);
      await backend.delete('pub.ext/k');
      expect(commands.calls.last.arguments.first, 'clear');
      result = _result(1);
      await backend.delete('pub.ext/k');
    });

    test('is available when installed and a service answers', () async {
      Future<bool> probe(ProcessResult Function(_Call) answer) =>
          SecretToolBackend.isAvailable(_Commands(answer).run);
      expect(await probe((_) => _result(1)), isFalse);
      expect(
        await probe((c) => c.executable == 'which' ? _result(0) : _result(1)),
        isTrue,
      );
      expect(
        await probe(
          (c) => c.executable == 'which'
              ? _result(0)
              : _result(1, stderr: 'secret-tool: No such interface'),
        ),
        isFalse,
      );
    });
  });

  group('forPlatform', () {
    late Directory temp;
    setUp(() async => temp = await Directory.systemTemp.createTemp('secrets'));
    tearDown(() => temp.delete(recursive: true));

    Future<SecretBackend> chosen(
      String os,
      ProcessResult Function(_Call) answer, {
      bool security = true,
    }) => (SecretBackend.forPlatform(
      fallbackDirectory: temp.path,
      operatingSystem: os,
      run: _Commands(answer).run,
      fileExists: (_) => security,
    ) as ProbingSecretBackend).chosen;

    test('picks the system\'s store, else the encrypted file', () async {
      expect((await chosen('macos', (_) => _result(0))).kind, 'keychain');
      expect(
        (await chosen('macos', (_) => _result(0), security: false)).kind,
        'encrypted-file',
      );
      expect(
        (await chosen('windows', (_) => _result(0))).kind,
        'credential-manager',
      );
      // `which` finds it; the probe's lookup finds nothing and says nothing.
      expect(
        (await chosen(
          'linux',
          (c) => c.executable == 'which' ? _result(0) : _result(1),
        )).kind,
        'secret-tool',
      );
      expect(
        (await chosen(
          'linux',
          (c) => c.executable == 'which' ? _result(1) : _result(0),
        )).kind,
        'encrypted-file',
      );
    });

    test('warns once, before the first secret goes into the file', () async {
      var warned = 0;
      final backend = SecretBackend.forPlatform(
        fallbackDirectory: temp.path,
        operatingSystem: 'linux',
        run: _Commands((_) => _result(1)).run,
        fileExists: (_) => false,
        onFallback: () => warned++,
      );
      // `which secret-tool` fails: the file.
      expect(await backend.read('a/b'), isNull);
      expect(warned, 0);
      await backend.write('a/b', '1');
      await backend.write('a/c', '2');
      expect(warned, 1);
      expect(await backend.read('a/b'), '1');
    });

    test('the warning is a notification', () {
      final notifications = IdeNotifications();
      addTearDown(notifications.dispose);
      showSecretsFallbackWarning(notifications, englishLocalizations);
      final shown = notifications.notifications.single;
      expect(shown.severity, IdeSeverity.warning);
      expect(shown.message, englishLocalizations.windowSecretsFallbackWarning);
      expect(shown.message, contains('encrypted file'));
    });
  });

  group('EncryptedFileBackend', () {
    late Directory temp;
    setUp(() async => temp = await Directory.systemTemp.createTemp('secrets'));
    tearDown(() => temp.delete(recursive: true));

    test('keeps values encrypted, its key in a file of its own', () async {
      final dir = p.join(temp.path, 'extension-secrets');
      final backend = EncryptedFileBackend(dir);
      expect(await backend.read('pub.ext/k'), isNull);
      await backend.write('pub.ext/k', 'hunter2 中文');
      await backend.write('pub.ext/empty', '');
      expect(await backend.read('pub.ext/k'), 'hunter2 中文');
      expect(await backend.read('pub.ext/empty'), '');

      final values = File(backend.valuesPath).readAsStringSync();
      expect(values, isNot(contains('hunter2')));
      expect((jsonDecode(values) as Map).keys, ['pub.ext/k', 'pub.ext/empty']);
      expect(
        base64.decode(File(backend.keyPath).readAsStringSync()),
        hasLength(32),
      );
      if (!Platform.isWindows) {
        expect(File(backend.keyPath).statSync().modeString(), 'rw-------');
        expect(File(backend.valuesPath).statSync().modeString(), 'rw-------');
        expect(Directory(dir).statSync().modeString(), 'rwx------');
      }

      // Another run reads them back; the same value encrypts differently.
      final again = EncryptedFileBackend(dir);
      expect(await again.read('pub.ext/k'), 'hunter2 中文');
      await again.write('pub.ext/k', 'hunter2 中文');
      expect(File(backend.valuesPath).readAsStringSync(), isNot(values));

      await again.delete('pub.ext/k');
      await again.delete('pub.ext/none');
      expect(await EncryptedFileBackend(dir).read('pub.ext/k'), isNull);
      expect(await EncryptedFileBackend(dir).read('pub.ext/empty'), '');
    });

    test(
      'a value moved to another account, or changed, reads as none',
      () async {
        final backend = EncryptedFileBackend(temp.path);
        await backend.write('a/1', 'one');
        await backend.write('a/2', 'two');
        final json =
            jsonDecode(File(backend.valuesPath).readAsStringSync()) as Map;
        final sealed = base64.decode(json['a/2'] as String);
        sealed[sealed.length - 1] ^= 1;
        File(backend.valuesPath).writeAsStringSync(
          jsonEncode({'a/1': json['a/2'], 'a/2': base64.encode(sealed)}),
        );
        final again = EncryptedFileBackend(temp.path);
        expect(await again.read('a/1'), isNull);
        expect(await again.read('a/2'), isNull);
      },
    );

    test('without its key the values are dropped', () async {
      final backend = EncryptedFileBackend(temp.path);
      await backend.write('a/1', 'one');
      File(backend.keyPath).deleteSync();
      final again = EncryptedFileBackend(temp.path);
      expect(await again.read('a/1'), isNull);
      await again.write('a/2', 'two');
      expect(await again.read('a/2'), 'two');
      expect(
        (jsonDecode(File(backend.valuesPath).readAsStringSync()) as Map).keys,
        ['a/2'],
      );
    });

    test('overlapping writes of different accounts all land', () async {
      final backend = EncryptedFileBackend(temp.path);
      await Future.wait([
        for (var i = 0; i < 20; i++) backend.write('a/$i', 'v$i'),
      ]);
      final again = EncryptedFileBackend(temp.path);
      for (var i = 0; i < 20; i++) {
        expect(await again.read('a/$i'), 'v$i');
      }
    });
  });

  group('CredentialManagerBackend', () {
    test('targets and parts', () {
      expect(
        credentialTarget('pub.ext/k'),
        'BaoCode Extension Secrets/pub.ext/k',
      );
      expect(
        credentialTarget('pub.ext/k', part: 1),
        'BaoCode Extension Secrets (part 2)/pub.ext/k',
      );
      expect(splitCredentialBlob(Uint8List(0)).map((b) => b.length), [0]);
      expect(splitCredentialBlob(Uint8List(2560)).map((b) => b.length), [2560]);
      expect(splitCredentialBlob(Uint8List(6000)).map((b) => b.length), [
        2560,
        2560,
        880,
      ]);
      expect(credentialPartsComment(1), isNull);
      expect(credentialPartsComment(3), 'parts=3');
      expect(credentialParts(null), 1);
      expect(credentialParts('parts=3'), 3);
      expect(credentialParts('parts=0'), 1);
    });

    test('UTF-16 with a NUL for LPCWSTR', () {
      expect(utf16z('a中😀'), [0x61, 0x4e2d, 0xd83d, 0xde00, 0]);
      expect(utf16z(''), [0]);
    });

    test('keeps a value as UTF-8, split when long', () async {
      final store = _Credentials();
      final backend = CredentialManagerBackend(store: store);
      await backend.write('pub.ext/k', 'pä');
      expect(store.items.keys, ['BaoCode Extension Secrets/pub.ext/k']);
      expect(store.items.values.single.blob, utf8.encode('pä'));
      expect(store.items.values.single.comment, isNull);
      expect(await backend.read('pub.ext/k'), 'pä');

      final long = '中' * 2000; // 6000 bytes.
      await backend.write('pub.ext/k', long);
      expect(store.items, hasLength(3));
      expect(
        store.items['BaoCode Extension Secrets/pub.ext/k']!.comment,
        'parts=3',
      );
      expect(await backend.read('pub.ext/k'), long);

      // Shorter again: the parts no longer needed go.
      await backend.write('pub.ext/k', 'x' * 3000);
      expect(store.items, hasLength(2));
      expect(await backend.read('pub.ext/k'), 'x' * 3000);

      await backend.delete('pub.ext/k');
      expect(store.items, isEmpty);
      expect(await backend.read('pub.ext/k'), isNull);
      await backend.delete('pub.ext/k');

      await backend.write('pub.ext/e', '');
      expect(await backend.read('pub.ext/e'), '');
    });

    test('a missing part is an error', () async {
      final store = _Credentials();
      final backend = CredentialManagerBackend(store: store);
      await backend.write('pub.ext/k', 'y' * 3000);
      store.items.remove(credentialTarget('pub.ext/k', part: 1));
      await expectLater(
        backend.read('pub.ext/k'),
        throwsA(isA<SecretBackendException>()),
      );
    });

    test('CREDENTIALW is laid out as wincred.h on 64 bit', () {
      expect(sizeOf<CredentialW>(), 80);
      // Fields written through the struct land at the C offsets.
      final malloc = DynamicLibrary.process()
          .lookupFunction<
            Pointer<Void> Function(Size),
            Pointer<Void> Function(int)
          >('malloc');
      final free = DynamicLibrary.process()
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free');
      final memory = malloc(80);
      addTearDown(() => free(memory));
      memory.cast<Uint8>().asTypedList(80).fillRange(0, 80, 0);
      memory.cast<CredentialW>().ref
        ..flags = 0x11
        ..type = 0x22
        ..targetName = Pointer.fromAddress(0x33)
        ..comment = Pointer.fromAddress(0x44)
        ..credentialBlobSize = 0x55
        ..credentialBlob = Pointer.fromAddress(0x66)
        ..persist = 0x77
        ..attributeCount = 0x88
        ..userName = Pointer.fromAddress(0x99);
      final bytes = memory.cast<Uint8>().asTypedList(80);
      expect(
        {
          for (final offset in [0, 4, 8, 16, 32, 40, 48, 52, 72])
            offset: bytes[offset],
        },
        {
          0: 0x11,
          4: 0x22,
          8: 0x33,
          16: 0x44,
          32: 0x55,
          40: 0x66,
          48: 0x77,
          52: 0x88,
          72: 0x99,
        },
      );
    }, skip: sizeOf<IntPtr>() != 8 ? '64 bit only' : false);
  });
}
