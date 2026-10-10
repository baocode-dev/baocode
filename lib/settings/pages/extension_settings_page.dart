// The settings dialog's Extension Settings page: VS Code's settings editor
// for what extensions contribute (and VS Code's own settings they read),
// generated from the settings' JSON schemas.
//
// Ported, at a smaller scale, from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5
// (1.135.0): src/vs/workbench/contrib/preferences/browser/settingsEditor2.ts
// (search, User/Workspace targets, `@lang:` writing into `[lang]`, a link to
// a setting searching for it) and settingsTree.ts (a setting's title
// `Category: Label`, markdown descriptions with `#setting.id#` links, the
// modified indicator, "Also modified in", the gear menu's Reset Setting /
// Copy Setting ID / Copy Setting as JSON, "Edit in settings.json" for what
// has no control). The settings' logic is in
// lib/extensions/configuration/ui/setting_entries.dart.
//
// Deviations:
// - No table of contents (the dialog's own list is at the left); a
//   dropdown picks extensions' settings, VS Code's or both.
// - A link to a setting searches for it (`@id:`) rather than scrolling to it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../../chat/widgets/markdown_view.dart';
import '../../extensions/configuration/configuration_model.dart';
import '../../extensions/configuration/configuration_registry.dart';
import '../../extensions/configuration/configuration_service.dart';
import '../../extensions/configuration/ui/setting_entries.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart' show openExternal;
import 'extension_setting_controls.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// The settings file a page edits.
enum ExtensionSettingsTarget { user, workspace }

/// What the page shows and edits: the registered settings, the user's
/// settings file and the workspace's.
final class ExtensionSettingsSource {
  const ExtensionSettingsSource({
    required this.registry,
    required this.user,
    this.workspace,
    this.changes,
    this.extensionNames = const {},
    this.openSettingsJson,
  });

  final ConfigurationRegistry registry;
  final SettingsFile user;
  final SettingsFile? workspace;

  /// Notifies when [registry] changes (extensions installed or removed),
  /// a [ConfigurationService], say.
  final Listenable? changes;

  /// Extensions' display names, by id.
  final Map<String, String> extensionNames;

  /// Opens a target's settings.json at a setting.
  final void Function(ExtensionSettingsTarget target, String key)?
  openSettingsJson;
}

/// Gives the Extension Settings page its [source], for the dialog's page
/// builder to show it without knowing it.
class ExtensionSettingsScope extends InheritedWidget {
  const ExtensionSettingsScope({
    super.key,
    required this.source,
    required super.child,
  });

  final ExtensionSettingsSource source;

  static ExtensionSettingsSource? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ExtensionSettingsScope>()
      ?.source;

  @override
  bool updateShouldNotify(ExtensionSettingsScope oldWidget) =>
      source != oldWidget.source;
}

/// Which settings the page lists.
enum ExtensionSettingsFilter { extensions, core, all }

class ExtensionSettingsPage extends StatefulWidget {
  /// [source]: what [ExtensionSettingsScope] gives when null.
  const ExtensionSettingsPage({
    super.key,
    this.source,
    this.initialQuery = '',
    this.initialFilter,
  });

  final ExtensionSettingsSource? source;
  final String initialQuery;

  /// Extensions' settings when there are, all otherwise, when null.
  final ExtensionSettingsFilter? initialFilter;

  @override
  State<ExtensionSettingsPage> createState() => ExtensionSettingsPageState();
}

class ExtensionSettingsPageState extends State<ExtensionSettingsPage> {
  late final _search = TextEditingController(text: widget.initialQuery);
  final _scroll = ScrollController();
  ExtensionSettingsTarget _target = ExtensionSettingsTarget.user;
  ExtensionSettingsFilter? _filter;
  Timer? _debounce;
  late String _query = widget.initialQuery;

  /// Markdown parsed, by text.
  final _parsed = <String, List<md.Node>>{};
  final _recognizers = <GestureRecognizer>[];

