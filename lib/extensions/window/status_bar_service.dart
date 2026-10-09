/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/statusBarExtensionPoint.ts
// (`ExtensionStatusBarItemService.setOrUpdateEntry`: the aria label, the
// two background colors that become an entry's kind, alignment and
// priority fixed at creation, the extension's hash as the secondary
// priority; `StatusBarItemsExtensionPoint`: `contributes.statusBarItems`),
// src/vs/workbench/browser/parts/statusbar/statusbarModel.ts (sorting by
// priority, hidden entries kept by id) and
// src/vs/workbench/services/statusbar/browser/statusbar.ts.
//
// Deviations: hidden entries are kept in a JsonStateStore (upstream:
// profile storage `workbench.statusbar.hidden`); no relative positions
// (`location`) or compact entries.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'extension_descriptions.dart';
import 'json_state_store.dart';

/// `StatusBarUpdateKind`.
enum StatusBarUpdateKind { didDefine, didUpdate }

/// `StatusbarEntryKind` for the two background colors extensions may use.
enum ExtensionStatusBarKind { standard, warning, error }

/// One extension's status bar entry (`IStatusbarEntry` with its place).
final class ExtensionStatusBarEntry {
  ExtensionStatusBarEntry({
    required this.entryId,
    required this.id,
    required this.extensionId,
    required this.name,
    required this.text,
    required this.tooltip,
    required this.hasTooltipProvider,
    required this.command,
    required this.color,
    required this.kind,
    required this.alignLeft,
    required this.priority,
    required this.secondaryPriority,
    required this.ariaLabel,
    required this.role,
  });

  /// The extension host's id of it (`<extension>.<id>` or a number).
  final String entryId;

  /// The id shared by its kind of entry (`statusId`), which hiding uses.
  final String id;
  final String? extensionId;
  final String name;
  final String text;

  /// A string, or an `IMarkdownString` (`{value, isTrusted, …}`).
  final Object? tooltip;

  /// Its tooltip comes from `ExtHostStatusBar.$provideTooltip`.
  final bool hasTooltipProvider;

  /// `ICommandDto`: `{id, title, arguments}`.
  final Map<String, Object?>? command;

  /// A CSS color string or a `ThemeColor` (`{id}`).
  final Object? color;
  final ExtensionStatusBarKind kind;
  final bool alignLeft;
  final num priority;
  final int secondaryPriority;
  final String ariaLabel;
  final String? role;

  /// The tooltip as plain text, or the Markdown's source.
  String? get tooltipText => switch (tooltip) {
    final String text => text,
    final Map<Object?, Object?> markdown => markdown['value'] as String?,
    _ => null,
  };

  bool get tooltipIsMarkdown => tooltip is Map;

  /// `ExtHostStatusBar`'s `StatusBarItemDto` of it.
  Map<String, Object?> toDto() => {
    'entryId': entryId,
    'alignLeft': alignLeft,
    'priority': priority,
    'name': name,
    'text': text,
    'tooltip': tooltipText,
    'command': command?['id'],
    'accessibilityInformation': {'label': ariaLabel, 'role': ?role},
  };
}

/// The extensions' status bar entries of a window, and which the user hid.
final class ExtensionStatusBarService extends ChangeNotifier {
  ExtensionStatusBarService({this.hiddenStore});

  /// Keeps the ids of hidden entries.
  final JsonStateStore? hiddenStore;

  static const _hiddenKey = 'workbench.statusbar.hidden';
  static const errorBackground = 'statusBarItem.errorBackground';
  static const warningBackground = 'statusBarItem.warningBackground';

  final Map<String, ExtensionStatusBarEntry> _entries = {};
  final Set<String> _static = {};
  Set<String>? _hidden;
  final _added = StreamController<ExtensionStatusBarEntry>.broadcast(
    sync: true,
  );

