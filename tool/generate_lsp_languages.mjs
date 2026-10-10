#!/usr/bin/env node
// Generates assets/lsp/languages.json: which language a file is in and the
// language servers it uses, from Helix's languages.toml, with each server
// mapped to the mason-registry package that installs it.
//
// Pinned upstream: helix-editor/helix commit HELIX_COMMIT (languages.toml,
// MPL-2.0; see assets/lsp/LICENSE-helix) and the mason-registry release
// pinned in tool/generate_mason_registry.mjs.
//
// Usage:
//   node tool/generate_lsp_languages.mjs [helix-checkout|languages.toml] [output-dir] [--mason registry.json(.zip)]
//
// Without a Helix source the pinned languages.toml is downloaded into /tmp
// (likewise the mason registry). Run tool/generate_mason_registry.mjs after
// this script so the packages the mapping names are kept.
//
// Output shape (keys omitted when empty):
//   { source, languages: [{ id, languageId, fileTypes, fileNames, globs,
//     shebangs, roots, servers: [name | { name, only, except }] }],
//     servers: { <name>: { command, args, environment, config,
//     requiredRoots, mason } } }
// Helix sends a server's `config` both as `initializationOptions` and as the
// answer to `workspace/configuration`; the catalog mirrors that.

import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { MASON_RELEASE, readMasonRegistry } from './generate_mason_registry.mjs';

export const HELIX_COMMIT = 'ba40e547426b0f9896c8bdc699a4ab11f2b37dbc';
const HELIX_URL = `https://raw.githubusercontent.com/helix-editor/helix/${HELIX_COMMIT}/languages.toml`;

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// A TOML 1.0 parser, enough for languages.toml: tables, arrays of tables,
// dotted keys, inline tables (newlines allowed inside, as TOML 1.1 does),
// every string form, integers, floats and booleans. Dates stay strings.

