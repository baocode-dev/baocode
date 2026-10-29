// baocode.dev's Worker: site/ is served as static assets, and this runs only
// for /dl/* (run_worker_first in wrangler.jsonc). /dl/windows,
// /dl/windows-arm64, /dl/macos-arm64,
// /dl/macos-x64, /dl/linux-x64 and /dl/linux-arm64 redirect to that build of
// the release in latest.json, and
// /dl/android to the phone app's in releases/mobile/latest.json, so
// a page's links work before site.js swaps them, and without it: a page
// cached by a browser, a fetch of the manifest too slow or blocked.
// /dl/ios redirects to the TestFlight beta.
// /dl/browser-extension redirects to the browser extension's zip, and
// /dl/chrome-web-store to its page in the store (releases/extension/
// latest.json's store), or, that not read, to the page its id makes.
// A desktop build's with ?ch=<channel> (site.js, from a page in another
// site's frame): the channel kept in a cookie of baocode.dev's own, which
// /activate reads, and a channel listed with its account site gets the
// channel build, as on the page.

const MANIFEST = 'https://dl.baocode.dev/releases/latest.json';
const MOBILE_MANIFEST = 'https://dl.baocode.dev/releases/mobile/latest.json';
const EXTENSION_MANIFEST = 'https://dl.baocode.dev/releases/extension/latest.json';
const MOBILE = new Set(['android', 'ios']);
// A phone app off the site: its link goes to the download page instead of
// to a build. None now.
const MOBILE_OFFLINE = new Set();
// iOS is on TestFlight, not in the manifest: /dl/ios is its public beta's
// link (App Store Connect → BaoCode → TestFlight → Public beta), the same
// for every build.
const TESTFLIGHT = 'https://testflight.apple.com/join/KWwGgyhv';
const EXTENSION = new Set(['browser-extension', 'chrome-web-store']);
const EXTENSION_ID = 'jfjagocghaaheooicmdnhcholmgdkngk';
const DESKTOP = new Set(['windows', 'windows-arm64', 'macos-arm64', 'macos-x64', 'linux-x64', 'linux-arm64']);
// A channel's id, as site.js takes one.
const CHANNEL = /^[\p{L}\p{N}._-]{1,128}$/u;

async function hasAccount(env, request, channel) {
  try {
    const res = await env.ASSETS.fetch(new Request(new URL('/channels.json', request.url)));
    const channels = await res.json();
    return typeof (Object.hasOwn(channels, channel) ? channels[channel] : null)?.account?.url === 'string';
  } catch {
    return false;
  }
}

export default {
  async fetch(request, env) {
    const { pathname, searchParams } = new URL(request.url);
    const os = pathname.match(/^\/dl\/([a-z0-9-]+)\/?$/)?.[1];
    if (!os) return env.ASSETS.fetch(request);
    const ch = searchParams.get('ch')?.trim().toLowerCase();
    const channel = DESKTOP.has(os) && ch && CHANNEL.test(ch) ? ch : null;
    if (MOBILE_OFFLINE.has(os)) {
      return new Response(null, {
        status: 302,
        headers: { Location: '/download', 'Cache-Control': 'no-store' },
      });
    }
    if (os === 'ios') {
      return new Response(null, {
        status: 302,
        headers: { Location: TESTFLIGHT, 'Cache-Control': 'no-store' },
      });
    }
    let manifest;
    try {
      const url = MOBILE.has(os) ? MOBILE_MANIFEST : EXTENSION.has(os) ? EXTENSION_MANIFEST : MANIFEST;
      const res = await fetch(url, { cf: { cacheTtl: 60, cacheEverything: true } });
      if (res.ok) manifest = await res.json();
    } catch {}
    if (os === 'chrome-web-store') {
      return new Response(null, {
        status: 302,
        headers: { Location: manifest?.store || `https://chromewebstore.google.com/detail/${manifest?.id || EXTENSION_ID}`, 'Cache-Control': 'no-store' },
      });
    }
    const file = manifest?.downloads?.[os];
    if (!file?.url) {
      const [status, text] = manifest ? [404, 'Not found'] : [502, 'The release could not be read; try again shortly.'];
      return new Response(text, { status, headers: { 'Cache-Control': 'no-store' } });
    }
    if (!channel) {
      return new Response(null, {
        status: 302,
        headers: { Location: file.url, 'Cache-Control': 'no-store' },
      });
    }
    const kept = encodeURIComponent(JSON.stringify({ source: 'channel', value: channel, at: new Date().toISOString() }));
    const build = file.channel?.url && await hasAccount(env, request, channel) ? file.channel.url : file.url;
    return new Response(null, {
      status: 302,
      headers: {
        Location: build,
        'Cache-Control': 'no-store',
        'Set-Cookie': `attribution=${kept}; Path=/; Max-Age=34560000; Secure; SameSite=Lax`,
      },
    });
  },
};