  /// Asks the extension host for an entry's tooltip
  /// (`ExtHostStatusBar.$provideTooltip`); set by the running session.
  Future<Object?> Function(String entryId)? tooltipProvider;

  /// Entries as they are added (`onDidChange` with `added`).
  Stream<ExtensionStatusBarEntry> get added => _added.stream;

  /// All entries, in no particular order.
  Iterable<ExtensionStatusBarEntry> get entries => _entries.values;

  ExtensionStatusBarEntry? entry(String entryId) => _entries[entryId];

  /// Reads which entries are hidden.
  Future<void> load() async {
    final store = hiddenStore;
    if (store == null) return;
    await store.load();
    _hidden = null;
    notifyListeners();
  }

  Set<String> get _hiddenIds => _hidden ??= {
    ...switch (hiddenStore?.getJson(_hiddenKey)) {
      final List<Object?> ids => ids.whereType<String>(),
      _ => const <String>[],
    },
  };

  /// Whether entries of [id] are hidden.
  bool isHidden(String id) => _hiddenIds.contains(id);

  /// Hides or shows the entries of [id] (the status bar's context menu).
  void setHidden(String id, bool hidden) {
    final ids = _hiddenIds;
    if (!(hidden ? ids.add(id) : ids.remove(id))) return;
    hiddenStore?.setJson(_hiddenKey, ids.toList()..sort());
    notifyListeners();
  }

  /// The entries shown on a side, as the status bar orders them: higher
  /// priorities first, then the extensions' hashes.
  List<ExtensionStatusBarEntry> visible({required bool left}) {
    final list = [
      for (final entry in _entries.values)
        if (entry.alignLeft == left && !isHidden(entry.id)) entry,
    ];
    final order = {for (final (i, e) in _entries.values.indexed) e: i};
    list.sort((a, b) {
      final primary = b.priority.compareTo(a.priority);
      if (primary != 0) return primary;
      final secondary = b.secondaryPriority.compareTo(a.secondaryPriority);
      if (secondary != 0) return secondary;
      return order[a]!.compareTo(order[b]!);
    });
    return list;
  }

  /// `setOrUpdateEntry`.
  StatusBarUpdateKind setOrUpdateEntry({
    required String entryId,
    required String id,
    required String? extensionId,
    required String name,
    required String text,
    required Object? tooltip,
    bool hasTooltipProvider = false,
    Map<String, Object?>? command,
    Object? color,
    Object? backgroundColor,
    required bool alignLeft,
    num? priority,
    Map<String, Object?>? accessibilityInformation,
  }) {
    String ariaLabel;
    String? role;
    if (accessibilityInformation != null) {
      ariaLabel = '${accessibilityInformation['label'] ?? ''}';
      role = accessibilityInformation['role'] as String?;
    } else {
      ariaLabel = codiconAriaLabel(text);
      final tooltipText = switch (tooltip) {
        final String text => text,
        final Map<Object?, Object?> markdown => markdown['value'] as String?,
        _ => null,
      };
      if (tooltipText != null) ariaLabel += ', $tooltipText';
    }
    var kind = ExtensionStatusBarKind.standard;
    final backgroundId = switch (backgroundColor) {
      final Map<Object?, Object?> theme => theme['id'],
      _ => null,
    };
    if (backgroundId == errorBackground || backgroundId == warningBackground) {
      kind = backgroundId == errorBackground
          ? ExtensionStatusBarKind.error
          : ExtensionStatusBarKind.warning;
      color = null;
    }
    final existing = _entries[entryId];
    final entry = ExtensionStatusBarEntry(
      entryId: entryId,
      id: id,
      extensionId: extensionId,
      name: name,
      text: text,
      tooltip: tooltip,
      hasTooltipProvider: hasTooltipProvider,
      command: command,
      color: color,
      kind: kind,
      // Alignment and priority are set once, at creation.
      alignLeft: existing?.alignLeft ?? alignLeft,
      priority: existing?.priority ?? priority ?? 0,
      secondaryPriority: extensionId == null ? 0 : stringHash(extensionId),
      ariaLabel: ariaLabel,
      role: role,
    );
    _entries[entryId] = entry;
    notifyListeners();
    if (existing == null) {
      _added.add(entry);
      return StatusBarUpdateKind.didDefine;
    }
    return StatusBarUpdateKind.didUpdate;
  }