export function parseToml(text) {
  let i = 0;
  const root = {};
  let current = root;
  const defined = new WeakSet();

  const fail = (message) => {
    const line = text.slice(0, i).split('\n').length;
    throw new SyntaxError(`TOML line ${line}: ${message}`);
  };
  const peek = (n = 0) => text[i + n];
  const skipInline = () => {
    while (peek() === ' ' || peek() === '\t') i++;
    if (peek() === '#') while (i < text.length && peek() !== '\n') i++;
  };
  const skipAll = () => {
    for (;;) {
      skipInline();
      if (peek() === '\n' || peek() === '\r') i++;
      else return;
    }
  };
  const expectLineEnd = () => {
    skipInline();
    if (i < text.length && peek() !== '\n' && peek() !== '\r') {
      fail(`unexpected ${JSON.stringify(peek())}`);
    }
  };

  const escapes = { b: '\b', t: '\t', n: '\n', f: '\f', r: '\r', '"': '"', '\\': '\\' };
  function basicString(multiline) {
    let out = '';
    for (;;) {
      if (i >= text.length) fail('unterminated string');
      if (multiline && text.startsWith('"""', i)) {
        let quotes = 3;
        while (text[i + quotes] === '"' && quotes < 5) quotes++;
        out += '"'.repeat(quotes - 3);
        i += quotes;
        return out;
      }
      const c = text[i++];
      if (!multiline && c === '"') return out;
      if (!multiline && c === '\n') fail('newline in string');
      if (c !== '\\') {
        out += c;
        continue;
      }
      const e = text[i++];
      if (e in escapes) out += escapes[e];
      else if (e === 'u' || e === 'U') {
        const n = e === 'u' ? 4 : 8;
        out += String.fromCodePoint(parseInt(text.slice(i, i + n), 16));
        i += n;
      } else if (multiline && /[ \t\r\n]/.test(e)) {
        // Line-ending backslash: trim whitespace through the next content.
        i--;
        while (/[ \t\r\n]/.test(peek())) i++;
      } else fail(`bad escape \\${e}`);
    }
  }
  function literalString(multiline) {
    const end = multiline ? "'''" : "'";
    const close = text.indexOf(end, i);
    if (close < 0) fail('unterminated string');
    let stop = close;
    if (multiline) while (text[stop + 3] === "'" && stop - close < 2) stop++;
    const out = text.slice(i, stop);
    i = stop + end.length;
    if (!multiline && out.includes('\n')) fail('newline in string');
    return out;
  }
  function string() {
    if (text.startsWith('"""', i)) {
      i += 3;
      if (peek() === '\n') i++;
      else if (peek() === '\r' && peek(1) === '\n') i += 2;
      return basicString(true);
    }
    if (text.startsWith("'''", i)) {
      i += 3;
      if (peek() === '\n') i++;
      else if (peek() === '\r' && peek(1) === '\n') i += 2;
      return literalString(true);
    }
    if (peek() === '"') {
      i++;
      return basicString(false);
    }
    i++;
    return literalString(false);
  }

  function key() {
    const parts = [];
    for (;;) {
      skipInline();
      if (peek() === '"' || peek() === "'") parts.push(string());
      else {
        const m = /^[A-Za-z0-9_-]+/.exec(text.slice(i, i + 256));
        if (!m) fail('expected a key');
        parts.push(m[0]);
        i += m[0].length;
      }
      skipInline();
      if (peek() !== '.') return parts;
      i++;
    }
  }

  function value() {
    const c = peek();
    if (c === '"' || c === "'") return string();
    if (c === '[') {
      i++;
      const items = [];
      for (;;) {
        skipAll();
        if (peek() === ']') {
          i++;
          return items;
        }
        items.push(value());
        skipAll();
        if (peek() === ',') i++;
        else if (peek() !== ']') fail('expected , or ]');
      }
    }
    if (c === '{') {
      i++;
      const table = {};
      for (;;) {
        skipAll();
        if (peek() === '}') {
          i++;
          return table;
        }
        assign(table, key(), true);
        skipAll();
        if (peek() === ',') i++;
        else if (peek() !== '}') fail('expected , or }');
      }
    }
    const m = /^[^\s,\]}#]+/.exec(text.slice(i, i + 256));
    if (!m) fail('expected a value');
    const raw = m[0];
    i += raw.length;
    if (raw === 'true') return true;
    if (raw === 'false') return false;
    if (/^[+-]?(inf|nan)$/.test(raw)) {
      return raw.endsWith('nan') ? NaN : raw.startsWith('-') ? -Infinity : Infinity;
    }
    const clean = raw.replace(/_/g, '');
    if (/^0x[0-9a-f]+$/i.test(clean)) return parseInt(clean.slice(2), 16);
    if (/^0o[0-7]+$/.test(clean)) return parseInt(clean.slice(2), 8);
    if (/^0b[01]+$/.test(clean)) return parseInt(clean.slice(2), 2);
    if (/^[+-]?\d+$/.test(clean)) return Number(clean);
    if (/^[+-]?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(clean)) return Number(clean);
    if (/^\d{4}-\d{2}-\d{2}/.test(raw) || /^\d{2}:\d{2}/.test(raw)) {
      // A date-time may contain one space between date and time.
      const rest = /^ \d{2}:[\d:.]+(Z|[+-]\d{2}:\d{2})?/.exec(text.slice(i));
      if (rest) i += rest[0].length;
      return raw + (rest ? rest[0] : '');
    }
    fail(`bad value ${raw}`);
  }

  function assign(table, parts, inline) {
    skipInline();
    if (peek() !== '=') fail('expected =');
    i++;
    skipInline();
    let target = table;
    for (const part of parts.slice(0, -1)) {
      target[part] ??= {};
      target = target[part];
      if (typeof target !== 'object' || Array.isArray(target)) {
        fail(`${parts.join('.')} is not a table`);
      }
    }
    const last = parts[parts.length - 1];
    if (Object.hasOwn(target, last)) fail(`duplicate key ${parts.join('.')}`);
    target[last] = value();
    if (!inline) expectLineEnd();
  }

  function descend(parts, arrayOfTables) {
    let target = root;
    parts.forEach((part, index) => {
      const lastPart = index === parts.length - 1;
      if (lastPart && arrayOfTables) {
        target[part] ??= [];
        if (!Array.isArray(target[part])) fail(`${part} is not an array`);
        const table = {};
        target[part].push(table);
        target = table;
        return;
      }
      target[part] ??= {};
      target = target[part];
      if (Array.isArray(target)) target = target[target.length - 1];
      if (typeof target !== 'object') fail(`${parts.join('.')} is not a table`);
    });
    return target;
  }

  for (;;) {
    skipAll();
    if (i >= text.length) return root;
    if (peek() === '[') {
      const arrayOfTables = peek(1) === '[';
      i += arrayOfTables ? 2 : 1;
      const parts = key();
      if (!text.startsWith(arrayOfTables ? ']]' : ']', i)) fail('expected ]');
      i += arrayOfTables ? 2 : 1;
      expectLineEnd();
      current = descend(parts, arrayOfTables);
      if (defined.has(current)) fail(`table ${parts.join('.')} defined twice`);
      defined.add(current);
    } else {
      assign(current, key(), false);
    }
  }
}

// ---------------------------------------------------------------------------
// Helix → catalog.

const nonEmpty = (value) =>
  value != null &&
  !(Array.isArray(value) && value.length === 0) &&
  !(typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === 0);

function compact(object) {
  return Object.fromEntries(
    Object.entries(object).filter(([, value]) => nonEmpty(value)),
  );
}

/** Helix's `file-types`: extensions stay extensions; `{ glob }` entries with
 * no wildcard or `/` are exact file names, the rest globs. */
function fileTypes(entries, problems, language) {
  const out = { fileTypes: [], fileNames: [], globs: [] };
  for (const entry of entries ?? []) {
    if (typeof entry === 'string') out.fileTypes.push(entry);
    else if (entry && typeof entry.glob === 'string') {
      if (/[*?[\]{}/]/.test(entry.glob)) out.globs.push(entry.glob);
      else out.fileNames.push(entry.glob);
    } else problems.push(`${language}: unknown file-type ${JSON.stringify(entry)}`);
  }
  return out;
}

