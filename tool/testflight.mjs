// Puts an iPhone build uploaded to TestFlight before the public testers
// (.github/workflows/mobile.yml, docs/release.md 10): once Apple has
// processed it, what to test is written for it, it joins the public group
// and goes to Beta App Review; with --wait, until the testers have it.
//
//   node tool/testflight.mjs --version 0.1.8 --build 123 \
//     [--notes-zh notes.zh.md] [--notes-en notes.en.md] [--wait] [--out ios.json]
//
// The App Store Connect API key from ASC_KEY (the .p8's text), ASC_KEY_ID
// and ASC_ISSUER. --out is written once the testers have it: the version
// and build, for latest.json.
import { createSign } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';

const BUNDLE_ID = 'dev.baocode.mobile';
const GROUP = 'Public beta';

const { values: args } = parseArgs({
  options: {
    version: { type: 'string' },
    build: { type: 'string' },
    'notes-zh': { type: 'string' },
    'notes-en': { type: 'string' },
    wait: { type: 'boolean', default: false },
    out: { type: 'string' },
    // How long Apple's processing and review are waited for, in minutes.
    'processing-minutes': { type: 'string', default: '90' },
    'review-minutes': { type: 'string', default: '330' },
  },
});
if (!args.version || !args.build) {
  console.error('--version and --build are needed');
  process.exit(2);
}

const { ASC_KEY, ASC_KEY_ID, ASC_ISSUER } = process.env;
if (!ASC_KEY || !ASC_KEY_ID || !ASC_ISSUER) {
  console.error('ASC_KEY, ASC_KEY_ID and ASC_ISSUER are needed');
  process.exit(2);
}

/// A token for a request: one lasts 20 minutes at most, and this waits
/// hours.
function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' });
  const body = b64({ iss: ASC_ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  const sig = createSign('SHA256')
    .update(`${head}.${body}`)
    .sign({ key: ASC_KEY, dsaEncoding: 'ieee-p1363' })
    .toString('base64url');
  return `${head}.${body}.${sig}`;
}

async function api(method, path, data) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const error = new Error(`${method} ${path}: ${res.status} ${text}`);
    error.status = res.status;
    throw error;
  }
  return json;
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/// Asks [look] every [every] ms until it gives something, for [minutes].
async function until(what, minutes, look, every = 30_000) {
  const end = Date.now() + minutes * 60_000;
  for (;;) {
    const found = await look();
    if (found) return found;
    if (Date.now() > end) throw new Error(`Still ${what} after ${minutes} minutes`);
    await sleep(every);
  }
}

const app = (await api('GET', `/v1/apps?filter[bundleId]=${BUNDLE_ID}`)).data[0];
if (!app) throw new Error(`No app ${BUNDLE_ID}`);

// The build, once Apple has processed it (it shows a while after upload).
const build = await until('processing', Number(args['processing-minutes']), async () => {
  const found = await api(
    'GET',
    `/v1/builds?filter[app]=${app.id}&filter[version]=${args.build}` +
      `&filter[preReleaseVersion.version]=${args.version}`,
  );
  const build = found.data[0];
  const state = build?.attributes.processingState;
  console.log(`Build ${args.version} (${args.build}): ${state ?? 'not there yet'}`);
  if (state === 'FAILED' || state === 'INVALID') throw new Error(`Processing ${state}`);
  return state === 'VALID' ? build : null;
});

// What to test, in each language there are notes in.
const notes = { 'zh-Hans': args['notes-zh'], 'en-US': args['notes-en'] };
const localizations = (await api('GET', `/v1/builds/${build.id}/betaBuildLocalizations`)).data;
for (const [locale, file] of Object.entries(notes)) {
  if (!file) continue;
  // TestFlight takes 4000 characters.
  const whatsNew = readFileSync(file, 'utf8').trim().slice(0, 4000);
  if (!whatsNew) continue;
  const had = localizations.find((l) => l.attributes.locale === locale);
  if (had) {
    await api('PATCH', `/v1/betaBuildLocalizations/${had.id}`, {
      data: { type: 'betaBuildLocalizations', id: had.id, attributes: { whatsNew } },
    });
  } else {
    await api('POST', '/v1/betaBuildLocalizations', {
      data: {
        type: 'betaBuildLocalizations',
        attributes: { locale, whatsNew },
        relationships: { build: { data: { type: 'builds', id: build.id } } },
      },
    });
  }
  console.log(`What to test (${locale}) written`);
}

// To the public testers' group.
const group = (await api('GET', `/v1/apps/${app.id}/betaGroups`)).data.find(
  (g) => g.attributes.name === GROUP,
);
if (!group) throw new Error(`No beta group ${GROUP}`);
try {
  await api('POST', `/v1/betaGroups/${group.id}/relationships/builds`, {
    data: [{ type: 'builds', id: build.id }],
  });
} catch (error) {
  // In it already: a run again.
  if (error.status !== 409) throw error;
}
console.log(`In ${GROUP}`);

const state = async () =>
  (await api('GET', `/v1/builds/${build.id}/buildBetaDetail`)).data.attributes.externalBuildState;

// To review, unless it went already (or needs none: a build of a version
// already approved is let through).
if ((await state()) === 'READY_FOR_BETA_SUBMISSION') {
  await api('POST', '/v1/betaAppReviewSubmissions', {
    data: {
      type: 'betaAppReviewSubmissions',
      relationships: { build: { data: { type: 'builds', id: build.id } } },
    },
  });
  console.log('Sent to Beta App Review');
}

if (args.wait) {
  await until('in review', Number(args['review-minutes']), async () => {
    const now = await state();
    console.log(`External: ${now}`);
    if (now === 'BETA_REJECTED') throw new Error('Beta App Review rejected it');
    return now === 'IN_BETA_TESTING';
  }, 120_000);
  console.log(`The public testers have ${args.version} (${args.build})`);
  if (args.out) {
    writeFileSync(args.out, JSON.stringify({ version: args.version, build: Number(args.build) }));
  }
}
