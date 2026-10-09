import 'package:baocode/network/proxy_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// `scutil --proxy` with Clash Verge's system proxy on.
const _scutilClash = '''
<dictionary> {
  ExceptionsList : <array> {
    0 : 127.0.0.1
    1 : 192.168.0.0/16
    2 : localhost
    3 : *.local
    4 : timestamp.apple.com
  }
  ExcludeSimpleHostnames : 1
  FTPPassive : 1
  HTTPEnable : 1
  HTTPPort : 7897
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7897
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7897
  SOCKSProxy : 127.0.0.1
}
''';

/// `reg query` of Internet Settings with Clash for Windows' system proxy
/// on.
const _regClash = '''

HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    DisableCachingOfSSLPages    REG_DWORD    0x0
    IE5_UA_Backup_Flag    REG_SZ    5.0
    PrivacyAdvanced    REG_DWORD    0x1
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    127.0.0.1:7890
    ProxyOverride    REG_SZ    localhost;127.*;10.*;172.16.*;192.168.*;*.lan;<local>
    EnableNegotiate    REG_DWORD    0x1

HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\5.0
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\Connections
''';

void main() {
  group('ProxyMode', () {
    test('is the system proxy unless set otherwise', () {
      expect(ProxyMode.parse(null), ProxyMode.system);
      expect(ProxyMode.parse('bogus'), ProxyMode.system);
      expect(ProxyMode.parse(' manual '), ProxyMode.manual);
      expect(ProxyMode.parse('off'), ProxyMode.off);
    });
  });

  group('ProxyServer.parse', () {
    test('takes an HTTP proxy, with or without its scheme', () {
      expect(
        ProxyServer.parse('127.0.0.1:7890'),
        const ProxyServer('127.0.0.1', 7890),
      );
      expect(
        ProxyServer.parse(' http://proxy.corp:3128/ '),
        const ProxyServer('proxy.corp', 3128),
      );
      expect(ProxyServer.parse('http://proxy.corp')!.port, 80);
    });

    test('keeps who the user is, and shows it without the password', () {
      final server = ProxyServer.parse('http://me%40corp:p%3Ass@proxy:8080')!;
      expect(server.username, 'me@corp');
      expect(server.password, 'p:ss');
      expect(server.url, 'http://me%40corp:p%3Ass@proxy:8080');
      expect(server.display, 'http://me%40corp@proxy:8080');
      expect(server.directive, 'PROXY me@corp:p:ss@proxy:8080');
    });

    test('takes none but HTTP', () {
      expect(ProxyServer.parse(''), isNull);
      expect(ProxyServer.parse('socks5://127.0.0.1:7890'), isNull);
      expect(ProxyServer.parse('https://proxy:443'), isNull);
      expect(ProxyServer.parse('http://proxy:80/path'), isNull);
      expect(ProxyServer.parse('not a url at all'), isNull);
    });
  });

  group('ProxyRoute', () {
    final route = ProxyRoute(
      source: ProxySource.manual,
      http: const ProxyServer('127.0.0.1', 7890),
      https: const ProxyServer('127.0.0.1', 7890),
      bypass: const ['corp.example', '.internal', '*.lan', '10.*'],
      bypassSimpleHostnames: true,
    );

    test('sends a request through the proxy, or past it', () {
      expect(
        route.findProxy(Uri.parse('https://api.anthropic.com/v1/messages')),
        'PROXY 127.0.0.1:7890',
      );
      for (final url in [
        'http://localhost:3000/',
        'http://127.0.0.1:5000/p/gw',
        'http://[::1]:8080/',
        'https://corp.example/',
        'https://git.corp.example/',
        'https://internal/',
        'https://a.internal/',
        'https://nas.lan/',
        'http://10.0.0.8/',
        'http://intranet/',
      ]) {
        expect(route.findProxy(Uri.parse(url)), 'DIRECT', reason: url);
      }
      expect(
        route.findProxy(Uri.parse('https://notcorp.example/')),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('gives a child process both spellings, this machine kept out', () {
      expect(route.environment, {
        'HTTP_PROXY': 'http://127.0.0.1:7890',
        'http_proxy': 'http://127.0.0.1:7890',
        'HTTPS_PROXY': 'http://127.0.0.1:7890',
        'https_proxy': 'http://127.0.0.1:7890',
        'NO_PROXY': 'localhost,127.0.0.1,::1,corp.example,.internal,*.lan',
        'no_proxy': 'localhost,127.0.0.1,::1,corp.example,.internal,*.lan',
      });
    });

    test('off clears what the child would inherit; none leaves it', () {
      final off = const ProxyRoute.direct(ProxySource.off).environment;
      expect(
        off.keys,
        containsAll(['HTTPS_PROXY', 'https_proxy', 'ALL_PROXY']),
      );
      expect(off.values.toSet(), {''});
      expect(const ProxyRoute.direct().environment, isEmpty);
      expect(
        const ProxyRoute.direct().findProxy(Uri.parse('https://x.example/')),
        'DIRECT',
      );
    });

    test('reads the environment, the lowercase first', () {
      final route = ProxyRoute.fromEnvironment(const {
        'https_proxy': 'http://127.0.0.1:7890',
        'HTTPS_PROXY': 'http://other:1',
        'no_proxy': 'corp.example, .lan',
      });
      expect(route.source, ProxySource.environment);
      expect(route.https, const ProxyServer('127.0.0.1', 7890));
      expect(route.http, isNull);
      expect(route.bypasses('git.corp.example'), isTrue);
      expect(
        ProxyRoute.fromEnvironment(const {'ALL_PROXY': 'http://p:8080'}).http,
        const ProxyServer('p', 8080),
      );
      expect(
        ProxyRoute.fromEnvironment(const {'ALL_PROXY': 'socks5://p:1080'})
            .direct,
        isTrue,
      );
    });
  });

  group('parseScutilProxy', () {
    test('reads the system proxy Clash sets on macOS', () {
      final route = parseScutilProxy(_scutilClash);
      expect(route.source, ProxySource.system);
      expect(route.http, const ProxyServer('127.0.0.1', 7897));
      expect(route.https, const ProxyServer('127.0.0.1', 7897));
      expect(route.bypassSimpleHostnames, isTrue);
      expect(route.bypasses('printer.local'), isTrue);
      expect(route.bypasses('timestamp.apple.com'), isTrue);
      expect(route.bypasses('api.anthropic.com'), isFalse);
      // A range only macOS reads stays out of NO_PROXY.
      expect(route.noProxy, isNot(contains('192.168')));
    });

    test('is direct when no HTTP proxy is enabled', () {
      expect(
        parseScutilProxy('<dictionary> {\n  FTPPassive : 1\n}\n').direct,
        isTrue,
      );
      final pac = parseScutilProxy('''
<dictionary> {
  HTTPEnable : 0
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  ProxyAutoConfigEnable : 1
  ProxyAutoConfigURLString : http://127.0.0.1:7890/pac
}
''');
      expect(pac.direct, isTrue);
      expect(pac.autoConfig, isTrue);
    });
  });

  group('parseWindowsInternetSettings', () {
    test('reads the system proxy Clash sets on Windows', () {
      final route = parseWindowsInternetSettings(
        _regClash.replaceAll('\n', '\r\n'),
      );
      expect(route.source, ProxySource.system);
      expect(route.https, const ProxyServer('127.0.0.1', 7890));
      expect(route.http, const ProxyServer('127.0.0.1', 7890));
      expect(route.bypassSimpleHostnames, isTrue);
      expect(route.bypasses('192.168.1.2'), isTrue);
      expect(route.bypasses('nas.lan'), isTrue);
      expect(route.bypasses('api.anthropic.com'), isFalse);
      expect(route.noProxy, 'localhost,127.0.0.1,::1,*.lan');
    });

    test('takes a proxy a protocol each', () {
      final route = parseWindowsInternetSettings('''
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    http=127.0.0.1:8080;https=127.0.0.1:8443;socks=127.0.0.1:1080
''');
      expect(route.http, const ProxyServer('127.0.0.1', 8080));
      expect(route.https, const ProxyServer('127.0.0.1', 8443));
      expect(
        parseWindowsInternetSettings('''
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    socks=127.0.0.1:1080
''').direct,
        isTrue,
      );
    });

    test('is direct while the proxy is turned off', () {
      final route = parseWindowsInternetSettings(
        _regClash.replaceFirst(
          'ProxyEnable    REG_DWORD    0x1',
          'ProxyEnable    REG_DWORD    0x0',
        ),
      );
      expect(route.direct, isTrue);
      final pac = parseWindowsInternetSettings('''
    ProxyEnable    REG_DWORD    0x0
    AutoConfigURL    REG_SZ    http://127.0.0.1:33331/pac
''');
      expect(pac.autoConfig, isTrue);
    });
  });
}