function languageServers(entries) {
  return (entries ?? []).map((entry) => {
    if (typeof entry === 'string') return entry;
    return compact({
      name: entry.name,
      only: entry['only-features'],
      except: entry['except-features'],
    });
  });
}

/** The mason package whose `bin` provides [command]: by preference one
 * named like the server or the command, then an LSP package, then any. */
function masonPackageFor(id, command, registry) {
  if (!command || command.includes('/')) return undefined;
  const providers = registry.filter((pkg) =>
    Object.hasOwn(pkg.bin ?? {}, command),
  );
  if (!providers.length) return undefined;
  const lsp = (pkg) => (pkg.categories ?? []).includes('LSP');
  const ranked = [
    providers.filter((pkg) => pkg.name === id),
    providers.filter((pkg) => pkg.name === command),
    providers.filter((pkg) => lsp(pkg) && !pkg.deprecation),
    providers.filter((pkg) => !pkg.deprecation),
  ];
  for (const tier of ranked) {
    if (tier.length === 1) return tier[0].name;
    if (tier.length > 1) {
      return tier.map((pkg) => pkg.name).sort()[0];
    }
  }
  return undefined;
}

export function convert(toml, registry) {
  const problems = [];
  const servers = {};
  for (const [id, raw] of Object.entries(toml['language-server'] ?? {})) {
    if (typeof raw.command !== 'string') {
      problems.push(`server ${id}: no command`);
      continue;
    }
    servers[id] = compact({
      command: raw.command,
      args: raw.args,
      environment: raw.environment,
      config: raw.config,
      requiredRoots: raw['required-root-patterns'],
      mason: masonPackageFor(id, raw.command, registry),
    });
  }
  const languages = [];
  for (const raw of toml.language ?? []) {
    const types = fileTypes(raw['file-types'], problems, raw.name);
    const used = languageServers(raw['language-servers']);
    for (const entry of used) {
      const name = typeof entry === 'string' ? entry : entry.name;
      if (!servers[name]) problems.push(`${raw.name}: unknown server ${name}`);
    }
    languages.push(
      compact({
        id: raw.name,
        languageId: raw['language-id'],
        ...types,
        shebangs: raw.shebangs,
        roots: raw.roots,
        servers: used.filter((entry) =>
          servers[typeof entry === 'string' ? entry : entry.name],
        ),
      }),
    );
  }
  return { languages, servers, problems };
}

function readHelix(path) {
  if (!path) {
    const dir = join('/tmp', `helix-${HELIX_COMMIT}`);
    mkdirSync(dir, { recursive: true });
    path = join(dir, 'languages.toml');
    if (!existsSync(path)) {
      execFileSync('curl', ['-sSfL', '-o', path, HELIX_URL], { stdio: 'inherit' });
    }
  } else if (statSync(path).isDirectory()) {
    path = join(path, 'languages.toml');
  }
  return readFileSync(path, 'utf8');
}

function main() {
  const args = process.argv.slice(2);
  let masonPath;
  const masonFlag = args.indexOf('--mason');
  if (masonFlag >= 0) {
    masonPath = args[masonFlag + 1];
    args.splice(masonFlag, 2);
  }
  const [helixPath, outputArg] = args;
  const outDir = resolve(outputArg ?? join(repoRoot, 'assets/lsp'));
  const toml = parseToml(readHelix(helixPath));
  const registry = readMasonRegistry(masonPath);
  const { languages, servers, problems } = convert(toml, registry);
  for (const problem of problems) console.warn(`warning: ${problem}`);
  mkdirSync(outDir, { recursive: true });
  writeFileSync(
    join(outDir, 'languages.json'),
    JSON.stringify({
      source: {
        repository: 'https://github.com/helix-editor/helix',
        commit: HELIX_COMMIT,
        file: 'languages.toml',
        license: 'MPL-2.0',
        masonRelease: MASON_RELEASE,
      },
      languages,
      servers,
    }),
  );
  writeFileSync(join(outDir, 'LICENSE-helix'), LICENSE);
  const mapped = Object.values(servers).filter((server) => server.mason).length;
  console.log(
    `languages.json: ${languages.length} languages, ` +
      `${Object.keys(servers).length} servers (${mapped} with a mason package)`,
  );
}

const LICENSE = `assets/lsp/languages.json is derived from Helix's languages.toml
(https://github.com/helix-editor/helix/blob/${HELIX_COMMIT}/languages.toml),
commit ${HELIX_COMMIT}, by tool/generate_lsp_languages.mjs: the file types,
shebangs, roots and language servers of each language, and each server's
command, arguments, environment and configuration.

Helix is Copyright (c) the Helix contributors and is distributed under the
Mozilla Public License, Version 2.0. The source form of the covered file is
available at the URL above. A copy of the license is available at
https://mozilla.org/MPL/2.0/.

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
`;

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
