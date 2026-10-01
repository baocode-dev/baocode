// How fast the native scanner goes the way a tokenizer drives it: one
// OnigString per line, then findNextMatchSync from each match's end, over a
// scanner of 50 patterns like a TypeScript grammar's. Prints its timings.

@TestOn('mac-os || linux || windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/oniguruma/onig_lib_io.dart';

const _sources = [
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(import|export)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(?:(\bexport)\s+)?(?:(\bdeclare)\s+)?\b(?:(abstract)\s+)?\b(class)\b(?=\s*|/|\*)',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(?:(\bexport)\s+)?(?:(\bdeclare)\s+)?\b(interface)\b(?=\s*|/|\*)',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(?:(\bexport)\s+)?(?:(\bdeclare)\s+)?\b(type)\b\s+([_$[:alpha:]][_$[:alnum:]]*)\s*',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(?:(\bexport)\s+)?(?:(\bdeclare)\s+)?(?:(async)\s+)?(function\b)(?:\s*(\*))?(?:(?:\s+|(?<=\*))([_$[:alpha:]][_$[:alnum:]]*))?\s*',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(?:(\bexport)\s+)?(?:(\bdeclare)\s+)?\b(var|let)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))\s*',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(?:(\bexport)\s+)?(?:(\bdeclare)\s+)?\b(const(?!\s+enum\b))(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))\s*',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(break|continue|goto)\s+([_$[:alpha:]][_$[:alnum:]]*)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(break|continue|do|goto|while)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(return)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(if|else|switch|case|default)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(for)(?:\s+(await))?(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(try|catch|finally|throw)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(await)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(new)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(typeof|instanceof|in|of|keyof|delete|void)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(true|false|null|undefined|NaN|Infinity)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))',
  r'(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(this|super)\b(?!\$)',
  r'''(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(as)\s+(const)(?=\s*($|[;,:})\]]))''',
  r'\s*+(\/\*\*)(?!\/)',
  r'(\/\*)(?:\s*((@)internal)(?=\s|(\*\/)))?',
  r'(^[ \t]+)?((//)(?:\s*((@)internal)(?=\s|$))?)',
  r"'",
  r'"',
  r'([_$[:alpha:]][_$[:alnum:]]*)?(`)',
  r'(?<!\+\+|--)(?<=[=(:,\[?+!]|^return|[^\._$[:alnum:]]return|^case|[^\._$[:alnum:]]case|=>|&&|\|\||\*\/)\s*(\/)(?![\/*])(?=(?:[^\/\\\[\()]|\\.|\[([^\]\\]|\\.)+\]|\(([^\)\\]|\\.)+\))+\/([dgimsuy]+|(?<![\/\*])|(?=\/\*))(?!\s*[a-zA-Z0-9_$]))',
  r'(?x)(?<!\$)(?:(?:\b[0-9][0-9_]*(\.)[0-9][0-9_]*[eE][+-]?[0-9][0-9_]*(n)?\b)|(?:\b[0-9][0-9_]*(\.)[eE][+-]?[0-9][0-9_]*(n)?\b)|(?:\B(\.)[0-9][0-9_]*[eE][+-]?[0-9][0-9_]*(n)?\b)|(?:\b[0-9][0-9_]*[eE][+-]?[0-9][0-9_]*(n)?\b)|(?:\b[0-9][0-9_]*(\.)[0-9][0-9_]*(n)?\b)|(?:\b[0-9][0-9_]*(\.)(n)?\B)|(?:\B(\.)[0-9][0-9_]*(n)?\b)|(?:\b[0-9][0-9_]*(n)?(?!\.)))(?!\$)',
  r'\b(?<!\$)0(?:x|X)[0-9a-fA-F][0-9a-fA-F_]*(n)?\b(?!\$)',
  r'\b(?<!\$)0(?:b|B)[01][01_]*(n)?\b(?!\$)',
  r'\.\.\.',
  r'(?:\*|(?<!\()/|%|\+|-)=',
  r'\?\?=|&&=|\|\|=',
  r'(?:<<|>>>|>>)=',
  r'(?:\^|\||&)=',
  r'<<|>>>|>>',
  r'===|!==|==|!=',
  r'<=|>=|<>|<|>',
  r'(?<=[_$[:alnum:]])(\!)\s*(?:(/=)|(?:(/)(?![/*])))',
  r'\!|&&|\|\||\?\?',
  r'\&|~|\^|\|',
  r'\=',
  r'--',
  r'\+\+',
  r'%|\*|/|-|\+',
  r'(?:(\.)|(\?\.(?!\s*[[:digit:]])))\s*(?:(\#?[[:upper:]][_$[:digit:][:upper:]]*)(?![_$[:alnum:]])|(\#?[_$[:alpha:]][_$[:alnum:]]*))',
  r'([_$[:alpha:]][_$[:alnum:]]*)(?=\s*\()',
  r'([_$[:alpha:]][_$[:alnum:]]*)',
  r'\{',
  r'\(',
  r';',
];

const _lines = {
  'TypeScript':
      "    const response = await fetch(url, { method: 'POST', headers: "
      "{ 'Content-Type': 'application/json' }, body }); // retry 3x",
  'CJK and emoji':
      r'    const 消息 = format(`你好，${name} 👋`, count >= 10 ? "多" : "少");',
};

void main() {
  test('findNextMatchSync calls per second', () {
    const lib = NativeOnigLib();
    final scanner = lib.createOnigScanner(_sources);
    addTearDown(scanner.dispose);
    expect(_sources, hasLength(50));

    final lines = {
      ..._lines,
      // Past 1000 UTF-8 bytes: each regex on its own, with its cache.
      'long (1.2 KB)': List.filled(9, _lines['TypeScript']!).join(' '),
    };
    for (final MapEntry(key: name, value: line) in lines.entries) {
      var calls = 0;
      void tokenize() {
        final string = lib.createOnigString(line);
        var position = 0;
        while (position <= line.length) {
          final match = scanner.findNextMatchSync(string, position, 0);
          calls++;
          if (match == null) break;
          final end = match.captureIndices[0].end;
          position = end > position ? end : position + 1;
        }
        string.dispose();
      }

      for (var i = 0; i < 50; i++) {
        tokenize();
      }
      calls = 0;
      var lineCount = 0;
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 300) {
        tokenize();
        lineCount++;
      }
      watch.stop();
      final perCall = watch.elapsedMicroseconds / calls;
      // ignore: avoid_print
      print(
        'onig $name: ${(calls / watch.elapsedMicroseconds * 1e6).round()} '
        'calls/s, ${perCall.toStringAsFixed(2)}us/call, '
        '${calls ~/ lineCount} calls/line, '
        '${(watch.elapsedMicroseconds / lineCount).toStringAsFixed(1)}us/line',
      );
      expect(calls, greaterThan(0));
    }
  });
}