  ExtensionSettingsSource? get _source =>
      widget.source ?? ExtensionSettingsScope.maybeOf(context);

  /// Shows [key]'s setting (a `#setting.id#` link): searches for it.
  void reveal(String key) {
    _search.text = '@id:$key';
    _setQuery(_search.text);
  }

  void _setQuery(String text) {
    _debounce?.cancel();
    setState(() => _query = text);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = _source;
    if (source == null) {
      return SettingsPage(
        title: l10n.extensionSettingsSection,
        description: l10n.extensionSettingsUnavailable,
        children: const [],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        source.user,
        ?source.workspace,
        ?source.changes,
      ]),
      builder: (context, _) => _build(context, source),
    );
  }

  Widget _build(BuildContext context, ExtensionSettingsSource source) {
    final l10n = context.l10n;
    _disposeRecognizers();
    final query = SettingsQuery.parse(_query);
    final target = source.workspace == null
        ? ExtensionSettingsTarget.user
        : _target;
    final workspace = target == ExtensionSettingsTarget.workspace;
    final values = SettingsTargetValues(
      registry: source.registry,
      file: workspace ? source.workspace! : source.user,
      lower: workspace ? [source.user] : const [],
      language: query.language,
    );
    final other = workspace ? source.user : source.workspace;
    final otherValues = other == null
        ? null
        : SettingsTargetValues(
            registry: source.registry,
            file: other,
            language: query.language,
          );
    final hasExtensions = source.registry.properties.values.any(
      (p) => p.extensionId != null,
    );
    final filter =
        _filter ??
        widget.initialFilter ??
        (hasExtensions
            ? ExtensionSettingsFilter.extensions
            : ExtensionSettingsFilter.all);
    final sections = buildSettingsSections(
      registry: source.registry,
      query: query,
      target: values,
      workspace: workspace,
      extensionNames: source.extensionNames,
      includeCore: filter != ExtensionSettingsFilter.extensions,
      includeExtensions: filter != ExtensionSettingsFilter.core,
    );
    final count = sections.fold(0, (sum, s) => sum + s.count);

    // The list, flattened for a lazy ListView.
    final items = <Widget>[];
    for (final section in sections) {
      items.add(
        _SectionHeader(
          key: ValueKey('section:${section.id}'),
          title: section.title.isEmpty
              ? l10n.extensionSettingsOther
              : section.title,
          detail: section.extensionId,
          first: items.isEmpty,
        ),
      );
      for (final sub in section.subsections) {
        if (sub.title case final title?) {
          items.add(
            _SubsectionHeader(
              key: ValueKey('sub:${section.id}:$title'),
              title: title,
            ),
          );
        }
        for (final entry in sub.settings) {
          items.add(
            _SettingRow(
              key: ValueKey(
                'setting:${entry.key}:${target.name}:${query.language}',
              ),
              entry: entry,
              values: values,
              isUser: !workspace,
              alsoModifiedIn:
                  otherValues != null && otherValues.isModified(entry.key)
                  ? (workspace
                        ? l10n.extensionSettingsUser
                        : l10n.extensionSettingsWorkspace)
                  : null,
              markdown: _markdown,
              onEditInJson: () => _editInJson(source, target, values, entry),
            ),
          );
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxWidth = 860.0;
        final side = ((constraints.maxWidth - maxWidth) / 2).clamp(
          SettingsPage.inset,
          double.infinity,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(side, 40, side, 0),
              child: _header(context, source, query, target, filter, count),
            ),
            Expanded(
              child: items.isEmpty
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(side + 4, 24, side, 0),
                      child: Text(
                        hasExtensions ||
                                filter != ExtensionSettingsFilter.extensions
                            ? l10n.extensionSettingsResults(0)
                            : l10n.extensionSettingsEmpty,
                        style: SettingsText.description,
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(side, 8, side, 40),
                      itemCount: items.length,
                      itemBuilder: (context, i) => items[i],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    ExtensionSettingsSource source,
    SettingsQuery query,
    ExtensionSettingsTarget target,
    ExtensionSettingsFilter filter,
    int count,
  ) {
    final l10n = context.l10n;
    final colors = themeColors;
    String filterLabel(ExtensionSettingsFilter f) => switch (f) {
      ExtensionSettingsFilter.extensions =>
        l10n.extensionSettingsSourceExtensions,
      ExtensionSettingsFilter.core => l10n.extensionSettingsSourceCore,
      ExtensionSettingsFilter.all => l10n.extensionSettingsSourceAll,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.extensionSettingsSection, style: SettingsText.title),
        const SizedBox(height: 4),
        Text(
          l10n.extensionSettingsDescription,
          style: SettingsText.description,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 30,
          child: Semantics(
            container: true,
            textField: true,
            label: l10n.extensionSettingsSearch,
            child: TextField(
              controller: _search,
              style: TextStyle(color: colors['input.foreground'], fontSize: 13),
              cursorColor: AppColors.text,
              onChanged: (text) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 150),
                  () => _setQuery(text),
                );
              },
              onSubmitted: _setQuery,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.extensionSettingsSearch,
                hintStyle: TextStyle(
                  color: colors['input.placeholderForeground'],
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Codicons.search,
                  size: 14,
                  color: AppColors.textFaint,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                suffixIcon: _query.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SettingIconButton(
                          icon: Codicons.clearAll,
                          tooltip: l10n.extensionSettingsCancel,
                          onTap: () {
                            _search.clear();
                            _setQuery('');
                          },
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 26),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: colors['input.background'],
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppColors.borderStrong),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors['focusBorder']),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Tab(
              label: l10n.extensionSettingsUser,
              selected: target == ExtensionSettingsTarget.user,
              onTap: () =>
                  setState(() => _target = ExtensionSettingsTarget.user),
            ),
            if (source.workspace != null)
              _Tab(
                label: l10n.extensionSettingsWorkspace,
                selected: target == ExtensionSettingsTarget.workspace,
                onTap: () =>
                    setState(() => _target = ExtensionSettingsTarget.workspace),
              ),
            const Spacer(),
            if (!query.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  l10n.extensionSettingsResults(count),
                  style: SettingsText.description,
                ),
              ),
            SettingsDropdown(
              current: filterLabel(filter),
              semanticLabel:
                  '${l10n.extensionSettingsShow}: ${filterLabel(filter)}',
              entries: () => [
                for (final f in ExtensionSettingsFilter.values)
                  IdeMenuAction(
                    filterLabel(f),
                    checked: f == filter,
                    onSelected: () => setState(() => _filter = f),
                  ),
              ],
            ),
          ],
        ),
        Container(height: 1, color: AppColors.border),
        if (query.language case final language?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.extensionSettingsLanguage(language),
              style: SettingsText.description,
            ),
          ),
      ],
    );
  }

  /// Markdown as the settings editor renders it: `#setting.id#` links
  /// searching for the setting, web links opening in the browser.
  Widget _markdown(String text, TextStyle style) {
    final nodes = _parsed[text] ??= MarkdownView.document().parse(
      fixSettingLinks(text),
    );
    return MarkdownBlocks(
      nodes: nodes,
      style: style,
      options: MarkdownOptions(
        gap: 4,
        link: (href) {
          if (href == null) return null;
          final GestureRecognizer recognizer;
          if (href.startsWith('#')) {
            recognizer = TapGestureRecognizer()
              ..onTap = () => reveal(href.substring(1));
          } else {
            final uri = Uri.tryParse(href.trim());
            if (uri == null ||
                !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
              return null;
            }
            recognizer = TapGestureRecognizer()
              ..onTap = () => unawaited(openExternal(uri.toString()));
          }
          _recognizers.add(recognizer);
          return recognizer;
        },
      ),
    );
  }

  /// "Edit in settings.json": the setting written to the file first when
  /// it is not set there (its value as shown), as upstream does.
  Future<void> _editInJson(
    ExtensionSettingsSource source,
    ExtensionSettingsTarget target,
    SettingsTargetValues values,
    SettingEntry entry,
  ) async {
    if (!values.isModified(entry.key)) {
      await values.file.write(
        values.pathOf(entry.key),
        values.valueOf(entry.key),
      );
    }
    source.openSettingsJson?.call(target, entry.key);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
            margin: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: selected
                      ? (colors.get('panelTitle.activeBorder') ??
                            AppColors.accent)
                      : Colors.transparent,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    this.detail,
    this.first = false,
  });

  final String title;
  final String? detail;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(4, first ? 12 : 28, 4, 6),
    child: Semantics(
      container: true,
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (detail case final detail?) ...[
            const SizedBox(width: 8),
            Text(detail, style: SettingsText.description),
          ],
        ],
      ),
    ),
  );
}

