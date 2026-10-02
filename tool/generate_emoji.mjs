#!/usr/bin/env node
// Bundles Emojibase's emoji (https://emojibase.dev, MIT) for the project
// icon picker (lib/icons/emoji_catalog.dart).
//
//   npm pack emojibase-data@16.0.3 && tar xzf emojibase-data-*.tgz
//   node tool/generate_emoji.mjs package assets/emoji
//
// Writes emoji.tsv, one emoji a line in the picker's order:
//
//   <group>\t<emoji>\t<English name>\t<English tags>\t<Chinese name>\t<Chinese tags>
//
// tags space separated. The components (skin tones, hair) are left out, as
// are skin tone variants and the emoji newer than the platforms' fonts
// draw ([maxVersion]). Plus the package's LICENSE.

import fs from 'node:fs';
import path from 'node:path';

const [source, output] = process.argv.slice(2);
if (!source || !output) {
  console.error('usage: generate_emoji.mjs <package-dir> <output-dir>');
  process.exit(64);
}

/// Emoji 15.0: drawn by the macOS and Windows 11 fonts of 2023 on.
const maxVersion = 15;
const componentGroup = 2;

const read = (file) =>
  JSON.parse(fs.readFileSync(path.join(source, file), 'utf8'));
const en = read('en/data.json');
const zh = new Map(read('zh/compact.json').map((emoji) => [emoji.hexcode, emoji]));

const clean = (text) => (text ?? '').replace(/[\t\n]/g, ' ').trim();
const lines = en
  .filter(
    (emoji) =>
      emoji.group != null &&
      emoji.group !== componentGroup &&
      emoji.version <= maxVersion,
  )
  .sort((a, b) => a.order - b.order)
  .map((emoji) => {
    const chinese = zh.get(emoji.hexcode) ?? {};
    return [
      emoji.group,
      emoji.emoji,
      clean(emoji.label),
      clean((emoji.tags ?? []).join(' ')),
      clean(chinese.label),
      clean((chinese.tags ?? []).join(' ')),
    ].join('\t');
  });

fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(path.join(output, 'emoji.tsv'), `${lines.join('\n')}\n`);
fs.copyFileSync(path.join(source, 'LICENSE'), path.join(output, 'LICENSE'));
console.log(`${lines.length} emoji`);
