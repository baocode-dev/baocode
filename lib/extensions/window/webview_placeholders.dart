// The Webview degradation's model (the goal's 五.15): what the panel, view
// and custom editor shapes record about the Webviews they never show, so
// the UI can name them and say why nothing appears.

import 'package:flutter/foundation.dart';

/// One extension's Webview that BaoCode does not show (`WebviewKind`).
enum WebviewKind { panel, view, customEditor }

/// A Webview an extension asked for and BaoCode cannot show: kept for the
/// placeholder the workbench shows in its place and the line the Output
/// panel's "Extension Host" channel gets.
final class WebviewPlaceholder {
  WebviewPlaceholder({
    required this.handle,
    required this.kind,
    required this.extension,
    required this.viewType,
    required this.title,
  });

  /// The extension host's handle, or the view type for a view.
  final String handle;
  final WebviewKind kind;

  /// The extension that asked (`IExtensionDescription`'s fields).
  final Map<String, Object?> extension;

  /// The panel's or provider's `viewType`.
  final String viewType;

  /// Its title, as the extension set it.
  String title;

  /// It was shown again after being hidden.
  bool revealed = false;

  String get extensionId => switch (extension['identifier']) {
    final Map<Object?, Object?> id => '${id['value']}',
    _ => '${extension['publisher']}.${extension['name']}',
  };

  String get extensionName => '${extension['displayName'] ?? extensionId}';

  /// The line the Output panel gets: what could not be shown, and why.
  String get description =>
      'The $extensionName extension\'s ${switch (kind) {
        WebviewKind.panel => 'panel',
        WebviewKind.view => 'view',
        WebviewKind.customEditor => 'editor',
      }} "$title" ($viewType) needs a Webview, which BaoCode does not '
      'support.';
}

/// Every Webview an extension asked for in a session.
final class ExtensionWebviewPlaceholders extends ChangeNotifier {
  final Map<String, WebviewPlaceholder> _placeholders = {};

  /// The lines the Output panel's "Extension Host" channel gets, in
  /// order: one per Webview an extension asked for.
  final List<String> logLines = [];

  /// Adds [line] for the Output panel.
  void logLine(String line) {
    logLines.add(line);
    notifyListeners();
  }

  /// The HTML each webview was given, by handle (never rendered).
  final Map<String, String> html = {};

  /// The content options each webview was given.
  final Map<String, Map<String, Object?>> options = {};

  /// The title an extension set on a webview or a view.
  final Map<String, String?> title = {};

  /// The description a view was given.
  final Map<String, String?> description = {};

  /// The badge a view was given.
  final Map<String, Map<String, Object?>> badge = {};

  /// The icon a panel was given.
  final Map<String, Map<String, Object?>> icon = {};

  /// The placeholders, most recent first.
  List<WebviewPlaceholder> get placeholders =>
      _placeholders.values.toList().reversed.toList();

  /// The panels among them.
  List<WebviewPlaceholder> get panels => _ofKind(WebviewKind.panel);

  /// The views among them.
  List<WebviewPlaceholder> get views => _ofKind(WebviewKind.view);

  /// The custom editors among them.
  List<WebviewPlaceholder> get customEditors =>
      _ofKind(WebviewKind.customEditor);

  List<WebviewPlaceholder> _ofKind(WebviewKind kind) => [
    for (final placeholder in placeholders)
      if (placeholder.kind == kind) placeholder,
  ];

  WebviewPlaceholder? placeholder(String handle) => _placeholders[handle];

  WebviewPlaceholder? viewOf(String viewType) =>
      _placeholders['view:$viewType'];

  /// A panel was created (`$createWebviewPanel`).
  WebviewPlaceholder showPanel({
    required String handle,
    required Map<String, Object?> extension,
    required String viewType,
    required String title,
  }) => _add(
    WebviewPlaceholder(
      handle: handle,
      kind: WebviewKind.panel,
      extension: extension,
      viewType: viewType,
      title: title,
    ),
  );

  /// A view provider registered (`$registerWebviewViewProvider`).
  WebviewPlaceholder showView({
    required String viewType,
    required Map<String, Object?> extension,
    required String title,
  }) => _add(
    WebviewPlaceholder(
      handle: 'view:$viewType',
      kind: WebviewKind.view,
      extension: extension,
      viewType: viewType,
      title: title,
    ),
  );

  /// A custom editor provider registered
  /// (`$registerCustomEditorProvider`).
  WebviewPlaceholder showCustomEditor({
    required String viewType,
    required Map<String, Object?> extension,
  }) => _add(
    WebviewPlaceholder(
      handle: 'editor:$viewType',
      kind: WebviewKind.customEditor,
      extension: extension,
      viewType: viewType,
      title: viewType,
    ),
  );

  WebviewPlaceholder _add(WebviewPlaceholder placeholder) {
    _placeholders[placeholder.handle] = placeholder;
    notifyListeners();
    return placeholder;
  }

  /// It was shown again (`$reveal`, `$show`): the placeholder notes it,
  /// where upstream would bring the view forward.
  void reveal(String handle) {
    final placeholder = _placeholders[handle];
    if (placeholder == null) return;
    placeholder.revealed = true;
    notifyListeners();
  }

  void remove(String handle) {
    if (_placeholders.remove(handle) == null) return;
    html.remove(handle);
    options.remove(handle);
    title.remove(handle);
    icon.remove(handle);
    notifyListeners();
  }

  /// Forgets everything (the session ended).
  void clear() {
    _placeholders.clear();
    logLines.clear();
    html.clear();
    options.clear();
    title.clear();
    description.clear();
    badge.clear();
    icon.clear();
    notifyListeners();
  }
}
