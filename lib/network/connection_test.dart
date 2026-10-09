/// A site Settings → Network's connection test reaches through the proxy:
/// those the user's work needs (Claude's, OpenAI's), those only a working
/// proxy reaches from China (Google's, YouTube's), and one that only a
/// working network does (Baidu's).
class TestSite {
  const TestSite({
    required this.id,
    required this.name,
    required this.url,
    required this.icon,
  });

  final String id;
  final String name;

  /// What is asked: an answer of any status is the site reached.
  final Uri url;

  /// Its logo (assets/network/, from Iconify): in one color, drawn in
  /// the text's.
  final String icon;

  static final all = [
    TestSite(
      id: 'google',
      name: 'Google',
      url: Uri.parse('https://www.google.com/generate_204'),
      icon: 'assets/network/google.svg',
    ),
    TestSite(
      id: 'youtube',
      name: 'YouTube',
      url: Uri.parse('https://www.youtube.com/generate_204'),
      icon: 'assets/network/youtube.svg',
    ),
    TestSite(
      id: 'anthropic',
      name: 'Anthropic',
      url: Uri.parse('https://api.anthropic.com/'),
      icon: 'assets/network/anthropic.svg',
    ),
    TestSite(
      id: 'openai',
      name: 'OpenAI',
      url: Uri.parse('https://api.openai.com/v1/models'),
      icon: 'assets/network/openai.svg',
    ),
    TestSite(
      id: 'baidu',
      name: 'Baidu',
      url: Uri.parse('https://www.baidu.com/'),
      icon: 'assets/network/baidu.svg',
    ),
  ];
}

/// Why a site was not reached.
enum ProbeFailureKind {
  /// No answer in time: blocked, or the proxy too slow.
  timeout,

  /// Nothing listens there: the proxy (Clash) is not running.
  refused,

  /// Cut off as it connected: blocked on the way.
  reset,

  /// The name did not resolve.
  dns,

  /// The TLS handshake failed: a certificate, or the connection broken.
  tls,

  /// The proxy wants a user and password.
  proxyAuth,

  other,
}

class ProbeFailure implements Exception {
  const ProbeFailure(this.kind, [this.detail = '']);

  final ProbeFailureKind kind;

  /// What the system said, as it said it.
  final String detail;

  @override
  String toString() => detail.isEmpty ? kind.name : '${kind.name}: $detail';
}
