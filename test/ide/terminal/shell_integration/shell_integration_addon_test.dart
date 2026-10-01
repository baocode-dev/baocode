/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/xterm/
// shellIntegrationAddon.test.ts, on the ported core's internal terminal.
// Upstream mocks the capabilities with sinon; here the test addon hands out
// capabilities that record their calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/shell_integration_addon.dart';
import 'package:bao_xterm/headless/terminal.dart';

import 'shell_integration_test_helpers.dart';

/// A capability that records the methods called on it.
class _RecordingCapability {
  final List<Invocation> calls = [];

  /// The positional arguments of each call to [member], without the unset
  /// optional ones.
  List<List<Object?>> argsOf(Symbol member) => [
    for (final call in calls)
      if (call.memberName == member) _withoutTrailingNulls(call),
  ];

  static List<Object?> _withoutTrailingNulls(Invocation call) {
    final args = [...call.positionalArguments];
    while (args.isNotEmpty && args.last == null) {
      args.removeLast();
    }
    return args;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      calls.add(invocation);
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _RecordingCwdDetection extends _RecordingCapability
    implements ICwdDetectionCapability {}

class _RecordingCommandDetection extends _RecordingCapability
    implements ICommandDetectionCapability {}

class _TestShellIntegrationAddon extends ShellIntegrationAddon {
  _TestShellIntegrationAddon(
    super.nonce,
    super.onDidExecuteText,
    super.logService,
  );

  _RecordingCwdDetection? _cwdDetection;
  _RecordingCommandDetection? _commandDetection;

  _RecordingCommandDetection getCommandDetectionMock() {
    final capability = _commandDetection = _RecordingCommandDetection();
    capabilities.add(TerminalCapability.commandDetection, capability);
    return capability;
  }

  _RecordingCwdDetection getCwdDetectionMock() {
    final capability = _cwdDetection = _RecordingCwdDetection();
    capabilities.add(TerminalCapability.cwdDetection, capability);
    return capability;
  }

  @override
  ICwdDetectionCapability createOrGetCwdDetection() =>
      _cwdDetection ?? super.createOrGetCwdDetection();

  @override
  ICommandDetectionCapability createOrGetCommandDetection(Terminal terminal) =>
      _commandDetection ?? super.createOrGetCommandDetection(terminal);
}

void main() {
  late Terminal xterm;
  late _TestShellIntegrationAddon shellIntegrationAddon;
  late ITerminalCapabilityStore capabilities;

  setUp(() {
    xterm = createTestTerminal(cols: 80, rows: 30);
    shellIntegrationAddon = _TestShellIntegrationAddon(
      '',
      null,
      xterm.logService,
    );
    addTearDown(shellIntegrationAddon.dispose);
    shellIntegrationAddon.activate(xterm);
    capabilities = shellIntegrationAddon.capabilities;
  });

  group('cwd detection', () {
    test('should activate capability on the cwd sequence (OSC 633 ; P ; Cwd=<cwd> ST)', () async {
      expect(capabilities.has(TerminalCapability.cwdDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.cwdDetection), isFalse);
      await writeP(xterm, '\x1b]633;P;Cwd=/foo\x07');
      expect(capabilities.has(TerminalCapability.cwdDetection), isTrue);
    });

    test('should pass cwd sequence to the capability as trusted when nonce matches', () async {
      final mock = shellIntegrationAddon.getCwdDetectionMock();
      // The addon is constructed with nonce '' so a trailing ';' produces
      // args[1]==='' which matches
      await writeP(xterm, '\x1b]633;P;Cwd=/foo;\x07');
      expect(mock.argsOf(#updateCwd), [
        ['/foo', true],
      ]);
    });

    test(
      'should treat cwd sequence as untrusted when nonce is missing',
      () async {
        final mock = shellIntegrationAddon.getCwdDetectionMock();
        await writeP(xterm, '\x1b]633;P;Cwd=/foo\x07');
        expect(mock.argsOf(#updateCwd), [
          ['/foo', false],
        ]);
      },
    );

    test(
      'should treat cwd sequence as untrusted when nonce does not match',
      () async {
        final mock = shellIntegrationAddon.getCwdDetectionMock();
        await writeP(xterm, '\x1b]633;P;Cwd=/foo;invalid-nonce\x07');
        expect(mock.argsOf(#updateCwd), [
          ['/foo', false],
        ]);
      },
    );

    test('detect ITerm sequence: `OSC 1337 ; CurrentDir=<Cwd> ST`', () async {
      const cases = [
        ('root', '/', '/'),
        ('non-root', '/some/path', '/some/path'),
      ];
      for (final (title, input, expected) in cases) {
        final mock = shellIntegrationAddon.getCwdDetectionMock();
        await writeP(xterm, '\x1b]1337;CurrentDir=$input\x07');
        expect(mock.argsOf(#updateCwd), [
          [expected, false],
        ], reason: title);
      }
    });

    group('detect `SetCwd` sequence: `OSC 7; scheme://cwd ST`', () {
      test('should accept well-formatted URLs', () async {
        const cases = [
          // Different hostname values:
          ('empty hostname, pointing root', 'file:///', '/'),
          ('empty hostname', 'file:///test-root/local', '/test-root/local'),
          (
            'non-empty hostname',
            'file://some-hostname/test-root/local',
            '/test-root/local',
          ),
          // URL-encoded chars:
          (
            'URL-encoded value (1)',
            'file:///test-root/%6c%6f%63%61%6c',
            '/test-root/local',
          ),
          (
            'URL-encoded value (2)',
            'file:///test-root/local%22',
            '/test-root/local"',
          ),
          (
            'URL-encoded value (3)',
            'file:///test-root/local"',
            '/test-root/local"',
          ),
        ];
        for (final (title, input, expected) in cases) {
          final mock = shellIntegrationAddon.getCwdDetectionMock();
          await writeP(xterm, '\x1b]7;$input\x07');
          expect(mock.argsOf(#updateCwd), [
            [expected, false],
          ], reason: title);
        }
      });

      test('should ignore ill-formatted URLs', () async {
        const cases = [
          // Different hostname values:
          ('no hostname, pointing root', 'file://'),
          // Non-`file` scheme values:
          ('no scheme (1)', '/test-root'),
          ('no scheme (2)', '//test-root'),
          ('no scheme (3)', '///test-root'),
          ('no scheme (4)', ':///test-root'),
          ('http', 'http:///test-root'),
          ('ftp', 'ftp:///test-root'),
          ('ssh', 'ssh:///test-root'),
        ];
        for (final (title, input) in cases) {
          final mock = shellIntegrationAddon.getCwdDetectionMock();
          await writeP(xterm, '\x1b]7;$input\x07');
          expect(mock.argsOf(#updateCwd), isEmpty, reason: title);
        }
      });
    });

    test(
      'detect `SetWindowsFrindlyCwd` sequence: `OSC 9 ; 9 ; <cwd> ST`',
      () async {
        const cases = [
          ('root', '/', '/'),
          ('non-root', '/some/path', '/some/path'),
        ];
        for (final (title, input, expected) in cases) {
          final mock = shellIntegrationAddon.getCwdDetectionMock();
          await writeP(xterm, '\x1b]9;9;$input\x07');
          expect(mock.argsOf(#updateCwd), [
            [expected, false],
          ], reason: title);
        }
      },
    );
  });

  group('command tracking', () {
    test('should activate capability on the prompt start sequence (OSC 633 ; A ST)', () async {
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, '\x1b]633;A\x07');
      expect(capabilities.has(TerminalCapability.commandDetection), isTrue);
    });
    test('should pass prompt start sequence to the capability', () async {
      final mock = shellIntegrationAddon.getCommandDetectionMock();
      await writeP(xterm, '\x1b]633;A\x07');
      expect(mock.argsOf(#handlePromptStart), [<Object?>[]]);
    });
    test('should activate capability on the command start sequence (OSC 633 ; B ST)', () async {
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, '\x1b]633;B\x07');
      expect(capabilities.has(TerminalCapability.commandDetection), isTrue);
    });
    test('should pass command start sequence to the capability', () async {
      final mock = shellIntegrationAddon.getCommandDetectionMock();
      await writeP(xterm, '\x1b]633;B\x07');
      expect(mock.argsOf(#handleCommandStart), [<Object?>[]]);
    });
    test('should activate capability on the command executed sequence (OSC 633 ; C ST)', () async {
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, '\x1b]633;C\x07');
      expect(capabilities.has(TerminalCapability.commandDetection), isTrue);
    });
    test('should pass command executed sequence to the capability', () async {
      final mock = shellIntegrationAddon.getCommandDetectionMock();
      await writeP(xterm, '\x1b]633;C\x07');
      expect(mock.argsOf(#handleCommandExecuted), [<Object?>[]]);
    });
    test('should activate capability on the command finished sequence (OSC 633 ; D ; <ExitCode> ST)', () async {
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, '\x1b]633;D;7\x07');
      expect(capabilities.has(TerminalCapability.commandDetection), isTrue);
    });
    test('should pass command finished sequence to the capability', () async {
      final mock = shellIntegrationAddon.getCommandDetectionMock();
      await writeP(xterm, '\x1b]633;D;7\x07');
      expect(mock.argsOf(#handleCommandFinished), [
        [7],
      ]);
    });
    test('should pass command line sequence to the capability', () async {
      final mock = shellIntegrationAddon.getCommandDetectionMock();
      await writeP(xterm, '\x1b]633;E\x07');
      expect(mock.argsOf(#setCommandLine), [
        ['', false],
      ]);

      final mock2 = shellIntegrationAddon.getCommandDetectionMock();
      await writeP(xterm, '\x1b]633;E;cmd\x07');
      await writeP(xterm, '\x1b]633;E;cmd;invalid-nonce\x07');
      expect(mock2.argsOf(#setCommandLine), [
        ['cmd', false],
        ['cmd', false],
      ]);
    });
    test('should not activate capability on the cwd sequence (OSC 633 ; P=Cwd=<cwd> ST)', () async {
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
      await writeP(xterm, '\x1b]633;P;Cwd=/foo\x07');
      expect(capabilities.has(TerminalCapability.commandDetection), isFalse);
    });
    test(
      "should pass cwd sequence to the capability if it's initialized",
      () async {
        final mock = shellIntegrationAddon.getCommandDetectionMock();
        await writeP(xterm, '\x1b]633;P;Cwd=/foo\x07');
        expect(mock.argsOf(#setCwd), [
          ['/foo'],
        ]);
      },
    );
  });

  group('BufferMarkCapability', () {
    test('SetMark', () async {
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, '\x1b]633;SetMark;\x07');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isTrue);
    });
    test('SetMark - ID', () async {
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, '\x1b]633;SetMark;1;\x07');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isTrue);
    });
    test('SetMark - hidden', () async {
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, '\x1b]633;SetMark;;Hidden\x07');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isTrue);
    });
    test('SetMark - hidden & ID', () async {
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, 'foo');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isFalse);
      await writeP(xterm, '\x1b]633;SetMark;1;Hidden\x07');
      expect(capabilities.has(TerminalCapability.bufferMarkDetection), isTrue);
    });
    group('parseMarkSequence', () {
      Object props(IMarkProperties p) => (p.id, p.hidden);
      test('basic', () {
        expect(props(parseMarkSequence(['', ''])), (null, false));
      });
      test('ID', () {
        expect(props(parseMarkSequence(['Id=3', ''])), ('3', false));
      });
      test('hidden', () {
        expect(props(parseMarkSequence(['', 'Hidden'])), (null, true));
      });
      test('ID + hidden', () {
        expect(props(parseMarkSequence(['Id=4555', 'Hidden'])), ('4555', true));
      });
    });
  });

  group('deserializeMessage', () {
    // A single literal backslash, in order to avoid confusion about whether
    // we are escaping test data or testing escapes.
    const backslash = r'\';
    const newline = '\n';
    const semicolon = ';';

    const cases = [
      ('empty', '', ''),
      ('basic', 'value', 'value'),
      ('space', 'some thing', 'some thing'),
      ('escaped backslash', '$backslash$backslash', backslash),
      (
        'non-initial escaped backslash',
        'foo$backslash$backslash',
        'foo$backslash',
      ),
      (
        'two escaped backslashes',
        '$backslash$backslash$backslash$backslash',
        '$backslash$backslash',
      ),
      (
        'escaped backslash amidst text',
        'Hello$backslash${backslash}there',
        'Hello${backslash}there',
      ),
      (
        'backslash escaped literally and as hex',
        '$backslash$backslash is same as ${backslash}x5c',
        '$backslash is same as $backslash',
      ),
      ('escaped semicolon', '${backslash}x3b', semicolon),
      ('non-initial escaped semicolon', 'foo${backslash}x3b', 'foo$semicolon'),
      ('escaped semicolon (upper hex)', '${backslash}x3B', semicolon),
      (
        'escaped backslash followed by literal "x3b" is not a semicolon',
        '$backslash${backslash}x3b',
        '${backslash}x3b',
      ),
      (
        'non-initial escaped backslash followed by literal "x3b" is not a semicolon',
        'foo$backslash${backslash}x3b',
        'foo${backslash}x3b',
      ),
      (
        'escaped backslash followed by escaped semicolon',
        '$backslash$backslash${backslash}x3b',
        '$backslash$semicolon',
      ),
      (
        'escaped semicolon amidst text',
        'some${backslash}x3bthing',
        'some${semicolon}thing',
      ),
      ('escaped newline', '${backslash}x0a', newline),
      ('non-initial escaped newline', 'foo${backslash}x0a', 'foo$newline'),
      ('escaped newline (upper hex)', '${backslash}x0A', newline),
      (
        'escaped backslash followed by literal "x0a" is not a newline',
        '$backslash${backslash}x0a',
        '${backslash}x0a',
      ),
      (
        'non-initial escaped backslash followed by literal "x0a" is not a newline',
        'foo$backslash${backslash}x0a',
        'foo${backslash}x0a',
      ),
      ('PS1 simple', r'[\u@\h \W]\$', r'[\u@\h \W]\$'),
      (
        'PS1 VSC SI',
        '${backslash}x1b]633;A${backslash}x07\\[${backslash}x1b]0;\\u@\\h:\\w\\a\\]${backslash}x1b]633;B${backslash}x07',
        '\x1b]633;A\x07\\[\x1b]0;\\u@\\h:\\w\\a\\]\x1b]633;B\x07',
      ),
    ];

    for (final (title, input, expected) in cases) {
      test(title, () => expect(deserializeVSCodeOscMessage(input), expected));
    }
  });

  group('serializeVSCodeOscMessage', () {
    // A single literal backslash, in order to avoid confusion about whether
    // we are escaping test data or testing escapes.
    const backslash = r'\';
    const newline = '\n';
    const semicolon = ';';

    const cases = [
      ('empty', '', ''),
      ('basic', 'value', 'value'),
      ('space', 'some thing', 'some${backslash}x20thing'),
      ('backslash', backslash, '$backslash$backslash'),
      ('non-initial backslash', 'foo$backslash', 'foo$backslash$backslash'),
      (
        'two backslashes',
        '$backslash$backslash',
        '$backslash$backslash$backslash$backslash',
      ),
      (
        'backslash amidst text',
        'Hello${backslash}there',
        'Hello$backslash${backslash}there',
      ),
      ('semicolon', semicolon, '${backslash}x3b'),
      ('non-initial semicolon', 'foo$semicolon', 'foo${backslash}x3b'),
      (
        'semicolon amidst text',
        'some${semicolon}thing',
        'some${backslash}x3bthing',
      ),
      ('newline', newline, '${backslash}x0a'),
      ('non-initial newline', 'foo$newline', 'foo${backslash}x0a'),
      (
        'newline amidst text',
        'some${newline}thing',
        'some${backslash}x0athing',
      ),
      ('tab character', '\t', '${backslash}x09'),
      ('carriage return', '\r', '${backslash}x0d'),
      ('null character', '\x00', '${backslash}x00'),
      ('space character (0x20)', ' ', '${backslash}x20'),
      ('character above 0x20', '!', '!'),
      (
        'multiple special chars',
        'hello${newline}world${semicolon}test${backslash}end',
        'hello${backslash}x0aworld${backslash}x3btest$backslash${backslash}end',
      ),
      (
        'PS1 with escape sequences',
        '\x1b]633;A\x07\\[\x1b]0;\\u@\\h:\\w\\a\\]\x1b]633;B\x07',
        '${backslash}x1b]633${backslash}x3bA${backslash}x07$backslash$backslash[${backslash}x1b]0${backslash}x3b$backslash${backslash}u@$backslash${backslash}h:$backslash${backslash}w$backslash${backslash}a$backslash$backslash]${backslash}x1b]633${backslash}x3bB${backslash}x07',
      ),
    ];

    for (final (title, input, expected) in cases) {
      test(title, () => expect(serializeVSCodeOscMessage(input), expected));
    }
  });

  test('parseKeyValueAssignment', () {
    const cases = [
      ('empty', '', ('', null)),
      ('no "=" sign', 'some-text', ('some-text', null)),
      ('empty value', 'key=', ('key', '')),
      ('empty key', '=value', ('', 'value')),
      ('normal', 'key=value', ('key', 'value')),
      ('multiple "=" signs (1)', 'key==value', ('key', '=value')),
      ('multiple "=" signs (2)', 'key=value===true', ('key', 'value===true')),
      ('just a "="', '=', ('', '')),
      ('just a "=="', '==', ('', '=')),
    ];

    for (final (title, input, (key, value)) in cases) {
      expect(parseKeyValueAssignment(input), (
        key: key,
        value: value,
      ), reason: title);
    }
  });

  // Not upstream: the addon with its real capabilities.
  group('with its capabilities', () {
    late ShellIntegrationAddon addon;

    Future<void> setUpAddon({String nonce = '', bool isWindows = false}) async {
      addon = ShellIntegrationAddon(
        nonce,
        null,
        xterm.logService,
        isWindows: isWindows,
      );
      addTearDown(addon.dispose);
      // The terminal of the outer setUp has the test addon too: a new one.
      xterm = createTestTerminal();
      addon.activate(xterm);
    }

    test('status goes from off to FinalTerm to VS Code', () async {
      await setUpAddon();
      final statuses = <ShellIntegrationStatus>[];
      addon.onDidChangeStatus(statuses.add);
      expect(addon.status, ShellIntegrationStatus.off);

      await writeP(xterm, '\x1b]133;A\x07');
      expect(addon.status, ShellIntegrationStatus.finalTerm);
      await writeP(xterm, '\x1b]633;A\x07');
      expect(addon.status, ShellIntegrationStatus.vsCode);
      await writeP(xterm, '\x1b]133;A\x07\x1b]633;B\x07');
      expect(addon.status, ShellIntegrationStatus.vsCode);
      expect(statuses, [
        ShellIntegrationStatus.finalTerm,
        ShellIntegrationStatus.vsCode,
      ]);
      expect(addon.seenSequences, containsAll(['A', 'B']));
    });

    test('tracks a command from FinalTerm sequences (OSC 133)', () async {
      await setUpAddon();
      await writeP(xterm, '\x1b]133;A\x07\$ \x1b]133;B\x07ls\r\n');
      await writeP(xterm, '\x1b]133;C\x07a b\r\n\x1b]133;D;2\x07');
      final commandDetection = addon.capabilities.get(
        TerminalCapability.commandDetection,
      )!;
      final command = commandDetection.commands.single;
      expect(command.exitCode, 2);
      expect(command.marker!.line, 0);
      expect(command.getOutput(), 'a b\n');
    });

    test('trusts command lines and cwds with the nonce only', () async {
      await setUpAddon(nonce: 'n0nce');
      // Commands get the cwds that come after the first prompt.
      await writeP(xterm, '\x1b]633;A\x07\x1b]633;P;Cwd=/a;n0nce\x07');
      final cwdDetection = addon.capabilities.get(
        TerminalCapability.cwdDetection,
      )!;
      expect(cwdDetection.getCwd(), '/a');
      expect(cwdDetection.isTrusted, isTrue);
      await writeP(xterm, '\x1b]633;P;Cwd=/b;wrong\x07');
      expect(cwdDetection.getCwd(), '/b');
      expect(cwdDetection.isTrusted, isFalse);

      await writeP(xterm, '\$ \x1b]633;B\x07');
      await writeP(xterm, 'echo hi\r\n\x1b]633;E;echo\\x20hi;n0nce\x07');
      await writeP(xterm, '\x1b]633;C\x07hi\r\n\x1b]633;D;0\x07');
      await writeP(xterm, '\x1b]633;A\x07\$ \x1b]633;B\x07');
      await writeP(xterm, 'echo hi\r\n\x1b]633;E;echo\\x20hi;wrong\x07');
      await writeP(xterm, '\x1b]633;C\x07hi\r\n\x1b]633;D;0\x07');
      final commands = addon.capabilities
          .get(TerminalCapability.commandDetection)!
          .commands;
      expect(
        [for (final c in commands) (c.command, c.isTrusted)],
        [('echo hi', true), ('echo hi', false)],
      );
      expect([for (final c in commands) c.cwd], ['/b', '/b']);
    });

    test(
      'an unknown property adds a mark, as upstream falls through',
      () async {
        await setUpAddon();
        await writeP(xterm, '\x1b]633;P;Unknown=1\x07');
        final bufferMarks = addon.capabilities.get(
          TerminalCapability.bufferMarkDetection,
        )!;
        expect(bufferMarks.markers(), hasLength(1));
      },
    );

    test('an iTerm SetMark adds a mark', () async {
      await setUpAddon();
      await writeP(xterm, 'foo\r\n\x1b]1337;SetMark\x07');
      final bufferMarks = addon.capabilities.get(
        TerminalCapability.bufferMarkDetection,
      )!;
      expect([for (final m in bufferMarks.markers()) m.line], [1]);
    });

    test('marks by id', () async {
      await setUpAddon();
      await writeP(xterm, 'a\r\nb\x1b]633;SetMark;Id=m1;Hidden\x07');
      final bufferMarks = addon.capabilities.get(
        TerminalCapability.bufferMarkDetection,
      )!;
      expect(bufferMarks.getMark('m1')!.line, 1);
      expect(bufferMarks.getMark('m2'), isNull);
    });

    test('sanitizes cwds', () async {
      await setUpAddon(isWindows: true);
      await writeP(xterm, '\x1b]633;P;Cwd="c:\\x5cfoo"\x07');
      expect(
        addon.capabilities.get(TerminalCapability.cwdDetection)!.getCwd(),
        r'C:\foo',
      );
    });

    test('reads the environment (EnvJson and EnvSingle*)', () async {
      await setUpAddon(nonce: 'n');
      await writeP(
        xterm,
        '\x1b]633;EnvJson;${serializeVSCodeOscMessage('{"A":"1","B":"x;y"}')};n\x07',
      );
      final shellEnv = addon.capabilities.get(
        TerminalCapability.shellEnvDetection,
      )!;
      expect(shellEnv.env.value, {'A': '1', 'B': 'x;y'});
      expect(shellEnv.env.isTrusted, isTrue);

      await writeP(
        xterm,
        '\x1b]633;EnvSingleStart;1;n\x07'
        '\x1b]633;EnvSingleEntry;C;3;n\x07'
        '\x1b]633;EnvSingleEnd;n\x07',
      );
      expect(shellEnv.env.value, {'C': '3'});
      expect(shellEnv.env.isTrusted, isTrue);
    });

    test('ignores sequences it does not know', () async {
      await setUpAddon();
      await writeP(xterm, '\x1b]633;Z\x07\x1b]1337;Foo=bar\x07');
      expect(addon.capabilities.items, [
        TerminalCapability.partialCommandDetection,
      ]);
    });
  });

  group('helpers', () {
    test('sanitizeCwd', () {
      expect(sanitizeCwd('"/a b"'), '/a b');
      expect(sanitizeCwd("'/a'"), '/a');
      expect(sanitizeCwd('c:\\foo'), 'c:\\foo');
      expect(sanitizeCwd('c:\\foo', isWindows: true), 'C:\\foo');
      expect(sanitizeCwd('/c:', isWindows: true), '/c:');
    });

    test('removeAnsiEscapeCodesFromPrompt', () {
      expect(removeAnsiEscapeCodesFromPrompt('\x1b[38;5;8m∙\x1b[0m '), '∙ ');
      expect(
        removeAnsiEscapeCodesFromPrompt(
          r'\[\e]0;title\a\]'
          '\x1b]0;t\x07\$ ',
        ),
        r'$ ',
      );
    });

    test('uriPath', () {
      expect(uriPath('file:///a%20b/c'), '/a b/c');
      expect(uriPath('file://host/a?q#f'), '/a');
      expect(uriPath('file:///a%zz'), '/a%zz');
    });
  });
}
