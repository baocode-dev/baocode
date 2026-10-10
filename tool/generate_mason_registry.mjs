#!/usr/bin/env node
// Generates assets/lsp/mason-registry.json: the pinned mason-registry
// packages the IDE can install language servers from, trimmed to the fields
// the installer reads (lib/ide/lsp/install/).
//
// Pinned upstream: mason-org/mason-registry release MASON_RELEASE
// (tag commit MASON_COMMIT), whose `registry.json.zip` asset holds every
// package.yaml already converted to JSON. Licensed Apache-2.0; see
// assets/lsp/LICENSE-mason-registry.
//
// Usage:
//   node tool/generate_mason_registry.mjs [registry.json|registry.json.zip] [output-dir]
//
// Without a registry file the pinned release asset is downloaded into /tmp.
// The output keeps every `LSP` package plus any package named by
// assets/lsp/languages.json (run tool/generate_lsp_languages.mjs first when
// the Helix mapping changes). Only network access: the pinned download.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const MASON_RELEASE = '2026-09-29-glass-hat';
export const MASON_COMMIT = '27cabd46dfb4e97187a4619d7de966589e3945f7';
const MASON_URL = `https://github.com/mason-org/mason-registry/releases/download/${MASON_RELEASE}/registry.json.zip`;

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** Reads the mason registry (a JSON array of packages) from [path], a
 * `registry.json` or its release `.zip`; downloads the pinned release when
 * [path] is empty. */
export function readMasonRegistry(path) {
  if (!path) {
    const dir = join('/tmp', `mason-registry-${MASON_RELEASE}`);
    mkdirSync(dir, { recursive: true });
    path = join(dir, 'registry.json.zip');
    if (!existsSync(path)) {
      execFileSync('curl', ['-sSfL', '-o', path, MASON_URL], {
        stdio: 'inherit',
      });
    }
  }
  if (path.endsWith('.zip')) {
    const text = execFileSync('unzip', ['-p', path, 'registry.json'], {
      maxBuffer: 1 << 28,
    }).toString('utf8');
    return JSON.parse(text);
  }
  return JSON.parse(readFileSync(path, 'utf8'));
}

const list = (value) => (value == null ? [] : [].concat(value));

/** The package fields the installer reads: no descriptions, schemas,
 * version overrides or `share`/`opt` links. */
export function trimPackage(pkg) {
  const source = { id: pkg.source.id };
  for (const key of ['asset', 'download', 'build']) {
    if (pkg.source[key] != null) source[key] = pkg.source[key];
  }
  for (const key of ['extra_packages', 'supported_platforms', 'bin']) {
    if (pkg.source[key] != null) source[key] = pkg.source[key];
  }
  const out = {
    name: pkg.name,
    languages: pkg.languages ?? [],
    categories: pkg.categories ?? [],
    source,
    bin: pkg.bin ?? {},
  };
  if (pkg.deprecation) out.deprecated = true;
  return out;
}

function main() {
  const [input, outputArg] = process.argv.slice(2);
  const outDir = resolve(outputArg ?? join(repoRoot, 'assets/lsp'));
  const registry = readMasonRegistry(input);
  const referenced = new Set();
  const languagesPath = join(outDir, 'languages.json');
  if (existsSync(languagesPath)) {
    const languages = JSON.parse(readFileSync(languagesPath, 'utf8'));
    for (const server of Object.values(languages.servers ?? {})) {
      if (server.mason) referenced.add(server.mason);
    }
  }
  const packages = registry
    .filter(
      (pkg) =>
        list(pkg.categories).includes('LSP') || referenced.has(pkg.name),
    )
    .sort((a, b) => a.name.localeCompare(b.name))
    .map(trimPackage);
  const missing = [...referenced].filter(
    (name) => !packages.some((pkg) => pkg.name === name),
  );
  if (missing.length) {
    throw new Error(`languages.json names unknown packages: ${missing}`);
  }
  mkdirSync(outDir, { recursive: true });
  writeFileSync(
    join(outDir, 'mason-registry.json'),
    JSON.stringify({
      source: {
        repository: 'https://github.com/mason-org/mason-registry',
        release: MASON_RELEASE,
        commit: MASON_COMMIT,
        license: 'Apache-2.0',
      },
      packages,
    }),
  );
  writeFileSync(join(outDir, 'LICENSE-mason-registry'), LICENSE);
  console.log(
    `mason-registry.json: ${packages.length} packages ` +
      `(${referenced.size} named by languages.json)`,
  );
}

const LICENSE = `assets/lsp/mason-registry.json is derived from mason-registry
(https://github.com/mason-org/mason-registry), release ${MASON_RELEASE},
commit ${MASON_COMMIT}, by tool/generate_mason_registry.mjs, which keeps
a subset of each package's fields.

Copyright 2022-present mason-registry contributors.

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy
of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
`;

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) main();
