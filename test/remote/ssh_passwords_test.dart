import 'package:bao_remote/client.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/remote/ssh_password_dialog.dart';
import 'package:baocode/remote/ssh_passwords.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final host = SshTarget.parse('dev');
  SshPrompt password({bool retry = false}) =>
      SshPrompt(host, "me@dev's password: ", retry: retry);

  group('SshPasswords', () {
    late MemorySecretStore secrets;
    late List<(SshPrompt, bool)> asked;
    late List<SshPasswordAnswer?> answers;

    SshPasswords passwords() =>
        SshPasswords(secrets: secrets)
          ..ask = (prompt, {required keepable}) async {
            asked.add((prompt, keepable));
            return answers.removeAt(0);
          };

    setUp(() {
      secrets = MemorySecretStore();
      asked = [];
      answers = [];
    });

    test('remembered once signed in: asked no more, in this run or the '
        'next', () async {
      final kept = passwords();
      answers = [(answer: 'hunter2', remember: true)];
      expect(await kept.answer(password()), 'hunter2');
      expect(asked.single.$2, isTrue, reason: 'may be kept');
      expect(await secrets.read(SshPasswords.idOf(password())), isNull);
      // The next ssh of the same connection: from memory.
      expect(await kept.answer(password()), 'hunter2');
      await kept.signedIn('dev');
      expect(await secrets.read(SshPasswords.idOf(password())), 'hunter2');

      // The next run: from the keychain.
      expect(await passwords().answer(password()), 'hunter2');
      expect(asked, hasLength(1));
    });

    test('not remembered: kept for this run only', () async {
      final once = passwords();
      answers = [(answer: 'hunter2', remember: false)];
      expect(await once.answer(password()), 'hunter2');
      await once.signedIn('dev');
      expect(await once.answer(password()), 'hunter2');
      expect(asked, hasLength(1));
      expect(await secrets.read(SshPasswords.idOf(password())), isNull);
    });

    test('a refused one is forgotten and asked again', () async {
      final id = SshPasswords.idOf(password());
      await secrets.write(id, 'old');
      final refused = passwords();
      expect(await refused.answer(password()), 'old');
      expect(asked, isEmpty);

      answers = [(answer: 'new', remember: true)];
      expect(await refused.answer(password(retry: true)), 'new');
      expect(asked.single.$1.retry, isTrue);
      expect(await secrets.read(id), isNull);
      await refused.signedIn('dev');
      expect(await secrets.read(id), 'new');
    });

    test('refused at the end: forgotten, nothing kept', () async {
      final id = SshPasswords.idOf(password());
      await secrets.write(id, 'old');
      final refused = passwords();
      expect(await refused.answer(password()), 'old');
      await refused.failed('dev', SshFailure.authentication);
      expect(await secrets.read(id), isNull);

      answers = [(answer: 'wrong', remember: true)];
      expect(await refused.answer(password()), 'wrong');
      await refused.failed('dev', SshFailure.authentication);
      expect(await secrets.read(id), isNull);
      // Asked again, not answered from memory.
      answers = [null];
      expect(await refused.answer(password()), isNull);
      expect(asked, hasLength(2));
    });

    test('failing otherwise keeps what was remembered', () async {
      final id = SshPasswords.idOf(password());
      await secrets.write(id, 'kept');
      final unreachable = passwords();
      expect(await unreachable.answer(password()), 'kept');
      await unreachable.failed('dev', SshFailure.unreachable);
      expect(await secrets.read(id), 'kept');
    });

    test('a one-time code is asked each time, never kept', () async {
      final code = SshPrompt(host, 'Verification code: ');
      expect(SshPasswords.keepable(code), isFalse);
      expect(SshPasswords.keepable(SshPrompt(host, 'Password: ')), isTrue);
      expect(
        SshPasswords.keepable(
          SshPrompt(host, "Enter passphrase for key '/me/.ssh/id': "),
        ),
        isTrue,
      );
      final codes = passwords();
      answers = [
        (answer: '123456', remember: true),
        (answer: '654321', remember: true),
      ];
      expect(await codes.answer(code), '123456');
      expect(asked.single.$2, isFalse);
      expect(await codes.answer(code), '654321');
      await codes.signedIn('dev');
      expect(await secrets.read(SshPasswords.idOf(code)), isNull);
    });

    test('nothing answers where no window asks', () async {
      expect(await SshPasswords(secrets: secrets).answer(password()), isNull);
    });

    test('kept by host and prompt', () {
      expect(
        SshPasswords.idOf(password()),
        isNot(
          SshPasswords.idOf(
            SshPrompt(SshTarget.parse('prod'), password().text),
          ),
        ),
      );
      expect(SshPasswords.idOf(password()), startsWith('ssh:dev:'));
    });
  });

  group('the dialog', () {
    Future<Future<SshPasswordAnswer?>> open(
      WidgetTester tester, {
      bool keepable = true,
      bool retry = false,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox(key: Key('home'));
            },
          ),
        ),
      );
      final answer = showSshPasswordDialog(
        context,
        password(retry: retry),
        keepable: keepable,
      );
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('masked, remembered when checked', (tester) async {
      final answer = await open(tester);
      expect(find.text('Sign in to dev'), findsOneWidget);
      expect(find.text("me@dev's password:"), findsOneWidget);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(IdeInputBox),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.obscureText, isTrue);
      await tester.enterText(find.byType(IdeInputBox), 'hunter2');
      await tester.tap(find.textContaining('Remember on this computer'));
      await tester.pump();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(await answer, (answer: 'hunter2', remember: true));
    });

    testWidgets('Enter connects, once; Escape cancels', (tester) async {
      var answer = await open(tester, retry: true);
      expect(find.textContaining('not accepted'), findsOneWidget);
      await tester.enterText(find.byType(IdeInputBox), 'pw');
      // The key, a shortcut of the dialog's, and the input's submission.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await answer, (answer: 'pw', remember: false));
      // Closed once: the page under it is still there.
      expect(find.byKey(const Key('home')), findsOneWidget);

      answer = await open(tester, keepable: false);
      expect(find.textContaining('Remember'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await answer, isNull);
    });
  });
}
