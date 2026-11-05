// The workbench's extensions (upstream `IExtensionsWorkbenchService` with
// the extension editor): the Extensions view's tab (the color and file
// icon theme extensions of lib/extensions/, and the language servers), a
// theme extension's page among the editors', .vsix files installed or
// dropped on the window, and the file icon theme picked.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../extensions/theme_extensions.dart';
import '../../extensions/ui/extensions_model.dart';
import '../../extensions/ui/vsix_drop.dart';
import '../../l10n/l10n.dart';
import '../../theme/file_icon_theme.dart';
import '../../workspace/window_controls.dart';
import '../extensions/ide_extensions.dart';
import '../extensions/ide_extensions_view.dart';
import '../ide_quick_input.dart';
import '../workbench/contributions.dart';
import '../workbench/environment.dart';
import 'quick_input.dart';

/// What the Extensions view shows.
enum ExtensionsTab { themes, languageServers }

class ExtensionsViewService extends ChangeNotifier {
  ExtensionsViewService({
    required this.host,
    required this.environment,
    required this.quickInput,
    required this._themes,
    required this._languageServers,
    required this._notify,
  });

  final WorkbenchHost host;
  final WorkbenchEnvironment environment;
  final QuickInputService quickInput;

  /// The theme extensions, where the app has them; the language servers'.
  final ThemeExtensions? Function() _themes;
  final IdeExtensions? Function() _languageServers;
  ThemeExtensions? get themes => _themes();

  /// [message] told as an error notification.
  final ValueChanged<String> _notify;
  void reportMessage(String message) => _notify(message);

  /// The view's tab: the language servers alone without theme extensions.
  ExtensionsTab get tab =>
      themes == null ? ExtensionsTab.languageServers : _tab;
  ExtensionsTab _tab = ExtensionsTab.themes;
  set tab(ExtensionsTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// The language servers' listing and search, made when it first shows.
  IdeExtensionsSession get session => _session ??= IdeExtensionsSession(
    _languageServers() ?? IdeLanguageServerExtensions(),
  );
  IdeExtensionsSession? _session;

  /// The theme extension whose page has a tab among the editors', as
  /// VS Code's extension editor; and whether its tab is the one in front
  /// (another selected, it stays).
  ExtensionEntry? get page => themes == null ? null : _page;
  ExtensionEntry? _page;
  bool get pageShown => page != null && _pageShown;
  bool _pageShown = false;

  /// Opens [entry]'s page as an editor, in front of the one open.
  void openPage(ExtensionEntry entry) {
    _page = entry;
    _pageShown = true;
    notifyListeners();
  }

  /// Its tab selected again.
  void showPage() {
    _pageShown = true;
    notifyListeners();
  }

  void closePage() {
    _page = null;
    _pageShown = false;
    notifyListeners();
  }

  /// An editor brought to the front: the page goes behind it.
  void editorShown() {
    if (!_pageShown) return;
    _pageShown = false;
    notifyListeners();
  }

  /// Install from VSIX...: one picked in the open panel.
  Future<void> installFromVsix() async {
    final themes = this.themes;
    if (themes == null) return;
    final paths = await WindowControls.pickOpenFiles(multiple: false);
    final context = host.context;
    if (paths.isEmpty || context == null || !context.mounted) return;
    await showVsixInstallSheet(
      context,
      paths.first,
      backend: themes,
      locale: themes.locale,
    );
  }

  /// Takes the .vsix files among [paths] dropped on the window: false when
  /// there are none (they open as files do).
  bool drop(List<String> paths) {
    final themes = this.themes;
    final context = host.context;
    if (themes == null || context == null || !paths.any(isVsixDrop)) {
      return false;
    }
    unawaited(
      handleExtensionDrop(
        context,
        paths,
        backend: themes,
        locale: themes.locale,
      ),
    );
    return true;
  }

  /// Preferences: File Icon Theme: the bundled theme and the extensions';
  /// moving through them previews each, accepting keeps it in
  /// settings.json (`workbench.iconTheme`).
  void selectIconTheme() {
    final context = host.context;
    if (context == null) return;
    final service = FileIconThemeService.instance;
    final current = service.setting;
    final l10n = context.l10n;
    final ids = Map<IdeQuickPickItem, String?>.identity();
    IdeQuickPickItem item(String label, String? id, {String? description}) {
      final entry = IdeQuickPickItem(label: label, description: description);
      ids[entry] = id;
      return entry;
    }

    final bundled = item(
      'Material Icon Theme',
      null,
      description: l10n.themeIconThemeBuiltIn,
    );
    final themes = service.themes
      ..sort((a, b) => ideLocaleCompare(a.label, b.label));
    final items = [
      bundled,
      for (final theme in themes) item(theme.label, theme.id),
    ];
    var accepted = false;
    quickInput.showModel(
      IdeQuickPick(
        items: items,
        placeholder: l10n.themeSelectIconThemePlaceholder,
        activeItems: [
          items.firstWhere(
            (candidate) => ids[candidate] == current,
            orElse: () => bundled,
          ),
        ],
        sortByLabel: false,
        onDidChangeActive: (item) {
          if (item != null) unawaited(service.select(ids[item]));
        },
        onDidAccept: (item) {
          if (item == null) return;
          accepted = true;
          final id = ids[item];
          unawaited(service.select(id));
          unawaited(
            environment.settings?.edit(
              const ['workbench.iconTheme'],
              id,
              remove: id == null,
            ),
          );
        },
        onDidHide: () {
          if (!accepted) unawaited(service.select(current));
        },
      ),
    );
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }
}
