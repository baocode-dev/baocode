Future<void> sendPluginSlotHttp(
  Uri url, {
  String method = 'POST',
  Map<String, String> headers = const {},
  String? body,
}) => throw UnsupportedError('HTTP plugin actions are not supported on web');
