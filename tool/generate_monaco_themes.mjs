// Extract pinned standalone theme data for Flutter's Dart token theme port.
// Usage: node --experimental-transform-types tool/generate_monaco_themes.mjs <vscode-checkout> <output.json>
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const [root, output] = process.argv.slice(2);
if (!root || !output) throw new Error('Expected pinned VS Code checkout and output path');
if (execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim() !== revision) {
  throw new Error(`Expected VS Code revision ${revision}`);
}
const source = await readFile(join(root, 'src/vs/editor/standalone/common/themes.ts'), 'utf8');
const temporary = await mkdtemp(join(tmpdir(), 'baocode-monaco-themes-'));
try {
  await writeFile(join(temporary, 'package.json'), '{"type":"module"}');
  const symbols = [
    'editorActiveIndentGuide1', 'editorIndentGuide1', 'editorBackground',
    'editorForeground', 'editorInactiveSelection', 'editorSelectionHighlight',
  ];
  const declarations = symbols.map(name => `const ${name} = '${name}';`).join('\n');
  const loadable = source.replace(/^import .*;$/gm, '');
  await writeFile(join(temporary, 'themes.ts'), declarations + '\n' + loadable);
  const themes = await import(pathToFileURL(join(temporary, 'themes.ts')));
  const result = {
    revision,
    attribution: 'Copyright (c) Microsoft Corporation. Licensed under the MIT License; see lib/ide/editor/monaco/LICENSE.txt.',
    themes: { vs: themes.vs, 'vs-dark': themes.vs_dark,
      'hc-black': themes.hc_black, 'hc-light': themes.hc_light },
  };
  await writeFile(output, JSON.stringify(result, null, 2) + '\n');
} finally {
  await rm(temporary, { recursive: true, force: true });
}