  /// `unsetEntry`.
  void unsetEntry(String entryId) {
    if (_entries.remove(entryId) == null) return;
    _static.remove(entryId);
    notifyListeners();
  }

  /// `StatusBarItemsExtensionPoint`: the `contributes.statusBarItems` of
  /// [extensions] that enable the `contribStatusBarItems` proposal replace
  /// the ones before.
  void setContributions(Iterable<Map<String, Object?>> extensions) {
    for (final entryId in [..._static]) {
      unsetEntry(entryId);
    }
    for (final extension in extensions) {
      final proposals = extension['enabledApiProposals'];
      if (proposals is! List || !proposals.contains('contribStatusBarItems')) {
        continue;
      }
      final contributes = extension['contributes'];
      if (contributes is! Map) continue;
      final value = contributes['statusBarItems'];
      final candidates = value is List ? value : [value];
      final extensionId = extensionIdOf(extension);
      for (final candidate in candidates) {
        if (!_isStatusItem(candidate)) continue;
        final item = (candidate as Map).cast<String, Object?>();
        final fullId = '${extensionKey(extensionId)}.${item['id']}';
        final name = item['name'] as String? ?? extensionDisplayName(extension);
        final kind = setOrUpdateEntry(
          entryId: fullId,
          id: fullId,
          extensionId: extensionKey(extensionId),
          name: name,
          text: item['text']! as String,
          tooltip: item['tooltip'],
          command: switch (item['command']) {
            final String command => {'id': command, 'title': name},
            _ => null,
          },
          alignLeft: item['alignment'] == 'left',
          priority: item['priority'] as num?,
          accessibilityInformation: switch (item['accessibilityInformation']) {
            final Map<Object?, Object?> info => info.cast<String, Object?>(),
            _ => null,
          },
        );
        if (kind == StatusBarUpdateKind.didDefine) _static.add(fullId);
      }
    }
  }

  static bool _isStatusItem(Object? candidate) {
    if (candidate is! Map) return false;
    final id = candidate['id'];
    return id is String &&
        id.isNotEmpty &&
        candidate['name'] is String &&
        candidate['text'] is String &&
        (candidate['alignment'] == 'left' ||
            candidate['alignment'] == 'right') &&
        (candidate['command'] == null || candidate['command'] is String) &&
        (candidate['tooltip'] == null || candidate['tooltip'] is String) &&
        (candidate['priority'] == null || candidate['priority'] is num);
  }

  @override
  void dispose() {
    unawaited(_added.close());
    super.dispose();
  }
}

/// `getCodiconAriaLabel`: `$(name)` icons as their names, dashes as
/// spaces, `~modifiers` dropped.
String codiconAriaLabel(String text) => text
    .replaceAllMapped(
      RegExp(r'\$\(([a-z0-9-]+)(~[a-z]+)?\)'),
      (match) => match[1]!.replaceAll('-', ' '),
    )
    .trim();

/// `hash` (base/common/hash.ts) of a string: `stringHash(s, 0)`, a 32-bit
/// signed number like JavaScript's `| 0`.
int stringHash(String s) {
  var hash = numberHash(149417, 0);
  for (var i = 0; i < s.length; i++) {
    hash = numberHash(s.codeUnitAt(i), hash);
  }
  return hash;
}

/// `numberHash`: `(((initialHashVal << 5) - initialHashVal) + val) | 0`.
int numberHash(int val, int initialHashVal) =>
    (((initialHashVal << 5) - initialHashVal) + val).toSigned(32);
