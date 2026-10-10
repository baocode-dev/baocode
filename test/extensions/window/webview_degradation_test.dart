// The Webview notice: once per extension, named by the extension's display
// name. A panel, view or custom editor is sent its extension as a
// `WebviewExtensionDescription` (`{id, location}`), not the full
// description.

import 'package:baocode/extensions/window/webview_degradation.dart';
import 'package:baocode/extensions/window/webview_placeholders.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _webviewExtension(String id) => {
  'id': {'value': id, '_lower': id.toLowerCase()},
  'location': {'scheme': 'file', 'path': '/ext/$id'},
};

void main() {
  test('each extension of a Webview is told once, by its name', () {
    final notifications = IdeNotifications();
    final placeholders = ExtensionWebviewPlaceholders()
      ..nameOf = (id) => {'pub.one': 'One', 'pub.two': 'Two'}[id];
    final notices = ExtensionWebviewNotices(
      ExtensionWebviewUi(
        placeholders: placeholders,
        notifications: notifications,
      ),
    );

    notices.notice(_webviewExtension('pub.one'), 'first');
    notices.notice(_webviewExtension('pub.one'), 'again');
    notices.notice(_webviewExtension('pub.two'), 'second');

    expect(
      [for (final n in notifications.notifications) n.source],
      unorderedEquals(['One', 'Two']),
    );
    expect(notices.noticed('PUB.ONE'), isTrue);
    notifications.dispose();
  });
}
