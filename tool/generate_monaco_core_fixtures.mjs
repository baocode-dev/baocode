// Runs the pinned upstream TypeScript, not the Dart port, to create parity data.
// Usage: node --experimental-transform-types tool/generate_monaco_core_fixtures.mjs <vscode-checkout> <output.json>
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const [root, output] = process.argv.slice(2);
if (!root || !output) throw new Error('Expected VS Code checkout and output JSON path');
if (execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim() !== revision) {
  throw new Error(`Expected VS Code revision ${revision}`);
}
const temporary = await mkdtemp(join(tmpdir(), 'monad-monaco-fixtures-'));
try {
  await writeFile(join(temporary, 'package.json'), '{"type":"module"}');
  for (const name of ['position', 'range', 'selection']) {
    const source = await readFile(join(root, 'src/vs/editor/common/core', `${name}.ts`), 'utf8');
    // Node's built-in TypeScript loader requires explicit type-only imports and
    // real .ts file extensions. No executable upstream logic is changed.
    const loadable = source
      .replace("import { IPosition, Position } from './position.js';", "import type { IPosition } from './position.ts';\nimport { Position } from './position.ts';")
      .replace("from './range.js'", "from './range.ts'");
    await writeFile(join(temporary, `${name}.ts`), loadable);
  }
  const { Position } = await import(pathToFileURL(join(temporary, 'position.ts')));
  const { Range } = await import(pathToFileURL(join(temporary, 'range.ts')));
  const { Selection, SelectionDirection } = await import(pathToFileURL(join(temporary, 'selection.ts')));
  let state = 0x6687;
  const next = () => ((state = Math.imul(state, 1664525) + 1013904223 >>> 0) % 30) - 3;
  const coordinates = Array.from({ length: 64 }, () => [next(), next(), next(), next()]);
  coordinates.push([2147483648, 4294967296, 1, 1], [0, -1, 2147483647, 2147483648]);
  const position = coordinates.map(([line, column, otherLine, otherColumn]) => {
    const a = new Position(line, column), b = new Position(otherLine, otherColumn);
    return {
      input: [line, column, otherLine, otherColumn],
      equals: a.equals(b), before: a.isBefore(b), beforeOrEqual: a.isBeforeOrEqual(b),
      compare: Position.compare(a, b), delta: a.delta(-2, 3), withPosition: a.with(otherLine),
      display: a.toString(),
    };
  });
  const range = coordinates.map((input, i) => {
    const a = new Range(...input), b = new Range(...coordinates[(i + 1) % coordinates.length]);
    return {
      input, other: coordinates[(i + 1) % coordinates.length], normalized: a,
      empty: a.isEmpty(), contains: a.containsRange(b), strictContains: a.strictContainsRange(b),
      union: a.plusRange(b), intersection: a.intersectRanges(b),
      touching: Range.areIntersectingOrTouching(a, b), intersecting: Range.areIntersecting(a, b),
      onlyIntersecting: Range.areOnlyIntersecting(a, b),
      compareStarts: Range.compareRangesUsingStarts(a, b), compareEnds: Range.compareRangesUsingEnds(a, b),
      display: a.toString(),
    };
  });
  const selection = coordinates.map(input => {
    const a = new Selection(...input);
    return {
      input, value: a, direction: a.getDirection(),
      changeStart: a.setStartPosition(2, 3), changeEnd: a.setEndPosition(4, 5),
      fromRangeReverse: Selection.fromRange(a, SelectionDirection.RTL), display: a.toString(),
    };
  });
  await writeFile(output, JSON.stringify({
    revision,
    attribution: 'Copyright (c) Microsoft Corporation. Licensed under the MIT License; see lib/ide/editor/monaco/LICENSE.txt.',
    position, range, selection,
  }, null, 2) + '\n');
} finally {
  await rm(temporary, { recursive: true, force: true });
}