class _SubsectionHeader extends StatelessWidget {
  const _SubsectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
    child: Semantics(
      container: true,
      header: true,
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

typedef _Markdown = Widget Function(String text, TextStyle style);

/// One setting: `Category: Label`, the gear menu, its description, its
/// control; a bar at the left when it is modified in the target.
class _SettingRow extends StatefulWidget {
  const _SettingRow({
    super.key,
    required this.entry,
    required this.values,
    required this.isUser,
    required this.alsoModifiedIn,
    required this.markdown,
    required this.onEditInJson,
  });

  final SettingEntry entry;
  final SettingsTargetValues values;
  final bool isUser;
  final String? alsoModifiedIn;
  final _Markdown markdown;
  final VoidCallback onEditInJson;

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  bool _hover = false;

  SettingEntry get entry => widget.entry;
  String get key => entry.key;

  void _write(Object? value) =>
      unawaited(widget.values.write(key, value, isUser: widget.isUser));

  void _menu(BuildContext anchor, bool modified) {
    final l10n = context.l10n;
    final box = anchor.findRenderObject()! as RenderBox;
    unawaited(
      showIdeMenu(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        entries: [
          IdeMenuAction(
            l10n.extensionSettingsReset,
            enabled: modified,
            onSelected: () => unawaited(
              widget.values.file.write(widget.values.pathOf(key), null),
            ),
          ),
          const IdeMenuSeparator(),
          IdeMenuAction(
            l10n.extensionSettingsCopyId,
            onSelected: () =>
                unawaited(Clipboard.setData(ClipboardData(text: key))),
          ),
          IdeMenuAction(
            l10n.extensionSettingsCopyJson,
            onSelected: () {
              final json = const JsonEncoder.withIndent('  ')
                  .convert({key: widget.values.valueOf(key)});
              unawaited(
                Clipboard.setData(
                  ClipboardData(
                    text: json.substring(1, json.length - 1).trim(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final modified = widget.values.isModified(key);
    final value = widget.values.valueOf(key);
    final description = entry.description;
    final label = entry.title;
    Widget describe(({String text, bool markdown}) d, TextStyle style) =>
        d.markdown
        ? widget.markdown(d.text, style)
        : Text(d.text, style: style);

    final control = _control(context, value, label);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: _hover
              ? (themeColors.get('settings.rowHoverBackground') ??
                    AppColors.hover.withValues(alpha: 0.5))
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The modified indicator.
              Semantics(
                container: true,
                label: modified ? l10n.extensionSettingsModified : null,
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: modified
                      ? (themeColors.get('settings.modifiedItemIndicator') ??
                            AppColors.accent)
                      : Colors.transparent,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 6, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: key,
                              excludeFromSemantics: true,
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (entry.display.category.isNotEmpty)
                                      TextSpan(
                                        text: '${entry.display.category}: ',
                                      ),
                                    TextSpan(
                                      text: entry.display.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (widget.alsoModifiedIn case final where?)
                                      TextSpan(
                                        text:
                                            '   ${l10n.extensionSettingsAlsoModifiedIn(where)}',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                                style: SettingsText.label,
                              ),
                            ),
                          ),
                          Builder(
                            builder: (anchor) => SettingIconButton(
                              icon: Codicons.gear,
                              tooltip: l10n.extensionSettingsMoreActions,
                              onTap: () => _menu(anchor, modified),
                            ),
                          ),
                        ],
                      ),
                      if (entry.deprecation case final deprecation?) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2, right: 6),
                              child: Icon(
                                Codicons.warning,
                                size: 13,
                                color:
                                    themeColors.get(
                                      'editorWarning.foreground',
                                    ) ??
                                    settingsErrorColor,
                              ),
                            ),
                            Expanded(
                              child: describe(
                                deprecation,
                                SettingsText.description.copyWith(
                                  color: themeColors.get(
                                    'editorWarning.foreground',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (entry.control == SettingControl.boolean) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            control,
                            const SizedBox(width: 8),
                            Expanded(
                              child: describe(
                                description,
                                SettingsText.description,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        if (description.text.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          describe(description, SettingsText.description),
                        ],
                        const SizedBox(height: 8),
                        control,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _control(BuildContext context, Object? value, String label) {
    final l10n = context.l10n;
    final schema = entry.schema;
    switch (entry.control) {
      case SettingControl.boolean:
        return Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SettingCheckbox(
            value: value == true,
            label: label,
            onChanged: _write,
          ),
        );
      case SettingControl.enumeration:
        final options = (schema['enum']! as List).toList();
        final labels = (schema['enumItemLabels'] as List?) ?? const [];
        final markdownDescriptions =
            schema['markdownEnumDescriptions'] as List?;
        final descriptions =
            markdownDescriptions ??
            (schema['enumDescriptions'] as List?) ??
            const [];
        String labelOf(int i) => i < labels.length && labels[i] is String
            ? labels[i] as String
            : '${options[i]}';
        final index = options.indexWhere((o) => deepEquals(o, value));
        final current = index < 0 ? '${value ?? ''}' : labelOf(index);
        final chosen = index >= 0 && index < descriptions.length
            ? descriptions[index]
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsDropdown(
              current: current,
              semanticLabel: '$label: $current',
              entries: () => [
                for (var i = 0; i < options.length; i++)
                  IdeMenuAction(
                    labelOf(i),
                    checked: i == index,
                    onSelected: () => _write(options[i]),
                  ),
              ],
            ),
            if (chosen is String && chosen.isNotEmpty) ...[
              const SizedBox(height: 4),
              markdownDescriptions != null
                  ? widget.markdown(chosen, SettingsText.description)
                  : Text(chosen, style: SettingsText.description),
            ],
          ],
        );
      case SettingControl.string ||
          SettingControl.multilineString ||
          SettingControl.number ||
          SettingControl.integer:
        return SettingTextControl(
          value: value,
          schema: schema,
          control: entry.control,
          label: label,
          onCommit: _write,
        );
      case SettingControl.stringArray:
        return SettingStringListControl(
          value: [
            if (value is List)
              for (final item in value) '$item',
          ],
          schema: schema,
          onChanged: _write,
        );
      case SettingControl.booleanObject:
        final defaults = widget.values.defaultOf(key);
        return SettingBooleanObjectControl(
          value: value is Map ? value.cast<String, Object?>() : const {},
          defaults: defaults is Map
              ? defaults.cast<String, Object?>()
              : const {},
          onChanged: _write,
        );
      case SettingControl.complex:
        return Align(
          alignment: Alignment.centerLeft,
          child: SettingTextButton(
            label: l10n.extensionSettingsEditInJson,
            icon: Codicons.json,
            onTap: widget.onEditInJson,
          ),
        );
    }
  }
}
