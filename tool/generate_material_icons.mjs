#!/usr/bin/env node
// Bundles the Material Icon Theme (https://github.com/material-extensions/
// vscode-material-icon-theme, as used by material-icons-browser-extension)
// for the app's file and folder icons.
//
//   npm pack material-icon-theme@5.38.1 && tar xzf material-icon-theme-*.tgz
//   node tool/generate_material_icons.mjs package assets/material_icons
//
// Writes manifest.json (the dark theme's name/extension/folder mappings, by
// icon id) and icons/<id>.svg for every icon the mappings use, plus the
// package's LICENSE. Light and high-contrast variants are left out: the app
// is dark.

import fs from 'node:fs';
import path from 'node:path';

const [source, output] = process.argv.slice(2);
if (!source || !output) {
  console.error('usage: generate_material_icons.mjs <package-dir> <output-dir>');
  process.exit(64);
}

const pkg = JSON.parse(
  fs.readFileSync(path.join(source, 'package.json'), 'utf8'),
);
const theme = JSON.parse(
  fs.readFileSync(path.join(source, 'dist', 'material-icons.json'), 'utf8'),
);

const lower = (map) =>
  Object.fromEntries(
    Object.entries(map ?? {}).map(([key, id]) => [key.toLowerCase(), id]),
  );

const manifest = {
  name: pkg.name,
  version: pkg.version,
  file: theme.file,
  folder: theme.folder,
  folderExpanded: theme.folderExpanded,
  rootFolder: theme.rootFolder,
  rootFolderExpanded: theme.rootFolderExpanded,
  fileNames: lower(theme.fileNames),
  fileExtensions: lower(theme.fileExtensions),
  folderNames: lower(theme.folderNames),
  folderNamesExpanded: lower(theme.folderNamesExpanded),
};

const used = new Set([
  manifest.file,
  manifest.folder,
  manifest.folderExpanded,
  manifest.rootFolder,
  manifest.rootFolderExpanded,
  ...Object.values(manifest.fileNames),
  ...Object.values(manifest.fileExtensions),
  ...Object.values(manifest.folderNames),
  ...Object.values(manifest.folderNamesExpanded),
]);

const icons = path.join(output, 'icons');
fs.rmSync(icons, { recursive: true, force: true });
fs.mkdirSync(icons, { recursive: true });
let bytes = 0;
for (const id of [...used].sort()) {
  const definition = theme.iconDefinitions[id];
  if (!definition) throw new Error(`No icon definition for ${id}`);
  const file = path.join(source, 'dist', definition.iconPath);
  // Whitespace between tags only: the drawing is untouched.
  const svg = fs
    .readFileSync(file, 'utf8')
    .replace(/>\s+</g, '><')
    .trim();
  fs.writeFileSync(path.join(icons, `${id}.svg`), svg);
  bytes += svg.length;
}
fs.writeFileSync(
  path.join(output, 'manifest.json'),
  JSON.stringify(manifest),
);
fs.copyFileSync(path.join(source, 'LICENSE'), path.join(output, 'LICENSE'));
console.log(
  `${pkg.name}@${pkg.version}: ${used.size} icons, ${(bytes / 1024).toFixed(0)} KiB`,
);
