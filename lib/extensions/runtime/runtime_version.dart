// The one extension runtime the app works with: VSCodium's REH at this
// version (tool/build_exthost_runtime.dart pins it, and
// assets/exthost/exthost_runtimes.json says where its builds are). The
// protocol in packages/bao_exthost is ported from [upstreamCommit], and the
// server's handshake expects [productCommit]. Upgrading changes them all
// together (test/extensions/runtime/ checks they agree).

/// VSCodium's release.
const extHostRuntimeVersion = '1.135.06055';

/// Its product.json's `commit`: VSCodium's build, sent in the handshake.
const extHostProductCommit = '1a46a584725d5dd330e0bcd7f5510f24990efcf2';

/// The VS Code release it is built from, which the Dart side is ported from.
const extHostUpstreamVersion = '1.135.0';
const extHostUpstreamCommit = '08d4889f9ec4a1685d257b9b95de036c8e1ce1e5';

/// The Node.js it runs on.
const extHostNodeVersion = '24.18.1';
