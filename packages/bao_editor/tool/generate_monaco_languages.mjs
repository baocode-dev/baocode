// Extract the pinned Monaco language data; no JavaScript runs in the Flutter app.
// Usage: node --experimental-transform-types tool/generate_monaco_languages.mjs <monaco-checkout> <output-directory>
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm, stat, writeFile, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const revision = 'd61824269f1377111d34306e4a47172327777083';
const [root, output] = process.argv.slice(2);
if (!root || !output) throw new Error('Expected Monaco checkout and output directory');
if (execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim() !== revision) {
  throw new Error(`Expected Monaco revision ${revision}`);
}
const source = join(root, 'src/languages/definitions');
const temporary = await mkdtemp(join(tmpdir(), 'baocode-monaco-grammars-'));
try {
  await writeFile(join(temporary, 'package.json'), '{"type":"module"}');
  const names = (await readdir(source, { withFileTypes: true }))
    .filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  for (const name of names) {
    const sourceFile = join(source, name, `${name}.ts`);
    try { await stat(sourceFile); } catch { continue; }
    let contents = await readFile(sourceFile, 'utf8');
    contents = contents.replaceAll("import { languages } from '../../../editor';", [
      '// Standalone runtime values of Monaco languages.IndentAction.',
      'const languages = { IndentAction: { None: 0, Indent: 1, IndentOutdent: 2, Outdent: 3 } };',
    ].join('\n'));
    contents = contents.replaceAll(/from '(\.\.\/[^']+)'/g, (match, path) =>
      match.replace(path, `${path}.ts`));
    await mkdir(join(temporary, name), { recursive: true });
    await writeFile(join(temporary, name, `${name}.ts`), contents);
    const registration = join(source, name, 'register.ts');
    try {
      const registered = (await readFile(registration, 'utf8'))
        .replaceAll("from '../_.contribution'", "from '../_.contribution.ts'");
      await writeFile(join(temporary, name, 'register.ts'), registered);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  const grammars = [];
  const failed = [];
  await writeFile(join(temporary, '_.contribution.ts'), [
    'export const registrations = [];',
    'export function registerLanguage(item) { registrations.push(item); }',
  ].join('\n'));
  await mkdir(output, { recursive: true });
  for (const name of names) {
    const path = join(temporary, name, `${name}.ts`);
    try {
      await stat(path);
      const module = await import(pathToFileURL(path).href);
      const variants = name === 'freemarker2' ? [
        ['freemarker2', module.TagAutoInterpolationDollar],
        ['freemarker2.tag-auto.interpolation-bracket', module.TagAutoInterpolationBracket],
        ['freemarker2.tag-angle.interpolation-dollar', module.TagAngleInterpolationDollar],
        ['freemarker2.tag-angle.interpolation-bracket', module.TagAngleInterpolationBracket],
        ['freemarker2.tag-bracket.interpolation-dollar', module.TagBracketInterpolationDollar],
        ['freemarker2.tag-bracket.interpolation-bracket', module.TagBracketInterpolationBracket],
      ] : [[name, module]];
      for (const [languageId, variant] of variants) {
        if (!variant?.language) throw new Error(`No language export for ${languageId}`);
        const encoded = JSON.stringify({
          revision,
          attribution: 'Copyright (c) Microsoft Corporation. Licensed under the MIT License; see assets/monaco/LICENSE.txt.',
          languageId,
          language: variant.language,
          configuration: variant.conf ?? null,
        }, (_key, value) => {
          if (typeof value === 'function') throw new Error(`Non-serializable function in ${languageId}`);
          return value instanceof RegExp
            ? { '$regex': value.source, '$flags': value.flags }
            : value;
        }, 2);
        await writeFile(join(output, `${languageId}.json`), `${encoded}\n`);
        grammars.push(languageId);
      }
    } catch (error) {
      if (error.code === 'ENOENT') continue;
      failed.push({ name, error: error.message });
    }
  }
  for (const name of names) {
    const registration = join(temporary, name, 'register.ts');
    try {
      await stat(registration);
      await import(pathToFileURL(registration).href);
    } catch (error) {
      if (error.code !== 'ENOENT') failed.push({ name: `${name}/register`, error: error.message });
    }
  }
  const { registrations } = await import(pathToFileURL(join(temporary, '_.contribution.ts')).href);
  const metadata = registrations.map(({ loader, ...item }) => {
    const sourceName = loader?.toString().match(/import\(['"]\.\/([^'"]+)['"]\)/)?.[1];
    const assetId = grammars.includes(item.id) ? item.id : sourceName;
    if (!assetId || !grammars.includes(assetId)) {
      failed.push({ name: `${item.id}/register`, error: `Missing grammar asset ${assetId}` });
    }
    return { ...item, assetId };
  });
  await writeFile(join(output, 'manifest.json'), JSON.stringify({
    revision,
    attribution: 'Copyright (c) Microsoft Corporation. Licensed under the MIT License; see assets/monaco/LICENSE.txt.',
    grammars, registrations: metadata, failed,
  }, (_key, value) => value instanceof RegExp
    ? { '$regex': value.source, '$flags': value.flags }
    : value, 2) + '\n');
  if (failed.length) {
    console.error(failed);
    process.exitCode = 1;
  } else {
    console.log(`Serialized ${grammars.length} Monaco language definitions`);
  }
} finally {
  await rm(temporary, { recursive: true, force: true });
}
