import 'dart:convert';
import 'dart:io';

Future<void> sendPluginSlotHttp(
  Uri url, {
  String method = 'POST',
  Map<String, String> headers = const {},
  String? body,
}) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await c.openUrl(method.toUpperCase(), url);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType ??= ContentType.json;
      req.add(utf8.encode(body));
    }
    await (await req.close().timeout(const Duration(seconds: 5))).drain<void>();
  } finally {
    c.close(force: true);
  }
}
