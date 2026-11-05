// The extensions' parts: the Extensions view (Themes and Language
// Servers, as tabs), a theme extension's page and its tab among the
// editors'; built again as the ExtensionsViewService changes.

import 'package:flutter/widgets.dart';

import '../../../extensions/ui/extension_detail.dart';
import '../../../extensions/ui/extensions_view.dart';
import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/codicons.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/islands.dart';
import '../../extensions/ide_extensions_view.dart';
import '../../ide_tab_bar.dart';
import '../../services/extensions_view.dart';
import '../../services/language.dart';
import '../../tab_strip_scroll.dart';

/// The Extensions view: Themes and Language Servers, as tabs (the
/// language servers alone without theme extensions).
class ExtensionsViewPart extends StatelessWidget {
  const ExtensionsViewPart({
    super.key,
    required this.service,
    required this.language,
    required this.islands,
  });

  final ExtensionsViewService service;
  final LanguageService language;

  /// Whether the workbench is islands (see IdeWorkbench.islands).
  final bool islands;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final themes = service.themes;
      final tab = service.tab;
      final l10n = context.l10n;
      // On the side bar's card, as the other views are; not islands, under
      // the tabs, on the editor's color as the tab in front is.
      final background = themes == null || islands
          ? null
          : themeColors['editor.background'];
      final body = switch (tab) {
        ExtensionsTab.themes => ExtensionsView(
          model: themes!.model,
          onOpen: service.openPage,
          onInstallFromVsix: service.installFromVsix,
          onError: service.reportMessage,
          background: background,
        ),
        ExtensionsTab.languageServers => IdeExtensionsView(
          session: service.session,
          recommended: language.recommendedServers(),
          onInstalled: language.startServer,
          onError: service.host.report,
          background: background,
        ),
      };
      if (themes == null) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExtensionsTabs(
            tabs: [
              (ExtensionsTab.themes, Codicons.symbolColor, l10n.extsTabThemes),
              (
                ExtensionsTab.languageServers,
                Codicons.extensions,
                l10n.extsTabLanguageServers,
              ),
            ],
            selected: tab,
            onSelect: (value) => service.tab = value,
            islands: islands,
          ),
          Expanded(child: body),
        ],
      );
    },
  );
}

/// The extension page's tab, after the files'.
class ExtensionPageTab extends StatelessWidget {
  const ExtensionPageTab({super.key, required this.service});

  final ExtensionsViewService service;

  @override
  Widget build(BuildContext context) {
    final entry = service.page!;
    final l10n = context.l10n;
    final key = entry.key;
    final installed = service.themes!.model.installed
        ?.where((extension) => extension.key == key)
        .firstOrNull;
    final title = l10n.extsPageTitle(installed?.manifest.label ?? entry.label);
    final shown = service.pageShown;
    return IdeEditorTab(
      key: ValueKey(key),
      icon: const Icon(Codicons.extensions),
      label: title,
      active: shown,
      closeTooltip: shown
          ? KeybindingService.instance.titleWithKeybinding(
              l10n.tabCloseNamed(title),
              'workbench.action.closeActiveEditor',
            )
          : l10n.tabCloseNamed(title),
      onSelect: service.showPage,
      onClose: service.closePage,
    );
  }
}

/// A theme extension's page, in the editors' place while its tab is the
/// one in front.
class ExtensionPageView extends StatelessWidget {
  const ExtensionPageView({super.key, required this.service});

  final ExtensionsViewService service;

  @override
  Widget build(BuildContext context) {
    final entry = service.page!;
    return ColoredBox(
      color: themeColors['editor.background'],
      child: ExtensionDetailPage(
        key: ValueKey(entry.key),
        model: service.themes!.model,
        id: entry.id,
        onError: service.reportMessage,
      ),
    );
  }
}

/// The Extensions view's header: its [tabs] as the editor's, scrolling
/// when the view is too narrow for them.
class _ExtensionsTabs extends StatefulWidget {
  const _ExtensionsTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.islands,
  });

  /// Segments on the side bar's card, rather than an editor's tabs.
  final bool islands;

  final List<(ExtensionsTab, IconData, String)> tabs;
  final ExtensionsTab selected;
  final ValueChanged<ExtensionsTab> onSelect;

  @override
  State<_ExtensionsTabs> createState() => _ExtensionsTabsState();
}

class _ExtensionsTabsState extends State<_ExtensionsTabs> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // A segmented control, as the other views' on a card have (Commit and
  // Stash): not an editor's tabs, which are a strip of their own. Not
  // islands, those.
  @override
  Widget build(BuildContext context) =>
      widget.islands ? _segments(context) : _tabs();

  Widget _tabs() => IdeTabStrip(
    child: TabStripScroll(
      controller: _scroll,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (value, icon, label) in widget.tabs)
            IdeEditorTab(
              key: ValueKey(value),
              icon: Icon(icon),
              label: label,
              active: widget.selected == value,
              minWidth: 0,
              onSelect: () => widget.onSelect(value),
            ),
        ],
      ),
    ),
  );

  Widget _segments(BuildContext context) => Container(
    height: 10 + IslandSegment.height + 4,
    padding: const EdgeInsets.fromLTRB(Islands.inset, 10, Islands.inset, 4),
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, (value, icon, label)) in widget.tabs.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              _ExtensionsSegment(
                key: ValueKey(value),
                icon: icon,
                label: label,
                selected: widget.selected == value,
                onTap: () => widget.onSelect(value),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ExtensionsSegment extends StatefulWidget {
  const _ExtensionsSegment({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ExtensionsSegment> createState() => _ExtensionsSegmentState();
}

class _ExtensionsSegmentState extends State<_ExtensionsSegment> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground = widget.selected || _hover
        ? colors['panelTitle.activeForeground']
        : colors['panelTitle.inactiveForeground'];
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: IslandSegment(
          selected: widget.selected,
          onTap: widget.onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(fontSize: 12, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
