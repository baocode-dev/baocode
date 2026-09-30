// Runs vscode-oniguruma 1.7.0 itself (its published WebAssembly), not the Dart
// port, to create the parity data onig_parity_test.dart checks against.
// Usage:
//   npm pack vscode-oniguruma@1.7.0 && tar -xzf vscode-oniguruma-1.7.0.tgz
//   node test/ide/editor/textmate/oniguruma/vscode_oniguruma_parity.mjs \
//     package test/ide/editor/textmate/oniguruma/vscode_oniguruma_parity.json
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';

const [root, output] = process.argv.slice(2);
if (!root || !output) throw new Error('Expected the package folder and output JSON path');
const manifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
if (manifest.name !== 'vscode-oniguruma' || manifest.version !== '1.7.0') {
  throw new Error('Expected vscode-oniguruma 1.7.0');
}
const onig = createRequire(import.meta.url)(resolve(root, 'release/main.js'));
await onig.loadWASM(await readFile(join(root, 'release/onig.wasm')));

let state = 0x6687;
const random = () => {
  // mulberry32
  state = (state + 0x6d2b79f5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (list) => list[Math.floor(random() * list.length)];
const int = (min, max) => min + Math.floor(random() * (max - min + 1));

// Patterns of the kind TextMate grammars use, and the Oniguruma features
// they lean on.
const patterns = [
  String.raw`\b(?:if|else|for|while|return|const|let)\b`,
  String.raw`(?<![_$[:alnum:]])(?:(?<=\.\.\.)|(?<!\.))(break|case|continue|default|do|else|finally|if|return|switch|throw|try|while)(?![_$[:alnum:]])(?:(?=\.\.\.)|(?!\.))`,
  String.raw`"(?:[^"\\]|\\.)*"`,
  String.raw`'(?:[^'\\]|\\.)*'`,
  String.raw`(")`,
  String.raw`(\\.)`,
  String.raw`//.*$`,
  String.raw`(//).*$\n?`,
  String.raw`/\*`,
  String.raw`\*/`,
  String.raw`\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b`,
  String.raw`\b0[xX]\h+\b`,
  String.raw`[_$[:alpha:]][_$[:alnum:]]*`,
  String.raw`\s+`,
  String.raw`^\s*(#)\s*(\w+)`,
  String.raw`$`,
  String.raw`^`,
  String.raw`\G`,
  String.raw`\G\s*`,
  String.raw`\G(\w+)`,
  String.raw`(?=\S)`,
  String.raw`(?!\G)`,
  String.raw`(\w+)\s*(\()`,
  String.raw`(?<=\.)\s*([_$[:alpha:]][_$[:alnum:]]*)`,
  String.raw`(?i)\bselect\b`,
  String.raw`(?i)[äöü]+`,
  String.raw`(?x) \b ( \d+ ) \s* # a number`,
  String.raw`\p{Han}+`,
  String.raw`\p{Hiragana}+`,
  String.raw`\p{L}+`,
  String.raw`\p{Emoji_Presentation}`,
  String.raw`\X`,
  String.raw`\R`,
  String.raw`\h+`,
  String.raw`\w+`,
  String.raw`\W+`,
  String.raw`\b`,
  String.raw`\B.`,
  String.raw`[[:punct:]]+`,
  String.raw`[[:upper:]][[:lower:]]*`,
  String.raw`(a)|(b)`,
  String.raw`(?<n>x)?y`,
  String.raw`(\w)\1`,
  String.raw`(?<q>['"]).*?\k<q>`,
  String.raw`(?>\w+)\d`,
  String.raw`\w++\d`,
  String.raw`o{2,3}+`,
  String.raw`\A`,
  String.raw`\A\w+`,
  String.raw`\z`,
  String.raw`\Z`,
  String.raw`\w+\z`,
  String.raw`(?<=^|\s)-{2,}`,
  String.raw`(?<!\\)\$\{`,
  String.raw`\}`,
  String.raw`[^\x{0}-\x{7F}]+`,
  String.raw`[\x{1F600}-\x{1F64F}]`,
  String.raw`\x{1D4B3}`,
  String.raw`.`,
  String.raw`..`,
  String.raw`.+?`,
  String.raw`(?m).+`,
  String.raw`foo\Kbar`,
  String.raw`(?~abc)`,
  String.raw`(x)?(?(1)a|b)`,
  String.raw`\y`,
  String.raw`(?<=[\p{Han}])\p{Hiragana}`,
  String.raw`(?<!\w)é\w*`,
  String.raw`[\s\S]{3}`,
  String.raw`(((a)|(b))+)`,
  String.raw`(?:(\()|(\)))`,
  String.raw`\t`,
  String.raw`\n`,
  String.raw`\r?\n`,
  String.raw`\x00`,
  String.raw``,
  String.raw`x*`,
  // Valid, but refused a regset.
  String.raw`(?L)a|ab`,
];

// Patterns Oniguruma rejects, which vscode-oniguruma's WebAssembly takes all
// the same.
const invalid = [
  String.raw`(`,
  String.raw`[a`,
  String.raw`*a`,
  String.raw`(?<!a(b))c`,
  String.raw`\p{Nope}`,
  String.raw`(?P<x>a)`,
  String.raw`a{2,1}`,
  String.raw`)`,
  String.raw`[b-a]`,
  String.raw`\x{110000}`,
  String.raw`\k<nope>`,
  String.raw`(?C)(a)`,
];

const fragments = [
  'const x = 42;', 'foo.bar(baz)', '"str\\"ing"', "'c'", '// comment', '/* block */',
  '  ', '\t', 'if (a && b) return;', 'SELECT * FROM t', 'select', '0x1F', '3.14e-2',
  '${x}', '--', '...', '\\', '_$id9', 'foobar', 'xy', 'aab', 'abc', 'ooo', 'Hello',
  'é', 'ñandú', 'Äöü', 'Возврат', '漢字', 'かな', '漢字かな', '한국어', '。', '😀', '👨‍👩‍👧',
  '💻', 'é', ' ', 'Ω', '‍', '𝒳', '\ud83d', '\ude00', '\udbff', '\ud800',
  '\r', '\u0000', '(', ')', '#include', 'return', '...else', '.if',
];

// Long: past the 1000 UTF-8 bytes where onig.cc stops using the regset.
function text(long) {
  let result = '';
  const minimum = long ? int(1000, 1100) : int(0, 60);
  while ((long ? Buffer.byteLength(result) : result.length) < minimum) {
    result += pick(fragments) + (random() < 0.3 ? ' ' : '');
  }
  if (random() < 0.3) result += '\n';
  return result;
}

function capture(match) {
  if (match == null) return null;
  const result = [match.index];
  for (const { start, end, length } of match.captureIndices) {
    if (length !== end - start) throw new Error('Unexpected length');
    result.push(start, end);
  }
  return result;
}

const options = [0, 0, 0, 1, 2, 4, 1 | 4, 1 | 2 | 4];

function session(sources, texts, randomCalls) {
  let scanner;
  try {
    scanner = new onig.OnigScanner(sources);
  } catch (error) {
    return { patterns: sources, error: error.message };
  }
  const strings = texts.map((t) => new onig.OnigString(t));
  const calls = [];
  const results = [];
  const find = (which, start, option) => {
    const match = scanner.findNextMatchSync(strings[which], start, option);
    calls.push([which, start, option]);
    results.push(capture(match));
    return match;
  };
  for (let round = 0; round < 2; round++) {
    for (let which = 0; which < texts.length; which++) {
      // As a tokenizer goes along a line.
      const option = round === 0 ? 0 : pick(options);
      let position = 0;
      for (let step = 0; step < (round === 0 ? 20 : 8) && position <= texts[which].length; step++) {
        const match = find(which, position, option);
        if (match == null) break;
        const end = match.captureIndices[0].end;
        position = end > position ? end : position + 1;
      }
    }
  }
  for (let i = 0; i < randomCalls; i++) {
    const which = int(0, texts.length - 1);
    const length = texts[which].length;
    const start = random() < 0.05 ? pick([-1000, -1, 2 ** 31 + 5, 2 ** 32 + 1]) : int(-2, length + 2);
    find(which, start, pick(options));
  }
  for (const s of strings) s.dispose();
  scanner.dispose();
  return { patterns: sources, texts, calls, results };
}

const sessions = [];
for (const source of invalid) {
  for (const sources of [[source], ['a', source], [source, 'a', source], ['\\w', source, 'b']]) {
    sessions.push(session(sources, [text(false), text(true)], 6));
  }
}
for (let i = 0; i < 200; i++) {
  const sources = Array.from({ length: int(1, 8) }, () => pick(patterns));
  const long = random() < 0.2;
  const texts = Array.from({ length: random() < 0.3 ? 2 : 1 }, () => text(long));
  sessions.push(session(sources, texts, 8));
}
// A grammar's worth of patterns in one scanner.
for (let i = 0; i < 6; i++) sessions.push(session(patterns, [text(i % 2 === 0), text(false)], 20));

await writeFile(output, JSON.stringify({ vscodeOniguruma: '1.7.0', sessions }) + '\n');
