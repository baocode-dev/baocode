// The native Oniguruma scanner against vscode-oniguruma's own tests and the
// Oniguruma features grammars lean on.
//
// The first group is adapted from vscode-oniguruma 1.7.0
// (716aeaa229e4ae2e3b0057377b55743e9a3e995b): src/test/index.test.ts (MIT,
// see native/oniguruma/LICENSE.txt).

@TestOn('mac-os || linux || windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/oniguruma/onig_lib.dart';
import 'package:bao_editor/textmate/oniguruma/onig_lib_io.dart'
    hide loadNativeOnigLib;
import 'package:bao_editor/textmate/vscode_textmate/onig_lib.dart';

/// vscode-oniguruma's result, as its tests compare it.
Map<String, Object>? _plain(IOnigMatch? match) => match == null
    ? null
    : {
        'index': match.index,
        'captureIndices': [
          for (final capture in match.captureIndices)
            {
              'start': capture.start,
              'end': capture.end,
              'length': capture.length,
            },
        ],
      };

Map<String, Object> _match(int index, List<(int, int)> captures) => {
  'index': index,
  'captureIndices': [
    for (final (start, end) in captures)
      {'start': start, 'end': end, 'length': end - start},
  ],
};

/// A register of a group that did not take part: vscode-oniguruma reads its
/// -1 as an unsigned 32-bit int, and passes it through on an ASCII string.
const _unmatched = 0xffffffff;

final _lib = NativeOnigLib();

OnigScanner _scanner(List<String> sources) {
  final scanner = _lib.createOnigScanner(sources);
  addTearDown(scanner.dispose);
  return scanner;
}

OnigString _string(String content) {
  final string = _lib.createOnigString(content);
  addTearDown(string.dispose);
  return string;
}

/// vscode-oniguruma's `findNextMatchSync` on a plain string.
Map<String, Object>? _find(
  OnigScanner scanner,
  String content,
  int startPosition, [
  int options = FindOption.none,
]) {
  final string = _lib.createOnigString(content);
  try {
    return _plain(scanner.findNextMatchSync(string, startPosition, options));
  } finally {
    string.dispose();
  }
}

void main() {
  test('loadNativeOnigLib finds the native library', () {
    expect(loadNativeOnigLib(), isA<NativeOnigLib>());
  });

  group('vscode-oniguruma', () {
    test('simple1', () {
      final scanner = _scanner(['ell', 'wo']);
      final s = _string('Hello world!');
      expect(
        _plain(scanner.findNextMatchSync(s, 0, FindOption.none)),
        _match(0, [(1, 4)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(s, 2, FindOption.none)),
        _match(1, [(6, 8)]),
      );
    });

    test('simple2', () {
      final scanner = _scanner(['a', 'b', 'c']);
      expect(_find(scanner, 'x', 0), isNull);
      expect(_find(scanner, 'xxaxxbxxc', 0), _match(0, [(2, 3)]));
      expect(_find(scanner, 'xxaxxbxxc', 4), _match(1, [(5, 6)]));
      expect(_find(scanner, 'xxaxxbxxc', 7), _match(2, [(8, 9)]));
      expect(_find(scanner, 'xxaxxbxxc', 9), isNull);
    });

    test('unicode1', () {
      final scanner1 = _scanner(['1', '2']);
      expect(_find(scanner1, 'ab…cde21', 5), _match(1, [(6, 7)]));

      final scanner2 = _scanner(['"']);
      expect(_find(scanner2, '{"…": 1}', 1), _match(0, [(1, 2)]));
    });

    test('unicode2', () {
      final scanner = _scanner(['Y', 'X']);
      expect(_find(scanner, 'a💻bYX', 0), _match(0, [(4, 5)]));
      expect(_find(scanner, 'a💻bYX', 1), _match(0, [(4, 5)]));
      expect(_find(scanner, 'a💻bYX', 3), _match(0, [(4, 5)]));
      expect(_find(scanner, 'a💻bYX', 4), _match(0, [(4, 5)]));
      expect(_find(scanner, 'a💻bYX', 5), _match(1, [(5, 6)]));
    });

    test('unicode3', () {
      final scanner = _scanner(['Возврат']);
      expect(_find(scanner, 'Возврат long_var_name;', 0), _match(0, [(0, 7)]));
    });

    test('unicode4', () {
      final scanner = _scanner(['X']);
      final high = 'X${String.fromCharCode(0xd83c)}X';
      expect(_find(scanner, high, 0), _match(0, [(0, 1)]));
      expect(_find(scanner, high, 1), _match(0, [(2, 3)]));
      expect(_find(scanner, high, 2), _match(0, [(2, 3)]));
      final low = 'X${String.fromCharCode(0xdfff)}X';
      expect(_find(scanner, low, 0), _match(0, [(0, 1)]));
      expect(_find(scanner, low, 1), _match(0, [(2, 3)]));
      expect(_find(scanner, low, 2), _match(0, [(2, 3)]));
      // These are actually valid, just testing the min & max
      expect(
        _find(
          scanner,
          'X${String.fromCharCode(0xd800)}${String.fromCharCode(0xdc00)}X',
          2,
        ),
        _match(0, [(3, 4)]),
      );
      expect(
        _find(
          scanner,
          'X${String.fromCharCode(0xdbff)}${String.fromCharCode(0xdfff)}X',
          2,
        ),
        _match(0, [(3, 4)]),
      );
    });

    test('out of bounds', () {
      final scanner = _scanner(['X']);
      expect(_find(scanner, 'X💻X', -1000), _match(0, [(0, 1)]));
      expect(_find(scanner, 'X💻X', 1000), isNull);
    });

    test(r'regex with \G', () {
      final str = _string('first-and-second');
      final scanner = _scanner([r'\G-and']);
      expect(scanner.findNextMatchSync(str, 0, FindOption.none), isNull);
      expect(
        _plain(scanner.findNextMatchSync(str, 5, FindOption.none)),
        _match(0, [(5, 9)]),
      );
    });

    test('kkos/oniguruma#192', () {
      final str = _string('    while (i < len && f(array[i]))');
      final scanner = _scanner([
        '(?x)\n'
            r'  (?<!\+\+|--)(?<=[({\[,?=>:*]|&&|\|\||\?|\*\/|^await|[^\._$[:alnum:]]await|^return|[^\._$[:alnum:]]return|^default|[^\._$[:alnum:]]default|^yield|[^\._$[:alnum:]]yield|^)\s*'
            '\n'
            r'  (?!<\s*[_$[:alpha:]][_$[:alnum:]]*((\s+extends\s+[^=>])|,)) # look ahead is not type parameter of arrow'
            '\n'
            r'  (?=(<)\s*(?:([_$[:alpha:]][-_$[:alnum:].]*)(?<!\.|-)(:))?((?:[a-z][a-z0-9]*|([_$[:alpha:]][-_$[:alnum:].]*))(?<!\.|-))(?=((<\s*)|(\s+))(?!\?)|\/?>))',
      ]);
      expect(scanner.findNextMatchSync(str, 0, FindOption.none), isNull);
    });

    test('FindOption.NotBeginPosition', () {
      final str = _string('first-and-second');
      final scanner = _scanner([r'\G-and']);
      expect(
        _plain(scanner.findNextMatchSync(str, 5, FindOption.none)),
        _match(0, [(5, 9)]),
      );
      expect(
        scanner.findNextMatchSync(str, 5, FindOption.notBeginPosition),
        isNull,
      );
    });

    test('FindOption.NotBeginString', () {
      final str = _string('first-and-first');
      final scanner = _scanner([r'\Afirst']);
      expect(scanner.findNextMatchSync(str, 10, FindOption.none), isNull);
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(0, 5)]),
      );
      expect(
        scanner.findNextMatchSync(str, 0, FindOption.notBeginString),
        isNull,
      );
    });

    test('FindOption.NotEndString', () {
      final str = _string('first-and-first');
      final scanner = _scanner([r'first\z']);
      expect(
        _plain(scanner.findNextMatchSync(str, 10, FindOption.none)),
        _match(0, [(10, 15)]),
      );
      expect(
        scanner.findNextMatchSync(str, 10, FindOption.notEndString),
        isNull,
      );
    });
  });

  group('anchors and options', () {
    test(r'\G anchors at the start position only', () {
      final scanner = _scanner([r'\G\w+']);
      final str = _string('ab cd');
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(0, 2)]),
      );
      expect(scanner.findNextMatchSync(str, 2, FindOption.none), isNull);
      expect(
        _plain(scanner.findNextMatchSync(str, 3, FindOption.none)),
        _match(0, [(3, 5)]),
      );
      expect(
        scanner.findNextMatchSync(str, 3, FindOption.notBeginPosition),
        isNull,
      );
    });

    test(r'\G after a surrogate pair counts in UTF-16', () {
      final scanner = _scanner([r'\G(b)']);
      final str = _string('a😀b');
      expect(
        _plain(scanner.findNextMatchSync(str, 3, FindOption.none)),
        _match(0, [(3, 4), (3, 4)]),
      );
      expect(scanner.findNextMatchSync(str, 1, FindOption.none), isNull);
    });

    test('options combine', () {
      final scanner = _scanner([r'\A\G', r'\z']);
      final str = _string('abc');
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(0, 0)]),
      );
      expect(
        _plain(
          scanner.findNextMatchSync(
            str,
            0,
            FindOption.notBeginString | FindOption.notBeginPosition,
          ),
        ),
        _match(1, [(3, 3)]),
      );
      expect(
        scanner.findNextMatchSync(
          str,
          0,
          FindOption.notBeginString | FindOption.notEndString,
        ),
        isNull,
      );
    });

    test('an ASCII string does not clamp out-of-range positions', () {
      // vscode-oniguruma maps offsets only when UTF-8 and UTF-16 differ.
      final scanner = _scanner(['X']);
      expect(_find(scanner, 'XyX', -1), isNull);
      expect(_find(scanner, 'XyX', 4), isNull);
      expect(_find(scanner, 'XyX', 3), isNull);
      expect(_find(scanner, 'XyX', 2), _match(0, [(2, 3)]));
    });

    test('(?i) folds case, Unicode included', () {
      final scanner = _scanner(['(?i)hello', '(?i)ÄÖ']);
      expect(_find(scanner, 'Say HeLLo', 0), _match(0, [(4, 9)]));
      expect(_find(scanner, 'x äö', 0), _match(1, [(2, 4)]));
      expect(_find(scanner, 'hallo', 0), isNull);
    });
  });

  group('Unicode offsets', () {
    test('captures around emoji are UTF-16 offsets', () {
      final scanner = _scanner([r'(\S+)\s+(😀+)(!)']);
      expect(
        _find(scanner, '😀x 😀😀! end', 0),
        _match(0, [(0, 9), (0, 3), (4, 8), (8, 9)]),
      );
      expect(
        _find(scanner, '😀x 😀😀! end', 2),
        _match(0, [(2, 9), (2, 3), (4, 8), (8, 9)]),
      );
    });

    test('captures in CJK text are UTF-16 offsets', () {
      final scanner = _scanner([r'(漢字)(\p{Hiragana}+)']);
      expect(
        _find(scanner, 'ab 漢字かな 漢字', 0),
        _match(0, [(3, 7), (3, 5), (5, 7)]),
      );
    });

    test(r'\w, \b and [[:alpha:]] know CJK', () {
      final scanner = _scanner([r'\b\w+\b', r'[[:alpha:]]+']);
      expect(_find(scanner, '  漢字かな abc', 0), _match(0, [(2, 6)]));
      // No word boundary inside 漢字: the POSIX class matches first.
      expect(_find(scanner, '  漢字かな abc', 3), _match(1, [(3, 6)]));
      expect(_find(scanner, '。。한국어。', 0), _match(0, [(2, 5)]));
    });

    test('a group that did not take part', () {
      final scanner = _scanner(['(a)|(b)']);
      // On an ASCII string, the unsigned -1 passes through.
      expect(
        _find(scanner, 'xb', 0),
        _match(0, [(1, 2), (_unmatched, _unmatched), (1, 2)]),
      );
      // Otherwise it is past the end, and so the string's length.
      expect(_find(scanner, 'éb', 0), _match(0, [(1, 2), (2, 2), (1, 2)]));
    });

    test('lone surrogates in the middle of a match', () {
      final lone = String.fromCharCode(0xd83d);
      final scanner = _scanner(['a(.)b']);
      expect(_find(scanner, 'xa${lone}b', 0), _match(0, [(1, 4), (2, 3)]));
    });
  });

  group('Oniguruma features', () {
    test('atomic groups and possessive quantifiers do not backtrack', () {
      final scanner = _scanner(['(?>a+)a', 'a++a', 'a+a']);
      expect(_find(scanner, 'aaa', 0), _match(2, [(0, 3)]));
      expect(_find(_scanner(['(?>a+)a', 'a++a']), 'aaa', 0), isNull);
      expect(_find(_scanner(['(?>a|ab)c']), 'abc', 0), isNull);
    });

    test('lookbehind', () {
      final scanner = _scanner([r'(?<=\$)\d+', r'(?<!x)y']);
      expect(_find(scanner, 'xy cost \$42', 0), _match(0, [(9, 11)]));
      expect(_find(scanner, 'xy zy', 0), _match(1, [(4, 5)]));
      // A lookbehind sees text before the start position.
      expect(_find(scanner, '\$42', 1), _match(0, [(1, 3)]));
    });

    test('backreferences', () {
      final scanner = _scanner([r'(\w)\1']);
      expect(_find(scanner, 'abccd', 0), _match(0, [(2, 4), (2, 3)]));
      final named = _scanner([r'''(?<q>['"]).*?\k<q>''']);
      expect(
        _find(named, '''say "it's" ok''', 0),
        _match(0, [(4, 10), (4, 5)]),
      );
    });

    test('named groups still number every group', () {
      final scanner = _scanner([r'(?<word>\w+)-(\d+)']);
      expect(_find(scanner, 'ab-12', 0), _match(0, [(0, 5), (0, 2), (3, 5)]));
    });

    test('strict: an invalid pattern throws Oniguruma\'s message', () {
      const strict = NativeOnigLib(strict: true);
      void expectError(List<String> sources, String message) => expect(
        () => strict.createOnigScanner(sources),
        throwsA(isA<OnigError>().having((e) => e.message, 'message', message)),
      );
      expectError(['a', '('], 'end pattern with unmatched parenthesis');
      expectError(['[a'], 'premature end of char-class');
      expectError(['*a', '('], 'target of repeat operator is not specified');
      // A capture in a negative lookbehind.
      expectError([r'(?<!a(b))c'], 'invalid pattern in look-behind');
      expectError([r'\k<nope>'], 'undefined name <nope> reference');
      expect(
        () => strict.createOnigScanner(['a', '[', '(']),
        throwsA(isA<OnigError>().having((e) => e.pattern, 'pattern', '[')),
      );
    });

    test('an invalid pattern makes a scanner, as in VS Code', () {
      // vscode-oniguruma 1.7.0's WebAssembly never throws (see
      // native/oniguruma/bao_onig.c).
      final scanner = _scanner(['a', '(', 'b']) as NativeOnigScanner;
      expect(scanner.error?.message, 'end pattern with unmatched parenthesis');
      expect(scanner.error?.pattern, '(');
      // No regset: nothing under 1000 bytes matches.
      expect(_find(scanner, 'xab', 0), isNull);
      // Past it, the valid patterns do, and the invalid one never.
      final long = '${'x' * 1100}ab';
      expect(_find(scanner, long, 0), _match(0, [(1100, 1101)]));
      expect(_find(scanner, long, 1101), _match(2, [(1101, 1102)]));
      expect((_scanner(['a']) as NativeOnigScanner).error, isNull);
    });

    test('a scanner of only invalid patterns, as in VS Code', () {
      final invalid = _scanner(['(', '[']);
      final long = '${'x' * 1100}ab';
      // Whether it matches empty in a short string depends on the options
      // of the last search of an invalid pattern, of any scanner.
      _find(invalid, long, 0);
      expect(_find(invalid, 'xab', 1), _match(0, [(1, 1)]));
      expect(
        _find(invalid, 'xab', 1, FindOption.notBeginPosition),
        _match(0, [(1, 1)]),
      );
      expect(_find(invalid, 'xab', 4), isNull);
      expect(_find(_scanner(['[']), 'xab', 3), _match(0, [(3, 3)]));
      _find(invalid, long, 0, FindOption.notBeginString);
      expect(_find(invalid, 'xab', 1), isNull);
      expect(_find(_scanner(['[']), 'xab', 3), isNull);
      _find(invalid, long, 5);
      expect(_find(invalid, 'xab', 2), _match(0, [(2, 2)]));
    });

    test('(?L) is refused a regset, as in VS Code', () {
      final scanner = _scanner(['(?L)a|ab', 'b']) as NativeOnigScanner;
      expect(scanner.error, isNull);
      expect(_find(scanner, 'xab', 0), isNull);
      expect(_find(scanner, '${'x' * 1100}ab', 0), _match(0, [(1100, 1101)]));
    });
  });

  group('the scanner', () {
    test('the earliest match wins, a tie goes to the lowest index', () {
      final scanner = _scanner(['c', 'b', 'ab', 'a', 'x?']);
      expect(_find(scanner, 'zzabc', 0), _match(4, [(0, 0)]));
      final nonEmpty = _scanner(['c', 'b', 'ab', 'a']);
      expect(_find(nonEmpty, 'zzabc', 0), _match(2, [(2, 4)]));
      expect(_find(nonEmpty, 'zzabc', 3), _match(1, [(3, 4)]));
      // Past 1000 UTF-8 bytes each regex searches on its own, with a cache.
      final long = '${'z' * 1200}abc';
      expect(_find(nonEmpty, long, 0), _match(2, [(1200, 1202)]));
      expect(_find(nonEmpty, long, 1201), _match(1, [(1201, 1202)]));
    });

    test('no patterns never match', () {
      final scanner = _scanner([]);
      expect(_find(scanner, 'abc', 0), isNull);
      expect(_find(scanner, 'a' * 2000, 0), isNull);
    });

    test('the search cache follows positions on one long string', () {
      final scanner = _scanner(['needle', r'\d+']);
      final text = '${'.' * 1500}needle${'.' * 100}42${'.' * 100}needle';
      final str = _string(text);
      final second = 1500 + 6 + 100;
      final third = second + 2 + 100;
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(1500, 1506)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(str, 10, FindOption.none)),
        _match(0, [(1500, 1506)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(str, 1506, FindOption.none)),
        _match(1, [(second, second + 2)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(str, second + 1, FindOption.none)),
        _match(1, [(second + 1, second + 2)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(str, second + 2, FindOption.none)),
        _match(0, [(third, third + 6)]),
      );
      expect(
        scanner.findNextMatchSync(str, third + 1, FindOption.none),
        isNull,
      );
      // Going back searches again.
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(1500, 1506)]),
      );
    });

    test('the search cache does not carry over to another string', () {
      final scanner = _scanner(['needle']);
      final a = _string('${'.' * 1500}needle');
      final b = _string('${'.' * 1200}needle${'.' * 300}');
      expect(
        _plain(scanner.findNextMatchSync(a, 0, FindOption.none)),
        _match(0, [(1500, 1506)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(b, 0, FindOption.none)),
        _match(0, [(1200, 1206)]),
      );
      expect(scanner.findNextMatchSync(b, 1201, FindOption.none), isNull);
      expect(
        _plain(scanner.findNextMatchSync(a, 1201, FindOption.none)),
        _match(0, [(1500, 1506)]),
      );
      // Nor to a new string where a disposed one was.
      for (final at in [1300, 1400, 1100]) {
        final c = _lib.createOnigString(
          '${'.' * at}needle${'.' * (1500 - at)}',
        );
        expect(
          _plain(scanner.findNextMatchSync(c, 0, FindOption.none)),
          _match(0, [(at, at + 6)]),
        );
        c.dispose();
      }
    });

    test('the search cache keys on the options', () {
      final scanner = _scanner([r'\Aab|ab\z']);
      final str = _string('ab${'.' * 1200}ab');
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(0, 2)]),
      );
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.notBeginString)),
        _match(0, [(1202, 1204)]),
      );
      expect(
        scanner.findNextMatchSync(
          str,
          0,
          FindOption.notBeginString | FindOption.notEndString,
        ),
        isNull,
      );
    });

    test(r'\G is never cached', () {
      final scanner = _scanner([r'\G\.']);
      final str = _string('${'.' * 1100}x.');
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(0, 1)]),
      );
      expect(scanner.findNextMatchSync(str, 1100, FindOption.none), isNull);
      expect(
        _plain(scanner.findNextMatchSync(str, 1101, FindOption.none)),
        _match(0, [(1101, 1102)]),
      );
    });

    test('long non-ASCII lines map offsets both ways', () {
      final scanner = _scanner(['(é+)(😀)']);
      final text = '${'中' * 500}ééé😀${'x' * 10}';
      expect(
        _find(scanner, text, 0),
        _match(0, [(500, 505), (500, 503), (503, 505)]),
      );
      expect(
        _find(scanner, text, 502),
        _match(0, [(502, 505), (502, 503), (503, 505)]),
      );
    });

    test('DebugCall logs and finds the same match', () {
      final scanner = _scanner(['b', 'a']);
      expect(
        _find(scanner, 'xab', 0, FindOption.debugCall),
        _match(1, [(1, 2)]),
      );
    });

    test('an OnigString of another library is searched as its content', () {
      final scanner = _scanner(['b']);
      expect(
        _plain(scanner.findNextMatchSync(_PlainString('ab'), 0, 0)),
        _match(0, [(1, 2)]),
      );
    });
  });

  group('dispose', () {
    test('is idempotent', () {
      final scanner = _lib.createOnigScanner(['a']);
      final str = _lib.createOnigString('a');
      expect(
        _plain(scanner.findNextMatchSync(str, 0, FindOption.none)),
        _match(0, [(0, 1)]),
      );
      str.dispose();
      str.dispose();
      disposeOnigString(str);
      scanner.dispose();
      scanner.dispose();
      expect(str.disposed, isTrue);
      expect(scanner.disposed, isTrue);
    });

    test('forbids use after', () {
      final scanner = _lib.createOnigScanner(['a']);
      final str = _lib.createOnigString('a');
      str.dispose();
      expect(
        () => scanner.findNextMatchSync(str, 0, FindOption.none),
        throwsStateError,
      );
      scanner.dispose();
      expect(
        () => scanner.findNextMatchSync(_string('a'), 0, FindOption.none),
        throwsStateError,
      );
    });

    test('empty strings and patterns', () {
      final scanner = _scanner(['', r'\z']);
      expect(_find(scanner, '', 0), _match(0, [(0, 0)]));
    });
  });
}

class _PlainString implements OnigString {
  _PlainString(this.content);

  @override
  final String content;

  @override
  void dispose() {}
}
